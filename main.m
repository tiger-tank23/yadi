#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "CWJPEGInstrument.h"

@interface Bridge : UIViewController <WKNavigationDelegate>
@end
@implementation Bridge {
    WKWebView *_page;
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
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _worker = dispatch_queue_create("jpeg.instrument", DISPATCH_QUEUE_SERIAL);
    _sender = [CWJPEGInstrument new];
    _port = [UITextField new];
    _port.text = @"9888"; _port.accessibilityLabel = @"CarWithin HTTP 端口";
    _port.keyboardType = UIKeyboardTypeNumberPad;
    _port.borderStyle = UITextBorderStyleRoundedRect;
    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    [_button setTitle:@"开始投屏" forState:UIControlStateNormal];
    [_button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UILabel *label = [UILabel new]; label.text = @"本机 HTTP 端口";
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label,_port,_button]];
    row.spacing = 8;
    _status = [UILabel new]; _status.numberOfLines = 0;
    _status.text = @"先在 CarWithin 启动浏览器输出，再开始投屏。";
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    _page = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    _page.navigationDelegate = self;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[row,_status,_page]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:g.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-10]]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(background:)
        name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)background:(NSNotification *)note {
    if (_running) [self stop:@"已暂停。回到前台后可重新开始。"];
}
- (void)stop:(NSString *)message {
    _running = NO; _generation++; [_page stopLoading]; [_page loadHTMLString:@"" baseURL:nil];
    _port.enabled = YES; UIApplication.sharedApplication.idleTimerDisabled = NO;
    [_button setTitle:@"开始投屏" forState:UIControlStateNormal]; _status.text = message;
    dispatch_async(_worker, ^{ [self->_sender stop]; });
}
- (void)toggle {
    if (_running) { [self stop:@"已停止"]; return; }
    NSInteger port = _port.text.integerValue;
    if (port < 1 || port > 65535) { _status.text = @"请输入有效端口"; return; }
    [_port resignFirstResponder]; _port.enabled = NO; _running = YES; _frames = 0;
    NSUInteger generation = ++_generation;
    [_button setTitle:@"停止" forState:UIControlStateNormal];
    _status.text = @"正在连接仪表 192.168.7.1…";
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/",(long)port]];
    [_page loadRequest:[NSURLRequest requestWithURL:url]];
    dispatch_async(_worker, ^{
        NSError *err = nil;
        BOOL ok = [self->_sender startWithIPv4:@"192.168.7.1" error:&err];
        CGSize size = self->_sender.canvasSize; int fps = self->_sender.frameRate;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            if (!ok) { [self stop:err.localizedDescription]; return; }
            self->_status.text = @"仪表已连接，等待本机网页播放…";
            [self capture:generation size:size fps:fps];
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
    [_page evaluateJavaScript:js completionHandler:^(id value,NSError *err){
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
                if (encoded && (++self->_frames == 1 || self->_frames % 30 == 0))
                    self->_status.text = [NSString stringWithFormat:@"已发送 %lu 帧",(unsigned long)self->_frames];
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
