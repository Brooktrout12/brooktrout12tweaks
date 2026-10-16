#import "BCBatteryReader.h"
#import "BCCommon.h"
#import <IOKit/IOKitLib.h>

// Exported by iOS IOKit; omitted by some versions of Theos's IOKit headers.
extern kern_return_t IORegistryEntryGetRegistryEntryID(io_registry_entry_t entry, uint64_t *entryID);

@implementation BC18Snapshot
@end

static BCAmperageReading BCAmperageNumber(id value, BCAmperageSource source) {
    BCAmperageReading reading = {.source = source};
    if (![value isKindOfClass:NSNumber.class]
        || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return reading;
    // Preserve integer precision: a negative registry current can arrive as a
    // signed integer or an unsigned 32/64-bit two's-complement representation.
    const char *type = [value objCType];
    switch (type ? type[0] : 0) {
        case 'c': case 's': case 'i': case 'l': case 'q':
            reading.kind = BCAmperageInputSigned;
            reading.value.signedValue = [value longLongValue];
            break;
        case 'C': case 'S': case 'I': case 'L': case 'Q':
            reading.kind = BCAmperageInputUnsigned;
            reading.value.unsignedValue = [value unsignedLongLongValue];
            break;
        case 'f': case 'd':
            reading.kind = BCAmperageInputFloating;
            reading.value.floatingValue = [value doubleValue];
            break;
    }
    return reading;
}

static BC18Snapshot *BCParseProperties(NSDictionary *properties, NSString *serviceName) {
    BC18Snapshot *snapshot = [BC18Snapshot new];
    snapshot.readAt = [NSDate date];
    snapshot.serviceName = serviceName;
    NSMutableDictionary *raw = [NSMutableDictionary dictionary];
    NSDictionary *nested = [properties[@"BatteryData"] isKindOfClass:NSDictionary.class]
        ? properties[@"BatteryData"] : @{};
    BCReading readings[BCSourceLimit - 1] = {0};
    const NSUInteger readingCount = sizeof(readings) / sizeof(readings[0]);
    for (NSUInteger i = 0; i < readingCount; i++) {
        BCSource source = (BCSource)(i + 1);
        NSString *path = @(BCSourceKey(source));
        BOOL inBatteryData = [path hasPrefix:@"BatteryData."];
        NSString *key = inBatteryData ? [path substringFromIndex:12] : path;
        id value = (inBatteryData ? nested : properties)[key];
        BOOL numeric = [value isKindOfClass:NSNumber.class]
            && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID();
        readings[i] = (BCReading){source, numeric ? [value doubleValue] : 0, numeric};
        if (numeric) raw[path] = value;
        else if (value) raw[path] = @"Rejected nonnumeric value";
    }
    snapshot.capacities = BCSelectCapacities(readings, readingCount);
    BCAmperageReading amperageReadings[BCAmperageSourceLimit - 1] = {0};
    const NSUInteger amperageCount = sizeof(amperageReadings) / sizeof(amperageReadings[0]);
    for (NSUInteger i = 0; i < amperageCount; i++) {
        BCAmperageSource source = (BCAmperageSource)(i + 1);
        NSString *path = @(BCAmperageSourceKey(source));
        BOOL inBatteryData = [path hasPrefix:@"BatteryData."];
        NSString *key = inBatteryData ? [path substringFromIndex:12] : path;
        id value = (inBatteryData ? nested : properties)[key];
        amperageReadings[i] = BCAmperageNumber(value, source);
        if (amperageReadings[i].kind != BCAmperageInputInvalid) raw[path] = value;
        else if (value) raw[path] = @"Rejected nonnumeric value";
    }
    snapshot.amperage = BCSelectAmperage(amperageReadings, amperageCount);
    snapshot.rawValues = raw;
    BCCapacities c = snapshot.capacities;
    snapshot.status = c.hasRatio ? @"Reported capacity and design capacity available"
        : c.hasFullCharge ? @"Battery did not expose a valid DesignCapacity in mAh"
        : c.hasDesign ? @"Battery did not expose a valid full-charge capacity in mAh"
        : c.hasCurrentCharge ? @"Only current charge available; full-charge/design capacities unavailable"
        : @"Battery did not expose usable capacity values in mAh";
    return snapshot;
}

static NSInteger BCScore(BC18Snapshot *snapshot) {
    BCCapacities c = snapshot.capacities;
    return (c.hasRatio ? 100 : 0) + (c.hasFullCharge ? 20 : 0)
        + (c.hasDesign ? 10 : 0)
        + (c.hasFullCharge && c.fullChargeSource <= BCSourceBatteryDataNominal ? 2 : 0)
        + (c.hasCurrentCharge ? 1 : 0);
}

static BC18Snapshot *BCReadBattery(void) {
    BC18Snapshot *best = nil;
    NSMutableSet *seen = [NSMutableSet set];
    kern_return_t lastResult = KERN_SUCCESS;
    // Enumerating the base class is only a discovery fallback. It is never used
    // to select an external accessory as the phone's battery.
    const char *classes[] = {"AppleSmartBattery", "AppleARMPMUPowerSource", "IOPMPowerSource"};
    for (NSUInteger n = 0; n < 3; n++) {
        io_iterator_t iterator = IO_OBJECT_NULL;
        lastResult = IOServiceGetMatchingServices(MACH_PORT_NULL,
            IOServiceMatching(classes[n]), &iterator);
        if (lastResult != KERN_SUCCESS || iterator == IO_OBJECT_NULL) continue;
        io_service_t service;
        while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
            BOOL internal = IOObjectConformsTo(service, "AppleSmartBattery")
                || IOObjectConformsTo(service, "AppleARMPMUPowerSource");
            uint64_t entryID = 0;
            IORegistryEntryGetRegistryEntryID(service, &entryID);
            if (!internal || (entryID && [seen containsObject:@(entryID)])) {
                IOObjectRelease(service);
                continue;
            }
            if (entryID) [seen addObject:@(entryID)];
            CFMutableDictionaryRef raw = NULL;
            lastResult = IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0);
            io_name_t serviceName = {0};
            IORegistryEntryGetName(service, serviceName);
            IOObjectRelease(service);
            NSDictionary *properties = CFBridgingRelease(raw);
            if (lastResult != KERN_SUCCESS || ![properties isKindOfClass:NSDictionary.class]) continue;
            id installed = properties[@"BatteryInstalled"];
            if ([installed isKindOfClass:NSNumber.class] && ![installed boolValue]) continue;
            BC18Snapshot *candidate = BCParseProperties(properties, @(serviceName));
            // Keep all readings from ONE registry entry. An amperage reading
            // breaks a capacity-score tie; it never displaces better capacities.
            if (!best || BCScore(candidate) > BCScore(best)
                || (BCScore(candidate) == BCScore(best)
                    && candidate.amperage.available && !best.amperage.available)) best = candidate;
        }
        IOObjectRelease(iterator);
        if (best && best.capacities.hasRatio && best.capacities.hasCurrentCharge && best.amperage.available
            && best.capacities.fullChargeSource <= BCSourceBatteryDataNominal) break;
    }
    if (!best) {
        best = [BC18Snapshot new];
        best.readAt = [NSDate date];
        best.serviceName = @"Unavailable";
        best.status = [NSString stringWithFormat:@"No readable internal battery registry entry (IOKit 0x%08x)", lastResult];
        best.rawValues = @{};
    }
    return best;
}

