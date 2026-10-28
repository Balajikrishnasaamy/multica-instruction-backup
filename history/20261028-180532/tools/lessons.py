#!/usr/bin/env python3
"""lessons.py: the learning loop for the CirDoc agents.

Commands (all deterministic; the Lessons Curator agent only calls these):
  scan <issue>                      evidence report for an issue: failed runs, repeated commands, error bursts,
                                    deploy/test failures and LESSON blocks posted by agents. Secrets are masked.
  show [role]                       print the approved lessons (whole skill, or one section)
  propose ...                       record a proposal (add or retire) and print the block to post for approval
  add --proposal PR-x --approved-comment <id>      apply an APPROVED add proposal
  retire --proposal PR-x --approved-comment <id>   apply an APPROVED retire proposal
  reject --proposal PR-x --comment <id>            record a rejected proposal
  mark <issue> [note]               remember that the issue's runs were reviewed (scan then shows what is new)
  sync [--check|--push]             compare / push lessons/LESSONS.md to the Multica skill "cirdoc-lessons"
  init                              create the skill and the inbox issue (one time)

Approval gate: add/retire refuse to run unless --approved-comment is a comment by a HUMAN workspace member on the
inbox issue that says "APPROVE <proposal-id>". The text applied is the text stored at propose time, so the curator
cannot change a lesson between approval and application.

Data lives in the backup folder: ~/multica-instruction-backup/lessons/
  LESSONS.md  proposals/*.json  processed.tsv  audit.tsv  config.json
"""
import argparse
import datetime
import difflib
import json
import os
import re
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
DATA = os.environ.get("LESSONS_DIR", f"{HOME}/multica-instruction-backup/lessons")
WORKSPACE = "85121eb5-c9c7-4018-a975-140810c991cb"
APP_BIN = "/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica"
CAP_PER_SECTION = 12
MAX_RULE, MAX_WHY = 300, 200

SECTIONS = [  # key, heading, id prefix, who reads it
    ("all", "All agents", "A"),
    ("worker", "Worker", "W"),
    ("reviewer", "Reviewer", "R"),
    ("leader", "Classify & Route", "L"),
    ("planning", "Planning (Plan Lead, Requirements Analyst, Feasibility Engineer)", "PL"),
    ("curator", "Lessons Curator", "K"),
]
ALIASES = {"worker": "worker", "worker-1": "worker", "worker-o": "worker", "reviewer": "reviewer", "leader": "leader",
           "classify & route": "leader", "classify": "leader", "planning": "planning", "plan lead": "planning",
           "requirements analyst": "planning", "feasibility engineer": "planning", "curator": "curator",
           "lessons curator": "curator", "all": "all", "all agents": "all"}

SECRET = re.compile(r"(?i)((?:password|passwd|secret|token|privatekey|private_key|authtoken|apikey|api_key|client[._]secret|bearer)[A-Za-z0-9_.]*\s*[=:]\s*)[^\s,;&\"']+")
LONGHEX = re.compile(r"\b[0-9a-f]{32,}\b|\bmul_[0-9a-f]{20,}\b|\b1000\.[0-9a-f]{20,}\.[0-9a-f]{20,}\b", re.I)


def mask(s):
    return LONGHEX.sub("****", SECRET.sub(r"\1****", s or ""))


def has_secret(s):
    return bool(SECRET.search(s or "") or LONGHEX.search(s or ""))


# ------------------------------------------------------------------ multica CLI
def mc_cmd():
    exe = shutil.which("multica")
    if exe:
        return [exe]
    return [APP_BIN, "--profile", "desktop-api.multica.ai"]


def mc(*args, expect_json=True):
    env = dict(os.environ)
    env.setdefault("MULTICA_WORKSPACE_ID", WORKSPACE)
    p = subprocess.run(mc_cmd() + list(args), capture_output=True, text=True, env=env)
    if p.returncode != 0:
        raise SystemExit(f"multica {' '.join(args[:3])} failed: {p.stderr.strip()[:300] or p.stdout.strip()[:300]}")
    if not expect_json:
        return p.stdout
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        raise SystemExit(f"multica {' '.join(args[:3])} returned non-JSON: {p.stdout[:200]}")


