#import "Compatibility.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <stdlib.h>
#import "BCCommon.h"
#import "BCBatteryReader.h"
#import "WarningRules.h"

static BOOL gEnabled = YES;
static BOOL gHideMessage = NO;
static NSHashTable *gPages;
static NSMutableSet *gHookedClasses;
static char kPageState;
static char kRenderedWarning;
static id gLifecycleObserver;
static NSTimer *gChargeRefreshTimer;
static BOOL gApplicationActive;
static void BCUpdateChargeRefreshTimer(void);

typedef struct {
    Class cls;
    IMP original;
} BC18HookRecord;
static BC18HookRecord gSpecifierHooks[64];
static size_t gSpecifierHookCount;
static IMP gAppearOriginal;
static IMP gDisappearOriginal;
static IMP gLayoutOriginal;

@interface BC18PageState : NSObject
@property(nonatomic, copy) NSArray *baseline;
@property(nonatomic, copy) NSArray *lastApplied;
@property(nonatomic) BOOL transforming;
@property(nonatomic) Class activeHookClass;
@property(nonatomic) BOOL showing;
@property(nonatomic) BOOL hadMaximumRow;
@property(nonatomic) NSUInteger removedMessageSpecifiers;
@property(nonatomic) BOOL filteringQueued;
@property(nonatomic) NSUInteger renderedWarningDetections;
@property(nonatomic, strong) NSMutableSet<NSString *> *renderedWarningIDs;
@end
@implementation BC18PageState
@end

static BC18PageState *BCState(id page) {
    BC18PageState *state = objc_getAssociatedObject(page, &kPageState);
    if (!state) {
        state = [BC18PageState new];
        state.renderedWarningIDs = [NSMutableSet set];
        objc_setAssociatedObject(page, &kPageState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gPages addObject:page];
    }
    return state;
}

static NSString *BCNormalize(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *folded = [[text stringByFoldingWithOptions:NSDiacriticInsensitiveSearch
        locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]] lowercaseString];
    return [[folded componentsSeparatedByCharactersInSet:
        NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
}

static BOOL BCIsHealthClass(Class cls) {
    NSString *name = BCNormalize(NSStringFromClass(cls));
    return [name containsString:@"battery"] && [name containsString:@"health"]
        && ![name hasPrefix:@"bc18"];
}

static BOOL BCIsTarget(id page) {
    if (![page isKindOfClass:NSClassFromString(@"PSListController")]) return NO;
    for (Class cls = object_getClass(page); cls; cls = class_getSuperclass(cls)) {
        if (BCIsHealthClass(cls) || [NSStringFromClass(cls) isEqualToString:@"BatteryUIController"])
            return YES;
    }
    return NO;
}

static BOOL BCIsHealthPage(id page) {
    for (Class cls = object_getClass(page); cls; cls = class_getSuperclass(cls))
        if (BCIsHealthClass(cls)) return YES;
    return NO;
}

static void BCViewTexts(UIView *view, NSMutableArray *values, NSUInteger depth,
                        NSUInteger *budget) {
    if (!view || depth > 16 || !*budget) return;
    --*budget;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length) [values addObject:label.text];
        if (label.attributedText.length) [values addObject:label.attributedText.string];
    } else if ([view isKindOfClass:UITextView.class]) {
        UITextView *text = (UITextView *)view;
        if (text.text.length) [values addObject:text.text];
        if (text.attributedText.length) [values addObject:text.attributedText.string];
    } else if ([view isKindOfClass:UIButton.class]) {
        NSString *title = [(UIButton *)view currentTitle];
        if (title.length) [values addObject:title];
    }
    if ([view isKindOfClass:UITableViewCell.class]) {
        id configuration = [(UITableViewCell *)view contentConfiguration];
        if ([configuration isKindOfClass:UIListContentConfiguration.class]) {
            UIListContentConfiguration *content = configuration;
            if (content.text.length) [values addObject:content.text];
            if (content.secondaryText.length) [values addObject:content.secondaryText];
            if (content.attributedText.length) [values addObject:content.attributedText.string];
            if (content.secondaryAttributedText.length) [values addObject:content.secondaryAttributedText.string];
        }
    }
    for (UIView *child in view.subviews) BCViewTexts(child, values, depth + 1, budget);
}

