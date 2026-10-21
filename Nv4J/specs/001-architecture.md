# 001 - Architecture and workflow

Status: P1 confirmed and built (all 9 checks pass, 135 PASS on the last full runs). P2 to P5 not started. Source of truth for Nv4J. Later specs must not contradict this file. User-facing summary: `README.md` (keep both consistent; each later plan updates the README Capabilities section in its last task).

## Goal

A fast, lightweight Neovim setup for Java and Spring development. IntelliJ is the feature reference. Each feature gets a priority (P1 highest, P5 lowest) and a measurable pass/fail criterion.

## Decisions

D1 to D6 are confirmed by P1 (nothing was reversed). D7 to D13 are decisions taken during P1. D14 and later are P2 decisions (`specs/004-p2-spring-run-debug.md`).

| # | Decision | Owner | Status |
|---|----------|-------|--------|
| D1 | Start from the existing LazyVim-based config, keep only what Java/Spring needs. No rewrite from scratch. | Claude (user agreed to approach) | Confirmed. `lazyvim.json` dropped `lang.typescript.vtsls` and `formatting.prettier` (nothing used them). |
| D2 | Maven is first-class. Gradle is supported but second. | User | Confirmed. Gradle is untested (P4). |
| D3 | The existing `~/.config/nvim` is never modified. | User | Confirmed. |
| D4 | Config lives in this repo under `nvim/` and runs as a separate Neovim app named `nv4j`. | User | Confirmed. `~/.config/nv4j` is a symlink to `nvim/`. |
| D5 | Logs and temporary test output live under `/tmp/nv4j/`. The jdt.ls workspace (`-data`) and its writable `-configuration` copy are not temporary and live under `stdpath("cache")` (`~/.cache/nv4j/jdtls-data`, `~/.cache/nv4j/jdtls-config`): macOS empties `/tmp` on reboot and after 3 days, which forces a full re-import and can corrupt a running index. | User (`/tmp/nv4j`); final review (jdt.ls dirs) | Confirmed (`nvim/lua/nv4j/paths.lua`, check `00_boot`). |
| D6 | Priorities: P1 completion/diagnostics/imports/code actions/Java 25; P2 Spring awareness, run, debug; P3 tests, scaffolding, refactors; P4 Gradle, Spring navigation, JPA checks; P5 everything else. | User | Confirmed. P1 done. |
| D7 | Nothing is pinned to one JDK. JDKs come from SDKMAN (`~/.sdkman/candidates/java`), `~/Library/Java/JavaVirtualMachines`, `/Library/Java/JavaVirtualMachines`. jdt.ls runs on `$JAVA_HOME` if >= 21, else the newest >= 21; the project JDK follows `.sdkmanrc` and the pom. | User (Task 4) | Built: `nvim/lua/nv4j/jdk.lua`, `specs/features/jdk-java25.md`. |
| D8 | Unused-import warnings must show even when the file has compile errors (jdt.ls/ECJ drops them then, IntelliJ keeps them). | User (Task 6) | Built: `nvim/lua/nv4j/unused_imports.lua`. |
| D9 | `<leader>co` is Organize Imports (removes unused, orders groups). Outgoing calls moved to `<leader>cO` so each key means one thing. | User (Task 6) | Built, checked in `31_imports`. |
| D10 | Organize imports on save stays off (IntelliJ default). | User (Task 6) | Built (`java.saveActions.organizeImports = false`). |
| D11 | Completion ranking uses project usage counts, counted with ripgrep (IntelliJ `PreferMostUsedWeigher` idea), as a tie breaker after jdt.ls relevance. | Claude, accepted by user (Task 5) | Built: `nvim/lua/nv4j/usage.lua`; without `rg` ranking falls back to jdt.ls order. |
| D12 | `java.awt.List` is hidden from completion by default so `List` completes to `java.util.List`. Override with `vim.g.nv4j_filtered_types = { add = {...}, remove = {...} }`. | User (Task 5 review) | Built: `nvim/lua/nv4j/completion.lua`. |
| D13 | Budgets stay as set below, not weakened. `cold_first` is measured 1.0 s after jdt.ls ServiceReady. | Task 5 ruling | Confirmed with the numbers below. |
| D14 | Spring Boot language server wiring: the `JavaHello/spring-boot.nvim` plugin (pinned, commit `9880be4`) with the Mason `vscode-spring-boot-tools` server, configured by nv4j (root = the jdt.ls project root, `java_cmd` from `nv4j.jdk`, start only for Spring Boot projects), not our own thin Lua client. Reason: the plugin already implements the client half of the `sts/*` protocol (12 forwarders to jdt.ls, classpath-listener callbacks, language ids, settings push after classpath events), which our own client would have to re-implement in at least about 150 lines; it is Neovim 0.12 native and met every P2 Spring LS budget in the Task 0 trial (first completion 195 to 205 ms, warm p95 5 to 6 ms, hover 7 ms, RSS about 300 to 430 MB). Ponytail rule: a plugin only because it removes real code. Revisit if the pinned plugin breaks or costs a budget. Details: `specs/features/spring-language-server.md`. | Claude (P2 Task 0), user can overturn | Decided, built in P2 Task 3. |
| D15 | Spring Boot run (`<leader>rs`) starts the `@SpringBootApplication` main class with plain `java -cp <jdt.ls classpath>` on the project JDK (`nv4j.jdk`), after jdt.ls's refresh + build, not `mvn spring-boot:run`; the build tool (Maven first, then Gradle `bootRun`) is the fallback without jdt.ls and an opt-in (`<leader>rS`, `vim.g.nv4j_run_tool`) for projects that need the plugin's `<configuration>` or pom profiles. Stop kills the whole process tree. | Task 2 trials | Built: `nvim/lua/nv4j/run.lua`, `41_run`. Measured 2.5 s against 5 to 7 s to "Started", and `spring-boot:run` hung on plugin resolution over the network (`specs/features/run.md`). |

