#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

@interface PAProgressController : NSObject <NSApplicationDelegate>
@property(nonatomic, copy) NSString *pipePath;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) NSTextField *status;
@end

@implementation PAProgressController

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;

    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 420, 150)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"Project Ascension";
    self.window.releasedWhenClosed = NO;

    NSTextField *heading = [NSTextField labelWithString:@"Preparing Project Ascension"];
    heading.font = [NSFont systemFontOfSize:17.0 weight:NSFontWeightSemibold];
    heading.translatesAutoresizingMaskIntoConstraints = NO;

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.progress.indeterminate = NO;
    self.progress.minValue = 0.0;
    self.progress.maxValue = 100.0;
    self.progress.doubleValue = 0.0;
    self.progress.controlSize = NSControlSizeRegular;
    self.progress.translatesAutoresizingMaskIntoConstraints = NO;

    self.status = [NSTextField labelWithString:@"Starting setup…"];
    self.status.font = [NSFont systemFontOfSize:12.0];
    self.status.textColor = NSColor.secondaryLabelColor;
    self.status.lineBreakMode = NSLineBreakByTruncatingTail;
    self.status.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = self.window.contentView;
    [content addSubview:heading];
    [content addSubview:self.progress];
    [content addSubview:self.status];
    [NSLayoutConstraint activateConstraints:@[
        [heading.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:28.0],
        [heading.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-28.0],
        [heading.topAnchor constraintEqualToAnchor:content.topAnchor constant:26.0],
        [self.progress.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
        [self.progress.trailingAnchor constraintEqualToAnchor:heading.trailingAnchor],
        [self.progress.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:20.0],
        [self.status.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
        [self.status.trailingAnchor constraintEqualToAnchor:heading.trailingAnchor],
        [self.status.topAnchor constraintEqualToAnchor:self.progress.bottomAnchor constant:12.0],
    ]];

    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self readUpdates];
}

- (void)readUpdates
{
    NSString *path = self.pipePath;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        FILE *stream = fopen(path.fileSystemRepresentation, "r");
        if (stream == NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
            return;
        }

        char *line = NULL;
        size_t capacity = 0;
        while (getline(&line, &capacity, stream) != -1) {
            NSString *update = [[NSString alloc] initWithUTF8String:line];
            update = [update stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
            NSRange separator = [update rangeOfString:@"\t"];
            if (separator.location == NSNotFound) {
                continue;
            }

            double value = [[update substringToIndex:separator.location] doubleValue];
            NSString *message = [update substringFromIndex:NSMaxRange(separator)];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.progress.doubleValue = value;
                self.status.stringValue = message;
                if (value >= 100.0) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                        (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [NSApp terminate:nil];
                    });
                }
            });
        }
        free(line);
        fclose(stream);

        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
    });
}

@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2) {
            return 2;
        }

        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyAccessory;
        PAProgressController *controller = [[PAProgressController alloc] init];
        controller.pipePath = [NSString stringWithUTF8String:argv[1]];
        application.delegate = controller;
        [application run];
    }
    return 0;
}
