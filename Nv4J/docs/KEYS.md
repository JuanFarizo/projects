# Nv4J keys

Every key Nv4J adds or relies on for Java and Spring work, in one place. `<leader>` is Space. "Where" says which file defines the key, so you can change it. How to use them step by step: [GUIDE.md](GUIDE.md). Measurements, limits and the reason behind each: [README.md](../README.md) and `specs/features/`.

Keys marked **Java buffer** exist only in a Java file after jdt.ls has attached. Keys marked **global** work in any buffer.

## Java: new files and refactors (`<leader>j`)

| Key | Does | Scope | Where |
|-----|------|-------|-------|
| `<leader>jn` | New class, interface, record, enum, annotation, Spring controller, service, repository, entity, package or test. Asks the kind, then the name. `foo.Bar` creates package `foo` | global | `config/keymaps.lua` |
| `<leader>jt` | Open the test class of this class, or create it in `src/test/java` | global | `config/keymaps.lua` |
| `<leader>jr` | Rename the class under the cursor (file, references, imports; test classes, variables of that type and subclasses named like it follow). On a `package` line: rename the package (into an existing package: merge) | global | `config/keymaps.lua` |
| `<leader>jp` | Rename the current file's package (folders in `src/main/java` and `src/test/java` move) | global | `config/keymaps.lua` |
| `<leader>jm` | Move the class under the cursor (or the class named under it) to another package of `src/main/java` or `src/test/java` (picked, or typed: the folder is created); package-private conflicts are listed and asked first | global | `config/keymaps.lua` |
| `<leader>ji` | Inline the method call, local variable or constant under the cursor | global | `config/keymaps.lua` |
| `<leader>js` | Change the signature of the method under the cursor (declaration or call). You type it as one line, for example `public int total(Invoice invoice, int discount = 0)` | global | `config/keymaps.lua` |
| `<leader>jd` | Safe delete the method, field, constant or type under the cursor. With usages nothing is deleted and they go to the quickfix list | global | `config/keymaps.lua` |
| `<leader>ju` | Undo the last rename, package rename or move completely: file names, folders, package lines, imports (`u` in a buffer gives back its text only) | global | `config/keymaps.lua` |
| `:Nv4jRestoreDeleted` | Put back the file that safe delete removed last (copy kept in the Nv4J trash, last 20) | command | `config/keymaps.lua` |
| neo-tree `r` on a `.java` file or package folder | Same rename, with the code updated | neo-tree | `plugins/neo-tree.lua`, `nv4j/refactor.lua` |

## Tests (`<leader>t`)

| Key | Does | Scope | Where |
|-----|------|-------|-------|
| `<leader>tr` | Run the test under the cursor | Java buffer and global | `config/keymaps.lua`, `plugins/java.lua` |
| `<leader>tt` | Run every test of the class | Java buffer and global | same |
| `<leader>tp` | Run every test of the project. It replaces the old `mvn test` terminal key | Java buffer and global | same |
| `<leader>tf` | Run the tests that failed last time again | Java buffer and global | same |
| `<leader>tl` | Run the last test run again | Java buffer and global | same |
| `<leader>to` | Open the results (quickfix list) | Java buffer and global | same |
| `<leader>tv` (or `:Nv4JTestResults`) | Test results view of the last run in this project: failed tests first, then the rest, with time per test. `<CR>` on a test opens its message, stack trace (your own frames bright, library frames dim) and the output it printed; `<CR>` on one of your frames jumps to that file and line; `r` reruns the test under the cursor, `R` reruns the failed ones, `q` closes | Java buffer and global | `nv4j/testresultsui.lua`, bound with the others |
| `<leader>td` | Debug the nearest test (breakpoints stop) | Java buffer and global | same |
| `<leader>tT` | Pick a test of the file (nvim-jdtls picker; also runs TestNG). Outside a Java file with jdt.ls it only says so | Java buffer and global | `config/keymaps.lua`, `plugins/java.lua` (`nv4j.tests.bind()`) |
| `<leader>tn` | New terminal in a tab (use it for `mvn test` by hand) | global | `config/keymaps.lua` |

