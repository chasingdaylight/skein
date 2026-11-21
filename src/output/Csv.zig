//! Writes CSV (RFC 4180): fields with a comma, a quote or a line end are
//! quoted, and a quote inside is doubled. Lines end with a line feed.

const std = @import("std");

const Csv = @This();

pub const Error = std.mem.Allocator.Error;

arena: std.mem.Allocator,
out: std.ArrayList(u8) = .empty,
/// whether the row being written has a field yet
in_row: bool = false,

pub fn field(self: *Csv, value: []const u8) Error!void {
    if (self.in_row) try self.out.append(self.arena, ',');
    self.in_row = true;
    if (std.mem.findAny(u8, value, ",\"\r\n") == null) return self.out.appendSlice(self.arena, value);
    try self.out.append(self.arena, '"');
    for (value) |c| {
        if (c == '"') try self.out.append(self.arena, '"');
        try self.out.append(self.arena, c);
    }
    try self.out.append(self.arena, '"');
}

pub fn integer(self: *Csv, value: u64) Error!void {
    var buf: [20]u8 = undefined;
    try self.field(std.mem.print(&buf, "{d}", .{value}) catch unreachable);
}

pub fn endRow(self: *Csv) Error!void {
    try self.out.append(self.arena, '\n');
    self.in_row = false;
}

/// A whole row
pub fn row(self: *Csv, fields: []const []const u8) Error!void {
    for (fields) |f| try self.field(f);
    try self.endRow();
}

// req: export.csv
test "fields are quoted only when they must be" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var csv: Csv = .{ .arena = arena.allocator() };
    try csv.row(&.{ "id", "text", "line" });
    try csv.field("SRS-001");
    try csv.field("The software shall say \"hello\", then stop.\nSecond line.");
    try csv.integer(12);
    try csv.endRow();
    try csv.row(&.{ "", "plain", "" });
    try std.testing.expectEqualStrings(
        "id,text,line\n" ++
            "SRS-001,\"The software shall say \"\"hello\"\", then stop.\nSecond line.\",12\n" ++
            ",plain,\n",
        csv.out.items,
    );
}
