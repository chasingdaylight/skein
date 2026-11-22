// The planning view's model: the schedule as the server gives it
// (skein/schedule), days as numbers, where each bar goes on the time line,
// and the columns of the board. No VS Code and no page here, so that it is
// tested with Node alone; the page's script (webview/plan.ts) draws it.

export interface PlanItem {
  id: string;
  type: string;
  title: string;
  status: string;
  uri: string;
  line: number;
  start?: string;
  finish?: string;
  duration?: number;
  mode: string;
  source: string;
  slack?: number;
  critical: boolean;
  milestone: boolean;
  after: string[];
  parents: string[];
  assignees: string[];
}

export interface Schedule {
  items: PlanItem[];
  statuses: string[];
  /** Monday to Sunday */
  workdays: boolean[];
  holidays: string[];
}

const msPerDay = 86_400_000;

/** Days since 1970-01-01 of `YYYY-MM-DD` */
export function toDay(date: string): number {
  return Math.round(Date.parse(`${date}T00:00:00Z`) / msPerDay);
}

/** `YYYY-MM-DD` of a day */
export function fromDay(day: number): string {
  return new Date(day * msPerDay).toISOString().slice(0, 10);
}

/** 0 for Monday to 6 for Sunday */
export function weekday(day: number): number {
  return (((day + 3) % 7) + 7) % 7;
}

export function isWorking(schedule: Schedule, day: number): boolean {
  if (!schedule.workdays[weekday(day)]) return false;
  return !schedule.holidays.includes(fromDay(day));
}

export interface Bar {
  item: PlanItem;
  row: number;
  first: number;
  last: number;
}

export interface Layout {
  /** the first and the last day drawn */
  first: number;
  last: number;
  bars: Bar[];
  unscheduled: PlanItem[];
}

/** The bars of the scheduled items, a row each in the server's order, and a margin of days around them */
export function layout(schedule: Schedule, margin = 3): Layout {
  const bars: Bar[] = [];
  const unscheduled: PlanItem[] = [];
  for (const item of schedule.items) {
    if (!item.start || !item.finish) {
      unscheduled.push(item);
      continue;
    }
    bars.push({ item, row: bars.length, first: toDay(item.start), last: toDay(item.finish) });
  }
  if (bars.length === 0) return { first: 0, last: 0, bars, unscheduled };
  const first = Math.min(...bars.map((b) => b.first));
  const last = Math.max(...bars.map((b) => b.last));
  // from a Monday, so that the weeks line up
  const from = first - margin - weekday(first - margin);
  return { first: from, last: last + margin, bars, unscheduled };
}

/** The whole days a drag of `pixels` moves, at `dayWidth` pixels a day */
export function daysMoved(pixels: number, dayWidth: number): number {
  return Math.round(pixels / dayWidth);
}

/** What a drag asks the server to write: a new start, or a new finish; null for no change */
export function planChange(bar: Bar, edge: "move" | "end", days: number): { id: string; start?: string; finish?: string } | null {
  if (days === 0) return null;
  if (edge === "move") return { id: bar.item.id, start: fromDay(bar.first + days) };
  // a bar is never shorter than one day
  const last = Math.max(bar.first, bar.last + days);
  return last === bar.last ? null : { id: bar.item.id, finish: fromDay(last) };
}

/** The board's columns: each status in the order given, with its items */
export function columns(schedule: Schedule): { status: string; items: PlanItem[] }[] {
  const out = schedule.statuses.map((status) => ({ status, items: [] as PlanItem[] }));
  for (const item of schedule.items) {
    let column = out.find((c) => c.status === item.status);
    if (!column) {
      column = { status: item.status, items: [] };
      out.push(column);
    }
    column.items.push(item);
  }
  return out;
}
