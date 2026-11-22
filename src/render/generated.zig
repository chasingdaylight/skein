//! Pages that skein generates from the graph, in the place a document
//! asks for them, as Markdown: a fenced code block of the language
//! `skein` holds the request.
//!
//!     ```skein
//!     list rule category=syntax
//!     ```
//!
//! - `list [TYPE...] [category=C] [status=S] [profile=P] [ATTRIBUTE=V]`:
//!   the items, with their category, status and first paragraph (a
//!   glossary is `list term`)
//! - `matrix LINKTYPE [profile=P]`: each item the link type may point to,
//!   with the items that link to it, gaps shown
//! - `coverage [profile=P]`: what `skein coverage` counts, with the items
//!   that are not covered
//! - `documents`: the register of controlled documents
//! - `gantt [...]`: the schedule as a Gantt chart (gantt.zig)
//! - `burndown MILESTONE`, `burnup MILESTONE`: a milestone's charts (burnchart.zig)
//! - `board [...]`, `roadmap [...]`: boards and the roadmap (boards.zig)

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Project = @import("../Project.zig");
const Schema = @import("../schema/Schema.zig");
const coverage = @import("../graph/coverage.zig");
const Results = @import("../results/Results.zig");
const summary = @import("../results/summary.zig");
const matrix_columns = @import("matrix_columns.zig");
const Control = @import("control.zig");
const boards = @import("boards.zig");
const burnchart = @import("burnchart.zig");
const gantt = @import("gantt.zig");
const walk = @import("../graph/walk.zig");

pub const Error = std.mem.Allocator.Error;

pub const Context = struct {
    arena: std.mem.Allocator,
    project: *const Project,
    graph: *const Graph,
    citations: *const Graph.Citations,
    /// where an item is linked to from the file the page is in
    href: *const fn (ctx: *const anyopaque, item: *const Item) Error![]const u8,
    href_ctx: *const anyopaque,
    /// where a link to the file `file` (from the root) leads, from the page
    fileHref: *const fn (ctx: *const anyopaque, file: []const u8) Error![]const u8,
    /// the profile a request without `profile=` is limited to: that of
    /// the rendering
    default_profile: ?*const Schema.Profile = null,
    /// test results, which a coverage page also shows
    results: ?ResultsOf = null,
    /// document control, for the register of documents
    control: ?*const Control = null,
    /// the schedule, for Gantt charts
    planning: ?*const gantt.Plan = null,
};

/// Test results, and which items they belong to
pub const ResultsOf = struct {
    results: *const Results,
    index: *const Results.Index,
};

/// Whether the first line of a code block asks for a generated page
pub fn isRequest(first_line: []const u8) bool {
    const s = std.mem.trim(u8, first_line, " \t\r");
    if (s.len < 3 or (!std.mem.startsWith(u8, s, "```") and !std.mem.startsWith(u8, s, "~~~"))) return false;
    const info = std.mem.trim(u8, std.mem.trimStart(u8, s, &.{s[0]}), " \t");
    return std.mem.eql(u8, info, "skein");
}

/// The Markdown that the request `text` (the lines inside the fences)
/// stands for; a request skein cannot read is said so, in its place
pub fn render(ctx: Context, text: []const u8) Error![]const u8 {
    const a = ctx.arena;
    var words: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (it.next()) |w| try words.append(a, w);
    if (words.items.len == 0) return problem(a, "the request is empty: list, matrix, coverage, documents, gantt, burndown, burnup, board or roadmap", .{});
    const what = words.items[0];
    const args = words.items[1..];
    if (std.mem.eql(u8, what, "list")) return list(ctx, args);
    if (std.mem.eql(u8, what, "matrix")) return matrix(ctx, args);
    if (std.mem.eql(u8, what, "coverage")) return coverageTable(ctx, args);
    if (std.mem.eql(u8, what, "documents")) return register(ctx, args);
    if (std.mem.eql(u8, what, "gantt")) return gantt.render(ctx, args);
    if (std.mem.eql(u8, what, "burndown")) return burnchart.render(ctx, .burndown, args);
    if (std.mem.eql(u8, what, "burnup")) return burnchart.render(ctx, .burnup, args);
    if (std.mem.eql(u8, what, "board")) return boards.board(ctx, args);
    if (std.mem.eql(u8, what, "roadmap")) return boards.roadmap(ctx, args);
    return problem(a, "'{s}' is no request skein knows: list, matrix, coverage, documents, gantt, burndown, burnup, board or roadmap", .{what});
}

