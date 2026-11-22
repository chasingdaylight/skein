//! `skein move OLD NEW`: gives an item another ID, everywhere the old one
//! is used: its marker or front matter, references in text, links,
//! citations in code and tests, and the review and approval records. The
//! parts whose IDs continue the old ID follow it.
//!
//! A rename is not a change to what anything says: the reviews and the
//! approvals that were current before it are current after it.

const std = @import("std");
const Io = std.Io;

const Approvals = @import("../graph/Approvals.zig");
const cli = @import("../cli.zig");
const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Marker = @import("../markdown/Marker.zig");
const Report = @import("../Report.zig");
const Reviews = @import("../graph/Reviews.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");
const fingerprint = @import("../graph/fingerprint.zig");
const alias = @import("../edit/alias.zig");
const rename = @import("../edit/rename.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Move) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    // what is wrong with the items is for `check`; the schema must be sound
    if (!ws.items_read) return ws.problems();

    const item = ws.graph.find(options.old) orelse return misuse(arena, "there is no item '{s}'", .{options.old});
    if (std.mem.eql(u8, options.old, options.new)) return misuse(arena, "'{s}' is its ID already", .{options.new});
    const item_type = ws.project.schema.itemType(item.type_name) orelse return misuse(arena, "'{s}' is of a type the schema does not have", .{options.old});
    if (!item_type.idMatches(options.new)) return misuse(arena, "'{s}' is not spelled as the IDs of a '{s}' are", .{ options.new, item.type_name });

    // the item, and the parts whose IDs continue its ID
    var renames: rename.Renames = .empty;
    try renames.put(arena, options.old, options.new);
    try addParts(arena, &ws.graph, item, options.old, options.new, &renames);
    for (renames.values()) |new_id| {
        if (ws.graph.find(new_id) != null and !renames.contains(new_id)) return misuse(arena, "the ID '{s}' is taken", .{new_id});
        if (ws.graph.formerly(new_id)) |had| return misuse(arena, "'{s}' is a former ID of '{s}'; take it out of its aliases first", .{ new_id, had.id });
    }

    // the records, and which of them are current, before anything changes
    const before = ws.report.problems.items.len;
    const reviews = try Reviews.load(io, arena, ws.root, &ws.report);
    const approvals = try Approvals.load(io, arena, ws.root, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();
    const kept = try Kept.find(arena, &ws, &reviews, &approvals, &renames);

    // every line that names one of the IDs
    var edits: Edits = .{ .arena = arena };
    try edits.collect(&ws, &renames);

    var changed: std.ArrayList(Changed) = .empty;
    var places: usize = 0;
    for (edits.files.keys(), edits.files.values()) |file, *lines| {
        const text = ws.root.readFileAlloc(io, file, arena, .limited(1 << 26)) catch |e| return misuse(arena, "cannot read '{s}' ({s})", .{ file, @errorName(e) });
        const result = try rewrite(arena, text, lines, &renames, if (std.mem.eql(u8, file, item.file)) item else null, options.new);
        if (result.count == 0) continue;
        places += result.count;
        try changed.append(arena, .{ .file = file, .text = result.text });
    }

    // the old IDs kept as aliases: by default when others can cite the project
    const keep = options.alias orelse (ws.project.id != null);
    if (keep) for (renames.keys()) |old_id| {
        const renamed = ws.graph.find(old_id).?;
        for (changed.items) |*c| {
            if (!std.mem.eql(u8, c.file, renamed.file)) continue;
            c.text = if (renamed.in_document) try onLine(arena, c.text, renamed.line, old_id) else try alias.frontMatter(arena, c.text, old_id);
        }
    };

    // a read-only source is imported again, not edited
    for (changed.items) |c| {
        if (ws.project.readOnlySource(c.file)) |s| return misuse(arena, "the rename would change {s}, which is in the read-only source '{s}'", .{ c.file, s.path });
    }
    // nothing is written before everything is known to be writable
    for (changed.items) |c| try ws.root.writeFile(io, .{ .sub_path = c.file, .data = c.text });
    try renameItemFiles(io, arena, &ws, &renames);
    try kept.write(io, arena, options.common, &ws, &reviews, &approvals, &renames);

    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "skein: {s} is now {s}", .{ options.old, options.new });
    if (renames.count() > 1) try out.print(arena, ", with {d} part{s}", .{ renames.count() - 1, if (renames.count() == 2) "" else "s" });
    try out.print(arena, ": {d} place{s} in {d} file{s}", .{ places, if (places == 1) "" else "s", changed.items.len, if (changed.items.len == 1) "" else "s" });
    try out.appendSlice(arena, if (keep) "; the old ID is kept as an alias\n" else "\n");
    return .{ .text = out.items };
}

