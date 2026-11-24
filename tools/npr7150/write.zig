//! A chapter of NPR 7150.2D as a skein document: each requirement an
//! item of the type `swe`, its lettered sub-parts its parts, its notes
//! quoted under it, and the rest as the narrative it is.

const std = @import("std");

const appendix = @import("appendix.zig");
const html = @import("html.zig");

/// What a requirement's handbook page is, by SWE
pub const Page = struct { id: []const u8, title: []const u8, url: []const u8 };

pub const Source = struct {
    /// the page of the chapter on NODIS
    url: []const u8,
    effective: []const u8,
    retrieved: []const u8,
};

const Error = std.mem.Allocator.Error;

const Line = enum { none, block, entry, note };

pub fn chapter(arena: std.mem.Allocator, blocks: []const html.Block, matrix: []const appendix.Row, pages: []const Page, source: Source) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "<!-- NPR 7150.2D, NASA Software Engineering Requirements (effective {s}), from {s}, retrieved {s}. Taken by tools/npr7150 in skein's repository (zig build npr7150), and kept by hand from here when NASA revises the NPR. -->", .{ source.effective, source.url, source.retrieved });
    var last: Line = .block;
    // whether the paragraphs read last are a requirement and its parts
    var in_swe = false;
    for (blocks) |b| {
        switch (b.kind) {
            .heading1, .heading2 => {
                try gap(arena, &out, &last, .block);
                try out.print(arena, "{s} {s}", .{ if (b.kind == .heading1) "#" else "##", try escape(arena, b.text) });
                in_swe = false;
            },
            .note => {
                // notes in a row are one quote, not two quotes with a blank line between
                if (last == .note) try out.appendSlice(arena, "\n>\n") else try gap(arena, &out, &last, .block);
                last = .note;
                var lines = std.mem.splitScalar(u8, b.text, '\n');
                var first = true;
                while (lines.next()) |l| : (first = false) try out.print(arena, "{s}> {s}", .{ if (first) "" else "\n", try escape(arena, l) });
            },
            .table => {
                try gap(arena, &out, &last, .block);
                for (b.rows, 0..) |row, i| {
                    if (i > 0) try out.append(arena, '\n');
                    try out.append(arena, '|');
                    for (row) |cell| try out.print(arena, "{s}{s}{s}|", .{ if (cell.len > 0) " " else "", try escapeCell(arena, cell), " " });
                    if (i == 0) {
                        try out.appendSlice(arena, "\n|");
                        for (row) |_| try out.appendSlice(arena, " --- |");
                    }
                }
            },
            .paragraph => if (try requirement(arena, b.text, matrix, pages)) |item| {
                try gap(arena, &out, &last, .block);
                try out.appendSlice(arena, item);
                in_swe = true;
            } else if (in_swe and letterPart(b.text) != null) {
                const p = letterPart(b.text).?;
                try gap(arena, &out, &last, .entry);
                try out.print(arena, "- %swe[.{c}] {s}", .{ p.letter, try escape(arena, p.text) });
            } else if (in_swe and last == .entry and std.mem.startsWith(u8, b.text, "(")) {
                try gap(arena, &out, &last, .entry);
                try out.print(arena, "  - {s}", .{try escape(arena, b.text)});
            } else if (std.mem.startsWith(u8, b.text, "\u{2022}")) {
                try gap(arena, &out, &last, .entry);
                try out.print(arena, "- {s}", .{try escape(arena, std.mem.trim(u8, b.text["\u{2022}".len..], " \t"))});
            } else {
                try gap(arena, &out, &last, .block);
                try out.appendSlice(arena, try escape(arena, b.text));
                in_swe = false;
            },
        }
    }
    try out.append(arena, '\n');
    return out.items;
}

/// Ends what came before: list entries follow each other line by line,
/// anything else after a blank line
fn gap(arena: std.mem.Allocator, out: *std.ArrayList(u8), last: *Line, next: Line) Error!void {
    if (last.* != .none) try out.appendSlice(arena, if (last.* == .entry and next == .entry) "\n" else "\n\n");
    last.* = next;
}

