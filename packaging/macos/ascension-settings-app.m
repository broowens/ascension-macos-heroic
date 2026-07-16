#import <AppKit/AppKit.h>
#import <sys/sysctl.h>

#import "ascension-settings.h"

static NSString *const PAResourcesEnvironment = @"ASCENSION_APP_RESOURCES";

static NSString *PAResourcesPath(void)
{
    NSString *path = NSProcessInfo.processInfo.environment[PAResourcesEnvironment];
    if (path.length > 0) {
        return path;
    }
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    if ([bundlePath.pathExtension.lowercaseString isEqualToString:@"app"]) {
        NSString *outerResources = [bundlePath stringByDeletingLastPathComponent];
        if ([outerResources.lastPathComponent isEqualToString:@"Resources"]) {
            return outerResources;
        }
    }
    return [[[NSProcessInfo.processInfo.arguments.firstObject stringByDeletingLastPathComponent]
        stringByStandardizingPath] copy];
}

static NSString *PAAppRoot(void)
{
    NSString *resources = PAResourcesPath();
    if ([[resources lastPathComponent] isEqualToString:@"Resources"]) {
        return [[resources stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    }
    return @"/Applications/Project Ascension.app";
}

static NSString *PASupportPath(void)
{
    return [PASettingsPath() stringByDeletingLastPathComponent];
}

static NSTextField *PALabel(NSString *text, CGFloat size, NSFontWeight weight)
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.maximumNumberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    return label;
}

static NSButton *PACheckbox(NSString *title, id target, SEL action)
{
    NSButton *button = [NSButton checkboxWithTitle:title target:target action:action];
    button.font = [NSFont systemFontOfSize:13.0];
    return button;
}

static NSButton *PAButton(NSString *title, id target, SEL action)
{
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

static NSStackView *PAVerticalStack(void)
{
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

static NSView *PAWrapView(NSStackView *stack)
{
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 470)];
    [view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor constant:-24.0],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor constant:24.0],
    ]];
    return view;
}

@interface PASettingsController : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *settings;
@property(nonatomic, strong) NSButton *overlayEnabled;
@property(nonatomic, strong) NSPopUpButton *preset;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *metricButtons;
@property(nonatomic, strong) NSSlider *scale;
@property(nonatomic, strong) NSTextField *scaleValue;
@property(nonatomic, strong) NSSlider *opacity;
@property(nonatomic, strong) NSTextField *opacityValue;
@property(nonatomic, strong) NSButton *closeLauncherWhilePlaying;
@property(nonatomic, strong) NSButton *keepLauncherVisible;
@property(nonatomic, strong) NSButton *showLauncherAfterGame;
@property(nonatomic, strong) NSButton *confirmQuit;
@property(nonatomic, copy) NSString *startupAction;
@end

@implementation PASettingsController

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    self.settings = PALoadSettings();
    self.metricButtons = [NSMutableDictionary dictionary];
    [self buildWindow];
    [self loadControls];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    if ([self.startupAction isEqualToString:@"uninstall"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self uninstall:nil]; });
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)buildWindow
{
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 680, 520)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"Project Ascension Settings";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;

    NSTabViewController *tabs = [[NSTabViewController alloc] init];
    tabs.tabStyle = NSTabViewControllerTabStyleSegmentedControlOnTop;
    [tabs addTabViewItem:[self tabWithTitle:@"General" view:[self generalView]]];
    [tabs addTabViewItem:[self tabWithTitle:@"Performance Overlay" view:[self performanceView]]];
    [tabs addTabViewItem:[self tabWithTitle:@"Support" view:[self supportView]]];
    self.window.contentViewController = tabs;
}

- (NSTabViewItem *)tabWithTitle:(NSString *)title view:(NSView *)view
{
    NSViewController *controller = [[NSViewController alloc] init];
    controller.view = view;
    NSTabViewItem *item = [NSTabViewItem tabViewItemWithViewController:controller];
    item.label = title;
    return item;
}

