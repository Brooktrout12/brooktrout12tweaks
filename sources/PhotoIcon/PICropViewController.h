#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface PICropViewController : UIViewController
- (instancetype)initWithImage:(UIImage *)image crop:(nullable NSDictionary *)crop
    cornerRatio:(CGFloat)cornerRatio;
@property(nonatomic, copy) void (^onSave)(UIImage *image, NSDictionary *crop);
@property(nonatomic, copy) void (^onCancel)(void);
@property(nonatomic, copy) void (^onChoosePhoto)(void);
@property(nonatomic, getter=isSaving) BOOL saving;
@end
NS_ASSUME_NONNULL_END
