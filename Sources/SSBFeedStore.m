#import "SSBFeedStore.h"
#import "SSBEnvironment.h"
#import "SSBFeedCodecRegistry.h"
#import "SSBQueryEngine.h"
#import "SSBTangle.h"
#import "SSBBamboo.h"
#import <sqlite3.h>
#import <string.h>
#import "SSBLogCompat.h"

static os_log_t ssb_feedstore_log;

static NSString *const SSBFeedStoreErrorDomain = @"SSBFeedStore";
static const NSInteger kCurrentSchemaVersion = 4;

@interface SSBFeedStore () {
    sqlite3 *_db;
}
@property (nonatomic, SSB_STRONG_DISPATCH) dispatch_queue_t dbQueue;

- (BOOL)_appendMessageToTable:(const char *)tableName message:(SSBMessage *)message error:(NSError **)error;
- (void)_updateFeedStateForAuthor:(NSString *)author sequence:(NSInteger)sequence key:(NSString *)key feedFormat:(SSBBFEFeedFormat)feedFormat;
- (void)_drainQuarantineForKey:(NSString *)satisfiedKey author:(NSString *)author;
- (SSBMessage *)_getQuarantinedMessageByKey:(NSString *)key;
- (SSBMessage *)_getQuarantinedMessageForAuthor:(NSString *)author sequence:(NSInteger)sequence;
- (void)_removeMessageFromQuarantine:(SSBMessage *)message;
- (SSBMessage *)_messageFromStatement:(sqlite3_stmt *)stmt;
- (nullable SSBFeedState *)_feedStateForAuthor:(NSString *)author;
- (BOOL)_hasMessageWithKey:(NSString *)key;
- (void)_updateQuarantineDependenciesForMessage:(SSBMessage *)message missingDeps:(NSArray<NSString *> *)missingDeps;
- (NSArray<NSString *> *)_getMissingDependenciesForMessage:(SSBMessage *)message;
- (void)_tryReleaseQuarantinedMessageWithKey:(NSString *)msgKey;
- (void)_setDisplayName:(nullable NSString *)name image:(nullable NSString *)image forAuthor:(NSString *)author;
- (void)wipeDatabase;
- (void)createSchema;
- (void)migrateSchema;
- (BOOL)columnExists:(NSString *)column inTable:(NSString *)table;

@end

@implementation SSBFeedStore

+ (void)initialize {
    if (self == [SSBFeedStore class]) {
        ssb_feedstore_log = os_log_create("com.scuttlebutt.room", "FeedStore");
    }
}

+ (instancetype)sharedStore {
    static SSBFeedStore *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        NSString *dir = [appSupport stringByAppendingPathComponent:@"ScuttleKit"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *dbPath = [dir stringByAppendingPathComponent:@"feeds.db"];
        shared = [[SSBFeedStore alloc] initWithPath:dbPath];
    });
    return shared;
}

- (instancetype)initWithPath:(NSString *)dbPath {
    self = [super init];
    if (self) {
        _dbQueue = dispatch_queue_create("com.scuttlebutt.feedstore.db", DISPATCH_QUEUE_SERIAL);

        int rc = sqlite3_open(dbPath.UTF8String, &_db);
        if (rc != SQLITE_OK) {
            os_log_error(ssb_feedstore_log, "Failed to open database at %{public}@: %{public}s", dbPath, sqlite3_errmsg(_db));
            return nil;
        }

        os_log_info(ssb_feedstore_log, "Opened feed store at %{public}@", dbPath);
        [self createSchema];
        [self migrateSchema];
    }
    return self;
}

- (NSInteger)currentSchemaVersion {
    int version = 0;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, "PRAGMA user_version", -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            version = sqlite3_column_int(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }
    return (NSInteger)version;
}

- (BOOL)columnExists:(NSString *)column inTable:(NSString *)table {
    char sql[256];
    snprintf(sql, sizeof(sql), "PRAGMA table_info(%s)", [table UTF8String]);
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return NO;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *colName = (const char *)sqlite3_column_text(stmt, 1);
        if (colName && strcmp(colName, [column UTF8String]) == 0) {
            sqlite3_finalize(stmt);
            return YES;
        }
    }
    sqlite3_finalize(stmt);
    return NO;
}

- (void)setSchemaVersion:(NSInteger)version {
    char sql[64];
    snprintf(sql, sizeof(sql), "PRAGMA user_version = %ld", (long)version);
    sqlite3_exec(_db, sql, NULL, NULL, NULL);
}

