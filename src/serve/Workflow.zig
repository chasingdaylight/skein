//! How a save from `skein serve` reaches git, as the project chooses in
//! `.skein/config.toml` (#280; emanspeaks, 2026-11-27):
//!
//!     [serve]
//!     save = "pull-request"   # or "branch", or "commit"
//!     branch = "dev"          # where changes go; by default the branch checked out
//!     editors = ["A. Person"] # with "commit": who commits; others are warned of
//!     approve_sign_in = "again"   # an approval that must be signed: sign in again
//!
//! - `pull-request`: each change is a branch (`edit/NAME`), proposed as a
//!   pull request on the forge, merged there. The default with a `[forge]`.
//! - `branch`: each change is a branch, merged into the branch in the
//!   interface. The default without one.
//! - `commit`: each save is a commit on the branch, its items approved after.
//!
//! None is enforced in a checkout: `skein check` warns where the chosen way
//! was not followed (serve/workflow_checks.zig).

const std = @import("std");

const Schema = @import("../schema/Schema.zig");

const Workflow = @This();

pub const Save = enum { @"pull-request", branch, commit };

/// null: as the forge says, `pull-request` with one, `branch` without
save: ?Save = null,
branch: ?[]const u8 = null,
editors: []const []const u8 = &.{},
/// for an approval that must be signed, given in `skein serve` or on the
/// forge: whether the sign-in of the session will do, or the approver
/// signs in again to give it (#288)
approve_sign_in: ApproveSignIn = .session,

pub const ApproveSignIn = enum { session, again };

/// The way the project chose, or the default
pub fn mode(self: Workflow, has_forge: bool) Save {
    return self.save orelse if (has_forge) .@"pull-request" else .branch;
}

/// The `[serve]` table of the configuration `r`
pub fn read(r: Schema.Reader) Schema.Reader.Error!Workflow {
    const s = try r.child("serve") orelse return .{};
    try s.known(&.{ "save", "branch", "editors", "approve_sign_in" });
    var w: Workflow = .{ .branch = try s.string("branch"), .editors = try s.strings("editors") };
    if (try s.string("save")) |name| {
        w.save = std.meta.stringToEnum(Save, name) orelse blk: {
            try s.complain("save", "expected \"pull-request\", \"branch\" or \"commit\"", .{});
            break :blk null;
        };
    }
    if (try s.string("approve_sign_in")) |name| {
        w.approve_sign_in = std.meta.stringToEnum(ApproveSignIn, name) orelse blk: {
            try s.complain("approve_sign_in", "expected \"session\" or \"again\"", .{});
            break :blk .session;
        };
    }
    return w;
}

/// The branch a change goes on: `edit/NAME`
pub const change_prefix = "edit/";

/// Whether `name` may name a change: lowercase letters, digits and dashes
pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 60 or name[0] == '-') return false;
    for (name) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '-')) return false;
    return true;
}
