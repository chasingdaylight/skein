//! Jama Connect's REST API (#251), at `URL/rest/v1/`: what `skein import
//! jama` reads and `skein jama` writes. Signed in from the environment,
//! never the repository: an API client's `JAMA_CLIENT_ID` and
//! `JAMA_CLIENT_SECRET` (OAuth client credentials, `URL/rest/oauth/token`),
//! else `JAMA_USERNAME` and `JAMA_PASSWORD` (basic authentication). The
//! instance is `url` in `.skein/jama.toml`, else `JAMA_URL`. Lists come in
//! pages of 50 (`startAt`, `maxResults`; `meta.pageInfo.totalResults`).

const std = @import("std");
const Io = std.Io;

const env = @import("../env.zig");
const github = @import("github.zig");
const tool = @import("tool.zig");

pub const Reply = github.Reply;

pub const Request = struct {
    method: std.http.Method,
    url: []const u8,
    /// the value of the Authorization header
    auth: []const u8,
    payload: ?[]const u8 = null,
    content_type: []const u8 = "application/json",
};

/// How Jama is asked: the instance itself, or recorded answers in tests
pub var call: *const fn (Io, std.mem.Allocator, Request) anyerror!Reply = live;

fn live(io: Io, arena: std.mem.Allocator, r: Request) anyerror!Reply {
    const headers = [_]std.http.Header{
        .{ .name = "Authorization", .value = r.auth },
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "User-Agent", .value = "skein" },
    };
    const uri = std.Uri.parse(r.url) catch return .{ .unreachable_ = try arena.print("'{s}' is not a URL", .{r.url}) };
    const host = if (uri.host) |h| switch (h) {
        .raw, .percent_encoded => |s| s,
    } else r.url;
    return tool.httpsSendAs(io, arena, r.method, r.url, &headers, r.payload, r.content_type, host, "Jama");
}

pub fn Found(comptime T: type) type {
    return union(enum) { found: T, missing, failed: []const u8 };
}

pub const Client = struct {
    io: Io,
    arena: std.mem.Allocator,
    /// the instance, without a trailing slash: `https://example.jamacloud.com`
    base: []const u8,
    auth: []const u8,

    /// `method` to `path` of the API (`items?project=1`), with `json`
    pub fn send(self: *const Client, method: std.http.Method, path: []const u8, json: ?[]const u8) !Reply {
        return call(self.io, self.arena, .{ .method = method, .url = try self.arena.print("{s}/rest/v1/{s}", .{ self.base, path }), .auth = self.auth, .payload = json });
    }

    /// The `data` of the answer to GET `path`
    pub fn get(self: *const Client, path: []const u8) !Found(std.json.Value) {
        const text = switch (try self.send(.GET, path, null)) {
            .body => |t| t,
            .missing => return .missing,
            .unreachable_ => |why| return .{ .failed = why },
        };
        const v = parse(self.arena, text) orelse return .{ .failed = "Jama gave an answer skein cannot read" };
        return .{ .found = v.object.get("data") orelse return .{ .failed = "Jama gave no data" } };
    }

    /// Every entry of the list at `path`, page by page
    pub fn getAll(self: *const Client, path: []const u8) !Found([]const std.json.Value) {
        var out: std.ArrayList(std.json.Value) = .empty;
        const sep: u8 = if (std.mem.findScalar(u8, path, '?') == null) '?' else '&';
        while (true) {
            const text = switch (try self.send(.GET, try self.arena.print("{s}{c}startAt={d}&maxResults={d}", .{ path, sep, out.items.len, page_size }), null)) {
                .body => |t| t,
                .missing => return .missing,
                .unreachable_ => |why| return .{ .failed = why },
            };
            const v = parse(self.arena, text) orelse return .{ .failed = "Jama gave an answer skein cannot read" };
            const data = v.object.get("data") orelse return .{ .failed = "Jama gave no data" };
            if (data != .array) return .{ .failed = "Jama gave no list" };
            try out.appendSlice(self.arena, data.array.items);
            const total = integer(field(v, &.{ "meta", "pageInfo", "totalResults" })) orelse break;
            if (data.array.items.len == 0 or out.items.len >= total) break;
        }
        return .{ .found = out.items };
    }

    /// The id Jama gave what a POST made (`meta.id`)
    pub fn created(self: *const Client, path: []const u8, json: []const u8) !Found(i64) {
        const text = switch (try self.send(.POST, path, json)) {
            .body => |t| t,
            .missing => return .missing,
            .unreachable_ => |why| return .{ .failed = why },
        };
        const v = parse(self.arena, text) orelse return .{ .failed = "Jama gave an answer skein cannot read" };
        return .{ .found = integer(field(v, &.{ "meta", "id" })) orelse return .{ .failed = "Jama gave no id for what it made" } };
    }
};

