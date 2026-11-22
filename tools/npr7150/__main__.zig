//! Writes NPR 7150.2D as skein documents, one per chapter of requirements
//! (2 to 5), from its pages on NODIS and the handbook's page of each
//! requirement:
//!
//!     zig build npr7150 -- HTML_DIR OUT_DIR RETRIEVED
//!
//! HTML_DIR holds Chapter2.html to Chapter5.html and AppendixC.html, as
//! `tools/npr7150/fetch.sh` saves them; RETRIEVED is their date. README.md
//! says where everything comes from.

const std = @import("std");
const Io = std.Io;

const appendix = @import("appendix.zig");
const guidance = @import("guidance.zig");
const html = @import("html.zig");
const write = @import("write.zig");

const csv = @import("skein").csv;

const nodis = "https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=";
/// where they come from: README.md
const pages_csv = @embedFile("handbook.csv");
const guidance_csv = @embedFile("guidance.csv");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4) {
        try Io.File.stderr().writeStreamingAll(io, "usage: npr7150 HTML_DIR OUT_DIR RETRIEVED\n");
        std.process.exit(2);
    }
    const cwd = Io.Dir.cwd();
    var in = try cwd.openDir(io, args[1], .{});
    defer in.close(io);
    try cwd.createDirPath(io, args[2]);
    var out = try cwd.openDir(io, args[2], .{});
    defer out.close(io);

    const matrix_page = try in.readFileAlloc(io, "AppendixC.html", arena, .limited(1 << 22));
    const matrix = try appendix.read(arena, matrix_page);
    const pages = try readPages(arena, pages_csv);
    const effective = effectiveDate(matrix_page);

    var count: usize = 0;
    for ([_][]const u8{ "2", "3", "4", "5" }) |n| {
        const name = try arena.print("Chapter{s}", .{n});
        const page = try in.readFileAlloc(io, try arena.print("{s}.html", .{name}), arena, .limited(1 << 22));
        const blocks = try html.blocks(arena, page);
        const text = try write.chapter(arena, blocks, matrix, pages, .{ .url = try arena.print("{s}{s}", .{ nodis, name }), .effective = effective, .retrieved = args[3] });
        try out.writeFile(io, .{ .sub_path = try arena.print("chapter-{s}.md", .{n}), .data = text });
        count += std.mem.count(u8, text, "\n%swe[SWE-");
    }
    try out.writeFile(io, .{ .sub_path = "guidance.md", .data = try guidance.document(arena, try csv.parse(arena, guidance_csv), pages) });
    var line: [128]u8 = undefined;
    try Io.File.stdout().writeStreamingAll(io, try std.mem.print(&line, "npr7150: {d} requirements, {d} in the matrix of Appendix C\n", .{ count, matrix.len }));
}

/// `Effective Date: March 08, 2022` of a page, as it is written
fn effectiveDate(page: []const u8) []const u8 {
    const label = "Effective Date: ";
    const at = std.mem.find(u8, page, label) orelse return "unknown";
    const end = std.mem.findScalarPos(u8, page, at, '<') orelse return "unknown";
    return std.mem.trim(u8, page[at + label.len .. end], " ");
}

/// The rows of `handbook.csv` after its header: swe, title, page
fn readPages(arena: std.mem.Allocator, text: []const u8) ![]const write.Page {
    var out: std.ArrayList(write.Page) = .empty;
    const rows = try csv.parse(arena, text);
    for (rows, 0..) |row, i| {
        if (i == 0 or row.len < 3) continue;
        try out.append(arena, .{ .id = row[0], .title = row[1], .url = row[2] });
    }
    return out.items;
}

test {
    _ = guidance;
    _ = html;
    _ = appendix;
    _ = write;
}

test readPages {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const pages = try readPages(arena.allocator(), "swe,title,page\nSWE-027,\"Use of Commercial, Government, and Legacy Software\",https://x.invalid/27\n");
    try std.testing.expectEqual(1, pages.len);
    try std.testing.expectEqualStrings("Use of Commercial, Government, and Legacy Software", pages[0].title);
    // every requirement of the index has its page
    try std.testing.expectEqual(130, (try readPages(arena.allocator(), pages_csv)).len);
}
