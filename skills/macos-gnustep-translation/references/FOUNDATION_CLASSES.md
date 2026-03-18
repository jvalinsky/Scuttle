# Foundation Classes Compatibility

## Overview

GNUstep's Foundation framework provides **90%+ API compatibility** with Apple's Foundation. Most code works without modification.

## NSObject

**Compatibility:** ✅ 100%

```objc
// Same API as macOS
+ (id)alloc;
- (void)dealloc;
- (id)retain;
- (void)release;
- (id)autorelease;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)respondsToSelector:(SEL)aSelector;
```

**GNUstep Extensions:**
```objc
// NSObject(GNUstep) category
- (id)copyUniqued;           // GNUstep extension
- (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

// Threading
- (void)performSelectorInBackground:(SEL)aSelector withObject:(id)arg;
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(id)arg waitUntilDone:(BOOL)wait;
```

## NSString

**Compatibility:** ✅ 100%

```objc
// Creation - same API
+ (instancetype)string;
+ (instancetype)stringWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (instancetype)stringWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error;

// Access
- (NSUInteger)length;
- (unichar)characterAtIndex:(NSUInteger)index;

// Encoding
- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding;
- (instancetype)initWithData:(NSData *)data encoding:(NSStringEncoding)encoding;
```

**GNUstep Path Handling:**
```objc
// Three modes: 'gnustep', 'unix', 'windows'
// Use standard NSPath methods (same as macOS)
[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
[path stringByExpandingTildeInPath];
[path lastPathComponent];
[path pathExtension];
```

## NSArray

**Compatibility:** ✅ 100%

```objc
// Creation
+ (instancetype)array;
+ (instancetype)arrayWithObjects:(id)firstObj, ... NS_REQUIRES_NIL_TERMINATION;

// Access
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)index;

// Searching
- (NSUInteger)indexOfObject:(id)anObject;
- (BOOL)containsObject:(id)anObject;

// Sorting
- (NSArray *)sortedArrayUsingDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors;
- (NSArray *)sortedArrayUsingComparator:(NSComparator)cmptr;
```

## NSDictionary / NSMutableDictionary

**Compatibility:** ✅ 100%

```objc
// Creation
+ (instancetype)dictionary;
+ (instancetype)dictionaryWithObjectsAndKeys:(id)firstObject, ...;

// Access
- (id)objectForKey:(id)aKey;
- (NSArray *)allKeys;
- (NSArray *)allValues;

// Modification (NSMutableDictionary)
- (void)setObject:(id)object forKey:(id<NSCopying>)key;
- (void)removeObjectForKey:(id)aKey;
```

## NSData

**Compatibility:** ✅ 100%

```objc
// Creation
+ (instancetype)data;
+ (instancetype)dataWithBytes:(const void *)bytes length:(NSUInteger)length;
+ (instancetype)dataWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)readOptionsMask error:(NSError **)errorPtr;

// Access
- (const void *)bytes;
- (NSUInteger)length;

// Writing
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)writeOptionsMask error:(NSError **)errorPtr;
```

## NSFileManager

**Compatibility:** ✅ 100%

```objc
// Singleton
+ (NSFileManager *)defaultManager;

// File operations
- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)contents attributes:(NSDictionary *)attributes;
- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error;
- (BOOL)moveItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory;

// Directory operations
- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary *)attributes error:(NSError **)error;
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error;
```

## NSThread

**Compatibility:** ✅ 100%

```objc
// Thread management
+ (NSThread *)currentThread;
+ (BOOL)isMainThread;
+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument;

// Sleep
+ (void)sleepUntilDate:(NSDate *)date;
+ (void)sleepForTimeInterval:(NSTimeInterval)seconds;
```

## NSRunLoop

**Compatibility:** ✅ 100%

