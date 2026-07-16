#import <AppKit/AppKit.h>

#import "ascension-settings.h"

static NSInteger const PAMenuMarkerTag = 0x50414D45;
static NSInteger const PAOverlayOffTag = 0x50414F01;
static NSInteger const PAOverlayCompactTag = 0x50414F02;
static NSInteger const PAOverlayDetailedTag = 0x50414F03;

@interface PAMenuController : NSObject <NSMenuDelegate>
@property(nonatomic, strong) NSMenu *overlayMenu;
@end

@implementation PAMenuController

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationActivated:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)applicationActivated:(NSNotification *)notification
{
    (void)notification;
    [self installMenuIfNeeded];
}

- (void)installMenuIfNeeded
{
    NSMenu *mainMenu = NSApp.mainMenu;
    if (mainMenu.numberOfItems == 0) return;
    NSMenuItem *applicationItem = [mainMenu itemAtIndex:0];
    NSMenu *applicationMenu = applicationItem.submenu;
    if (applicationMenu == nil || [applicationMenu itemWithTag:PAMenuMarkerTag] != nil) return;

    applicationItem.title = @"Project Ascension";

    for (NSInteger index = applicationMenu.numberOfItems - 1; index >= 0; index--) {
        NSMenuItem *item = [applicationMenu itemAtIndex:index];
        if ([item.keyEquivalent.lowercaseString isEqualToString:@"q"] ||
            [item.title hasPrefix:@"Quit "]) {
            [applicationMenu removeItemAtIndex:index];
        }
    }

    NSMenuItem *marker = [[NSMenuItem alloc] initWithTitle:@"About Project Ascension"
                                                   action:@selector(showAbout:)
                                            keyEquivalent:@""];
    marker.tag = PAMenuMarkerTag;
    marker.target = self;
    [applicationMenu insertItem:marker atIndex:0];
    [applicationMenu insertItem:NSMenuItem.separatorItem atIndex:1];

    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…"
                                                     action:@selector(openSettings:)
                                              keyEquivalent:@","];
    settings.target = self;
    [applicationMenu insertItem:settings atIndex:2];

    NSMenuItem *overlay = [[NSMenuItem alloc] initWithTitle:@"Performance Overlay"
                                                    action:nil keyEquivalent:@""];
    self.overlayMenu = [[NSMenu alloc] initWithTitle:@"Performance Overlay"];
    self.overlayMenu.delegate = self;
    [self addOverlayItem:@"Off" preset:@"off" tag:PAOverlayOffTag];
    [self addOverlayItem:@"Compact" preset:@"compact" tag:PAOverlayCompactTag];
    [self addOverlayItem:@"Detailed" preset:@"detailed" tag:PAOverlayDetailedTag];
    [self.overlayMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *custom = [[NSMenuItem alloc] initWithTitle:@"Custom…"
                                                   action:@selector(openSettings:)
                                            keyEquivalent:@""];
    custom.target = self;
    [self.overlayMenu addItem:custom];
    overlay.submenu = self.overlayMenu;
    [applicationMenu insertItem:overlay atIndex:3];

    NSMenuItem *logs = [[NSMenuItem alloc] initWithTitle:@"Open Diagnostic Logs"
                                                 action:@selector(openLogs:)
                                          keyEquivalent:@""];
    logs.target = self;
    [applicationMenu insertItem:logs atIndex:4];
    [applicationMenu insertItem:NSMenuItem.separatorItem atIndex:5];

    NSMenuItem *uninstall = [[NSMenuItem alloc] initWithTitle:@"Uninstall Project Ascension…"
                                                      action:@selector(uninstall:)
                                               keyEquivalent:@""];
    uninstall.target = self;
    [applicationMenu insertItem:uninstall atIndex:6];

    [applicationMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Project Ascension"
                                                 action:@selector(quit:)
                                          keyEquivalent:@"q"];
    quit.target = self;
    [applicationMenu addItem:quit];
}

- (void)addOverlayItem:(NSString *)title preset:(NSString *)preset tag:(NSInteger)tag
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                 action:@selector(selectOverlay:)
                                          keyEquivalent:@""];
    item.target = self;
    item.representedObject = preset;
    item.tag = tag;
    [self.overlayMenu addItem:item];
}

