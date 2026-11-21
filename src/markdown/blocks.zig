//! Splits a Markdown file into its blocks: enough of Markdown to place
//! items, not a renderer. Works on lines, as the block structure does.

const std = @import("std");

const Marker = @import("Marker.zig");

pub const Block = struct {
    kind: Kind,
    /// 1-based, inclusive
    first_line: u32,
    last_line: u32,
    /// the block's lines, without the last line's end
    text: []const u8,

    pub const Kind = enum {
        /// TOML between `+++` lines at the top of the file (the text is
        /// what is between them)
        front_matter,
        /// YAML between `---` lines at the top of the file, as site
        /// generators and Doorstop write: not skein's, and passed over
        yaml_front_matter,
        /// what makes the next block an item (Marker.zig): the start of a
        /// line, up to the closing bracket
        marker,
        heading,
        paragraph,
        list,
        code,
        quote,
        table,
        html,
        thematic_break,
    };
};

const Line = struct {
    /// offsets into the source; `end` is before the line's end characters
    start: usize,
    end: usize,
};

/// The blocks of `source`, in order. A marker (Marker.zig) at the start of
/// a line is a block of its own: the text after it on its line, if any,
/// starts the next block, a paragraph.
pub fn scan(arena: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]const Block {
    var s: Scanner = .{ .arena = arena, .src = source };
    try s.splitLines();
    try s.run();
    return s.blocks.items;
}

