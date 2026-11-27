//! What a request to `skein serve` is answered in: the checkout that serves,
//! on the branch changes go to; the site the person works in, that
//! checkout's or their change's (serve/Sites.zig); and who they are.

const std = @import("std");

const People = @import("People.zig");
const Site = @import("Site.zig");
const Sites = @import("Sites.zig");
const worktrees = @import("worktrees.zig");

const Context = @This();

main: *Site,
/// where this person works
site: *Site,
/// null on this computer alone: git's user
user: ?People.User,
people: *People,
sites: *Sites,
/// where to sign in, when people sign in through a provider and this one has not
sign_in: ?[]const u8 = null,
/// the session's token, when signed in through a provider
session: ?[]const u8 = null,

/// What the person is known by; "" on this computer alone
pub fn login(c: *const Context) []const u8 {
    return if (c.user) |u| u.login else "";
}

/// The context of a person on `main`, in their open change when they have one
pub fn of(arena: std.mem.Allocator, main: *Site, people: *People, sites: *Sites, user: ?People.User) !Context {
    var c: Context = .{ .main = main, .site = main, .user = user, .people = people, .sites = sites };
    if (people.changeOf(c.login())) |name| {
        if (try worktrees.place(main.io, arena, main.root, name)) |p| {
            c.site = sites.of(name, p.project, main.options) catch blk: {
                // its worktree is gone (merged or abandoned by someone else)
                try people.setChange(c.login(), null);
                break :blk main;
            };
        }
    }
    return c;
}
