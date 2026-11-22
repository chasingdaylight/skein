//! The Language Server Protocol messages the server reads and writes, of
//! what it uses. Requests are parsed with unknown fields ignored; responses
//! are written without the optional fields that are null.

const json = @import("std").json;

pub const Position = struct { line: usize, character: usize };

pub const Range = struct { start: Position, end: Position };

pub const Location = struct { uri: []const u8, range: Range };

pub const Diagnostic = struct {
    range: Range,
    /// 1 error
    severity: u8 = 1,
    source: []const u8 = "skein",
    message: []const u8,
    /// what would mend it, which the editor gives back for a quick fix
    data: ?Fix = null,
};

pub const Fix = struct { old: []const u8, new: []const u8 };

pub const PublishDiagnosticsParams = struct {
    uri: []const u8,
    diagnostics: []const Diagnostic,
};

/// Full text sync (`change` 1). The project is read from the files, so
/// what `check` says changes when a file is saved.
pub const TextDocumentSyncOptions = struct {
    openClose: bool = true,
    change: u8 = 1,
    save: struct { includeText: bool = false } = .{},
};

pub const ServerCapabilities = struct {
    textDocumentSync: TextDocumentSyncOptions = .{},
    definitionProvider: bool = true,
    referencesProvider: bool = true,
    hoverProvider: bool = true,
    completionProvider: CompletionOptions = .{},
    renameProvider: RenameOptions = .{},
    codeLensProvider: struct { resolveProvider: bool = false } = .{},
    codeActionProvider: struct { codeActionKinds: []const []const u8 = &.{"quickfix"} } = .{},
};

pub const InitializeResult = struct {
    capabilities: ServerCapabilities = .{},
    serverInfo: struct { name: []const u8, version: []const u8 },
};

pub const TextDocumentItem = struct { uri: []const u8, text: []const u8 };

pub const DidOpenParams = struct { textDocument: TextDocumentItem };

pub const DidChangeParams = struct {
    textDocument: struct { uri: []const u8 },
    contentChanges: []const struct { text: []const u8 },
};

/// `didSave` and `didClose`
pub const TextDocumentParams = struct { textDocument: struct { uri: []const u8 } };

/// `definition`, `references` and `hover`
pub const PositionParams = struct {
    textDocument: struct { uri: []const u8 },
    position: Position,
    context: struct { includeDeclaration: bool = true } = .{},
};

pub const Hover = struct {
    contents: struct { kind: []const u8 = "markdown", value: []const u8 },
};

pub const ResponseError = struct { code: i64, message: []const u8 };

pub const error_codes = struct {
    pub const parse_error = -32700;
    pub const invalid_request = -32600;
    pub const method_not_found = -32601;
    pub const invalid_params = -32602;
    pub const server_not_initialized = -32002;
};

pub const CompletionOptions = struct {
    triggerCharacters: []const []const u8 = &.{ "%", "[", "=", ",", "." },
};

pub const TextEdit = struct { range: Range, newText: []const u8 };

/// `kind`: 7 class (an item type), 18 reference (an ID), 20 enum member
/// (a category, a status, a value), 5 field (a key)
pub const CompletionItem = struct {
    label: []const u8,
    kind: u8,
    detail: ?[]const u8 = null,
    textEdit: TextEdit,
};

pub const RenameOptions = struct { prepareProvider: bool = true };

pub const RenameParams = struct {
    textDocument: struct { uri: []const u8 },
    position: Position,
    newName: []const u8,
};

/// What `prepareRename` answers: the word to rename, and its text
pub const PrepareRename = struct { range: Range, placeholder: []const u8 };

/// The changes of a rename. The server makes them on disk, as `skein
/// move` does, so the edit it answers with is empty and the editor
/// reloads the files.
pub const WorkspaceEdit = struct {
    changes: struct {} = .{},
};

/// A lens above a line: its title, and the client's command it runs
pub const CodeLens = struct {
    range: Range,
    command: Command,
};

pub const Command = struct {
    title: []const u8,
    /// empty: the lens is only shown
    command: []const u8,
    arguments: ?[]const json.Value = null,
};

/// A quick fix: the edit, and the problems it mends as the editor gave them
pub const CodeAction = struct {
    title: []const u8,
    kind: []const u8 = "quickfix",
    diagnostics: []const json.Value,
    isPreferred: bool = true,
    edit: struct { changes: json.ArrayHashMap([]const TextEdit) },
};
