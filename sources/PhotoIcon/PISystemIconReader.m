#import "PISystemIconReader.h"
#import "PISharedPaths.h"
#import <QuartzCore/QuartzCore.h>
#include <notify.h>
#include <sys/stat.h>
#include <math.h>

@interface NSObject (PIExtensionRecord)
- (id)initWithBundleIdentifier:(NSString *)identifier error:(NSError **)error;
- (id)containingBundleRecord;
- (NSString *)bundleIdentifier;
@end

static NSObject *PIReaderLock;
static NSDictionary *PISharedTokens;
static NSCache *PISharedPhotos;
static NSCache *PISharedRendered;
static NSCache *PIExtensionParents;
static int PINotifyToken = -1;
static CFAbsoluteTime PILastProbe;
static ino_t PICatalogInode;
static struct timespec PICatalogMtime;
static off_t PICatalogSize;

static void PIInitializeReader(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PIReaderLock = [NSObject new];
        PISharedTokens = @{};
        PISharedPhotos = [NSCache new];
        PISharedPhotos.totalCostLimit = 16*1024*1024;
        PISharedRendered = [NSCache new];
        PISharedRendered.totalCostLimit = 16*1024*1024;
        PIExtensionParents = [NSCache new];
        PIExtensionParents.countLimit = 256;
        if (notify_register_check(PI_SHARED_ICON_NOTIFICATION,&PINotifyToken) != NOTIFY_STATUS_OK)
            PINotifyToken = -1;
    });
}
static NSDictionary *PITokenSnapshot(void) {
    PIInitializeReader();
    @synchronized (PIReaderLock) {
        int changed = 0;
        if (PINotifyToken >= 0) notify_check(PINotifyToken,&changed);
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (!changed && PILastProbe > 0 && now-PILastProbe >= 0 && now-PILastProbe < 1.0)
            return PISharedTokens;
        PILastProbe = now;
        NSString *path = [PISharedIconDirectory() stringByAppendingPathComponent:@"Icons.plist"];
        struct stat state = {0};
        if (stat(path.fileSystemRepresentation,&state) != 0) {
            if (PISharedTokens.count) {
                PISharedTokens = @{};
                [PISharedPhotos removeAllObjects];
                [PISharedRendered removeAllObjects];
            }
            PICatalogInode = 0;
            return PISharedTokens;
        }
        if (!changed && state.st_ino == PICatalogInode && state.st_size == PICatalogSize &&
            state.st_mtimespec.tv_sec == PICatalogMtime.tv_sec &&
            state.st_mtimespec.tv_nsec == PICatalogMtime.tv_nsec) return PISharedTokens;
        if (state.st_size <= 0 || state.st_size > 2*1024*1024) return PISharedTokens;
        NSDictionary *catalog = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![catalog isKindOfClass:NSDictionary.class] || ![catalog[@"version"] isEqual:@1] ||
            ![catalog[@"icons"] isKindOfClass:NSDictionary.class]) return PISharedTokens;
        NSDictionary *raw = catalog[@"icons"];
        NSMutableDictionary *valid = [NSMutableDictionary new];
        for (id key in raw) {
            id token = raw[key];
            if ([key isKindOfClass:NSString.class] && [key length] > 0 && [key length] < 1024 &&
                [token isKindOfClass:NSString.class] && [token length] == 36 &&
                [[NSUUID alloc] initWithUUIDString:token]) valid[key] = token;
        }
        PISharedTokens = [valid copy];
        PICatalogInode = state.st_ino;
        PICatalogSize = state.st_size;
        PICatalogMtime = state.st_mtimespec;
        [PISharedPhotos removeAllObjects];
        [PISharedRendered removeAllObjects];
        [PIExtensionParents removeAllObjects];
        return PISharedTokens;
    }
}

