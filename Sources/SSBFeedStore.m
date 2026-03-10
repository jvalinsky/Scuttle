#import "SSBFeedStore.h"
#import <sqlite3.h>
#import <os/log.h>

static os_log_t ssb_feedstore_log;

static NSString *const SSBFeedStoreErrorDomain = @"SSBFeedStore";

@implementation SSBMessage
@end

@implementation SSBFeedState
@end

@interface SSBFeedStore () {
    sqlite3 *_db;
}
@property (nonatomic, strong) dispatch_queue_t dbQueue;
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
    }
    return self;
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
        "    content_type TEXT,"
        "    value_json BLOB NOT NULL,"
        "    content_json TEXT,"
        "    PRIMARY KEY (author, sequence)"
        ");"
        "CREATE TABLE IF NOT EXISTS feed_state ("
        "    author TEXT PRIMARY KEY,"
        "    max_sequence INTEGER NOT NULL,"
        "    max_key TEXT NOT NULL"
        ");"
        "CREATE TABLE IF NOT EXISTS contacts ("
        "    target_author TEXT PRIMARY KEY,"
        "    following INTEGER NOT NULL,"
        "    sequence INTEGER NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(content_type);"
        "CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(claimed_timestamp);";

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, sql, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        os_log_error(ssb_feedstore_log, "Schema creation failed: %{public}s", errMsg);
        sqlite3_free(errMsg);
    }
}

#pragma mark - Append

- (BOOL)appendMessage:(SSBMessage *)message error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *blockError = nil;

    dispatch_sync(self.dbQueue, ^{
        // Look up current feed state
        SSBFeedState *state = [self _feedStateForAuthor:message.author];

        NSInteger expectedSeq = state ? (state.maxSequence + 1) : 1;
        if (message.sequence != expectedSeq) {
            blockError = [NSError errorWithDomain:SSBFeedStoreErrorDomain code:1
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Sequence mismatch: expected %ld, got %ld",
                        (long)expectedSeq, (long)message.sequence]}];
            return;
        }

        // Validate previous key chain
        if (message.sequence == 1) {
            if (message.previousKey != nil) {
                blockError = [NSError errorWithDomain:SSBFeedStoreErrorDomain code:2
                    userInfo:@{NSLocalizedDescriptionKey: @"First message must have nil previousKey"}];
                return;
            }
        } else {
            if (![message.previousKey isEqualToString:state.maxKey]) {
                blockError = [NSError errorWithDomain:SSBFeedStoreErrorDomain code:3
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Previous key mismatch: expected %@, got %@",
                            state.maxKey, message.previousKey]}];
                return;
            }
        }

        // Extract content_type from content dict
        NSString *contentType = message.contentType;
        if (!contentType && message.content[@"type"]) {
            contentType = message.content[@"type"];
        }

        // Serialize content dict to JSON for storage
        NSData *contentJSON = nil;
        if (message.content) {
            contentJSON = [NSJSONSerialization dataWithJSONObject:message.content options:0 error:nil];
        }

        int64_t receivedAt = message.receivedAt;
        if (receivedAt == 0) {
            receivedAt = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
        }

        // INSERT message
        const char *insertSQL =
            "INSERT INTO messages (author, sequence, key, previous_key, claimed_timestamp, "
            "received_at, content_type, value_json, content_json) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(_db, insertSQL, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:SSBFeedStoreErrorDomain code:4
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Prepare failed: %s", sqlite3_errmsg(_db)]}];
            return;
        }

        sqlite3_bind_text(stmt, 1, message.author.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, message.sequence);
        sqlite3_bind_text(stmt, 3, message.key.UTF8String, -1, SQLITE_TRANSIENT);
        if (message.previousKey) {
            sqlite3_bind_text(stmt, 4, message.previousKey.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 4);
        }
        sqlite3_bind_int64(stmt, 5, message.claimedTimestamp);
        sqlite3_bind_int64(stmt, 6, receivedAt);
        if (contentType) {
            sqlite3_bind_text(stmt, 7, contentType.UTF8String, -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 7);
        }
        sqlite3_bind_blob(stmt, 8, message.valueJSON.bytes, (int)message.valueJSON.length, SQLITE_TRANSIENT);
        if (contentJSON) {
            sqlite3_bind_text(stmt, 9, (const char *)contentJSON.bytes, (int)contentJSON.length, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 9);
        }

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        if (rc != SQLITE_DONE) {
            blockError = [NSError errorWithDomain:SSBFeedStoreErrorDomain code:5
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Insert failed: %s", sqlite3_errmsg(_db)]}];
            return;
        }

        // Upsert feed_state
        const char *upsertSQL =
            "INSERT INTO feed_state (author, max_sequence, max_key) VALUES (?, ?, ?) "
            "ON CONFLICT(author) DO UPDATE SET max_sequence = excluded.max_sequence, max_key = excluded.max_key";

        stmt = NULL;
        rc = sqlite3_prepare_v2(_db, upsertSQL, -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, message.author.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, message.sequence);
            sqlite3_bind_text(stmt, 3, message.key.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }

        os_log_info(ssb_feedstore_log, "Stored message %{public}@ seq %ld for %{public}@",
                     message.key, (long)message.sequence, message.author);
        success = YES;
    });

    if (blockError && error) {
        *error = blockError;
    }
    return success;
}