## Run and debug a Spring Boot app (`<leader>r`)

| Key | Does | Scope | Where |
|-----|------|-------|-------|
| `<leader>rs` | Run the Spring Boot app (`java -cp`, project JDK, build first; `.nv4j` run defaults if present) | global | `config/keymaps.lua` |
| `<leader>rd` | Debug the Spring Boot app (same defaults) | global | same |
| `<leader>rp` | Pick a profile, then run (this run only; does not write `.nv4j`) | global | same |
| `:Nv4jMark` | Create an empty `.nv4j` in the current working directory (does not overwrite) | command | `nv4j/settings.lua` |
| `<leader>rS` | Run through Maven or Gradle (`spring-boot:run`, `bootRun`; Gradle: VM args go in `JAVA_TOOL_OPTIONS`, a `gradlew` without exec bit runs via `sh`) | global | same |
| `<leader>rx` | Stop every Spring Boot run | global | same |
| `<leader>rj` | Run a main class with plain `java` in a terminal | global | same |
| `<C-c>` in the run split (normal mode) | Stop the app | run split | `nv4j/run.lua` |
| `q` in the run split | Stop the app and close the split | run split | `nv4j/run.lua` |
| `<leader>sp` | Spring symbols: beans and request mappings (Telescope) | global | `config/keymaps.lua` |

## Debugger (`<leader>d`, LazyVim)

| Key | Does |
|-----|------|
| `<leader>db` / `<leader>dB` | Toggle breakpoint / conditional breakpoint |
| `<leader>dc` | Run or continue |
| `<leader>dO` / `<leader>di` / `<leader>do` | Step over / into / out |
| `<leader>dC` | Run to cursor |
| `<leader>dt` | Terminate |
| `<leader>du` / `<leader>dr` | Debug UI / REPL |
| `<leader>de` | Evaluate (normal and visual) |

### IntelliJ debugger keys (only while a debug session is active)

Set when the session starts, removed when it ends; `F8` and `S-F8` are next / previous diagnostic again afterwards (`nv4j/debugkeys.lua`, check `92_debug_keys`). The `<leader>d` keys above stay.

| Key | Does |
|-----|------|
| `<F7>` / `<S-F7>` | Step into / smart step into (asks for the target when the adapter supports it, else plain step into with a notice; the Java adapter has no step-in targets) |
| `<F8>` / `<S-F8>` | Step over / step out |
| `<F9>` | Resume |
| `<A-F9>` | Run to cursor |
| `<A-F8>` | Evaluate expression: the selection in visual mode, else the word under the cursor (nvim-dap-ui float) |
| `<D-F8>` (Linux: `<C-F8>`) | Toggle breakpoint, any time (IntelliJ: Cmd+F8 on a Mac, Ctrl+F8 elsewhere). The platform is chosen like the other app keys (`vim.g.nv4j_mod`); Linux gets Ctrl, not Alt, because `<A-F8>` is evaluate |

On a Mac the top row sends media keys unless you hold `fn` or turn on "Use F1, F2, etc. keys as standard function keys" (System Settings, Keyboard); set that, or F7 to F9 never reach the terminal. kitty (the terminal the Cmd keys here are written for) passes them through. `<A-F8>` / `<A-F9>` need `macos_option_as_alt yes` in `kitty.conf`; Cmd+F8 reaches Neovim only through the kitty keyboard protocol, and macOS may take it first if a system shortcut uses it.

What Neovim really receives (measured in a private tmux server and in a bare pty with `TERM=xterm-kitty`, no kitty protocol): plain F7 / F8 / F9 arrive as `<F7>` / `<F8>` / `<F9>`, but Shift+F7, Shift+F8, Alt+F8, Alt+F9, Ctrl+F8 arrive under the terminfo names `<F19>`, `<F20>`, `<F56>`, `<F57>`, `<F32>`, not `<S-F7>` etc. So both names are mapped to the same action (the session keys and the diagnostic `<F20>` alias). Real kitty with the keyboard protocol was not run here.

## Code actions, imports and generation (`<leader>c`)

