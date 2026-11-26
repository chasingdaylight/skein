//! Starting a project from a template, and taking a template's files into
//! the project to change them.

// req: templates.init, templates.eject
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const coverage_command = @import("../../commands/coverage.zig");
const render_command = @import("../../commands/render.zig");
const init_command = @import("../../commands/init.zig");
const template_command = @import("../../commands/template.zig");

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

fn rootOf(a: std.mem.Allocator, tmp: anytype) ![]const u8 {
    return tmp.dir.realPathFileAlloc(testing.io, ".", a);
}

test "init with a template starts a project that checks clean" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    const started = try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"langspec"} });
    try testing.expectEqual(.ok, started.status);
    try expectContains(started.text, "from the template langspec, with 4 documents");
    const config = try tmp.dir.readFileAlloc(testing.io, ".skein/config.toml", a, .limited(1 << 16));
    try expectContains(config, "template = [\"langspec\"]");
    // the template's own config.toml, after the configuration init writes
    try expectContains(config, "path = \"docs\"\n\n# Conformance tests cite the rules");
    for ([_][]const u8{ "charter", "introduction", "glossary", "coverage" }) |doc| {
        _ = try tmp.dir.readFileAlloc(testing.io, try a.print("docs/{s}.md", .{doc}), a, .limited(1 << 16));
    }

    const checked = try check_command.run(testing.io, a, .{ .root = root });
    try testing.expectEqual(.ok, checked.status);

    const again = try init_command.run(testing.io, a, .{ .root = root });
    try testing.expectEqual(.misuse, again.status);
    try expectContains(again.text, "there is a project here already");
}

test "init without a template, and with one skein does not have" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    const unknown = try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"nope"} });
    try testing.expectEqual(.misuse, unknown.status);
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, ".skein", .{}));

    const plain = try init_command.run(testing.io, a, .{ .root = root });
    try testing.expectEqual(.ok, plain.status);
    try expectContains(plain.text, "with 0 documents");
    const config = try tmp.dir.readFileAlloc(testing.io, ".skein/config.toml", a, .limited(1 << 16));
    try testing.expect(std.mem.find(u8, config, "template") == null);
}

// req: templates.npr
test "a project under NPR 7150.2D: its class chooses the requirements and the traces" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    const started = try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"npr7150.2d"} });
    try testing.expectEqual(.ok, started.status);
    // the standard, read-only, where the template's configuration says
    _ = try tmp.dir.readFileAlloc(testing.io, "standards/npr7150.2d/chapter-3.md", a, .limited(1 << 20));
    _ = try tmp.dir.readFileAlloc(testing.io, "standards/npr7150.2d/guidance.md", a, .limited(1 << 20));
    // the class is the project's to give
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "needs the option 'class'");

    const config = try tmp.dir.readFileAlloc(testing.io, ".skein/config.toml", a, .limited(1 << 16));
    const given = try std.mem.replaceOwned(u8, a, config, "# \"class\" = \"\"", "\"class\" = \"C\"");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/config.toml", .data = given });
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    const plain = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(plain, "complies links to swe items: 0 of 88");
    // class C traces requirements to design; the example procedure verifies the example requirement
    try expectContains(plain, "satisfies links to requirement items: 0 of 1");
    try expectContains(plain, "verifies links to requirement items: 1 of 1");

    const safety = try std.mem.replaceOwned(u8, a, given, "\"safety-critical\" = \"false\"", "\"safety-critical\" = \"true\"");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/config.toml", .data = safety });
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text, "complies links to swe items: 0 of 92");

    // at PDR, the development plan is expected updated; the skeleton is a draft
    const at_pdr = try std.mem.replaceOwned(u8, a, given, "# milestone = \"pdr\"", "milestone = \"pdr\"");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/config.toml", .data = at_pdr });
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "document SW-SDP is at D; at pdr, PRD-01 is expected to be at U");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/config.toml", .data = given });

    // the handbook's product maturity and review checklists, read-only
    const maturity = try tmp.dir.readFileAlloc(testing.io, "standards/npr7150.2d/maturity.md", a, .limited(1 << 20));
    try testing.expectEqual(54, std.mem.count(u8, maturity, "\n%product[PRD-"));
    const checklists = try tmp.dir.readFileAlloc(testing.io, "standards/npr7150.2d/review-checklists.md", a, .limited(1 << 20));
    try testing.expectEqual(13, std.mem.count(u8, checklists, "\n%sw-check[SWR-"));

    // class D does not trace to design
    const d = try std.mem.replaceOwned(u8, a, given, "\"class\" = \"C\"", "\"class\" = \"D\"");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/config.toml", .data = d });
    const class_d = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try testing.expect(std.mem.find(u8, class_d, "satisfies links") == null);
}

