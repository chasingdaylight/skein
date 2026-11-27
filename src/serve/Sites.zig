//! The sites of the changes people have open in `skein serve`: each change's
//! worktree rendered as the checkout's site is (serve/Site.zig), made when
//! someone first opens it, and let go before its worktree is taken away
//! (a directory still open cannot be removed on Windows).

const std = @import("std");
const Io = std.Io;

const Site = @import("Site.zig");
const cli = @import("../cli.zig");

const Sites = @This();

gpa: std.mem.Allocator,
io: Io,
by_change: std.StringHashMapUnmanaged(*Site) = .empty,

pub fn init(gpa: std.mem.Allocator, io: Io) Sites {
    return .{ .gpa = gpa, .io = io };
}

pub fn deinit(self: *Sites) void {
    var it = self.by_change.iterator();
    while (it.next()) |e| self.free(e.key_ptr.*, e.value_ptr.*);
    self.by_change.deinit(self.gpa);
}

/// The site of the change `name`, whose project is at `project` in its
/// worktree; rendered as `options` say for the checkout
pub fn of(self: *Sites, name: []const u8, project: []const u8, options: cli.Serve) !*Site {
    if (self.by_change.get(name)) |s| return s;
    const key = try self.gpa.dupe(u8, name);
    errdefer self.gpa.free(key);
    const root_path = try self.gpa.dupe(u8, project);
    errdefer self.gpa.free(root_path);
    var root = try Io.Dir.cwd().openDir(self.io, root_path, .{ .iterate = true });
    errdefer root.close(self.io);
    var o = options;
    o.common.root = root_path;
    const s = try self.gpa.create(Site);
    s.* = .init(self.gpa, self.io, o, root);
    try self.by_change.put(self.gpa, key, s);
    return s;
}

/// Lets the site of the change `name` go, when there is one
pub fn drop(self: *Sites, name: []const u8) void {
    const kv = self.by_change.fetchRemove(name) orelse return;
    self.free(kv.key, kv.value);
}

fn free(self: *Sites, key: []const u8, s: *Site) void {
    var root = s.root;
    const path = s.options.common.root;
    s.deinit();
    root.close(self.io);
    self.gpa.free(path);
    self.gpa.destroy(s);
    self.gpa.free(key);
}
