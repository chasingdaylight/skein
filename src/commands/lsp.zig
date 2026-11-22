//! `skein lsp`: the language server, on standard input and output.

const std = @import("std");
const Io = std.Io;

const Server = @import("../lsp/Server.zig");
const jsonrpc = @import("../lsp/jsonrpc.zig");
const stdio = @import("../stdio.zig");

/// Serves until the editor says `exit` or closes the input. The exit
/// code: 0 after a `shutdown`, 1 otherwise.
pub fn serve(io: Io, gpa: std.mem.Allocator, version: []const u8) !u8 {
    var in_buf: [64 * 1024]u8 = undefined;
    var reader = stdio.stdin().readerStreaming(io, &in_buf);
    var out_buf: [64 * 1024]u8 = undefined;
    var writer = stdio.stdout().writerStreaming(io, &out_buf);
    var server: Server = .{ .gpa = gpa, .io = io, .out = &writer.interface, .version = version };
    defer server.deinit();

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    while (server.running) {
        _ = arena.reset(.retain_capacity);
        const body = (jsonrpc.readMessage(gpa, &reader.interface) catch |e| {
            std.debug.print("skein lsp: reading a message: {t}\n", .{e});
            return 1;
        }) orelse break;
        defer gpa.free(body);
        try server.handle(arena.allocator(), body);
    }
    return server.exitCode();
}

test {
    _ = Server;
}
