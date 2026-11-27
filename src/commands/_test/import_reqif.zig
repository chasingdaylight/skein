//! `skein import reqif`: a file as DOORS writes one, and the round trip
//! through `skein export reqif`.

// req: import.reqif
const std = @import("std");
const testing = std.testing;

const check = @import("../check.zig");
const export_command = @import("../export.zig");
const import_csv = @import("../import_csv.zig");
const reqif = @import("../../import/reqif.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

fn import(a: std.mem.Allocator, root: []const u8, file: []const u8, item_type: []const u8, to: []const u8) ![]const u8 {
    return (try import_csv.importRows(testing.io, a, .{ .common = .{ .root = root }, .format = .reqif, .paths = &.{file}, .item_type = item_type, .to = to }, "reqif", reqif.rows)).text;
}

const doors =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<REQ-IF xmlns="http://www.omg.org/spec/ReqIF/20110401/reqif.xsd" xmlns:xhtml="http://www.w3.org/1999/xhtml">
    \\  <THE-HEADER><REQ-IF-HEADER IDENTIFIER="h"><CREATION-TIME>2026-01-01T00:00:00Z</CREATION-TIME><REQ-IF-TOOL-ID>t</REQ-IF-TOOL-ID><REQ-IF-VERSION>1.0</REQ-IF-VERSION><SOURCE-TOOL-ID>DOORS</SOURCE-TOOL-ID><TITLE>SRS</TITLE></REQ-IF-HEADER></THE-HEADER>
    \\  <CORE-CONTENT><REQ-IF-CONTENT>
    \\    <DATATYPES>
    \\      <DATATYPE-DEFINITION-ENUMERATION IDENTIFIER="dt-priority" LAST-CHANGE="2026-01-01T00:00:00Z">
    \\        <SPECIFIED-VALUES>
    \\          <ENUM-VALUE IDENTIFIER="ev-high" LONG-NAME="High" LAST-CHANGE="2026-01-01T00:00:00Z"/>
    \\        </SPECIFIED-VALUES>
    \\      </DATATYPE-DEFINITION-ENUMERATION>
    \\    </DATATYPES>
    \\    <SPEC-TYPES>
    \\      <SPEC-OBJECT-TYPE IDENTIFIER="ot" LONG-NAME="Requirement" LAST-CHANGE="2026-01-01T00:00:00Z">
    \\        <SPEC-ATTRIBUTES>
    \\          <ATTRIBUTE-DEFINITION-STRING IDENTIFIER="ad-fid" LONG-NAME="ReqIF.ForeignID" LAST-CHANGE="2026-01-01T00:00:00Z"/>
    \\          <ATTRIBUTE-DEFINITION-XHTML IDENTIFIER="ad-text" LONG-NAME="ReqIF.Text" LAST-CHANGE="2026-01-01T00:00:00Z"/>
    \\          <ATTRIBUTE-DEFINITION-STRING IDENTIFIER="ad-name" LONG-NAME="ReqIF.Name" LAST-CHANGE="2026-01-01T00:00:00Z"/>
    \\          <ATTRIBUTE-DEFINITION-ENUMERATION IDENTIFIER="ad-priority" LONG-NAME="Priority" LAST-CHANGE="2026-01-01T00:00:00Z"/>
    \\        </SPEC-ATTRIBUTES>
    \\      </SPEC-OBJECT-TYPE>
    \\      <SPEC-RELATION-TYPE IDENTIFIER="rt" LONG-NAME="refines" LAST-CHANGE="2026-01-01T00:00:00Z"/>
    \\    </SPEC-TYPES>
    \\    <SPEC-OBJECTS>
    \\      <SPEC-OBJECT IDENTIFIER="_o2" LAST-CHANGE="2026-01-01T00:00:00Z"><TYPE><SPEC-OBJECT-TYPE-REF>ot</SPEC-OBJECT-TYPE-REF></TYPE>
    \\        <VALUES>
    \\          <ATTRIBUTE-VALUE-STRING THE-VALUE="SRS-002"><DEFINITION><ATTRIBUTE-DEFINITION-STRING-REF>ad-fid</ATTRIBUTE-DEFINITION-STRING-REF></DEFINITION></ATTRIBUTE-VALUE-STRING>
    \\          <ATTRIBUTE-VALUE-XHTML><DEFINITION><ATTRIBUTE-DEFINITION-XHTML-REF>ad-text</ATTRIBUTE-DEFINITION-XHTML-REF></DEFINITION><THE-VALUE><xhtml:div>Second.</xhtml:div></THE-VALUE></ATTRIBUTE-VALUE-XHTML>
    \\        </VALUES>
    \\      </SPEC-OBJECT>
    \\      <SPEC-OBJECT IDENTIFIER="_o1" LAST-CHANGE="2026-01-01T00:00:00Z"><TYPE><SPEC-OBJECT-TYPE-REF>ot</SPEC-OBJECT-TYPE-REF></TYPE>
    \\        <VALUES>
    \\          <ATTRIBUTE-VALUE-STRING THE-VALUE="SRS-001"><DEFINITION><ATTRIBUTE-DEFINITION-STRING-REF>ad-fid</ATTRIBUTE-DEFINITION-STRING-REF></DEFINITION></ATTRIBUTE-VALUE-STRING>
    \\          <ATTRIBUTE-VALUE-STRING THE-VALUE="Logging"><DEFINITION><ATTRIBUTE-DEFINITION-STRING-REF>ad-name</ATTRIBUTE-DEFINITION-STRING-REF></DEFINITION></ATTRIBUTE-VALUE-STRING>
    \\          <ATTRIBUTE-VALUE-XHTML><DEFINITION><ATTRIBUTE-DEFINITION-XHTML-REF>ad-text</ATTRIBUTE-DEFINITION-XHTML-REF></DEFINITION>
    \\            <THE-VALUE><xhtml:div><xhtml:p>The system <xhtml:b>shall</xhtml:b>
    \\              log:</xhtml:p><xhtml:ul><xhtml:li>errors</xhtml:li><xhtml:li>warnings<xhtml:br/>too</xhtml:li></xhtml:ul></xhtml:div></THE-VALUE>
    \\          </ATTRIBUTE-VALUE-XHTML>
    \\          <ATTRIBUTE-VALUE-ENUMERATION><DEFINITION><ATTRIBUTE-DEFINITION-ENUMERATION-REF>ad-priority</ATTRIBUTE-DEFINITION-ENUMERATION-REF></DEFINITION><VALUES><ENUM-VALUE-REF>ev-high</ENUM-VALUE-REF></VALUES></ATTRIBUTE-VALUE-ENUMERATION>
    \\        </VALUES>
    \\      </SPEC-OBJECT>
    \\    </SPEC-OBJECTS>
    \\    <SPEC-RELATIONS>
    \\      <SPEC-RELATION IDENTIFIER="r1" LAST-CHANGE="2026-01-01T00:00:00Z"><TYPE><SPEC-RELATION-TYPE-REF>rt</SPEC-RELATION-TYPE-REF></TYPE>
    \\        <SOURCE><SPEC-OBJECT-REF>_o2</SPEC-OBJECT-REF></SOURCE><TARGET><SPEC-OBJECT-REF>_o1</SPEC-OBJECT-REF></TARGET></SPEC-RELATION>
    \\    </SPEC-RELATIONS>
    \\    <SPECIFICATIONS>
    \\      <SPECIFICATION IDENTIFIER="s" LAST-CHANGE="2026-01-01T00:00:00Z"><TYPE><SPECIFICATION-TYPE-REF>st</SPECIFICATION-TYPE-REF></TYPE>
    \\        <CHILDREN><SPEC-HIERARCHY IDENTIFIER="h1" LAST-CHANGE="2026-01-01T00:00:00Z"><OBJECT><SPEC-OBJECT-REF>_o1</SPEC-OBJECT-REF></OBJECT>
    \\          <CHILDREN><SPEC-HIERARCHY IDENTIFIER="h2" LAST-CHANGE="2026-01-01T00:00:00Z"><OBJECT><SPEC-OBJECT-REF>_o2</SPEC-OBJECT-REF></OBJECT></SPEC-HIERARCHY></CHILDREN>
    \\        </SPEC-HIERARCHY></CHILDREN>
    \\      </SPECIFICATION>
    \\    </SPECIFICATIONS>
    \\  </REQ-IF-CONTENT></CORE-CONTENT>
    \\</REQ-IF>
    \\
;

test "a ReqIF file as DOORS writes one: foreign IDs, XHTML text, an enumeration, a relation" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const got = switch (try reqif.rows(a, doors, "srs.reqif")) {
        .rows => |r| r,
        .failed => |why| {
            std.debug.print("{s}\n", .{why});
            return error.TestUnexpectedResult;
        },
    };
    try testing.expectEqual(3, got.len);
    try testing.expectEqualStrings("id", got[0][0]);
    // in the order of the specification: SRS-001 first
    try testing.expectEqualStrings("SRS-001", got[1][0]);
    try testing.expectEqualStrings("The system **shall** log:\n\n- errors\n- warnings\ntoo", got[1][1]);
    try testing.expectEqualStrings("_o1", got[1][2]);

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/links/refines.toml", "");
    try write(tmp.dir, "srs.reqif", doors);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try expectContains(try import(a, root, "srs.reqif", "srs", "srs"), "imported 2 items of type srs into srs");
    const one = try tmp.dir.readFileAlloc(testing.io, "srs/SRS-001.md", a, .limited(1 << 16));
    try expectContains(one, "reqif = \"_o1\"\n");
    try expectContains(one, "priority = \"High\"\n");
    try expectContains(one, "title = \"Logging\"\n");
    try expectContains(one, "+++\n\nThe system **shall** log:");
    try expectContains(try tmp.dir.readFileAlloc(testing.io, "srs/SRS-002.md", a, .limited(1 << 16)), "refines = [\"SRS-001\"]\n");
    try expectContains((try check.run(testing.io, a, .{ .root = root })).text, "no problems (2 items");

    try testing.expect(try reqif.rows(a, "<html/>", "x.reqif") == .failed);
}

