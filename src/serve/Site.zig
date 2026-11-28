//! The site `skein serve` serves: the pages `skein render --format html`
//! writes, rendered in memory from the checkout, and rendered again when
//! the files the project reads have changed (serve/stamp.zig). Every open
//! page asks each second whether they have; within one second, the answer
//! is the last one (#304).

const std = @import("std");
const Io = std.Io;

const Workspace = @import("../commands/Workspace.zig");
const cli = @import("../cli.zig");
const reading = @import("../places.zig");
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
/// the places the project reads, as it was rendered (in `arena`); null
/// before then, when the stamp looks at every file
places: ?[]const reading.Place = null,
/// the last stamp taken, and the second it was taken in
checked: [16]u8 = @splat('0'),
checked_at: i64 = -1,
rendered: bool = false,
/// why there is no site: the problems of the configuration or schema
failed: ?[]const u8 = null,
/// the project's name
name: []const u8 = "",
/// the branch checked out when it started: where changes go, unless
/// `[serve] branch` says
start_branch: ?[]const u8 = null,

pub fn init(gpa: std.mem.Allocator, io: Io, options: cli.Serve, root: Io.Dir) Site {
    return .{ .gpa = gpa, .io = io, .options = options, .root = root, .arena = .init(gpa) };
}

pub fn deinit(self: *Site) void {
    self.arena.deinit();
}

/// Renders the site again when the files changed since it was; the
/// caller holds the server's lock
pub fn refresh(self: *Site) !void {
    const now = try self.take();
    if (self.rendered and std.mem.eql(u8, &now, &self.stamp)) return;
    var next: std.heap.ArenaAllocator = .init(self.gpa);
    errdefer next.deinit();
    const a = next.allocator();
    var files: site.Files = .empty;
    var failed: ?[]const u8 = null;
    var name: []const u8 = "";
    var read: ?[]const reading.Place = null;
    switch (try Workspace.open(self.io, a, self.options.common)) {
        .failed => |outcome| failed = outcome.text,
        .ok => |opened| {
            var ws = opened;
            defer ws.close();
            name = ws.name();
            read = try reading.of(a, &ws.project, .site);
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
    self.rendered = true;
    // the stamp of what is read now, which the configuration may have changed
    self.places = read;
    self.stamp = if (read == null) now else try self.take();
}

/// The stamp of the files as they are now, for a page to know it is old;
/// within the second of the last one, that one
pub fn current(self: *Site) ![16]u8 {
    const second = Io.Clock.real.now(self.io).toSeconds();
    if (second == self.checked_at) return self.checked;
    return self.take();
}

/// The stamp of the files as they are now, kept as the last one taken
fn take(self: *Site) ![16]u8 {
    self.checked = try stamps.of(self.io, self.gpa, self.root, self.places);
    self.checked_at = Io.Clock.real.now(self.io).toSeconds();
    return self.checked;
}