// req: templates.nasa-std-8739.8b
test "software assurance under NASA-STD-8739.8B, with the NPR 7150.2D template" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    const started = try init_command.run(testing.io, a, .{ .root = root, .templates = &.{ "npr7150.2d", "nasa-std-8739.8b" } });
    try expectContains(started.text, "from the templates npr7150.2d and nasa-std-8739.8b");
    _ = try tmp.dir.readFileAlloc(testing.io, "standards/nasa-std-8739.8b/tasks.md", a, .limited(1 << 20));
    _ = try tmp.dir.readFileAlloc(testing.io, "docs/sa-rmm.md", a, .limited(1 << 20));
    // the class, given once for each template
    const config = try tmp.dir.readFileAlloc(testing.io, ".skein/config.toml", a, .limited(1 << 16));
    const given = try std.mem.replaceOwned(u8, a, config, "# \"class\" = \"\"", "\"class\" = \"C\"");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/config.toml", .data = given });
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    const coverage = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    // a group of tasks for each requirement of the class, and no IV&V without the option
    try expectContains(coverage, "performs links to satask items: 0 of 88");
    try testing.expect(std.mem.find(u8, coverage, "ivv-performs") == null);
}

// req: templates.nasa-std-7009b, render.generated.list
test "models and simulations under NASA-STD-7009B, with their factors in a list" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    try testing.expectEqual(.ok, (try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"nasa-std-7009b"} })).status);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text, "meets links to ms items: 0 of 42");

    // `list model columns=...`: the example model with its criticality
    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    try testing.expectEqual(.ok, (try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir })).status);
    const page = try tmp.dir.readFileAlloc(testing.io, "out/docs/models.md", a, .limited(1 << 20));
    try expectContains(page, "| Item | Status | Consequence | Influence | Criticality | Intended_use |\n");
    try expectContains(page, "[`MDL-001`](#MDL-001) | planned | III | 4 | red | Predict the peak load on the bracket during ascent |");
}

// req: templates.nist-ai-rmf, render.generated.list
test "AI risk management under the NIST AI RMF, with its inventory in a list" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    try testing.expectEqual(.ok, (try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"nist-ai-rmf"} })).status);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    // the 72 subcategories, each expected to be addressed by a row of the profile
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text, "ai-rmf-addresses links to ai-rmf items: 0 of 72");

    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    try testing.expectEqual(.ok, (try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir })).status);
    const page = try tmp.dir.readFileAlloc(testing.io, "out/docs/ai-inventory.md", a, .limited(1 << 20));
    try expectContains(page, "| Item | Status | Ai_kind | Third_party | Risk_tier | Purpose |\n");
    try expectContains(page, "[`AIS-001`](#AIS-001) | planned | generative | yes | moderate | Summarize anomaly reports for the review board |");
}

// req: templates.npr7150.2d-ai
test "AI in a software project under NPR 7150.2D: the handbook's notes link to its requirements" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    const started = try init_command.run(testing.io, a, .{ .root = root, .templates = &.{ "npr7150.2d", "npr7150.2d-ai" } });
    try expectContains(started.text, "from the templates npr7150.2d and npr7150.2d-ai");
    // the class, given once
    const config = try tmp.dir.readFileAlloc(testing.io, ".skein/config.toml", a, .limited(1 << 16));
    const given = try std.mem.replaceOwned(u8, a, config, "# \"class\" = \"\"", "\"class\" = \"C\"");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/config.toml", .data = given });
    // the notes' links name requirements of the NPR, so the project checks clean only with it
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    const notes = try tmp.dir.readFileAlloc(testing.io, "standards/npr7150.2d-ai/handbook-ai.md", a, .limited(1 << 20));
    try expectContains(notes, "%ai-note[AIN-003 topic=7.25 section=7.2 bears-on=SWE-219]");
}

// req: templates.npr7120.7a, render.generated.list
test "IT project management under NPR 7120.7A: the matrix is expected of the kind of effort" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    try testing.expectEqual(.ok, (try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"npr7120.7a"} })).status);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    // a project: its chapter and what both kinds share
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text, "complies-it links to it-action items: 0 of 134");

    // a service line instead
    const config = try tmp.dir.readFileAlloc(testing.io, ".skein/config.toml", a, .limited(1 << 16));
    const lined = try std.mem.replaceOwned(u8, a, config, "\"kind\" = \"project\"", "\"kind\" = \"service-line\"");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/config.toml", .data = lined });
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text, "complies-it links to it-action items: 0 of 39");

    // the reviews in a list
    const out_dir = try std.Io.Dir.path.join(a, &.{ root, "out" });
    try testing.expectEqual(.ok, (try render_command.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir })).status);
    const page = try tmp.dir.readFileAlloc(testing.io, "out/docs/it-life-cycle.md", a, .limited(1 << 20));
    try expectContains(page, "[`ITR-001`](#ITR-001) | SRR | planned | 2027-03-01 | SE DA |");
}