- (void)migrateSchema {
    NSInteger version = [self currentSchemaVersion];

    os_log_info(ssb_feedstore_log, "Schema version: %ld (target: %ld)", (long)version, (long)kCurrentSchemaVersion);

    if (version < 2 && ![self columnExists:@"is_private" inTable:@"messages"]) {
        os_log_info(ssb_feedstore_log, "Migrating to version 2: adding is_private column");
        const char *sql = "ALTER TABLE messages ADD COLUMN is_private INTEGER NOT NULL DEFAULT 0";
        char *errMsg = NULL;
        if (sqlite3_exec(_db, sql, NULL, NULL, &errMsg) != SQLITE_OK) {
            os_log_error(ssb_feedstore_log, "v2 migration failed: %s", errMsg);
            sqlite3_free(errMsg);
        }
    }

    if (version < 3 && ![self columnExists:@"blocking" inTable:@"contacts"]) {
        os_log_info(ssb_feedstore_log, "Migrating to version 3: adding blocking column to contacts");
        const char *sql = "ALTER TABLE contacts ADD COLUMN blocking INTEGER NOT NULL DEFAULT 0";
        char *errMsg = NULL;
        if (sqlite3_exec(_db, sql, NULL, NULL, &errMsg) != SQLITE_OK) {
            os_log_error(ssb_feedstore_log, "v3 migration failed: %s", errMsg);
            sqlite3_free(errMsg);
        }
    }

    if (version < 4) {
        struct { NSString *table; NSString *column; } cols[] = {
            @"messages", @"feed_format",
            @"feed_state", @"feed_format",
            @"quarantine", @"feed_format",
        };
        for (size_t i = 0; i < sizeof(cols)/sizeof(cols[0]); i++) {
            if ([self columnExists:cols[i].column inTable:cols[i].table]) continue;
            os_log_info(ssb_feedstore_log, "Migrating to version 4: adding feed_format column to %@", cols[i].table);
            char sql[256];
            snprintf(sql, sizeof(sql), "ALTER TABLE %s ADD COLUMN feed_format INTEGER NOT NULL DEFAULT 0",
                     [cols[i].table UTF8String]);
            char *errMsg = NULL;
            if (sqlite3_exec(_db, sql, NULL, NULL, &errMsg) != SQLITE_OK) {
                os_log_error(ssb_feedstore_log, "v4 migration failed: %s", errMsg);
                sqlite3_free(errMsg);
            }
        }
    }

    if (version < kCurrentSchemaVersion) {
        [self setSchemaVersion:kCurrentSchemaVersion];
    }
}

- (void)dealloc {
    if (_db) {
        sqlite3_close(_db);
        _db = NULL;
    }
}

- (void)createSchema {
    const char *sql =
        "CREATE TABLE IF NOT EXISTS messages ("
        "    author TEXT NOT NULL,"
        "    sequence INTEGER NOT NULL,"
        "    key TEXT NOT NULL UNIQUE,"
        "    previous_key TEXT,"
        "    claimed_timestamp INTEGER NOT NULL,"
        "    received_at INTEGER NOT NULL,"
        "    is_private INTEGER NOT NULL DEFAULT 0,"
        "    content_type TEXT,"
        "    value_json BLOB NOT NULL,"
        "    content_json TEXT,"
        "    feed_format INTEGER NOT NULL DEFAULT 0,"
        "    PRIMARY KEY (author, sequence)"
        ");"
        "CREATE TABLE IF NOT EXISTS feed_state ("
        "    author TEXT PRIMARY KEY,"
        "    max_sequence INTEGER NOT NULL,"
        "    max_key TEXT NOT NULL,"
        "    feed_format INTEGER NOT NULL DEFAULT 0"
        ");"
        "CREATE TABLE IF NOT EXISTS contacts ("
        "    target_author TEXT PRIMARY KEY,"
        "    following INTEGER NOT NULL,"
        "    blocking INTEGER NOT NULL DEFAULT 0,"
        "    sequence INTEGER NOT NULL"
        ");"
        "CREATE TABLE IF NOT EXISTS profiles ("
        "    author TEXT PRIMARY KEY,"
        "    display_name TEXT,"
        "    image_link TEXT"
        ");"
        "CREATE TABLE IF NOT EXISTS quarantine ("
        "    author TEXT NOT NULL,"
        "    sequence INTEGER NOT NULL,"
        "    key TEXT NOT NULL UNIQUE,"
        "    previous_key TEXT,"
        "    claimed_timestamp INTEGER NOT NULL,"
        "    received_at INTEGER NOT NULL,"
        "    is_private INTEGER NOT NULL DEFAULT 0,"
        "    content_type TEXT,"
        "    value_json BLOB NOT NULL,"
        "    content_json TEXT,"
        "    feed_format INTEGER NOT NULL DEFAULT 0,"
        "    PRIMARY KEY (author, sequence)"
        ");"
        "CREATE TABLE IF NOT EXISTS quarantine_dependencies ("
        "    message_key TEXT NOT NULL,"
        "    dependency_key TEXT NOT NULL,"
        "    FOREIGN KEY(message_key) REFERENCES quarantine(key) ON DELETE CASCADE"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(content_type);"
        "CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(claimed_timestamp);"
        "CREATE INDEX IF NOT EXISTS idx_messages_format ON messages(feed_format);";

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, sql, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        os_log_error(ssb_feedstore_log, "Schema creation failed: %{public}s", errMsg);
        sqlite3_free(errMsg);
    }
}

#pragma mark - Append

