//! Markdown as HTML, block by block, with the block structure skein
//! reads (markdown/blocks.zig): headings with anchors, paragraphs, lists
//! (with their entries read as Markdown of their own), fenced and
//! indented code, block quotes, tables, HTML blocks and thematic breaks.
//! Front matter is left out.

const std = @import("std");

const inline_html = @import("inline.zig");
const markdown = @import("../markdown.zig");

pub const Error = std.mem.Allocator.Error;
pub const Options = inline_html.Options;

/// What a document's rendering keeps between its blocks
pub const Document = struct {
    arena: std.mem.Allocator,
    options: Options = .{},
    out: std.ArrayList(u8) = .empty,
    /// the anchors given to headings, to keep them apart
    anchors: std.array_hash_map.String(usize) = .empty,
    /// the first heading of level 1, for the page's title
    title: ?[]const u8 = null,

    /// Appends `source`, Markdown, as HTML
    pub fn render(self: *Document, source: []const u8) Error!void {
        // the same HTML whatever the line ends
        const lf = try std.mem.replaceOwned(u8, self.arena, source, "\r\n", "\n");
        const blocks = try markdown.scan(self.arena, lf);
        for (blocks) |b| try self.block(b);
    }

    fn block(self: *Document, b: markdown.Block) Error!void {
        const a = self.arena;
        switch (b.kind) {
            .front_matter, .yaml_front_matter => {},
            // the renderer of a project turns markers into what it shows first
            .marker => {
                try self.out.appendSlice(a, "<p>");
                try inline_html.escape(a, &self.out, b.text);
                try self.out.appendSlice(a, "</p>\n");
            },
            .heading => try self.heading(b.text),
            .paragraph => {
                try self.out.appendSlice(a, "<p>");
                try inline_html.render(a, &self.out, std.mem.trim(u8, b.text, " \t\r\n"), self.options);
                try self.out.appendSlice(a, "</p>\n");
            },
            .list => try self.list(b),
            .code => try self.code(b.text),
            .quote => {
                try self.out.appendSlice(a, "<blockquote>\n");
                try self.nested(try unquote(a, b.text));
                try self.out.appendSlice(a, "</blockquote>\n");
            },
            .table => try self.table(b.text),
            // HTML of block elements is kept as it is; a paragraph that starts
            // with an inline tag (the anchor of an item) is a paragraph
            .html => if (isBlockHtml(b.text)) {
                try self.out.appendSlice(a, b.text);
                try self.out.append(a, '\n');
            } else {
                try self.out.appendSlice(a, "<p>");
                try inline_html.render(a, &self.out, std.mem.trim(u8, b.text, " \t\r\n"), self.options);
                try self.out.appendSlice(a, "</p>\n");
            },
            .thematic_break => try self.out.appendSlice(a, "<hr>\n"),
        }
    }

    /// Renders `source` inside the current element, with the same anchors
    fn nested(self: *Document, source: []const u8) Error!void {
        const blocks = try markdown.scan(self.arena, source);
        for (blocks) |b| try self.block(b);
    }

    fn heading(self: *Document, text: []const u8) Error!void {
        const a = self.arena;
        const line = std.mem.trim(u8, text, " \t\r");
        var level: usize = 0;
        while (level < line.len and line[level] == '#') level += 1;
        // a closing run of #, after a space, is not part of the heading
        var content = std.mem.trim(u8, line[level..], " \t");
        const closing = std.mem.trimEnd(u8, content, "#");
        if (closing.len < content.len and (closing.len == 0 or closing[closing.len - 1] == ' ')) content = std.mem.trimEnd(u8, closing, " ");
        if (level == 1 and self.title == null) self.title = content;
        const anchor = try self.anchorOf(content);
        try self.out.print(a, "<h{d} id=\"", .{level});
        try inline_html.attribute(a, &self.out, anchor);
        try self.out.appendSlice(a, "\">");
        try inline_html.render(a, &self.out, content, self.options);
        try self.out.print(a, "</h{d}>\n", .{level});
    }

    /// An anchor as GitHub makes it: lowercase, punctuation dropped,
    /// spaces as hyphens, and `-1`, `-2` after the first of a name
    fn anchorOf(self: *Document, text: []const u8) Error![]const u8 {
        const a = self.arena;
        var slug: std.ArrayList(u8) = .empty;
        var in_code = false;
        for (text) |c| {
            if (c == '`') {
                in_code = !in_code;
                continue;
            }
            if (std.ascii.isAlphanumeric(c)) {
                try slug.append(a, std.ascii.toLower(c));
            } else if (c == ' ' or c == '-') {
                try slug.append(a, '-');
            } else if (c == '_' or c >= 0x80) {
                try slug.append(a, c);
            }
        }
        const entry = try self.anchors.getOrPut(a, slug.items);
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
            return slug.items;
        }
        entry.value_ptr.* += 1;
        return a.print("{s}-{d}", .{ slug.items, entry.value_ptr.* });
    }

    fn list(self: *Document, b: markdown.Block) Error!void {
        const a = self.arena;
        const first = std.mem.trimStart(u8, b.text, " \t");
        const ordered = first.len > 0 and std.ascii.isDigit(first[0]);
        if (ordered) {
            var n: usize = 0;
            while (n < first.len and std.ascii.isDigit(first[n])) n += 1;
            const start = std.fmt.parseInt(usize, first[0..n], 10) catch 1;
            if (start == 1) try self.out.appendSlice(a, "<ol>\n") else try self.out.print(a, "<ol start=\"{d}\">\n", .{start});
        } else try self.out.appendSlice(a, "<ul>\n");
        const entries = try markdown.list.entries(a, b);
        // a list with a blank line between entries is loose: its text is in paragraphs
        const loose = std.mem.find(u8, std.mem.trimEnd(u8, b.text, "\r\n \t"), "\n\n") != null or std.mem.find(u8, b.text, "\r\n\r\n") != null;
        for (entries) |e| {
            try self.out.appendSlice(a, "<li>");
            const inner = try markdown.scan(a, e.text);
            if (!loose and inner.len >= 1 and inner[0].kind == .paragraph) {
                try inline_html.render(a, &self.out, std.mem.trim(u8, inner[0].text, " \t\r\n"), self.options);
                if (inner.len > 1) {
                    try self.out.append(a, '\n');
                    for (inner[1..]) |rest| try self.block(rest);
                }
            } else {
                try self.out.append(a, '\n');
                for (inner) |rest| try self.block(rest);
            }
            try self.out.appendSlice(a, "</li>\n");
        }
        try self.out.appendSlice(a, if (ordered) "</ol>\n" else "</ul>\n");
    }

    fn code(self: *Document, text: []const u8) Error!void {
        const a = self.arena;
        var lines: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| try lines.append(a, std.mem.trimEnd(u8, line, "\r"));
        const first = std.mem.trimStart(u8, lines.items[0], " ");
        var body: []const []const u8 = lines.items;
        var language: []const u8 = "";
        var strip: usize = 4;
        if (first.len >= 3 and (std.mem.startsWith(u8, first, "```") or std.mem.startsWith(u8, first, "~~~"))) {
            const fence = first[0];
            var n: usize = 0;
            while (n < first.len and first[n] == fence) n += 1;
            const info = std.mem.trim(u8, first[n..], " \t");
            language = if (std.mem.findScalar(u8, info, ' ')) |space| info[0..space] else info;
            strip = lines.items[0].len - first.len;
            body = lines.items[1..];
            if (body.len > 0) {
                const last = std.mem.trim(u8, body[body.len - 1], " \t");
                if (last.len >= n and last[0] == fence and std.mem.trim(u8, last, &.{fence}).len == 0) body = body[0 .. body.len - 1];
            }
        }
        // a diagram, which mermaid.js draws where the page loads it (render/layout.zig)
        if (std.mem.eql(u8, language, "mermaid")) {
            try self.out.appendSlice(a, "<pre class=\"mermaid\">");
            for (body) |line| {
                try inline_html.escape(a, &self.out, line);
                try self.out.append(a, '\n');
            }
            try self.out.appendSlice(a, "</pre>\n");
            return;
        }
        if (language.len > 0) {
            try self.out.appendSlice(a, "<pre><code class=\"language-");
            try inline_html.attribute(a, &self.out, language);
            try self.out.appendSlice(a, "\">");
        } else try self.out.appendSlice(a, "<pre><code>");
        for (body) |line| {
            var k: usize = 0;
            while (k < strip and k < line.len and line[k] == ' ') k += 1;
            try inline_html.escape(a, &self.out, line[k..]);
            try self.out.append(a, '\n');
        }
        try self.out.appendSlice(a, "</code></pre>\n");
    }

    fn table(self: *Document, text: []const u8) Error!void {
        const a = self.arena;
        var rows: std.ArrayList([]const []const u8) = .empty;
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len > 0) try rows.append(a, try cells(a, trimmed));
        }
        if (rows.items.len < 2 or !isDelimiterRow(rows.items[1])) {
            // no delimiter row: not a table, but its text
            try self.out.appendSlice(a, "<p>");
            try inline_html.render(a, &self.out, std.mem.trim(u8, text, " \t\r\n"), self.options);
            try self.out.appendSlice(a, "</p>\n");
            return;
        }
        const aligns = rows.items[1];
        try self.out.appendSlice(a, "<table>\n<thead>\n");
        try self.row(rows.items[0], aligns, "th");
        try self.out.appendSlice(a, "</thead>\n");
        if (rows.items.len > 2) {
            try self.out.appendSlice(a, "<tbody>\n");
            for (rows.items[2..]) |r| try self.row(r, aligns, "td");
            try self.out.appendSlice(a, "</tbody>\n");
        }
        try self.out.appendSlice(a, "</table>\n");
    }

    fn row(self: *Document, values: []const []const u8, aligns: []const []const u8, tag: []const u8) Error!void {
        const a = self.arena;
        try self.out.appendSlice(a, "<tr>");
        for (aligns, 0..) |delimiter, i| {
            const value = if (i < values.len) values[i] else "";
            const left = delimiter.len > 0 and delimiter[0] == ':';
            const right = delimiter.len > 0 and delimiter[delimiter.len - 1] == ':';
            const alignment: ?[]const u8 = if (left and right) "center" else if (right) "right" else if (left) "left" else null;
            if (alignment) |al| try self.out.print(a, "<{s} style=\"text-align: {s}\">", .{ tag, al }) else try self.out.print(a, "<{s}>", .{tag});
            try inline_html.render(a, &self.out, value, self.options);
            try self.out.print(a, "</{s}>", .{tag});
        }
        try self.out.appendSlice(a, "</tr>\n");
    }
};

