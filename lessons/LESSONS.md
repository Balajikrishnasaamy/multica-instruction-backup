# CirDoc lessons: approved fixes for problems earlier runs already hit

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

## All agents
- **A-001** (CIRD-23, 2026-10-28): The repo checkout is <workdir>/<repo>, not your workdir, and each bash call starts in the workdir. Run git as `git -C <workdir>/<repo> ...`. `fatal: not a git repository` means wrong folder: fix the path, never retry the same command. — why: a worker repeated one failing git command 476 times in one run
- **A-002** (CIRD-23, 2026-10-28): A run is killed by the provider near 1000 messages (about 500 tool calls). If you pass about 150 tool calls without a commit or a verdict, stop and post BLOCKED with what you tried. — why: the same run died with HTTP 400 'messages array size out of range 1-1000' at 505 tool calls

## Worker
- **W-001** (CIRD-23, 2026-10-28): Do not use EntityUtilTest or CriteriaQueryParserTest as your targeted test: they do not compile on an unchanged CIRCUIT_KB_STAGING (Entity.getEntityAdapter, Byte vs int). Pick another test class or write a new one, and never report that compile error as caused by your change. — why: verified with run_test.sh on the untouched target branch

## Reviewer
- (no lessons yet)

## Classify & Route
- (no lessons yet)

## Planning (Plan Lead, Requirements Analyst, Feasibility Engineer)
- (no lessons yet)

## Lessons Curator
- (no lessons yet)
