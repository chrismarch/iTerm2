//
//  NSView+iTerm.m
//  iTerm
//
//  Created by George Nachman on 3/15/14.
//
//

#import "NSView+iTerm.h"
#import "DebugLogging.h"
#import "iTermApplication.h"
#import "NSWindow+iTerm.h"

static NSInteger gTakingSnapshot;

@implementation NSView (iTerm)

+ (BOOL)iterm_takingSnapshot {
    return gTakingSnapshot > 0;
}

+ (NSView *)viewAtScreenCoordinate:(NSPoint)point {
    const NSRect mouseRect = {
        .origin = point,
        .size = NSZeroSize
    };
    NSArray<NSWindow *> *frontToBackWindows = [[iTermApplication sharedApplication] orderedWindowsPlusVisibleHotkeyPanels];
    for (NSWindow *window in frontToBackWindows) {
        if (!window.isOnActiveSpace) {
            continue;
        }
        if (!window.isVisible) {
            continue;
        }
        NSPoint pointInWindow = [window convertRectFromScreen:mouseRect].origin;
        if ([window isTerminalWindow]) {
            DLog(@"Consider window %@", window.title);
            NSView *view = [window.contentView hitTest:pointInWindow];
            if (view) {
                return view;
            } else {
                DLog(@"%@ failed hit test", window.title);
            }
        }
    }
    return nil;
}

- (NSRect)frameInScreenCoordinates {
    NSRect viewFrameInWindowCoords = [self convertRect:self.frame toView:nil];
    // TODO chrismarch check for convertRectToScreen if min os version of iTerm is less than convertRectToScreen min os version
    NSRect viewFrameInScreenCoords = [self.window convertRectToScreen:viewFrameInWindowCoords];
    return viewFrameInScreenCoords;
}

- (CGRect)contentsRectToMatchDesktopBackground:(CGSize) nativeTextureSize {
    CGRect globalTextureFrame;
    NSRect screenRect = self.window.screen.frame;
    const CGFloat imageAspectRatio = nativeTextureSize.width / nativeTextureSize.height;

    const CGFloat screenAspectRatio = screenRect.size.width / screenRect.size.height;
    // TODO chrismarch assuming aspect fill desktop background
    if (imageAspectRatio > screenAspectRatio) {
        // Image is wide relative to screen.
        // Crop left and right.
        const CGFloat width = nativeTextureSize.height * screenAspectRatio;
        const CGFloat crop = (nativeTextureSize.width - width) / 2.0;
        globalTextureFrame = CGRectMake(crop, 0, width, nativeTextureSize.height);
    } else {
        // Image is tall relative to screen.
        // Crop top and bottom.
        const CGFloat height = nativeTextureSize.width / screenAspectRatio;
        const CGFloat crop = (nativeTextureSize.height - height) / 2.0;
        globalTextureFrame = CGRectMake(0, crop, nativeTextureSize.width, height);
    }
    
    NSRect frameRelativeToScreen = [self frameInScreenCoordinates];
    CGRect frameRSN = CGRectMake(frameRelativeToScreen.origin.x / screenRect.size.width,
                                 frameRelativeToScreen.origin.y / screenRect.size.height,
                                 frameRelativeToScreen.size.width / screenRect.size.width,
                                 frameRelativeToScreen.size.height / screenRect.size.height);

    CGRect textureFrame = CGRectMake(frameRSN.origin.x * globalTextureFrame.size.width + globalTextureFrame.origin.x,
                              frameRSN.origin.y * globalTextureFrame.size.height + globalTextureFrame.origin.y,
                              frameRSN.size.width * globalTextureFrame.size.width,
                              frameRSN.size.height * globalTextureFrame.size.height);
    
    textureFrame.origin.x /= nativeTextureSize.width;
    textureFrame.size.width /= nativeTextureSize.width;
    textureFrame.origin.y /= nativeTextureSize.height;
    textureFrame.size.height /= nativeTextureSize.height;

    return textureFrame;
}

- (NSImage *)snapshot {
    return [self snapshotOfRect:self.bounds];
}

- (NSImage *)snapshotOfRect:(NSRect)rect {
    gTakingSnapshot += 1;

    NSBitmapImageRep *rep = [self bitmapImageRepForCachingDisplayInRect:rect];
    [self cacheDisplayInRect:self.bounds toBitmapImageRep:rep];
    NSImage *image = [[NSImage alloc] initWithSize:rect.size];
    [image addRepresentation:rep];

    gTakingSnapshot -= 1;
    return image;
}

