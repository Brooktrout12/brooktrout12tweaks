#import "PISharedPaths.h"
#include <dlfcn.h>

NSString *PISharedIconDirectory(void) {
    static NSString *directory;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Resolve relative to the loaded tweak, including relocated jb roots.
        Dl_info info = {0};
        NSString *prefix = @"/var/jb";
        if (dladdr((const void *)&PISharedIconDirectory, &info) && info.dli_fname) {
            NSString *image = [NSString stringWithUTF8String:info.dli_fname];
            NSRange marker = [image rangeOfString:@"/Library/MobileSubstrate/DynamicLibraries/"
                                         options:NSBackwardsSearch];
            if (marker.location != NSNotFound && marker.location > 0)
                prefix = [image substringToIndex:marker.location];
        }
        directory = [prefix stringByAppendingPathComponent:@"var/mobile/Library/Caches/PhotoIcon"];
    });
    return directory;
}
