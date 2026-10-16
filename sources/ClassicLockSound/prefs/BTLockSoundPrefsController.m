#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../BTPreferences.h"

@interface BTLockSoundPrefsController : PSListController
@end

@implementation BTLockSoundPrefsController
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        self.title = @"Classic Lock Sound";
        NSMutableArray *items = [NSMutableArray array];
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Volume"];
        [group setProperty:@"0% is silent. 100% uses the original recording at full level. Your iPhone’s ringer volume and Silent Mode still apply. Release the slider to apply the change to the next lock." forKey:@"footerText"];
        [items addObject:group];

        // Keep the percentage in a native value row. Do not reload or replace
        // the slider row while a finger is tracking its thumb.
        PSSpecifier *value = [PSSpecifier preferenceSpecifierNamed:@"Lock sound volume" target:self
            set:NULL get:@selector(readVolumeText:) detail:Nil cell:PSTitleValueCell edit:Nil];
        value.identifier = @"LockVolumeValue";
        [items addObject:value];

        // 1.0.7 embedded UISlider in a PSStaticTextCell, which is a display row.
        // Let Preferences own the interactive PSSliderCell, including hit
        // testing, layout, enabled state, tracking and accessibility.
        PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:@"Lock sound volume" target:self
            set:@selector(setVolume:specifier:) get:@selector(readVolume:)
            detail:Nil cell:PSSliderCell edit:Nil];
        slider.identifier = @"LockVolume";
        [slider setProperty:@"com.brooktrout12.classiclocksound" forKey:@"defaults"];
        [slider setProperty:@"VolumePercent" forKey:@"key"];
        [slider setProperty:@100 forKey:@"default"];
        [slider setProperty:@0 forKey:@"min"];
        [slider setProperty:@100 forKey:@"max"];
        [slider setProperty:@YES forKey:@"enabled"];
        [slider setProperty:@NO forKey:@"showValue"];
        [slider setProperty:@NO forKey:@"isContinuous"];
        [items addObject:slider];

        PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:@"Reset to 100%" target:self
            set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        reset.buttonAction = @selector(resetVolume);
        [items addObject:reset];
        PSSpecifier *about = [PSSpecifier emptyGroupSpecifier];
        [about setProperty:@"Classic Lock Sound 1.0.8 · Brooktrout12\niOS 17–18 · Rootless" forKey:@"footerText"];
        [items addObject:about];
        _specifiers = items;
    }
    return _specifiers;
}

- (NSNumber *)readVolume:(PSSpecifier *)specifier {
    (void)specifier;
    return @(BTReadVolume());
}

- (NSString *)readVolumeText:(PSSpecifier *)specifier {
    (void)specifier;
    return [NSString stringWithFormat:@"%d%%", BTReadVolume()];
}

- (void)setVolume:(NSNumber *)value specifier:(PSSpecifier *)specifier {
    if (![value isKindOfClass:NSNumber.class]) return;
    int percent = BTVolumePercent(value.doubleValue);
    [specifier setProperty:@(percent) forKey:@"value"];
    if (percent != BTReadVolume()) BTWriteVolume(percent);
    PSSpecifier *display = [self specifierForID:@"LockVolumeValue"];
    if (display) [self reloadSpecifier:display animated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (void)resetVolume {
    BTWriteVolume(100);
    [self reloadSpecifiers];
}
@end
