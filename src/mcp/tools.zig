//! The tools `skein mcp` offers: skein's commands over the graph and its
//! editing commands, each answering in JSON. A tool runs the command as
//! the command line would, on the project the server was started in.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;

const Json = @import("../output/Json.zig");
const Results = @import("../results/Results.zig");
const Workspace = @import("../commands/Workspace.zig");
const approve = @import("../commands/approve.zig");
const check = @import("../commands/check.zig");
const cli = @import("../cli.zig");
const coverage = @import("../commands/coverage.zig");
const diff = @import("../commands/diff.zig");
const generated = @import("../render/generated.zig");
const link = @import("../commands/link.zig");
const move = @import("../commands/move.zig");
const new = @import("../commands/new.zig");
const result = @import("../commands/result.zig");
const trace = @import("../commands/trace.zig");

pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    /// a JSON Schema of the arguments
    input_schema: []const u8,
};

const no_args = "{\"type\":\"object\",\"properties\":{}}";

pub const all = [_]Tool{
    .{ .name = "items", .description = "List the project's items: ID, type, category, status, file, line and the first line of the text. Narrow by item type and by words in the ID or the text.", .input_schema = "{\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"description\":\"an item type\"},\"query\":{\"type\":\"string\",\"description\":\"words the ID or the text contains\"}}}" },
    .{ .name = "trace", .description = "An item with everything about it: its text, attributes, links both ways, references, citations, reviews, approvals, results, and all above and below it.", .input_schema = "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}" },
    .{ .name = "check", .description = "Check the project: its configuration, schema, items, links, references and citations. Run it after editing documents, item files or .skein/; each problem has its file, line and message, and a fix where skein knows one.", .input_schema = no_args },
    .{ .name = "coverage", .description = "Of the items that should be linked to or cited (tested, verified), how many are, and which are not.", .input_schema = "{\"type\":\"object\",\"properties\":{\"profile\":{\"type\":\"string\",\"description\":\"only the items of this profile\"}}}" },
    .{ .name = "impact", .description = "The items added, removed or changed since a commit (default: HEAD, so the changes not yet committed), and what the changes reach through the links.", .input_schema = "{\"type\":\"object\",\"properties\":{\"revision\":{\"type\":\"string\"}}}" },
    .{ .name = "new", .description = "Start an item: write its file, with the next free ID for a numbered type, or give the marker to start a paragraph with.", .input_schema = "{\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\"},\"id\":{\"type\":\"string\"},\"to\":{\"type\":\"string\",\"description\":\"the source of item files it goes to\"}},\"required\":[\"type\"]}" },
    .{ .name = "link", .description = "Add a link of a type from one item to another, in the marker or front matter of the first; refused when check would report it.", .input_schema = "{\"type\":\"object\",\"properties\":{\"from\":{\"type\":\"string\"},\"type\":{\"type\":\"string\"},\"to\":{\"type\":\"string\"}},\"required\":[\"from\",\"type\",\"to\"]}" },
    .{ .name = "move", .description = "Give an item another ID everywhere the old one is used: markers, references, links, citations, records.", .input_schema = "{\"type\":\"object\",\"properties\":{\"old\":{\"type\":\"string\"},\"new\":{\"type\":\"string\"},\"alias\":{\"type\":\"boolean\",\"description\":\"keep the old ID as an alias\"}},\"required\":[\"old\",\"new\"]}" },
    .{ .name = "result", .description = "Record a result a person obtained for an item (pass, fail or skip), such as a procedure carried out by hand.", .input_schema = "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"outcome\":{\"type\":\"string\",\"enum\":[\"pass\",\"fail\",\"skip\"]},\"note\":{\"type\":\"string\"},\"by\":{\"type\":\"string\"}},\"required\":[\"id\",\"outcome\"]}" },
    .{ .name = "approve", .description = "Record an approval of items as they are now, by a person, in a role where the type names roles.", .input_schema = "{\"type\":\"object\",\"properties\":{\"ids\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"by\":{\"type\":\"string\"},\"as\":{\"type\":\"string\"}},\"required\":[\"ids\"]}" },
};

pub const Answer = struct { text: []const u8, is_error: bool = false };

