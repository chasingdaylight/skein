//! The inline Markdown of a block, as HTML: code spans, emphasis, strong,
//! strikethrough, links, images, autolinks, raw inline HTML, backslash
//! escapes and hard line breaks. Text is escaped; entities such as
//! `&copy;` are kept.

const std = @import("std");

pub const Error = std.mem.Allocator.Error;

pub const Options = struct {
    /// a relative link to `x.md` becomes one to `x.html`, its anchor kept
    md_links_to_html: bool = false,
};

const Renderer = struct {
    arena: std.mem.Allocator,
    out: *std.ArrayList(u8),
    options: Options,

    fn text(self: Renderer, s: []const u8) Error!void {
        try escape(self.arena, self.out, s);
    }
};

/// Appends `source`, the inline text of one block, as HTML
pub fn render(arena: std.mem.Allocator, out: *std.ArrayList(u8), source: []const u8, options: Options) Error!void {
    const r: Renderer = .{ .arena = arena, .out = out, .options = options };
    try span(r, source);
}

/// What can be escaped with a backslash
fn isPunct(c: u8) bool {
    return std.mem.findScalar(u8, "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", c) != null;
}

fn span(r: Renderer, s: []const u8) Error!void {
    var i: usize = 0;
    var plain: usize = 0;
    while (i < s.len) {
        const c = s[i];
        const taken: ?usize = switch (c) {
            '\\' => blk: {
                if (i + 1 < s.len and isPunct(s[i + 1])) {
                    try r.text(s[plain..i]);
                    try r.text(s[i + 1 .. i + 2]);
                    break :blk i + 2;
                }
                if (i + 1 < s.len and s[i + 1] == '\n') {
                    try r.text(s[plain..i]);
                    try r.out.appendSlice(r.arena, "<br>\n");
                    break :blk i + 2;
                }
                break :blk null;
            },
            '`' => try codeSpan(r, s, i, plain),
            '*', '_', '~' => try emphasis(r, s, i, plain),
            '!' => if (i + 1 < s.len and s[i + 1] == '[') try link(r, s, i + 1, plain, true) else null,
            '[' => try link(r, s, i, plain, false),
            '<' => try angle(r, s, i, plain),
            '\n' => blk: {
                // two spaces before a line end: a hard break
                const before = s[plain..i];
                const trimmed = std.mem.trimEnd(u8, before, " ");
                if (before.len - trimmed.len >= 2) {
                    try r.text(trimmed);
                    try r.out.appendSlice(r.arena, "<br>\n");
                    break :blk i + 1;
                }
                break :blk null;
            },
            'h' => try bareUrl(r, s, i, plain),
            else => null,
        };
        if (taken) |next| {
            i = next;
            plain = next;
        } else i += 1;
    }
    try r.text(s[plain..]);
}

/// A code span at `i`: what is between a run of backticks and the next
/// run as long. Null when nothing closes it.
fn codeSpan(r: Renderer, s: []const u8, i: usize, plain: usize) Error!?usize {
    var n: usize = 0;
    while (i + n < s.len and s[i + n] == '`') n += 1;
    var j = i + n;
    while (j < s.len) {
        if (s[j] != '`') {
            j += 1;
            continue;
        }
        var m: usize = 0;
        while (j + m < s.len and s[j + m] == '`') m += 1;
        if (m == n) {
            try r.text(s[plain..i]);
            var inner = s[i + n .. j];
            // one space on each side is taken off, when both are there
            if (inner.len >= 2 and inner[0] == ' ' and inner[inner.len - 1] == ' ' and std.mem.trim(u8, inner, " ").len > 0) inner = inner[1 .. inner.len - 1];
            try r.out.appendSlice(r.arena, "<code>");
            const flat = try r.arena.dupe(u8, inner);
            std.mem.replaceScalar(u8, flat, '\n', ' ');
            try r.text(flat);
            try r.out.appendSlice(r.arena, "</code>");
            return j + m;
        }
        j += m;
    }
    return null;
}

