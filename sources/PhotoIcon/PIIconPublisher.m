#import "PIIconPublisher.h"
#import "PISharedPaths.h"
#include <notify.h>

BOOL PIPublishIcons(NSDictionary *manifest, NSString *privateDirectory, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *directory = PISharedIconDirectory();
    if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES
                        attributes:@{NSFilePosixPermissions:@0755} error:error]) return NO;
    NSString *catalogPath = [directory stringByAppendingPathComponent:@"Icons.plist"];
    NSDictionary *previousCatalog = [NSDictionary dictionaryWithContentsOfFile:catalogPath];
    id previousTokens = previousCatalog[@"icons"];
    NSMutableSet *previousFiles = [NSMutableSet new];
    if ([previousTokens isKindOfClass:NSDictionary.class]) {
        for (id token in [previousTokens allValues]) {
            if ([token isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:token])
                [previousFiles addObject:[token stringByAppendingString:@".png"]];
        }
    }
    NSMutableDictionary *tokens = [NSMutableDictionary new];
    NSMutableSet *activeFiles = [NSMutableSet new];
    NSDataWritingOptions options = NSDataWritingAtomic |
        NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
    for (id identifier in manifest) {
        if (![identifier isKindOfClass:NSString.class]) continue;
        id entry = manifest[identifier];
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id token = entry[@"token"];
        if (![token isKindOfClass:NSString.class] || [token length] != 36 ||
            ![[NSUUID alloc] initWithUUIDString:token]) continue;
        NSString *name = [token stringByAppendingString:@".png"];
        NSString *target = [directory stringByAppendingPathComponent:name];
        if (![fm fileExistsAtPath:target]) {
            // The source photo and crop metadata never leave private storage.
            NSData *png = [NSData dataWithContentsOfFile:
                [privateDirectory stringByAppendingPathComponent:name] options:0 error:error];
            if (!png || ![png writeToFile:target options:options error:error]) return NO;
            if (![fm setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:target error:error]) return NO;
        }
        tokens[identifier] = token;
        [activeFiles addObject:name];
    }
    NSDictionary *catalog = @{@"version":@1, @"revision":NSUUID.UUID.UUIDString, @"icons":tokens};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:catalog
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToFile:catalogPath options:options error:error]) return NO;
    if (![fm setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:catalogPath error:error]) return NO;
    // Commit the catalog after every referenced PNG is in place.
    notify_post(PI_SHARED_ICON_NOTIFICATION);
    // Give clients with an in-flight old snapshot five minutes to finish.
    for (NSString *name in [fm contentsOfDirectoryAtPath:directory error:nil]) {
        if (![name.pathExtension isEqualToString:@"png"] || [activeFiles containsObject:name]) continue;
        if (![[NSUUID alloc] initWithUUIDString:name.stringByDeletingPathExtension]) continue;
        NSString *path = [directory stringByAppendingPathComponent:name];
        if ([previousFiles containsObject:name]) {
            [fm setAttributes:@{NSFileModificationDate:[NSDate date]} ofItemAtPath:path error:nil];
            continue;
        }
        NSDate *modified = [fm attributesOfItemAtPath:path error:nil][NSFileModificationDate];
        if (modified && -modified.timeIntervalSinceNow > 300) [fm removeItemAtPath:path error:nil];
    }
    return YES;
}
