#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *PASettingsPath(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *PADefaultSettings(void);
FOUNDATION_EXPORT NSMutableDictionary<NSString *, id> *PALoadSettings(void);
FOUNDATION_EXPORT BOOL PASaveSettings(NSDictionary<NSString *, id> *settings, NSError **error);
FOUNDATION_EXPORT NSString *PAHUDValue(NSDictionary<NSString *, id> *settings);
FOUNDATION_EXPORT NSString *PAOverlayPreset(NSDictionary<NSString *, id> *settings);
FOUNDATION_EXPORT BOOL PASettingBool(NSDictionary<NSString *, id> *settings, NSString *key);

NS_ASSUME_NONNULL_END
