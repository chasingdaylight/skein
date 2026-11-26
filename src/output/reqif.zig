//! The items as ReqIF 1.2 (OMG), for DOORS and the other tools that
//! exchange requirements in it (#102). Each item type is a spec object type
//! with string attributes for the ID, category, status, verification and
//! its declared attributes, and an XHTML one for the text; each link type a
//! spec relation type; each document (an item file's directory, for items
//! of their own) a specification, its items in order with their parts
//! under them. Identifiers come from the IDs, so an export of a later
//! commit updates the same objects. `LAST-CHANGE` is the time of the last
//! commit of each item's file.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Project = @import("../Project.zig");
const Schema = @import("../schema/Schema.zig");
const xml = @import("../xml.zig");

const Item = Graph.Item;
const Writer = std.Io.Writer;

pub const namespace = "http://www.omg.org/spec/ReqIF/20110401/reqif.xsd";
pub const xhtml_namespace = "http://www.w3.org/1999/xhtml";

/// The longest string a ReqIF string attribute is declared to hold
const max_length = 1 << 20;

pub const Input = struct {
    project: *const Project,
    graph: *const Graph,
    /// the items to write, in the graph's order
    items: []const *const Item,
    /// `version` of skein, for the header
    tool: []const u8,
    /// the time of the last commit of each file, as xsd:dateTime
    times: *const std.StringHashMapUnmanaged([]const u8),
    /// for a file without one: the last commit's, or a fixed time
    default_time: []const u8,
    /// the IDs and former IDs of `items`, filled by `write`
    ids: std.StringHashMapUnmanaged(void) = .empty,
};

