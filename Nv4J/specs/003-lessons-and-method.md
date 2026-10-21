# 003 - Lessons learned and working method

Status: written after P1. Update at the end of every plan (last task of each plan, next to the README update). This file records what P1 taught us: how the reference repos are used, what surprised us, and how to build the next feature faster and safer. It does not contradict `001-architecture.md`.

## 1. Reference repos: what each is for

Four repos are used (three cloned now, `spring-tools` at P2 start), read only in `~/.cache/nv4j/` (not committed). The method is always check, adapt, enhance: read how the reference does it, record it in `specs/features/<feature>.md` with the source path, then build the smallest Neovim version that meets the budget.

| Repo | License | Clone | Use it for | What P1 took from it |
|------|---------|-------|------------|----------------------|
| `jetbrains/intellij-community` | Apache-2.0 | `~/.cache/nv4j/intellij-community` | The target behaviour: ordering, inspections, intentions, refactorings, run configs. Spring features are NOT here (Ultimate only). | Completion weigher chain (`JavaCompletionSorting`, `PreferMostUsedWeigher`, `LookupElementProximityWeigher`): usage counts as tie breaker, project before SDK, postfix templates after members, `mayStartClassNameCompletion` (classes only after one typed char). Unused imports kept in files with errors. |
| `eclipse-jdt/eclipse.jdt.core` | EPL-2.0 | `~/.cache/nv4j/eclipse.jdt.core` | What jdt.ls really runs on: `CompletionEngine` relevance, `RelevanceConstants`, ECJ problem reporting. Read it to learn WHY jdt.ls behaves a way before working around it. | Relevance is one integer sum (no tie-break chain, no usage stats, `java.*` gets +2). ECJ drops unused-import/local warnings when the file has errors. |
| `eclipse-jdt/eclipse.jdt.ls` | EPL-2.0 | `~/.cache/nv4j/eclipse.jdt.ls` | The LSP layer: `CompletionProposalRequestor`, `ProposalComparator`, `SortTextHelper`, `Preferences`, code action and codegen handlers. | `sortText = 999999999 - (relevance*16 + kindOffset)`; postfix items carry the receiver in `filterText`; settings that matter (`filteredTypes`, `postfix`, `maxResults`, `guessMethodArguments`). |
| `spring-projects/spring-tools` | EPL-2.0 | to clone at P2 start | The Spring Boot language server (annotation attributes, `application.properties`/`yml`, beans, request mappings), launch and Boot Dash behaviour. Likely the server we install in P2. | Nothing yet (P2). |

Rules for using them:

- Reference first, code never by default. Prefer a dependency (Mason package or release jar) over copying source.
- Copying EPL-2.0 code is allowed only with the original license header and a line in the feature spec naming the source path and commit. Apache-2.0 (IntelliJ) needs the notice kept.
- Pin the commit you read in the feature spec (see `specs/features/completion-ranking.md`). The clones are `master`; the installed server is older (jdt.ls 1.62, jdt.core 3.48), so line numbers can differ.
- Read the installed version when a detail decides the design (the jar in Mason, not only the clone).
- "Why does jdt.ls do X" is answered in `eclipse.jdt.core`/`jdt.ls`; "what should it do" is answered in IntelliJ. Do both lookups before designing.

## 2. Technical findings that change how we build

- **Measure the real thing.** The first fixture had no Spring dependencies and showed no lag. The real failures only appeared after adding web, JPA, security and validation. A fixture must resemble the user's project or the baseline lies.
- **The slow part is often not the list.** First completion cost 740-827 ms because jdt.ls was cold, not because of sorting. A warm-up request at `Started` and at `ServiceReady` fixed it (about 55 ms). Profile before tuning the sort.
- **Things that did not help** are logged in `specs/002-p1-completion.md` (ParallelGC, AppCDS, `maxResults` 50/1000, `lazyResolveTextEdit`). Always log the failed trials, they stop us repeating them.
- **Imports arrive late.** The import edit comes only in `completionItem/resolve`. blink gave up after 100 ms, so the import was missing. `resolve_timeout_ms` is 1500. Cost: up to ~0.8 s wait on accept for heavily documented types (async apply planned).
- **Frecency pollutes ranking.** blink's frecency pushed `RestController` from 4 to 27. Tests isolate state with `XDG_STATE_HOME=/tmp/nv4j/state`. Real sessions still suffer (follow-up in `002`).
- **ECJ drops warnings when errors exist.** Unused imports are recomputed in Lua with treesitter (p95 under 2 ms on 3000 lines).
- **JDT cache and `/tmp`.** The jdt.ls workspace must not live in `/tmp` (macOS wipes it). Logs and test output can.
- **Mason links.** A manually moved package leaves stale links; install retries must clean them (path-guarded `rm`).
- **Debug is blocked by a classpath warning.** `m2e.launchconfig.classpathProvider` fails on start. It must be solved before Spring run/debug (P2, first task).
- **Spring is outside Community IntelliJ.** For Spring the reference is user-visible IntelliJ Ultimate behaviour plus `spring-tools`.