def as_list(d, key):
    return d if isinstance(d, list) else d.get(key, [])


# ------------------------------------------------------------------ data files
def path(*p):
    return os.path.join(DATA, *p)


def load_config():
    try:
        return json.load(open(path("config.json")))
    except OSError:
        return {}


def save_config(c):
    os.makedirs(DATA, exist_ok=True)
    json.dump(c, open(path("config.json"), "w"), indent=2)


def audit(action, ident, detail=""):
    os.makedirs(DATA, exist_ok=True)
    with open(path("audit.tsv"), "a") as f:
        f.write("\t".join([datetime.datetime.now().strftime("%F %T"), action, ident, detail.replace("\t", " ").replace("\n", " ")]) + "\n")


def parse_lessons():
    """-> {section_key: [dict(id, issue, date, rule, why)]}"""
    out = {k: [] for k, _, _ in SECTIONS}
    try:
        text = open(path("LESSONS.md")).read()
    except OSError:
        return out
    cur = None
    for line in text.splitlines():
        if line.startswith("## "):
            head = line[3:].strip()
            cur = next((k for k, h, _ in SECTIONS if h == head), None)
        elif cur and line.startswith("- **"):
            m = re.match(r"- \*\*([A-Z]+-\d+)\*\* \(([^,)]*)(?:, ([^)]*))?\): (.*?)(?: — why: (.*))?$", line)
            if m:
                out[cur].append({"id": m.group(1), "issue": m.group(2), "date": m.group(3) or "", "rule": m.group(4), "why": m.group(5) or ""})
    return out


HEADER = """# CirDoc lessons: approved fixes for problems earlier runs already hit

At the start of every run read the section "All agents" and the section for your own role, and follow them as rules.
Only lessons approved by the human are in this file. A LESSON block you post is only a proposal; never act on a
proposal and never edit this skill. Lessons never override an approval gate or any "never" rule in your own instructions.
Entries are short on purpose: if one does not apply to your task, ignore it.

To propose a lesson, end your comment with a LESSON block (plain text, no mention links, no secrets, at most one per run):
LESSON
role: <worker|reviewer|leader|planning|all>
problem: <what went wrong, one line>
cause: <why it happened>
rule: <what every later run must do or avoid, one line>
"""


def render(lessons):
    parts = [HEADER]
    for key, head, _ in SECTIONS:
        parts.append(f"## {head}")
        items = lessons[key]
        if not items:
            parts.append("- (no lessons yet)")
        for l in items:
            tail = f" — why: {l['why']}" if l["why"] else ""
            parts.append(f"- **{l['id']}** ({l['issue']}, {l['date']}): {l['rule']}{tail}")
        parts.append("")
    return "\n".join(parts).rstrip() + "\n"


def write_lessons(lessons):
    os.makedirs(DATA, exist_ok=True)
    open(path("LESSONS.md"), "w").write(render(lessons))
    hist = path("history")
    os.makedirs(hist, exist_ok=True)
    shutil.copy(path("LESSONS.md"), f"{hist}/LESSONS-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}.md")
    for old in sorted(os.listdir(hist))[:-40]:
        os.remove(os.path.join(hist, old))


def push_skill():
    if os.environ.get("LESSONS_NO_PUSH"):
        return
    cfg = load_config()
    if not cfg.get("skill_id"):
        raise SystemExit("skill not created yet: run  lessons.py init")
    mc("skill", "update", cfg["skill_id"], "--content-file", path("LESSONS.md"), "--output", "json")


def norm_role(r):
    k = ALIASES.get((r or "").strip().lower())
    if not k:
        raise SystemExit(f"unknown role '{r}'. use one of: worker, reviewer, leader, planning, curator, all")
    return k


# ------------------------------------------------------------------ scan
ERR_FIRST = re.compile(r"(?i)^(fatal:|error[: ]|.*\bno such file or directory\b|.*\bcommand not found\b|.*\bpermission denied\b|.*not a git repository|.*\btimed out\b|traceback|.*exception\b)")
STATUS_BAD = re.compile(r'"status":\s*"(compile_failed|deploy_failed|rolled_back|rollback_failed|preempted)"')