#pragma mark - Feed State

- (nullable SSBFeedState *)feedStateForAuthor:(NSString *)author {
    __block SSBFeedState *result = nil;
    dispatch_sync(self.dbQueue, ^{
        result = [self _feedStateForAuthor:author];
    });
    return result;
}

/// Internal feed state lookup (must be called on dbQueue).
- (nullable SSBFeedState *)_feedStateForAuthor:(NSString *)author {
    const char *sql = "SELECT author, max_sequence, max_key FROM feed_state WHERE author = ?";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return nil;

    sqlite3_bind_text(stmt, 1, author.UTF8String, -1, SQLITE_TRANSIENT);

    SSBFeedState *state = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        state = [[SSBFeedState alloc] init];
        state.author = [[NSString alloc] initWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        state.maxSequence = (NSInteger)sqlite3_column_int64(stmt, 1);
        const char *maxKey = (const char *)sqlite3_column_text(stmt, 2);
        state.maxKey = maxKey ? [[NSString alloc] initWithUTF8String:maxKey] : nil;
    }
    sqlite3_finalize(stmt);
    return state;
}

#pragma mark - Queries

- (NSArray<SSBMessage *> *)messagesForAuthor:(NSString *)author
                                fromSequence:(NSInteger)startSeq
                                       limit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];

    dispatch_sync(self.dbQueue, ^{
        const char *sql =
            "SELECT key, author, sequence, previous_key, claimed_timestamp, received_at, "
            "content_type, value_json, content_json "
            "FROM messages WHERE author = ? AND sequence >= ? ORDER BY sequence ASC LIMIT ?";

        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, author.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, startSeq);
        sqlite3_bind_int64(stmt, 3, limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [results addObject:[self _messageFromStatement:stmt]];
        }
        sqlite3_finalize(stmt);
    });

    return results;
}

- (NSArray<SSBMessage *> *)timelineWithLimit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];

    dispatch_sync(self.dbQueue, ^{
        const char *sql =
            "SELECT key, author, sequence, previous_key, claimed_timestamp, received_at, "
            "content_type, value_json, content_json "
            "FROM messages WHERE author IN "
            "(SELECT target_author FROM contacts WHERE following = 1) "
            "ORDER BY claimed_timestamp DESC LIMIT ?";

        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;

        sqlite3_bind_int64(stmt, 1, limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [results addObject:[self _messageFromStatement:stmt]];
        }
        sqlite3_finalize(stmt);
    });

    return results;
}

- (NSArray<SSBMessage *> *)feedForAuthor:(NSString *)author limit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];

    dispatch_sync(self.dbQueue, ^{
        const char *sql =
            "SELECT key, author, sequence, previous_key, claimed_timestamp, received_at, "
            "content_type, value_json, content_json "
            "FROM messages WHERE author = ? ORDER BY sequence DESC LIMIT ?";

        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, author.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [results addObject:[self _messageFromStatement:stmt]];
        }
        sqlite3_finalize(stmt);
    });

    return results;
}