## Budgets and final P1 results

Budgets are confirmed (they were provisional until the Task 5 re-baseline). Measured on the Spring Boot fixture `tests/fixtures/demo`; details, per-case tables and trial logs in the linked feature specs. Result columns are the ranges over the consecutive full runs recorded there.

| Metric | Budget | Result | Check |
|--------|--------|--------|-------|
| Warm completion round trip p95, per case | <= 150 ms | worst case 38 to 45 ms (baseline 43 ms) | `10_completion_latency` |
| Menu list (blink sort) p95, per case | <= 150 ms | worst about 40 ms | `10_completion_latency` |
| First completion, 1.0 s after jdt.ls ServiceReady | <= 400 ms | 51 to 55 ms (baseline 740 to 827 ms) | `10_completion_latency` |
| Expected item rank in the order the user sees | top 5 plus a relative rule | `@` `RestController` 4 (jdt.ls order 6), `http.` `authorizeHttpRequests` 2 (baseline 19), `repository.` `save` 1 (baseline 42) | `11_completion_ranking` |
| Edit to diagnostics in `vim.diagnostic` | <= 3 s | errors 462 to 476 ms, unused 674 to 684 ms, fix clears 471 to 511 ms, burst settles 633 to 683 ms, Java 25 file clean 490 to 521 ms | `30_diagnostics` |
| Unused imports shown while the file has errors | <= 3 s | 473 to 506 ms; pass cost on 3000 lines p95 1.6 to 1.9 ms over 100 passes, 5 runs (budget 5 ms) | `30_diagnostics` |
| Accept a completion with its import | <= 1.5 s | first `List` 685 to 746 ms, second type 379 to 439 ms | `31_imports` |
| One code action round trip | <= 1 s | 9 to 120 ms | `32_code_actions` |
| jdt.ls open to ready | none (info) | about 6.1 to 6.4 s warm workspace, about 15 s first import | `01_jdtls_ready`, `10_completion_latency` |
| Java 25 / Java 21 project correctness, JDK discovery | zero errors, right runtime | pass with `JAVA_HOME` unset and JDK 21 first on `PATH` | `20_java25` |

Last full `tests/run.sh` runs (final review, two consecutive): 135 PASS, 0 FAIL, 0 SKIP each, a `DONE` line for every check (00: 11, 01: 2, 10: 17, 11: 26, 12: 7, 20: 10, 30: 24, 31: 10, 32: 28). Logs `/tmp/nv4j/logs/test-20261020-225853.log`, `-230137.log`. Earlier (Task 7): 129 PASS, log `test-20261020-223125.log`.

Feature specs: [`specs/002-p1-completion.md`](002-p1-completion.md) (budget, baseline, trials), [`specs/features/completion-ranking.md`](features/completion-ranking.md), [`specs/features/diagnostics-imports-actions.md`](features/diagnostics-imports-actions.md), [`specs/features/jdk-java25.md`](features/jdk-java25.md).

Open follow-ups from P1 (carried to the P3 plan): async import apply (removes the up to 0.8 s accept wait), frecency vs project ranking, cosmetic gaps versus IntelliJ (see README, Known limitations).

See `003-lessons-and-method.md` for how the reference repos are used, what P1 taught us, and the improved working method.

## Reference: IntelliJ Community source

Repo: https://github.com/jetbrains/intellij-community (Apache 2.0). It is the reference for how IntelliJ implements Java and Spring-relevant features. Use: check, adapt, enhance. Not a port and not a full reverse engineering.

- Per feature, read how IntelliJ does it (completion ranking and sorting, inspections, intentions, refactorings, run configurations, test runner, debugger behaviour). Record the finding in `specs/features/<feature>.md`.
- Adapt the idea to what Neovim, JDTLS, the Spring language server and DAP can do. Where IntelliJ is better than those tools, enhance with config, sorting or small Lua, within the performance budget.
- Each feature spec holds: IntelliJ behaviour (with source path in the repo), priority P1-P5, Neovim approach, pass/fail test.
- Spring features in IntelliJ are mostly in the closed-source Ultimate plugin, not in Community. For Spring the reference is the IntelliJ user-visible behaviour and the Spring Tools language server, not Community code. This is a known limit.
- Local copy: shallow sparse clone at `~/.cache/nv4j/intellij-community`. Not committed to this repo, read only.

