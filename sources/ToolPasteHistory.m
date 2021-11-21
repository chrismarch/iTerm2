//
//  ToolPasteHistory.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//

#import "ToolPasteHistory.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermCompetentTableRowView.h"
#import "iTermController.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermToolWrapper.h"
#import "NSDateFormatterExtras.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSTableColumn+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;

@implementation ToolPasteHistory {
    NSScrollView *scrollView_;
    NSTableView *_tableView;
    NSButton *clear_;
    NSTextField *_secureKeyboardEntryWarning;
    PasteboardHistory *pasteHistory_;
    NSTimer *minuteRefreshTimer_;
    BOOL shutdown_;
    NSMutableParagraphStyle *_paragraphStyle;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        _paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
        _paragraphStyle.allowsDefaultTighteningForTruncation = NO;

        clear_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        if (@available(macOS 10.16, *)) {
            clear_.bezelStyle = NSBezelStyleRegularSquare;
            clear_.bordered = NO;
            clear_.image = [NSImage it_imageForSymbolName:@"trash" accessibilityDescription:@"Delete All"];
            clear_.imagePosition = NSImageOnly;
            clear_.frame = NSMakeRect(0, 0, 22, 22);
        } else {
            [clear_ setButtonType:NSButtonTypeMomentaryPushIn];
            [clear_ setTitle:@"Clear All"];
            [clear_ setBezelStyle:NSBezelStyleSmallSquare];
            [clear_ sizeToFit];
        }
        [clear_ setTarget:self];
        [clear_ setAction:@selector(clear:)];
        [clear_ setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:clear_];

        _secureKeyboardEntryWarning = [NSTextField newLabelStyledTextField];
        _secureKeyboardEntryWarning.stringValue = @"⚠️ Secure keyboard entry disables paste history.";
        _secureKeyboardEntryWarning.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        _secureKeyboardEntryWarning.cell.truncatesLastVisibleLine = YES;
        _secureKeyboardEntryWarning.hidden = ![[iTermSecureKeyboardEntryController sharedInstance] isEnabled];
        [self addSubview:_secureKeyboardEntryWarning];
        [_secureKeyboardEntryWarning sizeToFit];
        _secureKeyboardEntryWarning.frame = NSMakeRect(0, 0, frame.size.width, _secureKeyboardEntryWarning.frame.size.height);

        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        if (@available(macOS 10.16, *)) {
            [scrollView_ setBorderType:NSLineBorder];
            scrollView_.scrollerStyle = NSScrollerStyleOverlay;
        } else {
            [scrollView_ setBorderType:NSBezelBorder];
        }
        NSSize contentSize = [scrollView_ contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        scrollView_.drawsBackground = NO;

#if 1
        _tableView = [NSTableView toolbeltTableViewInScrollview:scrollView_ owner:self];
#else
        _tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
#ifdef MAC_OS_X_VERSION_10_16
        if (@available(macOS 10.16, *)) {
            _tableView.style = NSTableViewStyleFullWidth;
        }
#endif
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"contents"];
        [col setEditable:NO];
        [_tableView addTableColumn:col];
        [_tableView setHeaderView:nil];
        [_tableView setDataSource:self];
        [_tableView setDelegate:self];
        _tableView.intercellSpacing = NSMakeSize(_tableView.intercellSpacing.width, 0);

        [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
        [_tableView setAutoresizingMask:NSViewWidthSizable];
        if (@available(macOS 10.14, *)) {
            _tableView.backgroundColor = [NSColor clearColor];
        }

        [scrollView_ setDocumentView:_tableView];
#endif
        [self addSubview:scrollView_];

        [_tableView sizeToFit];
        [_tableView setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];
        [self relayout];
        pasteHistory_ = [PasteboardHistory sharedInstance];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardHistoryDidChange:)
                                                     name:kPasteboardHistoryDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(secureKeyboardEntryDidChange:)
                                                     name:iTermDidToggleSecureInputNotification
                                                   object:nil];
        minuteRefreshTimer_ = [NSTimer scheduledTimerWithTimeInterval:61
                                                               target:self
                                                             selector:@selector(pasteboardHistoryDidChange:)
                                                             userInfo:nil
                                                              repeats:YES];
        [_tableView performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
        [_tableView reloadData];
    }
    return self;
}

