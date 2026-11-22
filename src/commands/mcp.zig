//! `skein mcp`: the Model Context Protocol server, on standard input and
//! output, one message a line.

const std = @import("std");
const Io = std.Io;

const Server = @import("../mcp/Server.zig");
const stdio = @import("../stdio.zig");

/// Serves until the client closes the input
pub fn serve(io: Io, gpa: std.mem.Allocator, version: []const u8, root: []const u8) !u8 {
    const in_buf = try gpa.alloc(u8, 1 << 20);
    defer gpa.free(in_buf);
    var reader = stdio.stdin().readerStreaming(io, in_buf);
    var out_buf: [64 * 1024]u8 = undefined;
    var writer = stdio.stdout().writerStreaming(io, &out_buf);
    var server: Server = .{ .io = io, .out = &writer.interface, .version = version, .root = root };

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    while (true) {
        _ = arena.reset(.retain_capacity);
        const line = (reader.interface.takeDelimiter('\n') catch |e| {
            std.debug.print("skein mcp: reading a message: {t}\n", .{e});
            return 1;
        }) orelse break;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        // the line is in the reader's buffer, which the next read reuses
        try server.handle(arena.allocator(), try arena.allocator().dupe(u8, trimmed));
    }
    return 0;
}

test {
    _ = Server;
}
