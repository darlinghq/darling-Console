/*
This file is part of Darling.

Copyright (C) 2026 Lubos Dolezel

Darling is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Darling is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import "MainWindowController.h"
#import "LogEntry.h"

typedef NS_ENUM(NSInteger, SideKind) { SideHeader, SideAll, SideOSLog, SideLevel, SideFacility };

@interface SideItem : NSObject
@property SideKind kind;
@property (copy) NSString *title;
@property NSInteger level;          // SideLevel: show entries at this level or more severe
+ (instancetype)kind:(SideKind)k title:(NSString *)t level:(NSInteger)l;
@end
@implementation SideItem
+ (instancetype)kind:(SideKind)k title:(NSString *)t level:(NSInteger)l {
    SideItem *i = [SideItem new]; i.kind = k; i.title = t; i.level = l; return i;
}
- (BOOL)isEqualToItem:(SideItem *)o { return o && _kind == o.kind && [_title isEqualToString:o.title]; }
@end

@implementation MainWindowController {
    NSMutableArray<LogEntry *> *_all;
    NSArray<LogEntry *> *_shown;
    uint64_t _lastID;
    NSArray<SideItem *> *_sidebarItems;
    NSTimer *_timer;
    BOOL _loading;

    NSTableView *_sidebar, *_table;
    NSTextView *_detail;
    NSSearchField *_search;
    NSPopUpButton *_levelPopup;
    NSButton *_liveCheck;
    NSTextField *_status;
    NSDateFormatter *_shortFmt, *_fullFmt;
}

- (instancetype)init {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 700)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    w.title = @"ASL Console";
    [w center];
    self = [super initWithWindow:w];
    if (!self) return nil;

    _all = [NSMutableArray array];
    _shown = @[];
    _shortFmt = [NSDateFormatter new]; _shortFmt.dateFormat = @"MMM d HH:mm:ss";
    _fullFmt = [NSDateFormatter new]; _fullFmt.dateStyle = NSDateFormatterMediumStyle; _fullFmt.timeStyle = NSDateFormatterMediumStyle;

    [self buildUIInWindow:w];
    [self rebuildSidebar];
    [_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    [self reloadInitial:YES];

    __weak MainWindowController *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) {
        MainWindowController *s = weakSelf;
        if (s && s->_liveCheck.state == NSControlStateValueOn) [s reloadInitial:NO];
    }];
    return self;
}

#pragma mark - UI

static NSTableColumn *Column(NSString *ident, NSString *title, CGFloat width) {
    NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:ident];
    c.title = title; c.width = width; c.minWidth = 40;
    c.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:ident ascending:YES];
    return c;
}

- (void)buildUIInWindow:(NSWindow *)window {
    // Sidebar
    _sidebar = [NSTableView new];
    [_sidebar addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"side"]];
    _sidebar.headerView = nil;
    if (@available(macOS 11.0, *)) _sidebar.style = NSTableViewStyleSourceList;
    else _sidebar.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;
    _sidebar.dataSource = self; _sidebar.delegate = self;
    NSScrollView *sideScroll = [NSScrollView new];
    sideScroll.documentView = _sidebar; sideScroll.hasVerticalScroller = YES;
    [sideScroll.widthAnchor constraintGreaterThanOrEqualToConstant:160].active = YES;

    // Log table
    _table = [NSTableView new];
    for (NSArray *c in @[@[@"time", @"Time", @130], @[@"sender", @"Sender", @130], @[@"pid", @"PID", @55],
                         @[@"level", @"Level", @75], @[@"subsystem", @"Subsystem", @150],
                         @[@"category", @"Category", @100], @[@"message", @"Message", @500]]) {
        [_table addTableColumn:Column(c[0], c[1], [c[2] doubleValue])];
    }
    _table.usesAlternatingRowBackgroundColors = YES;
    _table.allowsMultipleSelection = YES;
    _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _table.dataSource = self; _table.delegate = self;
    NSScrollView *tableScroll = [NSScrollView new];
    tableScroll.documentView = _table;
    tableScroll.hasVerticalScroller = YES; tableScroll.hasHorizontalScroller = YES;

    // Detail pane
    _detail = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 100)];
    _detail.editable = NO;
    _detail.font = [NSFont userFixedPitchFontOfSize:12];
    _detail.textContainerInset = NSMakeSize(6, 6);
    _detail.verticallyResizable = YES;
    _detail.autoresizingMask = NSViewWidthSizable;
    NSScrollView *detailScroll = [NSScrollView new];
    detailScroll.documentView = _detail; detailScroll.hasVerticalScroller = YES;
    [detailScroll.heightAnchor constraintGreaterThanOrEqualToConstant:70].active = YES;

    NSSplitView *vsplit = [NSSplitView new];
    vsplit.vertical = NO; vsplit.dividerStyle = NSSplitViewDividerStyleThin;
    [vsplit addArrangedSubview:tableScroll];
    [vsplit addArrangedSubview:detailScroll];
    [vsplit setHoldingPriority:260 forSubviewAtIndex:1];

    // Filter bar
    _search = [NSSearchField new];
    _search.placeholderString = @"Search messages, senders…";
    _search.delegate = self;
    [_search.widthAnchor constraintGreaterThanOrEqualToConstant:220].active = YES;
    _levelPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_levelPopup addItemWithTitle:@"All Levels"];
    for (NSString *n in [LogEntry levelNames]) [_levelPopup addItemWithTitle:[n stringByAppendingString:@" and above"]];
    _levelPopup.target = self; _levelPopup.action = @selector(filterChanged:);
    _liveCheck = [NSButton checkboxWithTitle:@"Live" target:nil action:nil];
    _liveCheck.state = NSControlStateValueOn;
    _status = [NSTextField labelWithString:@""];
    _status.textColor = [NSColor secondaryLabelColor];
    _status.font = [NSFont systemFontOfSize:11];
    NSView *spacer = [NSView new];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *bar = [NSStackView stackViewWithViews:@[_levelPopup, _liveCheck, spacer, _status, _search]];
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal; bar.spacing = 10;
    bar.edgeInsets = NSEdgeInsetsMake(6, 8, 6, 8);

    NSView *right = [NSView new];
    for (NSView *v in @[bar, vsplit]) { v.translatesAutoresizingMaskIntoConstraints = NO; [right addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:right.topAnchor],
        [bar.heightAnchor constraintEqualToConstant:38],
        [bar.leadingAnchor constraintEqualToAnchor:right.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
        [vsplit.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [vsplit.leadingAnchor constraintEqualToAnchor:right.leadingAnchor],
        [vsplit.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
        [vsplit.bottomAnchor constraintEqualToAnchor:right.bottomAnchor],
        [right.widthAnchor constraintGreaterThanOrEqualToConstant:500]]];

    NSSplitView *hsplit = [NSSplitView new];
    hsplit.vertical = YES; hsplit.dividerStyle = NSSplitViewDividerStyleThin;
    [hsplit addArrangedSubview:sideScroll];
    [hsplit addArrangedSubview:right];
    [hsplit setHoldingPriority:260 forSubviewAtIndex:0];
    window.contentView = hsplit;
    [hsplit layoutSubtreeIfNeeded];
    [hsplit setPosition:210 ofDividerAtIndex:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        [vsplit layoutSubtreeIfNeeded];
        [vsplit setPosition:vsplit.bounds.size.height * 0.72 ofDividerAtIndex:0];
    });
}

#pragma mark - Data

- (void)reloadInitial:(BOOL)initial {
    if (_loading) return;
    _loading = YES;
    uint64_t after = initial ? 0 : _lastID;
    if (initial) _status.stringValue = @"Loading…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<LogEntry *> *fresh = [ASLReader fetchAfterID:after];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_loading = NO;
            if (fresh.count) {
                BOOL stick = initial || [self isAtBottom];
                [self->_all addObjectsFromArray:fresh];
                for (LogEntry *e in fresh) if (e.msgID > self->_lastID) self->_lastID = e.msgID;
                [self rebuildSidebar];
                [self applyFilterScrollToEnd:stick];
            } else if (initial) {
                [self applyFilterScrollToEnd:YES];
            }
        });
    });
}

- (void)rebuildSidebar {
    SideItem *selected = _sidebar.selectedRow >= 0 ? _sidebarItems[_sidebar.selectedRow] : nil;
    NSMutableSet *fac = [NSMutableSet set];
    for (LogEntry *e in _all) [fac addObject:e.facility];
    NSMutableArray *items = [NSMutableArray arrayWithObjects:
        [SideItem kind:SideHeader title:@"LOG QUERIES" level:0],
        [SideItem kind:SideAll title:@"All Messages" level:0],
        [SideItem kind:SideOSLog title:@"os_log Messages" level:0],
        [SideItem kind:SideLevel title:@"Errors" level:3],
        [SideItem kind:SideLevel title:@"Warnings & Errors" level:4],
        [SideItem kind:SideHeader title:@"FACILITIES" level:0], nil];
    for (NSString *f in [fac.allObjects sortedArrayUsingSelector:@selector(compare:)])
        [items addObject:[SideItem kind:SideFacility title:f level:0]];
    _sidebarItems = items;
    [_sidebar reloadData];
    NSUInteger idx = 1;
    for (NSUInteger i = 0; i < items.count; i++) if ([items[i] isEqualToItem:selected]) idx = i;
    [_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
}

- (void)applyFilterScrollToEnd:(BOOL)scrollToEnd {
    NSInteger minLevel = _levelPopup.indexOfSelectedItem - 1;      // -1 = all levels
    SideItem *side = _sidebar.selectedRow >= 0 ? _sidebarItems[_sidebar.selectedRow] : nil;
    if (side.kind == SideLevel) minLevel = minLevel < 0 ? side.level : MIN(minLevel, side.level);
    NSString *q = [_search.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(LogEntry *e, NSDictionary *b) {
        if (side.kind == SideFacility && ![e.facility isEqualToString:side.title]) return NO;
        if (side.kind == SideOSLog && !e.isOSLog) return NO;
        if (minLevel >= 0 && e.level > minLevel) return NO;
        if (q.length) {
            BOOL hit = [e.message localizedCaseInsensitiveContainsString:q]
                    || [e.sender localizedCaseInsensitiveContainsString:q]
                    || [e.subsystem localizedCaseInsensitiveContainsString:q]
                    || [e.category localizedCaseInsensitiveContainsString:q]
                    || [e.facility localizedCaseInsensitiveContainsString:q]
                    || [e.pid isEqualToString:q];
            if (!hit) return NO;
        }
        return YES;
    }];
    _shown = [_all filteredArrayUsingPredicate:p];
    [self applySort];
    [_table reloadData];
    _status.stringValue = [NSString stringWithFormat:@"%lu of %lu messages", (unsigned long)_shown.count, (unsigned long)_all.count];
    NSSortDescriptor *sd = _table.sortDescriptors.firstObject;
    BOOL chrono = !sd || ([sd.key isEqualToString:@"time"] && sd.ascending);
    if (scrollToEnd && _shown.count && chrono) [_table scrollRowToVisible:_shown.count - 1];
    [self updateDetail];
}

- (void)applySort {
    NSSortDescriptor *sd = _table.sortDescriptors.firstObject;
    if (!sd) return;
    NSString *key = sd.key;
    BOOL asc = sd.ascending;
    _shown = [_shown sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(LogEntry *a, LogEntry *b) {
        NSComparisonResult r;
        if ([key isEqualToString:@"time"]) r = a.msgID < b.msgID ? NSOrderedAscending : (a.msgID > b.msgID ? NSOrderedDescending : NSOrderedSame);
        else if ([key isEqualToString:@"sender"]) r = [a.sender caseInsensitiveCompare:b.sender];
        else if ([key isEqualToString:@"pid"]) r = [@(a.pid.integerValue) compare:@(b.pid.integerValue)];
        else if ([key isEqualToString:@"level"]) r = [@(a.level) compare:@(b.level)];
        else if ([key isEqualToString:@"subsystem"]) r = [a.subsystem caseInsensitiveCompare:b.subsystem];
        else if ([key isEqualToString:@"category"]) r = [a.category caseInsensitiveCompare:b.category];
        else r = [a.message caseInsensitiveCompare:b.message];
        return asc ? r : (NSComparisonResult)-r;
    }];
}

- (BOOL)isAtBottom {
    NSScrollView *sv = _table.enclosingScrollView;
    return !sv || NSMaxY(sv.contentView.bounds) >= NSMaxY(_table.bounds) - 20;
}

- (void)updateDetail {
    NSIndexSet *rows = _table.selectedRowIndexes;
    if (rows.count != 1 || rows.firstIndex >= _shown.count) {
        _detail.string = rows.count > 1 ? [NSString stringWithFormat:@"%lu messages selected", (unsigned long)rows.count] : @"";
        return;
    }
    LogEntry *e = _shown[rows.firstIndex];
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"Time:       %@\n", [_fullFmt stringFromDate:e.time]];
    [s appendFormat:@"Sender:     %@ [%@]\n", e.sender, e.pid];
    [s appendFormat:@"Host:       %@\n", e.host];
    [s appendFormat:@"Facility:   %@\n", e.facility];
    [s appendFormat:@"Level:      %ld (%@)\n", (long)e.level, e.levelName];
    if (e.isOSLog) {
        [s appendFormat:@"Subsystem:  %@\n", e.subsystem];
        [s appendFormat:@"Category:   %@\n", e.category];
    }
    for (NSArray *kv in e.extra) [s appendFormat:@"%-11@ %@\n", kv[0], kv[1]];
    [s appendFormat:@"\n%@", e.message];
    _detail.string = s;
}

#pragma mark - Table data source / delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return tv == _sidebar ? (NSInteger)_sidebarItems.count : (NSInteger)_shown.count;
}

- (NSView *)sidebarCellForRow:(NSInteger)row {
    SideItem *item = _sidebarItems[row];
    NSTableCellView *cell = [_sidebar makeViewWithIdentifier:@"sideCell" owner:nil];
    if (!cell) {
        cell = [NSTableCellView new]; cell.identifier = @"sideCell";
        NSImageView *iv = [NSImageView new]; NSTextField *tf = [NSTextField labelWithString:@""];
        iv.translatesAutoresizingMaskIntoConstraints = NO; tf.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:iv]; [cell addSubview:tf];
        cell.imageView = iv; cell.textField = tf;
        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:16],
            [tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:6],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]]];
    }
    cell.textField.stringValue = item.kind == SideFacility && !item.title.length ? @"(none)" : item.title;
    if (item.kind == SideHeader) {
        cell.textField.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        cell.textField.textColor = [NSColor secondaryLabelColor];
        cell.imageView.image = nil;
    } else {
        cell.textField.font = [NSFont systemFontOfSize:13];
        cell.textField.textColor = [NSColor labelColor];
        NSImage *img = nil;
        // SF Symbols are optional: skip quietly where unavailable (older macOS, Darling).
        if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
            NSString *name = item.kind == SideAll ? @"tray.full" : item.kind == SideFacility ? @"doc.text"
                           : item.kind == SideOSLog ? @"text.bubble" : @"exclamationmark.triangle";
            img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        }
        cell.imageView.image = img;
    }
    return cell;
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (tv == _sidebar) return [self sidebarCellForRow:row];
    if (row >= (NSInteger)_shown.count) return nil;
    LogEntry *e = _shown[row];
    NSTextField *tf = [tv makeViewWithIdentifier:@"logCell" owner:nil];
    if (!tf) {
        tf = [NSTextField labelWithString:@""]; tf.identifier = @"logCell";
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    NSString *c = col.identifier, *v;
    if ([c isEqualToString:@"time"]) v = [_shortFmt stringFromDate:e.time];
    else if ([c isEqualToString:@"sender"]) v = e.sender;
    else if ([c isEqualToString:@"pid"]) v = e.pid;
    else if ([c isEqualToString:@"level"]) v = e.levelName;
    else if ([c isEqualToString:@"subsystem"]) v = e.subsystem;
    else if ([c isEqualToString:@"category"]) v = e.category;
    else v = [e.message stringByReplacingOccurrencesOfString:@"\n" withString:@" ⏎ "];
    tf.stringValue = v;
    tf.font = [NSFont systemFontOfSize:12];
    tf.textColor = e.level <= 3 ? [NSColor systemRedColor] : (e.level == 4 ? [NSColor systemOrangeColor] : [NSColor labelColor]);
    return tf;
}

- (BOOL)tableView:(NSTableView *)tv isGroupRow:(NSInteger)row {
    return tv == _sidebar && _sidebarItems[row].kind == SideHeader;
}

- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row {
    return !(tv == _sidebar && _sidebarItems[row].kind == SideHeader);
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    if (n.object == _sidebar) [self applyFilterScrollToEnd:YES]; else [self updateDetail];
}

- (void)tableView:(NSTableView *)tv sortDescriptorsDidChange:(NSArray *)old {
    if (tv != _table) return;
    [self applyFilterScrollToEnd:NO];
}

#pragma mark - Actions

- (void)filterChanged:(id)sender { [self applyFilterScrollToEnd:YES]; }
- (void)controlTextDidChange:(NSNotification *)n { [self applyFilterScrollToEnd:YES]; }
- (void)focusSearch:(id)sender { [self.window makeFirstResponder:_search]; }

/// Drops everything loaded so far; only newer messages appear afterwards.
- (void)clearDisplay:(id)sender {
    [_all removeAllObjects];
    [self rebuildSidebar];
    [self applyFilterScrollToEnd:YES];
}

- (void)copy:(id)sender {
    NSMutableArray *lines = [NSMutableArray array];
    [_table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (i >= self->_shown.count) return;
        LogEntry *e = self->_shown[i];
        [lines addObject:[@[[self->_fullFmt stringFromDate:e.time], e.sender, e.pid, e.levelName, e.message]
                          componentsJoinedByString:@"\t"]];
    }];
    if (!lines.count) return;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:[lines componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
}
@end
