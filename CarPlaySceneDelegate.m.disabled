#import "CarPlaySceneDelegate.h"
#import "PlayerViewController.h"

@implementation CarPlaySceneDelegate

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene
  didConnectInterfaceController:(CPInterfaceController *)interfaceController
                       toWindow:(CPWindow *)window {
    self.interfaceController = interfaceController;
    self.carWindow = window;

    // Give CarPlay a valid root template so the scene is accepted.
    CPInformationItem *item =
        [[CPInformationItem alloc] initWithTitle:@"A510Player"
                                         detail:@"Direct A510 RTSP"];
    CPInformationTemplate *info =
        [[CPInformationTemplate alloc] initWithTitle:@"A510 LIVE"
                                              layout:CPInformationTemplateLayoutLeading
                                               items:@[item]
                                             actions:@[]];
    [interfaceController setRootTemplate:info animated:NO completion:nil];

    // Jailbreak experiment: attach our existing UIKit/H.264 renderer to CPWindow.
    PlayerViewController *player = [PlayerViewController new];
    window.rootViewController = player;
    window.hidden = NO;
    [window makeKeyAndVisible];
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene
didDisconnectInterfaceController:(CPInterfaceController *)interfaceController
                     fromWindow:(CPWindow *)window {
    window.rootViewController = nil;
    self.carWindow = nil;
    self.interfaceController = nil;
}
@end
