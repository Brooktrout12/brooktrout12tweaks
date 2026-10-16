#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface PIEditorCoordinator : NSObject
+ (instancetype)sharedCoordinator;
- (void)editBundleIdentifier:(NSString *)identifier fromIconView:(UIView *)iconView
                cornerRatio:(CGFloat)cornerRatio useSavedPhoto:(BOOL)useSavedPhoto;
- (void)restoreBundleIdentifier:(NSString *)identifier fromIconView:(UIView *)iconView;
- (void)close;
@end
NS_ASSUME_NONNULL_END
