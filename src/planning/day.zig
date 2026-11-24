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

pub const Civil = struct { year: i32, month: u32, day: u32 };

/// The year, month and day of a day (Howard Hinnant's civil_from_days)
pub fn civil(d: Day) Civil {
    const z = d + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const dd = doy - @divFloor(153 * mp + 2, 5) + 1;
    const mm = if (mp < 10) mp + 3 else mp - 9;
    return .{ .year = yoe + era * 400 + @as(i32, if (mm <= 2) 1 else 0), .month = @intCast(mm), .day = @intCast(dd) };
}

/// `YYYY-MM-DD` of a day
pub fn format(d: Day) [10]u8 {
    const c = civil(d);
    var out: [10]u8 = undefined;
    _ = std.mem.print(&out, "{d:0>4}-{d:0>2}-{d:0>2}", .{ @as(u32, @intCast(c.year)), c.month, c.day }) catch unreachable;
    return out;
}

/// 0 for Monday to 6 for Sunday (1970-01-01 was a Thursday)
pub fn weekday(d: Day) u3 {
    return @intCast(@mod(d + 3, 7));
}

/// The Monday of the week `d` is in
pub fn monday(d: Day) Day {
    return d - weekday(d);
}

/// The ISO 8601 week of a day, `YYYY-Www`: the year of its week's Thursday
pub fn isoWeek(d: Day) [8]u8 {
    const thursday = monday(d) + 3;
    const year = civil(thursday).year;
    const week: u32 = @intCast(@divFloor(thursday - fromCivil(year, 1, 1), 7) + 1);
    var out: [8]u8 = undefined;
    _ = std.mem.print(&out, "{d:0>4}-W{d:0>2}", .{ @as(u32, @intCast(year)), week }) catch unreachable;
    return out;
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
}

test "weekdays and ISO weeks" {
    // 2027-03-01 is a Monday
    try testing.expectEqual(0, weekday(parse("2027-03-01").?));
    try testing.expectEqual(6, weekday(parse("2027-03-07").?));
    try testing.expectEqualStrings("2027-03-01", &format(monday(parse("2027-03-04").?)));
    try testing.expectEqualStrings("2027-W09", &isoWeek(parse("2027-03-01").?));
    // 2027-01-01 is a Friday, in the last week of 2026
    try testing.expectEqualStrings("2026-W53", &isoWeek(parse("2027-01-01").?));
    try testing.expectEqualStrings("2026-W01", &isoWeek(parse("2025-12-29").?));
}
