//! Appendix C of NPR 7150.2D, the Requirements Mapping Matrix: for each
//! requirement in it, its authority and the classes that invoke it.

const std = @import("std");

const html = @import("html.zig");

pub const Row = struct {
    /// the paragraph, `3.1.4`
    section: []const u8,
    /// the requirement, `SWE-024`
    id: []const u8,
    /// who approves tailoring for classes A to E; empty when none of them
    authority: []const u8,
    /// for class F
    authority_f: []const u8,
    /// the classes marked X, in order: `ABCDF`
    classes: []const u8,
};

/// The rows of the matrix: a section, a three-digit number, the text, the
/// A to E authority, A to E, a spacer, the F authority, F
pub fn read(arena: std.mem.Allocator, page: []const u8) std.mem.Allocator.Error![]const Row {
    var out: std.ArrayList(Row) = .empty;
    for (try html.rows(arena, page)) |cells| {
        if (cells.len != 12 or cells[1].len != 3 or !allDigits(cells[1])) continue;
        var classes: std.ArrayList(u8) = .empty;
        for ("ABCDE", 4..) |class, i| if (std.mem.eql(u8, cells[i], "X")) try classes.append(arena, class);
        if (std.mem.eql(u8, cells[11], "X")) try classes.append(arena, 'F');
        try out.append(arena, .{
            .section = cells[0],
            .id = try arena.print("SWE-{s}", .{cells[1]}),
            .authority = cells[3],
            .authority_f = cells[10],
            .classes = classes.items,
        });
    }
    return out.items;
}

fn allDigits(s: []const u8) bool {
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

pub fn find(all: []const Row, id: []const u8) ?Row {
    for (all) |r| if (std.mem.eql(u8, r.id, id)) return r;
    return null;
}

test read {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const page =
        \\<table><tr><td valign="top"> 3.2</td> <td valign="top"> </td> <td colspan="10"><b>Cost</b></td></tr>
        \\<tr><td valign="top"> 3.1.4</td> <td valign="top"> 024</td> <td valign="top"> The project manager shall track.<br>a. Corrective actions.</td> <td valign="top"> Center </td> <td valign="top"> X</td> <td valign="top"> X</td> <td valign="top"> X</td> <td valign="top"> X</td> <td valign="top"> </td> <td bgcolor="999999"></td> <td valign="top"> CIO </td> <td valign="top"> X</td></tr></table>
    ;
    const rows = try read(arena.allocator(), page);
    try std.testing.expectEqual(1, rows.len);
    try std.testing.expectEqualStrings("SWE-024", rows[0].id);
    try std.testing.expectEqualStrings("3.1.4", rows[0].section);
    try std.testing.expectEqualStrings("ABCDF", rows[0].classes);
    try std.testing.expectEqualStrings("CIO", rows[0].authority_f);
}