@interface BC18BatteryReader ()
@property(nonatomic, strong, readwrite) BC18Snapshot *snapshot;
@property(nonatomic, strong) dispatch_queue_t readQueue;
@property(nonatomic) BOOL reading;
@end

static BC18BatteryReader *gReader;

static void BCInitializeReader(__unused void *context) {
    gReader = [BC18BatteryReader new];
}

static void BCRefreshReaderOnMain(void *context) {
    @autoreleasepool {
        BC18BatteryReader *reader = CFBridgingRelease(context);
        [reader refresh];
    }
}

static void BCDeliverReadingOnMain(void *context) {
    @autoreleasepool {
        NSArray *delivery = CFBridgingRelease(context);
        BC18BatteryReader *reader = delivery[0];
        reader.snapshot = delivery[1]; // Failed reads also replace old values.
        reader.reading = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:BCReadingChangedNotification object:reader];
    }
}

static void BCReadOnWorkerQueue(void *context) {
    @autoreleasepool {
        BC18BatteryReader *reader = CFBridgingRelease(context);
        BC18Snapshot *result = BCReadBattery();
        NSArray *delivery = @[reader, result];
        dispatch_async_f(dispatch_get_main_queue(), (__bridge_retained void *)delivery, BCDeliverReadingOnMain);
    }
}