const Scanner = struct {
    arena: std.mem.Allocator,
    src: []const u8,
    lines: std.ArrayList(Line) = .empty,
    blocks: std.ArrayList(Block) = .empty,

    fn splitLines(self: *Scanner) !void {
        var start: usize = 0;
        while (start < self.src.len) {
            const nl = std.mem.findScalarPos(u8, self.src, start, '\n') orelse self.src.len;
            var end = nl;
            if (end > start and self.src[end - 1] == '\r') end -= 1;
            try self.lines.append(self.arena, .{ .start = start, .end = end });
            start = nl + 1;
        }
    }

    fn text(self: *const Scanner, i: usize) []const u8 {
        const l = self.lines.items[i];
        return self.src[l.start..l.end];
    }

    fn blank(self: *const Scanner, i: usize) bool {
        return std.mem.trim(u8, self.text(i), " \t").len == 0;
    }

    /// Adds the block of lines `first` to `last` (inclusive)
    fn add(self: *Scanner, kind: Block.Kind, first: usize, last: usize) !void {
        const items = self.lines.items;
        try self.blocks.append(self.arena, .{
            .kind = kind,
            .first_line = @intCast(first + 1),
            .last_line = @intCast(last + 1),
            .text = self.src[items[first].start..items[last].end],
        });
    }

    fn run(self: *Scanner) !void {
        const n = self.lines.items.len;
        var i: usize = self.frontMatter() catch |e| return e;
        while (i < n) {
            if (self.blank(i)) {
                i += 1;
                continue;
            }
            const kind = self.kindAt(i);
            if (kind == .marker) {
                i = try self.marker(i);
                continue;
            }
            const last = switch (kind) {
                .marker => unreachable,
                .heading, .thematic_break => i,
                .code => self.codeEnd(i),
                .html => self.htmlEnd(i),
                .list => self.listEnd(i),
                else => self.plainEnd(i, kind),
            };
            try self.add(kind, i, last);
            i = last + 1;
        }
    }

    /// Adds the marker that line `i` starts with, and the paragraph that
    /// the rest of the line starts, if there is text there; the first line
    /// after them
    fn marker(self: *Scanner, i: usize) !usize {
        const l = self.lines.items[i];
        const line = self.src[l.start..l.end];
        const len = Marker.extent(line);
        try self.blocks.append(self.arena, .{
            .kind = .marker,
            .first_line = @intCast(i + 1),
            .last_line = @intCast(i + 1),
            .text = line[0..len],
        });
        const rest = std.mem.trimStart(u8, line[len..], " \t");
        if (rest.len == 0) return i + 1;
        const last = self.plainEnd(i, .paragraph);
        try self.blocks.append(self.arena, .{
            .kind = .paragraph,
            .first_line = @intCast(i + 1),
            .last_line = @intCast(last + 1),
            .text = self.src[l.end - rest.len .. self.lines.items[last].end],
        });
        return last + 1;
    }

    /// Adds the front matter, if the file starts with it; the first line
    /// after it
    fn frontMatter(self: *Scanner) !usize {
        const n = self.lines.items.len;
        if (n > 0 and isYamlFence(self.text(0))) {
            var k: usize = 1;
            while (k < n) : (k += 1) {
                if (!isYamlFence(self.text(k))) continue;
                try self.add(.yaml_front_matter, 0, k);
                return k + 1;
            }
            return 0;
        }
        if (n == 0 or !isFrontMatterFence(self.text(0))) return 0;
        var j: usize = 1;
        while (j < n) : (j += 1) {
            if (!isFrontMatterFence(self.text(j))) continue;
            const items = self.lines.items;
            const from = items[0].end;
            try self.blocks.append(self.arena, .{
                .kind = .front_matter,
                .first_line = 1,
                .last_line = @intCast(j + 1),
                // from the first line's end, so that the text's lines
                // count as the file's do
                .text = if (j == 1) self.src[from..from] else self.src[from..items[j - 1].end],
            });
            return j + 1;
        }
        // not closed: left as text, for whoever expects it to say so
        return 0;
    }

    /// What kind of block starts at line `i` (which is not blank)
    fn kindAt(self: *const Scanner, i: usize) Block.Kind {
        const line = self.text(i);
        const indent = indentOf(line);
        if (indent >= 4) return .code;
        const s = line[indent..];
        if (isFence(s) != null) return .code;
        if (indent == 0 and Marker.startsOne(line)) return .marker;
        if (isHeading(s)) return .heading;
        if (isThematicBreak(s)) return .thematic_break;
        if (s[0] == '>') return .quote;
        if (isListStart(s)) return .list;
        if (s[0] == '|') return .table;
        if (s[0] == '<' and s.len > 1 and (std.ascii.isAlphabetic(s[1]) or s[1] == '/' or s[1] == '!')) return .html;
        return .paragraph;
    }

    /// The last line of a paragraph, quote or table that starts at `i`:
    /// before a blank line or a line that starts another kind of block
    fn plainEnd(self: *const Scanner, i: usize, kind: Block.Kind) usize {
        var j = i + 1;
        while (j < self.lines.items.len and !self.blank(j)) : (j += 1) {
            const next = self.kindAt(j);
            if (next == kind and kind != .paragraph) continue;
            switch (next) {
                // these go on with the paragraph: Markdown's lazy lines
                .paragraph, .table, .html => {},
                // an indented line after text is more of the text
                .code => if (isFence(std.mem.trimStart(u8, self.text(j), " ")) != null) break,
                // only "1." and bullets interrupt a paragraph
                .list => if (kind != .paragraph or interruptsParagraph(std.mem.trimStart(u8, self.text(j), " "))) break,
                else => break,
            }
        }
        return j - 1;
    }

    /// The last line of the code block that starts at `i`
    fn codeEnd(self: *const Scanner, i: usize) usize {
        const n = self.lines.items.len;
        const first = self.text(i);
        if (isFence(std.mem.trimStart(u8, first, " "))) |open| {
            var j = i + 1;
            while (j < n) : (j += 1) {
                const s = std.mem.trim(u8, self.text(j), " \t");
                const close = isFence(s) orelse continue;
                // a closing fence has no text after it
                if (close.char == open.char and close.len >= open.len and close.len == s.len) return j;
            }
            return n - 1;
        }
        // indented: goes on over blank lines while more indented lines follow
        var last = i;
        var j = i + 1;
        while (j < n) : (j += 1) {
            if (self.blank(j)) continue;
            if (indentOf(self.text(j)) < 4) break;
            last = j;
        }
        return last;
    }

    /// The last line of the HTML block that starts at `i`: a comment ends
    /// where it closes, anything else at a blank line
    fn htmlEnd(self: *const Scanner, i: usize) usize {
        const n = self.lines.items.len;
        var j = i;
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, self.text(i), " "), "<!--")) {
            while (j < n) : (j += 1) {
                if (std.mem.find(u8, self.text(j), "-->") != null) return j;
            }
            return n - 1;
        }
        while (j + 1 < n and !self.blank(j + 1)) j += 1;
        return j;
    }

    /// The last line of the list that starts at `i`. A list goes on over
    /// a blank line when what follows is indented or another list item.
    fn listEnd(self: *const Scanner, i: usize) usize {
        const n = self.lines.items.len;
        var last = i;
        var j = i + 1;
        while (j < n) : (j += 1) {
            const line = self.text(j);
            if (self.blank(j)) {
                var k = j + 1;
                while (k < n and self.blank(k)) k += 1;
                if (k == n) break;
                const next = self.text(k);
                if (indentOf(next) < 2 and !isListStart(next)) break;
                continue;
            }
            const indent = indentOf(line);
            if (indent == 0 and (Marker.startsOne(line) or isHeading(line) or isThematicBreak(line))) break;
            last = j;
        }
        return last;
    }
};

