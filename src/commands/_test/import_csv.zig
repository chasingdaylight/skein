//! `skein import csv`, on files written for the test.

// req: import.csv.rows, import.csv.type, import.csv.all-or-nothing, import.place
const std = @import("std");
const testing = std.testing;

const check = @import("../check.zig");
const cli = @import("../../cli.zig");
const import_csv = @import("../import_csv.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn read(a: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) ![]const u8 {
    return dir.readFileAlloc(testing.io, path, a, .limited(1 << 20));
}

const Options = struct {
    file: []const u8 = "standard.csv",
    item_type: ?[]const u8 = "swe",
    to: ?[]const u8 = "standard",
    id_column: ?[]const u8 = null,
    text_column: ?[]const u8 = null,
    replace: bool = false,
};

fn run(a: std.mem.Allocator, dir: std.Io.Dir, options: Options) ![]const u8 {
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    return (try import_csv.run(testing.io, a, .{
        .common = .{ .root = root },
        .format = .csv,
        .paths = &.{options.file},
        .item_type = options.item_type,
        .to = options.to,
        .id_column = options.id_column,
        .text_column = options.text_column,
        .replace = options.replace,
    })).text;
}

const standard =
    \\ID,Text,Class A,Status,Notes
    \\SWE-013,"The project manager shall develop, and maintain, a ""plan"".",X,approved,
    \\SWE-022,The project shall assess the software.,,approved,"Two
    \\lines."
    \\
;

test "a standard's requirements become items, a type and a source" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "standard.csv", standard);

    try testing.expectEqualStrings(
        "skein: imported 2 items of type swe into standard\n       Run 'skein check'.\n",
        try run(a, tmp.dir, .{}),
    );
    try testing.expectEqualStrings(
        \\+++
        \\id = "SWE-013"
        \\class-a = "X"
        \\status = "approved"
        \\+++
        \\
        \\The project manager shall develop, and maintain, a "plan".
        \\
    , try read(a, tmp.dir, "standard/SWE-013.md"));
    try testing.expectEqualStrings(
        \\+++
        \\id = "SWE-022"
        \\status = "approved"
        \\notes = """
        \\Two
        \\lines."""
        \\+++
        \\
        \\The project shall assess the software.
        \\
    , try read(a, tmp.dir, "standard/SWE-022.md"));
    // the status is skein's own; the other columns are attributes
    try testing.expectEqualStrings(
        \\id = "numbered"
        \\prefix = "SWE"
        \\digits = 3
        \\separator = "-"
        \\
        \\[attributes.class-a]
        \\
        \\[attributes.notes]
        \\
    , try read(a, tmp.dir, ".skein/types/swe.toml"));
    try testing.expectEqualStrings("[[sources]]\npath = \"standard\"\nkind = \"items\"\ntype = \"swe\"\n", try read(a, tmp.dir, ".skein/config.toml"));

    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try testing.expect(std.mem.find(u8, (try check.run(testing.io, a, .{ .root = root })).text, "no problems (2 items of 1 types") != null);

    // again: the files are there, and are written over only when asked
    try testing.expectEqualStrings("skein: standard/SWE-013.md is there already (--replace writes over it)\n", try run(a, tmp.dir, .{}));
    try testing.expect(std.mem.startsWith(u8, try run(a, tmp.dir, .{ .replace = true }), "skein: imported 2 items"));
    // the source is not added twice
    try testing.expectEqualStrings("[[sources]]\npath = \"standard\"\nkind = \"items\"\ntype = \"swe\"\n", try read(a, tmp.dir, ".skein/config.toml"));
}

test "into a project: its type is kept, and a column named after a link type is links" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[project]\nname = \"example\"\n");
    try write(tmp.dir, ".skein/types/req.toml", "[attributes.owner]\n");
    try write(tmp.dir, ".skein/links/refines.toml", "");
    try write(tmp.dir, "in/list.csv", "Key;Requirement;Refines;Owner\nsys.start;The system shall start.;;ops\nsys.stop;The system shall stop.;sys.start, sys.other;\n");

    _ = try run(a, tmp.dir, .{ .file = "in/list.csv", .item_type = "req", .to = "docs/requirements/", .id_column = "Key", .text_column = "Requirement" });
    try testing.expectEqualStrings(
        \\+++
        \\id = "sys.stop"
        \\refines = ["sys.start", "sys.other"]
        \\+++
        \\
        \\The system shall stop.
        \\
    , try read(a, tmp.dir, "docs/requirements/sys.stop.md"));
    try testing.expectEqualStrings("[attributes.owner]\n", try read(a, tmp.dir, ".skein/types/req.toml"));
    try testing.expectEqualStrings(
        \\[project]
        \\name = "example"
        \\
        \\[[sources]]
        \\path = "docs/requirements"
        \\kind = "items"
        \\type = "req"
        \\
    , try read(a, tmp.dir, ".skein/config.toml"));
}

