//! `skein coverage`: of the items that should be linked to or cited, how
//! many are, and which are not.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Json = @import("../output/Json.zig");
const Workspace = @import("Workspace.zig");
const coverage = @import("../graph/coverage.zig");
const Results = @import("../results/Results.zig");
const summary = @import("../results/summary.zig");
const gitlab_requirements = @import("../forge/gitlab_requirements.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Coverage) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();

    const profile = if (options.profile) |name| ws.project.schema.profile(name) orelse return .{
        .text = try arena.print("skein: there is no profile '{s}'\n", .{name}),
        .status = .misuse,
    } else null;
    const expectations = try coverage.compute(arena, &ws.project, &ws.graph, &ws.citations, profile);
    // results that cannot be read are the command's to report
    const before = ws.report.problems.items.len;
    const results = try Results.load(io, arena, ws.root, &ws.project, &ws.graph, options.results, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();
    const idx = try results.index(arena, &ws.graph, &ws.citations);
    const summaries = try summary.compute(arena, &results, &idx, &ws.project, &ws.graph, profile);
    const methods = try summary.byMethod(arena, &results, &idx, &ws.project, &ws.graph, profile);
    if (options.gitlab_requirements) |path| {
        const map = try gitlab_requirements.loadMap(io, arena, ws.root);
        if (map.len == 0) return .{ .text = try arena.print("skein: {s} maps no item to a GitLab requirement: run skein import gitlab-requirements first\n", .{gitlab_requirements.map_file}), .status = .misuse };
        Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = try gitlab_requirements.report(arena, map, &results, &idx, &ws.graph) }) catch |e|
            return .{ .text = try arena.print("skein: cannot write '{s}' ({s})\n", .{ path, @errorName(e) }), .status = .misuse };
    }

    if (options.json) {
        var j: Json = .{ .arena = arena };
        try j.beginObject();
        try j.key("profile");
        try j.optional(options.profile);
        try j.key("expectations");
        try j.beginArray();
        for (expectations) |e| {
            try j.beginObject();
            try j.key("kind");
            try j.string(@tagName(e.kind));
            try j.key("name");
            try j.string(e.name);
            try j.key("type");
            try j.string(e.item_type);
            try j.key("total");
            try j.integer(@intCast(e.total));
            try j.key("covered");
            try j.integer(@intCast(e.covered));
            try j.key("categories");
            try j.beginArray();
            for (e.categories) |c| {
                try j.beginObject();
                try j.key("category");
                try j.string(c.name);
                try j.key("total");
                try j.integer(@intCast(c.total));
                try j.key("covered");
                try j.integer(@intCast(c.covered));
                try j.endObject();
            }
            try j.endArray();
            try j.key("uncovered");
            try j.strings(e.uncovered);
            try j.key("waived");
            try j.strings(e.waived);
            try j.endObject();
        }
        try j.endArray();
        try j.key("results");
        try j.beginArray();
        for (summaries) |s| {
            try j.beginObject();
            try j.key("implementation");
            try j.string(s.implementation);
            try j.key("label");
            try j.string(s.label);
            try j.key("total");
            try j.integer(@intCast(s.total));
            try j.key("passed");
            try j.integer(@intCast(s.passed));
            try j.key("failed");
            try j.strings(s.failed);
            try j.key("untested");
            try j.strings(s.untested);
            try j.endObject();
        }
        try j.endArray();
        try j.key("unmatched");
        try j.integer(@intCast(idx.unmatched.len));
        try j.key("verification");
        try j.beginArray();
        for (methods) |m| {
            try j.beginObject();
            try j.key("method");
            try j.string(m.method);
            try j.key("total");
            try j.integer(@intCast(m.total));
            try j.key("verified");
            try j.integer(@intCast(m.verified));
            try j.key("unverified");
            try j.strings(m.unverified);
            try j.endObject();
        }
        try j.endArray();
        try j.endObject();
        return .{ .text = try j.finish() };
    }

    if (options.markdown) {
        var md: std.ArrayList(u8) = .empty;
        try md.appendSlice(arena, try markdown(arena, ws.name(), options.profile, expectations));
        if (summaries.len > 0) try md.appendSlice(arena, "\n| Results | Passed | Failed | Untested |\n| --- | ---: | ---: | ---: |\n");
        for (summaries) |s| try md.print(arena, "| {s} | {d} of {d} | {d} | {d} |\n", .{ s.label, s.passed, s.total, s.failed.len, s.untested.len });
        if (methods.len > 0) try md.appendSlice(arena, "\n| Verified by | Verified |\n| --- | ---: |\n");
        for (methods) |m| try md.print(arena, "| {s} | {d} of {d} |\n", .{ m.method, m.verified, m.total });
        for (summaries) |s| {
            if (s.failed.len == 0) continue;
            try md.print(arena, "\n<details>\n<summary>{d} failed in {s}</summary>\n\n", .{ s.failed.len, s.label });
            for (s.failed) |id| try md.print(arena, "- `{s}`\n", .{id});
            try md.appendSlice(arena, "\n</details>\n");
        }
        return .{ .text = md.items };
    }

    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "Coverage of {s}", .{ws.name()});
    if (options.profile) |name| try out.print(arena, ", profile {s}", .{name});
    try out.appendSlice(arena, "\n");
    if (expectations.len == 0) {
        try out.appendSlice(arena, "\nNothing is expected: no link type and no citation set has 'expected = true'.\n");
    }
    for (expectations) |e| {
        const what = switch (e.kind) {
            .link => "links to",
            .citation => "citations of",
        };
        try out.print(arena, "\n{s} {s} {s} items: ", .{ e.name, what, e.item_type });
        try ratio(arena, &out, e.covered, e.total);
        if (e.waived.len > 0) try out.print(arena, ", {d} waived", .{e.waived.len});
        try out.append(arena, '\n');
        for (e.categories) |c| {
            if (c.total == 0) continue;
            try out.print(arena, "  {s}: ", .{c.name});
            try ratio(arena, &out, c.covered, c.total);
            try out.append(arena, '\n');
        }
        if (e.uncovered.len > 0) try out.appendSlice(arena, "  without:\n");
        for (e.uncovered) |id| try out.print(arena, "    {s}\n", .{id});
        if (e.waived.len > 0) try out.appendSlice(arena, "  waived:\n");
        for (e.waived) |id| try out.print(arena, "    {s}\n", .{id});
    }
    for (summaries) |s| {
        try out.print(arena, "\nresults ({s}): {d} of {d} passed, {d} failed, {d} untested\n", .{ s.label, s.passed, s.total, s.failed.len, s.untested.len });
        if (s.failed.len > 0) try out.appendSlice(arena, "  failed:\n");
        for (s.failed) |id| try out.print(arena, "    {s}\n", .{id});
        if (s.untested.len > 0) try out.appendSlice(arena, "  untested:\n");
        for (s.untested) |id| try out.print(arena, "    {s}\n", .{id});
    }
    if (methods.len > 0) try out.appendSlice(arena, "\nverified as their method requires:\n");
    for (methods) |m| {
        try out.print(arena, "  {s}: ", .{m.method});
        try ratio(arena, &out, m.verified, m.total);
        try out.append(arena, '\n');
        if (m.unverified.len > 0) try out.appendSlice(arena, "    not verified:\n");
        for (m.unverified) |id| try out.print(arena, "      {s}\n", .{id});
    }
    if (idx.unmatched.len > 0) try out.print(arena, "\n{d} {s} to no item:\n", .{ idx.unmatched.len, if (idx.unmatched.len == 1) "result that belongs" else "results that belong" });
    for (idx.unmatched) |i| {
        const r = results.all[i];
        try out.print(arena, "  {s}  ({s}, result {d})\n", .{ r.label(), r.source, r.index });
    }
    return .{ .text = out.items };
}

