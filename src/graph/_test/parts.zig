//! Markers with their text on the same line, items in lists, and parts.

// req: items.marker.inline, items.list-entries, items.parts, items.parts.names, items.parts.text, items.reference.narrative
// req: items.marker.words, items.marker.types-only
const std = @import("std");
const testing = std.testing;

const Fixture = @import("fixture.zig").Fixture;

test "the text may start on the marker's line" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md",
        \\%rule[lex.comment syntax] A comment starts with `//`
        \\and ends with the line. See %[lex.token].
        \\
        \\%term[lex.token] A token.
        \\
        \\Narrative.
    );
    try f.expectProblems("");
    try testing.expectEqual(2, f.items.items.len);
    const comment = f.items.items[0];
    try testing.expectEqualStrings("A comment starts with `//`\nand ends with the line. See %[lex.token].", comment.text);
    try testing.expectEqual(1, comment.line);
    try testing.expectEqual(2, comment.references[0].line);
    try testing.expectEqual(29, comment.references[0].column);
    try testing.expectEqualStrings("A token.", f.items.items[1].text);
}

test "a reference on the marker's line is found where it stands" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md", "%term[lex.token] As %[lex.other] says.\n");
    const ref = f.items.items[0].references[0];
    try testing.expectEqual(1, ref.line);
    try testing.expectEqual(21, ref.column);
}

test "a bare word is the category or the status" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md",
        \\%rule[a.one syntax approved] One.
        \\
        \\%rule[a.two deprecated legality] Two.
        \\
        \\%rule[a.three removed]
        \\
        \\%test[t.one retired]
    );
    try f.expectProblems("");
    const items = f.items.items;
    try testing.expectEqualStrings("syntax", items[0].category.?);
    try testing.expectEqualStrings("approved", items[0].status.?);
    try testing.expectEqualStrings("legality", items[1].category.?);
    try testing.expectEqualStrings("deprecated", items[1].status.?);
    try testing.expectEqualStrings("removed", items[2].status.?);
    try testing.expectEqualStrings("retired", items[3].status.?);
}

test "entries of a list are items" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md",
        \\The rules of comments:
        \\
        \\1. %rule[lex.comment.start syntax] A comment starts with `//`.
        \\2. %rule[lex.comment.end syntax]
        \\   It ends with the line.
        \\
        \\   ```text
        \\   // like this
        \\   ```
        \\3. Not an item.
        \\   - %term[lex.nested] An entry further in.
    );
    try f.expectProblems("");
    const items = f.items.items;
    try testing.expectEqual(3, items.len);
    try testing.expectEqualStrings("A comment starts with `//`.", items[0].text);
    try testing.expectEqual(3, items[0].line);
    try testing.expectEqualStrings("It ends with the line.\n\n```text\n// like this\n```", items[1].text);
    try testing.expectEqual(4, items[1].line);
    try testing.expectEqualStrings("lex.nested", items[2].id);
    try testing.expectEqual(11, items[2].line);
    // none is part of another: the list belongs to no item
    for (items) |item| try testing.expectEqual(null, item.parent);
}

test "the marked entries of an item's list are its parts" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md",
        \\%rule[lex.keywords syntax] The keywords are:
        \\
        \\- %rule[.as syntax] `as`, which converts.
        \\- %rule[.fn syntax approved] `fn`, of which there are:
        \\  - %rule[.plain syntax] the plain one
        \\  - %rule[lex.other syntax] one named in full
        \\- and no others
        \\
        \\%rule[lex.after syntax] Not a part.
    );
    try f.expectProblems("");
    const items = f.items.items;
    try testing.expectEqual(6, items.len);

    // each whole before its parts
    const keywords = items[0];
    try testing.expectEqualStrings("lex.keywords", keywords.id);
    try testing.expectEqual(null, keywords.parent);
    try testing.expectEqual(2, keywords.parts.len);
    try testing.expectEqualStrings("lex.keywords.as", keywords.parts[0]);
    try testing.expectEqualStrings("lex.keywords.fn", keywords.parts[1]);
    // its own text: what its parts do not say
    try testing.expectEqualStrings("The keywords are:\n\n- and no others", keywords.text);

    try testing.expectEqualStrings("lex.keywords.as", items[1].id);
    try testing.expectEqualStrings("lex.keywords", items[1].parent.?);
    try testing.expectEqualStrings("`as`, which converts.", items[1].text);
    try testing.expectEqual(3, items[1].line);

    const function = items[2];
    try testing.expectEqualStrings("lex.keywords.fn", function.id);
    try testing.expectEqualStrings("approved", function.status.?);
    try testing.expectEqualStrings("`fn`, of which there are:", function.text);
    try testing.expectEqual(2, function.parts.len);
    try testing.expectEqualStrings("lex.keywords.fn.plain", function.parts[0]);
    // a name without the dot is the ID as written
    try testing.expectEqualStrings("lex.other", function.parts[1]);
    try testing.expectEqualStrings("lex.keywords.fn", items[4].parent.?);
    try testing.expectEqual(6, items[4].line);

    try testing.expectEqualStrings("lex.after", items[5].id);
    try testing.expectEqual(null, items[5].parent);
}