- (void)menuWillOpen:(NSMenu *)menu
{
    if (menu != self.overlayMenu) return;
    NSString *preset = PAOverlayPreset(PALoadSettings());
    NSDictionary<NSString *, NSNumber *> *tags = @{
        @"off": @(PAOverlayOffTag), @"compact": @(PAOverlayCompactTag),
        @"detailed": @(PAOverlayDetailedTag)
    };
    for (NSNumber *tag in tags.allValues) {
        [menu itemWithTag:tag.integerValue].state = NSControlStateValueOff;
    }
    NSNumber *selected = tags[preset];
    if (selected != nil) [menu itemWithTag:selected.integerValue].state = NSControlStateValueOn;
}

- (void)selectOverlay:(NSMenuItem *)sender
{
    NSString *preset = sender.representedObject;
    NSMutableDictionary *settings = PALoadSettings();
    settings[@"performanceOverlayEnabled"] = @(![preset isEqualToString:@"off"]);
    settings[@"performanceOverlayPreset"] = preset;
    NSError *error = nil;
    if (!PASaveSettings(settings, &error)) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Overlay Setting Could Not Be Saved";
        alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
        return;
    }
    for (NSInteger tag = PAOverlayOffTag; tag <= PAOverlayDetailedTag; tag++) {
        [self.overlayMenu itemWithTag:tag].state = NSControlStateValueOff;
    }
    sender.state = NSControlStateValueOn;
    [self showRestartNotice];
}

- (void)openSettings:(id)sender
{
    (void)sender;
    [self launchHelper:@[] activate:YES];
}

- (void)openLogs:(id)sender
{
    (void)sender;
    NSString *logs = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Project Ascension"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logs
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:logs]];
}

- (void)uninstall:(id)sender
{
    (void)sender;
    [self launchHelper:@[@"--uninstall"] activate:YES];
}

- (void)showAbout:(id)sender
{
    (void)sender;
    NSString *root = NSProcessInfo.processInfo.environment[@"ASCENSION_APP_ROOT"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [root stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"Unknown";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Project Ascension for Mac";
    alert.informativeText = [NSString stringWithFormat:
        @"Version %@\n\nRuns the official Project Ascension launcher through a macOS compatibility runtime.",
        version];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)quit:(id)sender
{
    (void)sender;
    if (PASettingBool(PALoadSettings(), @"confirmQuitWhileGameRunning") && [self gameIsRunning]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Quit while the game is running?";
        alert.informativeText = @"Quitting Project Ascension may close the active game session.";
        [alert addButtonWithTitle:@"Quit"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.alertStyle = NSAlertStyleWarning;
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
    }
    [NSApp terminate:nil];
}

- (BOOL)gameIsRunning
{
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pgrep"];
    task.arguments = @[@"-f", @"ascension-live.*Ascension\\.exe|MMgr64\\.exe"];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return NO;
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

- (void)launchHelper:(NSArray<NSString *> *)arguments activate:(BOOL)activate
{
    NSString *resources = NSProcessInfo.processInfo.environment[@"ASCENSION_APP_RESOURCES"];
    NSString *helper = [resources stringByAppendingPathComponent:@"ascension-settings"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) return;

    NSTask *task = [[NSTask alloc] init];
    if (activate) {
        NSString *settingsApp = [resources stringByAppendingPathComponent:@"Ascension Settings.app"];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
        NSMutableArray<NSString *> *openArguments = [NSMutableArray arrayWithObjects:@"-n", settingsApp, nil];
        if (arguments.count > 0) {
            [openArguments addObject:@"--args"];
            [openArguments addObjectsFromArray:arguments];
        }
        task.arguments = openArguments;
    } else {
        task.executableURL = [NSURL fileURLWithPath:helper];
        task.arguments = arguments;
    }
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    [environment removeObjectForKey:@"DYLD_INSERT_LIBRARIES"];
    [environment removeObjectForKey:@"ASCENSION_MENU_ENABLED"];
    task.environment = environment;
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    [task launchAndReturnError:&error];
    (void)activate;
}

- (void)showRestartNotice
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Performance Overlay Updated";
    alert.informativeText = @"The change applies the next time Project Ascension starts.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)attemptInstall:(NSNumber *)attempt
{
    [self installMenuIfNeeded];
    if (NSApp.mainMenu.numberOfItems == 0 && attempt.unsignedIntegerValue < 80) {
        [self performSelector:@selector(attemptInstall:)
                   withObject:@(attempt.unsignedIntegerValue + 1)
                   afterDelay:0.1];
    }
}

@end

static PAMenuController *PAMenuControllerInstance;

__attribute__((constructor)) static void PAInstallMenu(void)
{
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.environment[@"ASCENSION_MENU_ENABLED"] boolValue]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            PAMenuControllerInstance = [[PAMenuController alloc] init];
            [PAMenuControllerInstance attemptInstall:@0];
        });
    }
}