pub fn write(arena: std.mem.Allocator, given: Input) ![]const u8 {
    var in = given;
    for (in.items) |i| {
        try in.ids.put(arena, i.id, {});
        for (i.aliases) |a| try in.ids.put(arena, a, {});
    }
    var buf: Writer.Allocating = .init(arena);
    const w = &buf.writer;
    const now = in.default_time;
    try w.print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<REQ-IF xmlns=\"{s}\" xmlns:xhtml=\"{s}\">\n", .{ namespace, xhtml_namespace });
    try w.writeAll("  <THE-HEADER>\n    <REQ-IF-HEADER IDENTIFIER=\"skein-header\">\n");
    try w.print("      <CREATION-TIME>{s}</CREATION-TIME>\n      <REQ-IF-TOOL-ID>skein</REQ-IF-TOOL-ID>\n      <REQ-IF-VERSION>1.0</REQ-IF-VERSION>\n", .{now});
    try w.print("      <SOURCE-TOOL-ID>skein {s}</SOURCE-TOOL-ID>\n      <TITLE>", .{in.tool});
    try xml.escape(w, in.project.name);
    try w.writeAll("</TITLE>\n    </REQ-IF-HEADER>\n  </THE-HEADER>\n  <CORE-CONTENT>\n    <REQ-IF-CONTENT>\n");

    try w.print("      <DATATYPES>\n        <DATATYPE-DEFINITION-STRING IDENTIFIER=\"dt-string\" LAST-CHANGE=\"{s}\" LONG-NAME=\"String\" MAX-LENGTH=\"{d}\"/>\n", .{ now, max_length });
    try w.print("        <DATATYPE-DEFINITION-XHTML IDENTIFIER=\"dt-xhtml\" LAST-CHANGE=\"{s}\" LONG-NAME=\"XHTML\"/>\n      </DATATYPES>\n", .{now});

    try w.writeAll("      <SPEC-TYPES>\n");
    for (in.project.schema.types) |*t| {
        if (!used(in.items, t.name)) continue;
        try w.print("        <SPEC-OBJECT-TYPE IDENTIFIER=\"{f}\" LAST-CHANGE=\"{s}\" LONG-NAME=\"", .{ ident("type-", t.name), now });
        try xml.escape(w, t.name);
        try w.writeAll("\">\n          <SPEC-ATTRIBUTES>\n");
        for (try fields(arena, t)) |f| {
            try w.print("            <ATTRIBUTE-DEFINITION-STRING IDENTIFIER=\"{f}\" LAST-CHANGE=\"{s}\" LONG-NAME=\"", .{ ident2(t.name, f), now });
            try xml.escape(w, f);
            try w.writeAll("\">\n              <TYPE><DATATYPE-DEFINITION-STRING-REF>dt-string</DATATYPE-DEFINITION-STRING-REF></TYPE>\n            </ATTRIBUTE-DEFINITION-STRING>\n");
        }
        try w.print("            <ATTRIBUTE-DEFINITION-XHTML IDENTIFIER=\"{f}\" LAST-CHANGE=\"{s}\" LONG-NAME=\"text\">\n", .{ ident2(t.name, "text"), now });
        try w.writeAll("              <TYPE><DATATYPE-DEFINITION-XHTML-REF>dt-xhtml</DATATYPE-DEFINITION-XHTML-REF></TYPE>\n            </ATTRIBUTE-DEFINITION-XHTML>\n");
        try w.writeAll("          </SPEC-ATTRIBUTES>\n        </SPEC-OBJECT-TYPE>\n");
    }
    for (in.project.schema.links) |l| {
        try w.print("        <SPEC-RELATION-TYPE IDENTIFIER=\"{f}\" LAST-CHANGE=\"{s}\" LONG-NAME=\"", .{ ident("link-", l.name), now });
        try xml.escape(w, l.name);
        try w.writeAll("\"/>\n");
    }
    try w.print("        <SPECIFICATION-TYPE IDENTIFIER=\"spec-type\" LAST-CHANGE=\"{s}\" LONG-NAME=\"document\"/>\n      </SPEC-TYPES>\n", .{now});

    try w.writeAll("      <SPEC-OBJECTS>\n");
    for (in.items) |item| try object(arena, w, in, item);
    try w.writeAll("      </SPEC-OBJECTS>\n      <SPEC-RELATIONS>\n");
    for (in.items) |item| for (item.links) |link| {
        if (!in.ids.contains(link.target)) continue;
        if (in.project.schema.linkType(link.type_name) == null) continue;
        try w.print("        <SPEC-RELATION IDENTIFIER=\"{f}\" LAST-CHANGE=\"{s}\">\n", .{ relation(item.id, link), timeOf(in, item) });
        try w.print("          <SOURCE><SPEC-OBJECT-REF>{f}</SPEC-OBJECT-REF></SOURCE>\n", .{ident("item-", item.id)});
        try w.print("          <TARGET><SPEC-OBJECT-REF>{f}</SPEC-OBJECT-REF></TARGET>\n", .{ident("item-", targetId(in.graph, link.target))});
        try w.print("          <TYPE><SPEC-RELATION-TYPE-REF>{f}</SPEC-RELATION-TYPE-REF></TYPE>\n        </SPEC-RELATION>\n", .{ident("link-", link.type_name)});
    };
    try w.writeAll("      </SPEC-RELATIONS>\n      <SPECIFICATIONS>\n");
    var i: usize = 0;
    while (i < in.items.len) {
        const doc = document(in.items[i]);
        try w.print("        <SPECIFICATION IDENTIFIER=\"{f}\" LAST-CHANGE=\"{s}\" LONG-NAME=\"", .{ ident("doc-", doc), timeOf(in, in.items[i]) });
        try xml.escape(w, doc);
        try w.writeAll("\">\n          <CHILDREN>\n");
        while (i < in.items.len and std.mem.eql(u8, document(in.items[i]), doc)) : (i += 1) {
            const item = in.items[i];
            // a part goes under its whole, when that is written too
            if (item.parent) |p| if (in.ids.contains(p)) continue;
            try hierarchy(w, in, item, 6);
        }
        try w.writeAll("          </CHILDREN>\n          <TYPE><SPECIFICATION-TYPE-REF>spec-type</SPECIFICATION-TYPE-REF></TYPE>\n        </SPECIFICATION>\n");
    }
    try w.writeAll("      </SPECIFICATIONS>\n    </REQ-IF-CONTENT>\n  </CORE-CONTENT>\n</REQ-IF>\n");
    return buf.written();
}

/// The string attributes of a type's objects: `id`, then what the type has
fn fields(arena: std.mem.Allocator, t: *const Schema.ItemType) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    try out.append(arena, "id");
    if (t.categories.len > 0) try out.append(arena, "category");
    if (t.statuses.len > 0) try out.append(arena, "status");
    if (t.verification.len > 0) try out.append(arena, "verification");
    for (t.attributes) |a| try out.append(arena, a.name);
    return out.items;
}

