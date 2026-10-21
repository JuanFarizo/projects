# Nv4J Foundation + P1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A separate `nv4j` Neovim config, a headless test harness, and P1 features (fast, well-ranked completion; correct diagnostics, imports, code actions; Java 25 syntax) measured against numeric budgets.

**Architecture:** Config in `Nv4J/nvim/` copied from `~/.config/nvim` then trimmed to Java/Spring needs. Headless Neovim drives real JDTLS against a fixture Maven project. Each requirement is one check script that prints a number or PASS/FAIL. Iterate on settings until budgets hold.

**Tech Stack:** Neovim 0.12, LazyVim, nvim-jdtls, JDTLS 1.60, blink.cmp, Mason, Maven, Corretto 25, Lua, sh.

**Spec:** `specs/001-architecture.md`. P2-P4 (Spring, tests/scaffold/refactor, Gradle) get separate plans after this one.

## Global Constraints

- `~/.config/nvim` is never modified. Symlink `~/.config/nv4j` -> `Nv4J/nvim` already exists. Alias `nv4j` already in `~/.zshrc`.
- Maven first-class, Gradle second.
- Logs and temp output only under `/tmp/nv4j/` (`logs/`, `jdtls-data/`).
- JDK for JDTLS: Corretto 25 under `~/Library/Java/JavaVirtualMachines`. Never rely on PATH or lazy SDK loading.
- Performance budget (my call, confirm after baseline in Task 3): completion p95 <= 150 ms warm, <= 400 ms cold first request; expected item in top 5.
- IntelliJ Community repo is read-only reference at `~/.cache/nv4j/intellij-community` (shallow sparse clone, not committed).
- Check, adapt, enhance. No port of IntelliJ code.

## Per-feature loop (applies to Tasks 3-6)

Each feature runs this loop in its own fresh subagent, and ends only when the exit criterion holds:

1. **Research:** read the IntelliJ Community source for the behavior, the JDTLS/blink/Spring Tools docs and source for what the Neovim side can do. Write findings to `specs/features/<feature>.md` (sources, how it works, gap, approach). No implementation before this exists.
2. **Implement:** smallest change that targets the gap, config first, small Lua only if config cannot.
3. **Test:** run the feature's checks via `tests/run.sh`.
4. **Profile:** record latency and result counts in `/tmp/nv4j/logs/latency.jsonl`; append the trial (change, numbers) to the feature spec.
5. **Decide:** budget met on three consecutive runs and a reviewer finds no flaw -> done. Otherwise return to step 1 or 2 with what the numbers showed. Keep only changes that improve a number.

Exit criterion: all the feature's checks PASS, budgets hold on three consecutive runs, spec updated with the final design and the trial log.

## Review Focus

- Start with a JDK other than 25 on PATH: JDTLS must still run on 25 and compile the project as 25.
- `~/.config/nv4j` symlink missing or broken: `tests/run.sh` fails with a clear message, not a silent skip.
- JDTLS slow cold start: checks wait with a timeout (120 s) and report timeout as FAIL, never hang.
- Project root with a different `pom.xml` layout (multi-module): root detection picks the parent with modules.
- Huge completion list (`java.util.` , `@`): result count is capped and latency stays in budget.

---

### Task 1: Bootstrap `nvim/` config

**Files:**
- Create: `nvim/` (copy of `~/.config/nvim` minus non-Java plugin specs), `nvim/lua/nv4j/paths.lua`
- Modify: `nvim/lua/plugins/java.lua`, `nvim/lazyvim.json`
- Test: `tests/checks/00_boot.lua`

**Interfaces:**
- Produces: `require("nv4j.paths")` returning `{ root="/tmp/nv4j", logs="/tmp/nv4j/logs", jdtls_data="/tmp/nv4j/jdtls-data" }` and creating them.

- [ ] **Step 1: Write failing check** `tests/checks/00_boot.lua`: assert `vim.env.NVIM_APPNAME == "nv4j"`, `require("nv4j.paths").logs == "/tmp/nv4j/logs"`, `vim.fn.isdirectory("/tmp/nv4j/logs") == 1`, `vim.fn.stdpath("config")` ends with `/nv4j`.
- [ ] **Step 2: Run** `NVIM_APPNAME=nv4j nvim --headless -l tests/checks/00_boot.lua`. Expect FAIL (module missing).
- [ ] **Step 3: Copy** the old config files with `cp -R` (excluding `.git`, `lazy-lock.json` kept), remove plugin specs unrelated to Java/Spring/DAP/completion/UI-essentials (list removed files in the commit message). Implement `nv4j.paths`. Set `vim.lsp.log` path to `<logs>/lsp.log` and JDTLS `-data` to `jdtls_data/<project_name>`.
- [ ] **Step 4: Run** the check, then `nv4j` once interactively headless-sync plugins: `NVIM_APPNAME=nv4j nvim --headless "+Lazy! sync" +qa`. Expect exit 0, check prints PASS.
- [ ] **Step 5: Commit** `feat: bootstrap nv4j config`.

