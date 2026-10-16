#import "Compatibility.h"
// ClassicLockSound 1.0.7 — brooktrout12
// The device report identifies lock playback as SBUISound feedback event 1002.
// Redirect that request into the controller's native file player. Never patch
// shared AudioServices entry points or intercept the screenshot action.
#import <Foundation/Foundation.h>
#import <substrate.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <string.h>
#include <pthread.h>
#include "BTLockSoundPolicy.h"
#include "BTPreferences.h"

// These signatures were captured from the user's iOS 18.6 runtime. There are
// no custom Objective-C classes, block literals, ivar offsets, or C audio hooks.
@interface SBUISound : NSObject
@property (nonatomic) long long eventType;
@property (nonatomic) long long soundType;
@property (nonatomic, copy) NSString *songPath;
@end

@interface SBSoundController : NSObject
- (bool)_playSystemSound:(SBUISound *)sound;
@end

static NSString *BTClassicSoundPath;
static NSData *BTOriginalAudio;
static pthread_mutex_t BTAudioMutex = PTHREAD_MUTEX_INITIALIZER;
static char BTImageAnchor;
static bool (*BTOriginalPlayFeedback)(id, SEL, SBUISound *);

static NSString *BTCopyActiveSoundPath(void) {
    pthread_mutex_lock(&BTAudioMutex);
    NSString *path = [BTClassicSoundPath retain];
    pthread_mutex_unlock(&BTAudioMutex);
    return path;
}

static bool BTPrepareVolume(void) {
    int percent = BTReadVolume();
    NSMutableData *scaled = [BTOriginalAudio mutableCopy];
    if (!scaled || !BTScaleCAF(scaled.mutableBytes, scaled.length, (unsigned int)percent)) {
        [scaled release];
        NSLog(@"[ClassicLockSound] Could not prepare the selected volume.");
        return false;
    }
    NSString *directory = @"/var/mobile/Library/Caches/ClassicLockSound";
    /* Source hash + algorithm + gain make the audio server's file identity
       different from older releases and from every other slider setting. */
    NSString *filename = [NSString stringWithFormat:
        @"original-90d02d979ff94def-pcm1-%03d.caf", percent];
    NSString *path = [directory stringByAppendingPathComponent:filename];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes = @{NSFileProtectionKey:NSFileProtectionNone};
    NSError *error = nil;
    bool ready = [manager createDirectoryAtPath:directory withIntermediateDirectories:YES
                                    attributes:attributes error:&error];
    if (ready) ready = [manager setAttributes:attributes ofItemAtPath:directory error:&error];
    if (ready) {
        NSData *existing = [NSData dataWithContentsOfFile:path];
        ready = [existing isEqualToData:scaled] ||
            [scaled writeToFile:path options:NSDataWritingAtomic | NSDataWritingFileProtectionNone error:&error];
    }
    [scaled release];
    if (!ready) {
        NSLog(@"[ClassicLockSound] Volume preparation failed: %@", error);
        return false; /* Keep the last successfully prepared setting. */
    }
    pthread_mutex_lock(&BTAudioMutex);
    NSString *previous = BTClassicSoundPath;
    BTClassicSoundPath = [path copy];
    pthread_mutex_unlock(&BTAudioMutex);
    [previous release];
    return true;
}

static void BTRefreshVolume(void *context) {
    (void)context;
    @autoreleasepool { BTPrepareVolume(); }
}

static void BTVolumeDidChange(CFNotificationCenterRef center, void *observer,
                             CFStringRef name, const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)name; (void)object; (void)info;
    /* No block literals; serialize cache preparation with initialization. */
    dispatch_async_f(dispatch_get_main_queue(), NULL, BTRefreshVolume);
}

