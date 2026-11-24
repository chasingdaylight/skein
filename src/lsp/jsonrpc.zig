//! JSON-RPC message framing over byte streams, as LSP frames it: headers,
//! a blank line, then `Content-Length` bytes of JSON (after zfls's
//! src/jsonrpc.zig).
//!
//! From cesiumlang/vscode-cesium, server/jsonrpc.zig (MIT), commit 047aa50.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const ReadError = error{ MissingContentLength, BadContentLength, BadHeader, TruncatedMessage, ReadFailed, OutOfMemory };

/// Reads one message body, owned by the caller; null at the end of the
/// stream before a message begins
pub fn readMessage(a: Allocator, r: *Io.Reader) ReadError!?[]u8 {
    var content_length: ?usize = null;
    var first = true;
    while (true) {
        const line = r.takeDelimiterInclusive('\n') catch |e| switch (e) {
            error.EndOfStream => return if (first) null else error.TruncatedMessage,
            error.StreamTooLong => return error.BadHeader,
            error.ReadFailed => return error.ReadFailed,
        };
        first = false;
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) break;
        const colon = std.mem.findScalar(u8, trimmed, ':') orelse return error.BadHeader;
        const key = std.mem.trim(u8, trimmed[0..colon], " \t");
        if (std.ascii.eqlIgnoreCase(key, "Content-Length")) {
            const value = std.mem.trim(u8, trimmed[colon + 1 ..], " \t");
            content_length = std.fmt.parseInt(usize, value, 10) catch return error.BadContentLength;
        }
    }
    const len = content_length orelse return error.MissingContentLength;
    return r.readAllocAll(a, len) catch |e| switch (e) {
        error.EndOfStream => error.TruncatedMessage,
        error.OutOfMemory => error.OutOfMemory,
        error.ReadFailed => error.ReadFailed,
    };
}

/// Writes `body` with its header, and flushes
pub fn writeMessage(w: *Io.Writer, body: []const u8) Io.Writer.Error!void {
    try w.print("Content-Length: {d}\r\n\r\n", .{body.len});
    try w.writeAll(body);
    try w.flush();
}

const testing = std.testing;

test readMessage {
    const a = testing.allocator;
    var r: Io.Reader = .fixed("Content-Length: 2\r\nContent-Type: x\r\n\r\n{}content-length:3\r\n\r\n[1]");
    const m1 = (try readMessage(a, &r)).?;
    defer a.free(m1);
    try testing.expectEqualStrings("{}", m1);
    const m2 = (try readMessage(a, &r)).?;
    defer a.free(m2);
    try testing.expectEqualStrings("[1]", m2);
    try testing.expect((try readMessage(a, &r)) == null);
}

test "readMessage: bad input" {
    const a = testing.allocator;
    var no_length: Io.Reader = .fixed("Content-Type: x\r\n\r\n{}");
    try testing.expectError(error.MissingContentLength, readMessage(a, &no_length));
    var bad_length: Io.Reader = .fixed("Content-Length: x\r\n\r\n{}");
    try testing.expectError(error.BadContentLength, readMessage(a, &bad_length));
    var no_colon: Io.Reader = .fixed("Content-Length 2\r\n\r\n{}");
    try testing.expectError(error.BadHeader, readMessage(a, &no_colon));
    var short: Io.Reader = .fixed("Content-Length: 5\r\n\r\n{}");
    try testing.expectError(error.TruncatedMessage, readMessage(a, &short));
    var no_body: Io.Reader = .fixed("Content-Length: 5\r\n");
    try testing.expectError(error.TruncatedMessage, readMessage(a, &no_body));
}

test writeMessage {
    var out: Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeMessage(&out.writer, "{\"a\":1}");
    try testing.expectEqualStrings("Content-Length: 7\r\n\r\n{\"a\":1}", out.written());
}
