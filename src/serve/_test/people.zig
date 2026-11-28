//! Who uses `skein serve`: sessions and sign-ins under way, which end, and
//! the change each has open. The testing allocator finds what is not freed.

// req: serve.sessions, serve.sign-in
const std = @import("std");
const testing = std.testing;

const People = @import("../People.zig");
const cli = @import("../../cli.zig");

const ada: People.User = .{ .login = "ada", .name = "Ada", .email = "ada@example.invalid", .provider = "forge:github", .subject = "1", .at = "2027-01-01T00:00:00Z" };

test "sessions, sign-ins under way, and open changes" {
    var p: People = .init(testing.allocator);
    defer p.deinit();
    const io = testing.io;
    const token = try p.signIn(io, ada, 100);
    try testing.expectEqual(64, token.len);
    try testing.expectEqualStrings("Ada", p.session(token, 100).?.name);
    try testing.expect(p.session("nope", 100) == null);
    const state = try p.begin(io, "/spec/a.html", true, 100);
    const f = (try p.finish(testing.allocator, state, 100)).?;
    defer testing.allocator.free(f.page);
    try testing.expectEqualStrings("/spec/a.html", f.page);
    try testing.expect(f.again);
    try testing.expect(try p.finish(testing.allocator, state, 100) == null);
    try p.setChange("ada", "fix-a");
    try p.setChange("ada", "fix-b");
    try p.setChange("bob", "fix-b");
    try p.setChange("cy", "other");
    p.closeChange("fix-b");
    try testing.expect(p.changeOf("ada") == null and p.changeOf("bob") == null);
    try testing.expectEqualStrings("other", p.changeOf("cy").?);
    try p.setChange("cy", null);
    try testing.expect(p.changeOf("cy") == null);
}

test "a session ends when idle, and at its longest; using it keeps it" {
    var p: People = .init(testing.allocator);
    defer p.deinit();
    p.limits = .{ .idle = 10, .longest = 100 };
    const io = testing.io;
    const idle = try p.signIn(io, ada, 0);
    try testing.expect(p.session(idle, 10) != null);
    // used at 10: counts from there
    try testing.expect(p.session(idle, 20) != null);
    try testing.expect(p.session(idle, 31) == null);
    // and once ended, gone for good
    try testing.expect(p.session(idle, 31) == null);
    try testing.expectEqual(0, p.sessions.count());

    const busy = try p.signIn(io, ada, 0);
    var t: i64 = 0;
    while (t <= 100) : (t += 5) try testing.expect(p.session(busy, t) != null);
    try testing.expect(p.session(busy, 101) == null);
}

test "a sign-in under way ends after ten minutes, and they are capped" {
    var p: People = .init(testing.allocator);
    defer p.deinit();
    p.limits.pending_most = 3;
    const io = testing.io;
    const late = try p.begin(io, "/", false, 0);
    const late_copy = try testing.allocator.dupe(u8, late);
    defer testing.allocator.free(late_copy);
    try testing.expect(try p.finish(testing.allocator, late_copy, 601) == null);

    // the oldest goes when there are too many
    var states: [5][]u8 = undefined;
    for (&states, 0..) |*s, i| s.* = try testing.allocator.dupe(u8, try p.begin(io, "/", false, @intCast(i)));
    defer for (states) |s| testing.allocator.free(s);
    try testing.expectEqual(3, p.pending.count());
    try testing.expect(try p.finish(testing.allocator, states[0], 5) == null);
    try testing.expect(try p.finish(testing.allocator, states[1], 5) == null);
    const kept = (try p.finish(testing.allocator, states[4], 5)).?;
    testing.allocator.free(kept.page);

    // those begun long ago are forgotten when the next begins
    _ = try p.begin(io, "/", false, 10_000);
    try testing.expectEqual(1, p.pending.count());
}

test "session lengths on the command line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const given = (try cli.parse(a, &.{ "serve", "--session-hours", "2", "--session-days", "30" })).serve;
    try testing.expectEqual(2, given.session_hours);
    try testing.expectEqual(30, given.session_days);
    const default = (try cli.parse(a, &.{"serve"})).serve;
    try testing.expectEqual(12, default.session_hours);
    try testing.expectEqual(7, default.session_days);
    try testing.expect(std.mem.find(u8, (try cli.parse(a, &.{ "serve", "--session-hours", "0" })).misuse, "a whole number above 0") != null);
}
