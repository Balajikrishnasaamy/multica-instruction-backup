#!/usr/bin/env python3
"""Upload skills-src/<skill>/ to the Multica skill of the same name; delete Multica files that no longer exist locally.
Usage: sync_skills.py [--apply] [skill ...]      (default: dry run, all skills below)
Source of truth: ~/multica-instruction-backup/skills-src/. skills-src-original/ keeps the untouched .claude copies for diffing."""
import json, os, subprocess, sys, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "skills-src")
M = ["/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica", "--profile", "desktop-api.multica.ai"]
ENV = dict(os.environ, MULTICA_WORKSPACE_ID="85121eb5-c9c7-4018-a975-140810c991cb")
DESC = {  # description overrides (frontmatter description of SKILL.md is the default)
    "circuit-engineer": None, "reactor-actor-engineer": None}
def run(*a, check=True):
    r = subprocess.run(M + list(a), capture_output=True, text=True, env=ENV)
    if check and r.returncode: raise SystemExit(f"multica {' '.join(a[:3])} failed: {r.stderr.strip()[:300]}")
    return r.stdout
def frontmatter_desc(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m: return None
    fm = m.group(1)
    d = re.search(r"^description:\s*(>-?|\|-?)?\s*(.*?)(?=^\w+:|\Z)", fm, re.S | re.M)
    if not d: return None
    body = d.group(2)
    return " ".join(x.strip() for x in body.strip().strip("'\"").splitlines() if x.strip())
apply = "--apply" in sys.argv
names = [a for a in sys.argv[1:] if not a.startswith("--")] or sorted(os.listdir(SRC))
skills = {s["name"]: s["id"] for s in json.loads(run("skill", "list", "--output", "json"))}
for name in names:
    sid = skills.get(name)
    if not sid: print(f"{name}: no such Multica skill, skipping"); continue
    base = os.path.join(SRC, name)
    local = {}
    for r, _, fs in os.walk(base):
        for f in fs:
            if f == ".DS_Store": continue
            p = os.path.join(r, f); local[os.path.relpath(p, base)] = open(p, encoding="utf-8").read()
    skill_md = local.pop("SKILL.md")
    live = json.loads(run("skill", "get", sid, "--with-content", "--output", "json"))
    live_files = {f["path"]: f for f in live.get("files", [])}
    desc = frontmatter_desc(skill_md)
    plan = []
    if (live.get("content") or "") != skill_md or (desc and desc != live.get("description")): plan.append("update SKILL.md/description")
    for path, txt in sorted(local.items()):
        if path not in live_files: plan.append(f"add    {path}")
        elif (live_files[path].get("content") or "") != txt: plan.append(f"change {path}")
    for path in sorted(set(live_files) - set(local)): plan.append(f"delete {path}")
    print(f"== {name} ({sid}): {len(plan)} change(s)"); [print("   ", x) for x in plan]
    if not apply: continue
    if any(x.startswith("update") for x in plan):
        args = ["skill", "update", sid, "--content-file", os.path.join(base, "SKILL.md"), "--output", "json"]
        if desc: args += ["--description", desc]
        run(*args)
    for path, txt in sorted(local.items()):
        if path not in live_files or (live_files[path].get("content") or "") != txt:
            run("skill", "files", "upsert", sid, "--path", path, "--content-file", os.path.join(base, path), "--output", "json")
    for path in sorted(set(live_files) - set(local)):
        run("skill", "files", "delete", sid, live_files[path]["id"])
    # verify by downloading again
    chk = json.loads(run("skill", "get", sid, "--with-content", "--output", "json"))
    got = {f["path"]: f.get("content") or "" for f in chk.get("files", [])}
    bad = [p for p in local if got.get(p) != local[p]] + ([] if (chk.get("content") or "") == skill_md else ["SKILL.md"]) + [p for p in got if p not in local]
    print(f"   verified after upload: {'OK, all ' + str(len(local) + 1) + ' files identical' if not bad else 'MISMATCH ' + str(bad)}")
