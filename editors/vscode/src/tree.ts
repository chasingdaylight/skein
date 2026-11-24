// The tree of items in the side bar (the Explorer's "Skein Items"), from
// the server's `skein/items`.

import * as vscode from "vscode";
import { Server } from "./client";
import { buildTree, describe, ItemInfo, Items, Node } from "./model";

export class ItemTree implements vscode.TreeDataProvider<Node> {
  private readonly changed = new vscode.EventEmitter<Node | undefined>();
  readonly onDidChangeTreeData = this.changed.event;
  private roots: Node[] = [];
  private byId = new Map<string, ItemInfo>();
  /** the project's root, for the paths of files */
  root: vscode.Uri | undefined;

  constructor(private readonly server: Server) {}

  /** Reads the items again */
  async refresh(): Promise<void> {
    const items = await this.server.request<Items | null>("skein/items");
    this.roots = items ? buildTree(items) : [];
    this.byId = new Map((items?.items ?? []).map((i) => [i.id, i]));
    this.changed.fire(undefined);
  }

  item(id: string): ItemInfo | undefined {
    return this.byId.get(id);
  }

  all(): ItemInfo[] {
    return [...this.byId.values()];
  }

  getChildren(node?: Node): Node[] {
    return node ? node.children : this.roots;
  }

  getTreeItem(node: Node): vscode.TreeItem {
    const state = node.children.length > 0 ? vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None;
    switch (node.kind) {
      case "source": {
        const t = new vscode.TreeItem(node.path, vscode.TreeItemCollapsibleState.Expanded);
        t.iconPath = vscode.ThemeIcon.Folder;
        return t;
      }
      case "file": {
        const t = new vscode.TreeItem(node.label, state);
        t.resourceUri = vscode.Uri.parse(node.uri);
        t.iconPath = vscode.ThemeIcon.File;
        t.tooltip = node.file;
        return t;
      }
      case "item": {
        const item = node.item;
        const t = new vscode.TreeItem(item.id, state);
        t.description = describe(item);
        t.tooltip = new vscode.MarkdownString().appendMarkdown(`**${item.id}** (${describe(item)})\n\n`).appendText(item.title);
        t.contextValue = "item";
        t.iconPath = new vscode.ThemeIcon(item.removed ? "circle-slash" : "symbol-key");
        t.command = { command: "skein.openItem", title: "Open", arguments: [item.id] };
        return t;
      }
    }
  }
}