/// Emphasis, strong or strikethrough opened by the delimiter at `i`.
/// Null when it opens nothing: not followed by text, inside a word for
/// `_`, or not closed.
fn emphasis(r: Renderer, s: []const u8, i: usize, plain: usize) Error!?usize {
    const c = s[i];
    var n: usize = 0;
    while (i + n < s.len and s[i + n] == c) n += 1;
    if (c == '~' and n != 2) return null;
    const size: usize = if (c == '~') 2 else @min(n, 2);
    const open_end = i + size;
    if (open_end >= s.len or std.ascii.isWhitespace(s[open_end])) return null;
    if (c == '_' and i > 0 and std.ascii.isAlphanumeric(s[i - 1])) return null;
    const delim = s[i..open_end];
    // the closing run: the same delimiter, after text, not before more of it
    var j = open_end + 1;
    while (j + size <= s.len) : (j += 1) {
        if (s[j] == '`') {
            // a code span is skipped whole
            var m: usize = 0;
            while (j + m < s.len and s[j + m] == '`') m += 1;
            const close = std.mem.findPos(u8, s, j + m, s[j .. j + m]) orelse break;
            j = close + m - 1;
            continue;
        }
        if (!std.mem.eql(u8, s[j .. j + size], delim)) continue;
        if (std.ascii.isWhitespace(s[j - 1])) continue;
        if (j + size < s.len and s[j + size] == c) {
            if (size == 2 or s.len < j + 2) continue;
            // `*a **b***`: let the inner pair close first
            j += 1;
            continue;
        }
        if (c == '_' and j + size < s.len and std.ascii.isAlphanumeric(s[j + size])) continue;
        try r.text(s[plain..i]);
        const tag = if (c == '~') "del" else if (size == 2) "strong" else "em";
        try r.out.print(r.arena, "<{s}>", .{tag});
        try span(r, s[open_end..j]);
        try r.out.print(r.arena, "</{s}>", .{tag});
        return j + size;
    }
    return null;
}

/// A link `[text](url "title")` or, with `image`, an image
/// `![alt](url)`, whose `[` is at `i`
fn link(r: Renderer, s: []const u8, i: usize, plain: usize, image: bool) Error!?usize {
    // the matching bracket, over nested ones and code spans
    var depth: usize = 0;
    var j = i;
    const close = while (j < s.len) : (j += 1) {
        switch (s[j]) {
            '\\' => j += 1,
            '`' => {
                var m: usize = 0;
                while (j + m < s.len and s[j + m] == '`') m += 1;
                if (std.mem.findPos(u8, s, j + m, s[j .. j + m])) |end| j = end + m - 1;
            },
            '[' => depth += 1,
            ']' => {
                depth -= 1;
                if (depth == 0) break j;
            },
            else => {},
        }
    } else return null;
    if (close + 1 >= s.len or s[close + 1] != '(') return null;
    const end = std.mem.findScalarPos(u8, s, close + 2, ')') orelse return null;
    const dest = std.mem.trim(u8, s[close + 2 .. end], " ");
    var url = dest;
    var title: ?[]const u8 = null;
    if (std.mem.findScalar(u8, dest, ' ')) |space| {
        const rest = std.mem.trim(u8, dest[space..], " ");
        if (rest.len >= 2 and (rest[0] == '"' or rest[0] == '\'') and rest[rest.len - 1] == rest[0]) {
            url = dest[0..space];
            title = rest[1 .. rest.len - 1];
        } else return null;
    }
    if (url.len >= 2 and url[0] == '<' and url[url.len - 1] == '>') url = url[1 .. url.len - 1];
    try r.text(s[plain..if (image) i - 1 else i]);
    const href = try rewrite(r, url);
    if (image) {
        try r.out.appendSlice(r.arena, "<img src=\"");
        try attribute(r.arena, r.out, href);
        try r.out.appendSlice(r.arena, "\" alt=\"");
        try attribute(r.arena, r.out, try plainText(r.arena, s[i + 1 .. close]));
        try r.out.append(r.arena, '"');
        if (title) |t| {
            try r.out.appendSlice(r.arena, " title=\"");
            try attribute(r.arena, r.out, t);
            try r.out.append(r.arena, '"');
        }
        try r.out.appendSlice(r.arena, ">");
    } else {
        try r.out.appendSlice(r.arena, "<a href=\"");
        try attribute(r.arena, r.out, href);
        try r.out.append(r.arena, '"');
        if (title) |t| {
            try r.out.appendSlice(r.arena, " title=\"");
            try attribute(r.arena, r.out, t);
            try r.out.append(r.arena, '"');
        }
        try r.out.append(r.arena, '>');
        try span(r, s[i + 1 .. close]);
        try r.out.appendSlice(r.arena, "</a>");
    }
    return end + 1;
}