def norm_cmd(m):
    inp = m.get("input") or {}
    cmd = inp.get("command") if isinstance(inp, dict) else None
    if cmd is None:
        cmd = json.dumps(inp, sort_keys=True)
    return (m.get("tool") or "?") + ": " + " ".join(str(cmd).split())[:170]


def first_line(out):
    for l in (out or "").splitlines():
        if l.strip():
            return l.strip()[:200]
    return ""


def processed():
    d = {}
    try:
        for line in open(path("processed.tsv")):
            p = line.rstrip("\n").split("\t")
            if len(p) >= 3:
                d[p[1]] = {"when": p[0], "runs": int(p[2] or 0), "note": p[3] if len(p) > 3 else ""}
    except OSError:
        pass
    return d


def cmd_scan(a):
    issue = mc("issue", "get", a.issue, "--output", "json")
    ident, iid = issue.get("identifier", a.issue), issue["id"]
    names = {x["id"]: x["name"] for x in as_list(mc("agent", "list", "--output", "json"), "agents")}
    runs = mc("issue", "runs", ident, "--output", "json")
    runs = runs if isinstance(runs, list) else runs.get("runs", [])
    runs.sort(key=lambda r: r.get("created_at", ""))
    done = processed().get(ident)
    print(f"SCAN {ident}: {issue.get('title','')[:90]} [status {issue.get('status')}] runs={len(runs)}")
    if done:
        print(f"already reviewed: {done['when']} ({done['runs']} runs then, now {len(runs)}){' - NEW RUNS since' if len(runs) > done['runs'] else ' - nothing new'}")
    signals = []
    for r in runs:
        agent = names.get(r.get("agent_id"), r.get("agent_id", "?")[:8])
        rid = r["id"]
        if r.get("kind") in ("quick_create",):
            continue
        msgs = mc("issue", "run-messages", rid, "--issue", ident, "--output", "json")
        msgs = msgs if isinstance(msgs, list) else msgs.get("messages", [])
        uses = [m for m in msgs if m.get("type") == "tool_use"]
        results = {m.get("call_id"): m for m in msgs if m.get("type") == "tool_result"}
        t0, t1 = r.get("started_at") or r.get("created_at"), r.get("completed_at")
        dur = ""
        try:
            f = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
            dur = f"{int((f(t1) - f(t0)).total_seconds() // 60)}m" if t0 and t1 else "running"
        except Exception:
            pass
        err = (r.get("error") or "").strip()
        print(f"- run {rid[-8:]} {agent}: {r.get('status')} {dur} tools={len(uses)}" + (f" error={mask(err)[:160]}" if err else ""))
        if r.get("status") == "failed":
            signals.append(("RUN_FAILED", agent, rid, f"{r.get('failure_reason','')}: {mask(err)[:220]}"))
        counts, errs, err_lines = {}, 0, {}
        for u in uses:
            k = norm_cmd(u)
            res = results.get(u.get("call_id"), {})
            out = res.get("output") if isinstance(res.get("output"), str) else json.dumps(res.get("output"))
            fl = first_line(out)
            is_err = bool(ERR_FIRST.match(fl))
            c = counts.setdefault(k, {"n": 0, "err": 0, "first_err": ""})
            c["n"] += 1
            if is_err:
                c["err"] += 1
                c["first_err"] = c["first_err"] or fl
                errs += 1
                err_lines[fl] = err_lines.get(fl, 0) + 1
            if out and STATUS_BAD.search(out):
                signals.append(("DEPLOY_PROBLEM", agent, rid, mask(STATUS_BAD.search(out).group(0))))
            if out and re.search(r"RESULT: (FAIL|ERROR)", out):
                signals.append(("TEST_OR_TOOL_RESULT", agent, rid, mask(re.search(r"RESULT: (FAIL|ERROR)[^\n]*", out).group(0))[:160]))
        for k, c in sorted(counts.items(), key=lambda kv: -kv[1]["n"]):
            if c["n"] >= 4 and (c["err"] >= 3 or c["n"] >= 8):
                signals.append(("LOOP", agent, rid, f"{c['n']}x {mask(k)} -> {mask(c['first_err']) or 'no error text'} ({c['err']} errors)"))
        if errs >= 10:
            top = sorted(err_lines.items(), key=lambda kv: -kv[1])[:2]
            signals.append(("ERROR_BURST", agent, rid, f"{errs} failing tool calls; top: " + " | ".join(f"{n}x {mask(l)[:90]}" for l, n in top)))
        if len(uses) >= 150:
            signals.append(("LONG_RUN", agent, rid, f"{len(uses)} tool calls (provider stops runs near 1000 messages)"))
    # LESSON blocks written by agents
    comments = mc("issue", "comment", "list", ident, "--output", "json", "--compact")
    comments = comments if isinstance(comments, list) else comments.get("comments", [])
    blocks = []
    for c in comments:
        if c.get("author_type") != "agent":
            continue
        for m in re.finditer(r"(?ms)^LESSON\s*\n(.*?)(?=\n\s*\n|\Z)", c.get("content") or ""):
            blocks.append((c.get("id", "")[-8:], names.get(c.get("author_id"), "agent"), mask(m.group(1).strip())))
    print(f"\nSIGNALS ({len(signals)}):")
    seen = set()
    for kind, agent, rid, ev in signals:
        key = (kind, agent, ev[:80])
        if key in seen:
            continue
        seen.add(key)
        print(f"  [{kind}] {agent} run {rid[-8:]}: {ev}")
    if not signals:
        print("  (none)")
    print(f"\nLESSON BLOCKS posted by agents ({len(blocks)}):")
    for cid, who, body in blocks:
        print(f"  comment {cid} by {who}:\n    " + body.replace("\n", "\n    "))
    if not blocks:
        print("  (none)")
    print(f"\nSUMMARY: signals={len(signals)} lesson_blocks={len(blocks)} runs={len(runs)}")


