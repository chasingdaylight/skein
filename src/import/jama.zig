//! A Jama Connect project's items as rows for an import (#251), as a ReqIF
//! file gives them (import/reqif.zig): `id` (the item's document key, as
//! `PRJ-REQ-12`), `text` (its description, as Markdown), `title` (its
//! name), `jama` (its id, to find it again), `jama-type` (its item type),
//! and a column for each relationship type, with the IDs of the items the
//! relationships go to, of any type. The items are those of one item type
//! (`--jama-type REQ`), as a Skein type has one scheme of IDs: an import a
//! type, each to a type of its own.

const std = @import("std");

const Rows = @import("../commands/import_csv.zig").Rows;
const jama = @import("../forge/jama.zig");
const text = @import("../forge/jama_text.zig");

const Map = std.StringArrayHashMapUnmanaged([]const u8);

pub fn rows(arena: std.mem.Allocator, client: *const jama.Client, project: i64, only: []const u8) !Rows {
    // the names of item types and relationship types, by id
    var type_keys: std.AutoHashMapUnmanaged(i64, []const u8) = .empty;
    var type_names: std.AutoHashMapUnmanaged(i64, []const u8) = .empty;
    var why: []const u8 = "";
    for (try all(client, "itemtypes", &why) orelse return .{ .failed = why }) |t| {
        const id = jama.integer(jama.field(t, &.{"id"})) orelse continue;
        try type_keys.put(arena, id, jama.string(jama.field(t, &.{"typeKey"})) orelse "");
        try type_names.put(arena, id, jama.string(jama.field(t, &.{"display"})) orelse "");
    }
    var relation_names: std.AutoHashMapUnmanaged(i64, []const u8) = .empty;
    for (try all(client, "relationshiptypes", &why) orelse return .{ .failed = why }) |t| {
        const id = jama.integer(jama.field(t, &.{"id"})) orelse continue;
        try relation_names.put(arena, id, jama.string(jama.field(t, &.{"name"})) orelse try arena.print("relationship-{d}", .{id}));
    }

    var columns: std.ArrayList([]const u8) = .empty;
    try columns.appendSlice(arena, &.{ "id", "text", "title", "jama", "jama-type" });
    var records: std.ArrayList(Map) = .empty;
    // the row of each item by its Jama id, and its ID
    var index: std.AutoArrayHashMapUnmanaged(i64, usize) = .empty;
    var keys: std.AutoHashMapUnmanaged(i64, []const u8) = .empty;
    for (try all(client, try arena.print("items?project={d}", .{project}), &why) orelse return .{ .failed = why }) |item| {
        const id = jama.integer(jama.field(item, &.{"id"})) orelse continue;
        const type_id = jama.integer(jama.field(item, &.{"itemType"})) orelse continue;
        const key = type_keys.get(type_id) orelse "";
        const document_key = jama.string(jama.field(item, &.{"documentKey"})) orelse try arena.print("JAMA-{d}", .{id});
        // every item, for the relationships to it
        try keys.put(arena, id, document_key);
        if (!std.ascii.eqlIgnoreCase(only, key)) continue;
        var r: Map = .empty;
        try r.put(arena, "id", document_key);
        try r.put(arena, "text", try text.markdown(arena, jama.string(jama.field(item, &.{ "fields", "description" })) orelse ""));
        try r.put(arena, "title", jama.string(jama.field(item, &.{ "fields", "name" })) orelse "");
        try r.put(arena, "jama", try arena.print("{d}", .{id}));
        try r.put(arena, "jama-type", type_names.get(type_id) orelse key);
        try index.put(arena, id, records.items.len);
        try records.append(arena, r);
    }

    // relationships, as columns of the item they come from
    for (try all(client, try arena.print("relationships?project={d}", .{project}), &why) orelse return .{ .failed = why }) |rel| {
        const from = jama.integer(jama.field(rel, &.{"fromItem"})) orelse continue;
        const to = jama.integer(jama.field(rel, &.{"toItem"})) orelse continue;
        const t = jama.integer(jama.field(rel, &.{"relationshipType"})) orelse continue;
        const i = index.get(from) orelse continue;
        const target = keys.get(to) orelse continue;
        const column = relation_names.get(t) orelse try arena.print("relationship-{d}", .{t});
        if (!contains(columns.items, column)) try columns.append(arena, column);
        const r = &records.items[i];
        const before = r.get(column);
        try r.put(arena, column, if (before) |b| try arena.print("{s},{s}", .{ b, target }) else target);
    }

    var out: std.ArrayList([]const []const u8) = .empty;
    try out.append(arena, columns.items);
    for (records.items) |r| {
        const row = try arena.alloc([]const u8, columns.items.len);
        for (columns.items, row) |col, *cell| cell.* = r.get(col) orelse "";
        try out.append(arena, row);
    }
    return .{ .rows = out.items };
}

/// The list at `path`; null, with why in `why`, when Jama gives none
fn all(client: *const jama.Client, path: []const u8, why: *[]const u8) !?[]const std.json.Value {
    switch (try client.getAll(path)) {
        .found => |list| return list,
        .missing => why.* = try client.arena.print("Jama has no {s}", .{path}),
        .failed => |w| why.* = w,
    }
    return null;
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, s)) return true;
    return false;
}