- (BOOL)appendMessage:(SSBMessage *)message error:(NSError **)error {
    // Phase 3: verify via codec registry before touching the DB
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry] codecForFeedFormat:message.feedFormat];
    if (codec) {
        NSError *verifyError = nil;
        if (![codec verifyMessageData:message.valueJSON error:&verifyError]) {
            if (error) *error = verifyError;
            return NO;
        }
    } else {
        // No codec registered for this format
        if (error) {
            *error = [NSError errorWithDomain:SSBFeedStoreErrorDomain code:7
                userInfo:@{NSLocalizedDescriptionKey: @"Unsupported feed format"}];
        }
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *blockError = nil;

    dispatch_sync(self.dbQueue, ^{
        SSBFeedState *state = [self _feedStateForAuthor:message.author];
        NSInteger expectedSeq = state ? (state.maxSequence + 1) : 1;

        if (message.sequence < expectedSeq) {
            blockError = [NSError errorWithDomain:SSBFeedStoreErrorDomain code:6
                userInfo:@{NSLocalizedDescriptionKey: @"Message already exists or is from the past"}];
            return;
        }

        BOOL isOutOfOrder = (message.sequence > expectedSeq);
        NSArray<NSString *> *missingDeps = [self _getMissingDependenciesForMessage:message];
        BOOL hasMissingDeps = (missingDeps.count > 0);

        if (isOutOfOrder || hasMissingDeps) {
            // Quarantine it
            success = [self _appendMessageToTable:"quarantine" message:message error:&blockError];
            if (success) {
                [self _updateQuarantineDependenciesForMessage:message missingDeps:missingDeps];
                os_log_info(ssb_feedstore_log, "Quarantined message %{public}@ (seq %ld, author %{public}@). Missing %lu deps.",
                             message.key, (long)message.sequence, message.author, (unsigned long)missingDeps.count);
            }
        } else {
            // Appending to main messages
            success = [self _appendMessageToTable:"messages" message:message error:&blockError];
            if (success) {
                [self _updateFeedStateForAuthor:message.author sequence:message.sequence key:message.key feedFormat:message.feedFormat];
                [self _drainQuarantineForKey:message.key author:message.author];
                
                // If it's an about message, update profile
                if ([message.contentType isEqualToString:@"about"] && message.content[@"about"]) {
                    NSString *target = message.content[@"about"];
                    NSString *name = message.content[@"name"];
                    NSString *image = message.content[@"image"];
                    if ([target isEqualToString:message.author]) {
                        [self _setDisplayName:name image:image forAuthor:target];
                    }
                }
            }
        }
    });

    if (blockError && error) {
        *error = blockError;
    }
    return success;
}

- (BOOL)_appendMessageToTable:(const char *)tableName message:(SSBMessage *)message error:(NSError **)error {
    NSString *contentType = message.contentType;
    if (!contentType && message.content[@"type"]) {
        contentType = message.content[@"type"];
    }

    NSData *contentJSON = nil;
    if (message.content) {
        contentJSON = [NSJSONSerialization dataWithJSONObject:message.content options:0 error:nil];
    }

    int64_t receivedAt = message.receivedAt;
    if (receivedAt == 0) {
        receivedAt = (int64_t)([[[SSBEnvironment shared] now] timeIntervalSince1970] * 1000.0);
    }

    BOOL isPrivate = message.isPrivate;
    if (!isPrivate && [message.content isKindOfClass:[NSString class]]) {
        NSString *contentStr = (NSString *)message.content;
        if ([contentStr hasSuffix:@".box"] || [contentStr hasSuffix:@".box2"]) {
            isPrivate = YES;
        }
    }

    char insertSQL[512];
    snprintf(insertSQL, sizeof(insertSQL),
             "INSERT INTO %s (author, sequence, key, previous_key, claimed_timestamp, "
             "received_at, is_private, content_type, value_json, content_json, feed_format) "
             "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", tableName);

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, insertSQL, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [NSError errorWithDomain:SSBFeedStoreErrorDomain code:4
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Prepare failed: %s", sqlite3_errmsg(_db)]}];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, message.author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 2, message.sequence);
    sqlite3_bind_text(stmt, 3, message.key.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    if (message.previousKey) {
        sqlite3_bind_text(stmt, 4, message.previousKey.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_int64(stmt, 5, message.claimedTimestamp);
    sqlite3_bind_int64(stmt, 6, receivedAt);
    sqlite3_bind_int(stmt, 7, isPrivate ? 1 : 0);
    if (contentType) {
        sqlite3_bind_text(stmt, 8, contentType.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 8);
    }
    sqlite3_bind_blob(stmt, 9, message.valueJSON.bytes ?: "", (int)message.valueJSON.length, SQLITE_TRANSIENT);
    if (contentJSON) {
        sqlite3_bind_text(stmt, 10, (const char *)contentJSON.bytes, (int)contentJSON.length, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 10);
    }
    sqlite3_bind_int(stmt, 11, (int)message.feedFormat);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [NSError errorWithDomain:SSBFeedStoreErrorDomain code:5
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Insert failed: %s", sqlite3_errmsg(_db)]}];
        return NO;
    }

    return YES;
}

- (void)_updateFeedStateForAuthor:(NSString *)author sequence:(NSInteger)sequence key:(NSString *)key feedFormat:(SSBBFEFeedFormat)feedFormat {
    const char *upsertSQL =
        "INSERT INTO feed_state (author, max_sequence, max_key, feed_format) VALUES (?, ?, ?, ?) "
        "ON CONFLICT(author) DO UPDATE SET max_sequence = excluded.max_sequence, "
        "max_key = excluded.max_key, feed_format = excluded.feed_format";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, upsertSQL, -1, &stmt, NULL);
    if (rc == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, author.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, sequence);
        sqlite3_bind_text(stmt, 3, key.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 4, (int)feedFormat);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }
}


- (NSArray<NSString *> *)_getMissingDependenciesForMessage:(SSBMessage *)message {
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    if (message.previousKey && ![self _hasMessageWithKey:message.previousKey]) {
        [missing addObject:message.previousKey];
    }
    NSDictionary *content = message.content;
    NSDictionary *tangles = content[@"tangles"];
    if ([tangles isKindOfClass:[NSDictionary class]]) {
        for (NSString *tangleName in tangles) {
            SSBTangleData *tangleData = [SSBTangle parseTangleData:tangleName fromContent:content];
            if (tangleData && tangleData.previous) {
                for (NSString *prevKey in tangleData.previous) {
                    if (![self _hasMessageWithKey:prevKey]) {
                        [missing addObject:prevKey];
                    }
                }
            }
        }
    }
    return [missing copy];
}

- (BOOL)_hasMessageWithKey:(NSString *)key {
    const char *sql = "SELECT 1 FROM messages WHERE key = ?";
    sqlite3_stmt *stmt = NULL;
    BOOL exists = NO;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, key.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            exists = YES;
        }
        sqlite3_finalize(stmt);
    }
    return exists;
}