## 3. Method improvements (apply from the next plan)

What went wrong or cost time in P1, and the rule that fixes it.

| Problem seen | Rule for next plans |
|--------------|---------------------|
| Baseline passed because the fixture was too easy | Task 0 of every plan: extend the fixture so the baseline FAILS the user's pain point first. A feature starts only with a failing, measured check. |
| A check died early and exited 0 | Every check prints `DONE <check> <pass> <fail>`; `run.sh` fails without it. Keep this contract for new checks. |
| Aborted runs saved edits into fixtures | `run.sh` ends each check with `qa!` and `</dev/null`. Fixtures are restored with `git checkout` after a run. Never run checks on the live fixture without that wrapper. |
| Flaky timing check (a log write inside the timed loop) | No I/O inside timed loops. Use 100 samples and a true p95. Pin the start point (e.g. 1.0 s after ServiceReady). |
| Test state leaked from the user's profile (blink frecency) | Isolate XDG state/cache in the harness. Stub anything that writes to user state. |
| Report claimed work that was not committed (T2) | The reviewer verifies claims against `git show`, not the report. The task is done only when the commit contains it. |
| An agent edited files outside its scope; 54 unrelated deletions showed in `git status` | Dispatch briefs name allowed paths. Stage explicit paths only (the git root is `~/Documents/projects`, never `git add -A`). Check `git status` before and after each agent. |
| Agent edits silently lost (broken `python3` pyenv shim) | Use `/usr/bin/python3` or avoid Python for edits; verify with `git diff` after every edit. |
| A fix round deleted part of a spec table | After editing a spec, diff against the previous commit; restore from git history, never rewrite from memory. |
| Co-author trailer slipped into commits | Rule in memory (`feedback_git_commits.md`). Check `git log --format=%B` for trailers before pushing. |
| Docs drifted from numbers (stale status lines) | Numbers live in ONE place (`001` budgets table + `002` trial log). README quotes them and says which check proves each. Final task re-reads README against the last run. |
| Review loop and long agent runs gave no progress signal | Each task brief states the check names and the expected count. Controllers report one line per milestone. |

### The per-feature loop (kept, tightened)

1. **Research**: read IntelliJ behaviour, then jdt.core/jdt.ls/spring-tools for the mechanism. Write `specs/features/<feature>.md` with source paths and pinned commits.
2. **Failing check first**: a headless check with a numeric budget that fails on current behaviour.
3. **Trial**: one change at a time. Log each in the trial table: change, effect on target, effect on others, kept or reverted.
4. **Profile**: p95 over enough samples, warm and cold. Compare to budget.
5. **Review**: task review (spec + quality), then scoped re-review of fixes. Cap 5 rounds, then adjudicate.
6. **Docs**: feature spec, `001` decisions/budgets, README capability row with the check name, memory file if a rule changed.
7. **Repeat** until the outcome is met or the trial log shows why it cannot be.

### Rulings are written down

Autonomous rulings (decisions taken without asking) are listed in the final report with what they cost if wrong, so the user can overturn them. P1 rulings: fixture extended with Spring deps; jdt.ls data in `~/.cache`; co-author trailers stripped from the first 7 commits before push; `java.awt.List` hidden; `java.awt.*`/`javax.swing.*` left visible; 400 ms cold budget kept; prettier extra dropped; lazy.nvim update check left on.

## 4. Checklist for starting a new plan

- [ ] Update `001` status, `README` Not yet list, and this file at the end, not at the start.
- [ ] Clone the repo the feature needs (`spring-tools` for P2) into `~/.cache/nv4j/`, pin the commit.
- [ ] Extend the fixture so the pain point fails the baseline.
- [ ] Define budgets before coding. Do not weaken them to pass.
- [ ] Brief names allowed paths and expected `DONE` lines.
- [ ] Final whole-branch review on the most capable model, one fix wave, then push to `main` as the user, no trailer.
