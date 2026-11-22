//! `zig build pdftext -- FILE.pdf OUT.txt [RUNS.tsv]`: the text of a PDF;
//! with RUNS.tsv, each piece of text with its page and position too
//! (page, x, y, text, tab-separated), for reading tables by column. Used to
//! build the data of templates from standards that NASA publishes as PDF.

const std = @import("std");
const Io = std.Io;

pub const Document = @import("Document.zig");
pub const text = @import("text.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3 and args.len != 4) {
        try Io.File.stderr().writeStreamingAll(io, "usage: pdftext FILE.pdf OUT.txt [RUNS.tsv]\n");
        std.process.exit(2);
    }
    const src = try Io.Dir.cwd().readFileAlloc(io, args[1], arena, .limited(1 << 28));
    const doc = try Document.read(arena, src);
    var runs: std.ArrayList(text.Run) = .empty;
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = args[2], .data = try text.all(&doc, if (args.len == 4) &runs else null) });
    if (args.len == 4) {
        var tsv: std.ArrayList(u8) = .empty;
        for (runs.items) |r| try tsv.print(arena, "{d}\t{d:.1}\t{d:.1}\t{s}\n", .{ r.page, r.x, r.y, r.text });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = args[3], .data = tsv.items });
    }
}

test {
    _ = @import("parse.zig");
    _ = Document;
    _ = text;
}
