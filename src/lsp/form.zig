//! skein's requests for the editor's item forms:
//!
//! - `skein/form` (`{ "id": ID }` or `{ "type": TYPE }`): what a form shows,
//!   the item as it is (none for a new one) and its type: categories,
//!   statuses, attributes with their kinds and values, the link types it
//!   may have with the items they may point to, and where a new item goes
//! - `skein/saveItem`: writes a form, the item's category, status,
//!   attributes and links, into its marker or front matter; a new item is
//!   started as `skein new` starts it, in a file of its own or at the end
//!   of the document chosen

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Item = @import("../graph/Item.zig");
const Schema = @import("../schema/Schema.zig");
const Server = @import("Server.zig");
const files = @import("../files.zig");
const item_edits = @import("item_edits.zig");
const protocol = @import("protocol.zig");

const Attribute = struct { name: []const u8, kind: []const u8, values: []const []const u8, required: bool, list: bool };
const LinkType = struct { name: []const u8, targets: []const []const u8 };

pub fn form(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    var ws = s.open(a) orelse return s.respond(a, id, null);
    defer ws.close();
    if (!ws.items_read) return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: the project has problems that stop it being read");
    const schema = &ws.project.schema;
    const want_id = Server.field(params, "id");
    const item: ?*const Item = if (want_id == .string) ws.graph.find(want_id.string) else null;
    if (want_id == .string and item == null) return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: there is no item '{s}'", .{want_id.string}));
    const want_type = Server.field(params, "type");
    const type_name = if (item) |it| it.type_name else if (want_type == .string) want_type.string else schema.types[0].name;
    const t = schema.itemType(type_name) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: there is no item type '{s}'", .{type_name}));

    var attributes: std.ArrayList(Attribute) = .empty;
    for (t.attributes) |attr| try attributes.append(a, .{ .name = attr.name, .kind = @tagName(attr.kind), .values = attr.values, .required = attr.required, .list = attr.list });
    var links: std.ArrayList(LinkType) = .empty;
    for (schema.links) |l| {
        if (l.from.len > 0 and !Schema.names.contains(l.from, t.name)) continue;
        var targets: std.ArrayList([]const u8) = .empty;
        for (ws.graph.items) |*other| {
            if (l.to.len > 0 and !Schema.names.contains(l.to, other.type_name)) continue;
            const ot = schema.itemType(other.type_name) orelse continue;
            if (!other.isTombstone(ot)) try targets.append(a, other.id);
        }
        try links.append(a, .{ .name = l.name, .targets = targets.items });
    }
    var types: std.ArrayList([]const u8) = .empty;
    for (schema.types) |x| try types.append(a, x.name);
    // where a new item goes: a source of item files, or a document
    var documents: std.ArrayList([]const u8) = .empty;
    var item_files = false;
    for (ws.project.sources) |src| {
        if (src.read_only) continue;
        if (src.kind == .items) {
            if (src.item_type == null or std.mem.eql(u8, src.item_type.?, t.name)) item_files = true;
            continue;
        }
        const found = files.list(s.io, a, ws.root, src.path, &.{".md"}) catch continue;
        try documents.appendSlice(a, found);
    }
    try s.respond(a, id, .{
        .item = if (item) |it| try current(a, it) else null,
        .types = types.items,
        .type = .{ .name = t.name, .description = t.description, .categories = t.categories, .statuses = t.statuses, .attributes = attributes.items, .links = links.items, .verification = t.verification, .numbered = t.id == .numbered },
        .itemFiles = item_files,
        .documents = documents.items,
    });
}

/// The item's values as the form shows them
fn current(a: Allocator, item: *const Item) Allocator.Error!json.Value {
    var o: json.ObjectMap = .empty;
    try o.put(a, "id", .{ .string = item.id });
    try o.put(a, "type", .{ .string = item.type_name });
    try o.put(a, "file", .{ .string = item.file });
    if (item.category) |c| try o.put(a, "category", .{ .string = c });
    if (item.status) |st| try o.put(a, "status", .{ .string = st });
    if (item.verification) |v| try o.put(a, "verification", .{ .string = v });
    var attrs: json.ObjectMap = .empty;
    for (item.attributes) |attr| try attrs.put(a, attr.name, .{ .string = if (attr.values.len > 0) try std.mem.join(a, ",", attr.values) else attr.value });
    try o.put(a, "attributes", .{ .object = attrs });
    var links: json.ObjectMap = .empty;
    for (item.links) |l| {
        const e = try links.getOrPut(a, l.type_name);
        if (!e.found_existing) e.value_ptr.* = .{ .array = .init(a) };
        try e.value_ptr.array.append(.{ .string = l.target });
    }
    try o.put(a, "links", .{ .object = links });
    try o.put(a, "text", .{ .string = item.text });
    return .{ .object = o };
}

pub const Save = struct {
    /// the item's ID; for a new item, the ID it is to have, or empty for
    /// the next free number
    id: []const u8 = "",
    /// whether the item is new
    new: bool = false,
    type: []const u8,
    category: []const u8 = "",
    status: []const u8 = "",
    verification: []const u8 = "",
    /// by name; an empty value takes the attribute out
    attributes: json.ArrayHashMap([]const u8) = .{},
    /// by link type, the IDs; none takes the links out
    links: json.ArrayHashMap([]const []const u8) = .{},
    /// a new item's text
    text: []const u8 = "",
    /// a new item of a type kept in documents: the document it goes at the end of
    document: []const u8 = "",
};

pub fn save(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    const p = Server.parse(Save, a, params) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein/saveItem: no type");
    var ws = s.open(a) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: no project");
    defer ws.close();
    if (!ws.items_read) return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: the project has problems that stop it being read");
    switch (try item_edits.write(s, a, &ws, p)) {
        .refused => |why| return s.respondError(a, id, protocol.error_codes.invalid_params, why),
        .written => |w| try s.respond(a, id, .{ .id = w.id, .uri = try s.uriOf(a, &ws, w.file), .line = w.line }),
    }
    try s.publishAll(a);
}