test "a list without marked entries is the item's own text" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md",
        \\%rule[lex.keywords syntax] The keywords are:
        \\
        \\- `as`
        \\- `fn`
    );
    try f.expectProblems("");
    try testing.expectEqual(1, f.items.items.len);
    try testing.expectEqualStrings("The keywords are:\n\n- `as`\n- `fn`", f.items.items[0].text);
    try testing.expectEqual(0, f.items.items[0].parts.len);
}

test "an entry that holds a part further in stays the whole's own text" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md",
        \\%rule[lex.keywords syntax] The keywords are:
        \\
        \\- those of conversion:
        \\  - %rule[.as syntax] `as`
    );
    try f.expectProblems("");
    const keywords = f.items.items[0];
    try testing.expectEqualStrings("lex.keywords.as", keywords.parts[0]);
    try testing.expect(std.mem.find(u8, keywords.text, "those of conversion:") != null);
}

test "a part of a numbered item extends its number" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/srs.md",
        \\%srs[SRS-001 priority=low] The software shall:
        \\
        \\- %srs[.a priority=low] start;
        \\- %srs[.b priority=low] stop.
    );
    try f.expectProblems("");
    try testing.expectEqualStrings("SRS-001.a", f.items.items[0].parts[0]);
    try testing.expectEqualStrings("SRS-001.b", f.items.items[2].id);
}

test "mistakes in the names of parts and in markers" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/bad.md",
        \\%rule[.alone syntax] A dot, and part of nothing.
        \\
        \\- %rule[.entry syntax] The same, in a list of no item.
        \\
        \\%srs[SRS-001 priority=low] A numbered item:
        \\
        \\- %rule[.part syntax] Its part cannot extend its ID.
        \\
        \\%rule[a.b syntax] A rule:
        \\
        \\- %srs[.1 priority=low] Nor can a numbered part.
        \\
        \\%nothing[a.c] No such type.
        \\
        \\%rule[a.d syntax
        \\Not closed.
        \\
        \\%rule[a.e syntax]
    );
    try f.expectProblems(
        \\spec/bad.md:1:1: error: .alone: an ID that starts with a dot extends the ID of a containing item, and this item is not part of another item
        \\spec/bad.md:3:3: error: .entry: an ID that starts with a dot extends the ID of a containing item, and this item is not part of another item
        \\spec/bad.md:7:3: error: .part: an ID that starts with a dot needs IDs of one kind, hierarchical or numbered, for this item and for 'SRS-001'
        \\spec/bad.md:11:3: error: .1: an ID that starts with a dot needs IDs of one kind, hierarchical or numbered, for this item and for 'a.b'
        \\spec/bad.md:13:1: error: a.c: there is no item type 'nothing'
        \\spec/bad.md:15:1: error: %rule[...]: the marker is not closed by ']'
        \\spec/bad.md:18:1: error: a.e: the marker has no text after it
        \\
    );
}

test "references in narrative text are read and checked" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md", "# About %[lex.token]\n\nNarrative that names %[lex.token the token] and\nthen %[no.such].\n\n" ++
        "%rule[lex.keywords syntax] The keywords, see %[lex.token]:\n\n" ++
        "- %rule[.as syntax] `as`\n\n  A note under the part: %[lex.gone].\n- its own text: %[lex.token]\n\n" ++
        "Narrative.\n\n- a list of no item: %[lex.keywords.as]\n\n" ++
        "```text\n%[in.code]\n```\n\n" ++
        "%term[lex.token] A token.\n\n%rule[lex.gone removed]\n\n%[lex.forgot] A marker without its type.\n");
    const graph = try f.check();
    try f.expectProblems("spec/lex.md:4:6: error: the text refers to 'no.such', and there is no such item\n" ++
        "spec/lex.md:10:26: error: the text refers to 'lex.gone', which is removed\n" ++
        "spec/lex.md:25:1: error: the text refers to 'lex.forgot', and there is no such item\n");
    // what an item says is its own, not narrative
    try testing.expectEqual(6, graph.mentions.len);
    try testing.expectEqualStrings("lex.token", graph.mentions[0].target);
    try testing.expectEqual(1, graph.mentions[0].line);
    try testing.expectEqual(9, graph.mentions[0].column);
    try testing.expectEqual(3, graph.mentions[1].line);
    try testing.expectEqual(22, graph.mentions[1].column);
    try testing.expectEqualStrings("lex.keywords.as", graph.mentions[4].target);
    try testing.expectEqual(15, graph.mentions[4].line);
    try testing.expectEqual(2, f.items.items[0].references.len);
}
