# Health report: `:Nv4JHealth` / `:checkhealth nv4j`

A read-only report of what Nv4J needs on this machine, for a new machine or when something does not start. `:Nv4JHealth` runs `:checkhealth nv4j` (Neovim's own convention: `lua/nv4j/health.lua`, `M.check()`). Code: `nvim/lua/nv4j/health.lua`, command in `nvim/lua/config/keymaps.lua`. Check: `tests/checks/96_health.lua` (12 cases; controls `tests/lib/control_96.sh`). No `<leader>` key.

## Cost

Zero at startup: the module is required only when the command or `:checkhealth` runs (`zero_cost_startup`). The report is stat calls, `executable()` lookups and one SHA-256 of the CFR jar (2 MB). No network, no process, no LSP request or restart (`no_side_effects`).

## What it checks

| Section | Line | Level |
|---------|------|-------|
| Tools | `java`, `mvn`, `rg`, `fd`, `git` on `PATH` | ok / error |
| | `fzf` | info (optional) |
| Mason packages | jdt.ls (`mason/packages/jdtls` with its launcher jar), java-debug bundle, java-test bundle | ok / error |
| | Spring Boot LS (`nv4j.spring`, same helpers as the config) | ok / warn when not installed yet (installed on the first Boot project) / info when `vim.g.nv4j_spring = false` |
| JDK | Java used for jdt.ls (`nv4j.jdk.server_home()`) | ok / error with the message that function raises |
| CFR | `stdpath("data")/nv4j/tools/cfr-0.152.jar` and its SHA-256 against `M.CFR.sha256` in `nv4j/decompile.lua` | ok / error on mismatch / warn when absent (optional: `:Nv4JInstallCfr`) |
| Logs | `/tmp/nv4j/logs` | ok when writable / info when absent (created on demand) |
| Maven | `~/.m2/settings.xml` present or absent; jdt.ls reads only this file, not a project `settings.xml` | info. The content is never printed (it may hold credentials) |
| Project | `.nv4j` marker above the current buffer (or the cwd) | ok with the root / info |

A section that raises is reported as an error line and the others still run.
