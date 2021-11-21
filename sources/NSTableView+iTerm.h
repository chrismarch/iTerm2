//
//  NSTableView+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/19.
//

#import <AppKit/AppKit.h>


#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTableView (iTerm)

- (void)it_performUpdateBlock:(void (^NS_NOESCAPE)(void))block;

+ (instancetype)toolbeltTableViewInScrollview:(NSScrollView *)scrollView
                                        owner:(NSView<NSTableViewDelegate, NSTableViewDataSource> *)owner;
- (NSTableCellView *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier
                                                             font:(NSFont *)font
                                                            string:(NSString *)string;
- (NSTableCellView *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier
                                                 attributedString:(NSAttributedString *)attributedString;

@end

NS_ASSUME_NONNULL_END
