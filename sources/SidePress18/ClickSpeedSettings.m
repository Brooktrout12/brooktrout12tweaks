#import "Compatibility.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "ClickSpeed.h"
#import "DeviceCapabilities.h"

// These are the identifiers from Apple's Accessibility Side Button page, not
// translated titles. Discovering the controller through its native specifiers
// also works when AccessibilitySettings.bundle is loaded after Preferences.
static NSString * const SPDefaultSpeedID = @"HOME_CLICK_SPEED_DEFAULT";
static NSString * const SPSlowSpeedID = @"HOME_CLICK_SPEED_SLOW";
static NSString * const SPSlowestSpeedID = @"HOME_CLICK_SPEED_SLOWEST";
static NSString * const SPFasterSpeedID = @"SP18_SIDE_CLICK_FASTER";
static NSString * const SPFastestSpeedID = @"SP18_SIDE_CLICK_FASTEST";
static const char SPSpeedGroupAssociation;
static Class speedControllerClass;

static NSMutableArray *(*originalLoad)(id, SEL, NSString *, id);
static NSMutableArray *(*originalLoadBundle)(id, SEL, NSString *, id, NSBundle *);
static void (*originalSetSpecifiers)(id, SEL, NSArray *);
static UITableViewCell *(*originalCell)(id, SEL, UITableView *, NSIndexPath *);
static void (*originalSelect)(id, SEL, UITableView *, NSIndexPath *);

static BOOL SPMethodHasObjectArguments(Class cls, SEL selector, char returnCode, unsigned count) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != count) return NO;
    char type[64] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != returnCode) return NO;
    method_getArgumentType(method, 0, type, sizeof(type));
    if (type[0] != '@') return NO;
    method_getArgumentType(method, 1, type, sizeof(type));
    if (type[0] != ':') return NO;
    for (unsigned index = 2; index < count; ++index) {
        method_getArgumentType(method, index, type, sizeof(type));
        if (type[0] != '@') return NO;
    }
    return YES;
}

static NSInteger SPChoiceForSpecifier(PSSpecifier *specifier) {
    NSString *identifier = specifier.identifier;
    if ([identifier isEqualToString:SPFasterSpeedID]) return 1;
    if ([identifier isEqualToString:SPFastestSpeedID]) return 2;
    return 0;
}

static BOOL SPIsNativeSpeed(PSSpecifier *specifier) {
    NSString *identifier = specifier.identifier;
    return [identifier isEqualToString:SPDefaultSpeedID] ||
           [identifier isEqualToString:SPSlowSpeedID] ||
           [identifier isEqualToString:SPSlowestSpeedID];
}

static void SPStoreSpeed(NSInteger choice) {
    SPWrite(SP_CLICK_SPEED_KEY, @(choice));
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        SP_CHANGED, NULL, NULL, true);
}

static UITableViewCell *SPCell(id self, SEL cmd, UITableView *table, NSIndexPath *indexPath) {
    PSSpecifier *specifier = [(PSListController *)self specifierAtIndexPath:indexPath];
    NSInteger choice = SPChoiceForSpecifier(specifier);
    if (choice) {
        // ButtonClickController enumerates visible cells and sends -specifier
        // when a native speed is selected. Every inserted row must obey that
        // Preferences contract, even though this hook draws its checkmark.
        PSTableCell *cell = [table dequeueReusableCellWithIdentifier:@"SidePress18ClickSpeed"];
        if (!cell) cell = [[PSTableCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:@"SidePress18ClickSpeed" specifier:specifier];
        cell.specifier = specifier;
        cell.textLabel.text = specifier.name;
        cell.textLabel.textColor = UIColor.labelColor;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        [cell setChecked:choice == SPClickSpeedChoice()];
        cell.accessibilityTraits = UIAccessibilityTraitButton |
            (choice == SPClickSpeedChoice() ? UIAccessibilityTraitSelected : 0);
        return cell;
    }
    UITableViewCell *cell = originalCell(self, cmd, table, indexPath);
    if (SPIsNativeSpeed(specifier) && SPClickSpeedChoice()) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessibilityTraits &= ~UIAccessibilityTraitSelected;
    }
    return cell;
}

static void SPSelect(id self, SEL cmd, UITableView *table, NSIndexPath *indexPath) {
    PSSpecifier *specifier = [(PSListController *)self specifierAtIndexPath:indexPath];
    NSInteger choice = SPChoiceForSpecifier(specifier);
    if (choice) {
        SPStoreSpeed(choice);
        PSSpecifier *group = objc_getAssociatedObject(self, &SPSpeedGroupAssociation);
        [group setProperty:specifier forKey:@"radioGroupCheckedSpecifier"];
        [table deselectRowAtIndexPath:indexPath animated:YES];
        [table reloadData];
        return;
    }
    // Clear first, so Apple's setter and selected-cell update run with their
    // normal Default/Slow/Slowest values and the native click speed takes over.
    BOOL nativeSpeed = SPIsNativeSpeed(specifier);
    if (nativeSpeed) SPStoreSpeed(0);
    originalSelect(self, cmd, table, indexPath);
    if (nativeSpeed) {
        // A native setter may return early when reselecting its existing value
        // (for example Default after Faster). Refresh the radio selection too.
        PSSpecifier *group = objc_getAssociatedObject(self, &SPSpeedGroupAssociation);
        [group setProperty:specifier forKey:@"radioGroupCheckedSpecifier"];
        [table reloadData];
    }
}