/// Runs the tool `name` with `args` on the project at `root`
pub fn call(io: Io, a: Allocator, root: []const u8, name: []const u8, args: json.Value) !Answer {
    const common: cli.Common = .{ .root = root };
    if (std.mem.eql(u8, name, "items")) return items(io, a, common, args);
    if (std.mem.eql(u8, name, "check")) return checkTool(io, a, common);
    if (std.mem.eql(u8, name, "trace")) return outcome(a, try trace.run(io, a, .{ .common = common, .id = text(args, "id") orelse return missing(a, "id"), .json = true }), true);
    if (std.mem.eql(u8, name, "coverage")) return outcome(a, try coverage.run(io, a, .{ .common = common, .profile = text(args, "profile"), .json = true }), true);
    if (std.mem.eql(u8, name, "impact")) {
        const revisions: []const []const u8 = if (text(args, "revision")) |r| try a.dupe([]const u8, &.{r}) else &.{};
        return outcome(a, try diff.run(io, a, .{ .common = common, .revisions = revisions, .impact = true, .json = true }), true);
    }
    if (std.mem.eql(u8, name, "new")) return outcome(a, try new.run(io, a, .{ .common = common, .type_name = text(args, "type") orelse return missing(a, "type"), .id = text(args, "id"), .to = text(args, "to") }), false);
    if (std.mem.eql(u8, name, "link")) return outcome(a, try link.run(io, a, .{
        .common = common,
        .from = text(args, "from") orelse return missing(a, "from"),
        .type_name = text(args, "type") orelse return missing(a, "type"),
        .to = text(args, "to") orelse return missing(a, "to"),
    }), false);
    if (std.mem.eql(u8, name, "move")) return outcome(a, try move.run(io, a, .{
        .common = common,
        .old = text(args, "old") orelse return missing(a, "old"),
        .new = text(args, "new") orelse return missing(a, "new"),
        .alias = if (field(args, "alias") == .bool) field(args, "alias").bool else null,
    }), false);
    if (std.mem.eql(u8, name, "result")) {
        const said = text(args, "outcome") orelse return missing(a, "outcome");
        const o = std.meta.stringToEnum(Results.Outcome, said) orelse return .{ .text = try a.print("{{\"error\":\"outcome: pass, fail or skip, not '{s}'\"}}", .{said}), .is_error = true };
        return outcome(a, try result.run(io, a, .{ .common = common, .id = text(args, "id") orelse return missing(a, "id"), .outcome = o, .note = text(args, "note"), .by = text(args, "by") }), false);
    }
    if (std.mem.eql(u8, name, "approve")) {
        var ids: std.ArrayList([]const u8) = .empty;
        const list = field(args, "ids");
        if (list == .array) for (list.array.items) |v| if (v == .string) try ids.append(a, v.string);
        if (ids.items.len == 0) return missing(a, "ids");
        return outcome(a, try approve.run(io, a, .{ .common = common, .ids = ids.items, .by = text(args, "by"), .as = text(args, "as") }), false);
    }
    return .{ .text = try a.print("{{\"error\":\"there is no tool '{s}'\"}}", .{name}), .is_error = true };
}

fn field(v: json.Value, name: []const u8) json.Value {
    if (v != .object) return .null;
    return v.object.get(name) orelse .null;
}

fn text(v: json.Value, name: []const u8) ?[]const u8 {
    const f = field(v, name);
    return if (f == .string and f.string.len > 0) f.string else null;
}

fn missing(a: Allocator, name: []const u8) Allocator.Error!Answer {
    return .{ .text = try a.print("{{\"error\":\"the argument '{s}' is needed\"}}", .{name}), .is_error = true };
}

/// What a command answered: its JSON as it is, or its text in JSON
fn outcome(a: Allocator, o: Workspace.Outcome, is_json: bool) Allocator.Error!Answer {
    const failed = o.status != .ok;
    if (is_json and !failed) return .{ .text = o.text };
    var j: Json = .{ .arena = a };
    try j.beginObject();
    try j.key("ok");
    try j.boolean(!failed);
    try j.key("output");
    try j.string(std.mem.trimEnd(u8, o.text, "\n"));
    try j.endObject();
    return .{ .text = try j.finish(), .is_error = failed };
}

fn checkTool(io: Io, a: Allocator, common: cli.Common) !Answer {
    var ws = switch (try Workspace.open(io, a, common)) {
        .ok => |ws| ws,
        .failed => |o| return outcome(a, o, false),
    };
    defer ws.close();
    try check.all(io, a, &ws);
    return .{ .text = try ws.report.renderJson(a) };
}

fn items(io: Io, a: Allocator, common: cli.Common, args: json.Value) !Answer {
    var ws = switch (try Workspace.open(io, a, common)) {
        .ok => |ws| ws,
        .failed => |o| return outcome(a, o, false),
    };
    defer ws.close();
    if (!ws.items_read) return .{ .text = try ws.report.renderJson(a), .is_error = true };
    const want_type = text(args, "type");
    const query = text(args, "query");
    var j: Json = .{ .arena = a };
    try j.beginArray();
    for (ws.graph.items) |*item| {
        const t = ws.project.schema.itemType(item.type_name) orelse continue;
        if (want_type) |w| if (!std.mem.eql(u8, w, item.type_name)) continue;
        if (query) |q| if (!containsIgnoringCase(item.id, q) and !containsIgnoringCase(item.text, q)) continue;
        try j.beginObject();
        try j.key("id");
        try j.string(item.id);
        try j.key("type");
        try j.string(item.type_name);
        try j.key("category");
        try j.optional(item.category);
        try j.key("status");
        try j.string(item.effectiveStatus(t));
        try j.key("file");
        try j.string(item.file);
        try j.key("line");
        try j.integer(item.line);
        try j.key("text");
        const first = generated.firstParagraph(item.text);
        try j.string(first[0 .. std.mem.findScalar(u8, first, '\n') orelse first.len]);
        try j.endObject();
    }
    try j.endArray();
    return .{ .text = try j.finish() };
}

fn containsIgnoringCase(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.findIgnoreCase(haystack, needle) != null;
}
