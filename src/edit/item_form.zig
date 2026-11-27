//! Writing an item form (edit/form.zig) into the project's files: a new item
//! started as `skein new` starts it, then each value that differs from the
//! item's written into its marker or its front matter, or taken out.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Item = @import("../graph/Item.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("../commands/Workspace.zig");
const attribute = @import("attribute.zig");
const form = @import("form.zig");
const new_command = @import("../commands/new.zig");

pub const Outcome = union(enum) {
    written: struct { id: []const u8, file: []const u8, line: usize },
    /// why it was not written
    refused: []const u8,
};

const Edited = union(enum) { text: []const u8, refused: []const u8 };

pub const Preview = union(enum) {
    /// the item's file as the form would write it
    text: struct { file: []const u8, text: []const u8 },
    /// a new item, which nothing refuses before it is started
    new,
    refused: []const u8,
};

/// What `write` would write, without writing it
pub fn preview(io: Io, a: Allocator, ws: *Workspace, p: form.Save) Allocator.Error!Preview {
    const schema = &ws.project.schema;
    const t = schema.itemType(p.type) orelse return .{ .refused = try a.print("skein: there is no item type '{s}'", .{p.type}) };
    if (try invalid(a, schema, t, ws, p)) |why| return .{ .refused = why };
    if (p.new) return .new;
    const item = ws.graph.find(p.id) orelse return .{ .refused = try a.print("skein: there is no item '{s}'", .{p.id}) };
    return switch (try edited(io, a, ws, t, item, p)) {
        .text => |x| .{ .text = .{ .file = item.file, .text = x } },
        .refused => |why| .{ .refused = why },
    };
}

pub fn write(io: Io, a: Allocator, ws: *Workspace, p: form.Save) Allocator.Error!Outcome {
    const schema = &ws.project.schema;
    const t = schema.itemType(p.type) orelse return refuse(a, "there is no item type '{s}'", .{p.type});
    if (try invalid(a, schema, t, ws, p)) |why| return .{ .refused = why };
    if (!p.new) {
        const item = ws.graph.find(p.id) orelse return refuse(a, "there is no item '{s}'", .{p.id});
        if (ws.project.readOnlySource(item.file)) |src| return refuse(a, "{s} is in the read-only source '{s}'", .{ item.id, src.path });
        return apply(io, a, ws, t, item, p);
    }

    // a new item: its file, or its marker at the end of a document
    const started = new_command.run(io, a, .{ .common = .{ .root = ws.root_path }, .type_name = t.name, .id = if (p.id.len > 0) p.id else null }) catch return refuse(a, "the item could not be started", .{});
    if (started.status != .ok) return .{ .refused = std.mem.trimEnd(u8, started.text, "\n") };
    const said = std.mem.trimEnd(u8, started.text, "\n");
    var new_id: []const u8 = "";
    if (std.mem.startsWith(u8, said, "%")) {
        if (p.document.len == 0) return refuse(a, "a '{s}' is written in a document: choose one", .{t.name});
        if (ws.project.readOnlySource(p.document) != null) return refuse(a, "{s} is in a read-only source", .{p.document});
        const old = ws.root.readFileAlloc(io, p.document, a, .limited(1 << 26)) catch return refuse(a, "{s} cannot be read", .{p.document});
        const sep = if (old.len == 0 or std.mem.endsWith(u8, old, "\n\n")) "" else if (std.mem.endsWith(u8, old, "\n")) "\n" else "\n\n";
        const text = if (p.text.len > 0) p.text else "(text to come)";
        ws.root.writeFile(io, .{ .sub_path = p.document, .data = try std.mem.concat(a, u8, &.{ old, sep, said, " ", text, "\n" }) }) catch return refuse(a, "{s} cannot be written", .{p.document});
        new_id = said[std.mem.findScalar(u8, said, '[').? + 1 .. said.len - 1];
    } else {
        // an item file: its text after its front matter
        if (p.text.len > 0) {
            const old = ws.root.readFileAlloc(io, said, a, .limited(1 << 26)) catch "";
            ws.root.writeFile(io, .{ .sub_path = said, .data = try std.mem.concat(a, u8, &.{ old, p.text, "\n" }) }) catch {};
        }
        new_id = if (p.id.len > 0) p.id else std.Io.Dir.path.stem(said);
    }
    // the project again, with the new item in it
    const reopened = Workspace.open(io, a, .{ .root = ws.root_path }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return refuse(a, "the project cannot be read again", .{}),
    };
    var again = switch (reopened) {
        .ok => |w| w,
        .failed => return refuse(a, "the project cannot be read again", .{}),
    };
    defer again.close();
    const item = again.graph.find(new_id) orelse return refuse(a, "the new item '{s}' cannot be found", .{new_id});
    return apply(io, a, &again, again.project.schema.itemType(t.name).?, item, p);
}

