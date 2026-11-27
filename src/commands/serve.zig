//! `skein serve`: the site of the project, served on this computer
//! (localhost only: it has no sign-in), rendered from the checkout as the
//! files change, with pages that load again when they do (serve/).

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const Site = @import("../serve/Site.zig");
const answer = @import("../serve/answer.zig");
const changes = @import("../serve/changes.zig");
const edit_api = @import("../serve/edit_api.zig");
const guard = @import("../serve/guard.zig");
const cli = @import("../cli.zig");
const stdio = @import("../stdio.zig");

/// How many requests are answered at once: a browser opens several
/// connections, some of which send nothing for a while
const workers = 8;

/// Serves until the process is stopped; the exit code when it cannot start
pub fn serve(io: Io, gpa: std.mem.Allocator, options: cli.Serve) !u8 {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const root_path = (Project.findRoot(io, a, options.common.root) catch null) orelse {
        try say(io, try a.print("skein: no project here: no '{s}' directory in '{s}' or above it\n", .{ Project.dir_name, options.common.root }));
        return 2;
    };
    var root = try Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true });
    defer root.close(io);
    var s: Site = .init(gpa, io, options, root);
    defer s.deinit();
    s.start_branch = try changes.current(io, a, root);
    try s.refresh();

    const address = try Io.net.IpAddress.parse("127.0.0.1", options.port);
    var server = address.listen(io, .{ .reuse_address = true }) catch |e| {
        try say(io, try a.print("skein: cannot serve on 127.0.0.1:{d} ({t}); give another --port\n", .{ options.port, e }));
        return 2;
    };
    defer server.deinit(io);
    try say(io, try a.print("skein: serving {s} at http://127.0.0.1:{d}/ until stopped (Ctrl+C){s}\n", .{
        if (s.name.len > 0) s.name else root_path, options.port, if (s.failed != null) "; it cannot be rendered yet: see the page" else "",
    }));

    var group: Io.Group = .init;
    defer group.cancel(io);
    var started: usize = 0;
    while (started < workers) : (started += 1) group.concurrent(io, work, .{ io, gpa, &server, &s }) catch break;
    // with no concurrency to be had, one at a time here
    if (started == 0) try work(io, gpa, &server, &s);
    try group.await(io);
    return 0;
}

fn work(io: Io, gpa: std.mem.Allocator, server: *Io.net.Server, s: *Site) Io.Cancelable!void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    while (true) {
        _ = arena.reset(.retain_capacity);
        const stream = server.accept(io) catch |e| switch (e) {
            error.Canceled => return error.Canceled,
            else => continue,
        };
        defer stream.close(io);
        connection(io, arena.allocator(), stream, s) catch |e| switch (e) {
            error.Canceled => return error.Canceled,
            else => {},
        };
    }
}

/// Answers one request on `stream`, and closes it
fn connection(io: Io, arena: std.mem.Allocator, stream: Io.net.Stream, s: *Site) !void {
    var in_buf: [16 * 1024]u8 = undefined;
    var reader = stream.reader(io, &in_buf);
    var out_buf: [16 * 1024]u8 = undefined;
    var writer = stream.writer(io, &out_buf);
    var http: std.http.Server = .init(&reader.interface, &writer.interface);
    var request = try http.receiveHead();
    const target = try arena.dupe(u8, request.head.target);
    const path = target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len];
    const query = if (std.mem.findScalar(u8, target, '?')) |at| target[at + 1 ..] else "";
    var host: ?[]const u8 = null;
    var skein_header = false;
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "host")) host = try arena.dupe(u8, h.value);
        if (std.ascii.eqlIgnoreCase(h.name, "x-skein")) skein_header = true;
    }
    const allowed = switch (guard.check(.{ .method = request.head.method, .path = path, .host = host, .skein_header = skein_header }, s.options.port)) {
        .refused => |r| return request.respond(r.text, .{ .status = r.status, .keep_alive = false }),
        .allowed => |x| x,
    };
    var body: []const u8 = "";
    if (allowed.method == .post) {
        var body_buf: [16 * 1024]u8 = undefined;
        const r = try request.readerExpectContinue(&body_buf);
        body = try r.allocRemaining(arena, .limited(1 << 26));
    }
    const a = blk: {
        try s.mutex.lock(io);
        defer s.mutex.unlock(io);
        if (allowed.api) break :blk try edit_api.handle(arena, s, allowed.method, path[guard.api_prefix.len..], query, body);
        break :blk try answer.get(arena, s, target);
    };
    var headers: std.ArrayList(std.http.Header) = .empty;
    try headers.append(arena, .{ .name = "content-type", .value = a.content_type });
    try headers.append(arena, .{ .name = "cache-control", .value = "no-store" });
    if (a.location) |l| try headers.append(arena, .{ .name = "location", .value = l });
    try request.respond(a.body, .{ .status = a.status, .keep_alive = false, .extra_headers = headers.items });
}

fn say(io: Io, text: []const u8) !void {
    try stdio.stderr().writeStreamingAll(io, text);
}