static NSString *PITokenForIdentifier(NSString *identifier, NSDictionary *tokens) {
    NSString *token = tokens[identifier];
    if (token || !tokens.count || [identifier hasPrefix:@"webclip:"]) return token;
    id parent = [PIExtensionParents objectForKey:identifier];
    if (!parent) {
        Class recordClass = NSClassFromString(@"LSApplicationExtensionRecord");
        if (![recordClass instancesRespondToSelector:@selector(initWithBundleIdentifier:error:)]) return nil;
        // A share extension maps only through LaunchServices' actual containing
        // app. Prefix guessing could change an unrelated application's icon.
        id record = [[recordClass alloc] initWithBundleIdentifier:identifier error:nil];
        id containing = [record respondsToSelector:@selector(containingBundleRecord)] ?
            [record containingBundleRecord] : nil;
        parent = [containing respondsToSelector:@selector(bundleIdentifier)] ? [containing bundleIdentifier] : nil;
        if (![parent isKindOfClass:NSString.class] || ![parent length]) parent = NSNull.null;
        [PIExtensionParents setObject:parent forKey:identifier];
    }
    return [parent isKindOfClass:NSString.class] ? tokens[parent] : nil;
}

UIImage *PISharedImage(NSString *identifier, CGSize size, CGFloat scale, CGFloat radius, BOOL masked) {
    if (![identifier isKindOfClass:NSString.class] || !identifier.length ||
        !isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0 ||
        size.width > 512 || size.height > 512 || !isfinite(scale) || scale < 1 || scale > 4 ||
        !isfinite(radius) || radius < 0) return nil;
    NSDictionary *tokens = PITokenSnapshot();
    NSString *token = PITokenForIdentifier(identifier,tokens);
    if (!token) return nil;
    NSString *key = [NSString stringWithFormat:@"%@:%@:%.4f:%.4f:%.4f:%.4f:%d", identifier,
        token,size.width,size.height,scale,radius,masked];
    UIImage *result = [PISharedRendered objectForKey:key];
    if (result) return result;
    UIImage *photo = [PISharedPhotos objectForKey:token];
    if (!photo) {
        NSString *file = [PISharedIconDirectory() stringByAppendingPathComponent:[token stringByAppendingString:@".png"]];
        struct stat state = {0};
        if (stat(file.fileSystemRepresentation,&state) || state.st_size <= 0 || state.st_size > 2*1024*1024)
            return nil;
        photo = [UIImage imageWithContentsOfFile:file];
        if (!photo.CGImage || CGImageGetWidth(photo.CGImage) > 1024 || CGImageGetHeight(photo.CGImage) > 1024)
            return nil;
        [PISharedPhotos setObject:photo forKey:token cost:CGImageGetWidth(photo.CGImage)*CGImageGetHeight(photo.CGImage)*4];
    }
    // IconServices also calls us on worker queues (including Control Center's
    // sensor icon cache). SpringBoard rejects implicit transactions there.
    // An explicit, balanced transaction belongs to this calling thread and
    // encloses detached-layer construction, configuration, and rasterization.
    [CATransaction begin];
    @try {
        [CATransaction setDisableActions:YES];
        CALayer *layer = [CALayer layer];
        layer.bounds = (CGRect){CGPointZero,size};
        layer.contents = (__bridge id)photo.CGImage;
        layer.contentsGravity = kCAGravityResize;
        layer.contentsScale = scale;
        layer.masksToBounds = masked;
        layer.cornerCurve = kCACornerCurveContinuous;
        layer.cornerRadius = masked ? MIN(radius,MIN(size.width,size.height)/2) : 0;
        UIGraphicsBeginImageContextWithOptions(size,NO,scale);
        @try {
            CGContextRef context = UIGraphicsGetCurrentContext();
            if (context) {
                [layer renderInContext:context];
                result = UIGraphicsGetImageFromCurrentImageContext();
                result = [result imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            }
        } @finally {
            UIGraphicsEndImageContext();
        }
    } @finally {
        [CATransaction commit];
    }
    if (result) [PISharedRendered setObject:result forKey:key
        cost:CGImageGetWidth(result.CGImage)*CGImageGetHeight(result.CGImage)*4];
    return result;
}
UIImage *PISharedImageMatching(NSString *identifier, UIImage *native) {
    if (![native isKindOfClass:UIImage.class]) return nil;
    return PISharedImage(identifier,native.size,native.scale,MIN(native.size.width,native.size.height)*0.2237,YES);
}
