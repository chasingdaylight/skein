// skein for VS Code's AI agents (Copilot's agent mode, Claude Code, others):
// - `skein mcp` registered with VS Code's MCP support, so that agents have
//   skein's tools with nothing to configure (skein.mcp.enabled);
// - the tool `#skeinItem`: the trace of the item under the cursor, or of
//   one named, as context for the chat;
// - the command that writes the project's agent instructions (`skein agents`).

import * as vscode from "vscode";
import { Server } from "./client";
import * as commands from "./commands";
import { agentsArgs } from "./program";
import { programOf, run } from "./run";

export function register(context: vscode.ExtensionContext, server: Server): void {
  const changed = new vscode.EventEmitter<void>();
  context.subscriptions.push(
    changed,
    vscode.lm.registerMcpServerDefinitionProvider("skein.mcp", {
      onDidChangeMcpServerDefinitions: changed.event,
      provideMcpServerDefinitions: () => {
        const settings = vscode.workspace.getConfiguration("skein");
        const folder = vscode.workspace.workspaceFolders?.[0];
        const program = programOf(context);
        if (!settings.get<boolean>("mcp.enabled", true) || !vscode.workspace.isTrusted || !folder || !program) return [];
        const definition = new vscode.McpStdioServerDefinition("Skein", program, ["mcp"], {}, context.extension.packageJSON.version as string);
        definition.cwd = folder.uri;
        return [definition];
      },
    }),
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration("skein.path") || e.affectsConfiguration("skein.mcp.enabled")) changed.fire();
    }),
    vscode.lm.registerTool<{ id?: string }>("skein_item", {
      prepareInvocation: (options) => ({ invocationMessage: options.input.id ? `Tracing ${options.input.id}` : "Tracing the item under the cursor" }),
      invoke: async (options) => {
        const id = options.input.id || (await commands.itemAtCursor(server));
        if (!id) throw new Error("There is no Skein item under the cursor; name one with its ID.");
        const text = await run(context, ["trace", id]);
        return new vscode.LanguageModelToolResult([new vscode.LanguageModelTextPart(text)]);
      },
    }),
    vscode.commands.registerCommand("skein.writeAgentInstructions", async () => {
      const settings = vscode.workspace.getConfiguration("skein");
      try {
        const said = await run(context, agentsArgs(settings.get<string>("agents.file", ""), settings.get<boolean>("agents.skill", false)));
        void vscode.window.showInformationMessage(said.trim());
      } catch (err) {
        void vscode.window.showErrorMessage(err instanceof Error ? err.message : String(err));
      }
    }),
  );
}