```objc
// Current run loop
+ (NSRunLoop *)currentRunLoop;
+ (NSRunLoop *)mainRunLoop;

// Running
- (void)run;
- (void)runUntilDate:(NSDate *)limitDate;
- (BOOL)runMode:(NSString *)mode beforeDate:(NSDate *)limitDate;

// Sources and timers
- (void)addSource:(id)source forMode:(NSString *)mode;
- (void)addTimer:(NSTimer *)timer forMode:(NSString *)mode;
```

## NSOperation / NSOperationQueue

**Compatibility:** ✅ 100%

```objc
// NSOperation
@property (readonly, getter=isFinished) BOOL finished;
@property (readonly, getter=isExecuting) BOOL executing;
- (void)start;
- (void)cancel;

// NSBlockOperation
+ (instancetype)blockOperationWithBlock:(void (^)(void))block;
- (void)addExecutionBlock:(void (^)(void))block;

// NSOperationQueue
+ (NSOperationQueue *)mainQueue;
- (void)addOperation:(NSOperation *)operation;
- (void)addOperationWithBlock:(void (^)(void))block;
@property NSInteger maxConcurrentOperationCount;
```

## NSDate

**Compatibility:** ✅ 100%

```objc
// Creation
+ (NSDate *)date;
+ (NSDate *)dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds;
+ (NSDate *)dateWithTimeIntervalSince1970:(NSTimeInterval)seconds;
+ (NSDate *)distantPast;
+ (NSDate *)distantFuture;

// Comparison
- (NSComparisonResult)compare:(NSDate *)other;
- (NSDate *)earlierDate:(NSDate *)anotherDate;
- (NSDate *)laterDate:(NSDate *)anotherDate;

// Time intervals
- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)otherDate;
- (NSTimeInterval)timeIntervalSinceNow;
```

## NSCalendar

**Compatibility:** ✅ 100%

```objc
// Calendar
+ (id)currentCalendar;

// Components
- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)date;
- (NSDate *)dateFromComponents:(NSDateComponents *)comps;
```

## NSDateFormatter

**Compatibility:** ✅ 100%

```objc
// Formatting
- (NSString *)stringFromDate:(NSDate *)date;
- (NSDate *)dateFromString:(NSString *)string;

// Properties
@property (copy) NSString *dateFormat;
@property NSDateFormatterStyle dateStyle;
@property NSDateFormatterStyle timeStyle;
```

## NSNotificationCenter

**Compatibility:** ✅ 100%

```objc
// Getting center
+ (NSNotificationCenter *)defaultCenter;

// Observing
- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)notificationName object:(id)sender;
- (id)addObserverForName:(NSString *)name object:(id)obj queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *note))block;

// Posting
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo;

// Removing
- (void)removeObserver:(id)observer;
- (void)removeObserver:(id)observer name:(NSString *)notificationName object:(id)object;
```

## NSError

**Compatibility:** ✅ 100%

```objc
// Creation
+ (instancetype)errorWithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)dict;

// Properties
@property (readonly) NSString *domain;
@property (readonly) NSInteger code;
@property (copy) NSDictionary *userInfo;
```

## NSTimeZone

**Compatibility:** ✅ 100%

```objc
// Timezone
+ (NSTimeZone *)localTimeZone;
+ (NSTimeZone *)systemTimeZone;
+ (NSTimeZone *)timeZoneWithName:(NSString *)name;
- (NSInteger)secondsFromGMT;
```

## Summary

| Class | Compatibility | Notes |
|-------|--------------|-------|
| NSObject | ✅ 100% | Same API |
| NSString | ✅ 100% | Same API |
| NSArray | ✅ 100% | Same API |
| NSDictionary | ✅ 100% | Same API |
| NSData | ✅ 100% | Same API |
| NSFileManager | ✅ 100% | Same API |
| NSThread | ✅ 100% | Same API |
| NSRunLoop | ✅ 100% | Same API |
| NSOperation | ✅ 100% | Same API |
| NSDate | ✅ 100% | Same API |
| NSCalendar | ✅ 100% | Same API |
| NSNotificationCenter | ✅ 100% | Same API |

**Conclusion:** Foundation classes are fully compatible. No shims needed.