/// `text` with `old` added to the aliases of the marker on line `number`
fn onLine(arena: std.mem.Allocator, text: []const u8, number: u32, old: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    var n: u32 = 1;
    while (it.next()) |line| : (n += 1) {
        if (n > 1) try out.append(arena, '\n');
        try out.appendSlice(arena, if (n == number) try alias.marker(arena, line, old) else line);
    }
    return out.items;
}

const Changed = struct { file: []const u8, text: []const u8 };

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

/// Adds the parts of `item`, and theirs, whose IDs continue `old`
fn addParts(arena: std.mem.Allocator, graph: *const Graph, item: *const Item, old: []const u8, new: []const u8, renames: *rename.Renames) !void {
    for (item.parts) |id| {
        const part = graph.find(id) orelse continue;
        if (id.len > old.len and std.mem.startsWith(u8, id, old) and id[old.len] == '.') {
            try renames.put(arena, id, try arena.print("{s}{s}", .{ new, id[old.len..] }));
        }
        try addParts(arena, graph, part, old, new, renames);
    }
}

/// The lines of each file that name an ID to rename
const Edits = struct {
    arena: std.mem.Allocator,
    /// by file: the lines (1-based); line 0 stands for the front matter
    files: std.array_hash_map.String(std.AutoHashMapUnmanaged(u32, void)) = .empty,

    fn add(self: *Edits, file: []const u8, line: u32) !void {
        const entry = try self.files.getOrPut(self.arena, file);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.put(self.arena, line, {});
    }

    fn collect(self: *Edits, ws: *const Workspace, renames: *const rename.Renames) !void {
        for (ws.graph.items) |*item| {
            const renamed = renames.contains(item.id);
            // an item file names its ID and its links in its front matter
            const own_line: u32 = if (item.in_document) item.line else 0;
            if (renamed) try self.add(item.file, own_line);
            for (item.links) |link| {
                if (!renames.contains(link.target)) continue;
                try self.add(item.file, if (!item.in_document) 0 else if (link.line > 0) link.line else item.line);
            }
            for (item.references) |r| {
                if (renames.contains(r.target)) try self.add(item.file, r.line);
            }
        }
        for (ws.graph.mentions) |m| {
            if (renames.contains(m.target)) try self.add(m.file, m.line);
        }
        for (ws.citations.all) |c| {
            if (renames.contains(c.target)) try self.add(c.file, c.line);
        }
    }
};

/// `text` with the IDs renamed on `lines`. `moved` is the item being
/// moved when this is its file: its marker may name it by a leading dot,
/// which is then written anew.
fn rewrite(
    arena: std.mem.Allocator,
    text: []const u8,
    lines: *const std.AutoHashMapUnmanaged(u32, void),
    renames: *const rename.Renames,
    moved: ?*const Item,
    new_id: []const u8,
) !rename.Result {
    var out: std.ArrayList(u8) = .empty;
    var count: usize = 0;
    var number: u32 = 1;
    var in_front_matter = lines.contains(0) and std.mem.startsWith(u8, text, "+++");
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| : (number += 1) {
        if (number > 1) try out.append(arena, '\n');
        var current = line;
        if (moved) |item| {
            if (item.in_document and item.line == number) {
                if (try relativeMarker(arena, current, item, new_id)) |rewritten| {
                    current = rewritten;
                    count += 1;
                }
            }
        }
        if (lines.contains(number) or in_front_matter) {
            const result = try rename.line(arena, current, renames);
            current = result.text;
            count += result.count;
        }
        if (in_front_matter and number > 1 and std.mem.eql(u8, std.mem.trimEnd(u8, line, " \t\r"), "+++")) in_front_matter = false;
        try out.appendSlice(arena, current);
    }
    return .{ .text = out.items, .count = count };
}

/// The marker line of a part that names itself by a leading dot
/// (`%rule[.as]`), with its new name: still with the dot when the new ID
/// continues the same containing item's, else in full. Null when the
/// marker gives the ID in full, which the renaming of whole IDs handles.
fn relativeMarker(arena: std.mem.Allocator, line: []const u8, item: *const Item, new_id: []const u8) !?[]const u8 {
    const start = Marker.startIn(line) orelse return null;
    const marker = try Marker.parse(arena, line[start..]) orelse return null;
    if (marker.id.len == 0 or marker.id[0] != '.') return null;
    const at = std.mem.findPos(u8, line, start, marker.id) orelse return null;
    const parent = item.parent orelse return null;
    const continues = new_id.len > parent.len and std.mem.startsWith(u8, new_id, parent) and new_id[parent.len] == '.';
    const written = if (continues) new_id[parent.len..] else new_id;
    return try arena.print("{s}{s}{s}", .{ line[0..at], written, line[at + marker.id.len ..] });
}