fn refuse(a: Allocator, comptime fmt: []const u8, args: anytype) Allocator.Error!Outcome {
    return .{ .refused = try a.print("skein: " ++ fmt, args) };
}

/// What `check` would refuse at once: words and keys the type does not have,
/// links to items there are not
fn invalid(a: Allocator, schema: *const Schema, t: *const Schema.ItemType, ws: *const Workspace, p: form.Save) Allocator.Error!?[]const u8 {
    if (p.category.len > 0 and !Schema.names.contains(t.categories, p.category)) return try a.print("skein: '{s}' is not a category of a '{s}'", .{ p.category, t.name });
    if (p.status.len > 0 and !Schema.names.contains(t.statuses, p.status)) return try a.print("skein: '{s}' is not a status of a '{s}'", .{ p.status, t.name });
    if (p.verification.len > 0 and !Schema.names.contains(t.verification, p.verification)) return try a.print("skein: '{s}' is not a verification method of a '{s}'", .{ p.verification, t.name });
    for (p.attributes.map.keys()) |name| if (t.attribute(name) == null) return try a.print("skein: '{s}' is not an attribute of a '{s}'", .{ name, t.name });
    for (p.links.map.keys(), p.links.map.values()) |name, targets| {
        const l = schema.linkType(name) orelse return try a.print("skein: there is no link type '{s}'", .{name});
        if (l.from.len > 0 and !Schema.names.contains(l.from, t.name)) return try a.print("skein: a '{s}' cannot have a '{s}' link", .{ t.name, name });
        for (targets) |target| if (std.mem.findScalar(u8, target, ':') == null and ws.graph.find(target) == null) return try a.print("skein: {s}: there is no item '{s}'", .{ name, target });
    }
    return null;
}

/// The item's file with each value of the form that differs from the item's
fn edited(io: Io, a: Allocator, ws: *const Workspace, t: *const Schema.ItemType, item: *const Item, p: form.Save) Allocator.Error!Edited {
    var text: []const u8 = ws.root.readFileAlloc(io, item.file, a, .limited(1 << 26)) catch return .{ .refused = try a.print("skein: {s} cannot be read", .{item.file}) };
    const edit: Edit = .{ .a = a, .item = item };
    text = try edit.word(text, "category", item.category, p.category) orelse return .{ .refused = try manual(a, item, "category") };
    text = try edit.word(text, "status", item.status, p.status) orelse return .{ .refused = try manual(a, item, "status") };
    text = try edit.value(text, "verification", item.verification orelse "", p.verification, .string) orelse return .{ .refused = try manual(a, item, "verification") };
    for (t.attributes) |attr| {
        const want = p.attributes.map.get(attr.name) orelse "";
        const have = if (item.attribute(attr.name)) |_| try joined(a, item, attr.name) else "";
        if (std.mem.eql(u8, want, have)) continue;
        const kind: Edit.Kind = if (attr.list) .list else switch (attr.kind) {
            .string => .string,
            .integer, .boolean, .date => .raw,
        };
        text = try edit.value(text, attr.name, have, want, kind) orelse return .{ .refused = try manual(a, item, attr.name) };
    }
    for (p.links.map.keys(), p.links.map.values()) |name, targets| {
        var have: std.ArrayList([]const u8) = .empty;
        for (item.links) |l| if (std.mem.eql(u8, l.type_name, name)) try have.append(a, l.target);
        const old = try std.mem.join(a, ",", have.items);
        const new = try std.mem.join(a, ",", targets);
        if (std.mem.eql(u8, old, new)) continue;
        text = try edit.value(text, name, old, new, .list) orelse return .{ .refused = try manual(a, item, name) };
    }
    return .{ .text = text };
}

