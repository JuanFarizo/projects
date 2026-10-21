# 003 - Lessons learned and working method

Status: written after P1, P2 lessons added at the end of P2 (section 3b). Update at the end of every plan (last task of each plan, next to the README update). This file records what P1 and P2 taught us: how the reference repos are used, what surprised us, and how to build the next feature faster and safer. It does not contradict `001-architecture.md`.

## 1. Reference repos: what each is for

Four repos are used (all four cloned; `spring-tools` since P2 Task 0), read only in `~/.cache/nv4j/` (not committed). The method is always check, adapt, enhance: read how the reference does it, record it in `specs/features/<feature>.md` with the source path, then build the smallest Neovim version that meets the budget.

| Repo | License | Clone | Use it for | What P1 took from it |
|------|---------|-------|------------|----------------------|
| `jetbrains/intellij-community` | Apache-2.0 | `~/.cache/nv4j/intellij-community` | The target behaviour: ordering, inspections, intentions, refactorings, run configs. Spring features are NOT here (Ultimate only). | Completion weigher chain (`JavaCompletionSorting`, `PreferMostUsedWeigher`, `LookupElementProximityWeigher`): usage counts as tie breaker, project before SDK, postfix templates after members, `mayStartClassNameCompletion` (classes only after one typed char). Unused imports kept in files with errors. |
| `eclipse-jdt/eclipse.jdt.core` | EPL-2.0 | `~/.cache/nv4j/eclipse.jdt.core` | What jdt.ls really runs on: `CompletionEngine` relevance, `RelevanceConstants`, ECJ problem reporting. Read it to learn WHY jdt.ls behaves a way before working around it. | Relevance is one integer sum (no tie-break chain, no usage stats, `java.*` gets +2). ECJ drops unused-import/local warnings when the file has errors. |
| `eclipse-jdt/eclipse.jdt.ls` | EPL-2.0 | `~/.cache/nv4j/eclipse.jdt.ls` | The LSP layer: `CompletionProposalRequestor`, `ProposalComparator`, `SortTextHelper`, `Preferences`, code action and codegen handlers. | `sortText = 999999999 - (relevance*16 + kindOffset)`; postfix items carry the receiver in `filterText`; settings that matter (`filteredTypes`, `postfix`, `maxResults`, `guessMethodArguments`). |
| `spring-projects/spring-tools` | EPL-2.0 | `~/.cache/nv4j/spring-tools` (sparse, commit `9c979426`) | The Spring Boot language server (annotation attributes, `application.properties`/`yml`, beans, request mappings), launch and Boot Dash behaviour. The server P2 installs (Mason `vscode-spring-boot-tools`). | P2: the exact VS Code launch command and JVM args, the `sts/*` client protocol (why `spring-boot.nvim` saves code, D14), the jdt.ls extension bundles, `ValueDefinitionProvider` for `@Value` go to definition. Nothing copied. |

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
- **Debug was blocked by a classpath warning** (solved in P2 Task 1). `m2e.launchconfig.classpathProvider` was a race in JDT launching (`JavaRuntime.initializeProviders()` fills a shared map without a lock) hit by nvim-jdtls's parallel classpath requests; the first launching calls now go one at a time. Read the installed jar (`javap -c`) when a race is suspected: the clone is newer than what runs.
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

## 3b. P2 lessons (run, debug, Spring Boot LS)

What went wrong or cost time in P2 (task reports in the SDD ledger, details in `specs/004-p2-spring-run-debug.md` and the feature specs), and the rule that fixes it. These rules apply from P3 on, next to the table above.

