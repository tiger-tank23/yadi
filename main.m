#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "CWJPEGInstrument.h"

static UIColor *Ink(void) { return [UIColor colorWithRed:0.055 green:0.067 blue:0.075 alpha:1]; }
static UIColor *Panel(void) { return [UIColor colorWithWhite:0.115 alpha:1]; }
static UIColor *Accent(void) { return [UIColor colorWithRed:1 green:0.74 blue:0.28 alpha:1]; }

@interface Bridge : UIViewController <WKNavigationDelegate>
@end
@implementation Bridge {
    WKWebView *_page, *_media;
    UISegmentedControl *_mode, *_rate;
    UIStackView *_networkRow, *_settings, *_layout;
    UIButton *_settingsButton;
    UILabel *_placeholder;
    NSLayoutConstraint *_sidebarWidth;
    int _reported;
    double _windowStart;
    NSUInteger _windowFrames;
    UITextField *_port;
    UILabel *_status;
    UIButton *_button;
    dispatch_queue_t _worker;
    CWJPEGInstrument *_sender;
    NSUInteger _generation, _frames;
    BOOL _running;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = Ink();
    _worker = dispatch_queue_create("jpeg.instrument", DISPATCH_QUEUE_SERIAL);
    _sender = [CWJPEGInstrument new];
    _port = [UITextField new];
    _port.text = @"9888"; _port.accessibilityLabel = @"CarWithin HTTP 端口";
    _port.keyboardType = UIKeyboardTypeNumberPad;
    _port.borderStyle = UITextBorderStyleRoundedRect;
    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    [_button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UILabel *title = [UILabel new]; title.text = @"仪表投屏";
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    title.adjustsFontSizeToFitWidth = YES; title.minimumScaleFactor = 0.8;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"dot.radiowaves.right"]];
    icon.tintColor = Accent(); icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:25].active = YES;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[icon,title,_button]];
    header.spacing = 9; header.alignment = UIStackViewAlignmentCenter;
    [_button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [_button.widthAnchor constraintGreaterThanOrEqualToConstant:96].active = YES;
    [self styleButton];
    _status = [UILabel new]; _status.numberOfLines = 0;
    _status.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    _status.textColor = UIColor.secondaryLabelColor;
    _status.text = @"等待连接";
    _mode = [[UISegmentedControl alloc] initWithItems:@[@"CarPlay", @"本地媒体"]];
    _mode.selectedSegmentIndex = 0;
    _mode.selectedSegmentTintColor = [UIColor colorWithWhite:0.30 alpha:1];
    [_mode.heightAnchor constraintEqualToConstant:40].active = YES;
    [_mode addTarget:self action:@selector(changeMode) forControlEvents:UIControlEventValueChanged];
    _rate = [[UISegmentedControl alloc] initWithItems:@[@"自动", @"5", @"10", @"15", @"20", @"30"]];
    _rate.selectedSegmentIndex = 0; _rate.accessibilityLabel = @"目标帧率";
    UILabel *fpsLabel = [UILabel new]; fpsLabel.text = @"目标帧率（FPS）";
    UILabel *portLabel = [UILabel new]; portLabel.text = @"本机 HTTP 端口";
    _networkRow = [[UIStackView alloc] initWithArrangedSubviews:@[portLabel,_port]];
    _networkRow.spacing = 8; _port.textAlignment = NSTextAlignmentCenter;
    _settings = [[UIStackView alloc] initWithArrangedSubviews:@[_networkRow,fpsLabel,_rate]];
    _settings.axis = UILayoutConstraintAxisVertical; _settings.spacing = 7; _settings.hidden = YES;
    _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_settingsButton setTitle:@" 连接设置" forState:UIControlStateNormal];
    [_settingsButton setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    _settingsButton.tintColor = UIColor.secondaryLabelColor;
    _settingsButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [_settingsButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [_settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    _page = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    _page.navigationDelegate = self;
    _media = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    _media.hidden = YES;
    NSURL *mediaURL = [NSBundle.mainBundle URLForResource:@"media" withExtension:@"html"];
    if (mediaURL) [_media loadFileURL:mediaURL allowingReadAccessToURL:mediaURL.URLByDeletingLastPathComponent];
    UIView *preview = [UIView new]; preview.backgroundColor = Panel();
    preview.layer.cornerRadius = 18; preview.clipsToBounds = YES;
    _placeholder = [UILabel new]; _placeholder.text = @"在 CarWithin 开启浏览器输出，\n然后点右上角「投屏」。";
    _placeholder.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _placeholder.textColor = UIColor.secondaryLabelColor;
    _placeholder.numberOfLines = 0; _placeholder.textAlignment = NSTextAlignmentCenter;
    for (UIView *surface in @[_placeholder,_page,_media]) {
        surface.translatesAutoresizingMaskIntoConstraints = NO; [preview addSubview:surface];
        [NSLayoutConstraint activateConstraints:@[[surface.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor],
            [surface.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor],
            [surface.topAnchor constraintEqualToAnchor:preview.topAnchor],[surface.bottomAnchor constraintEqualToAnchor:preview.bottomAnchor]]];
    }
    _page.hidden = YES;
    UIStackView *controls = [[UIStackView alloc] initWithArrangedSubviews:@[header,_mode,_settingsButton,_settings,_status]];
    controls.axis = UILayoutConstraintAxisVertical; controls.spacing = 7;
    UIScrollView *scroll = [UIScrollView new]; [scroll addSubview:controls]; controls.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[controls.topAnchor constraintEqualToAnchor:content.topAnchor],
        [controls.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],[controls.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],[controls.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    _sidebarWidth = [scroll.widthAnchor constraintEqualToConstant:270];
    _layout = [[UIStackView alloc] initWithArrangedSubviews:@[scroll,preview]];
    _layout.spacing = 12; _layout.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_layout];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_layout.topAnchor constraintEqualToAnchor:g.topAnchor constant:6],[_layout.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-6],
        [_layout.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [_layout.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14]]];
    NSLayoutConstraint *height = [scroll.heightAnchor constraintEqualToAnchor:controls.heightAnchor];
    height.priority = 749; height.active = YES;
    [preview setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisVertical];
    [self arrange];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(background:)
        name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self arrange]; }