- (void)_updateQuarantineDependenciesForMessage:(SSBMessage *)message missingDeps:(NSArray<NSString *> *)missingDeps {
    const char *delSQL = "DELETE FROM quarantine_dependencies WHERE message_key = ?";
    sqlite3_stmt *delStmt = NULL;
    if (sqlite3_prepare_v2(_db, delSQL, -1, &delStmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(delStmt, 1, message.key.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_step(delStmt);
        sqlite3_finalize(delStmt);
    }
    const char *insSQL = "INSERT INTO quarantine_dependencies (message_key, dependency_key) VALUES (?, ?)";
    sqlite3_stmt *insStmt = NULL;
    if (sqlite3_prepare_v2(_db, insSQL, -1, &insStmt, NULL) == SQLITE_OK) {
        for (NSString *dep in missingDeps) {
            sqlite3_bind_text(insStmt, 1, message.key.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(insStmt, 2, dep.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            sqlite3_step(insStmt);
            sqlite3_reset(insStmt);
        }
        sqlite3_finalize(insStmt);
    }
}

- (void)_drainQuarantineForKey:(NSString *)satisfiedKey author:(NSString *)author {
    NSMutableArray<NSString *> *blockedByThisKey = [NSMutableArray array];
    const char *findSQL = "SELECT message_key FROM quarantine_dependencies WHERE dependency_key = ?";
    sqlite3_stmt *findStmt = NULL;
    if (sqlite3_prepare_v2(_db, findSQL, -1, &findStmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(findStmt, 1, satisfiedKey.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        while (sqlite3_step(findStmt) == SQLITE_ROW) {
            const char *keyStr = (const char *)sqlite3_column_text(findStmt, 0);
            if (keyStr) [blockedByThisKey addObject:[NSString stringWithUTF8String:keyStr]];
        }
        sqlite3_finalize(findStmt);
    }
    const char *delDepSQL = "DELETE FROM quarantine_dependencies WHERE dependency_key = ?";
    sqlite3_stmt *delDepStmt = NULL;
    if (sqlite3_prepare_v2(_db, delDepSQL, -1, &delDepStmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(delDepStmt, 1, satisfiedKey.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_step(delDepStmt);
        sqlite3_finalize(delDepStmt);
    }
    NSMutableSet<NSString *> *candidates = [NSMutableSet setWithArray:blockedByThisKey];
    SSBFeedState *state = [self _feedStateForAuthor:author];
    NSInteger nextSeq = state.maxSequence + 1;
    SSBMessage *nextSeqMsg = [self _getQuarantinedMessageForAuthor:author sequence:nextSeq];
    if (nextSeqMsg) [candidates addObject:nextSeqMsg.key];
    for (NSString *msgKey in candidates) {
        [self _tryReleaseQuarantinedMessageWithKey:msgKey];
    }
}

- (void)_tryReleaseQuarantinedMessageWithKey:(NSString *)msgKey {
    const char *checkSQL = "SELECT 1 FROM quarantine_dependencies WHERE message_key = ? LIMIT 1";
    sqlite3_stmt *checkStmt = NULL;
    BOOL hasDeps = NO;
    if (sqlite3_prepare_v2(_db, checkSQL, -1, &checkStmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(checkStmt, 1, msgKey.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        if (sqlite3_step(checkStmt) == SQLITE_ROW) hasDeps = YES;
        sqlite3_finalize(checkStmt);
    }
    if (hasDeps) return;
    SSBMessage *message = [self _getQuarantinedMessageByKey:msgKey];
    if (!message) return;
    SSBFeedState *state = [self _feedStateForAuthor:message.author];
    NSInteger expectedSeq = state ? (state.maxSequence + 1) : 1;
    if (message.sequence != expectedSeq) return;
    if (message.sequence > 1 && ![message.previousKey isEqualToString:state.maxKey]) return;
    NSError *error = nil;
    if ([self _appendMessageToTable:"messages" message:message error:&error]) {
        [self _updateFeedStateForAuthor:message.author sequence:message.sequence key:message.key feedFormat:message.feedFormat];
        [self _removeMessageFromQuarantine:message];
        [self _drainQuarantineForKey:message.key author:message.author];
    }
}

- (SSBMessage *)_getQuarantinedMessageByKey:(NSString *)key {
    const char *sql = "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, is_private, content_type, value_json, content_json, feed_format FROM quarantine WHERE key = ?";
    sqlite3_stmt *stmt = NULL;
    SSBMessage *msg = nil;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, key.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) msg = [self _messageFromStatement:stmt];
        sqlite3_finalize(stmt);
    }
    return msg;
}

- (SSBMessage *)_getQuarantinedMessageForAuthor:(NSString *)author sequence:(NSInteger)sequence {
    const char *sql = "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, is_private, content_type, value_json, content_json, feed_format FROM quarantine WHERE author = ? AND sequence = ?";
    sqlite3_stmt *stmt = NULL;
    SSBMessage *msg = nil;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, sequence);
        if (sqlite3_step(stmt) == SQLITE_ROW) msg = [self _messageFromStatement:stmt];
        sqlite3_finalize(stmt);
    }
    return msg;
}

- (void)_removeMessageFromQuarantine:(SSBMessage *)message {
    const char *sql = "DELETE FROM quarantine WHERE author = ? AND sequence = ?";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, message.author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, message.sequence);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }
}

#pragma mark - Feed State

- (nullable SSBFeedState *)feedStateForAuthor:(NSString *)author {
    __block SSBFeedState *result = nil;
    dispatch_sync(self.dbQueue, ^{
        result = [self _feedStateForAuthor:author];
    });
    return result;
}

- (NSDictionary<NSString *, NSNumber *> *)localClock {
    __block NSMutableDictionary *clock = [NSMutableDictionary dictionary];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT author, max_sequence FROM feed_state";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *authorStr = (const char *)sqlite3_column_text(stmt, 0);
                if (authorStr) {
                    NSString *author = [NSString stringWithUTF8String:authorStr];
                    NSInteger seq = (NSInteger)sqlite3_column_int64(stmt, 1);
                    clock[author] = @(seq);
                }
            }
            sqlite3_finalize(stmt);
        }
    });
    return [clock copy];
}