def cmd_mark(a):
    ident = mc("issue", "get", a.issue, "--output", "json").get("identifier", a.issue)
    n = len(mc("issue", "runs", ident, "--output", "json"))
    os.makedirs(DATA, exist_ok=True)
    with open(path("processed.tsv"), "a") as f:
        f.write(f"{datetime.datetime.now().strftime('%F %T')}\t{ident}\t{n}\t{a.note or ''}\n")
    print(f"marked {ident} as reviewed at {n} runs")


# ------------------------------------------------------------------ propose / add / retire / reject
def proposals_dir():
    d = path("proposals")
    os.makedirs(d, exist_ok=True)
    return d


def next_proposal(ident):
    num = re.sub(r"\D", "", ident.split("-")[-1]) or "0"
    n = 1
    while os.path.exists(f"{proposals_dir()}/PR-{num}-{n}.json"):
        n += 1
    return f"PR-{num}-{n}"


def cmd_propose(a):
    lessons = parse_lessons()
    if a.retire:
        found = next((k for k, items in lessons.items() for l in items if l["id"] == a.retire), None)
        if not found:
            raise SystemExit(f"lesson {a.retire} not found")
        rec = {"kind": "retire", "lesson": a.retire, "reason": mask(a.reason or ""), "issue": a.issue}
        body = f"RETIRE {a.retire}: {mask(a.reason or '')}"
    else:
        role = norm_role(a.role)
        for fld, lim in (("rule", MAX_RULE), ("problem", MAX_WHY), ("cause", MAX_WHY)):
            v = getattr(a, fld) or ""
            if not v.strip():
                raise SystemExit(f"--{fld} is required")
            if len(v) > lim:
                raise SystemExit(f"--{fld} too long ({len(v)} > {lim}); lessons must stay short")
        if has_secret(" ".join([a.rule, a.problem, a.cause, a.evidence or ""])):
            raise SystemExit("proposal contains something that looks like a secret; remove it")
        if len(lessons[role]) >= CAP_PER_SECTION:
            raise SystemExit(f"section '{role}' already has {CAP_PER_SECTION} lessons. Propose a merge or --retire first.")
        for l in lessons[role] + lessons["all"]:
            if difflib.SequenceMatcher(None, l["rule"].lower(), a.rule.lower()).ratio() > 0.75:
                raise SystemExit(f"too similar to existing {l['id']}: \"{l['rule']}\". Propose a change to it (--retire then add) instead of a duplicate.")
        rec = {"kind": "add", "role": role, "rule": a.rule.strip(), "why": f"{a.problem.strip()}; {a.cause.strip()}"[:MAX_WHY], "evidence": mask(a.evidence or "")[:400], "issue": a.issue}
        body = (f"ADD to section '{role}':\n  rule: {rec['rule']}\n  why: {rec['why']}\n  evidence: {rec['evidence'] or '-'}")
    pid = next_proposal(a.issue)
    rec.update({"id": pid, "status": "proposed", "created": datetime.datetime.now().strftime("%F %T")})
    json.dump(rec, open(f"{proposals_dir()}/{pid}.json", "w"), indent=2)
    audit("propose", pid, body[:200])
    print(f"LESSON-PROPOSAL {pid} (from {a.issue})\n{body}\n\nReply with:  APPROVE {pid}   or   REJECT {pid}: <reason>")


