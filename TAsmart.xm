#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>

static NSString * const kTargetBundle = @"com.sushibta.a510player";
static NSString * const kLogPath = @"/var/mobile/TAsmartMiniBridge-v02.log";
static const char *kProbeRequest = "com.sushibta.tasmart.probe.request";
static const char *kProbeReply   = "com.sushibta.tasmart.probe.reply";

static void TALog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ | %@ | %@ | %@\n",
                      [NSDate date],
                      NSProcessInfo.processInfo.processName ?: @"?",
                      NSBundle.mainBundle.bundleIdentifier ?: @"?",
                      msg ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!h) [data writeToFile:kLogPath atomically:YES];
    else {
        @try { [h seekToEndOfFile]; [h writeData:data]; [h closeFile]; }
        @catch (__unused NSException *e) {}
    }
    NSLog(@"[TAsmartMB02] %@", msg);
}

static id TA0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(obj,sel);
}
static id TA1(id obj, SEL sel, id arg) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL,id))objc_msgSend)(obj,sel,arg);
}

static NSString *TASafeValue(id obj, NSString *selectorName) {
    if (!obj) return @"<nil object>";
    SEL sel = NSSelectorFromString(selectorName);
    if (![obj respondsToSelector:sel]) return @"<absent>";
    @try {
        id value = TA0(obj, sel);
        return [NSString stringWithFormat:@"%@ <%@>", value, value ? NSStringFromClass([value class]) : @"nil"];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"<EXC %@>", e.reason ?: e.name];
    }
}

static void TADumpMethods(Class cls, NSString *contains) {
    if (!cls) { TALog(@"CLASS %@ = nil", contains); return; }
    TALog(@"CLASS %@ ptr=%p superclass=%@", NSStringFromClass(cls), cls, NSStringFromClass(class_getSuperclass(cls)));
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSUInteger emitted = 0;
    for (unsigned int i=0; i<count && emitted<80; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        if (!contains.length ||
            [name localizedCaseInsensitiveContainsString:contains] ||
            [name localizedCaseInsensitiveContainsString:@"scene"] ||
            [name localizedCaseInsensitiveContainsString:@"application"] ||
            [name localizedCaseInsensitiveContainsString:@"activation"] ||
            [name localizedCaseInsensitiveContainsString:@"present"] ||
            [name localizedCaseInsensitiveContainsString:@"bridge"]) {
            const char *types = method_getTypeEncoding(methods[i]);
            TALog(@" METHOD -%@ types=%s", name, types ?: "?");
            emitted++;
        }
    }
    free(methods);
}

static void TADumpCarPlayScenes(void) {
    TALog(@"==== CARPLAY SCENES ====");
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        TALog(@"SCENE id=%@ class=%@ role=%@ state=%ld",
              scene.session.persistentIdentifier ?: @"",
              NSStringFromClass(scene.class),
              scene.session.role ?: @"",
              (long)scene.activationState);
        if ([scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                TALog(@" WINDOW class=%@ level=%.1f hidden=%d alpha=%.2f root=%@ frame=%@",
                      NSStringFromClass(w.class), w.windowLevel, w.hidden, w.alpha,
                      NSStringFromClass(w.rootViewController.class),
                      NSStringFromCGRect(w.frame));
            }
        }
    }
}

static id TAFindSBApplication(void) {
    Class c = NSClassFromString(@"SBApplicationController");
    id ctl = TA0(c, NSSelectorFromString(@"sharedInstance"));
    if (!ctl) ctl = TA0(c, NSSelectorFromString(@"sharedInstanceIfExists"));
    id app = TA1(ctl, NSSelectorFromString(@"applicationWithBundleIdentifier:"), kTargetBundle);
    TALog(@"SB lookup controller=%@ target=%@", ctl, app);
    return app;
}

static void TAProbeSpringBoard(void) {
    TALog(@"==== SPRINGBOARD TARGET PROBE ====");
    id app = TAFindSBApplication();
    NSArray *sels = @[
        @"bundleIdentifier", @"processState", @"mainScene", @"_foregroundActiveScene",
        @"sceneHandle", @"carPlaySupported", @"_carPlayDeclaration",
        @"applicationSceneHandles", @"mainSceneID"
    ];
    for (NSString *s in sels) TALog(@" TARGET %@ => %@", s, TASafeValue(app, s));

    if (app) {
        id scene = nil;
        @try { scene = TA0(app, NSSelectorFromString(@"_foregroundActiveScene")); } @catch (__unused NSException *e) {}
        if (!scene) @try { scene = TA0(app, NSSelectorFromString(@"mainScene")); } @catch (__unused NSException *e) {}
        TALog(@" TARGET chosenScene=%@", scene);
        for (NSString *s in @[@"sceneHandle", @"identifier", @"settings", @"clientProcess", @"contentState"]) {
            TALog(@"  SCENE %@ => %@", s, TASafeValue(scene, s));
        }
        if (scene) TADumpMethods([scene class], @"scene");
    }

    TADumpMethods(NSClassFromString(@"SBApplication"), @"scene");
    TADumpMethods(NSClassFromString(@"SBDeviceApplicationSceneHandle"), @"scene");
    TADumpMethods(NSClassFromString(@"SBDeviceApplicationSceneViewController"), @"scene");
    notify_post(kProbeReply);
}

static void TAProbeCarPlay(void) {
    TALog(@"==== CARPLAY HOST PROBE ====");
    TADumpCarPlayScenes();

    NSArray<NSString *> *classes = @[
        @"_UIScenePresentationView",
        @"_UISceneLayerHostContainerView",
        @"_UIContextLayerHostView",
        @"FBSScene",
        @"FBScene",
        @"FBSSystemService",
        @"UIApplicationSceneClientAgent",
        @"CBBridgeManagerCarPlay",
        @"CBBridged",
        @"CBBridgedUIApp",
        @"CBBridgedUIAppView"
    ];
    for (NSString *name in classes) TADumpMethods(NSClassFromString(name), @"");

    TALog(@"POST probe request to SpringBoard");
    notify_post(kProbeRequest);
}

static void TAInstallSpringBoardIPC(void) {
    int token = 0;
    notify_register_dispatch(kProbeRequest, &token, dispatch_get_main_queue(), ^(__unused int t) {
        TAProbeSpringBoard();
    });
    TALog(@"SpringBoard IPC ready");
}

static void TAInstallCarPlayIPC(void) {
    int token = 0;
    notify_register_dispatch(kProbeReply, &token, dispatch_get_main_queue(), ^(__unused int t) {
        TALog(@"SpringBoard probe replied; inspect preceding SpringBoard lines");
    });
    TALog(@"CarPlay IPC ready");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        TAProbeCarPlay();
    });
}

%ctor {
    @autoreleasepool {
        NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if ([bid isEqualToString:@"com.apple.springboard"]) {
            TALog(@"TAsmart MiniBridge v0.2 loaded in SpringBoard");
            TAInstallSpringBoardIPC();
        } else if ([bid isEqualToString:@"com.apple.CarPlayApp"]) {
            TALog(@"TAsmart MiniBridge v0.2 loaded in CarPlayApp");
            TAInstallCarPlayIPC();
        }
    }
}
