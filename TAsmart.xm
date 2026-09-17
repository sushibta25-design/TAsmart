#import <Foundation/Foundation.h>

// TAsmart v0.1.1 recovery:
// Deliberately no UIApplication/UIScene hooks and no CarPlay startup work.
// This package exists only to restore a known-safe installed baseline while
// we move the next probe away from CarPlay.app startup.
static NSString * const kLogPath = @"/var/mobile/TAsmartRecovery.log";

static void TARecoveryLog(void) {
    NSString *line = [NSString stringWithFormat:@"%@ | TAsmart v0.1.1 recovery loaded | process=%@ | bundle=%@\n",
                      [NSDate date],
                      NSProcessInfo.processInfo.processName ?: @"?",
                      NSBundle.mainBundle.bundleIdentifier ?: @"?"];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!h) [data writeToFile:kLogPath atomically:YES];
    else {
        @try { [h seekToEndOfFile]; [h writeData:data]; [h closeFile]; }
        @catch (__unused NSException *e) {}
    }
}

%ctor {
    @autoreleasepool {
        TARecoveryLog();
    }
}
