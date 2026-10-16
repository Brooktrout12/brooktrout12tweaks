#import "PICropViewController.h"
#import "PICropGeometry.h"
#import "PIBlockCompatibility.h"
#import <QuartzCore/QuartzCore.h>

@interface PICropViewController () <UIScrollViewDelegate>
@property(nonatomic, strong) UIImage *source;
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) UILabel *instructions;
@property(nonatomic, strong) UILabel *zoomLabel;
@property(nonatomic, strong) UISlider *zoomSlider;
@property(nonatomic, strong) UIButton *resetButton;
@property(nonatomic, copy) NSDictionary *initialCrop;
@property(nonatomic) CGFloat cornerRatio;
@property(nonatomic) BOOL adjustingLayout;
@end

@implementation PICropViewController
@synthesize onSave = _onSave;
@synthesize onCancel = _onCancel;
@synthesize onChoosePhoto = _onChoosePhoto;

// Keep typed ARC block-copy semantics at every stored callback boundary.
// This avoids the same legacy-arm64e copyWithZone: crash fixed in onReady.
- (void)setOnSave:(void (^)(UIImage *, NSDictionary *))callback {
    _onSave = callback;
}
- (void)setOnCancel:(void (^)(void))callback {
    _onCancel = callback;
}
- (void)setOnChoosePhoto:(void (^)(void))callback {
    _onChoosePhoto = callback;
}

