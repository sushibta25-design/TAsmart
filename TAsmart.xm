#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString * const kLogPath = @"/var/mobile/TAsmartMiniBridge-safe.log";

static void TALog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ | %@ | %@\n",
                      [NSDate date],
                      NSBundle.mainBundle.bundleIdentifier ?: @"?",
                      msg ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!h) [data writeToFile:kLogPath atomically:YES];
    else {
        @try { [h seekToEndOfFile]; [h writeData:data]; [h closeFile]; }
        @catch (__unused NSException *e) {}
    }
    NSLog(@"[TAsmartSafe] %@", msg);
}

static void TADump(void) {
    TALog(@"SAFE PROBE START");
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        TALog(@"scene id=%@ class=%@ role=%@ state=%ld",
              s.session.persistentIdentifier ?: @"",
              NSStringFromClass(s.class),
              s.session.role ?: @"",
              (long)s.activationState);
        if ([s isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                TALog(@" window=%@ level=%.1f hidden=%d root=%@ frame=%@",
                      NSStringFromClass(w.class), w.windowLevel, w.hidden,
                      NSStringFromClass(w.rootViewController.class),
                      NSStringFromCGRect(w.frame));
            }
        }
    }
    for (NSString *name in @[@"_UIScenePresentationView",
                              @"_UISceneLayerHostContainerView",
                              @"_UIContextLayerHostView",
                              @"CBBridgeManagerCarPlay",
                              @"CBBridged",
                              @"CBBridgedUIApp",
                              @"CBBridgedUIAppView"]) {
        Class c = NSClassFromString(name);
        TALog(@"class %@ => %@", name, c ? NSStringFromClass(c) : @"<nil>");
    }
    TALog(@"SAFE PROBE END");
}

%ctor {
    @autoreleasepool {
        NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if (![bid isEqualToString:@"com.apple.CarPlayApp"]) return;
        TALog(@"TAsmart v0.2-safe loaded");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ TADump(); });
    }
}
