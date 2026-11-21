//! Rendering documents and item files to Markdown.

// req: render.markdown, render.markdown.markers, render.markdown.references, render.markdown.item-files
const std = @import("std");
const testing = std.testing;

const Fixture = @import("../../graph/_test/fixture.zig").Fixture;
const fixture_schema = @import("../../graph/_test/fixture.zig").schema;
const render = @import("../markdown.zig");

const lex =
    \\# Lexical structure
    \\
    \\Narrative that names %[lex.token the token] and `%[lex.token]` in code.
    \\
    \\%rule[lex.comment syntax approved] A comment is not a %[lex.token].
    \\
    \\%rule[lex.keywords syntax]
    \\The keywords, as %[SRS-001] requires:
    \\
    \\- %rule[.as syntax] `as`
    \\  1. %rule[.cast] See %[lex.keywords.fn].
    \\- %rule[.fn syntax] `fn`
    \\- no others, and not %[no.such]
    \\
    \\```text
    \\%rule[in.code] %[lex.token]
    \\```
    \\
    \\%rule[lex.old removed]
    \\
;

const terms = "%term[lex.token] A token: see %[lex.comment comments] and %[other:some.id].\r\n";

const srs =
    \\+++
    \\id = "SRS-001"
    \\priority = "high"
    \\+++
    \\
    \\The keywords of %[lex.keywords] are reserved; see also %[SRS-001].
    \\
;

fn context(f: *Fixture, graph: *const @import("../../graph/Graph.zig")) render.Context {
    return .{ .arena = f.arena.allocator(), .graph = graph, .schema = &fixture_schema, .item_sources = &.{"requirements"} };
}

test "markers become anchors and IDs, references become links" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md", lex);
    try f.document("spec/terms/terms.md", terms);
    try f.itemFile("requirements/SRS-001.md", srs, "srs");
    var graph = try @import("../../graph/Graph.zig").init(f.arena.allocator(), f.items.items, &f.report);
    graph.mentions = f.mentions.items;
    const ctx = context(&f, &graph);

    try testing.expectEqualStrings(
        \\# Lexical structure
        \\
        \\Narrative that names [the token](terms/terms.md#lex.token) and `%[lex.token]` in code.
        \\
        \\<a id="lex.comment"></a>**[lex.comment](#lex.comment)** *(syntax, approved)* A comment is not a [lex.token](terms/terms.md#lex.token).
        \\
        \\<a id="lex.keywords"></a>**[lex.keywords](#lex.keywords)** *(syntax)*
        \\The keywords, as [SRS-001](../requirements/SRS-001.md) requires:
        \\
        \\- <a id="lex.keywords.as"></a>**[lex.keywords.as](#lex.keywords.as)** *(syntax)* `as`
        \\  1. <a id="lex.keywords.as.cast"></a>**[lex.keywords.as.cast](#lex.keywords.as.cast)** See [lex.keywords.fn](#lex.keywords.fn).
        \\- <a id="lex.keywords.fn"></a>**[lex.keywords.fn](#lex.keywords.fn)** *(syntax)* `fn`
        \\- no others, and not no.such
        \\
        \\```text
        \\%rule[in.code] %[lex.token]
        \\```
        \\
        \\<a id="lex.old"></a>**[lex.old](#lex.old)** *(removed)*
        \\
    , try render.document(ctx, "spec/lex.md", lex));

    // line ends are kept, and a reference into another repository is its ID
    try testing.expectEqualStrings(
        "<a id=\"lex.token\"></a>**[lex.token](#lex.token)** A token: see [comments](../lex.md#lex.comment) and other:some.id.\r\n",
        try render.document(ctx, "spec/terms/terms.md", terms),
    );
}

test "an item file gets the front matter of site generators" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md", lex);
    try f.itemFile("requirements/SRS-001.md", srs, "srs");
    var graph = try @import("../../graph/Graph.zig").init(f.arena.allocator(), f.items.items, &f.report);
    graph.mentions = f.mentions.items;
    const ctx = context(&f, &graph);

    try testing.expectEqualStrings(
        \\---
        \\title: "SRS-001"
        \\---
        \\
        \\The keywords of [lex.keywords](../spec/lex.md#lex.keywords) are reserved; see also SRS-001.
        \\
    , try render.itemFile(ctx, "requirements/SRS-001.md", srs));

    // a file of the directory that is no item is kept as it is
    const readme = "# Requirements\n\nSee %[lex.token].\n";
    try testing.expectEqualStrings(readme, try render.itemFile(ctx, "requirements/readme.md", readme));
}