static BOOL SPInstallControllerHooks(Class cls) {
    if (speedControllerClass) return cls == speedControllerClass;
    if (!cls || cls == PSListController.class) return NO;
    if (!SPMethodHasObjectArguments(cls, @selector(tableView:cellForRowAtIndexPath:), '@', 4) ||
        !SPMethodHasObjectArguments(cls, @selector(tableView:didSelectRowAtIndexPath:), 'v', 4)) return NO;
    speedControllerClass = cls;
    MSHookMessageEx(cls, @selector(tableView:cellForRowAtIndexPath:), (IMP)SPCell, (IMP *)&originalCell);
    MSHookMessageEx(cls, @selector(tableView:didSelectRowAtIndexPath:), (IMP)SPSelect, (IMP *)&originalSelect);
    return YES;
}

static NSMutableArray *SPAddSpeedSpecifiers(id controller, NSArray *specifiers) {
    if (![controller isKindOfClass:PSListController.class] ||
        ![specifiers isKindOfClass:NSArray.class]) return (NSMutableArray *)specifiers;
    PSSpecifier *currentGroup = nil, *speedGroup = nil;
    NSUInteger defaults = NSNotFound, slow = NSNotFound, slowest = NSNotFound;
    NSUInteger index = 0;
    for (id object in specifiers) {
        if (![object isKindOfClass:PSSpecifier.class]) return (NSMutableArray *)specifiers;
        PSSpecifier *specifier = object;
        if (SPChoiceForSpecifier(specifier)) return (NSMutableArray *)specifiers;
        if (specifier.cellType == PSGroupCell) currentGroup = specifier;
        if ([specifier.identifier isEqualToString:SPDefaultSpeedID]) {
            defaults = index; speedGroup = currentGroup;
        }
        if ([specifier.identifier isEqualToString:SPSlowSpeedID] && currentGroup == speedGroup) slow = index;
        if ([specifier.identifier isEqualToString:SPSlowestSpeedID] && currentGroup == speedGroup) slowest = index;
        ++index;
    }
    // Require all three native rows in the same group, in the expected order.
    // Other lists, localized titles and unrelated Accessibility pages are untouched.
    if (!speedGroup || defaults == NSNotFound || slow != defaults + 1 ||
        slowest != slow + 1 || !SPInstallControllerHooks([controller class])) return (NSMutableArray *)specifiers;

    NSMutableArray *result = [specifiers mutableCopy];
    PSSpecifier *faster = [PSSpecifier preferenceSpecifierNamed:@"Faster" target:nil set:NULL get:NULL
                                                      detail:Nil cell:PSStaticTextCell edit:Nil];
    faster.identifier = SPFasterSpeedID;
    PSSpecifier *fastest = [PSSpecifier preferenceSpecifierNamed:@"Fastest" target:nil set:NULL get:NULL
                                                       detail:Nil cell:PSStaticTextCell edit:Nil];
    fastest.identifier = SPFastestSpeedID;
    // Insert at the end of this group. Apple's three speed rows retain their
    // existing index paths, as do all later sections (row indices are per group).
    [result insertObject:faster atIndex:slowest + 1];
    [result insertObject:fastest atIndex:slowest + 2];
    objc_setAssociatedObject(controller, &SPSpeedGroupAssociation, speedGroup, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSInteger choice = SPClickSpeedChoice();
    if (choice) [speedGroup setProperty:choice == 1 ? faster : fastest forKey:@"radioGroupCheckedSpecifier"];
    return result;
}

static NSMutableArray *SPLoad(id self, SEL cmd, NSString *name, id target) {
    return SPAddSpeedSpecifiers(self, originalLoad(self, cmd, name, target));
}

static NSMutableArray *SPLoadBundle(id self, SEL cmd, NSString *name, id target, NSBundle *bundle) {
    return SPAddSpeedSpecifiers(self, originalLoadBundle(self, cmd, name, target, bundle));
}

static void SPSetSpecifiers(id self, SEL cmd, NSArray *specifiers) {
    originalSetSpecifiers(self, cmd, SPAddSpeedSpecifiers(self, specifiers));
}

__attribute__((constructor)) static void SPClickSpeedSettingsStart(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"] ||
            !BTSupportsIOS17And18()) return;
        if (SPNeedsSeparateSideButtonTiming()) return;
        Class cls = PSListController.class;
        if (!SPMethodHasObjectArguments(cls, @selector(loadSpecifiersFromPlistName:target:), '@', 4) ||
            !SPMethodHasObjectArguments(cls, @selector(loadSpecifiersFromPlistName:target:bundle:), '@', 5) ||
            !SPMethodHasObjectArguments(cls, @selector(setSpecifiers:), 'v', 3)) return;
        MSHookMessageEx(PSListController.class, @selector(loadSpecifiersFromPlistName:target:),
                       (IMP)SPLoad, (IMP *)&originalLoad);
        MSHookMessageEx(PSListController.class, @selector(loadSpecifiersFromPlistName:target:bundle:),
                       (IMP)SPLoadBundle, (IMP *)&originalLoadBundle);
        MSHookMessageEx(PSListController.class, @selector(setSpecifiers:),
                       (IMP)SPSetSpecifiers, (IMP *)&originalSetSpecifiers);
    }
}
