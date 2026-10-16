#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <dlfcn.h>
#import "../BCCommon.h"

@interface BC18PrefsController : PSListController
@end

@implementation BC18PrefsController
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        self.title = @"Battery Capacity 18";
        NSMutableArray *items = [NSMutableArray array];
        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        [group setProperty:BCLocal(@"Adds battery capacities and current charge in mAh, capacity ratio in %, and current discharge rate in mA below Maximum Capacity in Battery Health.",
            @"Zeigt Batteriekapazitäten und aktuelle Ladung in mAh, das Kapazitätsverhältnis in % und den aktuellen Entladestrom in mA unter Maximale Kapazität im Batteriezustand.") forKey:@"footerText"];
        [items addObject:group];
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:BCLocal(@"Enable Tweak", @"Tweak aktivieren")
            target:self set:@selector(setValue:forSpecifier:) get:@selector(valueForSpecifier:)
            detail:Nil cell:PSSwitchCell edit:Nil];
        [enabled setProperty:@"Enabled" forKey:@"key"];
        [enabled setProperty:@YES forKey:@"default"];
        [items addObject:enabled];

        PSSpecifier *messageGroup = [PSSpecifier emptyGroupSpecifier];
        [messageGroup setProperty:BCLocal(@"Apple may show an Important Battery Message if it can’t verify the battery, for example after a replacement. This option only hides that message if it is shown.",
            @"Apple zeigt möglicherweise eine Wichtige Batterienachricht an, wenn die Batterie nicht verifiziert werden kann, zum Beispiel nach einem Austausch. Diese Option blendet nur diese Nachricht aus, falls sie angezeigt wird.") forKey:@"footerText"];
        [items addObject:messageGroup];
        PSSpecifier *hide = [PSSpecifier preferenceSpecifierNamed:BCLocal(@"Hide Battery Message", @"Batterienachricht ausblenden")
            target:self set:@selector(setValue:forSpecifier:) get:@selector(valueForSpecifier:)
            detail:Nil cell:PSSwitchCell edit:Nil];
        [hide setProperty:@"HideImportantBatteryMessage" forKey:@"key"];
        [hide setProperty:@NO forKey:@"default"];
        [hide setProperty:@(BCPreference(@"Enabled", YES)) forKey:@"enabled"];
        [items addObject:hide];

        PSSpecifier *about = [PSSpecifier groupSpecifierWithName:BCLocal(@"About the Reading", @"Zur Kapazitätsanzeige")];
        [about setProperty:BCLocal(@"Uses readings reported by the battery controller. These are controller estimates; a replacement or reprogrammed battery can report inaccurate values. Missing readings show Unavailable.\n\nFull Charge Capacity is how much the battery can hold when full. Current Charge is the charge remaining now, in mAh. Current Discharge Rate is how fast charge is leaving the battery, in mA. It shows Charging while current flows into the battery. Readings refresh every five seconds while you view them.\n\nBrooktrout12 · Version 1.0.5",
            @"Verwendet die vom Batteriecontroller gemeldeten Werte. Es handelt sich um Schätzwerte des Controllers. Ein Ersatzakku oder ein umprogrammierter Controller kann falsche Werte melden. Fehlende Werte werden als Nicht verfügbar angezeigt.\n\nVollladekapazität beschreibt die Kapazität bei voller Ladung. Aktuelle Ladung zeigt die momentan verbleibende Ladung in mAh. Aktueller Entladestrom zeigt, wie schnell Ladung aus der Batterie fließt, in mA. Fließt Strom in die Batterie, erscheint Wird geladen. Die Werte werden alle fünf Sekunden aktualisiert, solange die Batterieseite geöffnet ist.\n\nBrooktrout12 · Version 1.0.5") forKey:@"footerText"];
        [items addObject:about];
        PSSpecifier *copy = [PSSpecifier preferenceSpecifierNamed:BCLocal(@"Copy Battery Details", @"Batteriedetails kopieren")
            target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        copy.buttonAction = @selector(copyBatteryDetails);
        [items addObject:copy];
        _specifiers = items;
    }
    return _specifiers;
}
- (id)valueForSpecifier:(PSSpecifier *)specifier {
    return @(BCPreference([specifier propertyForKey:@"key"], [[specifier propertyForKey:@"default"] boolValue]));
}
- (void)setValue:(id)value forSpecifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)@([value boolValue]),
        (__bridge CFStringRef)BCPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)BCPrefsDomain);
    notify_post(BCChangedNotification);
    [self reloadSpecifiers];
}
- (void)copyBatteryDetails {
    NSString *(*copyText)(void) = (NSString *(*)(void))dlsym(RTLD_DEFAULT, "BC18CopyDiagnosticText");
    NSString *text = copyText ? copyText() : BCLocal(@"The tweak is not loaded in Settings. Close Settings completely and reopen it after installing.",
        @"Der Tweak ist nicht in Einstellungen geladen. Einstellungen nach der Installation vollständig schließen und erneut öffnen.");
    UIPasteboard.generalPasteboard.string = text;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:BCLocal(@"Copied", @"Kopiert")
        message:BCLocal(@"Battery details are on the clipboard. Nothing is sent automatically.",
            @"Die Batteriedetails wurden kopiert. Es wird nichts automatisch gesendet.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
