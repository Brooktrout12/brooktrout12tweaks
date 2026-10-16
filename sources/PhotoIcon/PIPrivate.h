#pragma once
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
@class SBIconView;

// Only selectors used by PhotoIcon. Checked against iOS 18 runtime headers.
typedef struct SBIconImageInfo {
    CGSize size;
    CGFloat scale;
    CGFloat continuousCornerRadius;
} SBIconImageInfo;

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
- (BOOL)isApplicationIcon;
- (BOOL)isBookmarkIcon;
- (void)reloadIconImage;
+ (UIImage *)iconImageFromUnmaskedImage:(UIImage *)image info:(SBIconImageInfo)info;
@end
@interface SBHBookmark : NSObject
@property(nonatomic, readonly) NSString *identifier;
@property(nonatomic, readonly) BOOL isAppClip;
@end
@interface UIWebClip : NSObject
@property(nonatomic, copy) NSString *identifier;
@end
// The real class inherits SBLeafIcon, which in turn inherits SBIcon.
@interface SBHBookmarkIcon : SBIcon
@property(nonatomic, retain) SBHBookmark *bookmark;
@property(nonatomic, readonly) UIWebClip *webClip;
@end
@interface UIContextMenuConfiguration (PhotoIconPrivate)
// Present in the iOS 18 runtime header; preserve the original configuration.
@property(nonatomic, copy) UIContextMenuActionProvider actionProvider;
@end
@interface SBIconImageView : UIView
@property(nonatomic, readonly) SBIcon *icon;
@property(nonatomic, readonly) SBIconView *iconView;
@property(nonatomic) SBIconImageInfo iconImageInfo;
@property(nonatomic, readonly) CGFloat continuousCornerRadius;
@property(nonatomic, readonly) CGRect visibleBounds;
@property(nonatomic) BOOL showsSquareCorners;
@property(nonatomic, retain) UIImage *displayedImage;
@property(nonatomic, retain) CALayer *contentsLayer;
- (void)updateImageAnimated:(BOOL)animated;
- (void)updateImageSublayerAnimated:(BOOL)animated;
@end
@interface SBHClockApplicationIconImageView : SBIconImageView
- (BOOL)areHandsHidden;
- (void)setHandsHidden:(BOOL)hidden animated:(BOOL)animated;
@end
@interface SBIconView : UIView
@property(nonatomic, retain) SBIcon *icon;
@property(nonatomic, readonly) NSString *applicationBundleIdentifierForShortcuts;
@property(nonatomic, readonly) CGSize iconImageSize;
@property(nonatomic, readonly) CGFloat iconImageCornerRadius;
@property(nonatomic, getter=isEditing) BOOL editing;
- (UIView *)_iconImageView;
@end
@interface SBSApplicationShortcutItem : NSObject
@property(nonatomic, copy) NSString *type;
@property(nonatomic, copy) NSString *localizedTitle;
@property(nonatomic, copy) NSString *localizedSubtitle;
@property(nonatomic, copy) NSDictionary *userInfo;
@end
