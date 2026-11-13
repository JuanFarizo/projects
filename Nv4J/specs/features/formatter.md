# Java formatter profiles: `:Nv4JFormatter`

Which Eclipse formatter profile jdt.ls uses when you format Java (`<leader>cf`). Formatting stays on demand only (`vim.g.autoformat = false`, nothing runs on save). Code: `nvim/lua/nv4j/formatter.lua`, the jdt.ls setting in `nvim/lua/plugins/java.lua`, the command in `nvim/lua/config/keymaps.lua`. Check: `tests/checks/97_formatter.lua` (14 cases; controls `tests/lib/control_97.sh`). No `<leader>` key.

## Profiles

Every profile is an Eclipse formatter XML (the format jdt.ls reads through `java.format.settings.url`; plus `java.format.settings.profile` for the profile name inside the file). No google-java-format jar, no conform formatter for Java.

| Profile | What | Source of the XML |
|---------|------|-------------------|
| `intellij` (default) | An approximation of IntelliJ's defaults: spaces, 4 indent, 120 columns (code and Javadoc), continuation indent 8, up to 2 blank lines kept, wrap where necessary for arguments, parameters, binary and conditional expressions, chained calls wrapped after the first, block and line comments not re-wrapped | A Lua table in `formatter.lua`, written to `stdpath("data")/nv4j/formatter/intellij.xml` on first use (rewritten only when it differs). Not a file in the repo |
| `eclipse` | jdt.ls's built-in profile | `java.format.settings.url` is not set |
| `google` | Google's `eclipse-java-google-style.xml` (profile `GoogleStyle`: 2 spaces, 100 columns) | Downloaded once to `stdpath("data")/nv4j/formatter/`, see below |
| `<path>` | Your own Eclipse XML | Absolute, or relative to the project root; a missing file warns and jdt.ls keeps its built-in profile |

An approximation, not IntelliJ: only the settings listed in `M.INTELLIJ` differ from jdt.ls's built-in profile. Measured on the check's messy fixture: intellij and eclipse both wrap at 120 columns (jdt.ls's built-in profile is 120 too), the difference is the blank lines kept (2 against 1); the Google profile wraps at 100.

## Choosing

Precedence, highest first: `"format_profile"` in the project's `.nv4j` (`{ "format_profile": "google" }`, a name or a path), the choice saved by `:Nv4JFormatter`, `vim.g.nv4j_format_profile`, the default `intellij`. A wrong type in `.nv4j` is ignored.

`:Nv4JFormatter` with no argument shows the current profile and where it comes from and opens `vim.ui.select` (intellij, eclipse, google, path; path asks for the file). `:Nv4JFormatter <profile>` switches. The choice is global, saved in `stdpath("state")/nv4j/formatter.json` (`{"profile": "..."}`); when a `.nv4j` sets a profile the message says the effective one stays the `.nv4j` one.

## Applying without a restart

On a jdt.ls start the profile goes into `java.format.settings` (url + profile) with the other settings. On a switch every running jdt.ls gets `workspace/didChangeConfiguration` with its own project's effective profile. Verified live (check 97 `live_*`): one jdt.ls, same client id, intellij -> eclipse -> intellij gives the first result again, so jdt.ls does reload `java.format.settings.url` on that notification (switching back to eclipse sends `null` for url and profile). No restart, no process.

## Google download

Google deleted the Eclipse and IntelliJ style files from `google/styleguide` on 2026-10-14 (commit `355ad72`, "use the official google-java-format plugins"). The file is taken from the commit before it, `eaa0a05ec282e893ba314f1e6aeb9ef9f6674249`, official repository: `https://raw.githubusercontent.com/google/styleguide/eaa0a05ec282e893ba314f1e6aeb9ef9f6674249/eclipse-java-google-style.xml` (36003 bytes, Eclipse `<profiles version="13">`, profile `GoogleStyle`). SHA-256 `e75524bb67e3ffc88d5c680ed75254e072e3dbccbb91c4a0c708dcfabf2bdf91`, checked before the file is kept. Licence: CC-BY 3.0 (the repository's `LICENSE`, "Attribution 3.0 Unported"; the user accepted it). It is downloaded at runtime to the user's machine, never committed here. Done by `:Nv4JFormatter google` the first time (curl, once, never retried in a session). Not the third-party fork `darcyliu/google-styleguide` and not its IntelliJ-format file, which jdt.ls cannot read.

## Cost

Zero at startup: the module loads when a jdt.ls config is built (first Java file) or the command runs. Reading it costs one table-to-XML write at most. No network except the one-time google download, no process by formatting (jdt.ls formats in its own process).

## Checks

Pure: `zero_cost_startup`, `xml`, `xml_written`, `precedence`, `path_resolution`, `persistence`, `settings_of`, `google_install` (stubbed curl: wrong SHA refused, pinned SHA kept), `command_switch`. Live (messy fixture, `textDocument/formatting`): `live_intellij`, `live_eclipse`, `live_switch_no_restart`, `live_back`, `live_google`. The real state and data dirs are never touched (stubbed to a temp tree).

Controls (`tests/lib/control_97.sh`, one patch each, the named case must fail): `width` -> `xml`, `order` -> `precedence`, `relpath` -> `path_resolution`, `nosha` -> `google_install`, `nosave` -> `persistence`, `live` (no didChangeConfiguration) -> `live_eclipse`.

## Not verified / open

- Real terminal use of the `vim.ui.select` menu (only `:Nv4JFormatter <arg>` is exercised headless).
- Linux. Only macOS.
- The intellij profile is an approximation; no side-by-side with real IntelliJ output.
- The saved choice is global, not per project (per project = `.nv4j`).
- A different profile per jdt.ls is applied by project root; two projects with different `.nv4j` values work in theory, not tested.
