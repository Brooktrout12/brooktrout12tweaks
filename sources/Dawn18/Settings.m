#import <UIKit/UIKit.h>
#import <Preferences/PSViewController.h>
#import "Preferences.h"
#import "Preview.h"
#import <notify.h>

@interface D18OptionCell : UITableViewCell
@property(nonatomic, strong) UILabel *optionTitle;
@property(nonatomic, strong) UIImageView *symbol;
@property(nonatomic, strong) UISegmentedControl *selector;
@end

@implementation D18OptionCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _optionTitle = [UILabel new];
    _optionTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _optionTitle.adjustsFontForContentSizeCategory = YES;
    _optionTitle.textColor = UIColor.labelColor;
    _optionTitle.numberOfLines = 0;
    _symbol = [UIImageView new];
    _symbol.contentMode = UIViewContentModeScaleAspectFit;
    _symbol.tintColor = UIColor.labelColor;
    _symbol.isAccessibilityElement = NO;
    [_symbol.widthAnchor constraintEqualToConstant:24].active = YES;
    [_symbol.heightAnchor constraintEqualToConstant:24].active = YES;
    UIStackView *title = [[UIStackView alloc] initWithArrangedSubviews:@[_symbol, _optionTitle]];
    title.axis = UILayoutConstraintAxisHorizontal;
    title.alignment = UIStackViewAlignmentCenter;
    title.spacing = 10;
    _selector = [[UISegmentedControl alloc] initWithItems:@[@"Default", @"Light", @"Dark"]];
    [_selector.heightAnchor constraintGreaterThanOrEqualToConstant:36].active = YES;
    _selector.accessibilityHint = @"Default uses the normal appearance. Light or Dark overrides it.";
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, _selector]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14]
    ]];
    return self;
}
@end

@interface D18RootController : PSViewController <UITableViewDataSource, UITableViewDelegate> {
    D18Configuration _configuration;
    NSOperationQueue *_preferencesQueue;
    int _previewReplyToken;
    BOOL _previewReplyRegistered;
    BOOL _previewPending;
    uint32_t _previewRequestID;
    NSString *_previewStatus;
}
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) NSArray<NSDictionary *> *options;
@property(nonatomic, strong) UIView *heading;
@end

@implementation D18RootController
- (void)loadView {
    self.title = @"Dawn 18";
    _options = @[
        @{@"title": @"Applications", @"symbol": @"app", @"element": @(D18Applications)},
        @{@"title": @"Folders", @"symbol": @"folder", @"element": @(D18Folders)},
        @{@"title": @"Dock", @"symbol": @"dock.rectangle", @"element": @(D18Dock)},
        @{@"title": @"Widgets", @"symbol": @"rectangle.on.rectangle", @"element": @(D18Widgets)},
        @{@"title": @"App Library", @"symbol": @"square.grid.2x2", @"element": @(D18AppLibrary)},
        @{@"title": @"Home Screen Quick Actions", @"symbol": @"hand.tap", @"element": @(D18QuickActions)},
        @{@"title": @"Ringer", @"symbol": @"speaker.wave.2", @"element": @(D18RingerVolume)},
        @{@"title": @"Banners", @"symbol": @"rectangle.topthird.inset.filled", @"element": @(D18Banners)},
        @{@"title": @"Notifications", @"symbol": @"bell.badge", @"element": @(D18Notifications)},
        @{@"title": @"Notification Center Buttons", @"symbol": @"xmark.circle", @"element": @(D18Buttons)}
    ];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 102;
    _table.userInteractionEnabled = NO;
    [_table registerClass:D18OptionCell.class forCellReuseIdentifier:@"appearance"];
    self.view = _table;
    [self buildHeading];
}

