//! Documents held to the maturity their item expects at the milestone.

// req: control.maturity
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

test "a document below the maturity its item expects at the milestone" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"docs\"\n\n[maturity]\norder = [\"D\", \"P\", \"B\"]\nmilestone = \"pdr\"\n");
    try write(tmp.dir, ".skein/types/product.toml", "[attributes.pdr]\n");
    try write(tmp.dir, "docs/products.md", "%product[p.plan pdr=B] The plan.\n");
    try write(tmp.dir, "docs/plan.md", "+++\ndocument = \"PLAN\"\nitem = \"p.plan\"\nmaturity = \"P\"\n+++\n\n# Plan\n");
    try write(tmp.dir, "docs/ready.md", "+++\ndocument = \"READY\"\nitem = \"p.plan\"\nmaturity = \"B\"\n+++\n\n# Ready\n");
    try write(tmp.dir, "docs/odd.md", "+++\ndocument = \"ODD\"\nitem = \"p.plan\"\nmaturity = \"Z\"\n+++\n\n# Odd\n");
    try write(tmp.dir, "docs/lost.md", "+++\ndocument = \"LOST\"\nitem = \"p.none\"\n+++\n\n# Lost\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    const out = (try check_command.run(testing.io, a, .{ .root = root })).text;
    try expectContains(out, "document PLAN is at P; at pdr, p.plan is expected to be at B");
    try expectContains(out, "document ODD: 'Z' is not a maturity (D, P, B)");
    try expectContains(out, "document LOST is item 'p.none', and there is no such item");
    try testing.expect(std.mem.find(u8, out, "READY") == null);
    // warnings, not problems
    try expectContains(out, "no problems");

    // without a milestone, nothing is expected
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"docs\"\n\n[maturity]\norder = [\"D\", \"P\", \"B\"]\n");
    try testing.expect(std.mem.find(u8, (try check_command.run(testing.io, a, .{ .root = root })).text, "document PLAN") == null);
}