static void BCPropertyTexts(id value, NSMutableArray *values, NSUInteger depth,
                            NSUInteger *budget) {
    if (!value || depth > 4 || !*budget) return;
    --*budget;
    if (object_isClass(value)) [values addObject:NSStringFromClass(value)];
    else if ([value isKindOfClass:NSString.class]) [values addObject:value];
    else if ([value isKindOfClass:NSAttributedString.class]) [values addObject:[value string]];
    else if ([value isKindOfClass:NSDictionary.class]) {
        for (id key in value) {
            BCPropertyTexts(value[key], values, depth + 1, budget);
        }
    } else if ([value isKindOfClass:NSArray.class]) {
        for (id item in value) BCPropertyTexts(item, values, depth + 1, budget);
    }
    /* Views are inspected only in the guarded layout pass below, so a newly
       configured cell cannot trigger filtering during an index-path lookup.
       No arbitrary getters, KVC, object descriptions, or private ivar walks. */
}

static NSArray<NSString *> *BCTexts(PSSpecifier *specifier) {
    NSMutableArray *values = [NSMutableArray array];
    if ([specifier.name isKindOfClass:NSString.class]) [values addObject:specifier.name];
    if ([specifier.identifier isKindOfClass:NSString.class]) [values addObject:specifier.identifier];
    NSUInteger budget = 256;
    BCPropertyTexts(specifier.properties, values, 0, &budget);
    return values;
}

static BOOL BCIsOurs(PSSpecifier *specifier) {
    return [specifier.identifier hasPrefix:@"BC18."];
}

static NSArray<NSString *> *BCAnchorTexts(PSSpecifier *specifier) {
    NSMutableArray *texts = [NSMutableArray array];
    if (specifier.name.length) [texts addObject:specifier.name];
    if (specifier.identifier.length) [texts addObject:specifier.identifier];
    for (NSString *key in @[@"id", @"label", @"key", @"get", @"title"]) {
        id value = [specifier propertyForKey:key];
        if ([value isKindOfClass:NSString.class]) [texts addObject:value];
    }
    return texts;
}

static BOOL BCIsMaximum(PSSpecifier *specifier) {
    if (specifier.cellType == PSGroupCell || BCIsOurs(specifier)) return NO;
    NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(@"BatteryUIResourceClass") ?: specifier.class];
    for (NSString *text in BCAnchorTexts(specifier)) {
        NSString *normalized = BCNormalize(text);
        if ([normalized containsString:@"maximumcapacity"] || [normalized containsString:@"maxcapacity"]
            || [normalized containsString:@"maximalekapazitat"]) return YES;
        for (NSString *key in @[@"MAXIMUM_CAPACITY", @"MAX_CAPACITY", @"BATTERY_HEALTH_MAXIMUM_CAPACITY"]) {
            NSString *localized = [bundle localizedStringForKey:key value:nil table:@"BatteryUI"];
            if (![localized isEqualToString:key] && [normalized isEqualToString:BCNormalize(localized)]) return YES;
        }
    }
    return NO;
}

static BOOL BCWarningText(NSString *text) {
    return BC18WarningText(BCNormalize(text).UTF8String);
}

static NSArray<NSString *> *BCLocalizedWarnings(void) {
    static NSBundle *cachedBundle;
    static NSArray *cached;
    Class resourceClass = NSClassFromString(@"BatteryUIResourceClass")
        ?: NSClassFromString(@"BatteryHealthUIController") ?: NSClassFromString(@"BatteryUIController");
    NSBundle *bundle = resourceClass ? [NSBundle bundleForClass:resourceClass] : nil;
    if (!bundle) return @[];
    if (cached && cachedBundle == bundle) return cached;
    NSMutableSet *texts = [NSMutableSet set];
    // Learn translated warning labels from the system's English localization,
    // so message matching doesn't depend only on the language of the screenshot.
    for (NSString *path in [bundle pathsForResourcesOfType:@"strings" inDirectory:nil forLocalization:@"en"]) {
        NSDictionary *english = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![english isKindOfClass:NSDictionary.class]) continue;
        NSString *table = path.lastPathComponent.stringByDeletingPathExtension;
        for (NSString *key in english) {
            if (BCWarningText(key) || BCWarningText(english[key])) {
                NSString *translated = [bundle localizedStringForKey:key value:nil table:table];
                if (translated.length > 4 && ![translated isEqualToString:key]) [texts addObject:BCNormalize(translated)];
            }
        }
    }
    for (NSString *key in @[@"IMPORTANT_BATTERY_MESSAGE", @"IMPORTANT_BATTERY_MESSAGE_TITLE",
        @"BATTERY_HEALTH_IMPORTANT_MESSAGE", @"NON_GENUINE_BATTERY_MESSAGE"]) {
        NSString *localized = [bundle localizedStringForKey:key value:nil table:@"BatteryUI"];
        if (![localized isEqualToString:key]) [texts addObject:BCNormalize(localized)];
    }
    cachedBundle = bundle;
    cached = texts.allObjects;
    return cached;
}

