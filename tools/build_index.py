#!/usr/bin/env python3
"""Build a compact code index of the circuit repo for the cirdoc-code-index skill.
Usage: build_index.py <repo-dir> <git-ref> <out-file>
Reads the ref with `git archive` (never touches the working tree). Facts only, no guesses."""
import re, os, sys, glob, subprocess, tempfile, tarfile, io, datetime

repo, ref, out = sys.argv[1:4]
repo, out = os.path.abspath(repo), os.path.abspath(out)
tmp = tempfile.mkdtemp()
data = subprocess.check_output(["git", "-C", repo, "archive", ref, "source", "test", "product_package"])
tarfile.open(fileobj=io.BytesIO(data)).extractall(tmp)
sha = subprocess.check_output(["git", "-C", repo, "rev-parse", ref]).decode().strip()
os.chdir(tmp)
W = "source/worker/com/qntrl/circuit"
E = "source/executor/com/qntrl/execution"
rd = lambda p: open(p, errors="ignore").read()
HANDLERS = {os.path.basename(p)[:-5] for p in glob.glob("source/worker/**/*Handler.java", recursive=True)}
lines = []
add = lines.append

add(f"# circuit code index (generated {datetime.date.today()} from {ref} @ {sha[:10]})")
add("Facts derived from the code. Use it to explain a symptom and name the likely area. It is a hint: the worker must verify against the code.\n")

add("## Controllers (source/worker/com/qntrl/circuit/controller) -> bean / handler they use, public HTTP methods")
for p in sorted(glob.glob(f"{W}/controller/*Controller.java")):
    s = rd(p); n = os.path.basename(p)[:-5]
    model = re.search(r"ModelDriven<(\w+)>", s)
    handlers = sorted(h for h in set(re.findall(r"\b([A-Z]\w+Handler)\b", s)) if h in HANDLERS)[:3]
    meths = [m for m in re.findall(r"public\s+(?:String|void)\s+(index|show|create|update|destroy|\w+)\s*\(\s*\)", s)]
    meths = [m for m in meths if m not in ("execute", "validate", "input")][:8]
    add(f"- {n}: {('bean ' + model.group(1)) if model else ''} {('handlers ' + ','.join(handlers)) if handlers else ''} methods {','.join(meths)}".replace("  ", " "))

add("\n## URL entities in security-api.xml (/qntrl/api/v2/{portal}/{workspace}/{entity}[/{id}/{sub-entity}...]). methods in []; '->Controller' only when the entity name equals a controller name")
ctrl = {os.path.basename(p)[:-15].lower(): os.path.basename(p)[:-5] for p in glob.glob(f"{W}/controller/*Controller.java")}
ents = {}
for m in re.finditer(r'<url path="([^"]+)" method="(\w+)"', rd("product_package/conf/Security/QntrlCircuit/security-api.xml")):
    segs = [x for x in m.group(1).split("/") if x and x not in ("qntrl", "api", "v2")]
    plain = [x for x in segs if not x.startswith("${")]
    if plain:
        ents.setdefault(plain[0], {"m": set(), "sub": set()})
        ents[plain[0]]["m"].add(m.group(2)[0].upper())
        ents[plain[0]]["sub"].update(plain[1:])
for e, v in sorted(ents.items()):
    c = ctrl.get(e.replace("_", "").lower())
    add(f"- {e}[{''.join(sorted(v['m']))}]" + (f"->{c}" if c else "") + (f" sub: {','.join(sorted(v['sub']))}" if v["sub"] else ""))
add("(Sub-entities such as executions/rerun are served by the controller of the last entity: CustomActionMapper turns the entity name into a lower-hyphen action name. Other security-*.xml files are _admin, _internal, _mcp, _tool, _web.)")

def names(d):
    return sorted(os.path.basename(p)[:-5] for p in glob.glob(f"{d}/*.java"))
layers = [("Handlers", f"{W}/handler"), ("Request beans", f"{W}/bean/request"), ("Transaction beans", f"{W}/bean/transaction"),
          ("DB access/datasets", f"{W}/db"), ("Graph/validation", f"{W}/graph"), ("Utils", f"{W}/util"), ("Responses", f"{W}/response")]
add("\n## Worker layers (names only)")
for t, d in layers:
    n = names(d)
    if n: add(f"- {t} ({d.replace(W + '/', '')}): " + ", ".join(n))
add("- Integrations (integration/): " + ", ".join(sorted(x for x in os.listdir(f"{W}/integration") if os.path.isdir(f"{W}/integration/{x}"))))

add("\n## Executor (source/executor/com/qntrl/execution)")
for sub in ("actor", "task", "handler"):
    n = sorted(os.path.basename(p)[:-5] for p in glob.glob(f"{E}/{sub}/**/*.java", recursive=True))
    add(f"- {sub}: " + ", ".join(n))

add("\n## Existing unit tests (test/): a class named like its subject")
tests = sorted(os.path.relpath(p, "test")[:-5].replace("/", ".") for p in glob.glob("test/**/*Test.java", recursive=True))
add(", ".join(t.replace("com.qntrl.circuit.", "") for t in tests))
add("Everything not listed has no unit test: a fix there needs a new test or the human dev test.")

add("\n## High-risk files (risk: high if touched)")
for pat in ("product_package/conf/Security/**/security-*.xml", "product_package/conf/Circuit/data-dictionary*.xml",
            "product_package/conf/*.conf", "product_package/conf/ReactorWorker/*.conf", "product_package/conf/Circuit/bean.xml"):
    for p in sorted(glob.glob(pat, recursive=True)): add(f"- {p}")
add(f"- {E}/handler/ActorHandleable.java, ExecutorHandler.java (used by every actor)")
add("- source/entity/** is generated from the data dictionary: never edited by hand")

add("\n## Symptom -> where to look first")
add("- API returns wrong/missing field in a list or show response: the controller's bean (request) and the handler; for responses see response/.")
add("- 400/409 validation error text or code: exception/ErrorResponseType.java and the handler that throws ValidationException.")
add("- URL not found / 404 / scope or permission: product_package/conf/Security/QntrlCircuit/security-api.xml (high risk) and CustomActionMapper (source/qntrl/com/qntrl/struts).")
add("- Execution stuck/failed at a state: executor/actor/* and executor/task/*; state definition in worker state/ and graph/.")
add("- Placeholder / ${...} substitution: substitutor/QntrlSubstitutor and graph/PlaceholderValidator.")

open(out, "w").write("\n".join(lines) + "\n")
print(f"wrote {out}: {os.path.getsize(out)} bytes, {len(lines)} lines")
