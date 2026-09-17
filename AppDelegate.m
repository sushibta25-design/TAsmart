#import "AppDelegate.h"
#import "PlayerViewController.h"
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController=[PlayerViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
