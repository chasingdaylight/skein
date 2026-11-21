//! Reading items from documents and from item files.

// req: items.text-extent, items.removed, items.file, items.file.keys, items.file.not-items
// req: principle.prose-friendly
const std = @import("std");
const testing = std.testing;

const Fixture = @import("fixture.zig").Fixture;

test "a document's markers and the text that belongs to each" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md",
        \\# Lexical structure
        \\
        \\This chapter is narrative until a marker.
        \\
        \\%rule[lex.comment.line legality stage=s0 see=lex.token]
        \\A line comment starts with `//`. It is not a %[lex.token].
        \\
        \\%rule[lex.keywords syntax]
        \\
        \\The keywords are:
        \\
        \\- `as`
        \\- `fn`
        \\
        \\```text
        \\keyword = "as" | "fn"
        \\```
        \\
        \\This paragraph is narrative again.
        \\
        \\%term[lex.token]
        \\A token is a unit of the source text.
    );
    try f.expectProblems("");
    try testing.expectEqual(3, f.items.items.len);

    const comment = f.items.items[0];
    try testing.expectEqualStrings("lex.comment.line", comment.id);
    try testing.expectEqualStrings("rule", comment.type_name);
    try testing.expectEqualStrings("legality", comment.category.?);
    try testing.expectEqualStrings("s0", comment.attribute("stage").?);
    try testing.expectEqualStrings("spec/lex.md", comment.file);
    try testing.expectEqual(5, comment.line);
    try testing.expectEqualStrings("A line comment starts with `//`. It is not a %[lex.token].", comment.text);
    try testing.expectEqualStrings("see", comment.links[0].type_name);
    try testing.expectEqualStrings("lex.token", comment.links[0].target);
    try testing.expectEqualStrings("lex.token", comment.references[0].target);
    try testing.expectEqual(6, comment.references[0].line);
    try testing.expectEqual(46, comment.references[0].column);

    // the paragraph, with the list and the code block that hang on it
    const keywords = f.items.items[1];
    try testing.expect(std.mem.startsWith(u8, keywords.text, "The keywords are:"));
    try testing.expect(std.mem.endsWith(u8, keywords.text, "```"));
    try testing.expect(std.mem.find(u8, keywords.text, "narrative") == null);

    try testing.expectEqualStrings("term", f.items.items[2].type_name);
}

test "a removed item is its marker alone" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/old.md",
        \\%rule[lex.old removed]
        \\
        \\This text is narrative: it says why the rule went.
    );
    try f.expectProblems("");
    try testing.expectEqualStrings("", f.items.items[0].text);
    try testing.expectEqualStrings("removed", f.items.items[0].status.?);
}

test "markers that are wrong or have no text" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/bad.md",
        \\%rule[a.one syntax legality]
        \\Text.
        \\
        \\%rule[a.two syntax]
        \\
        \\## A heading, not text
        \\
        \\%rule[a.three syntax stage=s0,s1]
        \\Text.
        \\
        \\%rule[a.four syntax stage=s0 stage=s1]
        \\Text.
        \\
        \\%rule[a.five]
    );
    try f.expectProblems(
        \\spec/bad.md:1:1: error: a.one: 'legality' is one category or status too many
        \\spec/bad.md:4:1: error: a.two: the marker has no text after it
        \\spec/bad.md:8:1: error: a.three: 'stage' takes one value
        \\spec/bad.md:11:1: error: a.four: 'stage' is given twice
        \\spec/bad.md:14:1: error: a.five: the marker has no text after it
        \\
    );
}

test "an item file: front matter and text" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.itemFile("requirements/SRS-012.md",
        \\+++
        \\id = "SRS-012"
        \\status = "approved"
        \\priority = "high"
        \\verification = "test"
        \\refines = ["SRS-001", "SRS-002"]
        \\+++
        \\
        \\The software shall record the time of each measurement.
        \\
        \\See %[SRS-001].
    , "srs");
    try f.expectProblems("");
    const item = f.items.items[0];
    try testing.expectEqualStrings("SRS-012", item.id);
    try testing.expectEqualStrings("srs", item.type_name);
    try testing.expectEqualStrings("approved", item.status.?);
    try testing.expectEqualStrings("test", item.verification.?);
    try testing.expectEqualStrings("high", item.attribute("priority").?);
    try testing.expectEqual(2, item.links.len);
    try testing.expect(std.mem.startsWith(u8, item.text, "The software shall"));
    try testing.expect(std.mem.endsWith(u8, item.text, "%[SRS-001]."));
    try testing.expectEqual(11, item.references[0].line);
}

test "front matter values other than strings" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.itemFile("spec/a.md",
        \\+++
        \\id = "a.b"
        \\type = "rule"
        \\category = "syntax"
        \\since = 2027-03-01
        \\weight = 3
        \\final = true
        \\+++
        \\Text.
    , null);
    try f.expectProblems("");
    const item = f.items.items[0];
    try testing.expectEqualStrings("2027-03-01", item.attribute("since").?);
    try testing.expectEqualStrings("3", item.attribute("weight").?);
    try testing.expectEqualStrings("true", item.attribute("final").?);
}

test "item files that are not items" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.itemFile("requirements/a.md", "Just text.\n", "srs");
    try f.itemFile("requirements/b.md", "+++\nid = \"SRS-001\"\n\nText.\n", "srs");
    try f.itemFile("requirements/c.md", "+++\nid = \n+++\nText.\n", "srs");
    try f.itemFile("requirements/d.md", "+++\npriority = \"low\"\n+++\nText.\n", "srs");
    try f.itemFile("requirements/e.md", "+++\nid = \"x.y\"\n+++\nText.\n", null);
    try f.itemFile("requirements/f.md", "+++\nid = \"SRS-002\"\npriority = \"low\"\n+++\n", "srs");
    try f.itemFile("requirements/g.md", "+++\nid = \"SRS-003\"\npriority = 1.5\n+++\nText.\n", "srs");
    try f.expectProblems(
        \\requirements/b.md:1:1: error: the front matter is not closed by a +++ line
        \\requirements/c.md:2:6: error: expected a value
        \\requirements/d.md:1:1: error: the front matter has no id
        \\requirements/e.md:1:1: error: x.y: the front matter has no type, and its source gives none
        \\requirements/f.md:1:1: error: SRS-002: the item has no text
        \\requirements/g.md:1:1: error: SRS-003: 'priority' must be a string, a number, true or false, a date, or an array of strings
        \\
    );
}