static BOOL BCAnyWarningText(NSArray<NSString *> *texts) {
    for (NSString *text in texts) {
        if (BCWarningText(text)) return YES;
        NSString *normalized = BCNormalize(text);
        for (NSString *translated in BCLocalizedWarnings())
            if (translated.length && [normalized containsString:translated]) return YES;
    }
    return NO;
}

static BOOL BCIsWarning(PSSpecifier *specifier, BC18PageState *state) {
    if (BCIsOurs(specifier)) return NO;
    if ([[specifier propertyForKey:@"bc18.clearedWarningGroup"] boolValue]) return NO;
    if ([objc_getAssociatedObject(specifier, &kRenderedWarning) boolValue]) return YES;
    if (specifier.identifier.length && [state.renderedWarningIDs containsObject:specifier.identifier]) return YES;
    return BCAnyWarningText(BCTexts(specifier));
}

static BOOL BCIsLearnMore(PSSpecifier *specifier) {
    for (NSString *text in BCTexts(specifier))
        if (BC18LearnMoreText(BCNormalize(text).UTF8String)) return YES;
    return NO;
}

static NSData *BCWarningActions(NSArray *specifiers, BC18PageState *state) {
    NSMutableData *flags = [NSMutableData dataWithLength:specifiers.count];
    unsigned char *f = flags.mutableBytes;
    for (NSUInteger i = 0; i < specifiers.count; ++i) {
        PSSpecifier *s = specifiers[i];
        BOOL group = s.cellType == PSGroupCell;
        BOOL warning = BCIsWarning(s, state);
        BOOL learnMore = BCIsLearnMore(s);
        BOOL protected = BCIsOurs(s) || BCIsMaximum(s) || s.cellType == PSSwitchCell
            || (!group && !warning && !learnMore);
        f[i] = (group ? BC18Group : 0) | (warning ? BC18Warning : 0)
            | (protected ? BC18Protected : 0) | (learnMore ? BC18LearnMore : 0);
    }
    NSMutableData *actions = [NSMutableData dataWithLength:specifiers.count];
    BC18PlanWarningRemoval(f, specifiers.count, actions.mutableBytes);
    return actions;
}

static PSSpecifier *BCEmptyWarningGroup(PSSpecifier *original) {
    PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
    group.identifier = original.identifier;
    [group setProperty:@YES forKey:@"bc18.clearedWarningGroup"];
    return group;
}

static NSMutableArray *BCHideWarningGroups(NSArray *specifiers, BC18PageState *state) {
    NSMutableArray *output = [NSMutableArray array];
    NSData *plan = BCWarningActions(specifiers, state);
    const unsigned char *actions = plan.bytes;
    for (NSUInteger i = 0; i < specifiers.count; ++i) {
        if (actions[i] == BC18Keep) [output addObject:specifiers[i]];
        else if (actions[i] == BC18ClearGroup) [output addObject:BCEmptyWarningGroup(specifiers[i])];
    }
    return output;
}

static id BCCapacityValue(__unused id self, __unused SEL selector, PSSpecifier *specifier) {
    return [[BC18BatteryReader shared] valueForMetric:[specifier propertyForKey:@"bc18.metric"]];
}

static NSArray *BCCapacityRows(id page) {
    NSArray *labels = @[BCLocal(@"Full Charge Capacity", @"Vollladekapazität"),
        BCLocal(@"Design Capacity", @"Designkapazität"),
        BCLocal(@"Capacity vs. Design", @"Anteil der Designkapazität"),
        BCLocal(@"Current Charge", @"Aktuelle Ladung"),
        BCLocal(@"Current Discharge Rate", @"Aktueller Entladestrom")];
    NSArray *metrics = @[@"full", @"design", @"ratio", @"current", @"discharge"];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < metrics.count; i++) {
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:labels[i] target:page set:NULL
            get:@selector(bc18_capacityValue:) detail:Nil cell:PSTitleValueCell edit:Nil];
        row.identifier = [@"BC18." stringByAppendingString:metrics[i]];
        [row setProperty:metrics[i] forKey:@"bc18.metric"];
        [row setProperty:@YES forKey:@"isCopyable"];
        [row setProperty:@YES forKey:@"adjustFontSizeToFitWidth"];
        [row setProperty:@YES forKey:@"prioritizeValueTextDisplay"];
        [rows addObject:row];
    }
    return rows;
}

