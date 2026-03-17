#import "SSBLog.h"
#import <os/log.h>
#import <sys/stat.h>
#import <stdatomic.h>

@interface SSBLog () {
    dispatch_io_t _io;
    /// Current byte size of the log. Only modified on ioQueue; read atomically elsewhere.
    _Atomic uint64_t _currentOffset;
    /// Number of records appended. Only modified on ioQueue; read atomically elsewhere.
    _Atomic uint64_t _recordCount;
    /// Packed uint64_t[] mapping record index → byte offset in the log. ioQueue only.
    NSMutableData *_offsetMap;
    NSString *_offsetsPath;
}
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@end

@implementation SSBLog

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _ioQueue = dispatch_queue_create("com.scuttlebutt.log.io", DISPATCH_QUEUE_SERIAL);

        int fd = open(path.UTF8String, O_RDWR | O_CREAT, 0644);
        if (fd == -1) {
            os_log_error(OS_LOG_DEFAULT, "SSBLog: Failed to open log file at %{public}@", path);
            return nil;
        }

        struct stat st;
        uint64_t logSize = 0;
        if (fstat(fd, &st) == 0) {
            logSize = (uint64_t)st.st_size;
        }
        atomic_store(&_currentOffset, logSize);

        _io = dispatch_io_create(DISPATCH_IO_RANDOM, fd, _ioQueue, ^(int error) {
            close(fd);
        });
        if (!_io) {
            close(fd);
            return nil;
        }

        // Load or rebuild the offset map.
        _offsetsPath = [path stringByAppendingString:@".offsets"];
        NSData *savedOffsets = [NSData dataWithContentsOfFile:_offsetsPath];
        if (savedOffsets) {
            _offsetMap = [savedOffsets mutableCopy];
        } else {
            _offsetMap = [NSMutableData data];
        }

        if (logSize > 0) {
            uint64_t mappedCount = _offsetMap.length / sizeof(uint64_t);
            uint64_t scannedCount = [self _scanRecordCount];
            if (mappedCount != scannedCount) {
                os_log_info(OS_LOG_DEFAULT,
                    "SSBLog: Offset map mismatch (mapped=%llu scan=%llu). Rebuilding.",
                    mappedCount, scannedCount);
                _offsetMap = [self _buildOffsetMapByScanning];
                [_offsetMap writeToFile:_offsetsPath atomically:YES];
            }
        }

        atomic_store(&_recordCount, _offsetMap.length / sizeof(uint64_t));
        os_log_info(OS_LOG_DEFAULT,
            "SSBLog: Initialized at %{public}@, records=%llu bytes=%llu",
            path, atomic_load(&_recordCount), logSize);
    }
    return self;
}

/// Scans the log to count records. Called only from init (before ioQueue is shared).
- (uint64_t)_scanRecordCount {
    int fd = dispatch_io_get_descriptor(_io);
    uint64_t offset = 0;
    uint64_t totalSize = atomic_load(&_currentOffset);
    uint64_t count = 0;
    while (offset < totalSize) {
        uint32_t len = 0;
        if (pread(fd, &len, sizeof(len), offset) != sizeof(len)) break;
        if (len == 0 || len > 1024 * 1024 * 10) { offset += sizeof(len); continue; }
        offset += sizeof(len) + len;
        count++;
    }
    return count;
}

/// Scans the log and builds a fresh offset map. Called only from init for recovery.
- (NSMutableData *)_buildOffsetMapByScanning {
    int fd = dispatch_io_get_descriptor(_io);
    uint64_t offset = 0;
    uint64_t totalSize = atomic_load(&_currentOffset);
    NSMutableData *map = [NSMutableData data];
    while (offset < totalSize) {
        uint32_t len = 0;
        if (pread(fd, &len, sizeof(len), offset) != sizeof(len)) break;
        if (len == 0 || len > 1024 * 1024 * 10) { offset += sizeof(len); continue; }
        [map appendBytes:&offset length:sizeof(uint64_t)];
        offset += sizeof(len) + len;
    }
    return map;
}

