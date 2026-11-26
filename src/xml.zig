//! skein's XML reader, for the formats other tools write: JUnit test
//! results (#129) and ReqIF (#102, #241). Its own code, no dependency. It
//! reads elements, attributes, text, CDATA and the predefined and numeric
//! entities into a tree, and passes over the prolog, comments, processing
//! instructions and a document type declaration. Names keep their prefix.

const std = @import("std");

const Parser = @import("xml/Parser.zig");

pub const Element = @import("xml/Element.zig");
pub const Diagnostic = Parser.Diagnostic;
pub const Error = Parser.Error;
pub const escape = @import("xml/escape.zig").escape;

/// The root element of the document `source`. Names and text that need no
/// decoding point into `source`; the rest is allocated in `arena`. On
/// `error.InvalidXml`, `diag` says where and why.
pub fn parse(arena: std.mem.Allocator, source: []const u8, diag: *Diagnostic) Error!*const Element {
    var p: Parser = .{ .arena = arena, .src = source, .diag = diag };
    return p.document();
}

test {
    _ = @import("xml/_test/parse.zig");
}
