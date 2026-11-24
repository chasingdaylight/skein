//! A PDF file's objects, by number: those written at the top level and
//! those inside object streams; and the data of streams, inflated.

const std = @import("std");

const parse = @import("parse.zig");

const Document = @This();

pub const Value = parse.Value;
pub const Ref = parse.Ref;

arena: std.mem.Allocator,
objects: std.AutoHashMapUnmanaged(u32, Value) = .empty,

pub const Error = parse.Error || error{ UnsupportedFilter, BadStream };

/// Reads every object of `src`: it scans for `N G obj`, rather than trust
/// the cross-reference table, so a damaged or updated file still reads
pub fn read(arena: std.mem.Allocator, src: []const u8) Error!Document {
    var doc: Document = .{ .arena = arena };
    var at: usize = 0;
    while (std.mem.findPos(u8, src, at, " obj")) |hit| {
        at = hit + 4;
        const head = objectHead(src, hit) orelse continue;
        var p: parse.Parser = .{ .arena = arena, .src = src, .at = hit + 4 };
        var v = p.value() catch continue;
        p.skipSpace();
        if (v == .dict and std.mem.startsWith(u8, src[p.at..], "stream")) {
            // built apart: assigning to `v` straight away would overwrite what it reads
            const s: Value = .{ .stream = .{ .dict = v.dict, .raw = streamData(src, p.at + "stream".len, v) } };
            v = s;
        }
        try doc.objects.put(arena, head, v);
        at = p.at;
    }
    // the objects inside object streams
    var it = doc.objects.iterator();
    var streams: std.ArrayList(Value) = .empty;
    while (it.next()) |e| {
        const t = e.value_ptr.get("Type") orelse continue;
        if (t == .name and std.mem.eql(u8, t.name, "ObjStm")) try streams.append(arena, e.value_ptr.*);
    }
    for (streams.items) |s| doc.expand(s) catch continue;
    return doc;
}

/// The number of the object whose `obj` keyword is at `at`: `12 0 obj`
fn objectHead(src: []const u8, at: usize) ?u32 {
    var i = at;
    var nums: [2]u32 = undefined;
    var k: usize = 2;
    while (k > 0) {
        k -= 1;
        while (i > 0 and src[i - 1] == ' ') i -= 1;
        const end = i;
        while (i > 0 and std.ascii.isDigit(src[i - 1])) i -= 1;
        if (i == end) return null;
        nums[k] = std.fmt.parseInt(u32, src[i..end], 10) catch return null;
    }
    if (i > 0 and !parse.isSpace(src[i - 1]) and !parse.isDelimiter(src[i - 1])) return null;
    return nums[0];
}

/// The bytes of a stream that starts after its `stream` keyword
fn streamData(src: []const u8, after: usize, dict: Value) []const u8 {
    var start = after;
    if (start < src.len and src[start] == '\r') start += 1;
    if (start < src.len and src[start] == '\n') start += 1;
    if (dict.get("Length")) |len| if (len == .number) {
        const n: usize = @intFromFloat(len.number);
        if (start + n <= src.len and std.mem.startsWith(u8, std.mem.trimStart(u8, src[start + n ..], "\r\n "), "endstream")) return src[start .. start + n];
    };
    const end = std.mem.findPos(u8, src, start, "endstream") orelse src.len;
    return std.mem.trimEnd(u8, src[start..end], "\r\n");
}

fn expand(self: *Document, s: Value) Error!void {
    const data = try self.decode(s);
    const n: usize = @intFromFloat((s.get("N") orelse return).number);
    const first: usize = @intFromFloat((s.get("First") orelse return).number);
    var header: parse.Parser = .{ .arena = self.arena, .src = data[0..@min(first, data.len)] };
    for (0..n) |_| {
        const num = try header.value();
        const offset = try header.value();
        if (num != .number or offset != .number) return error.Malformed;
        const at = first + @as(usize, @intFromFloat(offset.number));
        if (at >= data.len) continue;
        var p: parse.Parser = .{ .arena = self.arena, .src = data, .at = at };
        const v = p.value() catch continue;
        const key: u32 = @intFromFloat(num.number);
        if (!self.objects.contains(key)) try self.objects.put(self.arena, key, v);
    }
}

/// `v`, or the object it refers to
pub fn resolve(self: *const Document, v: ?Value) ?Value {
    const value = v orelse return null;
    return switch (value) {
        .ref => |r| self.objects.get(r.num),
        else => value,
    };
}

/// The data of a stream, its filters undone (FlateDecode, or none)
pub fn decode(self: *const Document, s: Value) Error![]const u8 {
    if (s != .stream) return error.BadStream;
    const filter = self.resolve(s.get("Filter")) orelse return s.stream.raw;
    const name = switch (filter) {
        .name => |n| n,
        .array => |a| if (a.len == 1 and a[0] == .name) a[0].name else return error.UnsupportedFilter,
        else => return error.UnsupportedFilter,
    };
    if (!std.mem.eql(u8, name, "FlateDecode")) return error.UnsupportedFilter;
    var in: std.Io.Reader = .fixed(s.stream.raw);
    var inflate: std.compress.flate.Decompress = .init(&in, .zlib, &.{});
    var out: std.Io.Writer.Allocating = .init(self.arena);
    _ = inflate.reader.streamRemaining(&out.writer) catch return error.BadStream;
    return out.written();
}

test read {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const src = "%PDF-1.7\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Length 5 >>\nstream\nhello\nendstream\nendobj\n";
    const doc = try read(arena.allocator(), src);
    try std.testing.expectEqualStrings("Catalog", doc.objects.get(1).?.get("Type").?.name);
    try std.testing.expectEqualStrings("hello", try doc.decode(doc.objects.get(2).?));
}