static BOOL BCHasHealthLink(NSArray *specifiers) {
    for (PSSpecifier *s in specifiers) {
        if (s.detailControllerClass && BCIsHealthClass(s.detailControllerClass)) return YES;
        if (s.cellType != PSLinkCell && s.cellType != PSLinkListCell) continue;
        for (NSString *text in BCAnchorTexts(s))
            if ([BCNormalize(text) containsString:@"batteryhealth"]) return YES;
    }
    return NO;
}

static NSArray *BCTransform(id page, NSArray *raw) {
    if (![raw isKindOfClass:NSArray.class]) return raw;
    for (id object in raw) if (![object isKindOfClass:PSSpecifier.class]) return raw;
    BC18PageState *state = BCState(page);
    NSArray *baseline;
    if (state.lastApplied && [raw isEqualToArray:state.lastApplied]) baseline = state.baseline;
    else {
        NSMutableArray *clean = [NSMutableArray array];
        for (PSSpecifier *s in raw) if (!BCIsOurs(s)) [clean addObject:s];
        baseline = [clean copy];
        state.baseline = baseline;
    }
    NSMutableArray *output = [baseline mutableCopy];
    state.removedMessageSpecifiers = 0;
    state.hadMaximumRow = NO;
    if (gEnabled) {
        if (gHideMessage) {
            output = BCHideWarningGroups(output, state);
            state.removedMessageSpecifiers = baseline.count - output.count;
        }
        NSUInteger maximum = NSNotFound;
        for (NSUInteger i = 0; i < output.count; i++) {
            if (BCIsMaximum(output[i])) { maximum = i; break; }
        }
        state.hadMaximumRow = maximum != NSNotFound;
        if (maximum != NSNotFound) {
            NSArray *rows = BCCapacityRows(page);
            [output insertObjects:rows
                atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(maximum + 1, rows.count)]];
        } else if (BCIsHealthPage(page) || !BCHasHealthLink(output)) {
            // If Apple omits Maximum Capacity or the model has no Health page,
            // make the raw readings available in a clearly named section.
            PSSpecifier *group = [PSSpecifier groupSpecifierWithName:BCLocal(@"Battery Capacity", @"Batteriekapazität")];
            group.identifier = @"BC18.group";
            [group setProperty:BCLocal(@"Full-charge capacity reported by the battery controller, compared with its reported design capacity.",
                @"Vom Batteriecontroller gemeldete Vollladekapazität im Vergleich zur gemeldeten Designkapazität.") forKey:@"footerText"];
            [output addObject:group];
            [output addObjectsFromArray:BCCapacityRows(page)];
        }
    }
    state.lastApplied = [output copy];
    if ([raw isKindOfClass:NSMutableArray.class]) {
        if (![raw isEqualToArray:output]) [(NSMutableArray *)raw setArray:output];
        return raw;
    }
    // Some OS builds return immutable arrays. Keep the controller's own cache
    // consistent, and honour ARC ownership instead of writing an ivar offset.
    Ivar ivar = class_getInstanceVariable(object_getClass(page), "_specifiers");
    if (ivar && ivar_getTypeEncoding(ivar)[0] == '@' && object_getIvar(page, ivar) == raw)
        object_setIvarWithStrongDefault(page, ivar, output);
    return output;
}

static BC18HookRecord *BCFindSpecifierHook(Class cls) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        for (size_t i = 0; i < gSpecifierHookCount; i++)
            if (gSpecifierHooks[i].cls == current) return &gSpecifierHooks[i];
    }
    return NULL;
}

static id BCSpecifiersHook(id page, SEL selector) {
    BC18PageState *state = BCState(page);
    Class previousClass = state.activeHookClass;
    BOOL wasTransforming = state.transforming;
    // If an overridden method calls super, use that superclass's saved IMP.
    // This preserves hook chains without compiler-generated block trampolines.
    BC18HookRecord *record = BCFindSpecifierHook(previousClass
        ? class_getSuperclass(previousClass) : object_getClass(page));
    if (!record || !record->original) return state.lastApplied ?: state.baseline ?: @[];
    state.activeHookClass = record->cls;
    state.transforming = YES;
    id result;
    @try {
        id raw = ((id (*)(id, SEL))record->original)(page, selector);
        result = (wasTransforming || state.filteringQueued) ? raw : BCTransform(page, raw);
    } @finally {
        state.activeHookClass = previousClass;
        state.transforming = wasTransforming;
    }
    return result;
}