### Task 2: Test harness and fixture project

**Files:**
- Create: `tests/run.sh`, `tests/lib/lsp.lua`, `tests/fixtures/demo/pom.xml`, `tests/fixtures/demo/src/main/java/demo/{App.java,Person.java,Repo.java,MyAnno.java,Modern.java}`
- Test: `tests/checks/01_jdtls_ready.lua`

**Interfaces:**
- Produces in `tests/lib/lsp.lua`:
  - `open(path) -> bufnr`
  - `wait_ready(bufnr, timeout_ms) -> client|nil` (jdtls attached and project imported)
  - `complete(bufnr, line, col) -> { items = table, ms = number }` (synchronous `textDocument/completion`, `ms` wall time)
  - `diagnostics(bufnr) -> table`
  - `report(name, ok, detail)` prints `PASS|FAIL name detail` and appends to `<logs>/test-<timestamp>.log`
- `tests/run.sh` runs every `tests/checks/*.lua`, exits non-zero if any FAIL, fails loudly if the symlink is missing.

- [ ] **Step 1: Write check** `01_jdtls_ready.lua`: open `App.java`, `wait_ready(buf, 120000)` non-nil, `diagnostics(buf)` has 0 errors.
- [ ] **Step 2: Run** `tests/run.sh`. Expect FAIL (no fixture/harness).
- [ ] **Step 3: Implement** the fixture: plain Maven project (no Spring dependency yet), `maven.compiler.release=25`, `Modern.java` uses instance `void main()`, pattern `switch` with `->`, records, `sealed`. `MyAnno.java` is a custom annotation. Implement harness per Interfaces. Root `~/.m2` is used for deps; run `mvn -q -f tests/fixtures/demo/pom.xml compile` once in `run.sh` setup.
- [ ] **Step 4: Run** `tests/run.sh`. Expect `PASS 01_jdtls_ready`.
- [ ] **Step 5: Commit** `feat: add headless test harness and fixture`.

### Task 3: Baseline and IntelliJ reference for P1

**Files:**
- Create: `specs/002-p1-completion.md`, `specs/features/completion-ranking.md`, `tests/checks/10_completion_latency.lua`, `tests/checks/11_completion_ranking.lua`
- Modify: none

**Interfaces:**
- Consumes: `complete`, `report` from Task 2.
- Produces: `latency.jsonl` lines `{"case":string,"ms":number,"count":number}` in `/tmp/nv4j/logs/latency.jsonl`.

- [ ] **Step 1: Clone reference**: `git clone --depth 1 --filter=blob:none --sparse https://github.com/jetbrains/intellij-community ~/.cache/nv4j/intellij-community` then sparse-checkout the Java completion and sorting paths (locate by search for `CompletionSorter`, `PreferByKindWeigher`, `ExpectedTypeWeigher`).
- [ ] **Step 2: Write** `specs/features/completion-ranking.md`: how IntelliJ orders items (expected-type match, locality, kind, recency) with source file paths, and the Neovim mapping (blink `sorts`, `score_offset`, JDTLS settings).
- [ ] **Step 3: Write checks.** Latency cases: `System.` member list, `java.util.` package list, `@` annotation list, `new Person(` constructor, in `Person`/`App`. Ranking cases (each asserts expected label rank): a local variable of the expected type ranks above unrelated keywords; a `Person` field ranks above `java.lang` noise; `MyAnno` appears after typing `@My`.
- [ ] **Step 4: Run baseline** on the copied config. Record p50/p95 and ranks in `specs/002-p1-completion.md` as the baseline table. Confirm or adjust the budgets in Global Constraints with the user.
- [ ] **Step 5: Commit** `docs: p1 baseline and completion ranking spec`.

### Task 4: JDK and Java 25 correctness

**Files:**
- Modify: `nvim/lua/plugins/java.lua`
- Create: `tests/checks/20_java25.lua`

**Interfaces:**
- Produces: resolved JDK path via `require("nv4j.jdk").java25() -> string` (finds Corretto 25 in `~/Library/Java/JavaVirtualMachines`, errors clearly if absent). Settings: `java.configuration.runtimes = {{name="JavaSE-25", path=<java25>, default=true}}`, JDTLS launched with `JAVA_HOME=<java25>`.