test "files that cannot be imported, and why" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "empty.csv", "id,text\n");
    try write(tmp.dir, "unnamed.csv", "name,text\nA-1,x\n");
    try write(tmp.dir, "blank.csv", "id,text\nA-1,x\n,y\n");
    try write(tmp.dir, "twice.csv", "id,text\nA-1,x\nA-1,y\n");
    try write(tmp.dir, "mixed.csv", "id,text\nA-1,x\nsome.thing,y\nTwo Words,z\n");
    try write(tmp.dir, "odd.csv", "id,text\nA-1,x\nB-2,y\n");
    try write(tmp.dir, "open.csv", "id,text\nA-1,\"x\n");
    try write(tmp.dir, "type.csv", "id,text,type\nA-1,x,y\n");

    try testing.expectEqualStrings("skein: cannot read 'none.csv'\n", try run(a, tmp.dir, .{ .file = "none.csv" }));
    try testing.expectEqualStrings("skein: empty.csv: no rows after the one that names the columns\n", try run(a, tmp.dir, .{ .file = "empty.csv" }));
    try testing.expectEqualStrings("skein: unnamed.csv: there is no column 'id' for the IDs (--id-column names another)\n", try run(a, tmp.dir, .{ .file = "unnamed.csv" }));
    try testing.expectEqualStrings("skein: unnamed.csv: there is no column 'body' for the text (--text-column names another)\n", try run(a, tmp.dir, .{ .file = "unnamed.csv", .id_column = "name", .text_column = "body" }));
    try testing.expectEqualStrings("skein: blank.csv: row 3 has no ID\n", try run(a, tmp.dir, .{ .file = "blank.csv" }));
    try testing.expectEqualStrings("skein: twice.csv: row 3: the ID 'A-1' is in the file twice\n", try run(a, tmp.dir, .{ .file = "twice.csv" }));
    try testing.expectEqualStrings("skein: mixed.csv: row 4: 'Two Words' cannot be an ID: letters, digits, '.', '-' and '_'\n", try run(a, tmp.dir, .{ .file = "mixed.csv" }));
    try testing.expectEqualStrings("skein: the IDs follow no one scheme (like SRS-012, or like lex.comment.line); make the item type 'swe' first\n", try run(a, tmp.dir, .{ .file = "odd.csv" }));
    try testing.expectEqualStrings("skein: open.csv: a quoted field is never closed\n", try run(a, tmp.dir, .{ .file = "open.csv" }));
    try testing.expectEqualStrings("skein: type.csv: a column cannot be called 'type'; skein reads that key itself\n", try run(a, tmp.dir, .{ .file = "type.csv" }));
    try testing.expectEqualStrings("skein: import csv: name the item type with --type\n", try run(a, tmp.dir, .{ .item_type = null }));
    try testing.expectEqualStrings("skein: import csv: name the directory for the items with --to\n", try run(a, tmp.dir, .{ .to = null }));
    // nothing was written by any of them
    try testing.expectError(error.FileNotFound, read(a, tmp.dir, ".skein/config.toml"));
}

test "import csv on the command line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const i = (try cli.parse(a, &.{ "import", "csv", "in.csv", "--type", "swe", "--to", "standard", "--id-column", "Key", "--replace" })).import;
    try testing.expectEqual(.csv, i.format);
    try testing.expectEqualStrings("in.csv", i.paths[0]);
    try testing.expectEqualStrings("swe", i.item_type.?);
    try testing.expectEqualStrings("Key", i.id_column.?);
    try testing.expect(i.replace);
    try testing.expectEqualStrings("import csv: name one CSV file", (try cli.parse(a, &.{ "import", "csv" })).misuse);
    try testing.expectEqualStrings("--type does not go with import", (try cli.parse(a, &.{ "import", "doorstop", "docs", "--type", "x" })).misuse);
}
