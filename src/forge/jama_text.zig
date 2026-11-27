//! An item's text as Jama Connect keeps it: its `description` is HTML (a
//! rich text field). The import reads it as Markdown (import/xhtml.zig);
//! a publish writes each paragraph as a `p`; the two are compared as plain
//! text, since Jama rewrites the HTML it is given.

const std = @import("std");

const escape = @import("../xml/escape.zig").escape;
const xhtml = @import("../import/xhtml.zig");
const xml = @import("../xml.zig");

/// The Markdown of Jama's HTML; its plain text when it is not XHTML
pub fn markdown(arena: std.mem.Allocator, source: []const u8) ![]const u8 {
    var fixed = try arena.print("<div>{s}</div>", .{source});
    // HTML that XML refuses: void elements, and the one named entity Jama writes
    for ([_][2][]const u8{ .{ "<br>", "<br/>" }, .{ "<hr>", "<hr/>" }, .{ "&nbsp;", "&#160;" } }) |r| {
        fixed = try std.mem.replaceOwned(u8, arena, fixed, r[0], r[1]);
    }
    var diag: xml.Diagnostic = .{};
    const root = xml.parse(arena, fixed, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidXml => return plain(arena, source),
    };
    const md = try xhtml.markdown(arena, root);
    // a no-break space reads as a space
    return std.mem.replaceOwned(u8, arena, md, "\u{a0}", " ");
}

/// The HTML of an item's text: a `p` for each paragraph
pub fn html(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    var paragraphs = std.mem.splitSequence(u8, std.mem.trim(u8, text, " \r\n"), "\n\n");
    while (paragraphs.next()) |p| {
        const t = std.mem.trim(u8, p, " \r\n");
        if (t.len == 0) continue;
        out.writer.writeAll("<p>") catch return error.OutOfMemory;
        escape(&out.writer, t) catch return error.OutOfMemory;
        out.writer.writeAll("</p>") catch return error.OutOfMemory;
    }
    return out.written();
}

/// The text of HTML: tags taken out, entities read, whitespace collapsed
pub fn plain(arena: std.mem.Allocator, h: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    var space = false;
    while (i < h.len) {
        const c = h[i];
        if (c == '<') {
            const end = std.mem.findScalarPos(u8, h, i, '>') orelse h.len - 1;
            i = end + 1;
            space = true;
            continue;
        }
        var ch: []const u8 = h[i .. i + 1];
        if (c == '&') if (std.mem.findScalarPos(u8, h, i, ';')) |end| if (end - i <= 8) {
            if (entity(h[i + 1 .. end])) |e| {
                ch = e;
                i = end;
            }
        };
        i += 1;
        if (ch.len == 1 and std.ascii.isWhitespace(ch[0]) or std.mem.eql(u8, ch, "\u{a0}")) {
            space = true;
            continue;
        }
        if (space and out.items.len > 0) try out.append(arena, ' ');
        space = false;
        try out.appendSlice(arena, ch);
    }
    return out.items;
}

fn entity(name: []const u8) ?[]const u8 {
    const named = [_][2][]const u8{ .{ "amp", "&" }, .{ "lt", "<" }, .{ "gt", ">" }, .{ "quot", "\"" }, .{ "apos", "'" }, .{ "#39", "'" }, .{ "nbsp", " " }, .{ "#160", " " } };
    for (named) |n| if (std.mem.eql(u8, n[0], name)) return n[1];
    return null;
}

test "Jama's HTML as Markdown, an item's text as HTML, and both as plain text" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("The rover shall stop.\n\nWithin **2 s**.", try markdown(a, "<p>The rover shall&nbsp;stop.</p><p>Within <strong>2 s</strong>.</p>"));
    // not XHTML: its text
    try std.testing.expectEqualStrings("An open tag", try markdown(a, "<p>An <b>open tag</p>"));
    const h = try html(a, "Speed < 0.5 m/s & no more.\n\nSecond.");
    try std.testing.expectEqualStrings("<p>Speed &lt; 0.5 m/s &amp; no more.</p><p>Second.</p>", h);
    try std.testing.expectEqualStrings("Speed < 0.5 m/s & no more. Second.", try plain(a, h));
    try std.testing.expectEqualStrings(try plain(a, h), try plain(a, "<p>Speed &lt; 0.5 m/s &amp;&nbsp;no more.</p>\n<p>Second.</p>"));
}