- (nullable SSBFeedState *)_feedStateForAuthor:(NSString *)author {
    const char *sql = "SELECT author, max_sequence, max_key, feed_format FROM feed_state WHERE author = ?";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return nil;
    sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    SSBFeedState *state = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        state = [[SSBFeedState alloc] init];
        const char *authorStr = (const char *)sqlite3_column_text(stmt, 0);
        if (authorStr) state.author = [NSString stringWithUTF8String:authorStr];
        state.maxSequence = (NSInteger)sqlite3_column_int64(stmt, 1);
        const char *maxKey = (const char *)sqlite3_column_text(stmt, 2);
        if (maxKey) state.maxKey = [NSString stringWithUTF8String:maxKey];
        state.feedFormat = (SSBBFEFeedFormat)sqlite3_column_int(stmt, 3);
    }
    sqlite3_finalize(stmt);
    return state;
}

#pragma mark - Queries

- (nullable SSBBambooProof *)generateBambooProofForAuthor:(NSString *)author
                                                  sequence:(NSInteger)sequence {
    __block SSBBambooProof *proof = nil;
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT value_json, feed_format FROM messages WHERE author = ? AND sequence = ?";
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        
        sqlite3_bind_text(stmt, 1, author.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 2, (int)sequence);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int format = sqlite3_column_int(stmt, 1);
            if (format != SSBBFEFeedFormatBamboo) {
                sqlite3_finalize(stmt);
                return;
            }
            
            proof = [[SSBBambooProof alloc] init];
            const void *blob = sqlite3_column_blob(stmt, 0);
            int size = sqlite3_column_bytes(stmt, 0);
            proof.targetMessage = [NSData dataWithBytes:blob length:size];
            proof.authorPubKey = [SSBBFE bfeDataFromSigilString:author];
        }
        sqlite3_finalize(stmt);
        
        if (!proof) return;
        
        // Build the Lipmaa path
        NSMutableArray *path = [NSMutableArray array];
        NSInteger currentSeq = sequence;
        
        while (currentSeq > 1) {
            NSInteger nextSeq = [SSBBamboo lipmaaSequenceFor:currentSeq];
            
            // For a direct proof, we fetch the hashes (keys) of the Lipmaa targets
            sqlite3_stmt *pathStmt;
            const char *pathSql = "SELECT key FROM messages WHERE author = ? AND sequence = ?";
            if (sqlite3_prepare_v2(_db, pathSql, -1, &pathStmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(pathStmt, 1, author.UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(pathStmt, 2, (int)nextSeq);
                
                if (sqlite3_step(pathStmt) == SQLITE_ROW) {
                    const char *keyText = (const char *)sqlite3_column_text(pathStmt, 0);
                    if (keyText) {
                        NSString *key = [NSString stringWithUTF8String:keyText];
                        NSData *keyData = [SSBBFE bfeDataFromSigilString:key];
                        if (keyData) [path addObject:keyData];
                    }
                }
                sqlite3_finalize(pathStmt);
            }
            
            if (nextSeq >= currentSeq) break; // Should not happen with power-of-3 logic
            currentSeq = nextSeq;
        }
        
        proof.lipmaaPath = path;
        
        // Fetch root hash (seq 1)
        sqlite3_stmt *rootStmt;
        const char *rootSql = "SELECT key FROM messages WHERE author = ? AND sequence = 1";
        if (sqlite3_prepare_v2(_db, rootSql, -1, &rootStmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(rootStmt, 1, author.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(rootStmt) == SQLITE_ROW) {
                const char *rootKeyText = (const char *)sqlite3_column_text(rootStmt, 0);
                if (rootKeyText) {
                    NSString *rootKey = [NSString stringWithUTF8String:rootKeyText];
                    proof.rootHash = [SSBBFE bfeDataFromSigilString:rootKey];
                }
            }
            sqlite3_finalize(rootStmt);
        }
    });
    
    return proof;
}

