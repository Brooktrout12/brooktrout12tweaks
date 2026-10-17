#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../BSPreferences.h"

// Used by the native Preferences list picker; omitted by the minimal header.
@interface PSSpecifier (BSAnimationValues)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles shortTitles:(NSArray *)shortTitles;
@end

@interface BSRootListController : PSListController
@end
@implementation BSRootListController
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        self.title = @"BlurSleep";
        NSMutableArray *items = [NSMutableArray array];
        NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:BS_STATUS_PATH];
        BOOL current = [status[@"Version"] isEqual:BS_VERSION];
        PSSpecifier *statusGroup = [PSSpecifier groupSpecifierWithName:@"Status"];
        [statusGroup setProperty:current ? (status[@"Detail"] ?: @"")
            : @"No startup record for this version. Copy diagnostics if the animation remains inactive." forKey:@"footerText"];
        [items addObject:statusGroup];
        PSSpecifier *statusRow = [PSSpecifier preferenceSpecifierNamed:@"SpringBoard" target:self
            set:NULL get:@selector(readEngineStatus:) detail:Nil cell:PSTitleValueCell edit:Nil];
        [items addObject:statusRow];
        PSSpecifier *intro = [PSSpecifier groupSpecifierWithName:@"Lock animation"];
        [intro setProperty:@"Play the selected animation when you press the sleep button." forKey:@"footerText"];
        [items addObject:intro];
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"Enable BlurSleep" target:self
            set:@selector(setEnabled:specifier:) get:@selector(readEnabled:) detail:Nil cell:PSSwitchCell edit:Nil];
        [enabled setProperty:@YES forKey:@"default"];
        [items addObject:enabled];

        PSSpecifier *styleGroup = [PSSpecifier groupSpecifierWithName:@"Animation style"];
        [styleGroup setProperty:BSStyleDescription(BSReadStyle()) forKey:@"footerText"];
        [items addObject:styleGroup];
        PSSpecifier *style = [PSSpecifier preferenceSpecifierNamed:@"Animation" target:self
            set:@selector(setAnimationStyle:specifier:) get:@selector(readAnimationStyle:)
            detail:NSClassFromString(@"PSListItemsController") cell:PSLinkListCell edit:Nil];
        style.identifier = @"AnimationStyle";
        [style setProperty:@"com.brooktrout12.blursleep" forKey:@"defaults"];
        [style setProperty:@"AnimationStyle" forKey:@"key"];
        [style setProperty:@0 forKey:@"default"];
        NSMutableArray *styleValues = [NSMutableArray array];
        for (NSInteger i = 0; i < BSStyleCount; ++i) [styleValues addObject:@(i)];
        [style setValues:styleValues titles:BSStyleTitles() shortTitles:nil];
        [items addObject:style];

        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Animation duration"];
        [group setProperty:@"0.15–2.00 seconds. Shorter is faster; longer is slower. Release the slider to apply. Changes take effect the next time you lock." forKey:@"footerText"];
        [items addObject:group];
        PSSpecifier *value = [PSSpecifier preferenceSpecifierNamed:@"Duration" target:self
            set:NULL get:@selector(readDurationText:) detail:Nil cell:PSTitleValueCell edit:Nil];
        value.identifier = @"DurationValue"; [items addObject:value];
        PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:@"Animation duration" target:self
            set:@selector(setDuration:specifier:) get:@selector(readDuration:) detail:Nil cell:PSSliderCell edit:Nil];
        slider.identifier = @"Duration";
        [slider setProperty:@"com.brooktrout12.blursleep" forKey:@"defaults"];
        [slider setProperty:@"Duration" forKey:@"key"];
        [slider setProperty:@(BS_DEFAULT_DURATION) forKey:@"default"];
        [slider setProperty:@(BS_MIN_DURATION) forKey:@"min"];
        [slider setProperty:@(BS_MAX_DURATION) forKey:@"max"];
        [slider setProperty:@YES forKey:@"enabled"];
        [slider setProperty:@NO forKey:@"showValue"];
        [slider setProperty:@NO forKey:@"isContinuous"];
        [items addObject:slider];
        PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:@"Reset duration to 0.55 s" target:self
            set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        reset.buttonAction = @selector(resetDuration); [items addObject:reset];

        [items addObject:[PSSpecifier emptyGroupSpecifier]];
        PSSpecifier *preview = [PSSpecifier preferenceSpecifierNamed:@"Preview animation" target:self
            set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        preview.buttonAction = @selector(previewAnimation); [items addObject:preview];
        PSSpecifier *refresh = [PSSpecifier preferenceSpecifierNamed:@"Refresh status" target:self
            set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        refresh.buttonAction = @selector(refreshStatus); [items addObject:refresh];
        PSSpecifier *diagnostics = [PSSpecifier preferenceSpecifierNamed:@"Copy diagnostics" target:self
            set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        diagnostics.buttonAction = @selector(copyDiagnostics); [items addObject:diagnostics];
        PSSpecifier *about = [PSSpecifier emptyGroupSpecifier];
        [about setProperty:@"BlurSleep 1.2.0 · Brooktrout12\niOS 17–18 · Rootless\nPreview plays your selected animation without locking. All effects use the duration above." forKey:@"footerText"];
        [items addObject:about];
        _specifiers = items;
    }
    return _specifiers;
}
- (id)readEnabled:(PSSpecifier *)specifier { (void)specifier; return @(BSReadEnabled()); }
- (void)setEnabled:(NSNumber *)value specifier:(PSSpecifier *)specifier {
    (void)specifier; if ([value isKindOfClass:NSNumber.class]) BSWrite(@"Enabled",@(value.boolValue));
}
- (id)readDuration:(PSSpecifier *)specifier { (void)specifier; return @(BSReadDuration()); }
- (id)readAnimationStyle:(PSSpecifier *)specifier { (void)specifier; return @(BSReadStyle()); }
- (void)setAnimationStyle:(NSNumber *)value specifier:(PSSpecifier *)specifier {
    if (![value isKindOfClass:NSNumber.class]) return;
    NSNumber *selected = @(BSNormalizeStyle(value.longLongValue));
    [specifier setProperty:selected forKey:@"value"];
    BSWrite(@"AnimationStyle",selected);
}
- (id)readDurationText:(PSSpecifier *)specifier {
    (void)specifier; return [NSString stringWithFormat:@"%.2f s",BSReadDuration()];
}
- (void)setDuration:(NSNumber *)value specifier:(PSSpecifier *)specifier {
    if (![value isKindOfClass:NSNumber.class]) return;
    double duration = BSClampDuration(value.doubleValue);
    [specifier setProperty:@(duration) forKey:@"value"];
    BSWrite(@"Duration",@(duration));
    // Never replace/reload the slider while its thumb is being dragged.
    PSSpecifier *display = [self specifierForID:@"DurationValue"];
    if (display) [self reloadSpecifier:display animated:NO];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (void)resetDuration { BSWrite(@"Duration",@(BS_DEFAULT_DURATION)); [self reloadSpecifiers]; }
- (id)readEngineStatus:(PSSpecifier *)specifier {
    (void)specifier;
    NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:BS_STATUS_PATH];
    if (![status[@"Version"] isEqual:BS_VERSION]) return @"No startup record";
    return status[@"Stage"] ?: @"Unknown";
}
- (void)refreshStatus { [self reloadSpecifiers]; }
- (void)previewAnimation {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),BS_PREVIEW,NULL,NULL,true);
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshStatus) object:nil];
    [self performSelector:@selector(refreshStatus) withObject:nil afterDelay:BSReadDuration()+0.5];
}
- (void)copyDiagnostics {
    NSString *log = [NSString stringWithContentsOfFile:BS_LOG_PATH encoding:NSUTF8StringEncoding error:NULL];
    NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:BS_STATUS_PATH];
    UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"BlurSleep %@ Settings loaded\nOS: %@\nStatus: %@\n\n%@",
        BS_VERSION,NSProcessInfo.processInfo.operatingSystemVersionString,status ?: @{},
        log.length ? log : @"No SpringBoard log exists. The tweak library may not have loaded."];
    self.navigationItem.prompt = @"Diagnostics copied";
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearPrompt) object:nil];
    [self performSelector:@selector(clearPrompt) withObject:nil afterDelay:2];
}
- (void)clearPrompt { self.navigationItem.prompt = nil; }
@end
