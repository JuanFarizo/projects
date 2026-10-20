# 001 - Architecture and workflow

Status: draft. Source of truth for Nv4J. Later specs must not contradict this file.

## Goal

A fast, lightweight Neovim setup for Java and Spring development. IntelliJ is the feature reference. Each feature gets a priority (P1 highest, P5 lowest) and a measurable pass/fail criterion.

## Decisions

| # | Decision | Owner |
|---|----------|-------|
| D1 | Start from the existing LazyVim-based config, keep only what Java/Spring needs. No rewrite from scratch. | Claude (user agreed to approach) |
| D2 | Maven is first-class. Gradle is supported but second. | User |
| D3 | The existing `~/.config/nvim` is never modified. | User |
| D4 | Config lives in this repo under `nvim/` and runs as a separate Neovim app named `nv4j`. | User |
| D5 | Logs and temporary test output live under `/tmp/nv4j/`. | User |
| D6 | Priorities: P1 completion/diagnostics/imports/code actions/Java 25; P2 Spring awareness, run, debug; P3 tests, scaffolding, refactors; P4 Gradle, Spring navigation, JPA checks; P5 everything else. | User |

## Reference: IntelliJ Community source

Repo: https://github.com/jetbrains/intellij-community (Apache 2.0). It is the reference for how IntelliJ implements Java and Spring-relevant features. Use: check, adapt, enhance. Not a port and not a full reverse engineering.

- Per feature, read how IntelliJ does it (completion ranking and sorting, inspections, intentions, refactorings, run configurations, test runner, debugger behaviour). Record the finding in `specs/features/<feature>.md`.
- Adapt the idea to what Neovim, JDTLS, the Spring language server and DAP can do. Where IntelliJ is better than those tools, enhance with config, sorting or small Lua, within the performance budget.
- Each feature spec holds: IntelliJ behaviour (with source path in the repo), priority P1-P5, Neovim approach, pass/fail test.
- Spring features in IntelliJ are mostly in the closed-source Ultimate plugin, not in Community. For Spring the reference is the IntelliJ user-visible behaviour and the Spring Tools language server, not Community code. This is a known limit.
- Local copy: shallow sparse clone at `~/.cache/nv4j/intellij-community`. Not committed to this repo, read only.

## Layout

```
Nv4J/
  specs/            source of truth (this folder)
  nvim/             the Neovim config (init.lua, lua/, lazyvim.json)
  tests/
    fixtures/       sample Spring Boot Maven project used by tests
    run.sh          runs all checks headlessly
    checks/         one script per measurable requirement
```

## How to run

`~/.config/nv4j` is a symlink to `Nv4J/nvim`. With `NVIM_APPNAME=nv4j`, Neovim reads that directory instead of `~/.config/nvim`.

```sh
ln -s /Users/juan.farizo/Documents/projects/Nv4J/nvim ~/.config/nv4j   # once
NVIM_APPNAME=nv4j nvim                                                  # use it
nvim                                                                    # old config, unchanged
```

Rollback: stop using `NVIM_APPNAME=nv4j`, delete the symlink.

Side effect to know: data, state and cache go to `~/.local/share/nv4j`, `~/.local/state/nv4j`, `~/.cache/nv4j`. Plugins and Mason tools install again there. They do not share the old config's installs.

## How to test

Principle: build, measure, compare against the spec number, iterate.

- `tests/run.sh` starts `nvim --headless` with `NVIM_APPNAME=nv4j` against `tests/fixtures/`.
- Each check opens a fixture file, waits for the language server, then calls LSP requests directly (completion, diagnostics, code actions) and asserts on results.
- Check types:
  - Latency: completion p50/p95 against the budget set in the P1 spec.
  - Ranking: expected item appears in the top N.
  - Diagnostics: planted errors are reported, valid Java 25 code reports none.
  - Spring: annotation, attribute and property-key completion, including a custom annotation.
  - Run, debug, test: start the fixture app or one test through DAP and the jdtls test bundles, assert a breakpoint hit or a pass result.
- Not testable here, done by hand by the user: how typing and UI plugins feel.

## Logs and temp files

All under `/tmp/nv4j/`:

| Path | Content |
|------|---------|
| `/tmp/nv4j/logs/test-<timestamp>.log` | output of `tests/run.sh` |
| `/tmp/nv4j/logs/lsp.log` | Neovim LSP client log |
| `/tmp/nv4j/logs/jdtls.log` | JDTLS server log |
| `/tmp/nv4j/logs/latency.jsonl` | completion timing samples |
| `/tmp/nv4j/jdtls-data/` | JDTLS workspace data |

`/tmp` is cleared by macOS from time to time. Nothing there is needed after a run finishes.

## Open items

- Spring language server choice and install method (Mason or manual). To be decided in the P2 spec.
- Latency budgets (numbers) for P1. To be set after the first baseline measurement of the current config.