- (instancetype)initWithImage:(UIImage *)image crop:(NSDictionary *)crop cornerRatio:(CGFloat)cornerRatio {
    if ((self = [super init])) {
        _source = image;
        _initialCrop = [crop copy];
        _cornerRatio = PIClamp(cornerRatio, 0.15, 0.3);
        self.title = @"Move & Scale";
        self.modalInPresentation = YES;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.instructions = [UILabel new];
    self.instructions.text = @"Drag to position your photo.\nPinch to zoom, then tap Save.";
    self.instructions.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.instructions.adjustsFontForContentSizeCategory = YES;
    self.instructions.numberOfLines = 2;
    self.instructions.textAlignment = NSTextAlignmentCenter;
    self.instructions.textColor = UIColor.secondaryLabelColor;
    [self.view addSubview:self.instructions];

    self.scrollView = [UIScrollView new];
    self.scrollView.delegate = self;
    self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.bounces = NO;
    self.scrollView.bouncesZoom = NO;
    self.scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
    self.scrollView.clipsToBounds = YES;
    self.scrollView.backgroundColor = UIColor.blackColor;
    self.scrollView.layer.cornerCurve = kCACornerCurveContinuous;
    self.scrollView.accessibilityLabel = @"Icon crop preview";
    self.scrollView.accessibilityHint = @"Drag to reposition. Pinch or use the Zoom slider to resize.";
    [self.view addSubview:self.scrollView];
    self.imageView = [[UIImageView alloc] initWithImage:self.source];
    self.imageView.frame = (CGRect){CGPointZero,self.source.size};
    [self.scrollView addSubview:self.imageView];

    self.zoomLabel = [UILabel new];
    self.zoomLabel.text = @"Zoom";
    self.zoomLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [self.view addSubview:self.zoomLabel];
    self.zoomSlider = [UISlider new];
    self.zoomSlider.minimumValue = 1;
    self.zoomSlider.maximumValue = 8;
    self.zoomSlider.accessibilityLabel = @"Zoom";
    [self.zoomSlider addTarget:self action:@selector(zoomChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.zoomSlider];
    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"Reset Crop" forState:UIControlStateNormal];
    [self.resetButton addTarget:self action:@selector(resetCrop) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resetButton];
    UIBarButtonItem *choose = [[UIBarButtonItem alloc] initWithTitle:@"Choose Another Photo"
        style:UIBarButtonItemStylePlain target:self action:@selector(choosePhoto)];
    self.toolbarItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        choose,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
    [self.navigationController setToolbarHidden:NO animated:NO];
}
- (NSDictionary *)currentCrop {
    CGSize size = self.source.size;
    PICropRect r = PICropForViewport(size.width, size.height, self.scrollView.bounds.size.width,
        self.scrollView.zoomScale, self.scrollView.contentOffset.x, self.scrollView.contentOffset.y);
    return @{@"x":@(r.x/size.width), @"y":@(r.y/size.height), @"width":@(r.width/size.width)};
}
- (void)applyCrop:(NSDictionary *)crop {
    CGSize size = self.source.size;
    CGFloat side = self.scrollView.bounds.size.width;
    CGFloat minimum = PIFillScale(size.width,size.height,side);
    self.scrollView.minimumZoomScale = minimum;
    self.scrollView.maximumZoomScale = minimum * 8;
    double savedWidth = [crop[@"width"] respondsToSelector:@selector(doubleValue)] ? [crop[@"width"] doubleValue] : 0;
    double x = [crop[@"x"] respondsToSelector:@selector(doubleValue)] ? [crop[@"x"] doubleValue] : 0;
    double y = [crop[@"y"] respondsToSelector:@selector(doubleValue)] ? [crop[@"y"] doubleValue] : 0;
    BOOL valid = isfinite(savedWidth) && savedWidth > 0 && isfinite(x) && isfinite(y);
    CGFloat zoom = valid ? side/(savedWidth*size.width) : minimum;
    self.scrollView.zoomScale = PIClamp(zoom, minimum, minimum*8);
    CGFloat width = size.width*self.scrollView.zoomScale;
    CGFloat height = size.height*self.scrollView.zoomScale;
    self.scrollView.contentSize = CGSizeMake(width,height);
    self.scrollView.contentOffset = CGPointMake(
        valid ? PIClamp(x*width,0,width-side) : (width-side)*0.5,
        valid ? PIClamp(y*height,0,height-side) : (height-side)*0.5);
    self.zoomSlider.value = self.scrollView.zoomScale/minimum;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.adjustingLayout) return;
    CGRect area = UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    CGFloat side = floor(MAX(80, MIN(380, MIN(area.size.width-48,area.size.height-168))));
    CGFloat top = area.origin.y + MAX(70,(area.size.height-side-80)*0.5);
    CGRect frame = CGRectMake(CGRectGetMidX(area)-side*0.5,top,side,side);
    if (!CGRectEqualToRect(self.scrollView.frame,frame)) {
        self.adjustingLayout = YES;
        NSDictionary *crop = self.scrollView.bounds.size.width > 0 ? [self currentCrop] : self.initialCrop;
        self.scrollView.frame = frame;
        self.scrollView.layer.cornerRadius = side*self.cornerRatio;
        [self applyCrop:crop];
        self.initialCrop = nil;
        self.adjustingLayout = NO;
    }
    self.instructions.frame = CGRectMake(area.origin.x+20,area.origin.y+10,area.size.width-40,52);
    CGFloat footerY = CGRectGetMaxY(frame)+12;
    self.zoomLabel.frame = CGRectMake(CGRectGetMinX(frame),footerY,48,44);
    self.zoomSlider.frame = CGRectMake(CGRectGetMinX(frame)+54,footerY,side-54,44);
    self.resetButton.frame = CGRectMake(CGRectGetMidX(area)-80,footerY+40,160,44);
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.imageView; }
- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    self.zoomSlider.value = scrollView.zoomScale/MAX(scrollView.minimumZoomScale,0.0001);
}
- (void)zoomChanged:(UISlider *)slider {
    CGFloat side = self.scrollView.bounds.size.width;
    CGFloat oldScale = self.scrollView.zoomScale;
    CGPoint center = CGPointMake((self.scrollView.contentOffset.x+side*0.5)/oldScale,
                                (self.scrollView.contentOffset.y+side*0.5)/oldScale);
    CGFloat newScale = self.scrollView.minimumZoomScale*slider.value;
    [self.scrollView setZoomScale:newScale animated:NO];
    self.scrollView.contentOffset = CGPointMake(
        PIClamp(center.x*newScale-side*0.5,0,MAX(0,self.scrollView.contentSize.width-side)),
        PIClamp(center.y*newScale-side*0.5,0,MAX(0,self.scrollView.contentSize.height-side)));
}
- (void)resetCrop { [self applyCrop:nil]; }
- (void)cancel { if (!self.saving && self.onCancel) self.onCancel(); }
- (void)choosePhoto { if (!self.saving && self.onChoosePhoto) self.onChoosePhoto(); }
- (void)setSaving:(BOOL)saving {
    _saving = saving;
    self.navigationItem.rightBarButtonItem.enabled = !saving;
    self.navigationItem.rightBarButtonItem.title = saving ? @"Saving…" : @"Save";
    self.navigationItem.leftBarButtonItem.enabled = !saving;
    self.view.userInteractionEnabled = !saving;
    for (UIBarButtonItem *item in self.toolbarItems) item.enabled = !saving;
}
- (void)save {
    if (self.saving || !self.onSave) return;
    // Stop deceleration/bounce before reading the viewport, avoiding off-edge pixels.
    [self.scrollView setContentOffset:self.scrollView.contentOffset animated:NO];
    NSDictionary *crop = [self currentCrop];
    CGFloat edge = [crop[@"width"] doubleValue]*self.source.size.width;
    CGFloat x = [crop[@"x"] doubleValue]*self.source.size.width;
    CGFloat y = [crop[@"y"] doubleValue]*self.source.size.height;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(512,512) format:format];
    UIImage *image = [renderer imageWithActions:PI_SYSTEM_BLOCK(^(UIGraphicsImageRendererContext *context) {
        [UIColor.blackColor setFill];
        [context fillRect:CGRectMake(0,0,512,512)];
        CGFloat factor = 512/edge;
        [self.source drawInRect:CGRectMake(-x*factor,-y*factor,
            self.source.size.width*factor,self.source.size.height*factor)];
    })];
    // Keep this image square: the SpringBoard renderer supplies the native mask.
    self.onSave(image,crop);
}
@end
