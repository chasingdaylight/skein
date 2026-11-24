//! A planning repository: three repositories on disk, `plan` (which holds
//! the people and calendar, and whose schedule and views span the others),
//! `compiler` and `site`. Work in the plan orders work in the others, and
//! `site` takes its people from the plan.

// req: planning.repository, planning.span
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const load_command = @import("../../commands/load.zig");
const render_command = @import("../../commands/render.zig");
const schedule_command = @import("../../commands/schedule.zig");

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

const task_type =
    \\[attributes.start]
    \\type = "date"
    \\[attributes.days]
    \\type = "integer"
    \\[attributes.owner]
    \\[attributes.mode]
    \\[planning]
    \\start = "start"
    \\duration = "days"
    \\assignees = "owner"
    \\mode = "mode"
    \\
;

fn repository(dir: std.Io.Dir, name: []const u8, config: []const u8, plan: []const u8) !void {
    const base = try std.fmt.allocPrint(testing.allocator, "{s}/.skein/", .{name});
    defer testing.allocator.free(base);
    var path: [128]u8 = undefined;
    try write(dir, try std.fmt.bufPrint(&path, "{s}config.toml", .{base}), config);
    try write(dir, try std.fmt.bufPrint(&path, "{s}types/task.toml", .{base}), task_type);
    try write(dir, try std.fmt.bufPrint(&path, "{s}links/precedes.toml", .{base}), "[planning]\nrole = \"precedes\"\n");
    try write(dir, try std.fmt.bufPrint(&path, "{s}/plan/plan.md", .{name}), plan);
}

test "a planning repository: work ordered across repositories, shared people, views over all" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;

    try repository(dir, "plan",
        \\[[sources]]
        \\path = "plan"
        \\
        \\[planning]
        \\span = true
        \\
        \\[[repositories]]
        \\name = "compiler"
        \\path = "../compiler"
        \\
        \\[[repositories]]
        \\name = "site"
        \\path = "../site"
        \\
    , "%task[t.kickoff start=2027-03-01 days=2 mode=fixed precedes=compiler:t.parse,site:t.docs] Kick off.\n");
    try write(dir, "plan/.skein/resources.toml", "[calendar]\nhours = 6\n\n[people.ann]\nname = \"Ann\"\n");
    try repository(dir, "compiler", "[[sources]]\npath = \"plan\"\n", "%task[t.parse days=3 owner=ann] Parse.\n");
    try repository(dir, "site",
        \\[[sources]]
        \\path = "plan"
        \\
        \\[planning]
        \\repository = "plan"
        \\
        \\[[repositories]]
        \\name = "plan"
        \\path = "../plan"
        \\
    , "%task[t.docs days=2 owner=ann] Docs.\n");
    try write(dir, "plan/plan/views.md", "# Views\n\n```skein\ngantt task\n```\n\n```skein\nboard task\n```\n");

    const plan_root = try dir.realPathFileAlloc(testing.io, "plan", a);
    const site_root = try dir.realPathFileAlloc(testing.io, "site", a);
    const plan: @import("../../cli.zig").Common = .{ .root = plan_root, .state = .working };
    const site: @import("../../cli.zig").Common = .{ .root = site_root, .state = .working };

    // the plan's schedule places the others' work after its kickoff, two days from the 1st
    const said = (try schedule_command.run(testing.io, a, .{ .common = plan })).text;
    try expectContains(said, "3 work items scheduled");
    const toml = try dir.readFileAlloc(testing.io, "plan/.skein/schedule.toml", a, .limited(1 << 16));
    try expectContains(toml, "[items.\"compiler:t.parse\"]\nstart = 2027-03-03\nfinish = 2027-03-05\nmode = \"float\"\nsource = \"computed\"\n");
    try expectContains(toml, "[items.\"site:t.docs\"]\nstart = 2027-03-03\nfinish = 2027-03-04\n");
    // the other repositories' files are left alone
    try testing.expectError(error.FileNotFound, dir.access(testing.io, "compiler/.skein/schedule.toml", .{}));
    try expectContains((try dir.readFileAlloc(testing.io, "compiler/plan/plan.md", a, .limited(1 << 16))), "%task[t.parse days=3 owner=ann]");
    try expectContains((try check_command.run(testing.io, a, plan)).text, "no problems");

    // views over all of it
    const out_dir = try std.Io.Dir.path.join(a, &.{ plan_root, "out" });
    _ = try render_command.run(testing.io, a, .{ .common = plan, .out = out_dir });
    const page = try dir.readFileAlloc(testing.io, "plan/out/plan/views.md", a, .limited(1 << 16));
    try expectContains(page, "  compiler/t.parse :crit, t2, 2027-03-03, 2027-03-06\n  site/t.docs :t3, 2027-03-03, 2027-03-05\n");
    try expectContains(page, "| `compiler:t.parse` | 2027-03-03 | 2027-03-05 |");
    // the plan's own statuses as columns, the others' by what they name
    try expectContains(page, "| draft (1) | approved (0) | deprecated (0) | (not named) (2) |");
    try expectContains(page, "`site:t.docs`");

    // the site's people are the plan's: ann is there (its float work has no dates of its
    // own, the plan places it)
    const load = (try load_command.run(testing.io, a, .{ .common = site })).text;
    try expectContains(load, "ann (Ann)\n  no work with dates\n");
    // ann is known to the site's check, though the site has no schedule of its own
    const site_check = (try check_command.run(testing.io, a, site)).text;
    try testing.expect(std.mem.find(u8, site_check, "is not among the people") == null);
}
