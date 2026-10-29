#!/usr/bin/env python3
"""Builds a single-file, self-contained HTML test report for run_test.sh.

Usage: report.py <meta.json> <results.tsv or -> <console.log or -> <out.html>
meta.json keys: repo, src, branch, sha, dirty, classes[], command, status, summary, phase,
                started, duration_s, java, compile_log (optional)
status: PASS | FAIL | ERROR
"""
import html
import json
import re
import sys

meta = json.load(open(sys.argv[1]))
tsv, console, out = sys.argv[2], sys.argv[3], sys.argv[4]


def unesc(s):
    return re.sub(r"\\(.)", lambda m: {"t": "\t", "n": "\n", "\\": "\\"}.get(m.group(1), m.group(1)), s)


def read(path):
    if path == "-":
        return ""
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


# Anything that looks like a secret is masked before it reaches the report.
SECRET = re.compile(r"(?i)((?:password|passwd|secret|token|privatekey|private_key|authtoken|apikey|api_key|client\.secret)[A-Za-z0-9_.]*\s*[=:]\s*)[^\s,;&\"']+")


def mask(s):
    return SECRET.sub(r"\1****", s)


rows = []
for line in read(tsv).splitlines():
    p = line.split("\t")
    if len(p) < 5:
        continue
    p += [""] * (10 - len(p))
    ents = []
    for item in unesc(p[7]).split("\x02"):
        if "\x01" in item:
            k, v = item.split("\x01", 1)
            ents.append((k, v))
    rows.append({
        "cls": unesc(p[0]), "method": unesc(p[1]), "display": unesc(p[2]), "status": p[3],
        "ms": int(p[4] or 0), "msg": unesc(p[5]), "trace": unesc(p[6]),
        "entries": ents, "expected": unesc(p[8]), "actual": unesc(p[9]),
    })

counts = {k: sum(1 for r in rows if r["status"] == k) for k in ("PASSED", "FAILED", "SKIPPED", "ABORTED")}
total = len(rows)
by_class = {}
for r in rows:
    by_class.setdefault(r["cls"] or "(unknown)", []).append(r)

status = meta["status"]
color = {"PASS": "#1a7f37", "FAIL": "#cf222e", "ERROR": "#9a6700"}[status]
e = html.escape


def badge(s):
    c = {"PASSED": "#1a7f37", "FAILED": "#cf222e", "SKIPPED": "#6e7781", "ABORTED": "#9a6700"}[s]
    return f'<span class="b" style="background:{c}">{s}</span>'


LABELS = {"input": "Input", "output": "Output (got)", "expected": "Expected", "actual": "Actual", "note": "Note"}


def io_block(r, failed):
    """Input / output / expected for one test. Published entries come first, in the order the test wrote them;
    on failure the assertion's own expected/actual values are added when the test did not publish them."""
    items = [(k, v) for k, v in r["entries"]]
    have = {k.lower() for k, _ in items}
    if failed:
        if r["expected"] and "expected" not in have:
            items.append(("expected", r["expected"]))
        if r["actual"] and not ({"output", "actual"} & have):
            items.append(("actual", r["actual"]))
    if not items:
        return ""
    out = ['<table class="io">']
    for k, v in items:
        lab = LABELS.get(k.lower(), k)
        cls = {"expected": "exp", "output": "got", "actual": "got"}.get(k.lower(), "")
        out.append(f'<tr class="{cls}"><td>{e(lab)}</td><td><pre>{e(mask(v))}</pre></td></tr>')
    out.append("</table>")
    return "".join(out)


