//! Signed approvals (#287): where a type asks for them (`[approval] signed`,
//! of every role or of some), an approval counts only when the commit that
//! recorded it is signed by a key of the approver's, as git verifies it.
//! Skein holds no key and does no cryptography: git signs (`skein approve
//! --sign`, `git commit -S`) with an OpenPGP key, an SSH key, or an X.509
//! certificate such as a badge's (`gpg.format = x509`), and git verifies.
//! Each approver's keys are in `.skein/signers.toml`, committed and
//! reviewed like the type's approvers:
//!
//!     "A. Reviewer" = ["SHA256:Vq8...", "CN=REVIEWER.A.1234567890"]
//!
//! An entry is matched against the signature's key fingerprint, its primary
//! key's, its key ID or its signer, as git reports them.
//!
//! An approval given in `skein serve` or on the forge is not signed by the
//! approver's own key; an electronic signature will do (emanspeaks,
//! 2026-11-27, #288): the record keeps how the approver was signed in, or
//! the forge's record of it, and its commit is signed by a server the
//! project trusts to have seen it, whose keys are `servers` in the same file:
//!
//!     servers = ["SHA256:Qw3..."]
//!
//! With `[serve] approve_sign_in = "again"`, the approver must have signed
//! in again to give it, or the forge must have asked them to.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Approvals = @import("Approvals.zig");
const Graph = @import("Graph.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const git = @import("../git.zig");
const record_files = @import("record_files.zig");
const toml = @import("../toml.zig");

pub const signers_file = Project.dir_name ++ "/signers.toml";

pub const Signers = std.StringArrayHashMapUnmanaged([]const []const u8);

/// The keys of each approver, from `.skein/signers.toml`; empty when there is none
pub fn loadSigners(io: Io, a: Allocator, root: Io.Dir, report: *Report) !Signers {
    var out: Signers = .empty;
    const text = root.readFileAlloc(io, signers_file, a, .limited(1 << 20)) catch return out;
    var diag: toml.Diagnostic = .{};
    const t = toml.parse(a, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => {
            try report.add(signers_file, diag.line, diag.column, "{s}", .{diag.message});
            return out;
        },
    };
    for (t.keys()) |who| {
        const v = t.get(who).?;
        switch (v) {
            .string => |s| try out.put(a, who, try a.dupe([]const u8, &.{s})),
            .array => |list| {
                var keys: std.ArrayList([]const u8) = .empty;
                for (list.items.items) |k| {
                    if (k == .string) try keys.append(a, k.string);
                }
                try out.put(a, who, keys.items);
            },
            else => try report.add(signers_file, 0, 0, "{s}: a key, or a list of keys", .{who}),
        }
    }
    return out;
}

/// Whether an approval in `role` of an item of `item_type` must be signed
pub fn needed(item_type: *const Schema.ItemType, role: ?[]const u8) bool {
    return switch (item_type.approval_signed) {
        .none => false,
        .all => true,
        .roles => |roles| if (role) |r| Schema.names.contains(roles, r) else false,
    };
}

/// What git says of the commit that recorded an approval
pub const Signature = struct {
    /// git's `%G?`: G good, U good of unknown validity, B bad, X and Y
    /// expired, R revoked, E cannot be checked, N none
    status: u8,
    signer: []const u8,
    keys: []const []const u8,
};

/// The key of the signers file that lists the servers trusted to attest
pub const servers_key = "servers";

/// Why `approval` does not count as signed; null when it does. `line` is
/// its record as `Approvals.write` writes it.
pub fn problem(io: Io, a: Allocator, root: Io.Dir, signers: *const Signers, file: []const u8, line: []const u8, ap: Approvals.Approval, again: bool) !?[]const u8 {
    const by = ap.by;
    const attested = ap.evidence.signed_in != null or ap.evidence.pull != null;
    const out = try git.output(io, a, root, &.{ "log", "-1", "--format=%G?%x1f%GS%x1f%GF%x1f%GP%x1f%GK", "-S", line, "--", file }) orelse return "it is not in git: its signature is that of the commit that records it";
    const text = std.mem.trim(u8, out, " \r\n");
    if (text.len == 0) return "it is not committed yet: its signature is that of the commit that records it ('skein approve --sign')";
    var parts = std.mem.splitScalar(u8, text, 0x1f);
    const status = (parts.next() orelse "N");
    const signer = parts.next() orelse "";
    var keys: std.ArrayList([]const u8) = .empty;
    while (parts.next()) |k| if (k.len > 0) try keys.append(a, k);
    switch (if (status.len > 0) status[0] else 'N') {
        'G', 'U' => {},
        'N' => return "the commit that records it is not signed ('skein approve --sign')",
        'B' => return "the signature of the commit that records it is bad",
        'X', 'Y' => return "the commit that records it was signed with an expired key or signature",
        'R' => return "the commit that records it was signed with a revoked key",
        else => return "the signature of the commit that records it cannot be checked here (git lacks the key, or for SSH keys gpg.ssh.allowedSignersFile)",
    }
    if (signers.get(by)) |wanted| if (anyMatches(wanted, signer, keys.items)) return null;
    // an electronic signature: the sign-in or the forge's record, attested by a server
    if (attested) {
        const servers = signers.get(servers_key) orelse return try a.print("it was given in skein serve or on the forge, and {s} lists no servers to attest it", .{signers_file});
        if (!anyMatches(servers, signer, keys.items)) return try a.print("it was given in skein serve or on the forge, and its commit is signed by {s}, which is none of the servers in {s}", .{ if (signer.len > 0) signer else keys.items[0], signers_file });
        if (again) {
            if (ap.evidence.signed_in) |si| if (!si.again) return "it was given with the session's sign-in, and the project asks for a sign-in again to approve ([serve] approve_sign_in)";
            if (ap.evidence.pull != null and !ap.evidence.reauth) return "the forge did not ask the reviewer to sign in again to approve, and the project asks for it ([serve] approve_sign_in)";
        }
        return null;
    }
    if (signers.get(by) == null) return try a.print("{s} has no key in {s}", .{ by, signers_file });
    return try a.print("the commit that records it is signed by {s}, which is not one of {s}'s keys in {s}", .{ if (signer.len > 0) signer else keys.items[0], by, signers_file });
}

fn anyMatches(wanted: []const []const u8, signer: []const u8, keys: []const []const u8) bool {
    for (wanted) |w| {
        if (matches(w, signer)) return true;
        for (keys) |k| if (matches(w, k)) return true;
    }
    return false;
}

fn matches(want: []const u8, have: []const u8) bool {
    const w = std.mem.trim(u8, want, " ");
    const h = std.mem.trim(u8, have, " ");
    if (w.len == 0 or h.len == 0) return false;
    return std.ascii.eqlIgnoreCase(w, h) or (w.len >= 16 and std.ascii.endsWithIgnoreCase(h, w)) or (h.len >= 16 and std.ascii.endsWithIgnoreCase(w, h));
}

/// Reports each current approval of a type that asks for signed approvals
/// whose record's commit is not signed by a key of the approver's
pub fn check(io: Io, a: Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, approvals: *const Approvals, report: *Report) !void {
    const schema = &project.schema;
    const again = project.workflow.approve_sign_in == .again;
    var signers: ?Signers = null;
    for (approvals.all.items) |ap| {
        const item = graph.find(ap.item) orelse continue;
        const item_type = schema.itemType(item.type_name) orelse continue;
        if (!needed(item_type, ap.as)) continue;
        if (!try Approvals.isCurrent(a, graph, schema, ap, item)) continue;
        if (signers == null) signers = try loadSigners(io, a, root, report);
        const file = try Approvals.fileOf(a, item);
        const line = try Approvals.recordLine(a, item.id, ap);
        if (try problem(io, a, root, &signers.?, file, line, ap, again)) |why| {
            try report.add(item.file, item.line, 1, "{s}: the approval by {s}{s} must be signed, and {s}", .{ item.id, ap.by, if (ap.as) |r| try a.print(" as {s}", .{r}) else "", why });
        }
    }
}

test matches {
    try std.testing.expect(matches("SHA256:abcdefghijklmnop", "sha256:ABCDEFGHIJKLMNOP"));
    try std.testing.expect(matches("0123456789ABCDEF", "FFFF0123456789ABCDEF"));
    try std.testing.expect(!matches("", "x"));
    try std.testing.expect(!matches("ABCD", "zz-ABCD"));
}
