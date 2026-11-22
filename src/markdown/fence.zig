//! The opening line of a fenced code block, which may carry a marker
//! after the language, so that the block is an item (a tested example):
//!
//!     ```cesium %example[lex.comment.open rejects shows=lex.comment]
//!
//! The language stays the first word, so renderers still highlight the
//! code, and they ignore the rest of the line.

const std = @import("std");

pub const Info = struct {
    /// the first word after the fence; empty when there is none
    language: []const u8,
    /// `%type[...]` or a bare `%type`; null when the line has no marker
    marker: ?[]const u8,
    /// the lines between the fences, each ending with a line end
    code: []const u8,
};

/// What the fenced code block `text` says; null when it is not fenced
pub fn read(text: []const u8) ?Info {
    const trimmed = std.mem.trimStart(u8, text, " ");
    if (trimmed.len < 3) return null;
    const fence_char = trimmed[0];
    if (fence_char != '`' and fence_char != '~') return null;
    var n: usize = 0;
    while (n < trimmed.len and trimmed[n] == fence_char) n += 1;
    if (n < 3) return null;
    const line_end = std.mem.findScalar(u8, trimmed, '\n') orelse trimmed.len;
    const info = std.mem.trim(u8, trimmed[n..line_end], " \t\r");
    const space = std.mem.findAny(u8, info, " \t") orelse info.len;
    const language = info[0..space];
    const rest = std.mem.trim(u8, info[space..], " \t");
    const marker: ?[]const u8 = if (std.mem.startsWith(u8, language, "%")) language else if (std.mem.startsWith(u8, rest, "%")) rest else null;

    // the code: up to the closing fence, or to the end
    const body_start = @min(line_end + 1, trimmed.len);
    var code_end = trimmed.len;
    var at = body_start;
    while (at < trimmed.len) {
        const next = std.mem.findScalarPos(u8, trimmed, at, '\n') orelse trimmed.len;
        const line = std.mem.trim(u8, trimmed[at..next], " \t\r");
        if (line.len >= n and std.mem.allEqual(u8, line, fence_char)) {
            code_end = at;
            break;
        }
        at = next + 1;
    }
    return .{ .language = if (marker != null and marker.?.ptr == language.ptr) "" else language, .marker = marker, .code = trimmed[body_start..@max(body_start, code_end)] };
}

/// The item type a bare marker (`%example`) names; null when `marker`
/// has brackets
pub fn bareType(marker: []const u8) ?[]const u8 {
    if (std.mem.findScalar(u8, marker, '[') != null) return null;
    return std.mem.trim(u8, marker[1..], " ");
}

// req: examples.marked
test "the language, the marker and the code of a fence" {
    const a = read("```cesium %example[lex.x rejects]\n/* open\n```").?;
    try std.testing.expectEqualStrings("cesium", a.language);
    try std.testing.expectEqualStrings("%example[lex.x rejects]", a.marker.?);
    try std.testing.expectEqualStrings("/* open\n", a.code);
    const b = read("~~~~zig\nconst x = 1;\n~~~~\n").?;
    try std.testing.expectEqualStrings("zig", b.language);
    try std.testing.expectEqual(null, b.marker);
    const c = read("``` %example\nx\n```").?;
    try std.testing.expectEqualStrings("", c.language);
    try std.testing.expectEqualStrings("example", bareType(c.marker.?).?);
    try std.testing.expectEqual(null, read("plain text"));
}
