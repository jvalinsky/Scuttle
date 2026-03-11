#import "SSBLog.h"
#import <os/log.h>
#import <sys/stat.h>
#import <stdatomic.h>

@interface SSBLog () {
    dispatch_io_t _io;
    _Atomic uint64_t _currentOffset;
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
        
        // Seek to end to find current offset
        struct stat st;
        if (fstat(fd, &st) == 0) {
            _currentOffset = st.st_size;
        } else {
            _currentOffset = 0;
        }
        
        _io = dispatch_io_create(DISPATCH_IO_RANDOM, fd, _ioQueue, ^(int error) {
            close(fd);
        });
        
        if (!_io) {
            close(fd);
            return nil;
        }
        
        os_log_info(OS_LOG_DEFAULT, "SSBLog: Initialized at %{public}@, size: %llu", path, (uint64_t)_currentOffset);
    }
    return self;
}

- (void)appendRecord:(NSData *)data completion:(void(^)(uint64_t offset, NSError * _Nullable error))completion {
    dispatch_data_t d_data = dispatch_data_create(data.bytes, data.length, self.ioQueue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    uint64_t writeOffset = _currentOffset;
    
    // Atomically increment offset
    atomic_fetch_add(&_currentOffset, data.length);
    
    dispatch_io_write(_io, writeOffset, d_data, self.ioQueue, ^(bool done, dispatch_data_t  _Nullable data, int error) {
        if (done) {
            if (completion) {
                NSError *nsError = error != 0 ? [NSError errorWithDomain:NSPOSIXErrorDomain code:error userInfo:nil] : nil;
                completion(writeOffset, nsError);
            }
        }
    });
}

- (void)readRecordAtOffset:(uint64_t)offset length:(size_t)length completion:(void(^)(NSData * _Nullable data, NSError * _Nullable error))completion {
    dispatch_io_read(_io, offset, length, self.ioQueue, ^(bool done, dispatch_data_t  _Nullable data, int error) {
        if (done) {
            if (error != 0) {
                if (completion) completion(nil, [NSError errorWithDomain:NSPOSIXErrorDomain code:error userInfo:nil]);
                return;
            }
            
            if (data) {
                const void *buffer = NULL;
                size_t size = 0;
                dispatch_data_t contiguous = dispatch_data_create_map(data, &buffer, &size);
                NSData *nsData = [NSData dataWithBytes:buffer length:size];
                // contiguous will be released by ARC/dispatch when it goes out of scope, 
                // but for safety in this specific context we just use the NSData wrapper.
                if (completion) completion(nsData, nil);
                #pragma unused(contiguous)
            } else {
                if (completion) completion(nil, nil);
            }
        }
    });
}

- (void)close {
    if (_io) {
        dispatch_io_close(_io, DISPATCH_IO_STOP);
        _io = nil;
    }
}

- (uint64_t)currentOffset {
    return _currentOffset;
}

@end