- (NSView *)generalView
{
    NSStackView *stack = PAVerticalStack();
    [stack addArrangedSubview:PALabel(@"Launcher Behaviour", 18.0, NSFontWeightSemibold)];
    [stack addArrangedSubview:PALabel(
        @"These options control the macOS wrapper without changing the official launcher or game files.",
        12.0, NSFontWeightRegular)];

    self.closeLauncherWhilePlaying = PACheckbox(
        @"Close the launcher after the game starts (recommended)", self,
        @selector(launcherBehaviourChanged:));
    self.keepLauncherVisible = PACheckbox(@"Keep the launcher visible while playing", self,
        @selector(launcherBehaviourChanged:));
    self.showLauncherAfterGame = PACheckbox(@"Show the launcher when the game exits", self, nil);
    self.confirmQuit = PACheckbox(@"Confirm before quitting while the game is running", self, nil);
    [stack addArrangedSubview:self.closeLauncherWhilePlaying];
    [stack addArrangedSubview:self.keepLauncherVisible];
    [stack addArrangedSubview:self.showLauncherAfterGame];
    [stack addArrangedSubview:self.confirmQuit];

    NSView *spacer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 14)];
    [stack addArrangedSubview:spacer];
    NSButton *restore = PAButton(@"Restore All Defaults", self, @selector(restoreDefaults:));
    [stack addArrangedSubview:restore];
    [stack addArrangedSubview:PALabel(
        @"Restoring defaults disables the overlay and resets wrapper behaviour. It does not remove game data.",
        11.0, NSFontWeightRegular)];

    NSButton *save = PAButton(@"Save Settings", self, @selector(save:));
    save.keyEquivalent = @"\r";
    [stack addArrangedSubview:save];
    return PAWrapView(stack);
}

- (NSView *)performanceView
{
    NSStackView *stack = PAVerticalStack();
    [stack addArrangedSubview:PALabel(@"Performance Overlay", 18.0, NSFontWeightSemibold)];
    [stack addArrangedSubview:PALabel(
        @"Displays local, live DXVK statistics in the game. No performance data is uploaded or retained.",
        12.0, NSFontWeightRegular)];

    self.overlayEnabled = PACheckbox(@"Enable performance overlay", self, @selector(overlayChanged:));
    [stack addArrangedSubview:self.overlayEnabled];

    NSStackView *presetRow = [NSStackView stackViewWithViews:@[PALabel(@"Preset:", 13.0, NSFontWeightMedium)]];
    presetRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    presetRow.spacing = 8.0;
    self.preset = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.preset addItemsWithTitles:@[@"Compact", @"Detailed", @"Custom"]];
    self.preset.target = self;
    self.preset.action = @selector(presetChanged:);
    [presetRow addArrangedSubview:self.preset];
    [stack addArrangedSubview:presetRow];

    [stack addArrangedSubview:PALabel(@"Metrics", 14.0, NSFontWeightSemibold)];
    NSArray<NSArray<NSString *> *> *metrics = @[
        @[@"fps", @"FPS"],
        @[@"frametimes", @"Frame-time graph"],
        @[@"gpuload", @"Estimated GPU load"],
        @[@"memory", @"Graphics memory usage"],
        @[@"compiler", @"Shader compilation activity"],
        @[@"drawcalls", @"Draw calls"],
        @[@"submissions", @"Command submissions"],
        @[@"pipelines", @"Pipeline count"],
        @[@"api", @"Graphics API"],
        @[@"devinfo", @"GPU and driver information"],
        @[@"cs", @"Worker-thread statistics"],
        @[@"version", @"DXVK version"],
    ];
    NSMutableArray<NSArray<NSView *> *> *gridRows = [NSMutableArray array];
    for (NSUInteger index = 0; index < metrics.count; index += 2) {
        NSMutableArray<NSView *> *row = [NSMutableArray array];
        for (NSUInteger column = 0; column < 2; column++) {
            NSUInteger metricIndex = index + column;
            if (metricIndex < metrics.count) {
                NSString *key = metrics[metricIndex][0];
                NSButton *button = PACheckbox(metrics[metricIndex][1], self, @selector(metricChanged:));
                button.identifier = key;
                self.metricButtons[key] = button;
                [row addObject:button];
            } else {
                [row addObject:[[NSView alloc] init]];
            }
        }
        [gridRows addObject:row];
    }
    NSGridView *grid = [NSGridView gridViewWithViews:gridRows];
    grid.rowSpacing = 5.0;
    grid.columnSpacing = 24.0;
    [stack addArrangedSubview:grid];

    NSStackView *scaleRow = [NSStackView stackViewWithViews:@[PALabel(@"Scale", 13.0, NSFontWeightMedium)]];
    scaleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    scaleRow.spacing = 8.0;
    self.scale = [NSSlider sliderWithValue:1.0 minValue:0.75 maxValue:2.0
                                    target:self action:@selector(sliderChanged:)];
    self.scale.continuous = YES;
    [self.scale.widthAnchor constraintEqualToConstant:220].active = YES;
    self.scaleValue = PALabel(@"100%", 12.0, NSFontWeightRegular);
    [scaleRow addArrangedSubview:self.scale];
    [scaleRow addArrangedSubview:self.scaleValue];
    [stack addArrangedSubview:scaleRow];

    NSStackView *opacityRow = [NSStackView stackViewWithViews:@[PALabel(@"Opacity", 13.0, NSFontWeightMedium)]];
    opacityRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    opacityRow.spacing = 8.0;
    self.opacity = [NSSlider sliderWithValue:1.0 minValue:0.25 maxValue:1.0
                                      target:self action:@selector(sliderChanged:)];
    self.opacity.continuous = YES;
    [self.opacity.widthAnchor constraintEqualToConstant:220].active = YES;
    self.opacityValue = PALabel(@"100%", 12.0, NSFontWeightRegular);
    [opacityRow addArrangedSubview:self.opacity];
    [opacityRow addArrangedSubview:self.opacityValue];
    [stack addArrangedSubview:opacityRow];

    [stack addArrangedSubview:PALabel(
        @"GPU load is estimated and may be inaccurate. Overlay changes apply the next time Project Ascension starts.",
        11.0, NSFontWeightRegular)];
    NSButton *save = PAButton(@"Save Settings", self, @selector(save:));
    save.keyEquivalent = @"\r";
    [stack addArrangedSubview:save];
    return PAWrapView(stack);
}