- (void)dealloc {
    [minuteRefreshTimer_ invalidate];
}

- (void)shutdown {
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [minuteRefreshTimer_ invalidate];
    minuteRefreshTimer_ = nil;
}

- (NSSize)contentSize {
    NSSize size = [scrollView_ contentSize];
    size.height = _tableView.intrinsicContentSize.height;
    return size;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self relayout];
}

- (void)relayout {
    NSRect frame = self.frame;
    if (@available(macOS 10.16, *)){
        clear_.frame = NSMakeRect(frame.size.width - clear_.frame.size.width,
                                  frame.size.height - clear_.frame.size.height,
                                  clear_.frame.size.width,
                                  clear_.frame.size.height);
    } else {
        [clear_ sizeToFit];
        [clear_ setFrame:NSMakeRect(frame.size.width - clear_.frame.size.width, frame.size.height - kButtonHeight, clear_.frame.size.width, kButtonHeight)];
    }

    _secureKeyboardEntryWarning.hidden = [iTermAdvancedSettingsModel saveToPasteHistoryWhenSecureInputEnabled] || ![[iTermSecureKeyboardEntryController sharedInstance] isEnabled];
    _secureKeyboardEntryWarning.frame = NSMakeRect(0, 0, frame.size.width, _secureKeyboardEntryWarning.frame.size.height);

    const CGFloat offset = _secureKeyboardEntryWarning.isHidden ? 0 : _secureKeyboardEntryWarning.frame.size.height + 4;
    [scrollView_ setFrame:NSMakeRect(0, offset, frame.size.width, frame.size.height - kButtonHeight - kMargin - offset)];

    NSSize contentSize = [self contentSize];
    [_tableView setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    if (@available(macOS 10.16, *)) {
        return [[iTermBigSurTableRowView alloc] initWithFrame:NSZeroRect];
    }
    return [[iTermCompetentTableRowView alloc] initWithFrame:NSZeroRect];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return pasteHistory_.entries.count;
}

//- (NSTableCellView *)makecell {
//    static NSString *const identifier = @"MyCellIdentifier";
//    NSTableCellView *result = [_tableView makeViewWithIdentifier:identifier owner:self];
//    if (result != nil) {
//        return result;
//    }
//    return [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 18)];
//}
//
//- (void)initailizeTableCellViewIfNeeded:(NSTableCellView *)cell {
//    if (!cell.textField) {
//        NSTextField *text = [[NSTextField alloc] init];
//        text.font = [NSFont it_toolbeltFont];
//        text.bezeled = NO;
//        text.editable = NO;
//        text.selectable = NO;
//        text.drawsBackground = NO;
//        text.identifier = @"MyTextFieldIdentifier";
//        text.translatesAutoresizingMaskIntoConstraints = NO;
//        text.lineBreakMode = NSLineBreakByTruncatingTail;
//
//        cell.textField = text;
//        [cell addSubview:text];
//        const CGFloat verticalPadding = 2.0;
//        [cell addConstraint:[NSLayoutConstraint constraintWithItem:text
//                                                         attribute:NSLayoutAttributeTop
//                                                         relatedBy:NSLayoutRelationEqual
//                                                            toItem:cell
//                                                         attribute:NSLayoutAttributeTop
//                                                        multiplier:1
//                                                          constant:verticalPadding]];
//        [cell addConstraint:[NSLayoutConstraint constraintWithItem:text
//                                                         attribute:NSLayoutAttributeBottom
//                                                         relatedBy:NSLayoutRelationEqual
//                                                            toItem:cell
//                                                         attribute:NSLayoutAttributeBottom
//                                                        multiplier:1
//                                                          constant:-verticalPadding]];
//        [cell addConstraint:[NSLayoutConstraint constraintWithItem:text
//                                                         attribute:NSLayoutAttributeLeft
//                                                         relatedBy:NSLayoutRelationEqual
//                                                            toItem:cell
//                                                         attribute:NSLayoutAttributeLeft
//                                                        multiplier:1
//                                                          constant:13]];
//        [cell addConstraint:[NSLayoutConstraint constraintWithItem:text
//                                                         attribute:NSLayoutAttributeRight
//                                                         relatedBy:NSLayoutRelationEqual
//                                                            toItem:cell
//                                                         attribute:NSLayoutAttributeRight
//                                                        multiplier:1
//                                                          constant:-    13]];
//    }
//}
//
- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
#if 0
    static NSString *const identifier = @"ToolPasteHistoryEntry";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
    }

    NSAttributedString *value = [self attributedStringForTableColumn:tableColumn row:row];
    result.attributedStringValue = value;