- (NSArray<SSBMessage *> *)messagesForAuthor:(NSString *)author fromSequence:(NSInteger)startSeq limit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, is_private, content_type, value_json, content_json, feed_format FROM messages WHERE author = ? AND sequence >= ? ORDER BY sequence ASC LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, startSeq);
        sqlite3_bind_int64(stmt, 3, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) [results addObject:[self _messageFromStatement:stmt]];
        sqlite3_finalize(stmt);
    });
    return results;
}

- (NSArray<SSBMessage *> *)recentMessagesWithLimit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, is_private, content_type, value_json, content_json, feed_format FROM messages WHERE content_type != 'metafeed/index' ORDER BY claimed_timestamp DESC LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int64(stmt, 1, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) [results addObject:[self _messageFromStatement:stmt]];
        sqlite3_finalize(stmt);
    });
    return results;
}

- (NSArray<SSBMessage *> *)timelineWithLimit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        // Union classic followed feeds with any registered device sub-feeds of followed authors.
        // Device sub-feeds are listed in add/derived metafeed messages authored by followed users.
        const char *sql =
            "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, "
            "is_private, content_type, value_json, content_json, feed_format "
            "FROM messages "
            "WHERE content_type != 'metafeed/index' AND ("
            "    author IN (SELECT target_author FROM contacts WHERE following = 1)"
            "    OR author IN ("
            "        SELECT json_extract(content_json,'$.subfeed') "
            "        FROM messages "
            "        WHERE content_type = 'metafeed/add/derived' "
            "          AND author IN (SELECT target_author FROM contacts WHERE following = 1)"
            "    )"
            ") "
            "ORDER BY claimed_timestamp DESC LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int64(stmt, 1, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) [results addObject:[self _messageFromStatement:stmt]];
        sqlite3_finalize(stmt);
    });
    return results;
}

- (NSArray<SSBMessage *> *)feedForAuthor:(NSString *)author limit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, is_private, content_type, value_json, content_json, feed_format FROM messages WHERE author = ? ORDER BY sequence DESC LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) [results addObject:[self _messageFromStatement:stmt]];
        sqlite3_finalize(stmt);
    });
    return results;
}

- (NSArray<SSBMessage *> *)messagesOfType:(NSString *)contentType limit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, is_private, content_type, value_json, content_json, feed_format FROM messages WHERE content_type = ? ORDER BY claimed_timestamp DESC LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_text(stmt, 1, contentType.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) [results addObject:[self _messageFromStatement:stmt]];
        sqlite3_finalize(stmt);
    });
    return results;
}

- (NSArray<SSBMessage *> *)messagesForFeedFormat:(SSBBFEFeedFormat)format limit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, is_private, content_type, value_json, content_json, feed_format FROM messages WHERE feed_format = ? ORDER BY claimed_timestamp DESC LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int(stmt, 1, (int)format);
        sqlite3_bind_int64(stmt, 2, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) [results addObject:[self _messageFromStatement:stmt]];
        sqlite3_finalize(stmt);
    });
    return results;
}

- (BOOL)isTombstoned:(NSString *)feedID {
    if (!feedID) return NO;
    __block BOOL result = NO;
    dispatch_sync(self.dbQueue, ^{
        // A tombstone is a metafeed message whose content JSON contains
        // "type":"metafeed/tombstone" and "subfeed":<feedID>.
        const char *sql =
            "SELECT 1 FROM messages WHERE content_type = 'metafeed/tombstone' "
            "AND json_extract(content_json, '$.subfeed') = ? LIMIT 1";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, feedID.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) result = YES;
            sqlite3_finalize(stmt);
        }
    });
    return result;
}

- (nullable SSBMessage *)lipmaaMessageForAuthor:(NSString *)author
                                       sequence:(NSInteger)sequence
                                         format:(SSBBFEFeedFormat)format {
    // Compute the lipmaa sequence for the requested sequence number.
    NSInteger lipmaaSeq;
    if (format == SSBBFEFeedFormatBamboo) {
        lipmaaSeq = [SSBBamboo lipmaaSequenceFor:sequence];
    } else {
        // GabbyGrove uses the same lipmaa formula.
        lipmaaSeq = [SSBBamboo lipmaaSequenceFor:sequence];
    }
    if (lipmaaSeq <= 0 || lipmaaSeq == sequence) return nil;

    __block SSBMessage *result = nil;
    dispatch_sync(self.dbQueue, ^{
        const char *sql =
            "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, "
            "is_private, content_type, value_json, content_json, feed_format "
            "FROM messages WHERE author = ? AND sequence = ? AND feed_format = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, lipmaaSeq);
            sqlite3_bind_int(stmt, 3, (int)format);
            if (sqlite3_step(stmt) == SQLITE_ROW) result = [self _messageFromStatement:stmt];
            sqlite3_finalize(stmt);
        }
    });
    return result;
}