- (NSView *)supportView
{
    NSStackView *stack = PAVerticalStack();
    [stack addArrangedSubview:PALabel(@"Support and Maintenance", 18.0, NSFontWeightSemibold)];
    [stack addArrangedSubview:PALabel(
        @"Troubleshoot the macOS wrapper without modifying downloaded game content unless explicitly selected.",
        12.0, NSFontWeightRegular)];

    NSArray<NSArray *> *actions = @[
        @[@"Open Diagnostic Logs", NSStringFromSelector(@selector(openLogs:))],
        @[@"Copy System Information", NSStringFromSelector(@selector(copySystemInformation:))],
        @[@"Run Compatibility Check", NSStringFromSelector(@selector(runCompatibilityCheck:))],
        @[@"Repair Compatibility Runtime on Next Launch", NSStringFromSelector(@selector(repairRuntime:))],
        @[@"Reset Official Launcher Data on Next Launch", NSStringFromSelector(@selector(resetLauncherData:))],
    ];
    for (NSArray *action in actions) {
        [stack addArrangedSubview:PAButton(action[0], self, NSSelectorFromString(action[1]))];
    }

    NSView *spacer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 12)];
    [stack addArrangedSubview:spacer];
    [stack addArrangedSubview:PALabel(@"Uninstall", 14.0, NSFontWeightSemibold)];
    NSButton *uninstall = PAButton(@"Uninstall Project Ascension…", self, @selector(uninstall:));
    uninstall.contentTintColor = NSColor.systemRedColor;
    [stack addArrangedSubview:uninstall];
    [stack addArrangedSubview:PALabel(
        @"You can preserve the downloaded game when removing the application and compatibility runtime.",
        11.0, NSFontWeightRegular)];
    return PAWrapView(stack);
}