fn isYamlFence(line: []const u8) bool {
    return std.mem.eql(u8, std.mem.trimEnd(u8, line, " \t"), "---");
}

fn isFrontMatterFence(line: []const u8) bool {
    return std.mem.eql(u8, std.mem.trimEnd(u8, line, " \t"), "+++");
}

pub fn indentOf(line: []const u8) usize {
    var n: usize = 0;
    for (line) |c| switch (c) {
        ' ' => n += 1,
        '\t' => n += 4,
        else => break,
    };
    return n;
}

const Fence = struct { char: u8, len: usize };

/// The fence that `s` (without its indent) starts with: three or more
/// backticks or tildes
fn isFence(s: []const u8) ?Fence {
    if (s.len < 3 or (s[0] != '`' and s[0] != '~')) return null;
    var n: usize = 0;
    while (n < s.len and s[n] == s[0]) n += 1;
    if (n < 3) return null;
    // an opening fence of backticks has none in what follows
    if (s[0] == '`' and std.mem.findScalar(u8, s[n..], '`') != null) return null;
    return .{ .char = s[0], .len = n };
}

fn isHeading(s: []const u8) bool {
    var n: usize = 0;
    while (n < s.len and s[n] == '#') n += 1;
    return n >= 1 and n <= 6 and (n == s.len or s[n] == ' ' or s[n] == '\t');
}

/// Three or more of `-`, `*` or `_`, with spaces at most
fn isThematicBreak(s: []const u8) bool {
    if (s.len == 0 or (s[0] != '-' and s[0] != '*' and s[0] != '_')) return false;
    var n: usize = 0;
    for (s) |c| {
        if (c == s[0]) n += 1 else if (c != ' ' and c != '\t') return false;
    }
    return n >= 3;
}

/// `- `, `* `, `+ `, `1. ` or `1) `
pub fn isListStart(line: []const u8) bool {
    const s = std.mem.trimStart(u8, line, " ");
    if (s.len == 0) return false;
    if (s[0] == '-' or s[0] == '*' or s[0] == '+') return s.len == 1 or s[1] == ' ' or s[1] == '\t';
    var n: usize = 0;
    while (n < s.len and std.ascii.isDigit(s[n])) n += 1;
    if (n == 0 or n > 9 or n == s.len or (s[n] != '.' and s[n] != ')')) return false;
    return n + 1 == s.len or s[n + 1] == ' ' or s[n + 1] == '\t';
}

/// Whether the list item `s` starts may cut a paragraph short: a bullet
/// with text, or number one
fn interruptsParagraph(s: []const u8) bool {
    if (s[0] == '-' or s[0] == '*' or s[0] == '+') return s.len > 2;
    return std.mem.startsWith(u8, s, "1.") or std.mem.startsWith(u8, s, "1)");
}

test {
    _ = @import("_test/blocks.zig");
    _ = @import("_test/yaml_front_matter.zig");
}
