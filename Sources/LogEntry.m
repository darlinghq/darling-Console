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

#import "LogEntry.h"
#include <asl.h>

@implementation LogEntry
+ (NSArray *)levelNames {
    return @[@"Emergency", @"Alert", @"Critical", @"Error", @"Warning", @"Notice", @"Info", @"Debug"];
}
- (NSString *)levelName {
    NSArray *n = [LogEntry levelNames];
    return (self.level >= 0 && self.level < 8) ? n[self.level] : [NSString stringWithFormat:@"%ld", (long)self.level];
}
@end

@implementation ASLReader

static NSString *Get(aslmsg m, const char *key) {
    const char *v = asl_get(m, key);
    if (!v) return @"";
    NSString *s = [NSString stringWithUTF8String:v];
    return s ?: @"";
}

+ (NSArray<LogEntry *> *)fetchAfterID:(uint64_t)afterID {
    aslmsg q = asl_new(ASL_TYPE_QUERY);
    if (afterID > 0) {
        char buf[32]; snprintf(buf, sizeof buf, "%llu", afterID);
        asl_set_query(q, ASL_KEY_MSG_ID, buf, ASL_QUERY_OP_GREATER | ASL_QUERY_OP_NUMERIC);
    }
    aslresponse res = asl_search(NULL, q);
    asl_release(q);
    NSMutableArray *out = [NSMutableArray array];
    if (!res) return out;

    NSSet *skip = [NSSet setWithObjects:@ASL_KEY_TIME, @ASL_KEY_TIME_NSEC, @ASL_KEY_SENDER, @ASL_KEY_PID,
                   @ASL_KEY_LEVEL, @ASL_KEY_FACILITY, @ASL_KEY_HOST, @ASL_KEY_MSG, @ASL_KEY_MSG_ID,
                   @"os_log(3)", @"Subsystem", @"Category", @"HexBuffer", nil];
    aslmsg m;
    while ((m = asl_next(res)) != NULL) {
        @autoreleasepool {
            LogEntry *e = [LogEntry new];
            e.msgID = strtoull([Get(m, ASL_KEY_MSG_ID) UTF8String], NULL, 10);
            double secs = [Get(m, ASL_KEY_TIME) doubleValue], nanos = [Get(m, ASL_KEY_TIME_NSEC) doubleValue];
            e.time = [NSDate dateWithTimeIntervalSince1970:secs + nanos / 1e9];
            e.sender = Get(m, ASL_KEY_SENDER);
            e.pid = Get(m, ASL_KEY_PID);
            NSString *lv = Get(m, ASL_KEY_LEVEL);
            e.level = lv.length ? [lv integerValue] : 7;
            e.facility = Get(m, ASL_KEY_FACILITY);
            e.host = Get(m, ASL_KEY_HOST);
            e.message = Get(m, ASL_KEY_MSG);
            e.isOSLog = [Get(m, "os_log(3)") isEqualToString:@"TRUE"];
            e.subsystem = Get(m, "Subsystem");
            e.category = Get(m, "Category");
            NSMutableArray *extra = [NSMutableArray array];
            const char *k;
            for (uint32_t i = 0; (k = asl_key(m, i)) != NULL; i++) {
                NSString *key = [NSString stringWithUTF8String:k];
                if (!key || [skip containsObject:key]) continue;
                const char *v = asl_get(m, k);
                if (v) [extra addObject:@[key, [NSString stringWithUTF8String:v] ?: @""]];
            }
            e.extra = extra;
            [out addObject:e];
        }
    }
    asl_release(res);
    return out;
}
@end