/// The cells of a table row: split at the `|` that are not escaped and
/// not in a code span, without the outer ones
fn cells(arena: std.mem.Allocator, line: []const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var s = line;
    if (s.len > 0 and s[0] == '|') s = s[1..];
    if (s.len > 0 and s[s.len - 1] == '|' and (s.len < 2 or s[s.len - 2] != '\\')) s = s[0 .. s.len - 1];
    var start: usize = 0;
    var i: usize = 0;
    var in_code = false;
    var cell: std.ArrayList(u8) = .empty;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == '`') in_code = !in_code;
        if (c == '\\' and i + 1 < s.len and s[i + 1] == '|') {
            try cell.appendSlice(arena, s[start..i]);
            try cell.append(arena, '|');
            i += 1;
            start = i + 1;
            continue;
        }
        if (c == '|' and !in_code) {
            try cell.appendSlice(arena, s[start..i]);
            try out.append(arena, std.mem.trim(u8, cell.items, " \t"));
            cell = .empty;
            start = i + 1;
        }
    }
    try cell.appendSlice(arena, s[start..]);
    try out.append(arena, std.mem.trim(u8, cell.items, " \t"));
    return out.items;
}

fn isDelimiterRow(values: []const []const u8) bool {
    for (values) |v| {
        const t = std.mem.trim(u8, v, ":");
        if (t.len == 0) return false;
        for (t) |c| if (c != '-') return false;
    }
    return values.len > 0;
}