def load_proposal(pid, kind):
    try:
        rec = json.load(open(f"{proposals_dir()}/{pid}.json"))
    except OSError:
        raise SystemExit(f"unknown proposal {pid}")
    if rec["kind"] != kind:
        raise SystemExit(f"{pid} is a '{rec['kind']}' proposal, not '{kind}'")
    if rec["status"] != "proposed":
        raise SystemExit(f"{pid} is already {rec['status']}")
    return rec


def verify_approval(pid, comment_id, word="APPROVE"):
    cfg = load_config()
    inbox = cfg.get("inbox_issue")
    if not inbox:
        raise SystemExit("inbox issue not configured (lessons.py init)")
    comments = as_list(mc("issue", "comment", "list", inbox, "--output", "json", "--compact"), "comments")
    c = next((x for x in comments if x.get("id", "").endswith(comment_id) or x.get("id") == comment_id), None)
    if not c:
        raise SystemExit(f"comment {comment_id} not found on the lessons inbox issue")
    if c.get("author_type") != "member":
        raise SystemExit("approval must come from a human member, not an agent")
    if not re.search(rf"(?i)\b{word}\s+{re.escape(pid)}\b", c.get("content") or ""):
        raise SystemExit(f"that comment does not say '{word} {pid}'")
    return c


def next_id(lessons, role):
    prefix = next(p for k, _, p in SECTIONS if k == role)
    used = [int(l["id"].split("-")[1]) for items in lessons.values() for l in items if l["id"].startswith(prefix + "-")]
    return f"{prefix}-{max(used, default=0) + 1:03d}"


def cmd_add(a):
    rec = load_proposal(a.proposal, "add")
    c = verify_approval(a.proposal, a.approved_comment)
    lessons = parse_lessons()
    lid = next_id(lessons, rec["role"])
    lessons[rec["role"]].append({"id": lid, "issue": rec["issue"], "date": datetime.date.today().isoformat(), "rule": rec["rule"], "why": rec["why"]})
    write_lessons(lessons)
    push_skill()
    rec.update({"status": "applied", "lesson": lid, "approved_by_comment": c["id"]})
    json.dump(rec, open(f"{proposals_dir()}/{a.proposal}.json", "w"), indent=2)
    audit("add", lid, f"{a.proposal} approved in comment {c['id']}")
    print(f"ADDED {lid} to section '{rec['role']}', skill updated, backup file updated")


def cmd_retire(a):
    rec = load_proposal(a.proposal, "retire")
    c = verify_approval(a.proposal, a.approved_comment)
    lessons = parse_lessons()
    for k in lessons:
        lessons[k] = [l for l in lessons[k] if l["id"] != rec["lesson"]]
    write_lessons(lessons)
    push_skill()
    rec.update({"status": "applied", "approved_by_comment": c["id"]})
    json.dump(rec, open(f"{proposals_dir()}/{a.proposal}.json", "w"), indent=2)
    audit("retire", rec["lesson"], f"{a.proposal} approved in comment {c['id']}")
    print(f"RETIRED {rec['lesson']}, skill updated, backup file updated")