- [ ] **Step 1: Write check** `20_java25.lua`: open `Modern.java`, wait ready, assert zero diagnostics of severity error, and assert `workspace/executeCommand` project settings report `JavaSE-25`.
- [ ] **Step 2: Run** with `PATH` where `java` is 21 (`env PATH=<jdk21>/bin:$PATH tests/run.sh`). Expect FAIL.
- [ ] **Step 3: Implement** `nv4j.jdk` and wire into `java.lua` (cmd env + runtimes). Remove dependence on lazy SDK load for JDTLS.
- [ ] **Step 4: Run** under JDK 21 PATH and 25 PATH. Expect PASS both.
- [ ] **Step 5: Commit** `feat: pin jdtls to jdk 25`.

### Task 5: Completion order and lag

**Files:**
- Modify: `nvim/lua/plugins/blink.lua`, `nvim/lua/plugins/java.lua`, `nvim/lua/plugins/lsp.lua`, `nvim/lua/plugins/hlchunk.lua`, `nvim/lua/plugins/diagnostics.lua`
- Test: `tests/checks/10_completion_latency.lua`, `11_completion_ranking.lua` (from Task 3)

**Interfaces:**
- Consumes: baseline table in `specs/002-p1-completion.md`.

- [ ] **Step 1: Run** Task 3 checks. Expect FAIL on at least one budget (baseline).
- [ ] **Step 2: Iterate one change at a time**, re-run, keep the change only if a number improves, log each trial (change, p50, p95, ranks) in `specs/002-p1-completion.md`. Candidate knobs, in order: JDTLS `completion.maxResults`, `completion.filteredTypes`, `guessMethodArguments`, `favoriteStaticMembers`, `importOrder`; blink `sorts` (kind and expected-type aware), `max_items`, `score_offset` for JDTLS, timeouts; codelens and inlay hints off in completion-critical paths; `debounce_text_changes`.
- [ ] **Step 3: Stop** when all latency and ranking checks pass the budget on three consecutive runs.
- [ ] **Step 4: Commit** `perf: meet p1 completion budget`.

### Task 6: Diagnostics, imports, code actions

**Files:**
- Create: `tests/checks/30_diagnostics.lua`, `31_imports.lua`, `32_code_actions.lua`, `tests/fixtures/demo/src/main/java/demo/Broken.java.txt` (planted-error sources copied in by the check)
- Modify: `nvim/lua/plugins/java.lua`

- [ ] **Step 1: Write checks.** Diagnostics: a type error and an unused import are reported within 3 s of the change. Imports: completing `List` auto-adds `import java.util.List;`; organize-imports removes the unused one. Code actions: for an undefined method, a "create method" action is offered; for a missing interface method, "implement methods" is offered.
- [ ] **Step 2: Run.** Expect FAIL where config is missing.
- [ ] **Step 3: Fix** with JDTLS settings (`importOrder`, `completion.importOrder`, save actions) in `java.lua` only.
- [ ] **Step 4: Run** `tests/run.sh`. Expect all PASS.
- [ ] **Step 5: Commit** `feat: p1 diagnostics imports code actions`.

### Task 7: Docs and handoff

**Files:**
- Modify: `specs/001-architecture.md` (mark decisions confirmed, add budget numbers), Create: `README.md`

- [ ] **Step 1: Write** `README.md` (user request: capabilities and how to use). Sections: what Nv4J is and the P1-P5 priorities; **Capabilities** (every shipped feature, with the measured numbers from specs/002 and the checks that prove it, and a clear "not yet" list for P2-P4); **Install / first run** (symlink `~/.config/nv4j`, `nv4j` alias, first-start downloads, requirements: Neovim 0.12+, a JDK 21+ via SDKMAN or system, Maven, ripgrep, tree-sitter CLI); **How to use** (daily workflow for Java/Spring: open a Maven project, completion, imports, code actions, diagnostics, run/debug/test as far as shipped, with the exact keymaps read from the real config and verified, not guessed; how to switch JDK with `sdk use`; `vim.g.nv4j_filtered_types` override; `:CompletionProfile on`); **Configuration** map of `nvim/` files; **Testing** (`tests/run.sh`, `NV4J_CHECKS=<prefix>`, fixture, budgets); **Logs** under `/tmp/nv4j/`; **Troubleshooting** (jdtls not starting, no JDK >= 21, rg missing, stale workspace: `rm -rf /tmp/nv4j/jdtls-data`); **Limitations and known gaps** from the ledger's deferred minors, including the planned async import apply (accept no longer waits up to ~0.8 s for completionItem/resolve; specs/features/diagnostics-imports-actions.md "Planned follow-ups") and the frecency follow-up in specs/002. Plain English, accurate to the code; verify every command and keymap by running it. Each later plan (P2-P4) updates the README capabilities section as part of its last task.
- [ ] **Step 2: Run** `tests/run.sh` end to end. Expect all PASS, log in `/tmp/nv4j/logs/`.
- [ ] **Step 3: Commit** `docs: readme and spec updates`. Next plans: P2 Spring, P3 tests/scaffold/refactor, P4.