/// The URL of a link as the page needs it
fn rewrite(r: Renderer, url: []const u8) Error![]const u8 {
    if (!r.options.md_links_to_html or isAbsolute(url)) return url;
    const hash = std.mem.findScalar(u8, url, '#') orelse url.len;
    const path = url[0..hash];
    if (!std.ascii.endsWithIgnoreCase(path, ".md")) return url;
    return r.arena.print("{s}.html{s}", .{ path[0 .. path.len - 3], url[hash..] });
}

fn isAbsolute(url: []const u8) bool {
    if (std.mem.startsWith(u8, url, "//")) return true;
    const colon = std.mem.findScalar(u8, url, ':') orelse return false;
    for (url[0..colon]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '+' and c != '-' and c != '.') return false;
    }
    return colon > 0;
}

/// The text of inline Markdown without its markup, for an `alt`
fn plainText(arena: std.mem.Allocator, s: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| {
        if (std.mem.findScalar(u8, "*_`[]", c) == null) try out.append(arena, c);
    }
    return out.items;
}

/// `<https://...>` as a link, or raw inline HTML kept as it is
fn angle(r: Renderer, s: []const u8, i: usize, plain: usize) Error!?usize {
    const end = std.mem.findScalarPos(u8, s, i + 1, '>') orelse return null;
    const inner = s[i + 1 .. end];
    if (inner.len == 0 or std.mem.findAny(u8, inner, " \n<") != null and !isTag(inner)) return null;
    if (isAbsolute(inner) and std.mem.findAny(u8, inner, " \n<") == null) {
        try r.text(s[plain..i]);
        try r.out.appendSlice(r.arena, "<a href=\"");
        try attribute(r.arena, r.out, inner);
        try r.out.appendSlice(r.arena, "\">");
        try escape(r.arena, r.out, inner);
        try r.out.appendSlice(r.arena, "</a>");
        return end + 1;
    }
    if (!isTag(inner)) return null;
    try r.text(s[plain..i]);
    try r.out.appendSlice(r.arena, s[i .. end + 1]);
    return end + 1;
}

/// Whether `inner` (what is between `<` and `>`) is an HTML tag or comment
fn isTag(inner: []const u8) bool {
    if (std.mem.startsWith(u8, inner, "!--")) return std.mem.endsWith(u8, inner, "--");
    const name = if (inner[0] == '/') inner[1..] else inner;
    if (name.len == 0 or !std.ascii.isAlphabetic(name[0])) return false;
    var k: usize = 0;
    while (k < name.len and (std.ascii.isAlphanumeric(name[k]) or name[k] == '-')) k += 1;
    return k == name.len or name[k] == ' ' or name[k] == '/' or name[k] == '\n';
}

/// A bare `http://` or `https://` URL as a link, as GitHub shows it
fn bareUrl(r: Renderer, s: []const u8, i: usize, plain: usize) Error!?usize {
    const rest = s[i..];
    if (!std.mem.startsWith(u8, rest, "https://") and !std.mem.startsWith(u8, rest, "http://")) return null;
    if (i > 0 and (std.ascii.isAlphanumeric(s[i - 1]) or s[i - 1] == '"' or s[i - 1] == '=' or s[i - 1] == '/')) return null;
    var end = i;
    while (end < s.len and !std.ascii.isWhitespace(s[end]) and s[end] != '<') end += 1;
    // punctuation at the end belongs to the sentence
    while (end > i and std.mem.findScalar(u8, ".,:;!?'\")", s[end - 1]) != null) end -= 1;
    const url = s[i..end];
    if (std.mem.find(u8, url, "://").? + 3 >= url.len) return null;
    try r.text(s[plain..i]);
    try r.out.appendSlice(r.arena, "<a href=\"");
    try attribute(r.arena, r.out, url);
    try r.out.appendSlice(r.arena, "\">");
    try escape(r.arena, r.out, url);
    try r.out.appendSlice(r.arena, "</a>");
    return end;
}

