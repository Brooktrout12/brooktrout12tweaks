#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "../Shared.h"

static void SPNotify(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), SP_CHANGED, NULL, NULL, YES);
}
static id SPObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}
static BOOL SPFlag(id object, NSString *name, BOOL fallback) {
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((BOOL (*)(id, SEL))objc_msgSend)(object, selector) : fallback;
}

@interface SPAppListController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, copy) NSArray<NSDictionary *> *apps;
@property(nonatomic, copy) NSArray<NSDictionary *> *filtered;
@property(nonatomic, strong) UISearchController *search;
@end

@implementation SPAppListController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Choose App";
    self.apps = @[]; self.filtered = @[];
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Search apps";
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.tableView.backgroundView = spinner; [spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY | RTLD_GLOBAL);
        id workspace = SPObject(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
        id applications = SPObject(workspace, @"allInstalledApplications");
        if (![applications isKindOfClass:NSArray.class]) applications = SPObject(workspace, @"allApplications");
        NSMutableArray *items = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        if ([applications isKindOfClass:NSArray.class]) for (id app in applications) {
            NSString *bundle = SPObject(app, @"bundleIdentifier");
            NSString *name = SPObject(app, @"localizedName");
            id tags = SPObject(app, @"appTags");
            if (![bundle isKindOfClass:NSString.class] || bundle.length == 0 || [seen containsObject:bundle]) continue;
            if (!SPFlag(app, @"isInstalled", YES) || SPFlag(app, @"isLaunchProhibited", NO)) continue;
            if ([tags respondsToSelector:@selector(containsObject:)] && [tags containsObject:@"hidden"]) continue;
            if (![name isKindOfClass:NSString.class] || name.length == 0) name = bundle;
            [items addObject:@{@"id": bundle, @"name": name}]; [seen addObject:bundle];
        }
        [items sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
            selector:@selector(localizedStandardCompare:)]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) controller = weakSelf;
            if (!controller) return;
            controller.apps = items;
            controller.tableView.backgroundView = nil;
            [controller updateSearchResultsForSearchController:controller.search];
            if (items.count == 0) {
                UILabel *label = [UILabel new]; label.text = @"No launchable apps were returned by iOS.";
                label.textAlignment = NSTextAlignmentCenter; label.numberOfLines = 0;
                label.textColor = UIColor.secondaryLabelColor;
                controller.tableView.backgroundView = label;
            }
        });
    });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    if (query.length == 0) self.filtered = self.apps;
    else {
        // NSBlockPredicate sends -copy to its block. On the legacy arm64e
        // toolchain a capturing stack block's ISA cannot receive ObjC messages.
        // No callback is needed to filter a local array.
        NSMutableArray *matches = [NSMutableArray array];
        for (NSDictionary *app in self.apps) {
            if ([app[@"name"] localizedCaseInsensitiveContainsString:query] ||
                [app[@"id"] localizedCaseInsensitiveContainsString:query]) [matches addObject:app];
        }
        self.filtered = matches;
    }
    [self.tableView reloadData];
}
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    NSDictionary *app = self.filtered[indexPath.row];
    cell.textLabel.text = app[@"name"]; cell.detailTextLabel.text = app[@"id"];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = [SPRead(@"AppID", @"") isEqual:app[@"id"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(__unused UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *app = self.filtered[indexPath.row];
    SPWrite(@"AppID", app[@"id"]); SPWrite(@"AppName", app[@"name"]); SPWrite(@"Action", @"app"); SPNotify();
    self.search.active = NO;
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface SPActionListController : UITableViewController
@end
@implementation SPActionListController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Double-Press Action"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return [SPSelectedAction() isEqualToString:@"app"] ? 2 : 1;
}
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? SPActionIDs().count : 1;
}
- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"Choose which app the Open App action opens.";
    return @"iOS Default restores the system’s double-click behavior. Media actions use the current audio player.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"chooseApp"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"chooseApp"];
        cell.textLabel.text = @"Choose App";
        id name = SPRead(@"AppName", @"No app selected");
        cell.detailTextLabel.text = [name isKindOfClass:NSString.class] ? name : @"No app selected";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
    cell.textLabel.text = SPActionNames()[indexPath.row];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    NSArray *symbols = @[@"iphone", @"camera.fill", @"flashlight.on.fill", @"app.fill", @"playpause.fill", @"forward.end.fill", @"backward.end.fill"];
    cell.imageView.image = [UIImage systemImageNamed:symbols[indexPath.row]];
    cell.accessoryType = [SPSelectedAction() isEqual:SPActionIDs()[indexPath.row]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self.navigationController pushViewController:[SPAppListController new] animated:YES];
        return;
    }
    NSString *selected = SPActionIDs()[indexPath.row];
    SPWrite(@"Action", selected); SPNotify();
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; [tableView reloadData];
}
@end