- (void)appendRecord:(NSData *)data completion:(void(^)(uint64_t recordIndex, NSError * _Nullable error))completion {
    // Copy data so the caller can release their buffer immediately.
    NSData *dataCopy = [data copy];
    dispatch_async(self.ioQueue, ^{
        // All offset and record-count bookkeeping runs on the serial ioQueue — no races.
        uint64_t writeOffset = atomic_load_explicit(&self->_currentOffset, memory_order_relaxed);
        uint64_t recordIndex = self->_offsetMap.length / sizeof(uint64_t);

        [self->_offsetMap appendBytes:&writeOffset length:sizeof(uint64_t)];
        atomic_store_explicit(&self->_currentOffset, writeOffset + dataCopy.length, memory_order_relaxed);
        atomic_store_explicit(&self->_recordCount,   recordIndex + 1,              memory_order_relaxed);

        dispatch_data_t d_data = dispatch_data_create(dataCopy.bytes, dataCopy.length,
                                                       nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        dispatch_io_write(self->_io, writeOffset, d_data, self.ioQueue,
                          ^(bool done, dispatch_data_t rem, int error) {
            if (done) {
                if (completion) {
                    NSError *nsError = error != 0
                        ? [NSError errorWithDomain:NSPOSIXErrorDomain code:error userInfo:nil]
                        : nil;
                    completion(recordIndex, nsError);
                }
            }
        });
    });
}

- (void)readRecordAtIndex:(uint64_t)index completion:(void(^)(NSData * _Nullable data, NSError * _Nullable error))completion {
    dispatch_async(self.ioQueue, ^{
        uint64_t count = self->_offsetMap.length / sizeof(uint64_t);
        if (index >= count) {
            if (completion) {
                completion(nil, [NSError errorWithDomain:@"SSBLog" code:4
                    userInfo:@{NSLocalizedDescriptionKey: @"Record index out of bounds"}]);
            }
            return;
        }
        const uint64_t *offsets = self->_offsetMap.bytes;
        uint64_t byteOffset = offsets[index];

        // Phase 1: read the 4-byte length prefix.
        dispatch_io_read(self->_io, byteOffset, sizeof(uint32_t), self.ioQueue,
                         ^(bool done, dispatch_data_t hData, int hError) {
            if (!done) return;
            if (hError || !hData) {
                if (completion) completion(nil, [NSError errorWithDomain:NSPOSIXErrorDomain code:hError userInfo:nil]);
                return;
            }
            const void *hBuf = NULL; size_t hSize = 0;
            dispatch_data_t hContiguous = dispatch_data_create_map(hData, &hBuf, &hSize);
            if (hSize < sizeof(uint32_t)) {
                (void)hContiguous;
                if (completion) completion(nil, [NSError errorWithDomain:@"SSBLog" code:2 userInfo:nil]);
                return;
            }
            uint32_t payloadLen = 0;
            memcpy(&payloadLen, hBuf, sizeof(uint32_t));
            (void)hContiguous; // bytes copied into payloadLen; safe to release

            // Phase 2: read the payload.
            dispatch_io_read(self->_io, byteOffset + sizeof(uint32_t), payloadLen, self.ioQueue,
                             ^(bool done2, dispatch_data_t pData, int pError) {
                if (!done2) return;
                if (pError || !pData) {
                    if (completion) completion(nil, [NSError errorWithDomain:NSPOSIXErrorDomain code:pError userInfo:nil]);
                    return;
                }
                const void *pBuf = NULL; size_t pSize = 0;
                dispatch_data_t pContiguous = dispatch_data_create_map(pData, &pBuf, &pSize);
                NSData *result = [NSData dataWithBytes:pBuf length:pSize]; // copies bytes
                (void)pContiguous; // bytes copied into result; safe to release
                if (completion) completion(result, nil);
            });
        });
    });
}

- (void)readRecordAtOffset:(uint64_t)offset length:(size_t)length completion:(void(^)(NSData * _Nullable data, NSError * _Nullable error))completion {
    dispatch_io_read(_io, offset, length, self.ioQueue, ^(bool done, dispatch_data_t data, int error) {
        if (done) {
            if (error != 0) {
                if (completion) completion(nil, [NSError errorWithDomain:NSPOSIXErrorDomain code:error userInfo:nil]);
                return;
            }
            if (data) {
                const void *buffer = NULL;
                size_t size = 0;
                dispatch_data_t contiguous = dispatch_data_create_map(data, &buffer, &size);
                NSData *nsData = [NSData dataWithBytes:buffer length:size]; // copies bytes
                (void)contiguous; // safe to release; nsData owns its copy
                if (completion) completion(nsData, nil);
            } else {
                if (completion) completion(nil, nil);
            }
        }
    });
}

- (void)enumerateRecordsUsingBlock:(BOOL(^)(NSData *data, uint64_t recordIndex))block {
    int fd = dispatch_io_get_descriptor(_io);
    uint64_t offset = 0;
    uint64_t totalSize = atomic_load(&_currentOffset);
    uint64_t recordIndex = 0;

    while (offset < totalSize) {
        uint32_t len = 0;
        if (pread(fd, &len, sizeof(len), offset) != sizeof(len)) break;
        if (len == 0 || len > 1024 * 1024 * 10) { offset += sizeof(len); continue; }

        unsigned char *buf = malloc(len);
        if (!buf || pread(fd, buf, len, offset + sizeof(len)) != (ssize_t)len) {
            free(buf);
            break;
        }

        NSData *data = [NSData dataWithBytesNoCopy:buf length:len freeWhenDone:YES];
        if (!block(data, recordIndex)) break;

        offset += sizeof(len) + len;
        recordIndex++;
    }
}

- (void)close {
    if (_io) {
        // Save the offset map before closing so the next launch can skip the scan.
        dispatch_sync(self.ioQueue, ^{
            [self->_offsetMap writeToFile:self->_offsetsPath atomically:YES];
        });
        dispatch_io_close(_io, DISPATCH_IO_STOP);
        _io = nil;
    }
}

- (uint64_t)currentOffset {
    return atomic_load(&_currentOffset);
}

- (uint64_t)recordCount {
    return atomic_load(&_recordCount);
}

@end
