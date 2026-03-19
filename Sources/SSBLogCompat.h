#ifndef SSBLogCompat_h
#define SSBLogCompat_h

#ifdef __APPLE__
    #import <os/log.h>
#else
    #import <Foundation/Foundation.h>

    // 2026 Linux/GNUstep Compatibility Shim for Apple's Unified Logging
    typedef NSString * os_log_t;

    #define os_log_create(subsystem, category) [NSString stringWithFormat:@"%s.%s", subsystem, category]

    // Simple NSLog wrapper that identifies the category and level.
    // Note: We ignore the Apple-specific %{public} modifiers as NSLog handles strings normally.
    #define os_log_info(log, format, ...)  NSLog((@"[%@] INFO: " format), log, ##__VA_ARGS__)
    #define os_log_error(log, format, ...) NSLog((@"[%@] ERROR: " format), log, ##__VA_ARGS__)
    #define os_log_debug(log, format, ...) NSLog((@"[%@] DEBUG: " format), log, ##__VA_ARGS__)
    #define os_log(log, format, ...)       NSLog((@"[%@] LOG: " format), log, ##__VA_ARGS__)

    #define SSB_STRONG_DISPATCH assign

#endif /* __APPLE__ */

#ifdef __APPLE__
    #define SSB_STRONG_DISPATCH strong
#endif

#endif /* SSBLogCompat_h */