static void BCInstallClass(Class cls) {
    if (!cls || gSpecifierHookCount == sizeof(gSpecifierHooks) / sizeof(gSpecifierHooks[0])) return;
    for (size_t i = 0; i < gSpecifierHookCount; i++) if (gSpecifierHooks[i].cls == cls) return;
    // Reuse an existing ancestor hook for inherited implementations. If none
    // exists, install at this concrete battery controller, never globally on
    // PSListController.specifiers.
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    BOOL declaredHere = NO;
    for (unsigned int i = 0; i < methodCount; i++)
        if (method_getName(methods[i]) == @selector(specifiers)) declaredHere = YES;
    free(methods);
    if (!declaredHere && BCFindSpecifierHook(class_getSuperclass(cls))) return;
    Method method = class_getInstanceMethod(cls, @selector(specifiers));
    if (!method || method_getNumberOfArguments(method) != 2) return;
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != '@') return;
    class_addMethod(cls, @selector(bc18_capacityValue:), (IMP)BCCapacityValue, "@@:@");
    BC18HookRecord *record = &gSpecifierHooks[gSpecifierHookCount++];
    record->cls = cls;
    MSHookMessageEx(cls, @selector(specifiers), (IMP)BCSpecifiersHook, &record->original);
    [gHookedClasses addObject:NSStringFromClass(cls)];
}

static void BCInstallKnownClasses(void) {
    BCInstallClass(NSClassFromString(@"BatteryHealthUIController"));
    BCInstallClass(NSClassFromString(@"BatteryUIController"));
}

static void BCRefreshRows(void) {
    if (!gEnabled) return;
    [[BC18BatteryReader shared] refresh];
}

static void BCReloadReadings(void) {
    if (!gEnabled) return;
    for (PSListController *page in gPages.allObjects) {
        if (!BCState(page).showing) continue;
        for (NSString *identifier in @[@"BC18.full", @"BC18.design", @"BC18.ratio", @"BC18.current", @"BC18.discharge"])
            if ([page specifierForID:identifier]) [page reloadSpecifierID:identifier animated:NO];
    }
}

static void BCRestoreAndReload(PSListController *page) {
    BC18PageState *state = BCState(page);
    Ivar ivar = class_getInstanceVariable(object_getClass(page), "_specifiers");
    if (state.baseline && ivar && ivar_getTypeEncoding(ivar)[0] == '@')
        object_setIvarWithStrongDefault(page, ivar, [state.baseline mutableCopy]);
    state.lastApplied = nil;
    state.baseline = nil;
    [page reloadSpecifiers];
}

static NSArray *BCCachedSpecifiers(PSListController *page) {
    Ivar ivar = class_getInstanceVariable(object_getClass(page), "_specifiers");
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') return nil;
    id raw = object_getIvar(page, ivar);
    if (![raw isKindOfClass:NSArray.class]) return nil;
    for (id object in raw) if (![object isKindOfClass:PSSpecifier.class]) return nil;
    return [raw copy];
}

static UITableView *BCPageTable(UIViewController *page) {
    /* PSListController's private table/tableView accessors differ between OS
       builds. Inspect only the already-loaded public UIKit view hierarchy. */
    UIView *root = page.viewIfLoaded;
    if (!root) return nil;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    UITableView *ownedTable = nil;
    NSUInteger ownedCount = 0;
    for (NSUInteger i = 0; i < pending.count && i < 512; ++i) {
        UIView *view = pending[i];
        if ([view isKindOfClass:UITableView.class]) {
            UITableView *table = (UITableView *)view;
            if ((id)table.dataSource == page || (id)table.delegate == page) return table;
            UIResponder *owner = table.nextResponder;
            while (owner && ![owner isKindOfClass:UIViewController.class]) owner = owner.nextResponder;
            if (owner == page) { ownedTable = table; ++ownedCount; }
            // A table's cells can contain unrelated nested tables.
            continue;
        }
        if (pending.count + view.subviews.count > 512) return nil;
        [pending addObjectsFromArray:view.subviews];
    }
    // A delegate/data-source proxy is allowed only when ownership is unambiguous.
    return ownedCount == 1 ? ownedTable : nil;
}

static BOOL BCWarningMutationMethodsAvailable(PSListController *page) {
    return [page respondsToSelector:@selector(removeContiguousSpecifiers:animated:)]
        && [page respondsToSelector:@selector(replaceContiguousSpecifiers:withSpecifiers:animated:)];
}

