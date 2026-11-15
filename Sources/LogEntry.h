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

#import <Foundation/Foundation.h>

/// One ASL message.
@interface LogEntry : NSObject
@property (nonatomic) uint64_t msgID;
@property (nonatomic, strong) NSDate *time;
@property (nonatomic, copy) NSString *sender, *pid, *facility, *host, *message;
@property (nonatomic, copy) NSString *subsystem, *category;   // set for os_log(3) messages
@property (nonatomic) BOOL isOSLog;
@property (nonatomic) NSInteger level;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *extra;   // remaining [key, value] pairs
+ (NSArray<NSString *> *)levelNames;
- (NSString *)levelName;
@end

/// Reads messages through asl_search(3).
@interface ASLReader : NSObject
/// Entries with ASLMessageID greater than afterID (all when afterID == 0), oldest first.
+ (NSArray<LogEntry *> *)fetchAfterID:(uint64_t)afterID;
@end