- (void)loadControls
{
    self.overlayEnabled.state = PASettingBool(self.settings, @"performanceOverlayEnabled");
    NSString *preset = PAOverlayPreset(self.settings);
    NSDictionary *titles = @{@"compact": @"Compact", @"detailed": @"Detailed", @"custom": @"Custom"};
    [self.preset selectItemWithTitle:titles[preset] ?: @"Custom"];
    self.scale.doubleValue = [self.settings[@"overlayScale"] doubleValue] ?: 1.0;
    self.opacity.doubleValue = [self.settings[@"overlayOpacity"] doubleValue] ?: 1.0;
    self.closeLauncherWhilePlaying.state = PASettingBool(
        self.settings, @"closeLauncherWhilePlaying");
    self.keepLauncherVisible.state = PASettingBool(self.settings, @"keepLauncherVisible");
    self.showLauncherAfterGame.state = PASettingBool(self.settings, @"showLauncherAfterGame");
    self.confirmQuit.state = PASettingBool(self.settings, @"confirmQuitWhileGameRunning");
    [self applyPresetMetrics];
    [self updateControlState];
    [self updateLauncherControlState];
}

- (void)launcherBehaviourChanged:(id)sender
{
    (void)sender;
    [self updateLauncherControlState];
}

- (void)updateLauncherControlState
{
    BOOL closesLauncher = self.closeLauncherWhilePlaying.state == NSControlStateValueOn;
    self.keepLauncherVisible.enabled = !closesLauncher;
    self.showLauncherAfterGame.enabled = !closesLauncher &&
        self.keepLauncherVisible.state != NSControlStateValueOn;
}

- (void)applyPresetMetrics
{
    NSString *title = self.preset.titleOfSelectedItem;
    NSArray<NSString *> *selected;
    if ([title isEqualToString:@"Compact"]) {
        selected = @[@"fps", @"frametimes"];
    } else if ([title isEqualToString:@"Detailed"]) {
        selected = @[@"fps", @"frametimes", @"gpuload", @"memory", @"compiler"];
    } else {
        id metrics = self.settings[@"overlayMetrics"];
        selected = [metrics isKindOfClass:[NSArray class]] ? metrics : @[@"fps"];
    }
    NSSet *selectedSet = [NSSet setWithArray:selected];
    [self.metricButtons enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSButton *button, BOOL *stop) {
        (void)stop;
        button.state = [selectedSet containsObject:key] ? NSControlStateValueOn : NSControlStateValueOff;
    }];
}

- (void)updateControlState
{
    BOOL enabled = self.overlayEnabled.state == NSControlStateValueOn;
    BOOL custom = [self.preset.titleOfSelectedItem isEqualToString:@"Custom"];
    self.preset.enabled = enabled;
    for (NSButton *button in self.metricButtons.allValues) {
        button.enabled = enabled && custom;
    }
    self.scale.enabled = enabled;
    self.opacity.enabled = enabled;
    self.scaleValue.stringValue = [NSString stringWithFormat:@"%.0f%%", self.scale.doubleValue * 100.0];
    self.opacityValue.stringValue = [NSString stringWithFormat:@"%.0f%%", self.opacity.doubleValue * 100.0];
}

- (void)overlayChanged:(id)sender { (void)sender; [self updateControlState]; }
- (void)sliderChanged:(id)sender { (void)sender; [self updateControlState]; }
- (void)presetChanged:(id)sender
{
    (void)sender;
    [self applyPresetMetrics];
    [self updateControlState];
}
- (void)metricChanged:(id)sender { (void)sender; }

- (void)save:(id)sender
{
    (void)sender;
    BOOL enabled = self.overlayEnabled.state == NSControlStateValueOn;
    NSDictionary *presets = @{@"Compact": @"compact", @"Detailed": @"detailed", @"Custom": @"custom"};
    self.settings[@"performanceOverlayEnabled"] = @(enabled);
    self.settings[@"performanceOverlayPreset"] = enabled ? presets[self.preset.titleOfSelectedItem] : @"off";
    NSMutableArray<NSString *> *metrics = [NSMutableArray array];
    [self.metricButtons enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSButton *button, BOOL *stop) {
        (void)stop;
        if (button.state == NSControlStateValueOn) [metrics addObject:key];
    }];
    [metrics sortUsingSelector:@selector(compare:)];
    self.settings[@"overlayMetrics"] = metrics.count > 0 ? metrics : @[@"fps"];
    self.settings[@"overlayScale"] = @(self.scale.doubleValue);
    self.settings[@"overlayOpacity"] = @(self.opacity.doubleValue);
    self.settings[@"closeLauncherWhilePlaying"] = @(
        self.closeLauncherWhilePlaying.state == NSControlStateValueOn);
    self.settings[@"keepLauncherVisible"] = @(self.keepLauncherVisible.state == NSControlStateValueOn);
    self.settings[@"showLauncherAfterGame"] = @(self.showLauncherAfterGame.state == NSControlStateValueOn);
    self.settings[@"confirmQuitWhileGameRunning"] = @(self.confirmQuit.state == NSControlStateValueOn);

    NSError *error = nil;
    if (!PASaveSettings(self.settings, &error)) {
        [self showMessage:@"Settings Could Not Be Saved" detail:error.localizedDescription style:NSAlertStyleCritical];
        return;
    }
    [self showMessage:@"Settings Saved"
               detail:@"Your choices will be used the next time Project Ascension starts."
                style:NSAlertStyleInformational];
}