static void BCFilterRenderedWarnings(void *context) {
    @autoreleasepool {
        PSListController *page = CFBridgingRelease(context);
        BC18PageState *state = BCState(page);
        @try {
            if (!gEnabled || !gHideMessage || state.transforming) return;
            if (!BCWarningMutationMethodsAvailable(page)) return;
            NSArray *current = BCCachedSpecifiers(page);
            if (!current.count) return;
            NSData *plan = BCWarningActions(current, state);
            const unsigned char *actions = plan.bytes;
            BOOL changed = NO;
            for (NSUInteger i = 0; i < current.count; ++i)
                if (actions[i] != BC18Keep) { changed = YES; break; }
            if (!changed) return;

            /* UITableView can ask for specifiers inside an update. Let the
               original controller answer during these normal Preferences API
               mutations, so the getter hook cannot change its array mid-update. */
            state.transforming = YES;
            @try {
                for (NSUInteger end = current.count; end > 0;) {
                    NSUInteger i = end - 1;
                    if (actions[i] == BC18Remove) {
                        NSUInteger start = i;
                        while (start > 0 && actions[start - 1] == BC18Remove) --start;
                        [page removeContiguousSpecifiers:[current subarrayWithRange:
                            NSMakeRange(start, end - start)] animated:NO];
                        state.removedMessageSpecifiers += end - start;
                        end = start;
                    } else {
                        if (actions[i] == BC18ClearGroup)
                            [page replaceContiguousSpecifiers:@[current[i]]
                                withSpecifiers:@[BCEmptyWarningGroup(current[i])] animated:NO];
                        end = i;
                    }
                }
                state.lastApplied = BCCachedSpecifiers(page);
            } @finally {
                state.transforming = NO;
            }
        } @finally {
            state.filteringQueued = NO;
        }
    }
}

static BOOL BCViewIsWarning(UIView *view) {
    NSMutableArray *texts = [NSMutableArray array];
    NSUInteger budget = 256;
    BCViewTexts(view, texts, 0, &budget);
    return BCAnyWarningText(texts);
}

