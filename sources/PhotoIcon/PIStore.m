#import "PIStore.h"
#import "PIBlockCompatibility.h"
#import "PIIconPublisher.h"

NSString *const PIIconsDidChangeNotification = @"com.brooktrout12.photoicon.iconsChanged";

@interface PIStore ()
@property(nonatomic, copy) NSString *directory;
@property(nonatomic, strong) NSMutableDictionary *manifest;
@property(nonatomic, strong) NSCache *cache;
@property(nonatomic, strong) dispatch_queue_t ioQueue;
- (void)publishSharedIcons;
@end

@implementation PIStore
+ (instancetype)sharedStore {
    static PIStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [PIStore new]; });
    return store;
}
- (instancetype)init {
    if ((self = [super init])) {
        // Per-user data belongs in mobile's Library, outside the read-only OS.
        _directory = @"/var/mobile/Library/Application Support/PhotoIcon";
        // Retire beta 3's temporary trace. Saved icon files are independent.
        [NSFileManager.defaultManager removeItemAtPath:
            [_directory stringByAppendingPathComponent:@"Bookmark-Diagnostics.txt"] error:nil];
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:
                               [_directory stringByAppendingPathComponent:@"Icons.plist"]];
        _manifest = [NSMutableDictionary new];
        // Validate local state before letting corrupt preferences reach hooks.
        [saved enumerateKeysAndObjectsUsingBlock:PI_SYSTEM_BLOCK(^(id key, id entry, BOOL *stop) {
            if (![key isKindOfClass:NSString.class] || ![entry isKindOfClass:NSDictionary.class]) return;
            NSString *token = entry[@"token"];
            if ([token isKindOfClass:NSString.class] && token.length == 36 &&
                [[NSUUID alloc] initWithUUIDString:token]) self.manifest[key] = entry;
        })];
        _cache = [NSCache new];
        _cache.totalCostLimit = 24 * 1024 * 1024;
        _ioQueue = dispatch_queue_create("com.brooktrout12.photoicon.files", DISPATCH_QUEUE_SERIAL);
        // Publish existing choices too; upgrading does not require reselecting photos.
        dispatch_async(_ioQueue, ^{ @autoreleasepool { [self publishSharedIcons]; } });
    }
    return self;
}
- (NSString *)pathForToken:(NSString *)token suffix:(NSString *)suffix {
    return [self.directory stringByAppendingPathComponent:[token stringByAppendingString:suffix]];
}
- (NSDictionary *)entryForIdentifier:(NSString *)identifier {
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) return nil;
    @synchronized (self) { return self.manifest[identifier]; }
}
- (BOOL)hasIconForBundleIdentifier:(NSString *)identifier {
    return [self entryForIdentifier:identifier] != nil;
}
- (UIImage *)imageForBundleIdentifier:(NSString *)identifier {
    NSDictionary *entry = [self entryForIdentifier:identifier];
    if (!entry) return nil;
    NSString *token = entry[@"token"];
    UIImage *image = [self.cache objectForKey:token];
    if (!image) {
        image = [UIImage imageWithContentsOfFile:[self pathForToken:token suffix:@".png"]];
        if (image) [self.cache setObject:image forKey:token cost:
                    CGImageGetWidth(image.CGImage) * CGImageGetHeight(image.CGImage) * 4];
    }
    return image;
}
- (UIImage *)sourceForBundleIdentifier:(NSString *)identifier {
    NSString *token = [self entryForIdentifier:identifier][@"token"];
    return token ? [UIImage imageWithContentsOfFile:[self pathForToken:token suffix:@"-source.png"]] : nil;
}
- (NSDictionary *)cropForBundleIdentifier:(NSString *)identifier {
    id crop = [self entryForIdentifier:identifier][@"crop"];
    return [crop isKindOfClass:NSDictionary.class] ? crop : nil;
}
- (BOOL)writeManifest:(NSDictionary *)manifest error:(NSError **)error {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:manifest
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return data && [data writeToFile:[self.directory stringByAppendingPathComponent:@"Icons.plist"]
                            options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication
                              error:error];
}
- (void)finish:(NSError *)error identifier:(NSString *)identifier
    completion:(void (^)(NSError *))completion {
    if (!error) [self publishSharedIcons];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!error) [[NSNotificationCenter defaultCenter] postNotificationName:PIIconsDidChangeNotification
            object:identifier];
        completion(error);
    });
}
- (void)publishSharedIcons {
    NSDictionary *snapshot;
    @synchronized (self) { snapshot = [self.manifest copy]; }
    NSError *error = nil;
    if (!PIPublishIcons(snapshot, self.directory, &error))
        NSLog(@"[PhotoIcon] Could not publish cropped app icons: %@", error.localizedDescription);
}
- (void)deleteFilesForEntry:(NSDictionary *)entry {
    NSString *token = entry[@"token"];
    if (!token) return;
    for (NSString *suffix in @[@".png", @"-source.png"]) {
        [[NSFileManager defaultManager] removeItemAtPath:[self pathForToken:token suffix:suffix] error:nil];
    }
    [self.cache removeObjectForKey:token];
}
- (void)saveImage:(UIImage *)image source:(UIImage *)source crop:(NSDictionary *)crop
    forBundleIdentifier:(NSString *)identifier completion:(void (^)(NSError *))completion {
    dispatch_async(self.ioQueue, ^{
        @autoreleasepool {
            NSError *error = nil;
            NSFileManager *fm = NSFileManager.defaultManager;
            BOOL success = [fm createDirectoryAtPath:self.directory withIntermediateDirectories:YES
                attributes:@{NSFilePosixPermissions:@0700} error:&error];
            NSString *token = NSUUID.UUID.UUIDString;
            NSDictionary *entry = @{@"token":token, @"crop":crop};
            NSData *iconData = UIImagePNGRepresentation(image);
            NSData *sourceData = UIImagePNGRepresentation(source);
            if (!iconData || !sourceData) {
                success = NO;
                error = [NSError errorWithDomain:@"PhotoIcon" code:1
                    userInfo:@{NSLocalizedDescriptionKey:@"This photo could not be saved."}];
            }
            NSDataWritingOptions options = NSDataWritingAtomic |
                NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
            if (success) success = [iconData writeToFile:[self pathForToken:token suffix:@".png"]
                                                 options:options error:&error];
            if (success) success = [sourceData writeToFile:[self pathForToken:token suffix:@"-source.png"]
                                                   options:options error:&error];
            NSDictionary *oldEntry;
            if (success) {
                @synchronized (self) {
                    NSMutableDictionary *next = [self.manifest mutableCopy];
                    oldEntry = next[identifier];
                    next[identifier] = entry;
                    success = [self writeManifest:next error:&error];
                    if (success) self.manifest = next;
                }
            }
            // Commit the new manifest last; failures preserve the previous icon.
            if (success) {
                [self.cache setObject:image forKey:token cost:512 * 512 * 4];
                [self deleteFilesForEntry:oldEntry];
            } else {
                [self deleteFilesForEntry:entry];
            }
            [self finish:error identifier:identifier completion:PI_SYSTEM_BLOCK(completion)];
        }
    });
}
- (void)removeIconForBundleIdentifier:(NSString *)identifier completion:(void (^)(NSError *))completion {
    dispatch_async(self.ioQueue, ^{
        NSError *error = nil;
        NSDictionary *oldEntry;
        @synchronized (self) {
            oldEntry = self.manifest[identifier];
            NSMutableDictionary *next = [self.manifest mutableCopy];
            [next removeObjectForKey:identifier];
            if (!oldEntry || [self writeManifest:next error:&error]) self.manifest = next;
        }
        if (!error) [self deleteFilesForEntry:oldEntry];
        [self finish:error identifier:identifier completion:PI_SYSTEM_BLOCK(completion)];
    });
}
@end
