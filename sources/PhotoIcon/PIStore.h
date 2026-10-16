#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const PIIconsDidChangeNotification;

@interface PIStore : NSObject
// Legacy selector names are retained. Identifiers are opaque manifest keys:
// existing app bundle IDs, or "webclip:" plus a persistent bookmark identifier.
+ (instancetype)sharedStore;
- (BOOL)hasIconForBundleIdentifier:(NSString *)identifier;
- (nullable UIImage *)imageForBundleIdentifier:(NSString *)identifier;
- (nullable UIImage *)sourceForBundleIdentifier:(NSString *)identifier;
- (nullable NSDictionary *)cropForBundleIdentifier:(NSString *)identifier;
- (void)saveImage:(UIImage *)image source:(UIImage *)source crop:(NSDictionary *)crop
    forBundleIdentifier:(NSString *)identifier completion:(void (^)(NSError *_Nullable))completion;
- (void)removeIconForBundleIdentifier:(NSString *)identifier
                         completion:(void (^)(NSError *_Nullable))completion;
@end
NS_ASSUME_NONNULL_END
