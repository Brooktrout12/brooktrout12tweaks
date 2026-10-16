#import "Compatibility.h"
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dispatch/dispatch.h>
#import "Runtime.h"
#include <mach-o/dyld.h>
#include <limits.h>
#include <pthread.h>

// A typed initializer preserves ARC's alloc/init ownership convention.
// The private class is resolved at runtime, with its signature checked first.
@protocol BC18SystemSymbolInitializing <NSObject>
- (instancetype)initWithSystemImageName:(NSString *)name;
@end

static NSString *const BC18ActionType = @"com.brooktrout12.3dbadgeclear18.clear-badge";
static NSString *const BC18BundleKey = @"BC18SourceBundleIdentifier";
static Class BC18IconClass;
static Class BC18ShortcutClass;
static Class BC18SymbolClass;
static id (*BC18OriginalShortcutItems)(id, SEL);
static BOOL (*BC18OriginalShouldActivate)(id, SEL, id, NSUInteger);

static BOOL BC18IsOurAction(id item) {
    if (![item isKindOfClass:BC18ShortcutClass]) return NO;
    id type = BC18GetObject(item, NSSelectorFromString(@"type"));
    return [type isKindOfClass:NSString.class] && [type isEqualToString:BC18ActionType];
}

static id BC18ApplicationIcon(id view) {
    id icon = BC18GetObject(view, NSSelectorFromString(@"icon"));
    if (![icon isKindOfClass:BC18IconClass] ||
        !BC18GetBool(icon, NSSelectorFromString(@"isApplicationIcon"))) return nil;
    return icon;
}

static NSString *BC18BundleIdentifier(id icon) {
    id identifier = BC18GetObject(icon, NSSelectorFromString(@"applicationBundleID"));
    return [identifier isKindOfClass:NSString.class] && [identifier length] ? identifier : nil;
}

static BOOL BC18HasBadge(id icon) {
    id badge = BC18GetObject(icon, NSSelectorFromString(@"badgeNumberOrString"));
    // Match SBIcon's display behavior: positive numbers and nonempty strings.
    // A string can be an exclamation mark or another nonnumeric badge.
    if ([badge isKindOfClass:NSNumber.class]) return [badge longLongValue] > 0;
    if ([badge isKindOfClass:NSString.class]) return [badge length] > 0;
    return NO;
}

static id BC18MakeShortcut(NSString *bundleIdentifier) {
    id<BC18SystemSymbolInitializing> allocatedIcon = (id)[BC18SymbolClass alloc];
    id symbol = [allocatedIcon initWithSystemImageName:@"app.badge"];
    if (!symbol) return nil;
    id item = [BC18ShortcutClass new];
    if (!item) return nil;
    // A native symbol, not a precolored PNG. SpringBoard builds the action
    // image and UIKit resolves its tint against the menu's own appearance.
    // This also follows Dawn 18 when its menu mode differs from the device.
    if (!BC18SetObject(item, NSSelectorFromString(@"setType:"), BC18ActionType) ||
        !BC18SetObject(item, NSSelectorFromString(@"setLocalizedTitle:"), @"Clear Badge") ||
        !BC18SetObject(item, NSSelectorFromString(@"setIcon:"), symbol) ||
        !BC18SetObject(item, NSSelectorFromString(@"setUserInfo:"),
                       @{BC18BundleKey: bundleIdentifier})) return nil;
    return item;
}

static id BC18ShortcutItems(id self, SEL cmd) {
    id original = BC18OriginalShortcutItems(self, cmd);
    if (!pthread_main_np() || (original && ![original isKindOfClass:NSArray.class])) return original;
    id icon = BC18ApplicationIcon(self);
    NSString *identifier = BC18BundleIdentifier(icon);
    if (!identifier || !BC18HasBadge(icon) ||
        !BC18MethodMatches(object_getClass(icon), NSSelectorFromString(@"setBadge:"), 'v', "@")) return original;
    // Preserve native and other tweaks' actions, their identities and ordering.
    // Do not mutate SpringBoard's cached or proposed shortcut arrays.
    for (id item in original) if (BC18IsOurAction(item)) return original;
    id item = BC18MakeShortcut(identifier);
    if (!item) return original;
    NSMutableArray *result = original ? [original mutableCopy] : [NSMutableArray new];
    [result addObject:item];
    return [result copy];
}

