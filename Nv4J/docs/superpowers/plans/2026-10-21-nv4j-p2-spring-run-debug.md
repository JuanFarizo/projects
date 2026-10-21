# Nv4J P2: Run, Debug and Spring Awareness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run and debug a Spring Boot app from Neovim (profiles, env, breakpoints that hit), and Spring awareness: `application.properties`/`yml` key completion and hover, `@Value`/`@Profile` completion, beans and request mappings navigation, all inside the P1 budgets.

**Architecture:** Fix the jdt.ls debug classpath first (nothing in P2 works on a broken debug path). Run/debug through nvim-dap and the java-debug bundle already installed, with Spring Boot launch helpers in `nvim/lua/nv4j/`. Spring awareness comes from the Spring Boot language server (VMware `vscode-spring-boot` package, available in Mason as `vscode-spring-boot-tools`), run as a second LSP client next to jdt.ls and wired to jdt.ls through the extension bundles the Spring server needs. Every feature is proven by a headless check with a numeric budget.

**Tech Stack:** Neovim 0.12, nvim-jdtls, nvim-dap (+ dap-ui from LazyVim), java-debug-adapter, Spring Boot language server (Mason), blink.cmp, Maven, Corretto 25, Lua, sh.

**Spec:** `specs/001-architecture.md` (decisions D1-D13, budgets), `specs/003-lessons-and-method.md` (method rules). This plan adds decisions D14+ to 001 and a P2 spec `specs/004-p2-spring-run-debug.md`.

## Global Constraints

- `~/.config/nvim` is never modified. Config lives in `Nv4J/nvim/`, run as `NVIM_APPNAME=nv4j`.
- Maven first-class (about 80% of projects), Gradle second. Nothing hardcoded to one JDK (SDKMAN). Use `nv4j.jdk`.
- Logs and test output under `/tmp/nv4j/`. Persistent caches under `~/.cache/nv4j/`. Spring LS install under Mason (`~/.local/share/nv4j/mason`).
- Git: commit and push on `main` as the user, no Co-Authored-By or "Generated with" line. Stage explicit paths only (git root is `~/Documents/projects`, never `git add -A`). Check `git status` before and after each agent.
- P1 must not regress: `tests/run.sh` stays at 0 FAIL, and these P1 budgets still hold with the Spring LS running: completion warm p95 <= 150 ms, cold first <= 400 ms, `@` gives RestController in top 5, diagnostics <= 3 s.
- P2 budgets (set now, do not weaken; measured on the fixture): Spring LS ready after jdt.ls ready <= 10 s (info on first install), `application.properties` completion warm p95 <= 150 ms, first <= 400 ms, hover <= 500 ms, breakpoint hit <= 20 s from start of launch, extra RSS of the Spring LS <= 1 GB (info + hard limit 1.5 GB).
- References (read only, `~/.cache/nv4j/`): `spring-tools` (EPL-2.0, clone at Task 0), `eclipse.jdt.ls`, `intellij-community`. Copy no EPL code without header and a note in the feature spec. Prefer the Mason package.
- Per-feature loop and rules: `specs/003-lessons-and-method.md` section 3. Write the failing check first. Log every trial, also failed ones, in the feature spec.
- Each task ends with: feature spec updated, README Capabilities/Not yet updated for that feature, `tests/run.sh` full run recorded with its `DONE` lines.

## Review Focus

Failure modes the spec implies but no task's tests would otherwise cover (each gets a test in the owning task):

1. A project that is NOT Spring (plain Maven, loose `.java` file): the Spring LS must not start or must stay silent and cost nothing. Owner: Task 3.
2. Switching JDK with SDKMAN (`.sdkmanrc` 21 vs 25): debug and the Spring LS must follow the project JDK, not PATH. Owner: Tasks 1 and 3.
3. `application-dev.yml` and profile files, and a properties file with a syntax error: completion keeps working, no crash. Owner: Task 4.
4. Port already in use / app crashes on start: run reports it in a visible message, no hung terminal state. Owner: Task 2.
5. Stopping the debug session leaves no orphan `java` process. Owner: Task 1.

---

### Task 0: Research, fixture and failing baselines

**Files:**
- Create: `specs/004-p2-spring-run-debug.md`, `specs/features/debug-run.md`, `specs/features/spring-language-server.md`
- Modify: `tests/fixtures/demo/` (add `src/main/resources/application.properties`, `application-dev.yml`, a `@Value`, a `@ConfigurationProperties` class, a `@Profile` bean, a `@GetMapping` controller method; keep it compiling), `tests/run.sh` only if a new env var is needed
- Create: `tests/checks/40_debug.lua`, `tests/checks/50_spring_ls.lua` (stubs that FAIL for the right reason now)
- Clone: `spring-tools` sparse into `~/.cache/nv4j/spring-tools` (done once, pin the commit in the specs)

