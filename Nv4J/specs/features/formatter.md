# Java formatter profiles: `:Nv4JFormatter`

Which Eclipse formatter profile jdt.ls uses when you format Java (`<leader>cf`). Formatting stays on demand only (`vim.g.autoformat = false`, nothing runs on save). Code: `nvim/lua/nv4j/formatter.lua`, the jdt.ls setting in `nvim/lua/plugins/java.lua`, the command in `nvim/lua/config/keymaps.lua`. Check: `tests/checks/97_formatter.lua` (22 cases; controls `tests/lib/control_97.sh`). No `<leader>` key.

## Profiles

Every profile is an Eclipse formatter XML (the format jdt.ls reads through `java.format.settings.url`; plus `java.format.settings.profile` for the profile name inside the file). No google-java-format jar, no conform formatter for Java.

| Profile | What | Source of the XML |
|---------|------|-------------------|
| `intellij` (default) | An approximation of IntelliJ's defaults: spaces, 4 indent, 120 columns (code and Javadoc), continuation indent 8, up to 2 blank lines kept, wrap where necessary for arguments, parameters, binary and conditional expressions, chained calls wrapped after the first, block and line comments not re-wrapped | A Lua table in `formatter.lua`, written to `stdpath("data")/nv4j/formatter/intellij.xml` on first use (rewritten only when it differs). Not a file in the repo |
| `eclipse` | jdt.ls's built-in profile | `java.format.settings.url` is not set |
| `google` | Google's `eclipse-java-google-style.xml` (profile `GoogleStyle`: 2 spaces, 100 columns) | Downloaded once to `stdpath("data")/nv4j/formatter/`, see below |
| `<path>` | Your own Eclipse XML | Absolute, `~/x.xml`, or relative to the project root (a relative path is saved as typed in `.nv4j`, as an absolute path in the global file). A missing file, a directory or a file without `<profile name=...>` is refused with a one-line message; the profile name inside the file is sent to jdt.ls |

