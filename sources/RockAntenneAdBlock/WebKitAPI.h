#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Public WebKit API subset used by this project. The minimal Linux SDK omits
// WebKit; classes are resolved from the actual iOS system framework at runtime.
// No private methods or fabricated runtime implementations are involved.
@class WKNavigation, WKContentRuleList;
@interface WKScriptMessage : NSObject
@property(nonatomic, readonly, copy) id body;
@end
typedef NS_ENUM(NSInteger, WKUserScriptInjectionTime) {
    WKUserScriptInjectionTimeAtDocumentStart = 0,
    WKUserScriptInjectionTimeAtDocumentEnd = 1
};
@interface WKUserScript : NSObject
- (instancetype)initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)time forMainFrameOnly:(BOOL)mainOnly;
@end
@interface WKUserContentController : NSObject
- (void)addUserScript:(WKUserScript *)script;
- (void)addContentRuleList:(WKContentRuleList *)ruleList;
- (void)addScriptMessageHandler:(id)handler name:(NSString *)name;
@end
@interface WKWebViewConfiguration : NSObject
@property(nonatomic, strong) WKUserContentController *userContentController;
@end
@interface WKWebView : UIView
@property(nonatomic, readonly, copy) WKWebViewConfiguration *configuration;
@end
@interface WKContentRuleListStore : NSObject
+ (instancetype)defaultStore;
- (void)compileContentRuleListForIdentifier:(NSString *)identifier encodedContentRuleList:(NSString *)json completionHandler:(void (^)(WKContentRuleList *, NSError *))completion;
@end