static void BCInspectRenderedWarnings(PSListController *page) {
    if (!gEnabled || !gHideMessage) return;
    BC18PageState *state = BCState(page);
    if (!state.showing || state.transforming || state.filteringQueued) return;
    UITableView *table = BCPageTable(page);
    if (!table || !BCWarningMutationMethodsAvailable(page)) return;

    state.transforming = YES;
    @try {
        /* Resolve every index before marking anything. A lookup can call the
           specifiers getter; never change its filter policy halfway through a scan. */
        NSMutableSet *detected = [NSMutableSet set];
        for (UITableViewCell *cell in table.visibleCells) {
            if (!BCViewIsWarning(cell)) continue;
            NSIndexPath *path = [table indexPathForCell:cell];
            if (!path) continue;
            PSSpecifier *s = nil;
            if ([page respondsToSelector:@selector(specifierAtIndexPath:)])
                s = [page specifierAtIndexPath:path];
            else {
                // Some implementations expose the cached cell instead.
                for (PSSpecifier *candidate in BCCachedSpecifiers(page))
                    if ([candidate propertyForKey:@"cellObject"] == cell) { s = candidate; break; }
            }
            if ([s isKindOfClass:PSSpecifier.class] && !BCIsOurs(s)) [detected addObject:s];
        }
        for (NSInteger section = 0; section < table.numberOfSections; ++section) {
            UIView *header = [table headerViewForSection:section];
            UIView *footer = [table footerViewForSection:section];
            if (!BCViewIsWarning(header) && !BCViewIsWarning(footer)) continue;
            if (![page respondsToSelector:@selector(indexOfGroup:)]
                || ![page respondsToSelector:@selector(specifierAtIndex:)]) continue;
            NSInteger index = [page indexOfGroup:section];
            if (index < 0 || (NSUInteger)index >= BCCachedSpecifiers(page).count) continue;
            PSSpecifier *s = [page specifierAtIndex:index];
            if ([s isKindOfClass:PSSpecifier.class] && s.cellType == PSGroupCell && !BCIsOurs(s))
                [detected addObject:s];
        }
        for (PSSpecifier *s in detected) {
            if (![objc_getAssociatedObject(s, &kRenderedWarning) boolValue]) ++state.renderedWarningDetections;
            objc_setAssociatedObject(s, &kRenderedWarning, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (s.identifier.length) [state.renderedWarningIDs addObject:s.identifier];
        }

        /* This also catches specifiers added asynchronously after the getter's
           first pass, even when their text already exists in normal properties. */
        NSArray *current = BCCachedSpecifiers(page);
        NSData *plan = BCWarningActions(current ?: @[], state);
        const unsigned char *actions = plan.bytes;
        for (NSUInteger i = 0; i < current.count; ++i) {
            if (actions[i] == BC18Keep) continue;
            state.filteringQueued = YES;
            dispatch_async_f(dispatch_get_main_queue(), (__bridge_retained void *)page, BCFilterRenderedWarnings);
            break;
        }
    } @finally {
        state.transforming = NO;
    }
}

static void BCLayoutHook(PSListController *page, SEL selector) {
    ((void (*)(id, SEL))gLayoutOriginal)(page, selector);
    if (BCIsTarget(page)) BCInspectRenderedWarnings(page);
}

static void BCApplyPreferencesOnMain(__unused void *context) {
    @autoreleasepool {
        CFPreferencesAppSynchronize((__bridge CFStringRef)BCPrefsDomain);
        gEnabled = BCPreference(@"Enabled", YES);
        gHideMessage = BCPreference(@"HideImportantBatteryMessage", NO);
        for (PSListController *page in gPages.allObjects) BCRestoreAndReload(page);
        BCUpdateChargeRefreshTimer();
        BCRefreshRows();
    }
}

static void BCPreferencesChanged(__unused CFNotificationCenterRef center, __unused void *observer,
    __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
    dispatch_async_f(dispatch_get_main_queue(), NULL, BCApplyPreferencesOnMain);
}

__attribute__((visibility("default"))) NSString *BC18CopyDiagnosticText(void) {
    NSMutableString *text = [[[BC18BatteryReader shared] diagnosticText] mutableCopy];
    [text appendFormat:@"Enabled: %@\nHide message: %@\nHooked controllers: %@\n",
        gEnabled ? @"Yes" : @"No", gHideMessage ? @"Yes" : @"No", gHookedClasses.allObjects];
    for (PSListController *page in gPages.allObjects) {
        BC18PageState *state = BCState(page);
        [text appendFormat:@"Page: %@; Maximum Capacity anchor: %@; hidden message elements: %lu; rendered detections: %lu\n",
            NSStringFromClass(page.class), state.hadMaximumRow ? @"Found" : @"Not found",
            (unsigned long)state.removedMessageSpecifiers, (unsigned long)state.renderedWarningDetections];
        NSMutableArray *identifiers = [NSMutableArray array];
        for (PSSpecifier *s in state.baseline) {
            id cellClass = [s propertyForKey:@"cellClass"];
            NSString *className = object_isClass(cellClass) ? NSStringFromClass(cellClass)
                : ([cellClass isKindOfClass:NSString.class] ? cellClass : @"");
            [identifiers addObject:@{@"id": s.identifier ?: @"", @"label": s.name ?: @"",
                @"cellType": @(s.cellType), @"cellClass": className,
                @"propertyKeys": s.properties.allKeys ?: @[],
                @"recognizedWarning": @(BCIsWarning(s, state))}];
        }
        [text appendFormat:@"Battery page specifiers: %@\n", identifiers];
    }
    return text;
}

static void BCAppearHook(PSListController *page, SEL selector, BOOL animated) {
    BOOL target = BCIsTarget(page);
    if (target) {
        gApplicationActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        BCInstallClass(object_getClass(page));
        BCState(page).showing = YES;
    }
    ((void (*)(id, SEL, BOOL))gAppearOriginal)(page, selector, animated);
    if (target) {
        BCRestoreAndReload(page);
        BCRefreshRows();
        BCUpdateChargeRefreshTimer();
    }
}

static void BCDisappearHook(PSListController *page, SEL selector, BOOL animated) {
    if (BCIsTarget(page)) BCState(page).showing = NO;
    ((void (*)(id, SEL, BOOL))gDisappearOriginal)(page, selector, animated);
    BCUpdateChargeRefreshTimer();
}

static void BCInstallAfterBundleLoad(__unused void *context) {
    @autoreleasepool { BCInstallKnownClasses(); }
}

static void BCRefreshAfterForeground(__unused void *context) {
    @autoreleasepool {
        for (PSListController *page in gPages.allObjects) {
            if (BCState(page).showing) { BCRefreshRows(); break; }
        }
    }
}

static BOOL BCVisibleChargePage(void) {
    for (PSListController *page in gPages.allObjects) {
        BC18PageState *state = BCState(page);
        if (!state.showing) continue;
        for (PSSpecifier *s in state.lastApplied)
            if ([s.identifier isEqualToString:@"BC18.current"]) return YES;
    }
    return NO;
}

static void BCUpdateChargeRefreshTimer(void) {
    BOOL needed = gEnabled && gApplicationActive && BCVisibleChargePage();
    if (!needed) {
        [gChargeRefreshTimer invalidate];
        gChargeRefreshTimer = nil;
    } else if (!gChargeRefreshTimer) {
        // A selector-based timer avoids the legacy compiler's block-object ABI.
        gChargeRefreshTimer = [NSTimer timerWithTimeInterval:5.0 target:gLifecycleObserver
            selector:@selector(chargeRefreshTimerFired:) userInfo:nil repeats:YES];
        gChargeRefreshTimer.tolerance = 1.0;
        [NSRunLoop.mainRunLoop addTimer:gChargeRefreshTimer forMode:NSRunLoopCommonModes];
    }
}

@interface BC18LifecycleObserver : NSObject
- (void)bundleLoaded:(NSNotification *)notification;
- (void)enteringForeground:(NSNotification *)notification;
- (void)readingChanged:(NSNotification *)notification;
- (void)applicationBecameActive:(NSNotification *)notification;
- (void)applicationResigningActive:(NSNotification *)notification;
- (void)chargeRefreshTimerFired:(NSTimer *)timer;
@end

@implementation BC18LifecycleObserver
- (void)bundleLoaded:(__unused NSNotification *)notification {
    dispatch_async_f(dispatch_get_main_queue(), NULL, BCInstallAfterBundleLoad);
}
- (void)enteringForeground:(__unused NSNotification *)notification {
    dispatch_async_f(dispatch_get_main_queue(), NULL, BCRefreshAfterForeground);
}
- (void)readingChanged:(__unused NSNotification *)notification {
    BCReloadReadings(); // Reader posts this notification on the main queue.
    BCUpdateChargeRefreshTimer();
}
- (void)applicationBecameActive:(__unused NSNotification *)notification {
    gApplicationActive = YES;
    BCUpdateChargeRefreshTimer();
    if (gChargeRefreshTimer) BCRefreshRows();
}
- (void)applicationResigningActive:(__unused NSNotification *)notification {
    gApplicationActive = NO;
    BCUpdateChargeRefreshTimer();
}
- (void)chargeRefreshTimerFired:(__unused NSTimer *)timer {
    BCUpdateChargeRefreshTimer();
    if (gChargeRefreshTimer) BCRefreshRows();
}
@end

__attribute__((constructor)) static void BCInitialize(void) {
    @autoreleasepool {
        if (!BTSupportsIOS17And18()) return;
        gPages = [NSHashTable weakObjectsHashTable];
        gHookedClasses = [NSMutableSet set];
        gEnabled = BCPreference(@"Enabled", YES);
        gHideMessage = BCPreference(@"HideImportantBatteryMessage", NO);
        BCInstallKnownClasses();
        // Selector observers are ordinary runtime-allocated Objective-C objects.
        // No compiler-generated block objects are passed to Foundation/CF.
        gLifecycleObserver = [BC18LifecycleObserver new];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:gLifecycleObserver selector:@selector(bundleLoaded:)
            name:NSBundleDidLoadNotification object:nil];
        [center addObserver:gLifecycleObserver selector:@selector(enteringForeground:)
            name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:gLifecycleObserver selector:@selector(readingChanged:)
            name:BCReadingChangedNotification object:nil];
        [center addObserver:gLifecycleObserver selector:@selector(applicationBecameActive:)
            name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:gLifecycleObserver selector:@selector(applicationResigningActive:)
            name:UIApplicationWillResignActiveNotification object:nil];
        Class listClass = NSClassFromString(@"PSListController");
        if (listClass) {
            MSHookMessageEx(listClass, @selector(viewWillAppear:), (IMP)BCAppearHook, &gAppearOriginal);
            MSHookMessageEx(listClass, @selector(viewDidDisappear:), (IMP)BCDisappearHook, &gDisappearOriginal);
            MSHookMessageEx(listClass, @selector(viewDidLayoutSubviews), (IMP)BCLayoutHook, &gLayoutOriginal);
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, BCPreferencesChanged,
            (__bridge CFStringRef)@(BCChangedNotification), NULL, CFNotificationSuspensionBehaviorCoalesce);
    }
}
