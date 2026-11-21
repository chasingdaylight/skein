//! What `skein check` reports about items.

// req: check.ids, check.removed-ids, check.type-rules, check.attributes, check.links, check.references
// req: check.removed-exempt, check.other-repositories, principle.schema-driven
const std = @import("std");
const testing = std.testing;

const Fixture = @import("fixture.zig").Fixture;

test "items that keep every rule give no problems" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/lex.md",
        \\rule[lex.comment.line] legality stage=s0 since=2027-03-01 weight=2 final=true
        \\A line comment is not a [[lex.token]]; see [[other:some.rule]].
        \\
        \\term[lex.token]
        \\A token is a unit of the source text.
        \\
        \\rule[lex.old] status=removed
        \\
        \\test[t.lex.comment] verifies=lex.comment.line,SRS-001 see=other:thing
        \\Checks line comments.
    );
    try f.itemFile("requirements/SRS-001.md", "+++\nid = \"SRS-001\"\npriority = \"high\"\nverification = \"analysis\"\n+++\nThe software shall start.\n", "srs");
    const graph = try f.check();
    try f.expectProblems("");
    try testing.expectEqual(5, graph.items.len);
    try testing.expectEqualStrings("spec/lex.md", graph.find("lex.token").?.file);
    try testing.expectEqual(null, graph.find("no.such"));
}

test "IDs: used twice, or not as the type spells them" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/a.md",
        \\term[lex.token]
        \\One.
        \\
        \\term[lex.token]
        \\Two.
        \\
        \\term[Lex.Token]
        \\Three.
    );
    try f.itemFile("requirements/x.md", "+++\nid = \"REQ-1\"\npriority = \"low\"\n+++\nText.\n", "srs");
    _ = try f.check();
    try f.expectProblems(
        \\requirements/x.md:1:1: error: REQ-1: the ID of a 'srs' is 'SRS-' and 3 or more digits
        \\spec/a.md:4:1: error: lex.token: the ID is already used at spec/a.md:1
        \\spec/a.md:7:1: error: Lex.Token: the ID of a 'term' is lowercase words joined by dots, like 'lex.comment.line'
        \\
    );
}

test "a removed item keeps its ID taken" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/a.md",
        \\term[lex.old] status=removed
        \\
        \\term[lex.old]
        \\The ID used again.
    );
    _ = try f.check();
    try f.expectProblems(
        \\spec/a.md:3:1: error: lex.old: the ID is already used at spec/a.md:1
        \\
    );
}

test "categories, statuses and verification methods" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/a.md",
        \\rule[a.none]
        \\A rule needs a category.
        \\
        \\rule[a.wrong] semantics status=frozen
        \\Neither is known.
        \\
        \\term[a.term] syntax verification=test
        \\A term has neither.
    );
    _ = try f.check();
    try f.expectProblems(
        \\spec/a.md:1:1: error: a.none: a 'rule' needs a category
        \\spec/a.md:4:1: error: a.wrong: 'frozen' is not a status of a 'rule'
        \\spec/a.md:4:1: error: a.wrong: 'semantics' is not a category of a 'rule'
        \\spec/a.md:7:1: error: a.term: 'test' is not a verification method of a 'term'
        \\spec/a.md:7:1: error: a.term: a 'term' has no categories, so 'syntax' is none
        \\
    );
}

test "attributes: unknown, of the wrong kind, missing" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/a.md",
        \\rule[a.b] syntax stage=s2 since=March weight=heavy final=yes shape=round
        \\Text.
    );
    try f.itemFile("requirements/SRS-001.md", "+++\nid = \"SRS-001\"\n+++\nText.\n", "srs");
    try f.itemFile("requirements/SRS-002.md", "+++\nid = \"SRS-002\"\nstatus = \"removed\"\n+++\n", "srs");
    _ = try f.check();
    try f.expectProblems(
        \\requirements/SRS-001.md:1:1: error: SRS-001: a 'srs' needs the attribute 'priority'
        \\spec/a.md:1:1: error: a.b: 'final' must be true or false
        \\spec/a.md:1:1: error: a.b: 's2' is not a value of 'stage'
        \\spec/a.md:1:1: error: a.b: 'shape' is not an attribute of a 'rule', nor a link type
        \\spec/a.md:1:1: error: a.b: 'since' must be a date, like 2027-03-01
        \\spec/a.md:1:1: error: a.b: 'weight' must be an integer
        \\
    );
}

test "links: to nothing, to the wrong type, from the wrong type, missing, to a removed item" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/a.md",
        \\term[a.term]
        \\A term.
        \\
        \\term[a.gone] status=removed
        \\
        \\rule[a.rule] syntax verifies=a.term see=a.gone,a.rule
        \\A rule cannot verify.
        \\
        \\test[t.one] verifies=a.term,no.such
        \\A test of a term, and of nothing.
        \\
        \\test[t.two]
        \\A test of nothing at all.
        \\
        \\test[t.old] status=retired
    );
    _ = try f.check();
    try f.expectProblems(
        \\spec/a.md:6:1: error: a.rule: a 'rule' cannot have a 'verifies' link
        \\spec/a.md:6:1: error: a.rule: see: 'a.gone' is removed
        \\spec/a.md:6:1: error: a.rule: see: an item cannot link to itself
        \\spec/a.md:6:1: error: a.rule: verifies: 'a.term' is a 'term', which this link cannot point to
        \\spec/a.md:9:1: error: t.one: verifies: 'a.term' is a 'term', which this link cannot point to
        \\spec/a.md:9:1: error: t.one: verifies: there is no item 'no.such'
        \\spec/a.md:12:1: error: t.two: a 'test' needs a 'verifies' link
        \\
    );
}

test "references in text: to nothing, to a removed item" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.document("spec/a.md",
        \\term[a.gone] status=removed
        \\
        \\term[a.term]
        \\See [[a.gone]] and
        \\also [[no.such|that one]], but not `[[in.code]]`.
    );
    _ = try f.check();
    try f.expectProblems(
        \\spec/a.md:4:5: error: a.term: the text refers to 'a.gone', which is removed
        \\spec/a.md:5:6: error: a.term: the text refers to 'no.such', and there is no such item
        \\
    );
}

test "an item of a type that does not exist" {
    var f: Fixture = undefined;
    f.init();
    defer f.deinit();
    try f.itemFile("requirements/a.md", "+++\nid = \"N-1\"\ntype = \"need\"\n+++\nText.\n", null);
    _ = try f.check();
    try f.expectProblems(
        \\requirements/a.md:1:1: error: N-1: there is no item type 'need'
        \\
    );
}