- (void)buildHeading {
    _heading = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 390, 138)];
    UILabel *title = [UILabel new];
    title.text = @"Dawn 18";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    title.adjustsFontForContentSizeCategory = YES;
    title.textColor = UIColor.labelColor;
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    title.numberOfLines = 0;
    UIImageView *symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"circle.lefthalf.filled"]];
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    symbol.tintColor = UIColor.labelColor;
    [symbol.widthAnchor constraintEqualToConstant:42].active = YES;
    [symbol.heightAnchor constraintEqualToConstant:42].active = YES;
    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[title, symbol]];
    titleRow.axis = UILayoutConstraintAxisHorizontal;
    titleRow.alignment = UIStackViewAlignmentCenter;
    titleRow.spacing = 16;
    UILabel *subtitle = [UILabel new];
    subtitle.text = @"Choose a light or dark appearance for each part of iOS.";
    subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    subtitle.adjustsFontForContentSizeCategory = YES;
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.numberOfLines = 0;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, subtitle]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_heading addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:_heading.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:_heading.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:_heading.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:_heading.bottomAnchor constant:-18]
    ]];
    _table.tableHeaderView = _heading;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _preferencesQueue = [NSOperationQueue new];
    _preferencesQueue.name = @"com.brooktrout12.dawn18.settings";
    _preferencesQueue.maxConcurrentOperationCount = 1;
    _preferencesQueue.qualityOfService = NSQualityOfServiceUtility;
    NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self
        selector:@selector(readPreferencesInBackground) object:nil];
    [_preferencesQueue addOperation:operation];
}

- (void)dealloc {
    if (_previewReplyRegistered) notify_cancel(_previewReplyToken);
}

- (void)readPreferencesInBackground {
    @autoreleasepool {
        D18Configuration configuration = D18ReadConfiguration();
        NSValue *value = [NSValue valueWithBytes:&configuration objCType:@encode(D18Configuration)];
        [self performSelectorOnMainThread:@selector(configurationLoaded:) withObject:value waitUntilDone:NO];
    }
}

- (void)configurationLoaded:(NSValue *)value {
    [value getValue:&_configuration size:sizeof(_configuration)];
    _table.userInteractionEnabled = YES;
    [_table reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(_table.bounds);
    if (width <= 0) return;
    CGSize size = [_heading systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                        withHorizontalFittingPriority:UILayoutPriorityRequired
                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(CGRectGetWidth(_heading.frame) - width) > 0.5 || fabs(CGRectGetHeight(_heading.frame) - size.height) > 0.5) {
        _heading.frame = CGRectMake(0, 0, width, size.height);
        _table.tableHeaderView = _heading;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return _options.count + 2;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return 1;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return 8;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    (void)tableView;
    return section >= (NSInteger)_options.count ? UITableViewAutomaticDimension : 4;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == (NSInteger)_options.count)
        return _previewStatus ?: @"Preview a banner, then open Notification Center or long-press the notification to check its clear controls.";
    if (section != (NSInteger)_options.count + 1) return nil;
    return @"Default follows the normal appearance. Light and Dark override it.\n\nChanges apply automatically. Reopen an app or menu if it keeps its previous appearance. Apps and widgets with fixed colors may keep those colors.\n\nDawn 18 · 1.0.0\nBy Brooktrout12\nInspired by Dawn by EthanRDoesMC";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section >= (NSInteger)_options.count) {
        BOOL preview = indexPath.section == (NSInteger)_options.count;
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = preview ? (_previewPending ? @"Sending Preview…" : @"Send Test Notification") : @"Reset to Default";
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.textColor = preview && _previewPending ? UIColor.secondaryLabelColor : self.view.tintColor;
        cell.imageView.image = [UIImage systemImageNamed:preview ? @"bell.badge" : @"arrow.counterclockwise"];
        cell.imageView.tintColor = cell.textLabel.textColor;
        cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        if (preview && _previewPending) cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
        return cell;
    }
    NSDictionary *option = _options[indexPath.section];
    D18OptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"appearance" forIndexPath:indexPath];
    NSInteger element = [option[@"element"] integerValue];
    cell.optionTitle.text = option[@"title"];
    cell.symbol.image = [UIImage systemImageNamed:option[@"symbol"]] ?: [UIImage systemImageNamed:@"circle.lefthalf.filled"];
    cell.selector.tag = element;
    NSArray<NSString *> *choices = element == D18QuickActions ?
        @[@"Default", @"Light", @"Dark", @"iOS 10 style"] : @[@"Default", @"Light", @"Dark"];
    // Cells are reused between rows: remove the fourth segment again when a
    // Quick Actions cell becomes a different three-choice preference.
    if (cell.selector.numberOfSegments != choices.count) {
        [cell.selector removeAllSegments];
        for (NSUInteger index = 0; index < choices.count; index++)
            [cell.selector insertSegmentWithTitle:choices[index] atIndex:index animated:NO];
    }
    cell.selector.apportionsSegmentWidthsByContent = element == D18QuickActions;
    cell.selector.accessibilityHint = element == D18QuickActions ?
        @"Default follows the normal appearance. Light and Dark override it. iOS 10 style uses a translucent blur." :
        @"Default uses the normal appearance. Light or Dark overrides it.";
    cell.selector.selectedSegmentIndex = _configuration.values[element];
    cell.selector.accessibilityLabel = [option[@"title"] stringByAppendingString:@" appearance"];
    [cell.selector removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
    [cell.selector addTarget:self action:@selector(appearanceChanged:) forControlEvents:UIControlEventValueChanged];
    return cell;
}
- (void)appearanceChanged:(UISegmentedControl *)selector {
    NSInteger element = selector.tag;
    if (element < 0 || element >= D18ElementCount) return;
    D18Configuration next = _configuration;
    next.values[element] = D18ValidatedPreference((D18Element)element, selector.selectedSegmentIndex);
    [self saveConfiguration:next];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == (NSInteger)_options.count) {
        [self sendTestNotification];
    } else if (indexPath.section == (NSInteger)_options.count + 1) {
        D18Configuration defaults = {{0}};
        [self saveConfiguration:defaults];
    }
}