| Key | Does | Scope | Where |
|-----|------|-------|-------|
| `<leader>ca` | Code actions: quick fix, generate getters, constructors, `toString`, `equals`/`hashCode`, extract (normal and visual) | Java buffer | LazyVim |
| `<leader>co` | Organize imports (also removes unused ones) | Java buffer | LazyVim java extra |
| `<leader>cA` | Source actions | Java buffer | LazyVim |
| `<leader>cxv` / `<leader>cxc` | Extract variable / constant (normal and visual) | Java buffer | LazyVim java extra |
| `<leader>cxm` | Extract method (visual) | Java buffer | LazyVim java extra |
| `<leader>cr`, `<F2>`, `<leader>rn` | Rename any symbol (LSP rename). For classes and packages use `<leader>jr` / `<leader>jp` | Java buffer, global | LazyVim, `config/keymaps.lua` |
| `<leader>cf` | Format (Java and XML through their language servers) | global | LazyVim |
| `<leader>cc` / `<leader>cC` | Run / refresh code lens | Java buffer | LazyVim |

## Navigation

| Key | Does | Where |
|-----|------|-------|
| `gd`, `<F12>`, `<C-Down>` | Go to definition | LazyVim, `config/keymaps.lua` |
| `gr`, `<C-Up>` | References (usages) | LazyVim, `config/keymaps.lua` |
| `gI` / `gy` | Go to implementation / type definition | LazyVim |
| `gD` | Go to declaration | LazyVim |
| `K` | Hover docs | LazyVim |
| `gK` or `<C-k>` in insert mode | Signature help | LazyVim |
| `<leader>cS` / `<leader>cP` | Subtype / supertype hierarchy | `config/keymaps.lua` |
| `<leader>ci` / `<leader>cO` | Incoming / outgoing calls | `config/keymaps.lua` |
| `<leader>cgs` / `<leader>cgS` | Go to super implementation / go to test subjects | LazyVim java extra |
| `]]` / `[[` | Next / previous reference | LazyVim |
| `<C-m>` | Methods of the current file (needs the kitty keyboard protocol, else it acts as Enter) | `config/keymaps.lua` |
| `<leader>ss` / `<leader>sS` | Symbols of the file / workspace | LazyVim |
| `<D-Left>` / `<D-Right>` (Linux: `<A-Left>` / `<A-Right>`) | Jump back / forward | `config/keymaps.lua` |

## Diagnostics