**Interfaces:**
- Consumes: P1 harness (`tests/lib/lsp.lua`, `tests/run.sh` DONE-line contract).
- Produces: spec files with the decisions below filled in, fixture that exercises Boot features, two failing checks with budgets from Global Constraints.

- [ ] **Step 1: Reproduce the debug classpath warning.** Start the fixture, run `:JdtUpdateDebugConfig` or the LazyVim main-class debug config, capture the exact `m2e.launchconfig.classpathProvider` error and the jdt.ls log lines. Record in `debug-run.md`.
- [ ] **Step 2: Find the cause.** Read how `java-debug` resolves the classpath (`vscode.java.resolveClasspath` command in the installed bundle and jdt.ls `workspace/executeCommand`) and which bundle or m2e extension is missing or mis-ordered in `init_options.bundles`. Candidates to test one at a time: bundle order, missing `java-test`/debug jars, project not yet built, Corretto 25 vs m2e. Record each trial.
- [ ] **Step 3: Decide the Spring LS wiring.** Read `spring-tools` (`headless-services/spring-boot-language-server`, `vscode-extensions/vscode-spring-boot/package.json`, its jdt.ls extension jars and the `sts/*` commands it needs from the client). Check the Mason package `vscode-spring-boot-tools` layout. Decide between: (a) the `JavaHello/spring-boot.nvim` plugin, (b) own thin Lua in `nvim/lua/nv4j/spring.lua`. Pick the smaller one that meets the budgets; ponytail rule: a plugin only if it removes real code. Write the decision as D14 in `001`.
- [ ] **Step 4: Extend the fixture and write the failing checks.** `40_debug` asserts: attach/launch gives a stopped event at a breakpoint in the fixture within 20 s (FAIL now). `50_spring_ls` asserts: a Spring LS client attaches, `application.properties` completes `server.po` to `server.port` within budget, hover on `server.port` returns text (FAIL now). Both print `DONE <check> <pass> <fail>`.
- [ ] **Step 5: Commit** specs, fixture and checks. Run `tests/run.sh`: P1 checks still pass, the two new checks fail with the expected reason. Record the run log path in `004`.

### Task 1: Debug that works (P2, blocker)