- (void)insertSubview:(NSView *)subview atIndex:(NSInteger)index {
    NSArray *subviews = [self subviews];
    if (subviews.count == 0) {
        [self addSubview:subview];
        return;
    }
    if (index == 0) {
        [self addSubview:subview positioned:NSWindowBelow relativeTo:subviews[0]];
    } else {
        [self addSubview:subview positioned:NSWindowAbove relativeTo:subviews[index - 1]];
    }
}

- (void)swapSubview:(NSView *)subview1 withSubview:(NSView *)subview2 {
    NSArray *subviews = [self subviews];
    NSUInteger index1 = [subviews indexOfObject:subview1];
    NSUInteger index2 = [subviews indexOfObject:subview2];
    assert(index1 != index2);
    assert(index1 != NSNotFound);
    assert(index2 != NSNotFound);

    NSRect frame1 = subview1.frame;
    NSRect frame2 = subview2.frame;

    NSView *filler1 = [[NSView alloc] initWithFrame:subview1.frame];
    NSView *filler2 = [[NSView alloc] initWithFrame:subview2.frame];

    [self replaceSubview:subview1 with:filler1];
    [self replaceSubview:subview2 with:filler2];

    subview1.frame = frame2;
    subview2.frame = frame1;

    [self replaceSubview:filler1 with:subview2];
    [self replaceSubview:filler2 with:subview1];
}

+ (iTermDelayedPerform *)animateWithDuration:(NSTimeInterval)duration
                                       delay:(NSTimeInterval)delay
                                  animations:(void (^)(void))animations
                                  completion:(void (^)(BOOL finished))completion {
    iTermDelayedPerform *delayedPerform = [[iTermDelayedPerform alloc] init];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (!delayedPerform.canceled) {
                           DLog(@"Run dp %@", delayedPerform);
                           [self animateWithDuration:duration
                                          animations:animations
                                          completion:^(BOOL finished) {
                                              delayedPerform.completed = YES;
                                              completion(finished);
                                          }];
                       } else {
                           completion(NO);
                       }
                   });
    return delayedPerform;
}

+ (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (NS_NOESCAPE ^)(void))animations
                 completion:(void (^)(BOOL finished))completion {
   NSAnimationContext *context = [NSAnimationContext currentContext];
   NSTimeInterval savedDuration = [context duration];
   if (duration > 0) {
       [context setDuration:duration];
   }
   animations();
   [context setDuration:savedDuration];

   if (completion) {
       dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                      dispatch_get_main_queue(), ^{
                          completion(YES);
                      });
   }
}

- (void)enumerateHierarchy:(void (NS_NOESCAPE ^)(NSView *))block {
    block(self);
    for (NSView *view in self.subviews) {
        [view enumerateHierarchy:block];
    }
}

- (CGFloat)retinaRound:(CGFloat)value {
    NSWindow *window = self.window;
    if (!window) {
        return round(value);
    }
    CGFloat scale = window.backingScaleFactor;
    if (!scale) {
        scale = [[NSScreen mainScreen] backingScaleFactor];
    }
    if (!scale) {
        scale = 1;
    }
    return round(scale * value) / scale;
}

- (CGFloat)retinaRoundUp:(CGFloat)value {
    NSWindow *window = self.window;
    if (!window) {
        return ceil(value);
    }
    CGFloat scale = window.backingScaleFactor;
    if (!scale) {
        scale = [[NSScreen mainScreen] backingScaleFactor];
    }
    if (!scale) {
        scale = 1;
    }
    return ceil(scale * value) / scale;
}

- (CGRect)retinaRoundRect:(CGRect)rect {
    NSRect result = NSMakeRect([self retinaRound:NSMinX(rect)],
                               [self retinaRound:NSMinY(rect)],
                               [self retinaRoundUp:NSWidth(rect)],
                               [self retinaRoundUp:NSHeight(rect)]);
    return result;
}

- (BOOL)containsDescendant:(NSView *)possibleDescendant {
    for (NSView *subview in self.subviews) {
        if (subview == possibleDescendant || [subview containsDescendant:possibleDescendant]) {
            return YES;
        }
    }
    return NO;
}

- (NSColor *)it_backgroundColorOfEnclosingTerminalIfBackgroundColorViewHidden {
    return [self.superview it_backgroundColorOfEnclosingTerminalIfBackgroundColorViewHidden];
}

@end
