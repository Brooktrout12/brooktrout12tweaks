#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "WebKitAPI.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import "Rules.h"
#import "Diagnostics.h"
#import "AdsWizz.h"

static NSString * const RABVersion = @"0.2.0-test2";

static BOOL RABIsBlockedURL(NSURL *url) {
    if (!url) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;
    NSString *host = url.host.lowercaseString;
    BOOL blocked = RABIsAdHost(host.UTF8String);
    BOOL adsWizzDelivery = [host isEqualToString:@"deliveryengine.adswizz.com"] ||
                          [host hasSuffix:@".deliveryengine.adswizz.com"];
    // SSAI direct-selection responses can describe an ad already entering the
    // stream. Emptying that VAST can remove the manager needed to skip it.
    // Let the SDK process it when the documented skip hooks are available.
    if (adsWizzDelivery && RABAdsWizzHandlesDelivery()) {
        blocked = NO;
        RABObserveHost(host, NO);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ RABLog(@"SDK delivery policy: allow AdsWizz native delivery metadata so AdManager can identify and skip the ad; this is not proof of successful skipping"); });
    }
    RABObserveHost(host, blocked);
    return blocked;
}

static BOOL RABWantsVAST(NSURLRequest *request) {
    NSURL *url = request.URL;
    NSString *path = url.path.lowercaseString;
    // Documented AdsWizz direct selection endpoint and explicit VAST requests.
    BOOL adsWizz = [url.host.lowercaseString hasSuffix:@".deliveryengine.adswizz.com"] ||
                  [url.host.lowercaseString isEqualToString:@"deliveryengine.adswizz.com"];
    if (adsWizz && [path isEqualToString:@"/www/delivery/fc.php"]) return YES;
    if ([path.pathExtension isEqualToString:@"xml"] || [path containsString:@"/vast"]) return YES;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in parts.queryItems) {
        NSString *key = item.name.lowercaseString;
        if (([key isEqualToString:@"output"] || [key isEqualToString:@"format"] ||
             [key isEqualToString:@"type"]) && [item.value.lowercaseString containsString:@"vast"]) return YES;
    }
    return NO;
}

@interface RABURLProtocol : NSURLProtocol
@property(atomic) BOOL rabStopped;
@end

@implementation RABURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return RABIsBlockedURL(request.URL); }
+ (BOOL)canInitWithTask:(NSURLSessionTask *)task { return RABIsBlockedURL(task.currentRequest.URL); }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    if (self.rabStopped) return;
    // An empty VAST document follows the SDK's normal no-ad path. Everything
    // else receives an empty 204; no advertising request leaves this handler.
    BOOL vast = RABWantsVAST(self.request);
    RABBlockedRequest(self.request, vast);
    NSData *body = vast ? [@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><VAST version=\"3.0\"></VAST>"
                          dataUsingEncoding:NSUTF8StringEncoding] : [NSData data];
    NSDictionary *headers = @{@"Content-Type": vast ? @"application/xml; charset=utf-8" : @"text/plain; charset=utf-8",
                              @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)body.length],
                              @"Cache-Control": @"no-store"};
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
        statusCode:vast ? 200 : 204 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    if (self.rabStopped) return;
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (self.rabStopped) return;
    if (body.length) [self.client URLProtocol:self didLoadData:body];
    if (self.rabStopped) return;
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading { self.rabStopped = YES; }
@end

// Install hooks only for real public Objective-C methods with the expected
// number of arguments. class_replaceMethod does not alter inherited methods
// in a superclass. All original implementations remain callable.
static BOOL RABHook(Class cls, SEL selector, IMP replacement, IMP *original, unsigned int arguments) {
    if (!cls) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != arguments) return NO;
    *original = method_getImplementation(method);
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    return YES;
}

static NSURLSessionConfiguration *RABConfiguration(NSURLSessionConfiguration *configuration) {
    // Apple does not support URLProtocol in background download sessions.
    // Background audio playback is separate from that session mode.
    if (!configuration || configuration.identifier.length) return configuration;
    if ([configuration.protocolClasses containsObject:[RABURLProtocol class]]) return configuration;
    NSURLSessionConfiguration *copy = [configuration copy];
    NSMutableArray<Class> *classes = [NSMutableArray arrayWithObject:[RABURLProtocol class]];
    [classes addObjectsFromArray:configuration.protocolClasses ?: @[]];
    copy.protocolClasses = classes;
    return copy;
}