/// The paragraph as a requirement's marker and text, when it ends with
/// its `[SWE-nnn]`
fn requirement(arena: std.mem.Allocator, text: []const u8, matrix: []const appendix.Row, pages: []const Page) Error!?[]const u8 {
    // one tag has a period after it: `[SWE-153].`
    const trimmed = std.mem.trimEnd(u8, text, " .");
    if (!std.mem.endsWith(u8, trimmed, "]")) return null;
    const open = std.mem.findLast(u8, trimmed, "[SWE-") orelse return null;
    const id = trimmed[open + 1 .. trimmed.len - 1];
    var body = std.mem.trimEnd(u8, trimmed[0..open], " ");
    // the paragraph number it starts with
    var n: usize = 0;
    while (n < body.len and (std.ascii.isDigit(body[n]) or body[n] == '.')) n += 1;
    const section = std.mem.trimEnd(u8, body[0..n], ".");
    body = std.mem.trimStart(u8, body[n..], " ");

    var marker: std.ArrayList(u8) = .empty;
    try marker.print(arena, "%swe[{s}", .{id});
    if (section.len > 0) try marker.print(arena, " section={s}", .{section});
    if (appendix.find(matrix, id)) |row| {
        if (row.classes.len > 0) {
            try marker.appendSlice(arena, " classes=");
            for (row.classes, 0..) |c, i| try marker.print(arena, "{s}{c}", .{ if (i > 0) "," else "", c });
        }
        if (row.authority.len > 0) try marker.print(arena, " authority={s}", .{try value(arena, row.authority)});
        if (row.authority_f.len > 0) try marker.print(arena, " authority_f={s}", .{try value(arena, row.authority_f)});
        // whether it binds every project of its classes, or those with safety-critical software
        const conditional = std.mem.startsWith(u8, body, "If a project has safety-critical software");
        try marker.print(arena, " applies={s}", .{if (conditional) "safety-critical" else "always"});
    }
    for (pages) |p| if (std.mem.eql(u8, p.id, id)) {
        try marker.print(arena, " title=\"{s}\" handbook={s}", .{ p.title, p.url });
    };
    try marker.print(arena, "] {s}", .{try escape(arena, body)});
    return marker.items;
}

/// A value of a marker, in double quotes when it has a space
fn value(arena: std.mem.Allocator, v: []const u8) Error![]const u8 {
    return if (std.mem.findScalar(u8, v, ' ') != null) try arena.print("\"{s}\"", .{v}) else v;
}

const Part = struct { letter: u8, text: []const u8 };

/// `a. Text`: a lettered sub-part
fn letterPart(text: []const u8) ?Part {
    if (text.len < 4 or !std.ascii.isLower(text[0]) or text[1] != '.' or text[2] != ' ') return null;
    return .{ .letter = text[0], .text = text[3..] };
}

/// `text` safe as Markdown and as skein's text: emphasis characters,
/// angle brackets and the start of a reference escaped
pub fn escape(arena: std.mem.Allocator, text: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (text, 0..) |c, i| switch (c) {
        '*', '_', '`' => try out.print(arena, "\\{c}", .{c}),
        '<' => try out.appendSlice(arena, "&lt;"),
        '%' => try out.appendSlice(arena, if (i + 1 < text.len and text[i + 1] == '[') "\\%" else "%"),
        else => try out.append(arena, c),
    };
    return out.items;
}

fn escapeCell(arena: std.mem.Allocator, text: []const u8) Error![]const u8 {
    const escaped = try escape(arena, text);
    var out: std.ArrayList(u8) = .empty;
    for (escaped) |c| switch (c) {
        '|' => try out.appendSlice(arena, "\\|"),
        '\n' => try out.append(arena, ' '),
        else => try out.append(arena, c),
    };
    return out.items;
}

const testing = std.testing;

test chapter {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const blocks = [_]html.Block{
        .{ .kind = .heading2, .text = "3.1 Planning" },
        .{ .kind = .paragraph, .text = "3.1.4 The project manager shall track *results*. [SWE-024]" },
        .{ .kind = .paragraph, .text = "a. Corrective actions are taken." },
        .{ .kind = .paragraph, .text = "(1) One." },
        .{ .kind = .paragraph, .text = "b. Changes are managed." },
        .{ .kind = .note, .text = "Note: Track it." },
        .{ .kind = .note, .text = "Note: And report it." },
        .{ .kind = .paragraph, .text = "Narrative, then a list:" },
        .{ .kind = .paragraph, .text = "\u{2022}\tOne thing" },
    };
    const matrix = [_]appendix.Row{.{ .section = "3.1.4", .id = "SWE-024", .authority = "Center and Center CIO", .authority_f = "CIO", .classes = "ABF" }};
    const pages = [_]Page{.{ .id = "SWE-024", .title = "Plan Tracking", .url = "https://example.invalid/SWE-024" }};
    const text = try chapter(a, &blocks, &matrix, &pages, .{ .url = "u", .effective = "e", .retrieved = "r" });
    try testing.expectEqualStrings(
        \\## 3.1 Planning
        \\
        \\%swe[SWE-024 section=3.1.4 classes=A,B,F authority="Center and Center CIO" authority_f=CIO applies=always title="Plan Tracking" handbook=https://example.invalid/SWE-024] The project manager shall track \*results\*.
        \\
        \\- %swe[.a] Corrective actions are taken.
        \\  - (1) One.
        \\- %swe[.b] Changes are managed.
        \\
        \\> Note: Track it.
        \\>
        \\> Note: And report it.
        \\
        \\Narrative, then a list:
        \\
        \\- One thing
        \\
    , text[std.mem.find(u8, text, "-->\n\n").? + 5 ..]);
}