- (void)refreshPreviewRow {
    [_table reloadSections:[NSIndexSet indexSetWithIndex:_options.count] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)sendTestNotification {
    if (_previewPending) return;
    if (!_previewReplyRegistered)
        _previewReplyRegistered = notify_register_check(D18_PREVIEW_REPLY, &_previewReplyToken) == NOTIFY_STATUS_OK;
    int requestToken = -1;
    if (!_previewReplyRegistered || notify_register_check(D18_PREVIEW_REQUEST, &requestToken) != NOTIFY_STATUS_OK) {
        _previewStatus = @"The test notification could not be requested. Please try again.";
        [self refreshPreviewRow];
        return;
    }
    _previewRequestID = arc4random_uniform(UINT32_MAX - 1) + 1;
    BOOL sent = notify_set_state(requestToken, _previewRequestID) == NOTIFY_STATUS_OK &&
                notify_post(D18_PREVIEW_REQUEST) == NOTIFY_STATUS_OK;
    notify_cancel(requestToken);
    _previewPending = sent;
    _previewStatus = sent ? @"Sending a local appearance preview…" : @"The test notification could not be requested. Please try again.";
    [self refreshPreviewRow];
    if (sent) {
        // One acknowledgement read per tap. No persistent polling or blocks.
        [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(previewReply:)
                                     userInfo:@(_previewRequestID) repeats:NO];
    }
}

- (void)previewReply:(NSTimer *)timer {
    if ([timer.userInfo unsignedIntValue] != _previewRequestID) return;
    uint64_t reply = 0;
    BOOL received = _previewReplyRegistered && notify_get_state(_previewReplyToken, &reply) == NOTIFY_STATUS_OK &&
                    (reply >> 8) == _previewRequestID;
    _previewPending = NO;
    if (received && (reply & 0xff) == D18PreviewSubmitted)
        _previewStatus = @"Preview sent. Open Notification Center or long-press the notification to inspect its clear controls.";
    else if (received)
        _previewStatus = [NSString stringWithFormat:@"The test notification could not be sent (N%u). Please include this code when reporting the issue.", (unsigned int)(reply & 0xff)];
    else
        _previewStatus = @"The preview could not be confirmed. Respring and try again.";
    [self refreshPreviewRow];
}
- (void)saveConfiguration:(D18Configuration)configuration {
    _table.userInteractionEnabled = NO;
    NSValue *value = [NSValue valueWithBytes:&configuration objCType:@encode(D18Configuration)];
    NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self
        selector:@selector(savePreferencesInBackground:) object:value];
    [_preferencesQueue addOperation:operation];
}

- (void)savePreferencesInBackground:(NSValue *)value {
    @autoreleasepool {
        D18Configuration configuration = {{0}};
        [value getValue:&configuration size:sizeof(configuration)];
        BOOL saved = D18WriteConfiguration(configuration);
        D18Configuration persisted = saved ? configuration : D18ReadConfiguration();
        NSDictionary *result = @{
            @"saved": @(saved),
            @"configuration": [NSValue valueWithBytes:&persisted objCType:@encode(D18Configuration)]
        };
        [self performSelectorOnMainThread:@selector(configurationSaved:) withObject:result waitUntilDone:NO];
    }
}

- (void)configurationSaved:(NSDictionary *)result {
    [self configurationLoaded:result[@"configuration"]];
    if (![result[@"saved"] boolValue]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn’t Save"
            message:@"Your appearance choices could not be saved. Please try again."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end