#endif
#if 0
    NSTableCellView *result = [self makecell];
    [self initailizeTableCellViewIfNeeded:result];
    NSAttributedString *value = [self attributedStringForTableColumn:tableColumn row:row];
//    NSString *stringValue = value.string;
//    NSMutableParagraphStyle *paragraphStyle;
//    paragraphStyle = [[NSMutableParagraphStyle alloc] init];
//    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
//    paragraphStyle.allowsDefaultTighteningForTruncation = NO;
//    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont it_toolbeltFont],
//                                  NSParagraphStyleAttributeName: paragraphStyle };
//    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:stringValue attributes:attributes];
    result.textField.attributedStringValue = value;
#endif
    NSTableCellView *result = [tableView newTableCellViewWithTextFieldUsingIdentifier:@"iTermToolPasteHistory"
                                                                     attributedString:[self attributedStringForTableColumn:tableColumn row:row]];
    return result;
}

- (id <NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    PasteboardEntry* entry = pasteHistory_.entries[row];
    [pbItem setString:entry.mainValue forType:(NSString *)kUTTypeUTF8PlainText];
    return pbItem;
}

- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    return [[NSAttributedString alloc] initWithString:[self stringForTableColumn:aTableColumn row:rowIndex]
                                           attributes:@{NSFontAttributeName: [NSFont it_toolbeltFont],
                                                        NSParagraphStyleAttributeName: _paragraphStyle }];
}

- (NSString *)stringForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    PasteboardEntry* entry = pasteHistory_.entries[rowIndex];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter compactDateDifferenceStringFromDate:entry.timestamp];
    } else {
        // Contents
        NSString* value = [[entry mainValue] stringByReplacingOccurrencesOfString:@"\n"
                                                                       withString:@" "];
        // Don't return an insanely long value to avoid performance issues.
        const NSUInteger kMaxLength = 256;
        if (value.length > kMaxLength) {
            return [value substringToIndex:kMaxLength];
        } else {
            return value;
        }
    }
}

- (void)secureKeyboardEntryDidChange:(NSNotification *)notification {
    [self relayout];
}

- (void)pasteboardHistoryDidChange:(id)sender {
    [self update];
}

- (void)update {
    [_tableView reloadData];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];

    NSResponder *firstResponder = [[_tableView window] firstResponder];
    if (firstResponder != _tableView) {
        [_tableView scrollToEndOfDocument:nil];
    }
}

- (void)fixCursor {
    if (shutdown_) {
        return;
    }
    iTermToolWrapper *wrapper = self.toolWrapper;
    [wrapper.delegate.delegate toolbeltUpdateMouseCursor];
}

- (void)doubleClickOnTableView:(id)sender {
    NSInteger selectedIndex = [_tableView selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    PasteboardEntry* entry = pasteHistory_.entries[selectedIndex];
    NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
    [thePasteboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil];
    [thePasteboard setString:[entry mainValue] forType:NSPasteboardTypeString];
    PTYTextView *textView = [[iTermController sharedInstance] frontTextView];
    [textView paste:nil];
    [textView.window makeFirstResponder:textView];
}

- (void)clear:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Erase Paste History";
    alert.informativeText = @"Paste history will be erased. Continue?";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [pasteHistory_ eraseHistory];
        [pasteHistory_ clear];
        [_tableView reloadData];
    }
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (CGFloat)minimumHeight {
    return 60;
}

@end
