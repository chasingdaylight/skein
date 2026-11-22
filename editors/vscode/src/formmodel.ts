// The item form's model: what the server says a form shows (skein/form),
// the values a person enters, and what is sent to be written
// (skein/saveItem). No VS Code and no page here, so that it is tested with
// Node alone; the page's script (webview/form.ts) draws it.

export interface FormAttribute {
  name: string;
  kind: "string" | "integer" | "boolean" | "date";
  values: string[];
  required: boolean;
  list: boolean;
}

export interface FormLink {
  name: string;
  /** the items a link of this type may point to */
  targets: string[];
}

export interface FormType {
  name: string;
  description: string;
  categories: string[];
  statuses: string[];
  attributes: FormAttribute[];
  links: FormLink[];
  verification: string[];
  numbered: boolean;
}

export interface FormItem {
  id: string;
  type: string;
  file: string;
  category?: string;
  status?: string;
  verification?: string;
  attributes: Record<string, string>;
  links: Record<string, string[]>;
  text: string;
}

export interface Form {
  item: FormItem | null;
  types: string[];
  type: FormType;
  /** a new item goes into a file of its own */
  itemFiles: boolean;
  /** else, into one of these */
  documents: string[];
}

/** What a person has entered */
export interface Values {
  id: string;
  category: string;
  status: string;
  verification: string;
  attributes: Record<string, string>;
  /** by link type, IDs separated by commas */
  links: Record<string, string>;
  text: string;
  document: string;
}

/** The values of a form, as the item has them, or empty for a new one */
export function initial(form: Form): Values {
  const item = form.item;
  const attributes: Record<string, string> = {};
  for (const a of form.type.attributes) attributes[a.name] = item?.attributes[a.name] ?? "";
  const links: Record<string, string> = {};
  for (const l of form.type.links) links[l.name] = (item?.links[l.name] ?? []).join(", ");
  return {
    id: item?.id ?? "",
    category: item?.category ?? "",
    status: item?.status ?? "",
    verification: item?.verification ?? "",
    attributes,
    links,
    text: "",
    document: form.documents[0] ?? "",
  };
}

/** IDs separated by commas or spaces */
export function ids(text: string): string[] {
  return text.split(/[\s,]+/).filter((w) => w);
}

/** What is wrong before it is sent: a required attribute left empty, a new item with nowhere to go */
export function problems(form: Form, v: Values): string[] {
  const out: string[] = [];
  for (const a of form.type.attributes) if (a.required && !v.attributes[a.name]?.trim()) out.push(`${a.name} is required`);
  if (!form.item && !form.itemFiles && !v.document) out.push("choose the document the item goes in");
  if (!form.item && !form.type.numbered && !v.id.trim()) out.push("give the item an ID");
  return out;
}

/** The request that writes the form */
export function toSave(form: Form, v: Values): Record<string, unknown> {
  const links: Record<string, string[]> = {};
  for (const l of form.type.links) links[l.name] = ids(v.links[l.name] ?? "");
  const attributes: Record<string, string> = {};
  for (const a of form.type.attributes) attributes[a.name] = a.list ? ids(v.attributes[a.name] ?? "").join(",") : (v.attributes[a.name] ?? "").trim();
  return {
    new: form.item === null,
    id: v.id.trim(),
    type: form.type.name,
    category: v.category,
    status: v.status,
    verification: v.verification,
    attributes,
    links,
    text: v.text.trim(),
    document: form.item ? "" : v.document,
  };
}