fn object(arena: std.mem.Allocator, w: *Writer, in: Input, item: *const Item) !void {
    const t = in.project.schema.itemType(item.type_name) orelse return;
    try w.print("        <SPEC-OBJECT IDENTIFIER=\"{f}\" LAST-CHANGE=\"{s}\">\n          <VALUES>\n", .{ ident("item-", item.id), timeOf(in, item) });
    for (try fields(arena, t)) |f| {
        const value: ?[]const u8 = if (std.mem.eql(u8, f, "id"))
            item.id
        else if (std.mem.eql(u8, f, "category"))
            item.category
        else if (std.mem.eql(u8, f, "status"))
            item.effectiveStatus(t)
        else if (std.mem.eql(u8, f, "verification"))
            item.verification
        else
            item.attribute(f);
        const v = value orelse continue;
        try w.writeAll("            <ATTRIBUTE-VALUE-STRING THE-VALUE=\"");
        try xml.escape(w, v);
        try w.print("\"><DEFINITION><ATTRIBUTE-DEFINITION-STRING-REF>{f}</ATTRIBUTE-DEFINITION-STRING-REF></DEFINITION></ATTRIBUTE-VALUE-STRING>\n", .{ident2(t.name, f)});
    }
    try w.print("            <ATTRIBUTE-VALUE-XHTML>\n              <DEFINITION><ATTRIBUTE-DEFINITION-XHTML-REF>{f}</ATTRIBUTE-DEFINITION-XHTML-REF></DEFINITION>\n", .{ident2(t.name, "text")});
    try w.writeAll("              <THE-VALUE><xhtml:div>");
    try paragraphs(w, item.text);
    try w.writeAll("</xhtml:div></THE-VALUE>\n            </ATTRIBUTE-VALUE-XHTML>\n          </VALUES>\n");
    try w.print("          <TYPE><SPEC-OBJECT-TYPE-REF>{f}</SPEC-OBJECT-TYPE-REF></TYPE>\n        </SPEC-OBJECT>\n", .{ident("type-", t.name)});
}

/// The Markdown, a paragraph to each block between blank lines, as text
fn paragraphs(w: *Writer, text: []const u8) !void {
    var blocks = std.mem.splitSequence(u8, text, "\n\n");
    while (blocks.next()) |block| {
        const b = std.mem.trim(u8, block, " \t\r\n");
        if (b.len == 0) continue;
        try w.writeAll("<xhtml:p>");
        try xml.escape(w, b);
        try w.writeAll("</xhtml:p>");
    }
}

fn hierarchy(w: *Writer, in: Input, item: *const Item, depth: usize) !void {
    try w.splatByteAll(' ', depth * 2);
    try w.print("<SPEC-HIERARCHY IDENTIFIER=\"{f}\" LAST-CHANGE=\"{s}\">\n", .{ ident("h-", item.id), timeOf(in, item) });
    try w.splatByteAll(' ', depth * 2 + 2);
    try w.print("<OBJECT><SPEC-OBJECT-REF>{f}</SPEC-OBJECT-REF></OBJECT>\n", .{ident("item-", item.id)});
    var parts = false;
    for (item.parts) |id| {
        const part = in.graph.find(id) orelse continue;
        if (!in.ids.contains(part.id)) continue;
        if (!parts) {
            try w.splatByteAll(' ', depth * 2 + 2);
            try w.writeAll("<CHILDREN>\n");
            parts = true;
        }
        try hierarchy(w, in, part, depth + 2);
    }
    if (parts) {
        try w.splatByteAll(' ', depth * 2 + 2);
        try w.writeAll("</CHILDREN>\n");
    }
    try w.splatByteAll(' ', depth * 2);
    try w.writeAll("</SPEC-HIERARCHY>\n");
}

/// The document an item is in: its file, or for an item file its directory
fn document(item: *const Item) []const u8 {
    if (item.in_document) return item.file;
    return std.Io.Dir.path.dirnamePosix(item.file) orelse ".";
}

fn timeOf(in: Input, item: *const Item) []const u8 {
    return in.times.get(item.file) orelse in.default_time;
}

fn used(items: []const *const Item, type_name: []const u8) bool {
    for (items) |i| if (std.mem.eql(u8, i.type_name, type_name)) return true;
    return false;
}

fn targetId(graph: *const Graph, target: []const u8) []const u8 {
    const item = graph.find(target) orelse graph.formerly(target) orelse return target;
    return item.id;
}

/// An xsd:ID: `prefix` and `name`, with what an NCName cannot hold as `_`
const Ident = struct {
    prefix: []const u8,
    parts: [3][]const u8,

    pub fn format(self: Ident, w: *Writer) Writer.Error!void {
        try w.writeAll(self.prefix);
        for (self.parts, 0..) |p, n| {
            if (p.len == 0) continue;
            if (n > 0) try w.writeAll("--");
            for (p) |c| try w.writeByte(if (std.ascii.isAlphanumeric(c) or c == '.' or c == '-' or c == '_' or c >= 0x80) c else '_');
        }
    }
};

fn ident(prefix: []const u8, name: []const u8) Ident {
    return .{ .prefix = prefix, .parts = .{ name, "", "" } };
}

fn ident2(type_name: []const u8, field: []const u8) Ident {
    return .{ .prefix = "attr-", .parts = .{ type_name, field, "" } };
}

fn relation(from: []const u8, link: Item.Link) Ident {
    return .{ .prefix = "rel-", .parts = .{ from, link.type_name, link.target } };
}

test {
    _ = @import("_test/reqif.zig");
}