- (NSArray<NSString *> *)deviceFeedIDsForMetafeedID:(NSString *)metafeedID {
    if (!metafeedID) return @[];
    __block NSMutableArray<NSString *> *feedIDs = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        // add/derived messages from the root metafeed encode the new subfeed ID in content_json.
        const char *sql =
            "SELECT content_json FROM messages WHERE content_type = 'metafeed/add/derived' "
            "AND author = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, metafeedID.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *jsonStr = (const char *)sqlite3_column_text(stmt, 0);
                if (!jsonStr) continue;
                NSData *jsonData = [NSData dataWithBytes:jsonStr length:strlen(jsonStr)];
                NSDictionary *content = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                        options:0 error:nil];
                NSString *subfeedID = content[@"subfeed"];
                if (subfeedID) [feedIDs addObject:subfeedID];
            }
            sqlite3_finalize(stmt);
        }
    });
    return [feedIDs copy];
}

- (NSArray<SSBMessage *> *)querySubset:(NSDictionary<NSString *, id> *)query options:(NSDictionary<NSString *, id> *)options {
    NSDictionary *ql = [SSBQueryEngine sqlFragmentForQuery:query];
    if (!ql[@"sql"]) return @[];
    NSInteger pageSize = [options[@"pageSize"] integerValue] ?: 100;
    BOOL descending = options[@"descending"] ? [options[@"descending"] boolValue] : YES;
    NSInteger startFrom = [options[@"startFrom"] integerValue];
    NSString *order = descending ? @"DESC" : @"ASC";
    NSString *seqOp = descending ? @"<" : @">";
    NSMutableString *fullSQL = [NSMutableString stringWithFormat:@"SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, is_private, content_type, value_json, content_json, feed_format FROM messages WHERE %@", ql[@"sql"]];
    NSMutableArray *allParams = [NSMutableArray arrayWithArray:ql[@"params"]];
    if (startFrom > 0) { [fullSQL appendFormat:@" AND sequence %@ ?", seqOp]; [allParams addObject:@(startFrom)]; }
    [fullSQL appendFormat:@" ORDER BY sequence %@ LIMIT ?", order];
    [allParams addObject:@(pageSize)];
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, fullSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
            for (int i = 0; i < allParams.count; i++) {
                id p = allParams[i];
                if ([p isKindOfClass:[NSString class]]) sqlite3_bind_text(stmt, i + 1, [p UTF8String], -1, SQLITE_TRANSIENT);
                else if ([p isKindOfClass:[NSNumber class]]) sqlite3_bind_int64(stmt, i + 1, [p longLongValue]);
            }
            while (sqlite3_step(stmt) == SQLITE_ROW) [results addObject:[self _messageFromStatement:stmt]];
            sqlite3_finalize(stmt);
        }
    });
    return results;
}

- (SSBMessage *)_messageFromStatement:(sqlite3_stmt *)stmt {
    SSBMessage *msg = [[SSBMessage alloc] init];
    const char *author = (const char *)sqlite3_column_text(stmt, 0);
    if (author) msg.author = [NSString stringWithUTF8String:author];
    msg.sequence = (NSInteger)sqlite3_column_int64(stmt, 1);
    const char *key = (const char *)sqlite3_column_text(stmt, 2);
    if (key) msg.key = [NSString stringWithUTF8String:key];
    const char *prev = (const char *)sqlite3_column_text(stmt, 3);
    if (prev) msg.previousKey = [NSString stringWithUTF8String:prev];
    msg.claimedTimestamp = sqlite3_column_int64(stmt, 4);
    msg.receivedAt = sqlite3_column_int64(stmt, 5);
    msg.isPrivate = sqlite3_column_int(stmt, 6) != 0;
    const char *type = (const char *)sqlite3_column_text(stmt, 7);
    if (type) msg.contentType = [NSString stringWithUTF8String:type];
    const void *valBytes = sqlite3_column_blob(stmt, 8);
    int valLen = sqlite3_column_bytes(stmt, 8);
    if (valBytes) msg.valueJSON = [NSData dataWithBytes:valBytes length:valLen];
    const char *contentJSON = (const char *)sqlite3_column_text(stmt, 9);
    if (contentJSON) {
        NSData *data = [NSData dataWithBytes:contentJSON length:strlen(contentJSON)];
        msg.content = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    }
    msg.feedFormat = (SSBBFEFeedFormat)sqlite3_column_int(stmt, 10);
    return msg;
}

- (void)setFollowing:(BOOL)following forAuthor:(NSString *)author atSequence:(NSInteger)seq {
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "INSERT INTO contacts (target_author, following, blocking, sequence) VALUES (?, ?, COALESCE((SELECT blocking FROM contacts WHERE target_author = ?), 0), ?) ON CONFLICT(target_author) DO UPDATE SET following = excluded.following, sequence = excluded.sequence";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 2, following ? 1 : 0);
            sqlite3_bind_text(stmt, 3, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 4, seq);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    });
}

- (void)setBlocked:(BOOL)blocked forAuthor:(NSString *)author atSequence:(NSInteger)seq {
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "INSERT INTO contacts (target_author, following, blocking, sequence) VALUES (?, COALESCE((SELECT following FROM contacts WHERE target_author = ?), 0), ?, ?) ON CONFLICT(target_author) DO UPDATE SET blocking = excluded.blocking, sequence = excluded.sequence";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 3, blocked ? 1 : 0);
            sqlite3_bind_int64(stmt, 4, seq);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    });
}

