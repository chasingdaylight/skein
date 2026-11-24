//! Code taken from other projects and built into skein, each with its
//! license, its version and where it came from (see vendor/README.md).

/// mermaid's browser build (MIT), which draws the diagrams of rendered pages
pub const mermaid = @embedFile("mermaid/mermaid.min.js");
pub const mermaid_version = @embedFile("mermaid/VERSION");