/// The elements whose HTML is a block of its own (CommonMark's list)
const block_tags = [_][]const u8{
    "address", "article", "aside", "blockquote", "body", "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "pre", "script", "section", "source", "style", "summary", "table", "tbody", "td", "textarea", "tfoot", "th", "thead", "title", "tr", "track", "ul",
};

/// Whether `text`, a block that starts with `<`, starts with a comment or
/// a tag of a block element
fn isBlockHtml(text: []const u8) bool {
    const s = std.mem.trimStart(u8, text, " ");
    if (std.mem.startsWith(u8, s, "<!")) return true;
    var name = s[1..];
    if (name.len > 0 and name[0] == '/') name = name[1..];
    var n: usize = 0;
    while (n < name.len and std.ascii.isAlphanumeric(name[n])) n += 1;
    for (block_tags) |tag| {
        if (std.ascii.eqlIgnoreCase(name[0..n], tag)) return true;
    }
    return false;
}

/// The text of a block quote without its `>` marks
fn unquote(arena: std.mem.Allocator, text: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (it.next()) |line| {
        if (!first) try out.append(arena, '\n');
        first = false;
        var s = std.mem.trimStart(u8, line, " ");
        if (s.len > 0 and s[0] == '>') {
            s = s[1..];
            if (s.len > 0 and s[0] == ' ') s = s[1..];
        }
        try out.appendSlice(arena, s);
    }
    return out.items;
}

test {
    _ = inline_html;
    _ = @import("_test/blocks.zig");
}