test "what skein exports comes back the same" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "a/.skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, "a/.skein/types/req.toml", "statuses = [\"draft\", \"approved\"]\n\n[attributes.owner]\n");
    try write(tmp.dir, "a/.skein/links/refines.toml", "");
    try write(tmp.dir, "a/spec/sys.md", "%req[sys.a owner=Ann] First & <best>.\n\n%req[sys.b approved refines=sys.a] Second.\n");
    const a_root = try tmp.dir.realPathFileAlloc(testing.io, "a", a);
    try write(tmp.dir, "b/sys.reqif", (try export_command.run(testing.io, a, .{ .common = .{ .root = a_root }, .what = .reqif })).text);
    try write(tmp.dir, "b/.skein/links/refines.toml", "");
    const b_root = try tmp.dir.realPathFileAlloc(testing.io, "b", a);
    try expectContains(try import(a, b_root, "sys.reqif", "req", "items"), "imported 2 items");
    const first = try tmp.dir.readFileAlloc(testing.io, "b/items/sys.a.md", a, .limited(1 << 16));
    try expectContains(first, "status = \"draft\"\n");
    try expectContains(first, "owner = \"Ann\"\n");
    try expectContains(first, "+++\n\nFirst & <best>.\n");
    const second = try tmp.dir.readFileAlloc(testing.io, "b/items/sys.b.md", a, .limited(1 << 16));
    try expectContains(second, "status = \"approved\"\n");
    try expectContains(second, "refines = [\"sys.a\"]\n");
}