parts = []
parts.append(f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>Test report: {e(meta['status'])} - {e(meta['repo'])} {e(meta['sha'][:10])}</title>
<style>
body{{font:14px/1.5 -apple-system,Segoe UI,Helvetica,Arial,sans-serif;margin:0;background:#f6f8fa;color:#1f2328}}
header{{background:{color};color:#fff;padding:18px 28px}}
header h1{{margin:0;font-size:22px}} header .sub{{opacity:.9;margin-top:4px}}
main{{max-width:1100px;margin:0 auto;padding:20px 28px 60px}}
.cards{{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0}}
.card{{background:#fff;border:1px solid #d0d7de;border-radius:8px;padding:10px 18px;min-width:90px;text-align:center}}
.card .n{{font-size:26px;font-weight:600}} .card .l{{color:#656d76;font-size:12px;text-transform:uppercase}}
table{{border-collapse:collapse;width:100%;background:#fff;border:1px solid #d0d7de;border-radius:8px;overflow:hidden}}
th,td{{text-align:left;padding:7px 12px;border-bottom:1px solid #eaeef2;vertical-align:top}} th{{background:#f6f8fa;font-size:12px;color:#656d76;text-transform:uppercase}}
.meta td:first-child{{width:150px;color:#656d76}}
.b{{color:#fff;border-radius:10px;padding:1px 9px;font-size:11px;font-weight:600}}
h2{{margin:28px 0 8px;font-size:16px}} h3{{margin:18px 0 6px;font-size:14px;font-family:ui-monospace,Menlo,monospace}}
pre{{background:#0d1117;color:#e6edf3;padding:12px 14px;border-radius:8px;overflow:auto;font:12px/1.45 ui-monospace,Menlo,monospace;white-space:pre-wrap;word-break:break-word;margin:6px 0}}
details{{background:#fff;border:1px solid #d0d7de;border-radius:8px;margin:6px 0;padding:6px 12px}}
summary{{cursor:pointer}} .ms{{color:#656d76;font-size:12px}} .fail summary{{color:#cf222e}}
code{{font-family:ui-monospace,Menlo,monospace;font-size:12px}}
.filter{{margin:8px 0}} .filter label{{margin-right:14px;cursor:pointer}}
table.io{{margin:6px 0 4px 0;border:1px solid #d0d7de}} table.io td{{padding:4px 10px;border-bottom:1px solid #eaeef2}}
table.io td:first-child{{width:110px;color:#656d76;font-size:12px;text-transform:uppercase;white-space:nowrap}}
table.io pre{{margin:0;padding:6px 8px;background:#f6f8fa;color:#1f2328;border-radius:4px}}
table.io tr.exp pre{{background:#dafbe1}} table.io tr.got pre{{background:#fff1f0}}
.io-row td{{background:#fbfcfd}}
footer{{color:#656d76;font-size:12px;margin-top:30px}}
</style></head><body>
<header><h1>{e(status)} &mdash; {e(meta['summary'])}</h1>
<div class="sub">{e(meta['repo'])} @ {e(meta['sha'][:10])}{' (uncommitted changes in checkout)' if meta.get('dirty') else ''} &middot; {e(meta['started'])} &middot; {meta['duration_s']}s</div></header>
<main>""")

if status == "ERROR" and meta.get("phase") in ("compile", "run", "setup"):
    parts.append(f'<h2>Stopped at: {e(meta["phase"])}</h2>')

parts.append('<div class="cards">')
for lab, n in (("Tests", total), ("Passed", counts["PASSED"]), ("Failed", counts["FAILED"]), ("Skipped", counts["SKIPPED"] + counts["ABORTED"])):
    col = {"Passed": "#1a7f37", "Failed": "#cf222e"}.get(lab, "#1f2328") if n or lab == "Tests" else "#1f2328"
    parts.append(f'<div class="card"><div class="n" style="color:{col}">{n}</div><div class="l">{lab}</div></div>')
parts.append("</div>")

parts.append('<h2>Run details</h2><table class="meta">')
for k, v in (
    ("Repository", meta["repo"]), ("Commit", meta["sha"] + (" + uncommitted changes" if meta.get("dirty") else "")),
    ("Branch", meta.get("branch") or "-"), ("Checkout", meta["src"]),
    ("Test classes", ", ".join(meta["classes"])), ("Command", meta["command"]), ("Java", meta["java"]),
    ("Started", meta["started"]), ("Duration", f"{meta['duration_s']}s"),
):
    parts.append(f"<tr><td>{e(k)}</td><td><code>{e(str(v))}</code></td></tr>")
parts.append("</table>")

cl = mask(meta.get("compile_log") or "")
if cl.strip():
    parts.append(f"<h2>Compile errors</h2><pre>{e(cl)}</pre>")

if rows:
    failed = [r for r in rows if r["status"] in ("FAILED", "ABORTED")]
    if failed:
        parts.append(f"<h2>Failures ({len(failed)})</h2>")
        for r in failed:
            name = r["method"] or r["display"]
            parts.append(f'<details class="fail" open><summary>{badge(r["status"])} <b>{e(r["cls"])}</b>#{e(name)} <span class="ms">{r["ms"]} ms</span></summary>'
                         f'{io_block(r, True)}<pre>{e(mask(r["trace"] or r["msg"]))}</pre></details>')

    parts.append('<h2>All tests</h2><div class="filter">'
                 '<label><input type="checkbox" id="onlyfail"> show only failed / skipped</label></div>')
    for cls, rs in sorted(by_class.items()):
        p = sum(1 for r in rs if r["status"] == "PASSED")
        parts.append(f"<h3>{e(cls)} &mdash; {p}/{len(rs)} passed</h3><table><tr><th style='width:90px'>Status</th><th>Test</th><th style='width:80px'>Time</th><th>Message</th></tr>")
        for r in sorted(rs, key=lambda x: (x["status"] == "PASSED", x["method"])):
            name = r["method"] or r["display"]
            disp = f' <span class="ms">{e(r["display"])}</span>' if r["display"] and r["display"] != name + "()" and r["display"] != name else ""
            parts.append(f'<tr class="row {r["status"]}"><td>{badge(r["status"])}</td><td><code>{e(name)}</code>{disp}</td><td class="ms">{r["ms"]} ms</td><td>{e(mask(r["msg"]))[:300]}</td></tr>')
            blk = io_block(r, r["status"] in ("FAILED", "ABORTED"))
            if blk:
                parts.append(f'<tr class="row {r["status"]} io-row"><td></td><td colspan="3">{blk}</td></tr>')
        parts.append("</table>")
    parts.append("""<script>document.getElementById('onlyfail').addEventListener('change',function(){
document.querySelectorAll('tr.row.PASSED').forEach(function(r){r.style.display=this.checked?'none':''}.bind(this))})</script>""")

log = mask(read(console))
log = "\n".join(l[:400] for l in log.splitlines() if not l.startswith(("INFO:", "SLF4J")) and "com.zoho.conf.Configuration" not in l)
if log.strip():
    parts.append(f"<h2>Console output</h2><details><summary>show ({len(log.splitlines())} lines)</summary><pre>{e(log[-60000:])}</pre></details>")

parts.append(f"<footer>Generated by run_test.sh &middot; secrets in output are masked</footer></main></body></html>")
open(out, "w", encoding="utf-8").write("".join(parts))