- (void)restoreDefaults:(id)sender
{
    (void)sender;
    self.settings = [PADefaultSettings() mutableCopy];
    [self loadControls];
    NSError *error = nil;
    if (!PASaveSettings(self.settings, &error)) {
        [self showMessage:@"Defaults Could Not Be Restored" detail:error.localizedDescription style:NSAlertStyleCritical];
    }
}

- (void)openLogs:(id)sender
{
    (void)sender;
    NSString *logs = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Project Ascension"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:logs]];
}

- (void)copySystemInformation:(id)sender
{
    (void)sender;
    size_t size = 0;
    sysctlbyname("hw.model", NULL, &size, NULL, 0);
    char *modelBuffer = calloc(1, size + 1);
    if (modelBuffer != NULL) sysctlbyname("hw.model", modelBuffer, &size, NULL, 0);
    NSString *model = modelBuffer != NULL ? [NSString stringWithUTF8String:modelBuffer] : @"Unknown";
    free(modelBuffer);

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[PAAppRoot() stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"Unknown";
    NSString *runtimeMarker = @"Missing";
    NSString *markerPath = @"/Users/Shared/PAWine/.ascension-runtime-version";
    NSString *marker = [NSString stringWithContentsOfFile:markerPath encoding:NSUTF8StringEncoding error:nil];
    if (marker.length > 0) runtimeMarker = [marker stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    NSString *text = [NSString stringWithFormat:
        @"Project Ascension for Mac %@\nmacOS %@\nModel: %@\nArchitecture: %@\nMemory: %.1f GB\nRuntime: %@\nOverlay: %@\n",
        version, NSProcessInfo.processInfo.operatingSystemVersionString, model,
        NSProcessInfo.processInfo.processorCount > 0 ? @"Apple Silicon" : @"Unknown",
        NSProcessInfo.processInfo.physicalMemory / 1073741824.0, runtimeMarker,
        PAOverlayPreset(PALoadSettings())];
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
    [self showMessage:@"System Information Copied" detail:@"The diagnostic summary is ready to paste." style:NSAlertStyleInformational];
}

- (void)runCompatibilityCheck:(id)sender
{
    (void)sender;
    NSString *support = PASupportPath();
    NSArray<NSArray<NSString *> *> *checks = @[
        @[@"Application bundle", PAAppRoot()],
        @[@"Compatibility runtime", @"/Users/Shared/PAWine/bin/wine-heroic"],
        @[@"Wine prefix", [support stringByAppendingPathComponent:@".prefix-ready"]],
        @[@"Official launcher", [support stringByAppendingPathComponent:@"prefix/drive_c/Program Files/Ascension Launcher/Ascension Launcher.exe"]],
        @[@"Game installation", [support stringByAppendingPathComponent:@"prefix/drive_c/Program Files/Ascension Launcher/resources/ascension-live/Ascension.exe"]],
        @[@"macOS game patch", [support stringByAppendingPathComponent:@"runtime-patch-live/.ready"]],
    ];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    BOOL allPassed = YES;
    for (NSArray<NSString *> *check in checks) {
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:check[1]];
        allPassed = allPassed && exists;
        [lines addObject:[NSString stringWithFormat:@"%@  %@", exists ? @"✓" : @"✗", check[0]]];
    }
    [self showMessage:allPassed ? @"Compatibility Check Passed" : @"Compatibility Check Found Problems"
               detail:[lines componentsJoinedByString:@"\n"]
                style:allPassed ? NSAlertStyleInformational : NSAlertStyleWarning];
}

- (void)repairRuntime:(id)sender
{
    (void)sender;
    if (![self confirm:@"Repair Compatibility Runtime?"
                detail:@"The bundled runtime will be reinstalled the next time Project Ascension starts. Downloaded game data will be kept."]) return;
    [self createMarker:@".repair-runtime"];
    [self showMessage:@"Repair Scheduled" detail:@"Quit and reopen Project Ascension to reinstall the runtime." style:NSAlertStyleInformational];
}

- (void)resetLauncherData:(id)sender
{
    (void)sender;
    if (![self confirm:@"Reset Official Launcher Data?"
                detail:@"The official launcher's preferences, cache, and sign-in session will be reset next launch. Downloaded game files will be kept."]) return;
    [self createMarker:@".reset-launcher-data"];
    [self showMessage:@"Reset Scheduled" detail:@"Quit and reopen Project Ascension to reset the official launcher." style:NSAlertStyleInformational];
}

- (void)createMarker:(NSString *)name
{
    NSString *path = [PASupportPath() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:PASupportPath()
                               withIntermediateDirectories:YES attributes:nil error:nil];
    [@"1\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)uninstall:(id)sender
{
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Uninstall Project Ascension?";
    alert.informativeText = @"Choose what should be removed. This action cannot be undone.";
    [alert addButtonWithTitle:@"Uninstall"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    NSPopUpButton *choices = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 430, 26) pullsDown:NO];
    [choices addItemsWithTitles:@[
        @"Application only (keep runtime and downloaded game)",
        @"Application and compatibility runtime (keep downloaded game)",
        @"Everything, including downloaded game data",
    ]];
    alert.accessoryView = choices;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSArray<NSString *> *modes = @[@"app", @"runtime", @"all"];
    NSString *script = [PAResourcesPath() stringByAppendingPathComponent:@"ascension-uninstall.sh"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:script]) {
        [self showMessage:@"Uninstaller Is Missing" detail:@"Reinstall Project Ascension and try again." style:NSAlertStyleCritical];
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = @[script, @"--mode", modes[choices.indexOfSelectedItem], @"--app", PAAppRoot()];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self showMessage:@"Uninstall Could Not Start" detail:error.localizedDescription style:NSAlertStyleCritical];
        return;
    }
    [NSApp terminate:nil];
}