/// Appends `s` as text: `&`, `<` and `>` escaped, entities kept
pub fn escape(arena: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) Error!void {
    try escapeAs(arena, out, s, false);
}

/// Appends `s` as the value of an attribute: also `"` escaped
pub fn attribute(arena: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) Error!void {
    try escapeAs(arena, out, s, true);
}

fn escapeAs(arena: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8, quotes: bool) Error!void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        switch (s[i]) {
            '&' => {
                if (isEntity(s[i..])) try out.append(arena, '&') else try out.appendSlice(arena, "&amp;");
            },
            '<' => try out.appendSlice(arena, "&lt;"),
            '>' => try out.appendSlice(arena, "&gt;"),
            '"' => if (quotes) try out.appendSlice(arena, "&quot;") else try out.append(arena, '"'),
            else => try out.append(arena, s[i]),
        }
    }
}

fn isEntity(s: []const u8) bool {
    var j: usize = 1;
    if (j < s.len and s[j] == '#') j += 1;
    const start = j;
    while (j < s.len and j < 33 and std.ascii.isAlphanumeric(s[j])) j += 1;
    return j > start and j < s.len and s[j] == ';';
}

const testing = std.testing;

fn expectInline(expected: []const u8, source: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(u8) = .empty;
    try render(arena.allocator(), &out, source, .{ .md_links_to_html = true });
    try testing.expectEqualStrings(expected, out.items);
}

// req: html.inline
test "emphasis, strong, strikethrough and code" {
    try expectInline("<em>a</em> <strong>b</strong> <del>c</del> <code>d</code>", "*a* **b** ~~c~~ `d`");
    try expectInline("<em>a</em> and <strong>b</strong>", "_a_ and __b__");
    try expectInline("<strong>bold <em>and</em> more</strong>", "**bold *and* more**");
    try expectInline("snake_case_name and 2 * 3 * 4", "snake_case_name and 2 * 3 * 4");
    try expectInline("<code>a `b` c</code> and <code>*not*</code>", "`` a `b` c `` and `*not*`");
    try expectInline("<strong>a <code>**</code> b</strong>", "**a `**` b**");
}

test "links and images" {
    try expectInline("<a href=\"https://x.org\" title=\"T\">the <em>site</em></a>", "[the *site*](https://x.org \"T\")");
    try expectInline("<a href=\"spec/lex.html#lex.token\">token</a>", "[token](spec/lex.md#lex.token)");
    try expectInline("<a href=\"https://x.org/a.md\">a</a>", "[a](https://x.org/a.md)");
    try expectInline("<img src=\"assets/logo.svg\" alt=\"The logo\">", "![The *logo*](assets/logo.svg)");
    try expectInline("[not a link] and [x]", "[not a link] and [x]");
    try expectInline("<a href=\"https://a.b/c\">https://a.b/c</a>.", "https://a.b/c.");
    try expectInline("<a href=\"https://a.b\">https://a.b</a>", "<https://a.b>");
}

test "escapes, entities, raw HTML and line breaks" {
    try expectInline("a &lt; b &amp; c &copy; &#169; \"q\"", "a < b & c &copy; &#169; \"q\"");
    try expectInline("*not* [x]", "\\*not\\* \\[x\\]");
    try expectInline("<a id=\"lex.token\"></a><strong>x</strong>", "<a id=\"lex.token\"></a>**x**");
    try expectInline("one<br>\ntwo<br>\nthree\nfour", "one  \ntwo\\\nthree\nfour");
    try expectInline("&lt;not a tag", "<not a tag");
}