### More reference repos

| Repo | Use | Priority area |
|------|-----|---------------|
| https://github.com/eclipse-jdt/eclipse.jdt.core | JDT core: `CompletionEngine`, relevance computation, search/index, compiler behavior. This is what JDTLS runs on, so completion ranking and code-assist behavior can be tuned or extended against its real source. | P1 |
| https://github.com/spring-projects/spring-tools | Spring Tools (STS) source: the Spring Boot language server (annotation, `application.properties`/`yml`, bean and request-mapping support), launch and Boot Dash behavior. Reference and likely the Spring server we install. | P2, P4 |

- Same method as IntelliJ: check, adapt, enhance. Local shallow sparse clones in `~/.cache/nv4j/`, read only, not committed.
- License: both are EPL-2.0 (IntelliJ Community is Apache-2.0). Copying code into this repo is allowed only with the original license header and a note in the feature spec naming the source path. Prefer reusing the tool as a dependency (Mason or release jar) over copying source.

## Layout

```
Nv4J/
  README.md         user guide: capabilities, install, keys, limits
  specs/            source of truth (this folder)
  nvim/             the Neovim config (init.lua, lua/, lazyvim.json)
  tests/
    fixtures/       demo/ (Spring Boot Maven project) and planted/ (broken sources, in-memory only)
    run.sh          runs all checks headlessly
    checks/         one script per measurable requirement
    lib/            headless helpers (lsp, completion, edit, jdk_home)
```

## How to run

`~/.config/nv4j` is a symlink to `Nv4J/nvim`. With `NVIM_APPNAME=nv4j`, Neovim reads that directory instead of `~/.config/nvim`.

```sh
ln -s "$PWD/nvim" ~/.config/nv4j   # once, from <repo> (the Nv4J folder)
NVIM_APPNAME=nv4j nvim                                                  # use it
nvim                                                                    # old config, unchanged
```

Rollback: stop using `NVIM_APPNAME=nv4j` (plain `nvim` is the old config), delete the symlink. The `nv4j` shell alias is `alias nv4j="NVIM_APPNAME=nv4j nvim"`. Requirements and first-start steps: `README.md`.

Side effect to know: data, state and cache go to `~/.local/share/nv4j`, `~/.local/state/nv4j`, `~/.cache/nv4j`. Plugins and Mason tools install again there. They do not share the old config's installs.

## How to test

Principle: build, measure, compare against the spec number, iterate.

- `tests/run.sh` starts `nvim --headless` with `NVIM_APPNAME=nv4j` against `tests/fixtures/`.
- Each check opens a fixture file, waits for the language server, then calls LSP requests directly (completion, diagnostics, code actions) and asserts on results.
- Check types:
  - Latency: completion p50/p95 against the budget set in the P1 spec.
  - Ranking: expected item appears in the top N.
  - Diagnostics: planted errors are reported, valid Java 25 code reports none.
  - Spring: annotation, attribute and property-key completion, including a custom annotation. (P2, not built yet.)
  - Run, debug, test (P2/P3, not built yet): start the fixture app or one test through DAP and the jdtls test bundles, assert a breakpoint hit or a pass result.
- Not testable here, done by hand by the user: how typing and UI plugins feel.

## Logs and temp files

Logs and test output under `/tmp/nv4j/`; the jdt.ls workspace and config copy under `~/.cache/nv4j/` (`stdpath("cache")`, follows `NVIM_APPNAME`):

| Path | Content |
|------|---------|
| `/tmp/nv4j/logs/test-<timestamp>.log` | output of `tests/run.sh` |
| `/tmp/nv4j/logs/lsp.log` | Neovim LSP client log |
| `~/.cache/nv4j/jdtls-data/<project>-<hash>/.metadata/.log` | JDTLS server log (inside the workspace) |
| `/tmp/nv4j/logs/latency.jsonl` | timing samples of the last `tests/run.sh` (previous run: `latency.prev.jsonl`, rotated by `run.sh`) |
| `~/.cache/nv4j/jdtls-data/`, `~/.cache/nv4j/jdtls-config/` | JDTLS workspace data and writable config copy (persistent: losing them forces a full re-import) |

`/tmp` is cleared by macOS on reboot and after a few days. Nothing under `/tmp/nv4j` is needed after a run finishes; the jdt.ls dirs are therefore not there.

## Open items

- Spring language server: decided (D14, Mason `vscode-spring-boot-tools` through `spring-boot.nvim`); wiring is P2 Task 3, check `50_spring_ls`.
- Run and debug (P2): the "m2e.launchconfig.classpathProvider" warning is a race in JDT launching hit by nvim-jdtls's parallel classpath requests (root cause and three more debug blockers in `specs/features/debug-run.md`); fixed in P2 Task 1, check `40_debug`.
