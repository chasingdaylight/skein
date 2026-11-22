//! Which days are working days: the days of the week that are, less the
//! holidays and, for a person, their absences. A project without a
//! calendar counts every day.

const std = @import("std");

const day = @import("day.zig");
const Day = day.Day;

const Calendar = @This();

/// Monday to Sunday
workdays: [7]bool = @splat(true),
holidays: []const Day = &.{},
/// a person's days away, each from its first to its last day
absences: []const Range = &.{},
/// the hours of a working day
hours: f64 = 8,

pub const Range = struct { first: Day, last: Day };

/// Every day a working day of 8 hours
pub const every_day: Calendar = .{};

pub fn isWorking(self: *const Calendar, d: Day) bool {
    if (!self.workdays[day.weekday(d)]) return false;
    for (self.holidays) |h| if (h == d) return false;
    for (self.absences) |r| if (d >= r.first and d <= r.last) return false;
    return true;
}

/// Whether some day of the week is a working day
pub fn works(self: *const Calendar) bool {
    for (self.workdays) |w| if (w) return true;
    return false;
}

/// The last day of work that starts on `start` and takes `duration`
/// working days; a duration of 0 (a milestone) ends on its start. A
/// calendar with no working day counts every day.
pub fn finishOf(self: *const Calendar, start: Day, duration: u32) Day {
    if (duration == 0) return start;
    if (!self.works()) return start + @as(Day, @intCast(duration)) - 1;
    var d = start;
    var left = duration;
    while (true) : (d += 1) {
        if (!self.isWorking(d)) continue;
        left -= 1;
        if (left == 0) return d;
    }
}

/// The working days from `first` to `last`, both counted
pub fn workingDays(self: *const Calendar, first: Day, last: Day) u32 {
    var n: u32 = 0;
    var d = first;
    while (d <= last) : (d += 1) {
        if (self.isWorking(d)) n += 1;
    }
    return n;
}

const testing = std.testing;

test "working days: weekends, holidays and absences" {
    const week: Calendar = .{ .workdays = .{ true, true, true, true, true, false, false }, .holidays = &.{day.parse("2027-03-03").?} };
    const monday = day.parse("2027-03-01").?;
    try testing.expect(week.isWorking(monday));
    try testing.expect(!week.isWorking(monday + 2));
    try testing.expect(!week.isWorking(monday + 5));
    // five working days from Monday: past the holiday and the weekend
    try testing.expectEqualStrings("2027-03-08", &day.format(week.finishOf(monday, 5)));
    try testing.expectEqual(4, week.workingDays(monday, monday + 6));
    try testing.expectEqual(monday, week.finishOf(monday, 0));
    try testing.expectEqualStrings("2027-03-05", &day.format(every_day.finishOf(monday, 5)));
    const away: Calendar = .{ .absences = &.{.{ .first = monday, .last = monday + 1 }} };
    try testing.expectEqual(5, away.workingDays(monday, monday + 6));
}