// req: templates.npr7123.1d
test "systems engineering under NPR 7123.1D: its requirements and its reviews" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    try testing.expectEqual(.ok, (try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"npr7123.1d"} })).status);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text, "complies-se links to se items: 0 of 62");
    // the criteria of the 21 reviews, each criterion a part
    const criteria = try tmp.dir.readFileAlloc(testing.io, "standards/npr7123.1d/review-criteria.md", a, .limited(1 << 20));
    try testing.expectEqual(21, std.mem.count(u8, criteria, "\n%criteria[G-"));
    try expectContains(criteria, "- %criteria[.e1] ");
}

// req: templates.human-rating
test "human-rating under NPR 8705.2C and NASA-STD-8719.29, alone and with NPR 7150.2D" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    try testing.expectEqual(.ok, (try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"human-rating"} })).status);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    const coverage = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(coverage, "complies-hr links to hrc items: 0 of ");
    try expectContains(coverage, "complies-hr links to hr items: 0 of ");
    const npr = try tmp.dir.readFileAlloc(testing.io, "standards/human-rating/npr8705.2c.md", a, .limited(1 << 20));
    try expectContains(npr, "%hrc[HRC-2.2.2 srr=I sdr=U pdr=U cdr=U orr=U title=");
    try expectContains(npr, "- %hrc[.a] A list of the significant risk contributors");
    const std_text = try tmp.dir.readFileAlloc(testing.io, "standards/human-rating/nasa-std-8719.29.md", a, .limited(1 << 20));
    try expectContains(std_text, "%hr[HR-4.3.1] The space system shall provide at least single failure tolerance");

    var tmp2 = testing.tmpDir(.{});
    defer tmp2.cleanup();
    const root2 = try rootOf(a, tmp2);
    try testing.expectEqual(.ok, (try init_command.run(testing.io, a, .{ .root = root2, .templates = &.{ "npr7150.2d", "human-rating" } })).status);
    // class A: the software of a crewed system
    const config = try tmp2.dir.readFileAlloc(testing.io, ".skein/config.toml", a, .limited(1 << 16));
    try tmp2.dir.writeFile(testing.io, .{ .sub_path = ".skein/config.toml", .data = try std.mem.replaceOwned(u8, a, config, "# \"class\" = \"\"", "\"class\" = \"A\"") });
    try expectContains((try check_command.run(testing.io, a, .{ .root = root2 })).text, "no problems");
}

// req: templates.npr7120.5f
test "program and project management under NPR 7120.5F, with NPR 7123.1D" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    try testing.expectEqual(.ok, (try init_command.run(testing.io, a, .{ .root = root, .templates = &.{ "npr7120.5f", "npr7123.1d" } })).status);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems");
    const coverage = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(coverage, "complies-pm links to pm items: 0 of 51");
    try expectContains(coverage, "complies-se links to se items: 0 of 62");
}

// req: templates.iso29148
test "a project with requirements as ISO/IEC/IEEE 29148 describes them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);

    try testing.expectEqual(.ok, (try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"iso29148"} })).status);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems (5 items of 5 types, 4 link types");
    const coverage = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    // the examples trace from business needs down to a verification
    try expectContains(coverage, "refines links to business items: 1 of 1");
    try expectContains(coverage, "derives links to stakeholder items: 1 of 1");
    try expectContains(coverage, "verifies links to software items: 1 of 1");
}

test "eject writes the template's files into .skein/ and keeps the project's own" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try rootOf(a, tmp);
    _ = try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"langspec"} });
    try tmp.dir.createDirPath(testing.io, ".skein/types");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".skein/types/rule.toml", .data = "description = \"Ours\"\ncategories = [\"syntax\"]\n" });

    const ejected = try template_command.run(testing.io, a, .{ .common = .{ .root = root }, .what = .eject, .name = "langspec" });
    try testing.expectEqual(.ok, ejected.status);
    try expectContains(ejected.text, "6 files of 'langspec' written");
    try expectContains(ejected.text, "1 the project has already, left as it is");
    const rule = try tmp.dir.readFileAlloc(testing.io, ".skein/types/rule.toml", a, .limited(1 << 16));
    try expectContains(rule, "Ours");
    _ = try tmp.dir.readFileAlloc(testing.io, ".skein/links/shows.toml", a, .limited(1 << 16));

    const unused = try template_command.run(testing.io, a, .{ .common = .{ .root = root }, .what = .eject, .name = "other" });
    try testing.expectEqual(.misuse, unused.status);
    try expectContains(unused.text, "does not use the template 'other'");
}
