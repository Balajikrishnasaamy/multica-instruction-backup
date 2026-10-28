# cirdoc-code-index: map of the circuit repo, so you do not have to read the code

This skill holds `circuit-index.md` (same folder as this file): a generated map of the circuit repository (controllers and the bean/handler each uses, URL entities, layers, executor actors, existing unit tests, high-risk files, and a "symptom -> where to look first" list).

## Who uses it and how
- **Classify & Route**: use the index INSTEAD of opening the repo. Read `circuit-index.md` once, then explain the issue: what the symptom means, which area and files are the likely place, whether a unit test exists for that area, and whether any high-risk file is likely involved. Do not clone or grep the repository to do this.
- **Workers, Feasibility Engineer**: the index is where to start looking, nothing more. Everything it says about the issue is a hint. Verify against the code before you rely on it, and report the real root cause yourself.

## Rules
- The index covers only the **circuit** repo (branch CIRCUIT_KB_STAGING). For qntrlworker or qntrlcore there is no index: say "no code index for this repo" and leave the suspected-area line out. Never fill the gap by guessing file names.
- Every file or class you name must appear in the index. If the symptom is not covered by the index, write "area unknown, worker to find it". An honest "unknown" is better than a plausible guess.
- A name you took from the index is "suspected", never "the cause". Do not state a root cause, a line number or a fix: you have not read the code.
- The index header shows the commit it was built from. If the issue mentions a file or class that is not in the index, the index may be older than the code: say so in one line.
- Never edit this skill or the index. If the index misled you, put one LESSON block at the end of your comment (see cirdoc-lessons).