fn problem(a: std.mem.Allocator, comptime fmt: []const u8, args: anytype) Error![]const u8 {
    return a.print("> **skein:** " ++ fmt ++ "\n", args);
}

/// What a request selects items by
pub const Filter = struct {
    types: std.ArrayList([]const u8) = .empty,
    category: ?[]const u8 = null,
    status: ?[]const u8 = null,
    profile: ?*const Schema.Profile = null,
    attributes: std.ArrayList(Item.Attribute) = .empty,

    pub fn passes(self: *const Filter, schema: *const Schema, graph: *const Graph, item: *const Item) bool {
        const item_type = schema.itemType(item.type_name) orelse return false;
        if (item.isTombstone(item_type)) return false;
        if (self.types.items.len > 0 and !Schema.names.contains(self.types.items, item.type_name)) return false;
        if (self.category) |c| if (!std.mem.eql(u8, item.category orelse "", c)) return false;
        if (self.status) |s| if (!std.mem.eql(u8, item.effectiveStatus(item_type), s)) return false;
        if (self.profile) |p| if (!inProfile(p, schema, graph, item)) return false;
        for (self.attributes.items) |want| {
            if (!item.hasValue(want.name, want.value)) return false;
        }
        return true;
    }
};

/// Reads `KEY=VALUE` words into `filter`, and bare words as item types;
/// a message when one cannot be read
pub fn readFilter(ctx: Context, args: []const []const u8, filter: *Filter, bare_types: bool) Error!?[]const u8 {
    const a = ctx.arena;
    const schema = &ctx.project.schema;
    for (args) |word| {
        const eq = std.mem.findScalar(u8, word, '=') orelse {
            if (!bare_types) return try problem(a, "'{s}' is not KEY=VALUE", .{word});
            if (schema.itemType(word) == null) return try problem(a, "there is no item type '{s}'", .{word});
            try filter.types.append(a, word);
            continue;
        };
        const key = word[0..eq];
        const value = word[eq + 1 ..];
        if (std.mem.eql(u8, key, "category")) {
            filter.category = value;
        } else if (std.mem.eql(u8, key, "status")) {
            filter.status = value;
        } else if (std.mem.eql(u8, key, "profile")) {
            filter.profile = schema.profile(value) orelse return try problem(a, "there is no profile '{s}'", .{value});
        } else {
            try filter.attributes.append(a, .{ .name = key, .value = value });
        }
    }
    return null;
}

fn splitList(a: std.mem.Allocator, text: []const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, text, ',');
    while (it.next()) |w| try out.append(a, w);
    return out.items;
}

/// `text` for a cell of a Markdown table: on one line, its `|` escaped
pub fn cell(a: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) Error!void {
    for (text) |c| switch (c) {
        '\r' => {},
        '\n' => try out.append(a, ' '),
        '|' => try out.appendSlice(a, "\\|"),
        else => try out.append(a, c),
    };
}

/// The first paragraph of an item's text
pub fn firstParagraph(text: []const u8) []const u8 {
    const end = std.mem.find(u8, text, "\n\n") orelse text.len;
    return std.mem.trim(u8, text[0..end], " \t\r\n");
}

pub fn link(ctx: Context, out: *std.ArrayList(u8), item: *const Item) Error!void {
    try out.print(ctx.arena, "[`{s}`]({s})", .{ item.id, try ctx.href(ctx.href_ctx, item) });
}

fn list(ctx: Context, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    // `columns=` chooses the columns, as for a matrix
    var columns: ?[]const []const u8 = null;
    var conditions: std.ArrayList([]const u8) = .empty;
    for (args) |word| {
        if (std.mem.startsWith(u8, word, "columns=")) columns = try splitList(a, word["columns=".len..]) else try conditions.append(a, word);
    }
    var filter: Filter = .{ .profile = ctx.default_profile };
    if (try readFilter(ctx, conditions.items, &filter, true)) |message| return message;
    var out: std.ArrayList(u8) = .empty;
    if (columns) |cols| {
        try out.appendSlice(a, "| Item |");
        for (cols) |c| try out.print(a, " {s} |", .{try matrix_columns.heading(a, c)});
        try out.appendSlice(a, "\n|");
        for (0..cols.len + 1) |_| try out.appendSlice(a, " --- |");
        try out.append(a, '\n');
    } else try out.appendSlice(a, "| Item | Category | Status | Text |\n| --- | --- | --- | --- |\n");
    var n: usize = 0;
    for (ctx.graph.items) |*item| {
        if (!filter.passes(&ctx.project.schema, ctx.graph, item)) continue;
        n += 1;
        try out.appendSlice(a, "| ");
        try link(ctx, &out, item);
        if (columns) |cols| {
            for (cols) |c| {
                try out.appendSlice(a, " | ");
                try matrix_columns.value(ctx, &out, item, c);
            }
            try out.appendSlice(a, " |\n");
            continue;
        }
        try out.appendSlice(a, " | ");
        try cell(a, &out, item.category orelse "");
        try out.appendSlice(a, " | ");
        try cell(a, &out, item.effectiveStatus(ctx.project.schema.itemType(item.type_name).?));
        try out.appendSlice(a, " | ");
        try cell(a, &out, firstParagraph(item.text));
        try out.appendSlice(a, " |\n");
    }
    if (n == 0) return a.print("*No item is selected.*\n", .{});
    return out.items;
}