/// An item file named after its ID is named after the new one
fn renameItemFiles(io: Io, arena: std.mem.Allocator, ws: *Workspace, renames: *const rename.Renames) !void {
    for (ws.graph.items) |*item| {
        if (item.in_document) continue;
        const new_id = renames.get(item.id) orelse continue;
        const name = Io.Dir.path.basenamePosix(item.file);
        if (!std.mem.eql(u8, name[0 .. name.len - @min(name.len, 3)], item.id) or !std.ascii.endsWithIgnoreCase(name, ".md")) continue;
        const dir = Io.Dir.path.dirnamePosix(item.file);
        const to = if (dir) |d| try arena.print("{s}/{s}{s}", .{ d, new_id, name[name.len - 3 ..] }) else try arena.print("{s}{s}", .{ new_id, name[name.len - 3 ..] });
        try ws.root.rename(item.file, ws.root, to, io);
    }
}

/// The reviews and approvals that are current, to be kept so
const Kept = struct {
    /// "from\ntype\ntarget", with the old IDs
    reviews: std.array_hash_map.String(void) = .empty,
    /// "item\nby", with the old ID
    approvals: std.array_hash_map.String(void) = .empty,

    fn find(arena: std.mem.Allocator, ws: *const Workspace, reviews: *const Reviews, approvals: *const Approvals, renames: *const rename.Renames) !Kept {
        _ = renames;
        var kept: Kept = .{};
        const schema = &ws.project.schema;
        for (ws.graph.items) |*item| {
            for (item.links) |link| {
                const state = try reviews.stateOf(arena, schema, &ws.graph, item, link) orelse continue;
                if (state == .reviewed) try kept.reviews.put(arena, try arena.print("{s}\n{s}\n{s}", .{ item.id, link.type_name, link.target }), {});
            }
        }
        for (approvals.all.items) |approval| {
            const item = ws.graph.find(approval.item) orelse continue;
            if (try Approvals.isCurrent(arena, &ws.graph, schema, approval, item)) {
                try kept.approvals.put(arena, try arena.print("{s}\n{s}", .{ approval.item, approval.by }), {});
            }
        }
        return kept;
    }

    /// Writes the records again, with the new IDs, from the project as
    /// it is after the renaming
    fn write(
        self: *const Kept,
        io: Io,
        arena: std.mem.Allocator,
        common: cli.Common,
        old: *const Workspace,
        reviews: *const Reviews,
        approvals: *const Approvals,
        renames: *const rename.Renames,
    ) !void {
        if (reviews.records.count() == 0 and approvals.all.items.len == 0) return;
        var now = switch (try Workspace.open(io, arena, common)) {
            .ok => |ws| ws,
            // the renaming cannot make the project unreadable; if it did, the records stay as they were
            .failed => return,
        };
        defer now.close();
        if (!now.items_read) return;
        const schema = &now.project.schema;

        var review_files: std.array_hash_map.String(void) = .empty;
        var approval_files: std.array_hash_map.String(void) = .empty;
        for ([_]*const Graph{ &old.graph, &now.graph }) |graph| {
            for (graph.items) |*item| {
                try review_files.put(arena, try Reviews.fileOf(arena, item), {});
                try approval_files.put(arena, try Approvals.fileOf(arena, item), {});
            }
        }

        var new_reviews: Reviews = .{};
        for (reviews.records.keys(), reviews.records.values()) |key, recorded| {
            var parts = std.mem.splitScalar(u8, key, '\n');
            const from = parts.next().?;
            const link_type = parts.next().?;
            const target = parts.next().?;
            const new_target = renames.get(target) orelse target;
            var fp: []const u8 = recorded;
            if (self.reviews.contains(key)) {
                if (now.graph.find(new_target)) |item| fp = try arena.dupe(u8, &try fingerprint.of(arena, &now.graph, schema, item));
            }
            try new_reviews.put(arena, renames.get(from) orelse from, link_type, new_target, fp);
        }
        if (reviews.records.count() > 0) try new_reviews.write(io, arena, now.root, schema, &now.graph, review_files.keys());

        var new_approvals: Approvals = .{};
        for (approvals.all.items) |approval| {
            var moved = approval;
            moved.item = renames.get(approval.item) orelse approval.item;
            if (self.approvals.contains(try arena.print("{s}\n{s}", .{ approval.item, approval.by }))) {
                if (now.graph.find(moved.item)) |item| moved.fingerprint = try arena.dupe(u8, &try fingerprint.of(arena, &now.graph, schema, item));
            }
            try new_approvals.all.append(arena, moved);
        }
        if (approvals.all.items.len > 0) try new_approvals.write(io, arena, now.root, &now.graph, approval_files.keys());
    }
};

test {
    _ = rename;
    _ = Report;
    _ = Schema;
    _ = @import("_test/move.zig");
}
