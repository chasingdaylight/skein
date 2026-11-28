//! What `skein serve` holds while it serves, and how it answers a
//! connection: the request checked (serve/guard.zig), who sent it
//! (serve/sign_in.zig), then their site's page or an editing request,
//! one at a time behind one lock.

const std = @import("std");
const Io = std.Io;

const Context = @import("Context.zig");
const People = @import("People.zig");
const Site = @import("Site.zig");
const Sites = @import("Sites.zig");
const answer = @import("answer.zig");
const edit_api = @import("edit_api.zig");
const guard = @import("guard.zig");
const sign_in = @import("sign_in.zig");

const Server = @This();

io: Io,
gpa: std.mem.Allocator,
/// the checkout that serves
main: *Site,
people: People,
sites: Sites,
setup: sign_in.Setup,
/// the host people reach it at, from `--url`
public_host: ?[]const u8,
mutex: Io.Mutex = .init,

/// Answers connections on `listener` until canceled
pub fn work(self: *Server, listener: *Io.net.Server) Io.Cancelable!void {
    var arena: std.heap.ArenaAllocator = .init(self.gpa);
    defer arena.deinit();
    while (true) {
        _ = arena.reset(.retain_capacity);
        const stream = listener.accept(self.io) catch |e| switch (e) {
            error.Canceled => return error.Canceled,
            else => continue,
        };
        defer stream.close(self.io);
        self.connection(arena.allocator(), stream) catch |e| switch (e) {
            error.Canceled => return error.Canceled,
            else => {},
        };
    }
}

/// Answers one request on `stream`
fn connection(self: *Server, arena: std.mem.Allocator, stream: Io.net.Stream) !void {
    const io = self.io;
    var in_buf: [16 * 1024]u8 = undefined;
    var reader = stream.reader(io, &in_buf);
    var out_buf: [16 * 1024]u8 = undefined;
    var writer = stream.writer(io, &out_buf);
    var http: std.http.Server = .init(&reader.interface, &writer.interface);
    var request = try http.receiveHead();
    const target = try arena.dupe(u8, request.head.target);
    const path = target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len];
    var seen: sign_in.Seen = .{ .peer = stream.socket.address, .path = path, .query = if (std.mem.findScalar(u8, target, '?')) |at| target[at + 1 ..] else "", .now = Io.Clock.real.now(io).toSeconds() };
    var host: ?[]const u8 = null;
    var skein_header = false;
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "host")) host = try arena.dupe(u8, h.value);
        if (std.ascii.eqlIgnoreCase(h.name, "x-skein")) skein_header = true;
        if (std.ascii.eqlIgnoreCase(h.name, "cookie")) seen.cookie = try arena.dupe(u8, h.value);
        if (std.ascii.eqlIgnoreCase(h.name, self.setup.user_header)) seen.user = try arena.dupe(u8, h.value);
        if (std.ascii.eqlIgnoreCase(h.name, self.setup.email_header)) seen.email = try arena.dupe(u8, h.value);
    }
    const allowed = switch (guard.check(.{ .method = request.head.method, .path = path, .host = host, .skein_header = skein_header }, self.main.options.port, self.public_host)) {
        .refused => |r| return request.respond(r.text, .{ .status = r.status, .keep_alive = false }),
        .allowed => |x| x,
    };
    seen.change = allowed.method == .post;
    var body: []const u8 = "";
    if (allowed.method == .post) {
        var body_buf: [16 * 1024]u8 = undefined;
        const r = try request.readerExpectContinue(&body_buf);
        body = try r.allocRemaining(arena, .limited(1 << 26));
    }
    const a = blk: {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        const user = sign_in.who(self.setup, &self.people, seen);
        if (try sign_in.gate(io, arena, self.setup, &self.people, seen, user)) |g| break :blk g;
        var c = try Context.of(arena, self.main, &self.people, &self.sites, user);
        if ((self.setup.mode == .forge or self.setup.mode == .oidc) and user == null) c.sign_in = sign_in.sign_in_path;
        if (seen.cookie) |cookie| c.session = sign_in.cookieValue(cookie);
        if (allowed.api) break :blk try edit_api.handle(arena, &c, allowed.method, path[guard.api_prefix.len..], seen.query, body);
        break :blk try answer.get(arena, c.site, target);
    };
    var headers: std.ArrayList(std.http.Header) = .empty;
    try headers.append(arena, .{ .name = "content-type", .value = a.content_type });
    try headers.append(arena, .{ .name = "cache-control", .value = "no-store" });
    if (a.location) |l| try headers.append(arena, .{ .name = "location", .value = l });
    if (a.set_cookie) |cookie| try headers.append(arena, .{ .name = "set-cookie", .value = cookie });
    try request.respond(a.body, .{ .status = a.status, .keep_alive = false, .extra_headers = headers.items });
}