| Key | Does |
|-----|------|
| `]d` / `[d`, `<F8>` / `<S-F8>` | Next / previous diagnostic (F8 and S-F8 are the debugger's step over / out while a debug session runs) |
| `]e` / `[e` | Next / previous error |
| `<leader>cd` | Line diagnostics popup |
| `<leader>xx` / `<leader>xX` | All diagnostics / this buffer (Trouble) |

## Completion (blink.cmp, "enter" preset)

| Key | Does |
|-----|------|
| `<CR>` or `<C-y>` | Accept the selected item (adds the import) |
| `<C-n>` / `<C-p>`, `<Down>` / `<Up>` | Next / previous item |
| `<C-e>` | Close the menu |
| `<C-Space>` | Open the menu, show or hide the docs |
| `<Tab>` / `<S-Tab>` | Next / previous snippet field |

## Files, search and windows

| Key | Does |
|-----|------|
| `<C-p>` | Find files |
| `<C-o>` | Grep the project |
| `<C-f>` | Search in the current file |
| `<C-e>` (normal mode) | Search open buffers |
| `<C-b>`, `<leader>e`, `<leader>ef` | File explorer / explorer at root / reveal current file |
| `<leader>ff` / `<leader>fr` / `<leader>fb` | Find files / recent files / buffers |
| `<leader>sg` / `<leader>sw` | Grep / grep the word under the cursor |
| `<leader>fo` | Open a file or search files in another folder |
| `<leader>fy` / `<leader>fY` | Yank relative / absolute path |
| `<Tab>` / `<S-Tab>` (normal mode) | Next / previous buffer |
| `<C-q>` | Close the buffer |
| `<leader>w` / `<leader>W` / `<leader>q` | Save / save all / quit |
| `<C-/>` (or `<C-_>`, what terminals send for it) | Toggle terminal (LazyVim core; `<C-t>` in it: new terminal tab, `<D-]>` / `<D-[>`, Linux `<A-]>` / `<A-[>`: next / previous). `<C-j>` is window navigation again (LazyVim) |
| `<C-t>` | New scratch note (persistent) |

## Editing

| Key | Does |
|-----|------|
| `<A-Down>` / `<A-Up>` | Move line or selection down / up |
| `<C-S-d>` | Duplicate line or selection |
| `<D-/>` on a Mac, `<A-/>` on Linux (normal, visual, insert) | Toggle comment (`gcc` / `gc` work everywhere; `<C-/>` is the terminal now) |
| `ga` / `gA` | Align text (mini.align) |
| `<C-z>` / `<C-S-z>` | Undo / redo |
| `<C-d>` | Expand selection (in insert mode: leave insert and select the word) |
| `<C-g>` | Go to line |
| `<A-->` / `<A-+>` | Collapse / expand all folds |

## Git

| Key | Does |
|-----|------|
| `<leader>gs` / `<leader>gc` | Status / commits |
| `<leader>ghs` / `<leader>ghr` / `<leader>ghb` | Stage hunk / reset hunk / blame line |
| `]h` / `[h` | Next / previous hunk |
| `<leader>ghi` | Toggle inline diff of the whole file |

## AI agents (`<leader>a`, which-key group "AI agents")

Claude (claudecode.nvim) and Cursor (sidekick.nvim terminal, `cursor-agent`). Nothing loads at startup; the first `<leader>a` key loads the plugin. `<leader>aa` and the keys below it act on the active agent (Claude at the start of every session); `<leader>ac` / `<leader>ak` start one and make it the active one. Code: `lua/plugins/ai.lua`, `claudecode.lua`, `sidekick.lua`, `lua/util/ai.lua`.

| Key | Does |
|-----|------|
| `<leader>aa` | Toggle the active agent |
| `<leader>ap` | Pick the agent (Claude or Cursor) |
| `<leader>ac` / `<leader>ak` | Toggle Claude / toggle Cursor |
| `<leader>as` (visual) | Send the selection (in neo-tree: add the file, Claude) |
| `<leader>ab` | Add the current buffer |
| `<leader>ar` / `<leader>aC` | Resume / continue the last session |
| `<leader>am` | Select the model (Claude) |
| `<leader>af` | Focus the Claude panel |
| `<leader>ay` / `<leader>an` | Accept / deny the Claude diff |

If the Claude panel was open when you left a folder, it opens again next time you start Neovim on that folder (`nvim` or `nvim .`; state in `~/.local/state/nv4j/claudecode_sessions.json`).

## Indent guides and Markdown

| Key | Does |
|-----|------|
| `<leader>uI` | Toggle indent guides (replaces LazyVim's "Inspect Tree" on this key, still `:InspectTree`; hlchunk; off at start, the chunk border and the current line number highlight are on). snacks.nvim's indent and scope are disabled, so there is never a second set of guides |
| `<leader>cp` / `<leader>um` (Markdown buffers) | Toggle the in-buffer Markdown rendering (render-markdown.nvim) |

## Not a key, but good to know

- Formatting is on demand only (`<leader>cf`; `vim.g.autoformat` is false): Java and XML through the language servers, Markdown/JSON/YAML/HTML/CSS through Prettier (Mason installs it).
- `:Nv4JLogs [30m|2h|1d|7d]` lists every log (Neovim LSP, jdt.ls, Spring, DAP, captures) in Telescope, preview = end of the file. In the list: `<CR>` open, `<C-f>` follow, `<C-g>` grep (with an ERROR/WARN filter), `Tab` select, `<C-s>` save the selected files to `~/.local/state/nv4j/nv4j/saved-logs/`; `:Nv4JLogs save 2h` saves a whole period. No `<leader>` key. See `specs/features/observability.md`.
- `<leader>?` shows the keys of the current buffer; `<leader>sk` searches all keys.
- Options such as `vim.g.nv4j_run_tool` and `vim.g.nv4j_spring`: README "Options".
- To list every key of your own session: `:Telescope keymaps`.
