//! The site `skein serve` serves: the pages `skein render --format html`
//! writes, rendered in memory from the checkout, and rendered again when
//! the project's files have changed (serve/stamp.zig).

const std = @import("std");
const Io = std.Io;

const Workspace = @import("../commands/Workspace.zig");
const cli = @import("../cli.zig");
const render = @import("../commands/render.zig");
const site = @import("../render/site.zig");
const stamps = @import("stamp.zig");

const Site = @This();

gpa: std.mem.Allocator,
io: Io,
options: cli.Serve,
/// the project's root
root: Io.Dir,
/// the files of the site, and what they are kept in
arena: std.heap.ArenaAllocator,
files: site.Files = .empty,
/// the stamp of the files the site was rendered from
stamp: [16]u8 = @splat('0'),
rendered: bool = false,
/// why there is no site: the problems of the configuration or schema
failed: ?[]const u8 = null,
/// the project's name
name: []const u8 = "",
/// held while the site is read or rendered again
mutex: Io.Mutex = .init,

pub fn init(gpa: std.mem.Allocator, io: Io, options: cli.Serve, root: Io.Dir) Site {
    return .{ .gpa = gpa, .io = io, .options = options, .root = root, .arena = .init(gpa) };
}

pub fn deinit(self: *Site) void {
    self.arena.deinit();
}

/// Renders the site again when the files changed since it was; the
/// caller holds the mutex
pub fn refresh(self: *Site) !void {
    const now = try stamps.of(self.io, self.gpa, self.root);
    if (self.rendered and std.mem.eql(u8, &now, &self.stamp)) return;
    var next: std.heap.ArenaAllocator = .init(self.gpa);
    errdefer next.deinit();
    const a = next.allocator();
    var files: site.Files = .empty;
    var failed: ?[]const u8 = null;
    var name: []const u8 = "";
    switch (try Workspace.open(self.io, a, self.options.common)) {
        .failed => |outcome| failed = outcome.text,
        .ok => |opened| {
            var ws = opened;
            defer ws.close();
            name = ws.name();
            switch (try render.prepare(self.io, a, &ws, self.options.profile, self.options.results)) {
                .failed => |outcome| failed = outcome.text,
                .ok => |ctx| _ = try site.build(self.io, a, &ws, ctx, .{ .memory = &files }),
            }
        },
    }
    self.arena.deinit();
    self.arena = next;
    self.files = files;
    self.failed = failed;
    self.name = name;
    self.stamp = now;
    self.rendered = true;
}

/// The stamp of the files as they are now, for a page to know it is old
pub fn current(self: *Site) ![16]u8 {
    return stamps.of(self.io, self.gpa, self.root);
}