An approximation, not IntelliJ: only the settings listed in `M.INTELLIJ` differ from jdt.ls's built-in profile. Measured on the check's messy fixture: intellij and eclipse both wrap at 120 columns (jdt.ls's built-in profile is 120 too), the difference is the blank lines kept (2 against 1); the Google profile wraps at 100.

## Choosing

Precedence, highest first: `"format_profile"` in the project's `.nv4j` (`{ "format_profile": "google" }`, a name or a path), the global choice saved by `:Nv4JFormatter`, `vim.g.nv4j_format_profile`, the default `intellij`. A wrong type in `.nv4j` is ignored.

`:Nv4JFormatter` (no argument) prints one line: the effective profile, where it comes from and the file (`Java formatter: google (from .nv4j: /proj/.nv4j); global choice eclipse in ~/.local/state/nv4j/nv4j/formatter.json`), then asks in two steps: where to save (`This project (.nv4j)` or `Global`), then which profile (intellij, eclipse, google, path). `path` opens the native command line as `:Nv4JFormatter --project ` (or `--global `) so you type the file with normal file completion (Tab) and `<CR>` always submits; it does not use `vim.ui.input`, whose completion popup took the first `<CR>`.

`:Nv4JFormatter <profile> [--project|--global]`: `--project` writes `format_profile` into the project's `.nv4j` (project = the root of the current buffer, else of the cwd), keeping every other field (pretty JSON, keys sorted); if `.nv4j` does not exist it asks `Create <root>/.nv4j?` first and writes nothing on No; a `.nv4j` that is not a JSON object is never overwritten (message, nothing written); home or above is refused. `--global` (default, as before) writes `stdpath("state")/nv4j/formatter.json`. Every result is one notification that says where it was saved and what is effective, e.g. `Formatter profile 'google' saved to /proj/.nv4j (this project only). Effective here: google (from .nv4j: /proj/.nv4j). 1 jdt.ls updated, no restart.`; a global save while a `.nv4j` wins adds a NOTE saying so. No jdt.ls running: it says the choice applies when one starts. Any error in the command is caught and shown as `Nv4JFormatter failed: ...`.

## Indent follows the profile

jdt.ls formats with the indent the client sends (`options.tabSize` and `insertSpaces`, which Neovim fills from the buffer's `shiftwidth` and `expandtab`), and that overrides the profile's tabulation settings. Measured: with `google` and `shiftwidth=4` the output had Google's 100 columns but 4-space indent; with `shiftwidth=2` it was 2 spaces. So Java buffers attached to jdt.ls now take `shiftwidth`, `tabstop`, `softtabstop` and `expandtab` from the profile (`intellij` 4 spaces, `google` 2, a path file: its `tabulation.size` and `tabulation.char`) at attach and on every switch; `eclipse` (no indent in the profile) puts the buffer's own values back. Consequence: an `.editorconfig` `indent_size` on a Java file is overridden by the profile after jdt.ls attaches.

## Applying without a restart

On a jdt.ls start the profile goes into `java.format.settings` (url + profile) with the other settings. On a switch every running jdt.ls gets `workspace/didChangeConfiguration` with its own project's effective profile. Verified live (check 97 `live_*`, and by hand in a real tmux Neovim): one jdt.ls, same client id, intellij -> eclipse -> intellij gives the first result again, so jdt.ls does reload `java.format.settings.url` on that notification (switching back to eclipse sends `null` for url and profile). No restart, no process.

## Google download

Google deleted the Eclipse and IntelliJ style files from `google/styleguide` on 2026-10-14 (commit `355ad72`, "use the official google-java-format plugins"). The file is taken from the commit before it, `eaa0a05ec282e893ba314f1e6aeb9ef9f6674249`, official repository: `https://raw.githubusercontent.com/google/styleguide/eaa0a05ec282e893ba314f1e6aeb9ef9f6674249/eclipse-java-google-style.xml` (36003 bytes, Eclipse `<profiles version="13">`, profile `GoogleStyle`). SHA-256 `e75524bb67e3ffc88d5c680ed75254e072e3dbccbb91c4a0c708dcfabf2bdf91`, checked before the file is kept. Licence: CC-BY 3.0 (the repository's `LICENSE`, "Attribution 3.0 Unported"; the user accepted it). It is downloaded at runtime to the user's machine, never committed here. Done by `:Nv4JFormatter google` the first time (curl, once, never retried in a session). Not the third-party fork `darcyliu/google-styleguide` and not its IntelliJ-format file, which jdt.ls cannot read.

## Cost

Zero at startup: the module loads when a jdt.ls config is built (first Java file) or the command runs. Reading it costs one table-to-XML write at most. No network except the one-time google download, no process by formatting (jdt.ls formats in its own process).

## Checks

Pure: `zero_cost_startup`, `xml`, `xml_written`, `precedence`, `path_resolution`, `persistence`, `settings_of`, `google_install` (stubbed curl: wrong SHA refused, pinned SHA kept), `command_switch`. Live (messy fixture, `textDocument/formatting`): `live_intellij`, `live_eclipse`, `live_switch_no_restart`, `live_back`, `live_google` (the real command; 2-space indent, at most 100 columns), `live_path_project` (relative file written to `.nv4j`, 3 spaces, 60 columns), `live_project_eclipse`. The live cases format with the options Neovim builds from the buffer, as `<leader>cf` does (the first version sent a fixed tabSize 4, which hid the Google indent bug). New pure cases: `path_forms`, `indent_sync`, `settings_set`, `project_scope`, `select_flow` (stubbed `vim.ui.select`, stubbed cmdline feed), `failure_paths`. The real state and data dirs are never touched (stubbed to a temp tree).

Controls (`tests/lib/control_97.sh`, one patch each, the named case must fail): `width` -> `xml`, `order` -> `precedence`, `relpath` -> `path_resolution`, `nosha` -> `google_install`, `nosave` -> `persistence`, `live` (no didChangeConfiguration) -> `live_eclipse`, `indent` -> `indent_sync`, `merge` (.nv4j fields dropped) -> `settings_set`, `abspath` -> `select_flow`, `scope` -> `project_scope`, `isfile` -> `path_forms`.

## Bugs found by using it (2026-11-13)

The first version was only exercised headless with `:Nv4JFormatter <arg>` and a fixed tabSize. In a real tmux Neovim (jdt.ls attached, `<leader>cf`):

- google formatted with 4-space indent (only the 100 columns changed): jdt.ls takes tabSize from the client. Fixed by the indent sync above.
- `path` from the list: the typed path showed a completion popup (file source) and the first `<CR>` accepted the completion, so nothing happened until a second `<CR>`. Replaced by the native command line.
- the choice lived only in the global state file; nothing appeared in `.nv4j`. Now `--project` / the scope step.
- a relative path saved globally was resolved against whichever project was open later; now saved absolute.
- `:Nv4JFormatter google` "throws errors": NOT reproduced (google, eclipse -> google -> intellij sequences, from a no-name, directory and fake-named buffer, with and without the XML downloaded; no error in `:messages` or jdt.ls's log). The command is now wrapped so any error shows as one `Nv4JFormatter failed:` line.

## Not verified / open

- The `vim.ui.select` steps were driven by hand in a real terminal (Telescope-backed `dressing.nvim`); other UI plugins were not. The check stubs `vim.ui.select` and the cmdline feed.
- Linux. Only macOS.
- The intellij profile is an approximation; no side-by-side with real IntelliJ output.
- Two projects with different `.nv4j` values (one jdt.ls each) work by construction, not tested live.
- The user's own `google` error text is unknown; the cause of that one is not found.
