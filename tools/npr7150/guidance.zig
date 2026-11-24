//! The handbook's reading of each requirement, from `guidance.csv`, as
//! items of the type `guidance` (`HB-013`) that interpret it (`SWE-013`).

const std = @import("std");

const write = @import("write.zig");

const Error = std.mem.Allocator.Error;

/// The columns of `guidance.csv` after `swe`, with what each is called in
/// the document
const columns = [_]struct { []const u8, []const u8 }{
    .{ "evidence", "Objective evidence" },
    .{ "documents", "Documents" },
    .{ "milestones", "Milestones" },
    .{ "small_projects", "Small projects" },
    .{ "assurance", "Software assurance" },
    .{ "other", "Also" },
};

/// `rows` is the CSV with its header
pub fn document(arena: std.mem.Allocator, rows: []const []const []const u8, pages: []const write.Page) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "<!-- The NASA Software Engineering Handbook's reading of each requirement of NPR 7150.2D: paraphrased from its pages (NASA-HDBK-2203, version D, through Internet Archive captures of 2026-03 to 2026-10), in tools/npr7150/guidance.csv of skein's repository. Written by tools/npr7150 (zig build npr7150), and kept by hand from here. -->\n\n# The handbook's reading\n\nWhat NASA-HDBK-2203 says each requirement asks for in practice: the objective evidence of compliance, the documents that hold it, and what software assurance does. The handbook is guidance; the requirements are the NPR's.\n");
    if (rows.len == 0) return out.items;
    const header = rows[0];
    for (rows[1..]) |row| {
        if (row.len < 2 or !std.mem.startsWith(u8, row[0], "SWE-")) continue;
        const id = row[0];
        const title = for (pages) |p| {
            if (std.mem.eql(u8, p.id, id)) break p.title;
        } else "";
        try out.print(arena, "\n## {s} {s}\n\n%guidance[HB-{s} interprets={s}] {s}\n", .{ id, try write.escape(arena, title), id["SWE-".len..], id, try write.escape(arena, cell(header, row, "meaning")) });
        var any = false;
        for (columns) |c| {
            const text = cell(header, row, c[0]);
            if (text.len == 0) continue;
            if (!any) try out.append(arena, '\n');
            any = true;
            try out.print(arena, "- **{s}:** {s}\n", .{ c[1], try write.escape(arena, text) });
        }
    }
    return out.items;
}

/// The value of the column `name` in `row`; empty when there is none
fn cell(header: []const []const u8, row: []const []const u8, name: []const u8) []const u8 {
    for (header, 0..) |h, i| if (std.mem.eql(u8, h, name)) return if (i < row.len) std.mem.trim(u8, row[i], " ") else "";
    return "";
}

test document {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const rows = [_][]const []const u8{
        &.{ "swe", "meaning", "evidence", "assurance" },
        &.{ "SWE-013", "Plans cover the life cycle.", "a plan; its *approval*", "" },
    };
    const pages = [_]write.Page{.{ .id = "SWE-013", .title = "Software Plans", .url = "u" }};
    const text = try document(arena.allocator(), &rows, &pages);
    try std.testing.expect(std.mem.endsWith(u8, text,
        \\## SWE-013 Software Plans
        \\
        \\%guidance[HB-013 interprets=SWE-013] Plans cover the life cycle.
        \\
        \\- **Objective evidence:** a plan; its \*approval\*
        \\
    ));
}