| Problem seen in P2 | Rule for next plans |
|--------------------|---------------------|
| `40_debug` `classpath_first` measures a timing race: before the fix a lucky run can pass, so the case alone proves nothing (Task 0) | A race-prone check gets a deterministic twin that fails every time without the fix (`breakpoint_hit` next to `classpath_first`), and the spec says which case carries the baseline. |
| `no_orphan` passed vacuously in 2 of 4 baseline runs because the app had already died by itself | Absence checks first assert the thing was present (the JVM alive before terminate), then that it is gone. |
| A test cleanup ran `pkill -9 -f 6042`, which matches any process with those digits in its command line; a Chrome renderer matched (Task 2) | Test cleanup kills only by pid or by an anchored full pattern (`^perl .*6042`, `^sleep 6041`). Never a broad `pkill -f` on a short token, in tests or by hand. |
| A report said `@Value("${` "bypasses `max_items`"; the reviewer read the diff and it did not (the keys showed only because of alphabetical order and fixture naming) (Task 4) | Reviewers verify every mechanism claim against the diff and a test that would fail without it, not against the report. A claim without a failing control is rewritten or removed. |
| The fix for that claim was only proven once a fixture key sorting after every Boot key (`zz.sample.flag`) failed without it | Every new case cites a negative control (product change reverted or stubbed, the case FAILs) with its log path in the trial log (`neg-n4-52-...log`, c4 root-only kill, gating removed in `50`). A control that does not fail is recorded as unusable (n3), not counted. |
| Spring Boot detection was written twice (run and Spring LS) with different rules; a bare `spring-boot.version` property counted in one (Task 3 review) | One detector per concept, shared (`nv4j/root.lua` `boot_build`/`boot_project`), with a `detect` case in every check that consumes it, asserting the consumers agree. |
| First requests to a just-started server (Spring LS completion, `@Value`, `@Profile`, yml hover) were slow or empty in the first millisecond | Same rule as D13: pin the first request 1.0 s after init/open, and write the pin as a deviation with its cost in the README Known limitations; never hide an outlier with a warm-up the check then measures (trial c6 reverted). An outlier gets its own case with a regression limit (`hover_yml_port`, 1 s). |
| A 1 s `vim.defer_fn` fired after 671 ms under load (libuv's cached loop time) and failed `build_guard` once (Task 3) | Call `vim.uv.update_time()` before arming a timer whose duration matters, and assert durations against the fresh clock. |
| `32_code_actions` flaked: Nv4J's own copy of the unused-import warning satisfied the wait before jdt.ls's diagnostic arrived (Task 4) | A check waits for the exact producer it depends on (source/namespace), not for any matching diagnostic. A flake is investigated to a cause, not retried away. |
| A Task 3 agent hit the rate limit mid-task and was resumed | Resumed agents re-read `git status`, the brief and their own partial diff before continuing; the report says it was resumed. Commits stay small enough that a resume starts from a clean point. |
| Product code wraps plugin internals at runtime (`client.request`, `jdtls.start_or_attach`, `dap.adapters.java`) to fix upstream races (Task 1) | Allowed only with a check that fails without the wrap and a line in Known limitations; plugins stay pinned in `lazy-lock.json` (or `commit =`) so an update cannot silently break the wrap. |
| `mvn spring-boot:run` could not be run here (plugin resolution through an unreachable company mirror) | Something the environment cannot run is written as "checked as a command, not run" in README Not yet, with the stand-in that was tested (`tree_kill` on a synthetic process tree). |
| Stale case counts and PASS totals in specs after review rounds (004 said 19/10 cases and 219 PASS after the cases became 20/12 and the total 218) | The final task recomputes totals from the `DONE` lines of the last run and greps the specs for old counts. |

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

P2 rulings (costs in `specs/004-p2-spring-run-debug.md`): debug before the Spring LS (blocker first); D14 `spring-boot.nvim` pinned over own client; D15 run via `java -cp` over `mvn spring-boot:run`; build with compile errors warns and launches; JUnit launcher replaced from `~/.m2`; Spring client keeps full capabilities on Java buffers; one Boot detector, memoized per session; `<leader>sp` instead of `<leader>ss`; 1.0 s pins for first Spring requests; `hover_yml` budgeted on `logging.level` with `server.port` as a 1 s regression case; `@Value` project keys first by a fixed Boot namespace list; no `/people` mapping in the fixture.

## 4. Checklist for starting a new plan

- [ ] Update `001` status, `README` Not yet list, and this file at the end, not at the start.
- [ ] Clone the repo the feature needs into `~/.cache/nv4j/`, pin the commit.
- [ ] Extend the fixture so the pain point fails the baseline.
- [ ] Define budgets before coding. Do not weaken them to pass.
- [ ] Brief names allowed paths and expected `DONE` lines.
- [ ] Final whole-branch review on the most capable model, one fix wave, then push to `main` as the user, no trailer.
