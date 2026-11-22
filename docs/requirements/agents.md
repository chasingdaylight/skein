# AI agents

What skein gives the AI agents of its users, so that a coding agent in a repository with skein documents knows how to read and write them, and can ask skein rather than guess (emanspeaks, 2026-11-22, #180). The user documentation is in `docs/commands.md`.

## The Model Context Protocol server

%req[mcp.protocol]
`skein mcp` shall serve the Model Context Protocol on standard input and output, one JSON-RPC message a line, on the project in the directory it is started in (or `--root`): it answers `initialize` with the protocol version the client asks for when skein knows it (else its newest), the tools capability, its name and version, and a few lines on what skein is; `tools/list`, `tools/call` and `ping`; takes notifications in silence; and answers what it cannot read, and a method it does not know, with an error.

%req[mcp.tools]
The server's tools shall be skein's commands, each with a description and a JSON Schema of its arguments, answering in JSON: `items` (the items, by type and by words in the ID or the text), `trace`, `check` (each problem with its file, line, column, severity, message and fix), `coverage`, `impact`, and the editing commands `new`, `link`, `move`, `result` and `approve`. What a command refuses, and an argument that is missing, is an error result whose text says why.

## In VS Code

%req[vscode.mcp]
The VS Code extension shall offer `skein mcp`, run from the program it carries or the one `skein.path` names in the workspace's folder, to VS Code's MCP support, so that VS Code's agents have skein's tools with nothing to configure; in a trusted workspace only, and not when `skein.mcp.enabled` is off. (emanspeaks, 2026-11-22, #181.)

%req[vscode.chat-context]
The extension shall contribute a language model tool, `#skeinItem` in chat, that gives the trace of the item under the cursor, or of the item whose ID it is given, for an agent or a user to bring an item and everything linked to it into a chat.

%req[vscode.agent-instructions]
The command **skein: Write Agent Instructions** shall run `skein agents` in the workspace's folder, with the file `skein.agents.file` names and as a skill file when `skein.agents.skill` is on, and say what it wrote.

## Agent instructions

%req[agents.instructions]
`skein agents` shall write what a coding agent should know of the project's skein documents into its agent instructions file (`AGENTS.md`, or `CLAUDE.md` where there is one and no `AGENTS.md`, or the file `--file` names): what skein is, how markers, parts and references are written, the commands that edit items, the project's sources, item types (with their categories, statuses and attributes), link types and citations, and to run `skein check` after editing. The section is between two markers, so that it is written again in place, and the rest of the file and its line ends are kept. With `--skill`, it writes the same as a skill file (`.claude/skills/skein/SKILL.md`). `skein init` writes the section too.