def cmd_reject(a):
    try:
        rec = json.load(open(f"{proposals_dir()}/{a.proposal}.json"))
    except OSError:
        raise SystemExit(f"unknown proposal {a.proposal}")
    c = verify_approval(a.proposal, a.comment, word="REJECT")
    rec.update({"status": "rejected", "rejected_by_comment": c["id"]})
    json.dump(rec, open(f"{proposals_dir()}/{a.proposal}.json", "w"), indent=2)
    audit("reject", a.proposal, f"comment {c['id']}")
    print(f"recorded rejection of {a.proposal}")


# ------------------------------------------------------------------ show / sync / init
def cmd_show(a):
    text = render(parse_lessons())
    if not a.role:
        print(text)
        return
    want = norm_role(a.role)
    heads = {k: h for k, h, _ in SECTIONS}
    for key in ("all", want):
        m = re.search(rf"(?ms)^## {re.escape(heads[key])}\n(.*?)(?=^## |\Z)", text)
        print(f"## {heads[key]}\n{m.group(1).strip() if m else ''}\n")


def live_skill():
    cfg = load_config()
    d = mc("skill", "get", cfg["skill_id"], "--with-content", "--output", "json")
    return d.get("content") or ""


def cmd_sync(a):
    if not os.path.exists(path("LESSONS.md")):
        write_lessons(parse_lessons())
    mine = open(path("LESSONS.md")).read().strip()
    live = live_skill().strip()
    same = mine == live
    print("in sync: backup lessons/LESSONS.md == live skill" if same else "DRIFT: live skill differs from lessons/LESSONS.md")
    if a.push and not same:
        push_skill()
        print("pushed backup file to the skill")
    if a.adopt and not same:
        open(path("LESSONS.md"), "w").write(live + "\n")
        print("adopted live skill text into lessons/LESSONS.md")
    sys.exit(0 if same else 1)


def cmd_init(a):
    cfg = load_config()
    os.makedirs(DATA, exist_ok=True)
    if not os.path.exists(path("LESSONS.md")):
        write_lessons(parse_lessons())
    if not cfg.get("skill_id"):
        d = mc("skill", "create", "--name", "cirdoc-lessons", "--description",
               "Approved lessons from earlier CirDoc runs (fixes for tool, path, workflow and review problems). Read the 'All agents' section and your role's section at the start of EVERY run and follow them as rules.",
               "--content-file", path("LESSONS.md"), "--output", "json")
        cfg["skill_id"] = d["id"]
        save_config(cfg)
        print("created skill", d["id"])
    print(json.dumps(cfg, indent=2))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan"); s.add_argument("issue"); s.set_defaults(f=cmd_scan)
    s = sub.add_parser("mark"); s.add_argument("issue"); s.add_argument("note", nargs="?"); s.set_defaults(f=cmd_mark)
    s = sub.add_parser("show"); s.add_argument("role", nargs="?"); s.set_defaults(f=cmd_show)
    s = sub.add_parser("propose")
    s.add_argument("--issue", required=True); s.add_argument("--role"); s.add_argument("--problem"); s.add_argument("--cause")
    s.add_argument("--rule"); s.add_argument("--evidence"); s.add_argument("--retire"); s.add_argument("--reason")
    s.set_defaults(f=cmd_propose)
    s = sub.add_parser("add"); s.add_argument("--proposal", required=True); s.add_argument("--approved-comment", required=True); s.set_defaults(f=cmd_add)
    s = sub.add_parser("retire"); s.add_argument("--proposal", required=True); s.add_argument("--approved-comment", required=True); s.set_defaults(f=cmd_retire)
    s = sub.add_parser("reject"); s.add_argument("--proposal", required=True); s.add_argument("--comment", required=True); s.set_defaults(f=cmd_reject)
    s = sub.add_parser("sync"); s.add_argument("--check", action="store_true"); s.add_argument("--push", action="store_true"); s.add_argument("--adopt", action="store_true"); s.set_defaults(f=cmd_sync)
    s = sub.add_parser("init"); s.set_defaults(f=cmd_init)
    a = ap.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