@implementation BC18BatteryReader
+ (instancetype)shared {
    static dispatch_once_t once;
    dispatch_once_f(&once, NULL, BCInitializeReader);
    return gReader;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _readQueue = dispatch_queue_create("com.brooktrout12.batterycapacity18.reader", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (void)refresh {
    if (!NSThread.isMainThread) {
        dispatch_async_f(dispatch_get_main_queue(), (__bridge_retained void *)self, BCRefreshReaderOnMain);
        return;
    }
    if (self.reading) return;
    self.reading = YES;
    dispatch_async_f(self.readQueue, (__bridge_retained void *)self, BCReadOnWorkerQueue);
}
- (NSString *)valueForMetric:(NSString *)metric {
    BC18Snapshot *snapshot = self.snapshot;
    if (!snapshot) return BCLocal(@"Reading…", @"Wird gelesen…");
    BCCapacities c = snapshot.capacities;
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 0;
    if ([metric isEqualToString:@"full"] && c.hasFullCharge)
        return [[formatter stringFromNumber:@(c.fullChargeMAh)] stringByAppendingString:@" mAh"];
    if ([metric isEqualToString:@"design"] && c.hasDesign)
        return [[formatter stringFromNumber:@(c.designMAh)] stringByAppendingString:@" mAh"];
    if ([metric isEqualToString:@"current"] && c.hasCurrentCharge)
        return [[formatter stringFromNumber:@(c.currentChargeMAh)] stringByAppendingString:@" mAh"];
    if ([metric isEqualToString:@"discharge"] && snapshot.amperage.available) {
        long long signedMA = snapshot.amperage.signedMA;
        if (signedMA > 0) return BCLocal(@"Charging", @"Wird geladen");
        return [[formatter stringFromNumber:@(-signedMA)] stringByAppendingString:@" mA"];
    }
    if ([metric isEqualToString:@"ratio"] && c.hasRatio) {
        formatter.numberStyle = NSNumberFormatterPercentStyle;
        formatter.minimumFractionDigits = 1;
        formatter.maximumFractionDigits = 1;
        return [formatter stringFromNumber:@(c.ratioPercent / 100.0)];
    }
    return BCLocal(@"Unavailable", @"Nicht verfügbar");
}
- (NSString *)diagnosticText {
    BC18Snapshot *s = self.snapshot;
    if (!s) return @"No battery reading yet. Open Battery Health first.";
    BCCapacities c = s.capacities;
    return [NSString stringWithFormat:
        @"Battery Capacity 18 v1.0.5\nOS: %@\nRead: %@\nService: %@\nStatus: %@\nFull-charge source: %s\nDesign source: %s\nCurrent-charge source: %s\nAmperage source: %s\nFull-charge: %@\nDesign: %@\nRatio: %@\nCurrent charge: %@\nCurrent discharge rate: %@\nSigned battery current (negative = discharging): %@\nWhitelisted raw readings: %@\n",
        NSProcessInfo.processInfo.operatingSystemVersionString, s.readAt, s.serviceName,
        s.status, BCSourceKey(c.fullChargeSource), BCSourceKey(c.designSource), BCSourceKey(c.currentChargeSource),
        BCAmperageSourceKey(s.amperage.source),
        [self valueForMetric:@"full"], [self valueForMetric:@"design"],
        [self valueForMetric:@"ratio"], [self valueForMetric:@"current"],
        [self valueForMetric:@"discharge"],
        s.amperage.available ? [NSString stringWithFormat:@"%lld mA", s.amperage.signedMA] : @"Unavailable",
        s.rawValues];
}
@end
