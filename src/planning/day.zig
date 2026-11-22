//! Days of the calendar as numbers, for arithmetic on dates: days since
//! 1970-01-01. Until calendars come with resources (#92), every day is a
//! working day.

const std = @import("std");

const datetime = @import("../toml/datetime.zig");

pub const Day = i32;

/// The day `text` names (`YYYY-MM-DD`); null when it names none
pub fn parse(text: []const u8) ?Day {
    if (text.len != 10) return null;
    const dt = datetime.parse(text) orelse return null;
    const d = dt.date orelse return null;
    return fromCivil(d.year, d.month, d.day);
}

/// The day of a year, month and day (Howard Hinnant's days_from_civil)
pub fn fromCivil(year: i32, month: u32, day: u32) Day {
    const y = if (month <= 2) year - 1 else year;
    const era = @divFloor(y, 400);
    const yoe: i32 = y - era * 400;
    const m: i32 = @intCast(month);
    const doy: i32 = @divFloor(153 * (if (m > 2) m - 3 else m + 9) + 2, 5) + @as(i32, @intCast(day)) - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// `YYYY-MM-DD` of a day
pub fn format(d: Day) [10]u8 {
    const z = d + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const dd = doy - @divFloor(153 * mp + 2, 5) + 1;
    const mm = if (mp < 10) mp + 3 else mp - 9;
    const yy = yoe + era * 400 + @as(i32, if (mm <= 2) 1 else 0);
    var out: [10]u8 = undefined;
    _ = std.mem.print(&out, "{d:0>4}-{d:0>2}-{d:0>2}", .{ @as(u32, @intCast(yy)), @as(u32, @intCast(mm)), @as(u32, @intCast(dd)) }) catch unreachable;
    return out;
}

/// The last day of work that starts on `start` and takes `duration` days;
/// a duration of 0 (a milestone) ends on its start
pub fn finishOf(start: Day, duration: u32) Day {
    return start + @as(Day, @intCast(@max(duration, 1))) - 1;
}

const testing = std.testing;

test "days and dates" {
    try testing.expectEqual(0, parse("1970-01-01").?);
    try testing.expectEqual(31 + 28, parse("1970-03-01").?);
    try testing.expectEqualStrings("2027-03-01", &format(parse("2027-03-01").?));
    try testing.expectEqualStrings("2028-02-29", &format(parse("2028-02-28").? + 1));
    try testing.expectEqualStrings("1999-12-31", &format(parse("2000-01-01").? - 1));
    try testing.expectEqual(null, parse("2027-02-30"));
    try testing.expectEqual(null, parse("2027-03-01T10:00:00"));
    try testing.expectEqualStrings("2027-03-05", &format(finishOf(parse("2027-03-01").?, 5)));
    try testing.expectEqualStrings("2027-03-01", &format(finishOf(parse("2027-03-01").?, 0)));
}