- (NSArray<SSBMessage *> *)messagesOfType:(NSString *)contentType limit:(NSInteger)limit {
    __block NSMutableArray<SSBMessage *> *results = [NSMutableArray array];

    dispatch_sync(self.dbQueue, ^{
        const char *sql =
            "SELECT key, author, sequence, previous_key, claimed_timestamp, received_at, "
            "content_type, value_json, content_json "
            "FROM messages WHERE content_type = ? ORDER BY claimed_timestamp DESC LIMIT ?";

        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, contentType.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [results addObject:[self _messageFromStatement:stmt]];
        }
        sqlite3_finalize(stmt);
    });

    return results;
}

#pragma mark - Follow Graph

- (void)setFollowing:(BOOL)following forAuthor:(NSString *)author atSequence:(NSInteger)seq {
    dispatch_sync(self.dbQueue, ^{
        const char *sql =
            "INSERT INTO contacts (target_author, following, sequence) VALUES (?, ?, ?) "
            "ON CONFLICT(target_author) DO UPDATE SET following = excluded.following, sequence = excluded.sequence";

        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            os_log_error(ssb_feedstore_log, "Failed to prepare setFollowing: %{public}s", sqlite3_errmsg(_db));
            return;
        }

        sqlite3_bind_text(stmt, 1, author.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, following ? 1 : 0);
        sqlite3_bind_int64(stmt, 3, seq);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        os_log_info(ssb_feedstore_log, "%{public}@ %{public}@ at seq %ld",
                     following ? @"Following" : @"Unfollowing", author, (long)seq);
    });
}

- (BOOL)isFollowing:(NSString *)author {
    __block BOOL result = NO;

    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT following FROM contacts WHERE target_author = ?";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, author.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            result = sqlite3_column_int64(stmt, 0) == 1;
        }
        sqlite3_finalize(stmt);
    });

    return result;
}

- (NSArray<NSString *> *)followedAuthors {
    __block NSMutableArray<NSString *> *results = [NSMutableArray array];

    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT target_author FROM contacts WHERE following = 1";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *author = (const char *)sqlite3_column_text(stmt, 0);
            if (author) {
                [results addObject:[[NSString alloc] initWithUTF8String:author]];
            }
        }
        sqlite3_finalize(stmt);
    });

    return results;
}

- (NSInteger)totalMessageCount {
    __block NSInteger count = 0;

    dispatch_sync(self.dbQueue, ^{
        const char *sql = "SELECT COUNT(*) FROM messages";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = (NSInteger)sqlite3_column_int64(stmt, 0);
        }
        sqlite3_finalize(stmt);
    });

    return count;
}

#pragma mark - Internal

/// Parses a message from the current row of a prepared statement.
- (SSBMessage *)_messageFromStatement:(sqlite3_stmt *)stmt {
    SSBMessage *msg = [[SSBMessage alloc] init];

    msg.key = [[NSString alloc] initWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
    msg.author = [[NSString alloc] initWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
    msg.sequence = (NSInteger)sqlite3_column_int64(stmt, 2);

    const char *prevKey = (const char *)sqlite3_column_text(stmt, 3);
    msg.previousKey = prevKey ? [[NSString alloc] initWithUTF8String:prevKey] : nil;

    msg.claimedTimestamp = sqlite3_column_int64(stmt, 4);
    msg.receivedAt = sqlite3_column_int64(stmt, 5);

    const char *contentType = (const char *)sqlite3_column_text(stmt, 6);
    msg.contentType = contentType ? [[NSString alloc] initWithUTF8String:contentType] : nil;

    const void *blob = sqlite3_column_blob(stmt, 7);
    int blobLen = sqlite3_column_bytes(stmt, 7);
    msg.valueJSON = blob ? [NSData dataWithBytes:blob length:blobLen] : [NSData data];

    const char *contentJSON = (const char *)sqlite3_column_text(stmt, 8);
    if (contentJSON) {
        NSData *jsonData = [[NSData alloc] initWithBytes:contentJSON length:strlen(contentJSON)];
        msg.content = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    }

    return msg;
}

@end