fn matrix(ctx: Context, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    const schema = &ctx.project.schema;
    if (args.len == 0) return problem(a, "matrix needs a link type: matrix LINKTYPE", .{});
    const link_type = schema.linkType(args[0]) orelse return problem(a, "there is no link type '{s}'", .{args[0]});
    // the columns, apart from the conditions
    var columns: ?[]const []const u8 = null;
    var from_columns: []const []const u8 = &.{};
    var conditions: std.ArrayList([]const u8) = .empty;
    for (args[1..]) |word| {
        if (std.mem.startsWith(u8, word, "columns=")) {
            columns = try splitList(a, word["columns=".len..]);
        } else if (std.mem.startsWith(u8, word, "from.columns=")) {
            from_columns = try splitList(a, word["from.columns=".len..]);
        } else try conditions.append(a, word);
    }
    var filter: Filter = .{ .profile = ctx.default_profile };
    if (try readFilter(ctx, conditions.items, &filter, false)) |message| return message;
    for (link_type.to) |t| try filter.types.append(a, t);
    if (columns != null or from_columns.len > 0) return matrix_columns.render(.{ .ctx = ctx, .link_type = link_type, .columns = columns orelse &.{}, .from_columns = from_columns }, &filter);

    var out: std.ArrayList(u8) = .empty;
    try out.print(a, "| Item | Category | `{s}` from |\n| --- | --- | --- |\n", .{link_type.name});
    var rows: usize = 0;
    var covered: usize = 0;
    var waived: usize = 0;
    for (ctx.graph.items) |*item| {
        if (!filter.passes(schema, ctx.graph, item)) continue;
        rows += 1;
        try out.appendSlice(a, "| ");
        try link(ctx, &out, item);
        try out.appendSlice(a, " | ");
        try cell(a, &out, item.category orelse "");
        try out.appendSlice(a, " | ");
        var first = true;
        for (try walk.incoming(a, ctx.graph, item.id)) |in| {
            // a waiver that counts as this link type is listed as one, and named so
            const as = if (schema.linkType(in.link.type_name)) |t| t.counts_as else null;
            const counts = std.mem.eql(u8, in.link.type_name, link_type.name) or (as != null and std.mem.eql(u8, as.?, link_type.name));
            if (!counts) continue;
            if (!first) try out.appendSlice(a, ", ");
            first = false;
            if (!std.mem.eql(u8, in.link.type_name, link_type.name)) try out.print(a, "{s} by ", .{in.link.type_name});
            try link(ctx, &out, in.from);
        }
        if (first) {
            if (coverage.excusedBy(schema, ctx.graph, item.id, link_type.name)) |by| {
                try out.appendSlice(a, "waived by ");
                try link(ctx, &out, by);
                waived += 1;
            } else try out.appendSlice(a, "**none**");
        } else covered += 1;
        try out.appendSlice(a, " |\n");
    }
    if (rows == 0) return a.print("*No item is selected.*\n", .{});
    try out.print(a, "\n{d} of {d} with a `{s}` link", .{ covered, rows - waived, link_type.name });
    try out.appendSlice(a, if (waived > 0) try a.print(", {d} waived.\n", .{waived}) else ".\n");
    return out.items;
}