- (BOOL)confirm:(NSString *)message detail:(NSString *)detail
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = detail;
    [alert addButtonWithTitle:@"Continue"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    return [alert runModal] == NSAlertFirstButtonReturn;
}

- (void)showMessage:(NSString *)message detail:(NSString *)detail style:(NSAlertStyle)style
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = detail ?: @"";
    alert.alertStyle = style;
    [alert runModal];
}

@end

static int PASetOverlayPreset(NSString *preset)
{
    NSMutableDictionary *settings = PALoadSettings();
    if ([preset isEqualToString:@"off"]) {
        settings[@"performanceOverlayEnabled"] = @NO;
        settings[@"performanceOverlayPreset"] = @"off";
    } else if ([preset isEqualToString:@"compact"] || [preset isEqualToString:@"detailed"]) {
        settings[@"performanceOverlayEnabled"] = @YES;
        settings[@"performanceOverlayPreset"] = preset;
    } else {
        return 2;
    }
    NSError *error = nil;
    if (!PASaveSettings(settings, &error)) {
        fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    return 0;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        (void)argv;
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        if (argc >= 2 && [arguments[1] isEqualToString:@"--print-hud"]) {
            printf("%s\n", PAHUDValue(PALoadSettings()).UTF8String);
            return 0;
        }
        if (argc >= 3 && [arguments[1] isEqualToString:@"--print-bool"]) {
            printf("%d\n", PASettingBool(PALoadSettings(), arguments[2]) ? 1 : 0);
            return 0;
        }
        if (argc >= 3 && [arguments[1] isEqualToString:@"--set-overlay"]) {
            return PASetOverlayPreset(arguments[2]);
        }

        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyRegular;
        PASettingsController *controller = [[PASettingsController alloc] init];
        if (argc >= 2 && [arguments[1] isEqualToString:@"--uninstall"]) {
            controller.startupAction = @"uninstall";
        }
        application.delegate = controller;
        [application run];
    }
    return 0;
}