- (void)arrange {
    BOOL wide = self.view.bounds.size.width > self.view.bounds.size.height;
    _layout.axis = wide ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    _sidebarWidth.active = wide;
}
- (void)showSettings {
    _settings.hidden = !_settings.hidden;
    [_settingsButton setTitle:_settings.hidden ? @" 连接设置" : @" 收起设置" forState:UIControlStateNormal];
    if (_settings.hidden) [_port resignFirstResponder];
}
- (void)styleButton {
    UIButtonConfiguration *cfg = UIButtonConfiguration.filledButtonConfiguration;
    cfg.title = _running ? @"停止" : @"投屏";
    cfg.image = [UIImage systemImageNamed:_running ? @"stop.fill" : @"play.fill"];
    cfg.imagePadding = 7; cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.baseForegroundColor = _running ? UIColor.whiteColor : Ink();
    cfg.baseBackgroundColor = _running ? [UIColor colorWithRed:0.52 green:0.18 blue:0.15 alpha:1] : Accent();
    _button.configuration = cfg;
}
- (void)changeMode {
    if (_running) [self stop:@"已停止"];
    BOOL local = _mode.selectedSegmentIndex == 1;
    _page.hidden = YES; _networkRow.hidden = local; _placeholder.hidden = local;
    _media.hidden = !local;
    if (!local) [_media evaluateJavaScript:@"if (!movie.paused || (entries.length && running)) el('toggle').click()" completionHandler:nil];
    _status.text = local ? @"添加图片或视频，然后开始投屏。" : @"先在 CarWithin 启动浏览器输出。";
}
- (void)background:(NSNotification *)note {
    if (_running) [self stop:@"已暂停。回到前台后可重新开始。"];
}
- (void)stop:(NSString *)message {
    _running = NO; _generation++; [_page stopLoading]; [_page loadHTMLString:@"" baseURL:nil];
    _port.enabled = _rate.enabled = YES; UIApplication.sharedApplication.idleTimerDisabled = NO;
    [self styleButton]; _page.hidden = YES; _status.text = message;
    dispatch_async(_worker, ^{ [self->_sender stop]; });
}
- (void)toggle {
    if (_running) { [self stop:@"已停止"]; return; }
    NSInteger port = _port.text.integerValue;
    BOOL local = _mode.selectedSegmentIndex == 1;
    if (!local && (port < 1 || port > 65535)) { _status.text = @"请输入有效端口"; return; }
    [_port resignFirstResponder]; _port.enabled = _rate.enabled = NO; _running = YES; _frames = 0;
    NSUInteger generation = ++_generation;
    [self styleButton]; _page.hidden = local;
    _status.text = @"正在连接仪表 192.168.7.1…";
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/",(long)port]];
    if (!local) [_page loadRequest:[NSURLRequest requestWithURL:url]];
    dispatch_async(_worker, ^{
        NSError *err = nil;
        BOOL ok = [self->_sender startWithIPv4:@"192.168.7.1" error:&err];
        CGSize size = self->_sender.canvasSize; int fps = self->_sender.frameRate;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            if (!ok) { [self stop:err.localizedDescription]; return; }
            self->_reported = fps;
            int limits[] = {30,5,10,15,20,30};
            int target = MIN(fps, limits[self->_rate.selectedSegmentIndex]);
            self->_windowStart = CACurrentMediaTime(); self->_windowFrames = 0;
            self->_status.text = [NSString stringWithFormat:@"仪表 %d · 目标 %d FPS · 等待画面",fps,target];
            [self capture:generation size:size fps:target];
        });
    });
}
- (void)capture:(NSUInteger)generation size:(CGSize)size fps:(int)fps {
    if (generation != _generation) return;
    CFTimeInterval began = CACurrentMediaTime();
    NSString *js = [NSString stringWithFormat:
        @"(()=>{const v=document.querySelector('video'),c=document.querySelector('canvas#view');"
         "const s=c&&!c.hidden&&c.width&&getComputedStyle(c).display!=='none'?c:(v&&v.readyState>=2&&v.videoWidth?v:null);"
         "if(!s)return null;const w=%d,h=%d,t=window.__cwJPEG||(window.__cwJPEG=document.createElement('canvas'));"
         "if(t.width!==w||t.height!==h){t.width=w;t.height=h;}const x=t.getContext('2d'),"
         "sw=s.videoWidth||s.width,sh=s.videoHeight||s.height,k=Math.min(w/sw,h/sh);"
         "x.fillStyle='black';x.fillRect(0,0,w,h);x.drawImage(s,(w-sw*k)/2,(h-sh*k)/2,sw*k,sh*k);"
         "return t.toDataURL('image/jpeg',0.60).split(',')[1];})()", (int)size.width,(int)size.height];
    BOOL local = _mode.selectedSegmentIndex == 1;
    if (local) js = [NSString stringWithFormat:@"window.mediaJPEG ? window.mediaJPEG(%d,%d) : null",(int)size.width,(int)size.height];
    WKWebView *source = local ? _media : _page;
    [source evaluateJavaScript:js completionHandler:^(id value,NSError *err){
        if (generation != self->_generation) return;
        if (err) { [self stop:err.localizedDescription]; return; }
        NSString *encoded = [value isKindOfClass:NSString.class] ? value : nil;
        dispatch_async(self->_worker, ^{
            NSError *sendError = nil;
            if (encoded) {
                NSData *jpeg = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
                [self->_sender sendJPEG:jpeg error:&sendError];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self->_generation) return;
                if (sendError) { [self stop:sendError.localizedDescription]; return; }
                if (encoded) { self->_frames++; self->_windowFrames++; }
                double elapsed = CACurrentMediaTime() - self->_windowStart;
                if (elapsed >= 1.0) {
                    self->_status.text = [NSString stringWithFormat:@"仪表 %d · 目标 %d · 实发 %.1f FPS · 共 %lu 帧",
                        self->_reported,fps,self->_windowFrames/elapsed,(unsigned long)self->_frames];
                    self->_windowFrames = 0; self->_windowStart = CACurrentMediaTime();
                }
                double delay = MAX(0.001, (encoded ? 1.0/fps : 0.25) - (CACurrentMediaTime()-began));
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ [self capture:generation size:size fps:fps]; });
            });
        });
    }];
}
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation *)nav withError:(NSError *)error {
    if (_running && error.code != NSURLErrorCancelled)
        [self stop:[NSString stringWithFormat:@"打开本机接收页失败：%@",error.localizedDescription]];
}
@end

@interface App : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation App
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=[Bridge new]; [self.window makeKeyAndVisible]; return YES;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class)); }
}
