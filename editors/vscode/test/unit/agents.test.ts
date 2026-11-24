// Plain Node.js tests of what the extension gives VS Code's AI agents:
// the MCP server it registers, the #skeinItem tool, and the command that
// writes the agent instructions (package.json, src/program.ts)

// req: vscode.mcp, vscode.chat-context, vscode.agent-instructions
import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { test } from "node:test";
import { agentsArgs } from "../../src/program";

const root = path.join(__dirname, "..", "..");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
const agents = fs.readFileSync(path.join(root, "src", "agents.ts"), "utf8");

test("skein mcp is offered to VS Code's MCP support, and can be turned off", () => {
  assert.deepEqual(manifest.contributes.mcpServerDefinitionProviders, [{ id: "skein.mcp", label: "Skein" }]);
  assert.ok(agents.includes('registerMcpServerDefinitionProvider("skein.mcp"'));
  assert.ok(agents.includes('["mcp"]'));
  assert.equal(manifest.contributes.configuration.properties["skein.mcp.enabled"].default, true);
});

test("the tool #skeinItem: described for the model and the user, an optional ID", () => {
  const [tool] = manifest.contributes.languageModelTools;
  assert.equal(tool.name, "skein_item");
  assert.equal(tool.toolReferenceName, "skeinItem");
  assert.ok(tool.canBeReferencedInPrompt);
  assert.ok(tool.modelDescription.length > 100 && tool.userDescription.length > 20);
  assert.equal(tool.inputSchema.properties.id.type, "string");
  assert.equal(tool.inputSchema.required, undefined);
  assert.ok(agents.includes('registerTool<{ id?: string }>("skein_item"'));
});

test("Write Agent Instructions runs skein agents as the settings say", () => {
  assert.deepEqual(agentsArgs("", false), ["agents"]);
  assert.deepEqual(agentsArgs(" docs/AGENTS.md ", false), ["agents", "--file", "docs/AGENTS.md"]);
  assert.deepEqual(agentsArgs("", true), ["agents", "--skill"]);
  const props = manifest.contributes.configuration.properties;
  assert.ok(props["skein.agents.file"] && props["skein.agents.skill"]);
});