static NSURLSession *(*RABOriginalSession)(id, SEL, NSURLSessionConfiguration *, id, NSOperationQueue *);
static NSURLSession *RABSession(id self, SEL cmd, NSURLSessionConfiguration *configuration,
                               id delegate, NSOperationQueue *queue) {
    return RABOriginalSession(self, cmd, RABConfiguration(configuration), delegate, queue);
}
static NSURLSession *(*RABOriginalSimpleSession)(id, SEL, NSURLSessionConfiguration *);
static NSURLSession *RABSimpleSession(id self, SEL cmd, NSURLSessionConfiguration *configuration) {
    return RABOriginalSimpleSession(self, cmd, RABConfiguration(configuration));
}
static NSURLSessionConfiguration *(*RABOriginalDefault)(id, SEL);
static NSURLSessionConfiguration *RABDefault(id self, SEL cmd) {
    return RABConfiguration(RABOriginalDefault(self, cmd));
}
static NSURLSessionConfiguration *(*RABOriginalEphemeral)(id, SEL);
static NSURLSessionConfiguration *RABEphemeral(id self, SEL cmd) {
    return RABConfiguration(RABOriginalEphemeral(self, cmd));
}

// WebKit uses a different networking process, so NSURLProtocol alone does not
// cover it. Use WebKit's supported rules plus a narrowly scoped user script.
static NSHashTable<WKUserContentController *> *RABControllers;
static WKContentRuleList *RABWebRules;
static const char RABControllerKey;
static NSMutableSet<NSString *> *RABWebSeen;

@interface RABWebDiagnostics : NSObject
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message;
@end
@implementation RABWebDiagnostics
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)controller;
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *body = message.body;
    NSString *kind = body[@"kind"];
    NSString *host = body[@"host"];
    if (![kind isKindOfClass:[NSString class]] || ![host isKindOfClass:[NSString class]]) return;
    if (![@[@"resource", @"media-playing", @"media-error", @"media-stalled", @"companion-closed", @"page"] containsObject:kind]) return;
    if (host.length > 253 || [host rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]"] invertedSet]].location != NSNotFound) return;
    NSString *event = [NSString stringWithFormat:@"WEB %@ host=%@ adRule=%d", kind, host, RABIsAdHost(host.UTF8String)];
    if (RABWebSeen.count >= 160 || [RABWebSeen containsObject:event]) return;
    [RABWebSeen addObject:event];
    RABLog(event);
}
@end
static RABWebDiagnostics *RABWebHandler;

static NSString *RABWebScript(void) {
    return @"(()=>{'use strict';"
    "if(window.__rabTest1)return;window.__rabTest1=true;"
    "const send=(kind,host)=>{try{window.webkit.messageHandlers.rabDiagnosticTest1.postMessage({kind,host});}catch(e){}};"
    "const hostOf=u=>{try{return new URL(u,location.href).hostname;}catch(e){return '';}};"
    "send('page',location.hostname);const seen=new Set();"
    "const resource=e=>{const h=hostOf(e.name);if(h&&seen.size<120&&!seen.has(h)){seen.add(h);send('resource',h);}};"
    "try{new PerformanceObserver(l=>l.getEntries().forEach(resource)).observe({type:'resource',buffered:true});}catch(e){}"
    "['playing','error','stalled'].forEach(k=>document.addEventListener(k,e=>{const t=e.target;if(t&&(t.tagName==='AUDIO'||t.tagName==='VIDEO'))send('media-'+k,hostOf(t.currentSrc||t.src));},true));"
    "const h=location.hostname.toLowerCase();"
    "if(!['rockantenne.de','rockantenne.bayern','rockantenne.hamburg','rockantenne.at'].some(d=>h===d||h.endsWith('.'+d)))return;"
    // These companion dialog/close selectors are present in the broadcaster's
    // public web player. Use its close button to release its focus trap.
    "let pending=false;const clean=()=>{pending=false;"
    "document.querySelectorAll('.c-dialog--companion-ad').forEach(d=>{"
    "if(d.getAttribute('aria-hidden')==='true')return;"
    "const b=d.querySelector('[data-a11y-dialog-hide]');if(b){b.click();send('companion-closed',h);}"
    "else if(typeof d.close==='function'){d.close();send('companion-closed',h);}"
    "});};"
    "const schedule=()=>{if(!pending){pending=true;queueMicrotask(clean);}};"
    "new MutationObserver(schedule).observe(document,{childList:true,subtree:true,attributes:true,attributeFilter:['class','aria-hidden']});"
    "if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',schedule,{once:true});else schedule();"
    "})();";
}

