//! What a coding agent should know of a project's skein documents, written
//! for it: a section of the project's agent instructions file (`AGENTS.md`,
//! or `CLAUDE.md` where there is one and no `AGENTS.md`), between markers
//! that let it be written again; or a skill file, for agents that read
//! skills. It says what skein is, how markers and references are written,
//! the project's item types, link types and citations, and what to run.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Project = @import("../Project.zig");

pub const begin = "<!-- skein: begin; written by 'skein agents', which writes it again -->";
pub const end = "<!-- skein: end -->";

/// The skill file, for agents that read skills
pub const skill_file = ".claude/skills/skein/SKILL.md";

/// The text about the project, without the markers
pub fn body(a: Allocator, project: *const Project, todo: []const []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "## Skein\n\n");
    try out.appendSlice(a, "This repository keeps its requirements, specifications and their traceability with Skein (<https://github.com/chasingdaylight/skein>). An item is a paragraph or list entry of a Markdown document, or a Markdown file of its own, with a marker:\n\n");
    try out.appendSlice(a, "```markdown\n%TYPE[ID words key=value,value] The text of the item.\n\n- %TYPE[.part] A part of the item above, as a list entry.\n```\n\n");
    try out.appendSlice(a, "- A marker is `%`, the item type, and in brackets the ID, then bare words (the category and the status) and `key=value` (an attribute, or links to the items named, separated by commas). `.part` names a part by its whole's ID.\n");
    try out.appendSlice(a, "- `%[ID]` in text refers to an item; `%[ID some words]` shows the words in its place.\n");
    try out.appendSlice(a, "- IDs never change by hand: `skein move OLD NEW` renames one everywhere. `skein new TYPE` starts an item, `skein link FROM TYPE TO` adds a link.\n");
    if (project.sources.len > 0) {
        try out.appendSlice(a, "- Items are in ");
        for (project.sources, 0..) |s, i| {
            if (i > 0) try out.appendSlice(a, ", ");
            try out.print(a, "`{s}/`", .{s.path});
            if (s.kind == .items) try out.appendSlice(a, " (a file per item)");
            if (s.read_only) try out.appendSlice(a, " (read-only: an external standard, not to be edited)");
        }
        try out.appendSlice(a, ".\n");
    }
    const schema = &project.schema;
    if (schema.types.len > 0) {
        try out.appendSlice(a, "\nItem types:\n\n");
        for (schema.types) |t| {
            try out.print(a, "- `{s}`", .{t.name});
            if (t.description.len > 0) try out.print(a, ": {s}", .{t.description});
            if (t.categories.len > 0) try out.print(a, "; categories {s}", .{try quoted(a, t.categories)});
            try out.print(a, "; statuses {s}", .{try quoted(a, t.statuses)});
            if (t.attributes.len > 0) {
                var names: std.ArrayList([]const u8) = .empty;
                for (t.attributes) |attr| try names.append(a, attr.name);
                try out.print(a, "; attributes {s}", .{try quoted(a, names.items)});
            }
            try out.appendSlice(a, ".\n");
        }
    }
    if (schema.links.len > 0) {
        try out.appendSlice(a, "\nLink types (`key=ID` in a marker):\n\n");
        for (schema.links) |l| {
            try out.print(a, "- `{s}`", .{l.name});
            if (l.from.len > 0) try out.print(a, " from {s}", .{try quoted(a, l.from)});
            if (l.to.len > 0) try out.print(a, " to {s}", .{try quoted(a, l.to)});
            if (l.description.len > 0) try out.print(a, ": {s}", .{l.description});
            if (l.required) try out.appendSlice(a, " (required)");
            try out.appendSlice(a, ".\n");
        }
    }
    if (project.citations.len > 0) {
        try out.appendSlice(a, "\nCode and tests cite items in comments:\n\n");
        for (project.citations) |c| {
            try out.print(a, "- `{s}`: files under `{s}/` ending in {s}, `{s} ID, ID`.\n", .{ c.name, c.path, try quoted(a, c.files), c.marker });
        }
    }
    try out.appendSlice(a, "\nAfter editing documents, item files or `.skein/`, run `skein check` and mend what it reports. `skein trace ID` shows an item with everything above and below it, and `skein coverage` what is not yet linked or cited. `skein mcp` offers all of this as tools to agents that speak the Model Context Protocol.\n");
    try out.appendSlice(a, "\nApprovals and reviews are people's, never an agent's: do not run `skein approve`, `skein review` or `skein clear`, and do not edit `.skein/approvals/`, `.skein/reviews/`, `.skein/signers.toml` or `.skein/baselines/`. Say which items need approving or which links reviewing, and leave it to the people who do it.\n");
    if (todo.len > 0) {
        try out.appendSlice(a, "\nStill to do in setting up this project (`skein agents` writes this list again):\n\n");
        for (todo) |t| try out.print(a, "- {s}\n", .{t});
    }
    return out.items;
}

fn quoted(a: Allocator, names: []const []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (names, 0..) |n, i| {
        if (i > 0) try out.appendSlice(a, ", ");
        try out.print(a, "`{s}`", .{n});
    }
    return out.items;
}

/// The file the section goes in: `AGENTS.md`, or `CLAUDE.md` where it is
/// there and `AGENTS.md` is not
pub fn targetOf(io: Io, root: Io.Dir) []const u8 {
    if (root.access(io, "AGENTS.md", .{})) |_| return "AGENTS.md" else |_| {}
    if (root.access(io, "CLAUDE.md", .{})) |_| return "CLAUDE.md" else |_| {}
    return "AGENTS.md";
}

/// `existing` (the file's text, empty when there is none) with the section
/// in place of the one there, or after what is there
pub fn merge(a: Allocator, existing: []const u8, section_body: []const u8) Allocator.Error![]const u8 {
    const section = try std.mem.concat(a, u8, &.{ begin, "\n\n", section_body, "\n", end, "\n" });
    if (std.mem.find(u8, existing, begin)) |b| {
        if (std.mem.findPos(u8, existing, b, end)) |e| {
            var after = e + end.len;
            if (after < existing.len and existing[after] == '\n') after += 1;
            return std.mem.concat(a, u8, &.{ existing[0..b], section, existing[after..] });
        }
    }
    if (existing.len == 0) return section;
    const sep = if (std.mem.endsWith(u8, existing, "\n\n")) "" else if (std.mem.endsWith(u8, existing, "\n")) "\n" else "\n\n";
    return std.mem.concat(a, u8, &.{ existing, sep, section });
}

/// The skill file's text
pub fn skill(a: Allocator, section_body: []const u8) Allocator.Error![]const u8 {
    return std.mem.concat(a, u8, &.{
        "---\nname: skein\ndescription: Reading and writing this repository's Skein documents: item markers, references, links, and the skein commands that check and edit them. Use when editing Markdown with %type[...] markers or files under .skein/.\n---\n\n",
        section_body,
    });
}

const testing = std.testing;

test merge {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try merge(a, "# Notes\n", "B1\n");
    try testing.expectEqualStrings("# Notes\n\n" ++ begin ++ "\n\nB1\n\n" ++ end ++ "\n", first);
    // written again: in place, what is around it kept
    const again = try merge(a, try std.mem.concat(a, u8, &.{ first, "More.\n" }), "B2\n");
    try testing.expectEqualStrings("# Notes\n\n" ++ begin ++ "\n\nB2\n\n" ++ end ++ "\nMore.\n", again);
    try testing.expectEqualStrings(begin ++ "\n\nB\n\n" ++ end ++ "\n", try merge(a, "", "B\n"));
}
