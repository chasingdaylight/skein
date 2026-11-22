//! Markdown documents as HTML.

// req: html.blocks, html.headings, html.lists, html.code, html.tables
const std = @import("std");
const testing = std.testing;

const blocks = @import("../blocks.zig");

fn expectHtml(expected: []const u8, source: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var doc: blocks.Document = .{ .arena = arena.allocator() };
    try doc.render(source);
    try testing.expectEqualStrings(expected, doc.out.items);
}

test "headings get anchors, kept apart; the first sets the title" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var doc: blocks.Document = .{ .arena = arena.allocator() };
    try doc.render("# The `skein` tool #\n\n## Getting it\n\n## Getting it\n\n### A *b*: c, d!\n");
    try testing.expectEqualStrings(
        \\<h1 id="the-skein-tool">The <code>skein</code> tool</h1>
        \\<h2 id="getting-it">Getting it</h2>
        \\<h2 id="getting-it-1">Getting it</h2>
        \\<h3 id="a-b-c-d">A <em>b</em>: c, d!</h3>
        \\
    , doc.out.items);
    try testing.expectEqualStrings("The `skein` tool", doc.title.?);
}

test "paragraphs, quotes, breaks, HTML and front matter" {
    try expectHtml(
        \\<p>One
        \\line, then <em>another</em>.</p>
        \\<blockquote>
        \\<p>Quoted <strong>text</strong>.</p>
        \\</blockquote>
        \\<hr>
        \\<div class="note">raw</div>
        \\
    , "+++\nid = \"x\"\n+++\n\nOne\nline, then *another*.\n\n> Quoted **text**.\n\n---\n\n<div class=\"note\">raw</div>\n");
}

test "tight and loose lists, ordered and nested" {
    try expectHtml(
        \\<ul>
        \\<li>one</li>
        \\<li>two
        \\<ol>
        \\<li>three</li>
        \\<li>four</li>
        \\</ol>
        \\</li>
        \\</ul>
        \\
    , "- one\n- two\n  1. three\n  2. four\n");
    // a number other than 1 starts the list there
    try expectHtml("<ol start=\"3\">\n<li>three</li>\n<li>four</li>\n</ol>\n", "3. three\n4. four\n");
    try expectHtml(
        \\<ol>
        \\<li>
        \\<p>First.</p>
        \\</li>
        \\<li>
        \\<p>Second.</p>
        \\<pre><code>code
        \\</code></pre>
        \\</li>
        \\</ol>
        \\
    , "1. First.\n\n2. Second.\n\n   ```\n   code\n   ```\n");
}

test "fenced and indented code, escaped and with its language" {
    try expectHtml(
        \\<pre><code class="language-zig">const a = 1 &lt; 2;
        \\  // indented
        \\</code></pre>
        \\<pre><code>four spaces
        \\</code></pre>
        \\
    , "```zig\nconst a = 1 < 2;\n  // indented\n```\n\n    four spaces\n");
}

test "tables, with alignment and pipes in code" {
    try expectHtml(
        \\<table>
        \\<thead>
        \\<tr><th>Key</th><th style="text-align: center">Value</th><th style="text-align: right">N</th></tr>
        \\</thead>
        \\<tbody>
        \\<tr><td><code>a|b</code></td><td style="text-align: center">x | y</td><td style="text-align: right">3</td></tr>
        \\<tr><td>short</td><td style="text-align: center"></td><td style="text-align: right"></td></tr>
        \\</tbody>
        \\</table>
        \\
    , "| Key | Value | N |\n| --- | :---: | --: |\n| `a|b` | x \\| y | 3 |\n| short |\n");
}

test "CRLF line ends give the same HTML" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const source = "# T\n\nA *b*\nc.\n\n- x\n- y\n\n```\nz\n```\n";
    var lf: blocks.Document = .{ .arena = arena.allocator() };
    try lf.render(source);
    var crlf: blocks.Document = .{ .arena = arena.allocator() };
    try crlf.render(try std.mem.replaceOwned(u8, arena.allocator(), source, "\n", "\r\n"));
    try testing.expectEqualStrings(lf.out.items, crlf.out.items);
}
