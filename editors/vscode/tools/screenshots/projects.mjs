// The projects the screenshots are taken in, made fresh for each run:
// rover, the quickstart's (docs/quickstart.md, steps 2 to 5), and station,
// the planning tutorial's (docs/tutorial-planning.md), for the Plan view.

import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

function write(root, file, text) {
  mkdirSync(dirname(join(root, file)), { recursive: true });
  writeFileSync(join(root, file), text);
}

function edit(root, file, from, to) {
  const path = join(root, file);
  const text = readFileSync(path, "utf8");
  if (!text.includes(from)) throw new Error(`${file}: no '${from}' to replace`);
  writeFileSync(path, text.replace(from, to));
}

function fresh(dir) {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  execFileSync("git", ["init", "-q"], { cwd: dir });
}

/** Commits the project as made, so that each scene starts from it (restore) */
function commit(dir) {
  execFileSync("git", ["add", "-A"], { cwd: dir });
  execFileSync("git", ["-c", "user.name=skein", "-c", "user.email=skein@localhost", "commit", "-q", "-m", "The project as made"], { cwd: dir });
}

/** The project's files as made, undoing what a scene changed */
export function restore(dir) {
  execFileSync("git", ["checkout", "-q", "--", "."], { cwd: dir });
}

/** The quickstart's project: the npr7150.2d template, two requirements, a test citing one */
export function rover(dir, skein) {
  fresh(dir);
  execFileSync(skein, ["init", "--template", "npr7150.2d", "--option", "class=C"], { cwd: dir });
  edit(
    dir,
    "docs/srs.md",
    "%requirement[SRS-001 functional verification=test] The software shall start in a known safe state. (An example: replace it.)",
    "%requirement[SRS-001 functional verification=test] The rover shall stop within 2 seconds of losing contact with the ground station.\n\n" +
      "%requirement[SRS-002 functional verification=test] The rover shall not drive faster than 0.5 meters per second.",
  );
  edit(
    dir,
    ".skein/config.toml",
    '# [[citations]]\n# name = "test"\n# path = "tests"\n# files = [".c"]\n# marker = "// verifies:"\n# to = ["requirement"]\n',
    '[[citations]]\nname = "test"\npath = "tests"\nfiles = [".c"]\nmarker = "// verifies:"\nto = ["requirement"]\n',
  );
  write(dir, "tests/test_drive.c", '#include "drive.h"\n\n// verifies: SRS-001\nvoid test_stops_when_contact_is_lost(void) {\n  drive_lose_contact();\n  assert_stopped_within(2.0);\n}\n');
  execFileSync(skein, ["check"], { cwd: dir });
  commit(dir);
  return dir;
}

/** The planning tutorial's project: needs, requirements, and the work that meets them */
export function station(dir, skein) {
  fresh(dir);
  execFileSync(skein, ["init"], { cwd: dir });
  write(dir, ".skein/types/need.toml", 'description = "What someone needs from the station"\nid = "numbered"\nprefix = "NEED"\n');
  write(dir, ".skein/types/req.toml", 'description = "A requirement of the station"\nid = "numbered"\nprefix = "REQ"\n');
  write(dir, ".skein/types/task.toml", 'description = "Work to be done"\nstatuses = ["todo", "doing", "done"]\n\n[attributes.start]\ntype = "date"\n[attributes.days]\ntype = "integer"\n[attributes.effort]\ntype = "integer"\n[attributes.owner]\nlist = true\n\n[planning]\nstart = "start"\nduration = "days"\nestimate = "effort"\nassignees = "owner"\n');
  write(dir, ".skein/links/refines.toml", 'description = "A requirement refines a need"\nfrom = ["req"]\nto = ["need"]\nrequired = true\nexpected = true\n');
  write(dir, ".skein/links/after.toml", 'description = "This work starts once the work it names has finished"\nfrom = ["task"]\nto = ["task"]\n\n[planning]\nrole = "follows"\n');
  write(dir, ".skein/links/delivers.toml", 'description = "The work delivers a requirement"\nfrom = ["task"]\nto = ["req"]\nexpected = true\n');
  write(dir, ".skein/resources.toml", '[calendar]\nholidays = [2027-04-05]\n\n[people.ann]\nname = "Ann Example"\n\n[people.bob]\nname = "Bob Example"\nshare = 0.5\n');
  write(dir, "docs/needs.md", "# Needs\n\n%need[NEED-001] The farm needs to know the temperature and rainfall at the field, every hour.\n\n%need[NEED-002] The station must run unattended for a season on its battery and solar panel.\n");
  write(dir, "docs/requirements.md", "# Requirements\n\n%req[REQ-001 refines=NEED-001] The station shall measure air temperature from -30 to 50 °C, to 0.5 °C.\n\n%req[REQ-002 refines=NEED-001] The station shall measure rainfall in steps of 0.2 mm.\n\n%req[REQ-003 refines=NEED-001] The station shall send its measurements every hour by radio.\n\n%req[REQ-004 refines=NEED-002] The station shall run for 180 days without a visit.\n");
  write(
    dir,
    "docs/plan.md",
    "# Plan\n\n## Work\n\n" +
      "- %task[t.sensors start=2027-03-01 days=5 owner=ann delivers=REQ-001,REQ-002] Choose the sensors and wire a prototype.\n" +
      "- %task[t.radio start=2027-03-01 days=8 owner=bob delivers=REQ-003] Get a radio link to the farm's gateway.\n" +
      "- %task[t.firmware days=10 owner=ann after=t.sensors,t.radio delivers=REQ-001,REQ-002,REQ-003] Write the firmware that measures and sends every hour.\n" +
      "- %task[t.power days=6 owner=bob after=t.firmware delivers=REQ-004] Measure the power use and size the battery and panel.\n" +
      "- %task[t.field days=0 after=t.firmware,t.power] The station goes to the field.\n\n" +
      "## Schedule\n\n```skein\ngantt\n```\n\n## Board\n\n```skein\nboard by=assignee\n```\n",
  );
  execFileSync(skein, ["schedule"], { cwd: dir });
  execFileSync(skein, ["check"], { cwd: dir });
  commit(dir);
  return dir;
}