#import "../DeviceCapabilities.h"
#import "../ClickSpeed.h"

// Present in the iOS 17 Preferences runtime; the minimal Theos header omits it.
@interface PSSpecifier (SPClickSpeedValues)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles shortTitles:(NSArray *)shortTitles;
@end

@interface SPRootListController : PSListController
@end
@implementation SPRootListController
- (void)openSideButtonSettings {
    // Already inside Settings: push Apple's own controller instead of asking
    // UIApplication to reopen Preferences via an unsupported URL route.
    NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/AccessibilitySettings.bundle"];
    [bundle load];
    Class cls = NSClassFromString(@"ButtonClickController");
    if (cls && [cls isSubclassOfClass:PSListController.class]) {
        PSListController *controller = [[cls alloc] init];
        PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:@"Side Button" target:self
            set:NULL get:NULL detail:cls cell:PSLinkCell edit:Nil];
        link.identifier = @"HOME_CLICK_TITLE";
        controller.specifier = link;
        controller.parentController = self;
        controller.rootController = self.rootController;
        [self showController:controller animate:YES];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Side Button Settings"
        message:@"Open Settings → Accessibility → Side Button. The native settings page could not be loaded from this shortcut."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CFPreferencesAppSynchronize(SP_DOMAIN);
    self.title = @"SidePress18";
    [self reloadSpecifiers];
}
- (id)readValue:(PSSpecifier *)specifier { return SPRead([specifier propertyForKey:@"key"], [specifier propertyForKey:@"default"]); }
- (void)setValue:(id)value specifier:(PSSpecifier *)specifier { SPWrite([specifier propertyForKey:@"key"], value); SPNotify(); }
- (PSSpecifier *)toggle:(NSString *)title key:(NSString *)key defaultValue:(NSNumber *)value {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title target:self set:@selector(setValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSwitchCell edit:nil];
    [specifier setProperty:key forKey:@"key"]; [specifier setProperty:value forKey:@"default"];
    return specifier;
}
- (PSSpecifier *)group:(NSString *)title footer:(NSString *)footer {
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:title];
    if (footer) [group setProperty:footer forKey:@"footerText"];
    return group;
}
- (PSSpecifier *)button:(NSString *)title selector:(SEL)selector {
    PSSpecifier *button = [PSSpecifier preferenceSpecifierNamed:title target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    button.buttonAction = selector;
    return button;
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *selected = SPSelectedAction();
        NSString *appName = SPRead(@"AppName", @"No app selected");
        if (![appName isKindOfClass:NSString.class]) appName = @"No app selected";
        NSMutableArray *items = [NSMutableArray array];
        [items addObject:[self group:@"A shortcut at your fingertips" footer:@"Quickly press the side button twice, from an app, the Home Screen, or the Lock Screen."]];
        [items addObject:[self toggle:@"Enabled" key:@"Enabled" defaultValue:@YES]];
        [items addObject:[self group:@"Double Press" footer:[NSString stringWithFormat:@"Current action: %@", SPActionName(selected)]]];
        [items addObject:[self button:@"Choose Action" selector:@selector(chooseAction)]];
        if ([selected isEqualToString:@"app"]) {
            [items addObject:[self group:nil footer:[NSString stringWithFormat:@"Selected app: %@", appName]]];
            [items addObject:[self button:@"Choose App" selector:@selector(chooseApp)]];
        }
        [items addObject:[self group:@"When Locked" footer:@"On: authenticate with Touch ID, Face ID, or passcode before any selected action. Off: run the action while locked; apps open over the Lock Screen and return there when dismissed. Anyone holding the phone can use the chosen app and whatever content it exposes. An app’s own authentication and protected data still apply."]];
        [items addObject:[self toggle:@"Require Unlock" key:@"RequireUnlock" defaultValue:@NO]];
        if (SPNeedsSeparateSideButtonTiming()) {
            [items addObject:[self group:@"Feedback & Timing" footer:@"Choose the timing for SidePress18 here. Home button click speed stays in Accessibility. Faster choices require quicker double or triple presses; other system button gestures keep priority."]];
            PSSpecifier *speed = [PSSpecifier preferenceSpecifierNamed:@"Side Button Click Speed" target:self
                set:@selector(setValue:specifier:) get:@selector(readValue:) detail:NSClassFromString(@"PSListItemsController")
                cell:PSLinkListCell edit:Nil];
            [speed setProperty:SP_CLICK_SPEED_KEY forKey:@"key"];
            [speed setProperty:@0 forKey:@"default"];
            [speed setValues:@[@0, @1, @2] titles:@[@"iOS Default", @"Faster", @"Fastest"] shortTitles:nil];
            [items addObject:speed];
        } else {
            [items addObject:[self group:@"Feedback & Timing" footer:@"SidePress18 adds Faster and Fastest to Settings → Accessibility → Side Button. These shorten the wait after a single press and require quicker double or triple presses. The system’s other button gestures keep priority."]];
            [items addObject:[self button:@"Side Button Settings" selector:@selector(openSideButtonSettings)]];
        }
        [items addObject:[self toggle:@"Haptic Feedback" key:@"Haptic" defaultValue:@YES]];
        id result = SPRead(@"LastResult", @"Install and respring once to activate.");
        [items addObject:[self group:@"Last Result" footer:[result isKindOfClass:NSString.class] ? result : @"No result yet."]];
        [items addObject:[self button:@"Refresh Status" selector:@selector(refreshStatus)]];
        [items addObject:[self button:@"Copy Last Result" selector:@selector(copyLastResult)]];
        [items addObject:[self group:nil footer:@"SidePress18 1.0.1 • brooktrout12\niOS 17–18 • Rootless\nChanges take effect immediately."]];
        _specifiers = items;
    }
    return _specifiers;
}
- (void)chooseAction { [self.navigationController pushViewController:[SPActionListController new] animated:YES]; }
- (void)chooseApp { [self.navigationController pushViewController:[SPAppListController new] animated:YES]; }
- (void)refreshStatus { CFPreferencesAppSynchronize(SP_DOMAIN); [self reloadSpecifiers]; }
- (void)copyLastResult {
    CFPreferencesAppSynchronize(SP_DOMAIN);
    id result = SPRead(@"LastResult", @"No result yet.");
    id diagnostic = SPRead(@"LastSecureLaunchDiagnostic", @"");
    NSString *text = [result isKindOfClass:NSString.class] ? result : @"No result yet.";
    if ([diagnostic isKindOfClass:NSString.class] && [diagnostic length])
        text = [text stringByAppendingFormat:@"\n\nLast locked-app diagnostic:\n%@", diagnostic];
    for (NSString *key in @[@"LastClickSpeedConfiguration", @"LastTimingDiagnostic"]) {
        id timing = SPRead(key, @"");
        if ([timing isKindOfClass:NSString.class] && [timing length])
            text = [text stringByAppendingFormat:@"\n\n%@: %@", key, timing];
    }
    UIPasteboard.generalPasteboard.string = text;
}
@end