static void RABPrepareController(WKUserContentController *controller) {
    if (!controller || ![NSThread isMainThread]) return;
    if (objc_getAssociatedObject(controller, &RABControllerKey)) return;
    objc_setAssociatedObject(controller, &RABControllerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [controller addScriptMessageHandler:RABWebHandler name:@"rabDiagnosticTest1"];
    [controller addUserScript:[[NSClassFromString(@"WKUserScript") alloc] initWithSource:RABWebScript()
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    [RABControllers addObject:controller];
    if (RABWebRules) [controller addContentRuleList:RABWebRules];
}

static void RABCompileWebRules(void) {
    NSMutableArray *rules = [NSMutableArray array];
    for (size_t i = 0; i < RABHostRuleCount; ++i) {
        NSString *host = [NSString stringWithUTF8String:RABHostRules[i].host];
        NSString *escaped = [host stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
        NSString *filter = [NSString stringWithFormat:@"^https?://%@%@\\.?(:[0-9]+)?/",
            RABHostRules[i].includeSubdomains ? @"([^/]+\\.)?" : @"", escaped];
        [rules addObject:@{@"trigger": @{@"url-filter": filter, @"url-filter-is-case-sensitive": @NO},
                           @"action": @{@"type": @"block"}}];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:rules options:0 error:nil];
    if (!data) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    WKContentRuleListStore *ruleStore = [NSClassFromString(@"WKContentRuleListStore") defaultStore];
    [ruleStore compileContentRuleListForIdentifier:@"RockAntenneAdBlock-Test1" encodedContentRuleList:json
        completionHandler:^(WKContentRuleList *ruleList, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!ruleList || error) { RABLog(@"WebKit rules failed to compile"); return; }
                RABWebRules = ruleList;
                for (WKUserContentController *controller in RABControllers) [controller addContentRuleList:ruleList];
                RABLog(@"WebKit rules ready");
            });
        }];
}

static WKNavigation *(*RABOriginalWebRequest)(WKWebView *, SEL, NSURLRequest *);
static WKNavigation *RABWebRequest(WKWebView *self, SEL cmd, NSURLRequest *request) {
    RABPrepareController(self.configuration.userContentController);
    RABLog([@"WEB load host=" stringByAppendingString:request.URL.host ?: @"none"]);
    return RABOriginalWebRequest(self, cmd, request);
}
static WKNavigation *(*RABOriginalWebHTML)(WKWebView *, SEL, NSString *, NSURL *);
static WKNavigation *RABWebHTML(WKWebView *self, SEL cmd, NSString *html, NSURL *baseURL) {
    RABPrepareController(self.configuration.userContentController);
    RABLog([@"WEB HTML baseHost=" stringByAppendingString:baseURL.host ?: @"none"]);
    return RABOriginalWebHTML(self, cmd, html, baseURL);
}
static WKNavigation *(*RABOriginalWebData)(WKWebView *, SEL, NSData *, NSString *, NSString *, NSURL *);
static WKNavigation *RABWebData(WKWebView *self, SEL cmd, NSData *data, NSString *mime, NSString *encoding, NSURL *baseURL) {
    RABPrepareController(self.configuration.userContentController);
    RABLog([@"WEB data baseHost=" stringByAppendingString:baseURL.host ?: @"none"]);
    return RABOriginalWebData(self, cmd, data, mime, encoding, baseURL);
}
static WKNavigation *(*RABOriginalWebFile)(WKWebView *, SEL, NSURL *, NSURL *);
static WKNavigation *RABWebFile(WKWebView *self, SEL cmd, NSURL *url, NSURL *accessURL) {
    RABPrepareController(self.configuration.userContentController);
    RABLog(@"WEB local file (path omitted)");
    return RABOriginalWebFile(self, cmd, url, accessURL);
}

// Observe public player entry points without altering playback or volume.
static void (*RABOriginalPlay)(AVPlayer *, SEL);
static void RABPlay(AVPlayer *self, SEL cmd) {
    RABAdsWizzRefresh();
    RABOriginalPlay(self, cmd); RABPlayerEvent(self, @"play"); RABPlayerCheckpoints(self);
}
static void (*RABOriginalPlayRate)(AVPlayer *, SEL, float);
static void RABPlayRate(AVPlayer *self, SEL cmd, float rate) {
    RABAdsWizzRefresh();
    RABOriginalPlayRate(self, cmd, rate); RABPlayerEvent(self, @"playImmediately"); RABPlayerCheckpoints(self);
}
static void (*RABOriginalReplace)(AVPlayer *, SEL, AVPlayerItem *);
static void RABReplace(AVPlayer *self, SEL cmd, AVPlayerItem *item) {
    RABOriginalReplace(self, cmd, item); RABPlayerEvent(self, @"replaceItem"); RABPlayerCheckpoints(self);
}

static void RABReportSDKs(void) {
    // Inventory only, not speculative calls to private SDK methods.
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSUInteger reported = 0;
    for (unsigned int i = 0; classes && i < count && reported < 35; ++i) {
        const char *name = class_getName(classes[i]);
        if (!name) continue;
        NSString *text = [NSString stringWithUTF8String:name];
        if ([text hasPrefix:@"GADBannerView"] || [text hasPrefix:@"GADInterstitial"] ||
            [text hasPrefix:@"IMAAdsLoader"] || [text containsString:@"AdswizzSDK"] ||
            [text hasPrefix:@"Adswizz"] || [text hasPrefix:@"SASBannerView"]) {
            RABLog([@"SDK " stringByAppendingString:text]);
            ++reported;
        }
    }
    free(classes);
    RABLog([NSString stringWithFormat:@"SDK inventory finished (%lu matches)", (unsigned long)reported]);
}

__attribute__((constructor)) static void RABInitialize(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"de.rockantenne.eple"]) return;
        NSOperatingSystemVersion os = [NSProcessInfo processInfo].operatingSystemVersion;
        if (os.majorVersion < 17 || os.majorVersion >= 19) return;
        RABDiagnosticsInitialize(RABVersion);
        RABLog([NSString stringWithFormat:@"ROCK ANTENNE AdBlock %@ app=%@ iOS=%ld.%ld.%ld",
            RABVersion, [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
            (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion]);
        RABLog(@"Scope: AdsWizz skipAd for SDK-managed ads, separate request filtering and web companions. No automatic claim of ad-free listening.");
        RABAdsWizzInstall();
        BOOL registered = [NSURLProtocol registerClass:[RABURLProtocol class]];
        Class sessions = object_getClass([NSURLSession class]);
        Class configurations = object_getClass([NSURLSessionConfiguration class]);
        unsigned int hooks = 0;
        hooks += RABHook(sessions, @selector(sessionWithConfiguration:delegate:delegateQueue:),
            (IMP)RABSession, (IMP *)&RABOriginalSession, 5);
        hooks += RABHook(sessions, @selector(sessionWithConfiguration:),
            (IMP)RABSimpleSession, (IMP *)&RABOriginalSimpleSession, 3);
        hooks += RABHook(configurations, @selector(defaultSessionConfiguration),
            (IMP)RABDefault, (IMP *)&RABOriginalDefault, 2);
        hooks += RABHook(configurations, @selector(ephemeralSessionConfiguration),
            (IMP)RABEphemeral, (IMP *)&RABOriginalEphemeral, 2);
        RABControllers = [NSHashTable weakObjectsHashTable];
        RABWebHandler = [RABWebDiagnostics new];
        RABWebSeen = [NSMutableSet set];
        dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY | RTLD_LOCAL);
        Class webView = NSClassFromString(@"WKWebView");
        hooks += RABHook(webView, NSSelectorFromString(@"loadRequest:"),
            (IMP)RABWebRequest, (IMP *)&RABOriginalWebRequest, 3);
        hooks += RABHook(webView, NSSelectorFromString(@"loadHTMLString:baseURL:"),
            (IMP)RABWebHTML, (IMP *)&RABOriginalWebHTML, 4);
        hooks += RABHook(webView, NSSelectorFromString(@"loadData:MIMEType:characterEncodingName:baseURL:"),
            (IMP)RABWebData, (IMP *)&RABOriginalWebData, 6);
        hooks += RABHook(webView, NSSelectorFromString(@"loadFileURL:allowingReadAccessToURL:"),
            (IMP)RABWebFile, (IMP *)&RABOriginalWebFile, 4);
        hooks += RABHook([AVPlayer class], @selector(play), (IMP)RABPlay, (IMP *)&RABOriginalPlay, 2);
        hooks += RABHook([AVPlayer class], @selector(playImmediatelyAtRate:), (IMP)RABPlayRate, (IMP *)&RABOriginalPlayRate, 3);
        hooks += RABHook([AVPlayer class], @selector(replaceCurrentItemWithPlayerItem:), (IMP)RABReplace, (IMP *)&RABOriginalReplace, 3);
        RABLog([NSString stringWithFormat:@"Protocol=%@ hooks=%u/11", registered ? @"yes" : @"no", hooks]);
        dispatch_async(dispatch_get_main_queue(), ^{
            RABDiagnosticsInstallMenu();
            RABCompileWebRules();
            RABReportSDKs();
        });
    }
}

