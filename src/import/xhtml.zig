//! Markdown from the XHTML of a ReqIF text value: paragraphs and other
//! blocks apart by a blank line, `br` as a line break, lists as `-` and
//! `1.` entries, `b`/`strong`, `i`/`em`, `code` and `a` as Markdown, and the
//! text of everything else. Whitespace is collapsed, as XHTML shows it,
//! except in `pre`.

const std = @import("std");

const xml = @import("../xml.zig");

const Out = struct {
    arena: std.mem.Allocator,
    buf: std.ArrayList(u8) = .empty,

    fn put(self: *Out, s: []const u8) !void {
        try self.buf.appendSlice(self.arena, s);
    }

    /// A blank line before what follows, unless there is one or nothing
    fn block(self: *Out) !void {
        const t = std.mem.trimEnd(u8, self.buf.items, " ");
        self.buf.items.len = t.len;
        if (t.len == 0 or std.mem.endsWith(u8, t, "\n\n")) return;
        try self.put(if (std.mem.endsWith(u8, t, "\n")) "\n" else "\n\n");
    }

    /// Text, its whitespace collapsed to single spaces
    fn text(self: *Out, s: []const u8) !void {
        var space = false;
        for (s) |c| {
            if (std.ascii.isWhitespace(c)) {
                space = true;
                continue;
            }
            const at_line_start = self.buf.items.len == 0 or self.buf.items[self.buf.items.len - 1] == '\n';
            if (space and !at_line_start) try self.buf.append(self.arena, ' ');
            space = false;
            try self.buf.append(self.arena, c);
        }
        if (space and self.buf.items.len > 0 and self.buf.items[self.buf.items.len - 1] != '\n') try self.buf.append(self.arena, ' ');
    }
};

/// The Markdown of the content of `e` (a ReqIF `THE-VALUE`)
pub fn markdown(arena: std.mem.Allocator, e: *const xml.Element) ![]const u8 {
    var out: Out = .{ .arena = arena };
    try content(&out, e, 0);
    return std.mem.trim(u8, out.buf.items, " \n");
}

fn content(out: *Out, e: *const xml.Element, list_depth: usize) error{OutOfMemory}!void {
    for (e.content) |n| switch (n) {
        .text => |t| try out.text(t),
        .element => |c| try element(out, c, list_depth),
    };
}

fn element(out: *Out, e: *const xml.Element, list_depth: usize) error{OutOfMemory}!void {
    const name = xml.Element.local(e.name);
    const blocks = [_][]const u8{ "p", "div", "blockquote", "table", "tr", "h1", "h2", "h3", "h4", "h5", "h6" };
    for (blocks) |b| if (std.mem.eql(u8, name, b)) {
        try out.block();
        if (name[0] == 'h' and name.len == 2) {
            try out.put("#######"[0 .. name[1] - '0']);
            try out.put(" ");
        }
        try content(out, e, list_depth);
        try out.block();
        return;
    };
    if (std.mem.eql(u8, name, "br")) return out.put("\n");
    if (std.mem.eql(u8, name, "pre")) {
        try out.block();
        try out.put("```\n");
        try out.put(std.mem.trim(u8, try e.text(out.arena), "\n"));
        try out.put("\n```");
        return out.block();
    }
    if (std.mem.eql(u8, name, "ul") or std.mem.eql(u8, name, "ol")) {
        if (list_depth == 0) try out.block() else try out.put("\n");
        var n: usize = 0;
        for (e.content) |c| switch (c) {
            .element => |li| {
                if (!std.mem.eql(u8, xml.Element.local(li.name), "li")) continue;
                n += 1;
                if (n > 1) try out.put("\n");
                for (0..list_depth) |_| try out.put("  ");
                if (name[0] == 'o') try out.put(try out.arena.print("{d}. ", .{n})) else try out.put("- ");
                try content(out, li, list_depth + 1);
            },
            .text => {},
        };
        if (list_depth == 0) try out.block();
        return;
    }
    const marks = [_]struct { []const u8, []const u8 }{ .{ "b", "**" }, .{ "strong", "**" }, .{ "i", "*" }, .{ "em", "*" }, .{ "code", "`" } };
    for (marks) |m| if (std.mem.eql(u8, name, m[0])) {
        try out.put(m[1]);
        try content(out, e, list_depth);
        return out.put(m[1]);
    };
    if (std.mem.eql(u8, name, "a")) if (e.attribute("href")) |href| {
        try out.put("[");
        try content(out, e, list_depth);
        return out.put(try out.arena.print("]({s})", .{href}));
    };
    try content(out, e, list_depth);
}