fn coverageTable(ctx: Context, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    var profile: ?*const Schema.Profile = ctx.default_profile;
    for (args) |word| {
        if (!std.mem.startsWith(u8, word, "profile=")) return problem(a, "coverage takes only profile=NAME", .{});
        profile = ctx.project.schema.profile(word["profile=".len..]) orelse return problem(a, "there is no profile '{s}'", .{word["profile=".len..]});
    }
    const expectations = try coverage.compute(a, ctx.project, ctx.graph, ctx.citations, profile);
    var out: std.ArrayList(u8) = .empty;
    try resultsTable(ctx, &out, profile);
    if (expectations.len == 0) {
        try out.appendSlice(a, "*Nothing is expected: no link type and no citation set has `expected = true`.*\n");
        return out.items;
    }
    if (out.items.len > 0) try out.append(a, '\n');
    try out.appendSlice(a, "| Expected | Of | Covered | |\n| --- | --- | ---: | ---: |\n");
    for (expectations) |e| {
        const kind = switch (e.kind) {
            .link => "links",
            .citation => "citations",
        };
        const waived = if (e.waived.len == 0) "" else try a.print(", {d} waived", .{e.waived.len});
        try out.print(a, "| `{s}` {s} | `{s}` items | {d} of {d}{s} | {s} |\n", .{ e.name, kind, e.item_type, e.covered, e.total, waived, try percent(a, e.covered, e.total) });
    }
    for (expectations) |e| {
        if (e.uncovered.len == 0) continue;
        try out.print(a, "\nWithout a `{s}` {s}: ", .{ e.name, switch (e.kind) {
            .link => "link",
            .citation => "citation",
        } });
        for (e.uncovered, 0..) |id, i| {
            if (i > 0) try out.appendSlice(a, ", ");
            if (ctx.graph.find(id)) |item| try link(ctx, &out, item) else try out.print(a, "`{s}`", .{id});
        }
        try out.appendSlice(a, ".\n");
    }
    return out.items;
}

/// What the test results say, per implementation, with links to the
/// items that failed; nothing without results
fn resultsTable(ctx: Context, out: *std.ArrayList(u8), profile: ?*const Schema.Profile) Error!void {
    const a = ctx.arena;
    const r = ctx.results orelse return;
    const summaries = try summary.compute(a, r.results, r.index, ctx.project, ctx.graph, profile);
    if (summaries.len == 0) return;
    try out.appendSlice(a, "| Results | Passed | Failed | Untested |\n| --- | ---: | ---: | ---: |\n");
    for (summaries) |s| try out.print(a, "| {s} | {d} of {d} | {d} | {d} |\n", .{ s.label, s.passed, s.total, s.failed.len, s.untested.len });
    for (summaries) |s| {
        if (s.failed.len == 0) continue;
        try out.print(a, "\nFailed in {s}: ", .{s.label});
        for (s.failed, 0..) |id, i| {
            if (i > 0) try out.appendSlice(a, ", ");
            if (ctx.graph.find(id)) |item| try link(ctx, out, item) else try out.print(a, "`{s}`", .{id});
        }
        try out.appendSlice(a, ".\n");
    }
}

/// The register of documents: each controlled one, with its identifier,
/// title, revision and last change, linked to its page
fn register(ctx: Context, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    if (args.len > 0) return problem(a, "documents takes nothing more", .{});
    const control = ctx.control orelse return a.print("*No document gives its identifier (`document` in its front matter).*\n", .{});
    if (control.documents.len == 0) return a.print("*No document gives its identifier (`document` in its front matter).*\n", .{});
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "| Document | Title | Revision | Last changed |\n| --- | --- | --- | --- |\n");
    for (control.documents) |d| {
        try out.print(a, "| {s} | [", .{d.id});
        try cell(a, &out, if (d.title.len > 0) d.title else d.file);
        try out.print(a, "]({s}) | {s} | {s} |\n", .{ try ctx.fileHref(ctx.href_ctx, d.file), d.revision, try control.changed(a, d.file) });
    }
    return out.items;
}

fn percent(a: std.mem.Allocator, covered: usize, total: usize) Error![]const u8 {
    return if (total == 0) "" else a.print("{d}%", .{covered * 100 / total});
}

test {
    _ = @import("_test/generated.zig");
    _ = @import("_test/matrix_columns.zig");
    _ = @import("_test/control.zig");
    _ = @import("_test/gantt.zig");
    _ = @import("_test/boards.zig");
}

/// Whether `item` is in `profile`, and so is the item it is a part of
fn inProfile(profile: *const Schema.Profile, schema: *const Schema, graph: *const Graph, item: *const Item) bool {
    const item_type = schema.itemType(item.type_name) orelse return false;
    if (!coverage.inProfile(profile, item, item_type)) return false;
    const whole = graph.find(item.parent orelse return true) orelse return true;
    return inProfile(profile, schema, graph, whole);
}
