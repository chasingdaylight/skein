//! Signed approvals and approvals in order, in a repository made for the
//! test, signed with an SSH key made for it (skipped where `ssh-keygen`
//! is not to be had).

// req: approval.signed, approval.in-order
const std = @import("std");
const testing = std.testing;

const Repo = @import("../../commands/_test/Repo.zig");
const approve = @import("../../commands/approve.zig");
const check = @import("../../commands/check.zig");
const git = @import("../../git.zig");

fn has(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) == null) {
        std.debug.print("missing: {s}\nin: {s}\n", .{ part, text });
        return error.TestExpectedEqual;
    }
}

fn lacks(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) != null) {
        std.debug.print("present: {s}\nin: {s}\n", .{ part, text });
        return error.TestExpectedEqual;
    }
}

const types =
    \\[approval]
    \\statuses = ["approved"]
    \\roles = ["ppc", "pm"]
    \\signed = ["pm"]
    \\in_order = true
    \\
;

/// A repository whose commits `git commit -S` signs with a new SSH key; its
/// fingerprint, or null where no key can be made
fn signing(repo: *Repo) !?[]const u8 {
    const a = repo.arena.allocator();
    const key = try std.Io.Dir.path.join(a, &.{ repo.root, ".git", "test-key" });
    switch (try git.run(testing.io, a, repo.tmp.dir, &.{"version"})) {
        .ok => {},
        .failed => return null,
    }
    const made = std.process.run(a, testing.io, .{ .argv = &.{ "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "tester", "-f", key } }) catch return null;
    if (!made.term.success()) return null;
    const listed = std.process.run(a, testing.io, .{ .argv = &.{ "ssh-keygen", "-lf", try a.print("{s}.pub", .{key}) } }) catch return null;
    var words = std.mem.tokenizeScalar(u8, listed.stdout, ' ');
    _ = words.next();
    const fingerprint = words.next() orelse return null;
    const public = try repo.tmp.dir.readFileAlloc(testing.io, ".git/test-key.pub", a, .limited(1 << 12));
    try repo.write(".git/allowed-signers", try a.print("tester@example.invalid {s}", .{public}));
    try repo.git(&.{ "config", "user.name", "Tester" });
    try repo.git(&.{ "config", "user.email", "tester@example.invalid" });
    try repo.git(&.{ "config", "gpg.format", "ssh" });
    try repo.git(&.{ "config", "user.signingkey", try a.print("{s}.pub", .{key}) });
    try repo.git(&.{ "config", "gpg.ssh.allowedSignersFile", try std.Io.Dir.path.join(a, &.{ repo.root, ".git", "allowed-signers" }) });
    return fingerprint;
}

test "an approval in a role that must sign counts once its commit is signed by the approver's key" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    const fingerprint = try signing(&repo) orelse return error.SkipZigTest;
    try repo.write(".skein/types/rule.toml", types);
    try repo.write("spec/lex.md", "%rule[lex.a approved] A.\n\n%rule[lex.b] B.\n");
    try repo.write(".skein/signers.toml", try a.print("Tester = \"{s}\"\n", .{fingerprint}));
    try repo.commit("signed approvals");

    // PP&C approves, needing no signature; the project manager's comes after, signed
    const ppc = try approve.run(testing.io, a, .{ .common = .{ .root = repo.root }, .ids = &.{"lex.a"}, .by = "P. Controller", .as = "ppc" });
    try has(ppc.text, "approved by P. Controller as ppc");
    try repo.commit("ppc");
    // the project manager's approval written, not committed: not signed yet
    _ = try approve.run(testing.io, a, .{ .common = .{ .root = repo.root }, .ids = &.{"lex.a"}, .by = "Tester", .as = "pm" });
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "lex.a: the approval by Tester as pm must be signed, and it is not committed yet");
    // committed without a signature
    try repo.commit("pm, unsigned");
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "the commit that records it is not signed");

    // approved again, signed: it counts
    const signed = try approve.run(testing.io, a, .{ .common = .{ .root = repo.root }, .ids = &.{"lex.a"}, .by = "Tester", .as = "pm", .on = "2099-01-01", .sign = true });
    try has(signed.text, "committed, signed");
    try lacks((try check.run(testing.io, a, .{ .root = repo.root })).text, "must be signed");

    // a key that is not the approver's
    try repo.write(".skein/signers.toml", "Tester = \"SHA256:not-the-key-of-anyone-at-all\"\n");
    try repo.commit("another key");
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "which is not one of Tester's keys in .skein/signers.toml");
}

test "roles that approve in order: a later level before an earlier one is reported" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    try repo.write(".skein/types/rule.toml", "[approval]\nstatuses = [\"approved\"]\nroles = [\"ppc\", \"pm\"]\nin_order = true\n");
    try repo.write("spec/lex.md", "%rule[lex.a approved] A.\n\n%rule[lex.b] B.\n");
    try repo.commit("levels");
    _ = try approve.run(testing.io, a, .{ .common = .{ .root = repo.root }, .ids = &.{"lex.a"}, .by = "Tester", .as = "pm", .on = "2027-03-01" });
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "lex.a: approved as pm before it was as ppc, whose approval comes first");
    _ = try approve.run(testing.io, a, .{ .common = .{ .root = repo.root }, .ids = &.{"lex.a"}, .by = "P. Controller", .as = "ppc", .on = "2027-03-02" });
    try has((try check.run(testing.io, a, .{ .root = repo.root })).text, "lex.a: approved as pm on 2027-03-01, before it was as ppc");
    _ = try approve.run(testing.io, a, .{ .common = .{ .root = repo.root }, .ids = &.{"lex.a"}, .by = "Tester", .as = "pm", .on = "2027-03-03" });
    try lacks((try check.run(testing.io, a, .{ .root = repo.root })).text, "lex.a:");
}

test "signed names roles of the type" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    try repo.write(".skein/types/rule.toml", "[approval]\nstatuses = [\"approved\"]\nroles = [\"ppc\"]\nsigned = [\"pm\"]\nin_order = true\n");
    const out = (try check.run(testing.io, a, .{ .root = repo.root })).text;
    try has(out, "'pm' is not one of the roles");
    try has(out, "the roles approve in order: name two or more");
}
