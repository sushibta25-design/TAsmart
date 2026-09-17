#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>

@interface CarPlaySceneDelegate : UIResponder <CPTemplateApplicationSceneDelegate>
@property(nonatomic,strong) CPInterfaceController *interfaceController;
@property(nonatomic,strong) CPWindow *carWindow;
@end
