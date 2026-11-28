//! A project served for a test, without a socket: its site, the people,
//! and the sites of their changes, answering requests as a person would
//! send them.

const std = @import("std");
const testing = std.testing;

const Context = @import("../Context.zig");
const People = @import("../People.zig");
const Site = @import("../Site.zig");
const Sites = @import("../Sites.zig");
const changes = @import("../changes.zig");
const edit_api = @import("../edit_api.zig");

const Served = @This();

site: Site,
people: People,
sites: Sites,
/// what the test keeps for as long as it serves
arena: std.heap.ArenaAllocator,

/// The project at `root` (its path, and the directory), on the branch checked out
pub fn init(self: *Served, root: []const u8, dir: std.Io.Dir) !void {
    self.* = .{ .site = .init(testing.allocator, testing.io, .{ .common = .{ .root = root } }, dir), .people = .init(testing.allocator), .sites = .init(testing.allocator, testing.io), .arena = .init(testing.allocator) };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    if (try changes.current(testing.io, arena.allocator(), dir)) |b| self.site.start_branch = try self.arena.allocator().dupe(u8, b);
}

pub fn deinit(self: *Served) void {
    self.sites.deinit();
    self.people.deinit();
    self.site.deinit();
    self.arena.deinit();
}

/// The answer's body, to `user` (null: on this computer alone)
pub fn ask(self: *Served, a: std.mem.Allocator, user: ?People.User, method: edit_api.Method, path: []const u8, q: []const u8, body: []const u8) ![]const u8 {
    var c = try Context.of(a, &self.site, &self.people, &self.sites, user);
    return (try edit_api.handle(a, &c, method, path, q, body)).body;
}

pub fn get(self: *Served, a: std.mem.Allocator, path: []const u8, q: []const u8) ![]const u8 {
    return self.ask(a, null, .get, path, q, "");
}

pub fn post(self: *Served, a: std.mem.Allocator, path: []const u8, body: []const u8) ![]const u8 {
    return self.ask(a, null, .post, path, "", body);
}