/// Writes each value of the form that differs from the item's
fn apply(io: Io, a: Allocator, ws: *const Workspace, t: *const Schema.ItemType, item: *const Item, p: form.Save) Allocator.Error!Outcome {
    const text = switch (try edited(io, a, ws, t, item, p)) {
        .text => |x| x,
        .refused => |why| return .{ .refused = why },
    };
    ws.root.writeFile(io, .{ .sub_path = item.file, .data = text }) catch return refuse(a, "{s} cannot be written", .{item.file});
    return .{ .written = .{ .id = item.id, .file = item.file, .line = if (item.line > 0) item.line - 1 else 0 } };
}

fn manual(a: Allocator, item: *const Item, what: []const u8) Allocator.Error![]const u8 {
    return a.print("skein: {s}: the {s} is written in a way skein does not change; change it by hand", .{ item.file, what });
}

/// The values of an attribute, joined by commas as a form shows them
fn joined(a: Allocator, item: *const Item, name: []const u8) Allocator.Error![]const u8 {
    for (item.attributes) |attr| if (std.mem.eql(u8, attr.name, name)) return if (attr.values.len > 0) try std.mem.join(a, ",", attr.values) else attr.value;
    return "";
}

/// The edits of one item, in its marker or its front matter
const Edit = struct {
    a: Allocator,
    item: *const Item,

    const Kind = enum { string, raw, list };

    /// A bare word of a marker (the category, the status), a key of front matter
    fn word(self: Edit, text: []const u8, key: []const u8, old: ?[]const u8, new: []const u8) Allocator.Error!?[]const u8 {
        const before = old orelse "";
        if (std.mem.eql(u8, before, new)) return text;
        if (!self.item.in_document) return self.value(text, key, before, new, .string);
        if (new.len == 0) return attribute.markerRemoveWord(self.a, text, self.item.line, before);
        return attribute.markerWord(self.a, text, self.item.line, old, new);
    }

    /// `key=value` in a marker, `key = value` in front matter; an empty value takes it out
    fn value(self: Edit, text: []const u8, key: []const u8, old: []const u8, new: []const u8, kind: Kind) Allocator.Error!?[]const u8 {
        if (std.mem.eql(u8, old, new)) return text;
        const a = self.a;
        if (self.item.in_document) {
            if (new.len == 0) return attribute.markerRemove(a, text, self.item.line, key);
            const v = if (kind != .list and std.mem.findAny(u8, new, " ,\"") != null) try a.print("\"{s}\"", .{new}) else new;
            return attribute.marker(a, text, self.item.line, key, v);
        }
        if (new.len == 0) return attribute.frontMatterRemove(a, text, key);
        const v = switch (kind) {
            .raw => new,
            .string => try a.print("\"{s}\"", .{new}),
            .list => blk: {
                var out: std.ArrayList(u8) = .empty;
                try out.append(a, '[');
                var it = std.mem.tokenizeScalar(u8, new, ',');
                var first = true;
                while (it.next()) |w| {
                    if (!first) try out.appendSlice(a, ", ");
                    first = false;
                    try out.print(a, "\"{s}\"", .{std.mem.trim(u8, w, " ")});
                }
                try out.append(a, ']');
                break :blk out.items;
            },
        };
        return attribute.frontMatter(a, text, key, v);
    }
};
