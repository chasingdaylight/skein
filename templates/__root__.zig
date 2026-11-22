//! The templates that come with skein, built into the program: each a
//! directory of this one, laid out as a project's `.skein/` is, with a
//! `template.toml` that describes it. Every file of a template is listed
//! here; a test holds the list to the directory.

pub const File = struct {
    /// the template's name: its directory
    template: []const u8,
    /// within the template, with forward slashes
    path: []const u8,
    data: []const u8,
};

pub const files = [_]File{
    .{ .template = "langspec", .path = "template.toml", .data = @embedFile("langspec/template.toml") },
    .{ .template = "langspec", .path = "types/rule.toml", .data = @embedFile("langspec/types/rule.toml") },
    .{ .template = "langspec", .path = "types/term.toml", .data = @embedFile("langspec/types/term.toml") },
    .{ .template = "langspec", .path = "types/example.toml", .data = @embedFile("langspec/types/example.toml") },
    .{ .template = "langspec", .path = "links/shows.toml", .data = @embedFile("langspec/links/shows.toml") },
    .{ .template = "langspec", .path = "links/see.toml", .data = @embedFile("langspec/links/see.toml") },
    .{ .template = "langspec", .path = "types/test.toml", .data = @embedFile("langspec/types/test.toml") },
    .{ .template = "langspec", .path = "links/verifies.toml", .data = @embedFile("langspec/links/verifies.toml") },
    .{ .template = "langspec", .path = "config.toml", .data = @embedFile("langspec/config.toml") },
    .{ .template = "langspec", .path = "documents/charter.md", .data = @embedFile("langspec/documents/charter.md") },
    .{ .template = "langspec", .path = "documents/introduction.md", .data = @embedFile("langspec/documents/introduction.md") },
    .{ .template = "langspec", .path = "documents/glossary.md", .data = @embedFile("langspec/documents/glossary.md") },
    .{ .template = "langspec", .path = "documents/coverage.md", .data = @embedFile("langspec/documents/coverage.md") },
};
