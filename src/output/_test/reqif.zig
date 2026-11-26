//! The ReqIF export, read back with skein's XML reader: the header, the
//! types, the objects with their values, the relations and the documents.

// req: export.reqif
const std = @import("std");
const testing = std.testing;

const export_command = @import("../../commands/export.zig");
const reqif = @import("../reqif.zig");
const xml = @import("../../xml.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

/// The element under `e` along `path`, each step the first child so named
fn at(e: *const xml.Element, path: []const []const u8) !*const xml.Element {
    var cur = e;
    for (path) |name| cur = cur.child(name) orelse {
        std.debug.print("no '{s}' in '{s}'\n", .{ name, cur.name });
        return error.TestUnexpectedResult;
    };
    return cur;
}

test "items, links and documents as ReqIF" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[project]\nname = \"Spec & Co\"\n\n[[sources]]\npath = \"spec\"\n");
    try write(dir, ".skein/types/req.toml", "statuses = [\"draft\", \"approved\"]\n\n[attributes.owner]\n");
    try write(dir, ".skein/links/refines.toml", "from = [\"req\"]\nto = [\"req\"]\n");
    try write(dir, "spec/sys.md",
        \\%req[sys.a owner=Ann] The system shall <work>.
        \\
        \\- %req[.one approved refines=sys.b] A part.
        \\
        \\%req[sys.b] Second, with a block.
        \\
        \\```text
        \\code
        \\```
        \\
    );
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const out = (try export_command.run(testing.io, a, .{ .common = .{ .root = root }, .what = .reqif })).text;

    var diag: xml.Diagnostic = .{};
    const doc = xml.parse(a, out, &diag) catch |e| {
        std.debug.print("{s}\n{d}:{d}: {s}\n", .{ out[0..@min(out.len, 600)], diag.line, diag.column, diag.message });
        return e;
    };
    try testing.expectEqualStrings("REQ-IF", doc.name);
    try testing.expectEqualStrings(reqif.namespace, doc.attribute("xmlns").?);
    const header = try at(doc, &.{ "THE-HEADER", "REQ-IF-HEADER" });
    try testing.expectEqualStrings("Spec & Co", try (try at(header, &.{"TITLE"})).text(a));
    try testing.expectEqualStrings("1.0", try (try at(header, &.{"REQ-IF-VERSION"})).text(a));
    const content = try at(doc, &.{ "CORE-CONTENT", "REQ-IF-CONTENT" });

    const types = try at(content, &.{"SPEC-TYPES"});
    const object_type = try at(types, &.{"SPEC-OBJECT-TYPE"});
    try testing.expectEqualStrings("type-req", object_type.attribute("IDENTIFIER").?);
    const defs = try (try at(object_type, &.{"SPEC-ATTRIBUTES"})).children(a, "ATTRIBUTE-DEFINITION-STRING");
    try testing.expectEqual(3, defs.len);
    try testing.expectEqualStrings("owner", defs[2].attribute("LONG-NAME").?);
    try testing.expectEqualStrings("link-refines", (try at(types, &.{"SPEC-RELATION-TYPE"})).attribute("IDENTIFIER").?);

    const objects = try (try at(content, &.{"SPEC-OBJECTS"})).children(a, "SPEC-OBJECT");
    try testing.expectEqual(3, objects.len);
    try testing.expectEqualStrings("item-sys.a", objects[0].attribute("IDENTIFIER").?);
    // the last commit's time, or a fixed one outside a repository
    try testing.expect(std.mem.findScalar(u8, objects[0].attribute("LAST-CHANGE").?, 'T') == 10);
    const values = try (try at(objects[0], &.{"VALUES"})).children(a, "ATTRIBUTE-VALUE-STRING");
    try testing.expectEqualStrings("sys.a", values[0].attribute("THE-VALUE").?);
    try testing.expectEqualStrings("draft", values[1].attribute("THE-VALUE").?);
    try testing.expectEqualStrings("Ann", values[2].attribute("THE-VALUE").?);
    const text = try at(objects[0], &.{ "VALUES", "ATTRIBUTE-VALUE-XHTML", "THE-VALUE", "div" });
    try testing.expectEqualStrings("The system shall <work>.", try text.text(a));
    const second = try (try at(objects[2], &.{ "VALUES", "ATTRIBUTE-VALUE-XHTML", "THE-VALUE", "div" })).children(a, "p");
    try testing.expectEqual(2, second.len);

    const rel = try at(content, &.{ "SPEC-RELATIONS", "SPEC-RELATION" });
    try testing.expectEqualStrings("item-sys.a.one", try (try at(rel, &.{ "SOURCE", "SPEC-OBJECT-REF" })).text(a));
    try testing.expectEqualStrings("item-sys.b", try (try at(rel, &.{ "TARGET", "SPEC-OBJECT-REF" })).text(a));
    try testing.expectEqualStrings("link-refines", try (try at(rel, &.{ "TYPE", "SPEC-RELATION-TYPE-REF" })).text(a));

    const spec = try at(content, &.{ "SPECIFICATIONS", "SPECIFICATION" });
    try testing.expectEqualStrings("spec/sys.md", spec.attribute("LONG-NAME").?);
    const top = try (try at(spec, &.{"CHILDREN"})).children(a, "SPEC-HIERARCHY");
    try testing.expectEqual(2, top.len);
    try testing.expectEqualStrings("item-sys.a.one", try (try at(top[0], &.{ "CHILDREN", "SPEC-HIERARCHY", "OBJECT", "SPEC-OBJECT-REF" })).text(a));

    // the same files give the same bytes
    try testing.expectEqualStrings(out, (try export_command.run(testing.io, a, .{ .common = .{ .root = root }, .what = .reqif })).text);
}