static BOOL BC18ShouldActivate(id self, SEL cmd, id item, NSUInteger index) {
    if (!BC18IsOurAction(item)) return BC18OriginalShouldActivate(self, cmd, item, index);
    if (pthread_main_np()) {
        id info = BC18GetObject(item, NSSelectorFromString(@"userInfo"));
        id expected = [info isKindOfClass:NSDictionary.class] ? info[BC18BundleKey] : nil;
        id icon = BC18ApplicationIcon(self);
        NSString *current = BC18BundleIdentifier(icon);
        // A recycled icon view must not clear a different app's badge.
        if ([expected isKindOfClass:NSString.class] && [expected length] &&
            [current isEqualToString:expected]) {
            BC18SetObject(icon, NSSelectorFromString(@"setBadge:"), nil);
        }
    }
    // Consume only our action. Never forward it to the application launcher.
    // No permanent hiding hook: future native badge updates run untouched.
    return NO;
}

static void BC18Start(void *context) {
    (void)context;
    @autoreleasepool {
        if (!BTSupportsIOS17And18()) return;
        Class view = NSClassFromString(@"SBIconView");
        BC18IconClass = NSClassFromString(@"SBIcon");
        BC18ShortcutClass = NSClassFromString(@"SBSApplicationShortcutItem");
        BC18SymbolClass = NSClassFromString(@"SBSApplicationShortcutSystemPrivateIcon");
        SEL items = NSSelectorFromString(@"effectiveApplicationShortcutItems");
        SEL activate = NSSelectorFromString(@"shouldActivateApplicationShortcutItem:atIndex:");
        if (![view isSubclassOfClass:UIView.class] || !BC18IconClass ||
            ![BC18ShortcutClass isSubclassOfClass:NSObject.class] ||
            ![BC18SymbolClass isSubclassOfClass:NSObject.class] ||
            !BC18MethodMatches(view, items, '@', "") ||
            !BC18MethodMatches(view, activate, 'b', "@i") ||
            !BC18MethodMatches(view, NSSelectorFromString(@"icon"), '@', "") ||
            !BC18MethodMatches(BC18IconClass, NSSelectorFromString(@"isApplicationIcon"), 'b', "") ||
            !BC18MethodMatches(BC18IconClass, NSSelectorFromString(@"applicationBundleID"), '@', "") ||
            !BC18MethodMatches(BC18IconClass, NSSelectorFromString(@"badgeNumberOrString"), '@', "") ||
            !BC18MethodMatches(BC18IconClass, NSSelectorFromString(@"setBadge:"), 'v', "@") ||
            !BC18MethodMatches(BC18ShortcutClass, NSSelectorFromString(@"init"), '@', "") ||
            !BC18MethodMatches(BC18ShortcutClass, NSSelectorFromString(@"type"), '@', "") ||
            !BC18MethodMatches(BC18ShortcutClass, NSSelectorFromString(@"userInfo"), '@', "") ||
            !BC18MethodMatches(BC18SymbolClass, NSSelectorFromString(@"initWithSystemImageName:"), '@', "@")) return;
        for (NSString *setter in @[@"setType:", @"setLocalizedTitle:", @"setIcon:", @"setUserInfo:"])
            if (!BC18MethodMatches(BC18ShortcutClass, NSSelectorFromString(setter), 'v', "@")) return;
        if (![UIImage systemImageNamed:@"app.badge"]) return;
        // Install consumption first; never expose an item we cannot handle.
        MSHookMessageEx(view, activate, (IMP)BC18ShouldActivate, (IMP *)&BC18OriginalShouldActivate);
        if (!BC18OriginalShouldActivate) return;
        MSHookMessageEx(view, items, (IMP)BC18ShortcutItems, (IMP *)&BC18OriginalShortcutItems);
    }
}

__attribute__((constructor)) static void BC18Initialize(void) {
    char path[PATH_MAX];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) return;
    if (strcmp(path, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") &&
        strcmp(path, "/Applications/SpringBoard.app/SpringBoard")) return;
    // No Objective-C or service access while dyld is running initializers.
    // C callbacks avoid old-arm64e compiler block metadata entirely.
    dispatch_async_f(dispatch_get_main_queue(), NULL, BC18Start);
}
