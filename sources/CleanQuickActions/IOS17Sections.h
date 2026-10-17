#pragma once
#import <UIKit/UIKit.h>

typedef BOOL (*CQAIconMenuPolicy)(UIView *view);

// Installs nothing unless this is iOS 17 and every required interface matches.
void CQAInstallIOS17SectionFix(CQAIconMenuPolicy policy);
void CQARefreshIOS17Sections(UIView *view);