**Files:**
- Modify: `nvim/lua/plugins/java.lua` (bundles, debug setup), `nvim/lua/plugins/dap.lua` (create if LazyVim's config needs overrides)
- Create: `nvim/lua/nv4j/debug.lua` if more than a few lines are needed
- Test: `tests/checks/40_debug.lua`

**Interfaces:**
- Consumes: Task 0 findings and `40_debug`.
- Produces: `<leader>dc` / `<leader>db` / existing LazyVim DAP keys work on a Java main class and on a JUnit test; `require("nv4j.debug").main_class_config(root)` only if a helper is needed (name it in the spec).

- [ ] **Step 1: Implement the smallest fix** found in Task 0 (bundle list or ordering, classpath resolution, build-before-debug). The project JDK for the debuggee follows `nv4j.jdk` (`.sdkmanrc`, pom), not PATH.
- [ ] **Step 2: Make `40_debug` pass:** breakpoint at a fixture line, launch main class, wait for `stopped`, read the top frame (file, line) and a variable value, continue to termination. Budget: stopped event within 20 s of launch.
- [ ] **Step 3: Test debugging a JUnit test method** (`java-test` bundle) the same way. Add the case to `40_debug`.
- [ ] **Step 4: Orphan check (Review Focus 5).** After terminate/disconnect, assert no `java` child of the nvim process remains.
- [ ] **Step 5: JDK check (Review Focus 2).** Run with a hostile PATH (JDK 21 first) on the Java 25 fixture: the debuggee runs on 25. Assert the `java.version` seen by the debuggee.
- [ ] **Step 6: Profile, log trials in `debug-run.md`, update README, commit.**

### Task 2: Run Spring Boot (P2)

**Files:**
- Create: `nvim/lua/nv4j/run.lua`
- Modify: `nvim/lua/config/keymaps.lua`, `nvim/lua/plugins/java.lua` (wire only), `README.md`
- Test: `tests/checks/41_run.lua`

**Interfaces:**
- Consumes: Task 1 (debug launch), `nv4j.jdk`, `nv4j.buildfile`.
- Produces: `require("nv4j.run").spring_boot({ debug = boolean, profile = string|nil, env = table|nil })` and keys `<leader>rs` (run), `<leader>rd` (run with debug), `<leader>rp` (prompt profile). Replaces the P1 plain `<leader>rj` for Boot projects, keeps `rj` for plain main classes.

- [ ] **Step 1: Write `41_run` failing:** `rs` on the fixture starts the app (Maven `spring-boot:run` or the main class with the classpath, whichever Task 0 shows is faster and JDK-correct), reads `Started ... in` from the terminal buffer within a budget (info), then stops cleanly. Fail now.
- [ ] **Step 2: Implement `run.lua`:** detect Boot (pom has `spring-boot` parent/plugin or Gradle plugin), build the command (Maven first, Gradle second), pass `-Dspring.profiles.active`, env, and `JAVA_HOME` from `nv4j.jdk`. Output goes to a terminal split with `q` to close and a stop key.
- [ ] **Step 3: Port in use and crash (Review Focus 4).** Start twice: the second reports "port in use" (or the Boot failure analysis line) as a notification and leaves no hung state. Add to `41_run`.
- [ ] **Step 4: Test, profile, update README, commit.**

### Task 3: Spring Boot language server (P2)

**Files:**
- Create: `nvim/lua/nv4j/spring.lua` (or plugin spec, per D14), `nvim/lua/plugins/spring.lua`
- Modify: `nvim/lua/plugins/java.lua` (jdt.ls extension bundles for the Spring LS), `nvim/lua/nv4j/paths.lua` if a new dir is needed
- Test: `tests/checks/50_spring_ls.lua`

**Interfaces:**
- Consumes: Task 0 decision D14, Mason package install pattern from P1 (stale link cleanup).
- Produces: `require("nv4j.spring").setup()`; a Spring LS client named `spring-boot` attached to Java and properties/yml buffers of Boot projects only; `vim.g.nv4j_spring = false` disables it.

- [ ] **Step 1: Install through Mason** (`vscode-spring-boot-tools`) with the P1 bootstrap pattern. Resolve the server jar and the jdt.ls extension jars inside the package; no hardcoded versions.
- [ ] **Step 2: Start it only for Boot projects (Review Focus 1).** Gate on the pom/Gradle containing Spring Boot. A plain Maven project and a loose `.java` file must show no `spring-boot` client and no extra process. Test with a second fixture (the P1 release-21 project is fine) in `50_spring_ls`.
- [ ] **Step 3: JDK (Review Focus 2).** The server runs on a JDK >= 21 found by `nv4j.jdk`, never PATH. Test with the hostile PATH setup.
- [ ] **Step 4: Make `50_spring_ls` pass:** client attaches, bundles loaded into jdt.ls, ready within budget, RSS measured and logged against the 1 GB budget.
- [ ] **Step 5: P1 regression.** Full `tests/run.sh`: all P1 budgets hold with the second client running. If completion latency regresses, fix before moving on (client capabilities, `completion` disabled for Java buffers on the Spring client, as needed).
- [ ] **Step 6: Log trials, update `004` and README, commit.**

### Task 4: Spring completion, hover and navigation (P2/P4)

**Files:**
- Modify: `nvim/lua/plugins/blink.lua` (sources/ordering for the Spring client), `nvim/lua/nv4j/completion.lua` only if Spring items need the P1 sorter
- Create: `nvim/lua/nv4j/spring_nav.lua` only if keys beyond LSP defaults are needed
- Test: `tests/checks/51_spring_completion.lua`, `tests/checks/52_spring_nav.lua`

**Interfaces:**
- Consumes: Task 3 client.
- Produces: keys `<leader>ss` (Spring symbols: beans and request mappings via `workspace/symbol` on the Spring client) and Spring items inside blink.

- [ ] **Step 1: Failing checks first.** `51`: `server.po` -> `server.port` (properties and yml), `@Value("${` lists known keys, `@Profile("` lists profiles found in `application-*.yml`, `spring.jpa.hibernate.ddl` completes. Ranking: expected item top 3, latency per Global Constraints. `52`: hover on a property key returns docs; go-to-definition from `@Value("${server.port}")` reaches the property; request mappings listed with their paths (`/people`).
- [ ] **Step 2: Implement** the blink wiring (Spring LS items follow the P1 rules: no flood, warm p95 <= 150 ms). Trim noisy Spring items with the same trial table as P1 if the lists flood.
- [ ] **Step 3: Broken files (Review Focus 3).** Properties file with a syntax error and a YAML with bad indent: completion in the next valid line still works, no LSP crash (client alive after).
- [ ] **Step 4: `@` regression.** `@` still gives RestController in top 5 with the Spring client attached.
- [ ] **Step 5: Profile, log trials, README, commit.**

### Task 5: Docs, final run and whole-branch review

**Files:**
- Modify: `README.md` (Capabilities P2, Not yet, keymaps, install notes for Mason package, Known limitations), `specs/001-architecture.md` (status, decisions D14+, budgets table, open items), `specs/003-lessons-and-method.md` (new lessons, method changes), memory file `nv4j-project.md` if state changed

- [ ] **Step 1: Full `tests/run.sh` three times;** record numbers in `001` and the README rows with check names. Every check prints its `DONE` line.
- [ ] **Step 2: README re-read against the last run:** every number and key matches. Capabilities table for P2 (debug, run, Spring LS, completion, nav), Not yet updated (P3, P4, P5), Known limitations.
- [ ] **Step 3: Final whole-branch review** on the most capable model, one fix wave, push `main`.
