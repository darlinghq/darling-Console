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

#import "AppDelegate.h"
#import "MainWindowController.h"

@implementation AppDelegate {
    MainWindowController *_controller;
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [self buildMenu];
    _controller = [MainWindowController new];
    [_controller showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

static NSMenuItem *Item(NSString *title, SEL action, NSString *key) {
    return [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key ?: @""];
}

static void AddMenu(NSMenu *main, NSString *title, NSArray *items) {
    NSMenuItem *top = [NSMenuItem new];
    [main addItem:top];
    NSMenu *m = [[NSMenu alloc] initWithTitle:title];
    for (NSMenuItem *i in items) [m addItem:i];
    top.submenu = m;
}

- (void)buildMenu {
    NSMenu *main = [NSMenu new];
    AddMenu(main, @"ASL Console", @[
        Item(@"About ASL Console", @selector(orderFrontStandardAboutPanel:), nil),
        [NSMenuItem separatorItem],
        Item(@"Hide ASL Console", @selector(hide:), @"h"),
        [NSMenuItem separatorItem],
        Item(@"Quit ASL Console", @selector(terminate:), @"q")]);
    AddMenu(main, @"Edit", @[
        Item(@"Copy", @selector(copy:), @"c"),
        Item(@"Select All", @selector(selectAll:), @"a"),
        [NSMenuItem separatorItem],
        Item(@"Find…", @selector(focusSearch:), @"f"),
        Item(@"Clear Display", @selector(clearDisplay:), @"k")]);
    AddMenu(main, @"Window", @[
        Item(@"Minimize", @selector(performMiniaturize:), @"m"),
        Item(@"Close", @selector(performClose:), @"w")]);
    NSApp.mainMenu = main;
    NSApp.windowsMenu = main.itemArray.lastObject.submenu;
}
@end
