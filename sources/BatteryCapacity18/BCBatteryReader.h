#import <Foundation/Foundation.h>
#import "CapacityRules.h"
#import "AmperageRules.h"

@interface BC18Snapshot : NSObject
@property(nonatomic) BCCapacities capacities;
@property(nonatomic) BCAmperage amperage;
@property(nonatomic, copy) NSString *serviceName;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy) NSDate *readAt;
@property(nonatomic, copy) NSDictionary *rawValues;
@end

@interface BC18BatteryReader : NSObject
@property(nonatomic, strong, readonly) BC18Snapshot *snapshot;
+ (instancetype)shared;
- (void)refresh;
- (NSString *)valueForMetric:(NSString *)metric;
- (NSString *)diagnosticText;
@end
