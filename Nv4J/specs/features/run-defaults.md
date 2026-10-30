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

## Why this and not named configs

The user runs almost always with the same default. A picker of named configs is a second store and more ways to break. `rp` covers the exception.

## Mechanism

`nvim/lua/nv4j/settings.lua`: `load(root)` reads JSON (or `{}`), `apply(opts, root)` fills omitted `profile` / `env` / `vm_args`, `mark(dir)` writes the empty marker. `run.spring_boot` calls `apply` once it has a project root. No cache: the file is small; an edit is seen on the next `rs` without a restart. (Adding or removing the file as a **root marker** still needs a restart, D25.)

Bad JSON: one WARN (title Nv4J), apply empty, file still a marker. Unknown keys ignored.

## Negative control

n66a: `spring_boot` does not call `apply` (the `opts = require("nv4j.settings").apply(...)` line removed for one run, reverted) -> `66_settings.run_default` FAIL (cmd has no `-Dspring-boot.run.profiles=dev`). Log `/tmp/nv4j/logs/test-20261030-n66a.log`.