static NSString *BTResourcePath(void) {
    Dl_info image = {0};
    if (dladdr(&BTImageAnchor, &image) && image.dli_fname) {
        NSString *path = [NSString stringWithUTF8String:image.dli_fname];
        if ([path hasSuffix:@"/Library/MobileSubstrate/DynamicLibraries/ClassicLockSound.dylib"]) {
            NSString *library = [[[path stringByDeletingLastPathComponent]
                stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
            return [library stringByAppendingPathComponent:@"Application Support/ClassicLockSound/lock.caf"];
        }
        if ([path hasSuffix:@"/usr/lib/TweakInject/ClassicLockSound.dylib"]) {
            NSString *root = path;
            for (unsigned i = 0; i < 4; ++i) root = [root stringByDeletingLastPathComponent];
            return [root stringByAppendingPathComponent:@"Library/Application Support/ClassicLockSound/lock.caf"];
        }
    }
    return @THEOS_PACKAGE_INSTALL_PREFIX "/Library/Application Support/ClassicLockSound/lock.caf";
}

static bool BTTypeMatches(const char *encoding, char expected) {
    while (*encoding && strchr("rnNoORV", *encoding)) ++encoding;
    if (expected == '@') return encoding[0] == '@' && encoding[1] != '?';
    return encoding[0] == expected && encoding[1] == '\0';
}

static bool BTMethodMatches(Class cls, const char *name,
                            char resultType, const char *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName(name)) : NULL;
    if (!method || method_getNumberOfArguments(method) != strlen(arguments)) return false;
    char encoding[256] = {0};
    method_getReturnType(method, encoding, sizeof(encoding));
    if (!BTTypeMatches(encoding, resultType)) return false;
    for (unsigned i = 0; arguments[i]; ++i) {
        method_getArgumentType(method, i, encoding, sizeof(encoding));
        if (!BTTypeMatches(encoding, arguments[i])) return false;
    }
    return true;
}

static bool BTPlayFeedback(SBSoundController *controller, SEL command, SBUISound *sound) {
    if (![sound isKindOfClass:[SBUISound class]] ||
        !BTIsLockFeedback(sound.soundType, sound.eventType)) {
        return BTOriginalPlayFeedback(controller, command, sound);
    }

    // The parent playSound:environments:completion: has already applied its
    // environment policy. Preserve this very same sound object, its behavior,
    // vibration, event identity and completion ownership. Do not re-run a
    // separate shouldPlayLockSound query (the unsuccessful 1.0.2 approach).
    long long previousType = sound.soundType;
    NSString *previousPath = [sound.songPath retain];
    NSString *selectedPath = BTCopyActiveSoundPath();
    if (!selectedPath) {
        [previousPath release];
        return BTOriginalPlayFeedback(controller, command, sound);
    }
    sound.songPath = selectedPath;
    [selectedPath release];
    sound.soundType = BTSystemSoundType;

    // Native _playSystemSound: resolves songPath, installs its completion,
    // tracks the original object and plays the CAF. Leaving type=0 on success
    // lets subsequent stop/cleanup/replay requests take that same native path.
    // This is an Objective-C message with an object argument, never a sound ID
    // passed as an object and never an inline hook into AudioToolbox.
    bool started = [controller _playSystemSound:sound];
    if (!started) {
        // Its captured implementation returns false before starting playback
        // when completion registration fails. Restore the original request
        // before the fallback; never play both versions of the lock sound.
        sound.songPath = previousPath;
        sound.soundType = previousType;
    }
    [previousPath release];
    return started ? true : BTOriginalPlayFeedback(controller, command, sound);
}

static void BTStart(void *context) {
    (void)context;
    @autoreleasepool {
        // The explicit SpringBoardUI class reference loads the sound class.
        // Only install when every used private method has the captured ABI.
        Class sound = [SBUISound class];
        Class controller = objc_getClass("SBSoundController");
        if (!BTMethodMatches(controller, "_playFeedback:", 'B', "@:@") ||
            !BTMethodMatches(controller, "_playSystemSound:", 'B', "@:@") ||
            !BTMethodMatches(sound, "eventType", 'q', "@:") ||
            !BTMethodMatches(sound, "soundType", 'q', "@:") ||
            !BTMethodMatches(sound, "setSoundType:", 'v', "@:q") ||
            !BTMethodMatches(sound, "songPath", '@', "@:") ||
            !BTMethodMatches(sound, "setSongPath:", 'v', "@:@")) {
            NSLog(@"[ClassicLockSound] Unsupported sound-controller signatures; native playback retained.");
            return;
        }
        NSString *path = BTResourcePath();
        if (![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
            NSLog(@"[ClassicLockSound] Bundled lock sound unavailable; native playback retained.");
            return;
        }
        BTOriginalAudio = [[NSData alloc] initWithContentsOfFile:path];
        if (!BTPrepareVolume()) return;
        MSHookMessageEx(controller, sel_registerName("_playFeedback:"),
                        (IMP)BTPlayFeedback, (IMP *)&BTOriginalPlayFeedback);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            BTVolumeDidChange, BTVolumeChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}

__attribute__((constructor)) static void BTInitialize(void) {
    @autoreleasepool {
        if (!BTSupportsIOS17And18()) return;
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"])
            return;
        dispatch_async_f(dispatch_get_main_queue(), NULL, BTStart);
    }
}
