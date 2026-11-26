//! Text written into XML: the characters markup gives a meaning to, as
//! entities.

const std = @import("std");

/// `text` with `&`, `<`, `>`, `"` and `'` as entities, for element text
/// and attribute values alike
pub fn escape(w: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    var start: usize = 0;
    for (text, 0..) |c, i| {
        const entity: []const u8 = switch (c) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => "&quot;",
            '\'' => "&apos;",
            else => continue,
        };
        try w.writeAll(text[start..i]);
        try w.writeAll(entity);
        start = i + 1;
    }
    try w.writeAll(text[start..]);
}
