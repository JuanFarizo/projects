# Nv4J: pending work

One list of what is open. Update it when you finish or add something. Newest decisions are in `specs/001-architecture.md`; how to resume is in `docs/HANDOFF-p3.md`. Last update: 2026-11-02.

## Waiting for your decision

| Item | What to decide | Cost if wrong |
|------|----------------|---------------|
| D23 move via `workspace/willRenameFiles` | Keep it, or go back to the code action | Move class may behave differently from IntelliJ in edge cases |
| Command or key that creates `.nv4j` | Build it (for example `:Nv4jInit` in the project's top folder), or keep `touch .nv4j` | None |

## Open work

- [x] jdt.ls flakes investigated 2026-11-02 (details in `docs/HANDOFF-p3.md`, Flakes). B fixed twice (`rename_class` revalidates every open Java file, case `rename_class_revalidates`; the cold first rename that left dependents on the old name is retried once and warned, cases `rename_class_cold_*`). A (`INVALID_SERVER_JSON`) narrowed: not Neovim's parser, the message is jdt.ls's `sts.java.classpath` data over 64 KB; open: capture the raw bytes on error. C (stall) not found: old log gone, load was 11 to 49; `run.sh` now logs the load before each check.
- [ ] `two_boot_index` flake (about 1 in 4 at load 4-5): 8 instrumented runs were all green, cause not captured; two real defects fixed (`file:/` projectUri routing, retry of a rejected `addClasspathListener`, see spring-language-server.md s2). If it fails again, look at the `addClasspathListener rejected` lines in `/tmp/nv4j/logs/spring-route.log` and keep `spring-boot-ls.log`.
- [ ] Flake A: `INVALID_SERVER_JSON`: capture the raw bytes when `on_error` fires (a debug-only hook that keeps the last 128 KB of server stdout).
- [ ] Flake C: stall: look at the new `load: ..., java processes` lines in `tests/run.sh` output next time a check is slow.
- [ ] Linux: run Nv4J on Ubuntu once. `<A-/>` comment, `<A-Left>` / `<A-Right>`, `<A-]>` / `<A-[>` were tested only through the key map, not in a Linux terminal.
- [ ] AI agents: Claude and Cursor were never run for real; check 65 stubs `ClaudeCodeOpen`.
- [ ] First start with Mason on a new machine: prettier, marksman, markdownlint-cli2 and markdown-toc install (needs Node).
- [ ] Cap minors: a buffer the loose-file cap refused needs `:e` after the running jdt.ls stops; the `start_or_attach` wrap is lost if the jdtls module is reloaded; `warn_loose` compares raw path strings.
- [ ] Tests not covered: TestNG, JUnit 4, multi-module and Gradle test runs; the Mason `is_installing` guard; the warning paths of the Spring route log.
- [ ] Case-folding branch of the project path match runs only on a case-sensitive file system (this Mac is case-insensitive).

Settled, no longer asked: the 5 s ceiling for change signature on a method with implementations stays (it only sets how long the check waits); smear-cursor and mini.animate are not ported (user ruling D26).

## Later (priorities from the plan)

- [ ] P4: Gradle as a first-class build tool, JPA, TestNG polish.
- [ ] JDT index save (only if a start on the second day is slow).
- [ ] `-Xms` / `-Xmx` stay out (your rule).

## Done recently

- 2026-11-02: `61_scaffold` `compiles_all` / `edit_template` flake fixed: the Spring LS held the new file's template twice (nvim sends a pending didChange to a client that attached after the edit); `fill_buf` flushes pending changes, case `edit_template_sync` with control. The same race can hit any edit made within 150 ms before a second LS attaches (not fixed outside the scaffold).
- 2026-11-02: cold first class rename no longer leaves dependents on the old name silently: references compared with the edit, one retry, WARN if still missing (check 62 `rename_class_cold_*`). Docs name jdt.ls 1.63.0 (installed plugin 1.63.0.202610191322).
- 2026-11-02: Spring LS with two projects: checked with a real run, it does index the second project (request mapping, bean, configuration key) although it gets only the first folder; no fix needed. Check 50 `two_boot_index`. Memory warning timer path smoke-tested with a real jdt.ls: check 64 `memwatch_live`.
- 2026-11-02: jdt.ls memory: no budget and no limit; a warning once a jdt.ls reaches 2 GB RSS (`vim.g.nv4j_jdtls_warn_mb`, `nv4j/memwatch.lua`, check 64 `memwatch_unit`).
- 2026-11-02: cap on loose-file jdt.ls (`vim.g.nv4j_loose_max`, default 1), two Spring Boot apps in one Neovim, three full runs green (21 checks).
- 2026-10-30: Cmd keys on Mac, Alt keys on Linux (comment, jump, terminal tabs).
- 2026-10-29: dotfiles merge (D26), P3 pushed.
