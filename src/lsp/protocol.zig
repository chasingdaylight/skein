//! The Language Server Protocol messages the server reads and writes, of
//! what it uses. Requests are parsed with unknown fields ignored; responses
//! are written without the optional fields that are null.

pub const Position = struct { line: usize, character: usize };

pub const Range = struct { start: Position, end: Position };

pub const Location = struct { uri: []const u8, range: Range };

pub const Diagnostic = struct {
    range: Range,
    /// 1 error
    severity: u8 = 1,
    source: []const u8 = "skein",
    message: []const u8,
};

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
