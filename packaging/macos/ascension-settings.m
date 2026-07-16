#import "ascension-settings.h"

static NSString *const PASupportDirectory = @"Project Ascension";

NSString *PASettingsPath(void)
{
    NSString *support = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    return [[support stringByAppendingPathComponent:PASupportDirectory]
        stringByAppendingPathComponent:@"settings.plist"];
}

NSDictionary<NSString *, id> *PADefaultSettings(void)
{
    return @{
        @"schemaVersion": @1,
        @"performanceOverlayEnabled": @NO,
        @"performanceOverlayPreset": @"off",
        @"overlayMetrics": @[@"fps", @"frametimes"],
        @"overlayScale": @1.0,
        @"overlayOpacity": @1.0,
        @"closeLauncherWhilePlaying": @YES,
        @"keepLauncherVisible": @NO,
        @"showLauncherAfterGame": @YES,
        @"confirmQuitWhileGameRunning": @YES,
    };
}

NSMutableDictionary<NSString *, id> *PALoadSettings(void)
{
    NSMutableDictionary<NSString *, id> *settings = [PADefaultSettings() mutableCopy];
    NSDictionary<NSString *, id> *saved = [NSDictionary dictionaryWithContentsOfFile:PASettingsPath()];
    if ([saved isKindOfClass:[NSDictionary class]]) {
        [settings addEntriesFromDictionary:saved];
    }
    return settings;
}

BOOL PASaveSettings(NSDictionary<NSString *, id> *settings, NSError **error)
{
    NSString *path = PASettingsPath();
    NSString *directory = [path stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:error]) {
        return NO;
    }

    NSData *data = [NSPropertyListSerialization dataWithPropertyList:settings
                                                               format:NSPropertyListXMLFormat_v1_0
                                                              options:0
                                                                error:error];
    if (data == nil) {
        return NO;
    }
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

BOOL PASettingBool(NSDictionary<NSString *, id> *settings, NSString *key)
{
    id value = settings[key];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

NSString *PAOverlayPreset(NSDictionary<NSString *, id> *settings)
{
    if (!PASettingBool(settings, @"performanceOverlayEnabled")) {
        return @"off";
    }
    NSString *preset = settings[@"performanceOverlayPreset"];
    if (![preset isKindOfClass:[NSString class]] || preset.length == 0) {
        return @"custom";
    }
    return preset;
}

NSString *PAHUDValue(NSDictionary<NSString *, id> *settings)
{
    if (!PASettingBool(settings, @"performanceOverlayEnabled")) {
        return @"";
    }

    NSString *preset = PAOverlayPreset(settings);
    NSArray<NSString *> *metrics;
    if ([preset isEqualToString:@"compact"]) {
        metrics = @[@"fps", @"frametimes"];
    } else if ([preset isEqualToString:@"detailed"]) {
        metrics = @[@"fps", @"frametimes", @"gpuload", @"memory", @"compiler"];
    } else {
        id savedMetrics = settings[@"overlayMetrics"];
        metrics = [savedMetrics isKindOfClass:[NSArray class]] ? savedMetrics : @[@"fps"];
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSSet<NSString *> *supported = [NSSet setWithArray:@[
        @"fps", @"frametimes", @"gpuload", @"memory", @"compiler", @"drawcalls",
        @"submissions", @"pipelines", @"api", @"devinfo", @"cs", @"version"
    ]];
    for (id metric in metrics) {
        if ([metric isKindOfClass:[NSString class]] && [supported containsObject:metric]) {
            [parts addObject:metric];
        }
    }
    if (parts.count == 0) {
        [parts addObject:@"fps"];
    }

    double scale = [settings[@"overlayScale"] doubleValue];
    double opacity = [settings[@"overlayOpacity"] doubleValue];
    scale = MAX(0.75, MIN(scale > 0.0 ? scale : 1.0, 2.0));
    opacity = MAX(0.25, MIN(opacity > 0.0 ? opacity : 1.0, 1.0));
    [parts addObject:[NSString stringWithFormat:@"scale=%.2f", scale]];
    [parts addObject:[NSString stringWithFormat:@"opacity=%.2f", opacity]];
    return [parts componentsJoinedByString:@","];
}
