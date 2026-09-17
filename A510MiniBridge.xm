#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const kA510BundleID = @"com.sushibta.a510player";
static NSString * const kLogPath = @"/var/mobile/A510MiniBridge.log";

static void MBLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ | %@ | %@\n",
                      [NSDate date], NSBundle.mainBundle.bundleIdentifier ?: @"?", msg];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!h) {
        [line writeToFile:kLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    }
    NSLog(@"[A510MiniBridge] %@", msg);
}

static id Call0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(obj,sel);
}
static id Call1(id obj, SEL sel, id arg) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL,id))objc_msgSend)(obj,sel,arg);
}

static void DumpSceneState(void) {
    UIApplication *app = UIApplication.sharedApplication;
    MBLog(@"==== SCENE DUMP ====");
    for (UIScene *s in app.connectedScenes) {
        MBLog(@"scene=%@ class=%@ role=%@ state=%ld",
              s.session.persistentIdentifier,
              NSStringFromClass(s.class),
              s.session.role,
              (long)s.activationState);
        if ([s isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                MBLog(@" window=%@ level=%.1f hidden=%d root=%@",
                      NSStringFromClass(w.class), w.windowLevel, w.hidden,
                      NSStringFromClass(w.rootViewController.class));
            }
        }
    }
}

static id FindSBApplication(void) {
    Class c = NSClassFromString(@"SBApplicationController");
    id controller = Call0(c, NSSelectorFromString(@"sharedInstance"));
    if (!controller) controller = Call0(c, NSSelectorFromString(@"sharedInstanceIfExists"));
    id sbapp = Call1(controller, NSSelectorFromString(@"applicationWithBundleIdentifier:"), kA510BundleID);
    MBLog(@"SBApplicationController=%@ A510=%@", controller, sbapp);
    return sbapp;
}

static void ProbeA510(void) {
    MBLog(@"PROBE START process=%@ bundle=%@", NSProcessInfo.processInfo.processName,
          NSBundle.mainBundle.bundleIdentifier);
    DumpSceneState();

    id sbapp = FindSBApplication();
    if (sbapp) {
        NSArray *sels = @[
            @"bundleIdentifier", @"processState", @"mainScene",
            @"_foregroundActiveScene", @"sceneHandle", @"carPlaySupported",
            @"_carPlayDeclaration"
        ];
        for (NSString *name in sels) {
            SEL s = NSSelectorFromString(name);
            if ([sbapp respondsToSelector:s]) {
                id value = nil;
                @try { value = Call0(sbapp, s); }
                @catch (NSException *e) { value = [NSString stringWithFormat:@"EXC:%@", e]; }
                MBLog(@" A510 %@ => %@", name, value);
            } else {
                MBLog(@" A510 %@ => <selector absent>", name);
            }
        }
    }

    Class bridge = NSClassFromString(@"CBBridgeManagerCarPlay");
    Class bridged = NSClassFromString(@"CBBridged");
    Class pres = NSClassFromString(@"_UIScenePresentationView");
    MBLog(@"classes CBBridgeManagerCarPlay=%@ CBBridged=%@ _UIScenePresentationView=%@",
          bridge, bridged, pres);

    MBLog(@"PROBE END");
}

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ ProbeA510(); });
    }
}
%end

%ctor {
    @autoreleasepool {
        NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if ([bid isEqualToString:@"com.apple.CarPlayApp"]) {
            MBLog(@"v0.1 LOADED");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ ProbeA510(); });
        }
    }
}