pub const page_size = 50;

/// A client of the instance `url`, signed in from the environment; or why not
pub fn connect(io: Io, arena: std.mem.Allocator, url: ?[]const u8) !Found(Client) {
    const base = std.mem.trimEnd(u8, url orelse env.get("JAMA_URL") orelse
        return .{ .failed = "no Jama instance: url in .skein/jama.toml, or JAMA_URL" }, "/");
    if (env.get("JAMA_CLIENT_ID")) |id| {
        const secret = env.get("JAMA_CLIENT_SECRET") orelse return .{ .failed = "JAMA_CLIENT_ID is set, and JAMA_CLIENT_SECRET is not" };
        const reply = try call(io, arena, .{
            .method = .POST,
            .url = try arena.print("{s}/rest/oauth/token", .{base}),
            .auth = try basic(arena, id, secret),
            .payload = "grant_type=client_credentials",
            .content_type = "application/x-www-form-urlencoded",
        });
        const text = switch (reply) {
            .body => |t| t,
            .missing => return .{ .failed = "Jama has no OAuth token endpoint at that URL" },
            .unreachable_ => |why| return .{ .failed = why },
        };
        const v = parse(arena, text) orelse return .{ .failed = "Jama gave a token skein cannot read" };
        const token = field(v, &.{"access_token"}) orelse return .{ .failed = "Jama gave no access token" };
        if (token != .string) return .{ .failed = "Jama gave no access token" };
        return .{ .found = .{ .io = io, .arena = arena, .base = base, .auth = try arena.print("Bearer {s}", .{token.string}) } };
    }
    const user = env.get("JAMA_USERNAME") orelse return .{ .failed = "no Jama credentials: JAMA_CLIENT_ID and JAMA_CLIENT_SECRET (an API client), or JAMA_USERNAME and JAMA_PASSWORD" };
    const password = env.get("JAMA_PASSWORD") orelse return .{ .failed = "JAMA_USERNAME is set, and JAMA_PASSWORD is not" };
    return .{ .found = .{ .io = io, .arena = arena, .base = base, .auth = try basic(arena, user, password) } };
}

fn basic(arena: std.mem.Allocator, user: []const u8, password: []const u8) ![]const u8 {
    const pair = try arena.print("{s}:{s}", .{ user, password });
    const encoder = std.base64.standard.Encoder;
    const out = try arena.alloc(u8, encoder.calcSize(pair.len));
    return arena.print("Basic {s}", .{encoder.encode(out, pair)});
}

fn parse(arena: std.mem.Allocator, text: []const u8) ?std.json.Value {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{}) catch return null;
    return if (v == .object) v else null;
}

/// The value at `keys` of `v`
pub fn field(v: std.json.Value, keys: []const []const u8) ?std.json.Value {
    var cur = v;
    for (keys) |k| {
        if (cur != .object) return null;
        cur = cur.object.get(k) orelse return null;
    }
    return cur;
}

pub fn integer(v: ?std.json.Value) ?i64 {
    const x = v orelse return null;
    return if (x == .integer) x.integer else null;
}

pub fn string(v: ?std.json.Value) ?[]const u8 {
    const x = v orelse return null;
    return if (x == .string) x.string else null;
}

test {
    _ = @import("_test/jama.zig");
}
