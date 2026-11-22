//! What the adapters share: asking a forge's own program (`gh`, `glab`)
//! for a request, and asking its API over HTTPS.

const std = @import("std");
const Io = std.Io;

const github = @import("github.zig");

/// How long a forge's program may take to answer
pub const idle_seconds = 30;

/// Runs `argv` (a forge's program, `argv[0]`); null when it is not installed
pub fn cli(io: Io, arena: std.mem.Allocator, argv: []const []const u8) !?github.Reply {
    const result = std.process.run(arena, io, .{
        .argv = argv,
        .stdout_limit = .limited(1 << 22),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(idle_seconds), .clock = .awake } },
    }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return null,
        error.Timeout => return .{ .unreachable_ = try arena.print("{s} did not answer in time", .{argv[0]}) },
        else => return .{ .unreachable_ = try arena.print("{s} could not be run ({t})", .{ argv[0], e }) },
    };
    if (result.term.success()) return .{ .body = result.stdout };
    if (std.mem.find(u8, result.stderr, "Not Found") != null or std.mem.find(u8, result.stdout, "Not Found") != null) return .missing;
    return .{ .unreachable_ = try arena.print("{s}: {s}", .{ argv[0], std.mem.trim(u8, result.stderr, " \r\n") }) };
}

/// Sends `json` with `method` (POST, PUT, PATCH) to `path` through a forge's
/// program (`gh`, `glab`), which holds the sign-in; `body_path` is a file skein
/// may write the request in. `hostname` is for a server other than the public
/// one, `headers` extra header arguments (`-H`, text).
pub fn send(io: Io, arena: std.mem.Allocator, program: []const u8, hostname: ?[]const u8, headers: []const []const u8, method: []const u8, path: []const u8, json: []const u8, body_path: []const u8) !github.Reply {
    if (Io.Dir.path.dirname(body_path)) |d| Io.Dir.cwd().createDirPath(io, d) catch {};
    Io.Dir.cwd().writeFile(io, .{ .sub_path = body_path, .data = json }) catch return .{ .unreachable_ = "the request could not be written" };
    defer Io.Dir.cwd().deleteFile(io, body_path) catch {};
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ program, "api", "--method", method, path, "--input", body_path });
    for (headers) |h| try argv.appendSlice(arena, &.{ "-H", h });
    if (hostname) |h| try argv.appendSlice(arena, &.{ "--hostname", h });
    return (try cli(io, arena, argv.items)) orelse .{ .unreachable_ = try arena.print("{s} is not installed: writing to the forge needs it, signed in", .{program}) };
}

/// GET `url` with `headers`; `host` and `name` are for the reasons
pub fn https(io: Io, arena: std.mem.Allocator, url: []const u8, headers: []const std.http.Header, host: []const u8, name: []const u8) !github.Reply {
    var client: std.http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();
    var body: Io.Writer.Allocating = .init(arena);
    const result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &body.writer,
        .privileged_headers = headers,
    }) catch |e| return .{ .unreachable_ = try arena.print("{s} could not be reached ({t})", .{ host, e }) };
    return switch (result.status) {
        .ok => .{ .body = body.written() },
        .not_found, .gone => .missing,
        else => .{ .unreachable_ = try arena.print("{s} answered {d}", .{ name, @backingInt(result.status) }) },
    };
}
