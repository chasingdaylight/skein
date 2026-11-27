//! An item form, as the editor's forms (lsp/form.zig) and `skein serve`'s
//! pages show it: the item as it is (none for a new one) and its type:
//! categories, statuses, attributes with their kinds and values, the link
//! types it may have with the items they may point to, and where a new
//! item goes. What a form saves is a `Save` (edit/item_form.zig).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const json = std.json;

const Item = @import("../graph/Item.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("../commands/Workspace.zig");
const files = @import("../files.zig");

pub const Attribute = struct { name: []const u8, kind: []const u8, values: []const []const u8, required: bool, list: bool };
pub const LinkType = struct { name: []const u8, targets: []const []const u8 };

pub const Type = struct {
    name: []const u8,
    description: []const u8,
    categories: []const []const u8,
    statuses: []const []const u8,
    attributes: []const Attribute,
    links: []const LinkType,
    verification: []const []const u8,
    numbered: bool,
    /// the statuses that need an approval; none when the type asks for none
    approval: []const []const u8,
    /// the roles an approval is given in, when the type names them
    roles: []const []const u8,
};

pub const Form = struct {
    item: ?json.Value,
    types: []const []const u8,
    type: Type,
    /// whether a new item of the type may have a file of its own
    itemFiles: bool,
    /// the documents a new item may go at the end of
    documents: []const []const u8,
};

pub const Built = union(enum) { ok: Form, refused: []const u8 };

/// The form of the item `want_id`, or of a new item of `want_type` (the
/// first type when null)
pub fn build(io: Io, a: Allocator, ws: *Workspace, want_id: ?[]const u8, want_type: ?[]const u8) Allocator.Error!Built {
    if (!ws.items_read) return .{ .refused = "skein: the project has problems that stop it being read" };
    const schema = &ws.project.schema;
    const item: ?*const Item = if (want_id) |w| ws.graph.find(w) else null;
    if (want_id != null and item == null) return .{ .refused = try a.print("skein: there is no item '{s}'", .{want_id.?}) };
    if (schema.types.len == 0) return .{ .refused = "skein: the project has no item types" };
    const type_name = if (item) |it| it.type_name else want_type orelse schema.types[0].name;
    const t = schema.itemType(type_name) orelse return .{ .refused = try a.print("skein: there is no item type '{s}'", .{type_name}) };

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
        const found = files.list(io, a, ws.root, src.path, &.{".md"}) catch continue;
        try documents.appendSlice(a, found);
    }
    return .{ .ok = .{
        .item = if (item) |it| try current(a, it) else null,
        .types = types.items,
        .type = .{ .name = t.name, .description = t.description, .categories = t.categories, .statuses = t.statuses, .attributes = attributes.items, .links = links.items, .verification = t.verification, .numbered = t.id == .numbered, .approval = t.approval, .roles = t.approval_roles },
        .itemFiles = item_files,
        .documents = documents.items,
    } };
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
