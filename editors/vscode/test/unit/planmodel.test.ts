// Plain Node.js tests of the planning view's model (src/planmodel.ts)

// req: vscode.planning
import * as assert from "node:assert/strict";
import { test } from "node:test";
import { columns, daysMoved, fromDay, isWorking, layout, PlanItem, planChange, Schedule, toDay, weekday } from "../../src/planmodel";

function item(id: string, extra: Partial<PlanItem> = {}): PlanItem {
  return { id, type: "task", title: "", status: "open", uri: "", line: 0, mode: "float", source: "computed", critical: false, milestone: false, after: [], parents: [], assignees: [], ...extra };
}

const week = [true, true, true, true, true, false, false];

test("days: dates, weekdays and working days", () => {
  assert.equal(toDay("1970-01-01"), 0);
  assert.equal(fromDay(toDay("2027-03-01")), "2027-03-01");
  // 2027-03-01 is a Monday
  assert.equal(weekday(toDay("2027-03-01")), 0);
  const s: Schedule = { items: [], statuses: [], workdays: week, holidays: ["2027-03-03"] };
  assert.ok(isWorking(s, toDay("2027-03-02")));
  assert.ok(!isWorking(s, toDay("2027-03-03")));
  assert.ok(!isWorking(s, toDay("2027-03-06")));
});

test("layout: a row for each scheduled item, from a Monday, the unscheduled apart", () => {
  const s: Schedule = {
    items: [item("a", { start: "2027-03-03", finish: "2027-03-05" }), item("b"), item("c", { start: "2027-03-08", finish: "2027-03-08" })],
    statuses: [],
    workdays: week,
    holidays: [],
  };
  const l = layout(s);
  assert.deepEqual(l.bars.map((b) => [b.item.id, b.row]), [["a", 0], ["c", 1]]);
  assert.deepEqual(l.unscheduled.map((i) => i.id), ["b"]);
  assert.equal(weekday(l.first), 0);
  assert.ok(l.first <= toDay("2027-03-03") - 3);
  assert.equal(l.last, toDay("2027-03-08") + 3);
});

test("a drag: whole days, a new start for a move, a new finish for the end", () => {
  assert.equal(daysMoved(40, 28), 1);
  assert.equal(daysMoved(-80, 28), -3);
  const bar = { item: item("a"), row: 0, first: toDay("2027-03-01"), last: toDay("2027-03-03") };
  assert.deepEqual(planChange(bar, "move", 2), { id: "a", start: "2027-03-03" });
  assert.deepEqual(planChange(bar, "end", 1), { id: "a", finish: "2027-03-04" });
  // never shorter than a day
  assert.deepEqual(planChange(bar, "end", -9), { id: "a", finish: "2027-03-01" });
  assert.equal(planChange(bar, "move", 0), null);
});

test("the board: a column for each status, in order, the items in theirs", () => {
  const s: Schedule = { items: [item("a", { status: "done" }), item("b"), item("c", { status: "odd" })], statuses: ["open", "doing", "done"], workdays: week, holidays: [] };
  assert.deepEqual(
    columns(s).map((c) => [c.status, c.items.map((i) => i.id)]),
    [["open", ["b"]], ["doing", []], ["done", ["a"]], ["odd", ["c"]]],
  );
});
