#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
void RABDiagnosticsInitialize(NSString *version);
void RABDiagnosticsInstallMenu(void);
void RABLog(NSString *message);
void RABObserveHost(NSString *host, BOOL blocked);
void RABBlockedRequest(NSURLRequest *request, BOOL vast);
void RABPlayerEvent(AVPlayer *player, NSString *event);
void RABPlayerCheckpoints(AVPlayer *player);
void RABMediaEvent(NSURL *url, NSString *event);
void RABDiagnosticCounter(NSString *name);

