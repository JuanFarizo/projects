# Feature: saved run defaults in `.nv4j`

Priority: P2 leftover (saved run configurations). Status: built. Decision: D27 in `specs/001-architecture.md`. Check: `tests/checks/66_settings.lua` (13 cases). `41_run` still covers an explicit `profile` / `env` / `vm_args` on the call.

## What it does

One default per project, in the `.nv4j` file that is already the project marker (D25). Empty file: marker only, run unchanged. Optional JSON:

```json
{
  "run": {
    "profile": "dev",
    "env": { "SERVER_PORT": "0" },
    "vm_args": ["-Xmx512m"]
  }
}
```

`<leader>rs` / `<leader>rd` use those fields when the call omits them. `<leader>rp` still asks for a profile (this run only) and does not write the file. Lua `opts` win. Change the default: edit `.nv4j`.

`:Nv4jMark` writes an empty `.nv4j` in the current working directory (the folder Neovim was opened at, not the current file's folder). Refuses `$HOME` and above; does not overwrite.

## Variables (2026-11-23)

Strings that come from the file (`vm_args` items, `env` values) are expanded when `apply()` reads them. Syntax decided from IntelliJ: `JavaParametersUtil.configureConfiguration` (lines 60-79) runs the VM parameters through `ProgramParametersUtil.expandPath` (macros `$PROJECT_DIR$`, `$MODULE_DIR$`, ...) and then replaces every `$KEY$` with the value of that key in the run's env. Nv4J takes that form and adds the shell form:

- `$NAME$` and `${NAME}`, NAME = `[A-Za-z_][A-Za-z0-9_]*`.
- Built in: `PROJECT_DIR` and `MODULE_DIR` (both the project root), `USER_HOME` (`$HOME`).
- Otherwise: in `vm_args` the run's env table first (the file's `env` plus the caller's), then the process environment; in `env` values the process environment (no env-to-env references, so no cycles).
- Unknown names stay literal and warn once per file and name (title Nv4J). Text that is not a name (`${spring.profiles.active}`, `$$`, `$5`) is left alone without a warning, so Spring placeholders pass through.
- Values passed by the caller in Lua `opts` are not expanded (they win and are used as given).

Check `112_run_vars` (8 cases, pure), controls `tests/lib/control_112.sh` (6 patches).

## Why this and not named configs

The user runs almost always with the same default. A picker of named configs is a second store and more ways to break. `rp` covers the exception.

## Mechanism

`nvim/lua/nv4j/settings.lua`: `load(root)` reads JSON (or `{}`), `apply(opts, root)` fills omitted `profile` / `env` / `vm_args`, `mark(dir)` writes the empty marker. `run.spring_boot` calls `apply` once it has a project root. No cache: the file is small; an edit is seen on the next `rs` without a restart. (Adding or removing the file as a **root marker** still needs a restart, D25.)

Bad JSON: one WARN (title Nv4J), apply empty, file still a marker. Unknown keys ignored.

## Negative control

n66a: `spring_boot` does not call `apply` (the `opts = require("nv4j.settings").apply(...)` line removed for one run, reverted) -> `66_settings.run_default` FAIL (cmd has no `-Dspring-boot.run.profiles=dev`). Log `/tmp/nv4j/logs/test-20261030-n66a.log`.