- (BOOL)isFollowing:(NSString *)author {
    __block BOOL following = NO;
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT following FROM contacts WHERE target_author = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) following = sqlite3_column_int(stmt, 0) != 0;
            sqlite3_finalize(stmt);
        }
    });
    return following;
}

- (BOOL)isBlocked:(NSString *)author {
    __block BOOL blocked = NO;
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT blocking FROM contacts WHERE target_author = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) blocked = sqlite3_column_int(stmt, 0) != 0;
            sqlite3_finalize(stmt);
        }
    });
    return blocked;
}

- (NSArray<NSString *> *)followedAuthors {
    __block NSMutableArray *authors = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT target_author FROM contacts WHERE following = 1";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *authorStr = (const char *)sqlite3_column_text(stmt, 0);
                if (authorStr) [authors addObject:[NSString stringWithUTF8String:authorStr]];
            }
            sqlite3_finalize(stmt);
        }
    });
    return authors;
}

- (NSArray<NSString *> *)allChannels {
    __block NSMutableArray<NSString *> *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT DISTINCT json_extract(content_json, '$.channel') FROM messages WHERE content_type = 'post' AND json_extract(content_json, '$.channel') IS NOT NULL ORDER BY 1";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *chan = (const char *)sqlite3_column_text(stmt, 0);
                if (chan) [results addObject:[NSString stringWithUTF8String:chan]];
            }
            sqlite3_finalize(stmt);
        }
    });
    return results;
}

- (NSArray<SSBMessage *> *)searchMessages:(NSString *)searchText limit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT author, sequence, key, previous_key, claimed_timestamp, received_at, is_private, content_type, value_json, content_json, feed_format FROM messages WHERE content_json LIKE ? ORDER BY claimed_timestamp DESC LIMIT ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            NSString *likePattern = [NSString stringWithFormat:@"%%%@%%", searchText];
            sqlite3_bind_text(stmt, 1, likePattern.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, limit);
            while (sqlite3_step(stmt) == SQLITE_ROW) [results addObject:[self _messageFromStatement:stmt]];
            sqlite3_finalize(stmt);
        }
    });
    return results;
}

- (NSInteger)totalMessageCount {
    __block NSInteger count = 0;
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT COUNT(*) FROM messages";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            if (sqlite3_step(stmt) == SQLITE_ROW) count = (NSInteger)sqlite3_column_int64(stmt, 0);
            sqlite3_finalize(stmt);
        }
    });
    return count;
}

- (NSDictionary<NSString *, NSNumber *> *)storageStatistics {
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT author, COUNT(*) FROM messages GROUP BY author ORDER BY COUNT(*) DESC LIMIT 50";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *author = (const char *)sqlite3_column_text(stmt, 0);
                long long count = sqlite3_column_int64(stmt, 1);
                if (author) {
                    stats[[NSString stringWithUTF8String:author]] = @(count);
                }
            }
            sqlite3_finalize(stmt);
        }
    });
    return [stats copy];
}

#pragma mark - Profiles

- (void)setDisplayName:(nullable NSString *)name image:(nullable NSString *)image forAuthor:(NSString *)author {
    dispatch_sync(self.dbQueue, ^{
        [self _setDisplayName:name image:image forAuthor:author];
    });
}

- (void)_setDisplayName:(nullable NSString *)name image:(nullable NSString *)image forAuthor:(NSString *)author {
    const char *sql = "INSERT INTO profiles (author, display_name, image_link) VALUES (?, ?, ?) "
                      "ON CONFLICT(author) DO UPDATE SET display_name = COALESCE(excluded.display_name, display_name), "
                      "image_link = COALESCE(excluded.image_link, image_link)";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
        if (name) sqlite3_bind_text(stmt, 2, name.UTF8String, -1, SQLITE_TRANSIENT);
        else sqlite3_bind_null(stmt, 2);
        if (image) sqlite3_bind_text(stmt, 3, image.UTF8String, -1, SQLITE_TRANSIENT);
        else sqlite3_bind_null(stmt, 3);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }
}

- (NSString *)displayNameForAuthor:(NSString *)author {
    __block NSString *name = author;
    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT display_name FROM profiles WHERE author = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, author.UTF8String ?: "", -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *n = (const char *)sqlite3_column_text(stmt, 0);
                if (n) name = [NSString stringWithUTF8String:n];
            }
            sqlite3_finalize(stmt);
        }
    });
    return name;
}

- (void)wipeDatabase {
    dispatch_sync(self.dbQueue, ^{
        os_log_info(ssb_feedstore_log, "Wiping database...");
        
        const char *sql = 
            "DROP TABLE IF EXISTS messages;"
            "DROP TABLE IF EXISTS feed_state;"
            "DROP TABLE IF EXISTS contacts;"
            "DROP TABLE IF EXISTS profiles;"
            "DROP TABLE IF EXISTS quarantine;"
            "DROP TABLE IF EXISTS quarantine_dependencies;";
        
        char *errMsg = NULL;
        if (sqlite3_exec(self->_db, sql, NULL, NULL, &errMsg) != SQLITE_OK) {
            os_log_error(ssb_feedstore_log, "Failed to drop tables: %s", errMsg);
            sqlite3_free(errMsg);
        }
        
        [self createSchema];
        [self migrateSchema];
        
        os_log_info(ssb_feedstore_log, "Database wipe complete.");
    });
}

@end