/// The coverage as Markdown, for a job summary or a pull request: one
/// table, then the items without, folded away
fn markdown(arena: std.mem.Allocator, name: []const u8, profile: ?[]const u8, expectations: []const coverage.Expectation) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "## Coverage of {s}", .{name});
    if (profile) |p| try out.print(arena, ", profile {s}", .{p});
    try out.appendSlice(arena, "\n\n");
    if (expectations.len == 0) {
        try out.appendSlice(arena, "Nothing is expected: no link type and no citation set has `expected = true`.\n");
        return out.items;
    }
    try out.appendSlice(arena, "| Expected | Of | Covered | |\n| --- | --- | ---: | ---: |\n");
    for (expectations) |e| {
        try out.print(arena, "| `{s}` {s} | `{s}` items | {d} of {d}{s} | {s} |\n", .{ e.name, kindName(e.kind, true), e.item_type, e.covered, e.total, try waivedNote(arena, e), try percent(arena, e.covered, e.total) });
        for (e.categories) |c| {
            if (c.total == 0) continue;
            try out.print(arena, "| | {s} | {d} of {d} | {s} |\n", .{ c.name, c.covered, c.total, try percent(arena, c.covered, c.total) });
        }
    }
    for (expectations) |e| {
        if (e.uncovered.len == 0) continue;
        try out.print(arena, "\n<details>\n<summary>{d} <code>{s}</code> item{s} without a <code>{s}</code> {s}</summary>\n\n", .{
            e.uncovered.len, e.item_type, if (e.uncovered.len == 1) "" else "s", e.name, kindName(e.kind, false),
        });
        for (e.uncovered) |id| try out.print(arena, "- `{s}`\n", .{id});
        try out.appendSlice(arena, "\n</details>\n");
    }
    return out.items;
}

fn kindName(kind: coverage.Expectation.Kind, plural: bool) []const u8 {
    return switch (kind) {
        .link => if (plural) "links" else "link",
        .citation => if (plural) "citations" else "citation",
    };
}

/// ", 5 waived"; nothing when none is
pub fn waivedNote(arena: std.mem.Allocator, e: coverage.Expectation) ![]const u8 {
    return if (e.waived.len == 0) "" else arena.print(", {d} waived", .{e.waived.len});
}

/// "80%"; nothing when there is nothing to cover
fn percent(arena: std.mem.Allocator, covered: usize, total: usize) ![]const u8 {
    return if (total == 0) "" else arena.print("{d}%", .{covered * 100 / total});
}

/// "12 of 15 (80%)"
fn ratio(arena: std.mem.Allocator, out: *std.ArrayList(u8), covered: usize, total: usize) !void {
    try out.print(arena, "{d} of {d}", .{ covered, total });
    if (total > 0) try out.print(arena, " ({d}%)", .{covered * 100 / total});
}
