# Nv4J

A fast, lightweight Neovim setup for Java and Spring development. It is built on LazyVim and runs next to your normal Neovim: your own `~/.config/nvim` is never touched. IntelliJ is the feature reference. Every feature has a priority and a pass/fail number, and the numbers are re-measured by a headless test suite you can run yourself.

Status: **P1 is built and passing** (completion, diagnostics, imports, code actions, JDK handling). P2 to P5 are planned, not built. The "Not yet" list below is honest about that.

## Priorities

| Priority | Scope | Status |
|----------|-------|--------|
| P1 | Completion speed and ranking, diagnostics, imports, code actions, Java 25 and JDK handling | Done (this README, Capabilities) |
| P2 | Spring awareness (annotations, attributes, `application.properties`/`yml`), run and debug Spring Boot | Not yet |
| P3 | Tests runner polish, scaffolding (package/class creation), refactors beyond what jdt.ls already offers | Not yet |
| P4 | Gradle, Spring navigation, JPA checks | Not yet |
| P5 | Everything else | Not yet |

Maven is first class. Gradle is second and is not tested yet. Source of truth for decisions and numbers: `specs/001-architecture.md`, `specs/002-p1-completion.md`, `specs/features/*.md`.

## Capabilities (P1, shipped)

Each row says what you get, the measured result (ranges are the three consecutive full runs recorded in the specs; a later full run had 129 PASS and 0 FAIL, with single timings varying by about 10 to 20 percent), and the check that proves it. All numbers come from `tests/run.sh` on a Spring Boot 3.5 fixture project (`tests/fixtures/demo`: web, data-jpa, security, validation; Java 25), Neovim 0.12, jdt.ls 1.62, on the author's Mac. Your machine and a bigger project will differ. The logs of the runs behind the numbers are in `specs/002-p1-completion.md` and `specs/features/diagnostics-imports-actions.md`.

### Completion speed and ranking

| What you get | Measured (budget) | Check |
|--------------|-------------------|-------|
| Completion answers fast once warm | worst case p95 38 to 45 ms over the recorded runs (150 ms) for 14 cases: `@`, `@Table(`, `http.`, `repository.`, `System.`, `new Person(`, identifiers | `10_completion_latency` |
| The sorted list ready for the menu | menu p95 worst about 40 ms (150 ms) | `10_completion_latency` |
| First completion after jdt.ls is ready is not slow (warm-up on start) | 51 to 55 ms (400 ms). Before the warm-up it was 740 to 827 ms | `10_completion_latency` (`cold_first`, sent 1.0 s after ServiceReady) |
| Expected item near the top | `@` gives `RestController` at 4 (was 6), `http.` gives `authorizeHttpRequests` at 2 (was 19), `repository.` gives `save` at 1 (was 42). `@Auto`, `@Rest`, `@Table(`, `@Column(` first or in the short list. Local variables and fields beat JDK types | `11_completion_ranking` |
| Postfix templates (`http.cast`, `sysout`...) come after real members, `http.va` still finds `var` | rule checked | `11_completion_ranking` |
| Members you use most in the project rank higher (IntelliJ style "most used"), counted with ripgrep | rule checked, rg failing or timing out keeps old counts | `11_completion_ranking`, `12_usage_index` |
| Less JDK noise: internal packages, `com.apple.*`, AspectJ internals, `java.awt.List` hidden, so `List` completes to `java.util.List` | `no_noise` cases a, s, m, List | `11_completion_ranking` |

Why it is fast: measured, not guessed. What helped: postfix templates matched on their key and put last, project usage as a tie breaker after jdt.ls relevance, no `java.*` relevance bonus, fewer flooding items, a warm-up completion when jdt.ls is ready. What did not help is recorded too (ParallelGC, AppCDS, `maxResults` 50/1000, `lazyResolveTextEdit`), see the trial log in `specs/002-p1-completion.md`.

Time from opening a file until jdt.ls is ready: about 6.1 to 6.4 s on a warm workspace, about 15 s for the very first import of the Spring fixture (info, not budgeted).

### Diagnostics

| What you get | Measured (budget 3 s) | Check |
|--------------|-----------------------|-------|
| Errors appear after an edit | 462 to 476 ms | `30_diagnostics` |
| Unused import, local, private field, private method as faded warnings | 674 to 684 ms | `30_diagnostics` |
| Fixing the code clears them | 471 to 511 ms | `30_diagnostics` |
| A typing burst settles with no stale error | 633 to 683 ms | `30_diagnostics` |
| Java 25 code (module imports, flexible constructors, `_`, record patterns, Markdown doc comments) has zero diagnostics | 490 to 521 ms | `30_diagnostics`, `20_java25` |
| Unused-import warnings still show while the file has compile errors (jdt.ls drops them, IntelliJ does not) | shown 473 to 506 ms, pass cost on a 3000-line file p50 about 1.2 ms, p95 about 3 ms | `30_diagnostics` (`unused_pass_perf` and the unused-with-errors cases) |
| A broken `pom.xml` (malformed, missing artifact) shows a visible notification, a fixed one clears it automatically | error plus notice in 196 to 318 ms (malformed), 638 to 997 ms (missing artifact), fixed clean in 364 to 600 ms | `30_diagnostics` |

Inline diagnostics are drawn by tiny-inline-diagnostic. They refresh when you leave insert mode (`update_in_insert = false`), so a half typed line does not flicker red.

### Imports

| What you get | Measured (budget 1.5 s) | Check |
|--------------|-------------------------|-------|
| Accepting a completion adds its import, also the very first one of a session | first `List` 685 to 746 ms, second documented type (`HashMap`) 379 to 439 ms | `31_imports` |
| Imports land in IntelliJ-like groups: everything else, `javax`, `jakarta`, `java`, then static | checked on a planted file | `31_imports` |
| `<leader>co` organizes: removes unused imports, orders groups, also when the file has a compile error | 137 to 183 ms | `31_imports` |
| No wildcard imports (star threshold 99) | config | none |

Organize on save is off, like IntelliJ's default. The cost of always getting the import is a short wait on accept, see Known limitations.

### Code actions (`<leader>ca`)

Offered by jdt.ls, applied through Neovim's own code action UI. Round trip 9 to 120 ms (budget 1 s). Proven by `32_code_actions`:

- Quick fixes: create method (same class or another class), create variable/field/parameter, create class, import type, add unimplemented methods, remove unused import, remove unused local.
- Generate: getters and setters, constructors, `toString()` (`App{name=x, age=1}` style), `equals`/`hashCode` (`java.util.Objects`, braces). The field pickers start with all fields selected (a fix in `nvim/lua/nv4j/codegen.lua`).
- Extract: local variable, constant, method.
- Lombok: `@Getter`, `@RequiredArgsConstructor` members resolve with no errors (Mason's lombok agent).

### JDK handling and Java 25

Nothing is pinned to one JDK. `nvim/lua/nv4j/jdk.lua` finds JDKs in SDKMAN (`~/.sdkman/candidates/java`), `~/Library/Java/JavaVirtualMachines` and `/Library/Java/JavaVirtualMachines`, reading each JDK's `release` file.

- jdt.ls itself runs on `$JAVA_HOME` if that is a JDK 21 or newer, else the newest JDK 21+ it finds, else you get a clear error.
- Every JDK found is registered with jdt.ls. The one used to compile a project follows the build file: `.sdkmanrc`, then the pom's `maven.compiler.release`, `java.version` or `maven.compiler.source`, then `$JAVA_HOME`, then the newest.
- Proven by `20_java25` with a hostile setup (`JAVA_HOME` unset, a JDK 21 first on `PATH`): the Java 25 fixture reports release 25 and a JDK 25 location with zero errors, jdt.ls does not run on `PATH`'s Java 21, and a second Maven project with release 21 gets a JDK 21 runtime.

### Also available (from LazyVim, not covered by the P1 checks)

Debug adapter and test bundles (Mason: `java-debug-adapter`, `java-test`), the keymaps below for tests and debugging, Telescope, neo-tree, git signs, `lemminx` for XML (`pom.xml` formatting and validation), and a basic Java file template when you create a new `.java` file (class, package, and a Spring annotation for controller/service/repository/entity). They are here because the base config had them, they are not part of P1's measured work.

## Not yet

Be aware before you rely on Nv4J for a full workday:

- **P2: Spring awareness.** No Spring language server. No completion or checking for annotation attributes beyond what jdt.ls does (`@Table(`/`@Column(` lists come from jdt.ls only), no `application.properties`/`yml` key completion, no bean or request mapping support.
- **P2: run and debug Spring Boot.** There is no Spring Boot run/debug workflow yet. `<leader>rj` runs a plain `java -cp ... Main` in a terminal and works (checked by hand against the fixture), but it is not a Spring Boot launch with profiles or env. The debug keys exist (LazyVim) and are not tested here. During this work a notice `Could not resolve classpath and modulepath ... m2e.launchconfig.classpathProvider` appeared at start in headless runs, so treat debugging as unverified.
- **P3: tests runner polish.** `<leader>tt`, `<leader>tr`, `<leader>tT` (nvim-jdtls) and `<leader>tp` (whole project via `mvn test`) exist, they are not covered by checks.
- **P3: scaffolding** (create package, class, with a wizard). Only the basic new-file template above exists.
- **P3: refactors beyond what jdt.ls already offers.** Extract and rename work through jdt.ls. Move, inline, change signature, safe delete are not set up or tested.
- **P4: Gradle** (supported by jdt.ls, not tested, only the build-file notification code knows `build.gradle`), Spring navigation, JPA checks.
- **P5:** everything else.

## Install

### Requirements

- Neovim 0.12 or newer (`nvim --version`). Developed on 0.12.4.
- A JDK 21 or newer for jdt.ls, via SDKMAN or installed on the system. Your projects can use any JDK from 8 up that is installed; `.sdkmanrc` and the pom decide.
- Maven (`mvn`) on `PATH`. Needed for the test fixture build; jdt.ls brings its own m2e for project imports.
- ripgrep (`rg`). Used for the project usage counts that improve ranking. Without it everything works, ranking just falls back to jdt.ls order.
- The tree-sitter CLI (`tree-sitter`). `brew install tree-sitter-cli`. If it is missing, LazyVim installs it through Mason on first start.
- `git` and internet on first start (plugins and tools are downloaded).

### Steps

```sh
# from the repo root (the folder that holds nvim/, specs/, tests/)
ln -s "$PWD/nvim" ~/.config/nv4j
echo 'alias nv4j="NVIM_APPNAME=nv4j nvim"' >> ~/.zshrc   # then open a new shell
nv4j path/to/a/Maven/project/src/main/java/com/example/App.java
```

Why a symlink: with `NVIM_APPNAME=nv4j` Neovim reads `~/.config/nv4j` instead of `~/.config/nvim`, and the symlink points that at `nvim/` in this repo. Edit the repo files and you edit the config.

### First start

Expect it to be slow once. Neovim downloads the plugins (lazy.nvim, pinned by `nvim/lazy-lock.json`) into `~/.local/share/nv4j`, and Mason installs `jdtls`, `java-debug-adapter`, `java-test`, `lemminx`, `lua-language-server`, `stylua`, `shfmt` and the tree-sitter CLI if needed. Wait until the Mason window says it is done, then restart. Opening the first Java file imports the project: about 15 s for a Spring project the first time, about 6 s after. State, cache and data live in `~/.local/share/nv4j`, `~/.local/state/nv4j` and `~/.cache/nv4j`, separate from your normal Neovim.

### Roll back

Nothing of your old setup changed. Just use `nvim` instead of `nv4j`. To remove Nv4J completely: delete the `~/.config/nv4j` symlink, the `alias` line, and `~/.local/share/nv4j`, `~/.local/state/nv4j`, `~/.cache/nv4j`.

## How to use

`<leader>` is Space. Every key below was read from the config and checked in a real jdt.ls session (`vim.fn.maparg` in a Java buffer). If a key does not do what is written here, that is a bug in this README.

### Daily Java and Spring workflow

1. Open a file inside the Maven project (`nv4j src/main/java/...`). Opening only a folder (`nv4j .`) reloads the last session for that folder. jdt.ls starts, you see progress in the corner, and it is ready when the progress toasts stop.
2. Write code. Completion opens as you type.
3. Accept with the keys below, the import is added for you.
4. Fix what is red or faded with `<leader>ca`, tidy with `<leader>co`.

**Completion** (blink.cmp, "enter" preset):

| Key | Does |
|-----|------|
| `<CR>` | accept the selected item (adds the import) |
| `<C-y>` | accept (select and accept) |
| `<C-n>` / `<C-p>`, `<Down>` / `<Up>` | next / previous item |
| `<C-e>` | close the menu |
| `<C-Space>` | open the menu, show or hide the docs |
| `<Tab>` / `<S-Tab>` | next / previous snippet field |

The menu also shows ghost text, a docs popup after 200 ms and signature help inside call arguments.

**Imports and code actions**

| Key | Does |
|-----|------|
| `<leader>ca` (normal and visual) | code actions: quick fixes, generate, extract |
| `<leader>co` | organize imports (also removes unused, also when the file has errors) |
| `<leader>cA` | source actions |
| `<leader>cxv` / `<leader>cxc` (normal or visual) | extract variable / constant |
| `<leader>cxm` (visual) | extract method |
| `<leader>cr`, `<F2>`, `<leader>rn` | rename symbol |
| `<leader>cf` | format |

Generate getters, constructors, `toString`, `equals`/`hashCode`: put the cursor on the class name or a field, press `<leader>ca`, pick the "Generate ..." entry. The field picker is a numbered prompt (type numbers, Enter), not a checkbox list.

**Diagnostics**

| Key | Does |
|-----|------|
| `]d` / `[d` or `<F8>` / `<S-F8>` | next / previous diagnostic |
| `]e` | next error |
| `<leader>cd` | line diagnostics popup |
| `<leader>xx` / `<leader>xX` | all diagnostics / this buffer (Trouble) |

**Navigation**

| Key | Does |
|-----|------|
| `gd`, `<F12>`, `<C-Down>` | go to definition |
| `gr`, `<C-Up>` | references (usages) |
| `gI` / `gy` | implementation / type definition |
| `K` | hover docs |
| `<leader>cS` / `<leader>cP` | subtype / supertype hierarchy |
| `<leader>ci` / `<leader>cO` | incoming / outgoing calls |
| `<leader>cgs` / `<leader>cgS` | go to super implementation / go to test subjects |
| `<C-m>` | methods of the current file (needs a terminal with the kitty keyboard protocol, else it acts as Enter) |
| `<C-p>` / `<C-o>` / `<C-f>` | find files / grep project / search in file |
| `<C-b>` / `<leader>e` / `<leader>ef` | file explorer / explorer at root / reveal current file |
| `<leader>cc` / `<leader>cC` | run / refresh code lens ("n references" above methods) |

**Run, debug, test** (not covered by P1 checks, see Not yet):

| Key | Does |
|-----|------|
| `<leader>rj` | run a main class with plain `java` in a terminal (picks the class if several; uses the project's JDK from jdt.ls) |
| `<leader>tt` / `<leader>tr` / `<leader>tT` | run all tests in this class / nearest test / pick a test |
| `<leader>tp` | run all project tests (`mvnw test` or `mvn test`) in a terminal |
| `<leader>db` / `<leader>dc` / `<leader>dO` / `<leader>di` / `<leader>dB` / `<leader>dt` / `<leader>du` | toggle breakpoint / run or continue / step over / step into / conditional breakpoint / terminate / debug UI |

### Switch JDK with `sdk use`

The JDK that jdt.ls runs on is chosen when it starts, from `$JAVA_HOME`. Set it before you start Neovim:

```sh
sdk use java 21.0.7-amzn     # sets JAVA_HOME in this shell (SDKMAN)
nv4j path/to/File.java       # jdt.ls now runs on JDK 21
```

Checked: with that command, `JAVA_HOME` was the 21 JDK and the config picked it as the server JVM. The JDK used to compile your project is separate and follows the build file (the fixture still got JavaSE-25 as its default with `JAVA_HOME` on 21). To change the project's JDK edit `<maven.compiler.release>` or `.sdkmanrc`. After changing either of these in a running session, quit and start Neovim again.

### Hide or show more types in completion

Some JDK packages are hidden from completion by default (`com.sun.*`, `sun.*`, `jdk.internal.*`, `com.apple.*`, AspectJ internals, `java.awt.List` and a few more; the list is `DEFAULT_FILTERED_TYPES` in `nvim/lua/nv4j/completion.lua`). To change it, set this before jdt.ls starts, for example in `nvim/lua/config/options.lua`:

```lua
vim.g.nv4j_filtered_types = {
  add = { "javax.swing.*" },        -- hide these too
  remove = { "java.awt.List" },     -- show these again
}
```

Checked: the resulting list has `javax.swing.*` added and `java.awt.List` removed. Restart Neovim after changing it.

### Completion profiler

`:CompletionProfile on` starts a profiler that you turn on only when something feels slow. It records, per keystroke, the time to the menu, jdt.ls round trips, whether the list was incomplete, and UI stalls, as JSON lines in `~/.local/state/nv4j/completion-profile.jsonl`. `:CompletionProfile off` stops it, `status` shows the file and its size, `clear` deletes it (after `off`). It is always off after a restart.

## Configuration map

```
nvim/
  init.lua                 sets up /tmp/nv4j paths and the LSP log, then lazy.nvim
  lazyvim.json             LazyVim extras: telescope, neo-tree, blink, mini-surround, dap.core, lang.java
  lazy-lock.json           pinned plugin versions
  lua/config/              options.lua, keymaps.lua, autocmds.lua, lazy.lua
  lua/plugins/
    java.lua               jdt.ls settings, JDK runtimes, import order, code generation, hooks
    blink.lua              completion UI and the Java ranking hooks
    diagnostics.lua        inline diagnostics (tiny-inline-diagnostic)
    lsp.lua, xml.lua       code lens on, inlay hints off, lemminx
    neo-tree, telescope, gitsigns, noice, which_key, theme, treesitter, expand-region
  lua/nv4j/                Nv4J's own small Lua modules
    jdk.lua                JDK discovery and runtimes
    completion.lua         Java ranking, filtered types, snippet rules
    usage.lua              project usage counts (ripgrep)
    warmup.lua             warm-up completion when jdt.ls is ready
    unused_imports.lua     unused-import warnings while the file has errors
    buildfile.lua          notifications for broken pom.xml / build.gradle
    codegen.lua            field pickers preselect all fields
    paths.lua              /tmp/nv4j directories
  lua/util/                profile.lua (:CompletionProfile), java_scaffold.lua (new file template)
specs/                     001 architecture, 002 P1 numbers and trial log, features/*.md
tests/                     run.sh, checks/, fixtures/, lib/
```

## Testing

```sh
tests/run.sh                          # every check, each in its own headless Neovim
NV4J_CHECKS=30 tests/run.sh           # only checks whose file name starts with 30
NV4J_CHECKS='3*' tests/run.sh         # a glob works too
NV4J_PATH_JDK=25 tests/run.sh         # friendly case: JDK 25 first on PATH (default is the hostile 21)
```

It needs `~/.config/nv4j` linked (above), a JDK 25 (to compile the fixture) and Maven. It installs jdt.ls into Nv4J's own Mason directory if it is missing, prints only PASS/FAIL lines, and writes the full output to `/tmp/nv4j/logs/test-<timestamp>.log`. Exit code is 0 only if everything passed.

The checks (each file lists its cases at the top):

| Check | Covers |
|-------|--------|
| `00_boot`, `01_jdtls_ready` | config loads as `nv4j`, paths, jdt.ls attaches and imports with zero errors |
| `10_completion_latency` | warm and cold latency against budgets |
| `11_completion_ranking` | where the expected item sits, noise and snippet rules |
| `12_usage_index` | the ripgrep counts and their failure handling |
| `20_java25` | JDK selection, Java 25 and Java 21 projects |
| `30_diagnostics` | diagnostics, build file errors, unused imports with errors |
| `31_imports` | auto-import, grouping, organize imports |
| `32_code_actions` | quick fixes, generate, extract, Lombok |

Budgets: warm completion p95 at most 150 ms per case; first completion after ready at most 400 ms; expected item in the top 5 plus a relative rule per case; diagnostics at most 3 s from edit to screen; import accept at most 1.5 s; one code action round trip at most 1 s. The fixture is `tests/fixtures/demo`, planted broken sources are in `tests/fixtures/planted/*.java.txt` and are loaded into a buffer in memory only, never written to disk.

### What is measured and what you must judge

Measured by the checks: everything in the Capabilities tables, as time from request or edit until the data is in Neovim (including blink.cmp's own sort and the diagnostic store).

Not measurable headless, so you decide by feel in a real session: menu drawing and colors, how typing feels at your real project's size, documentation popup timing and its `completionItem/resolve`, signature help, ghost text, inline diagnostic redraw, and the real keystroke to screen time. If something feels slow, use `:CompletionProfile on`, reproduce, and look at the file. The fixture is small; a project 10 times bigger can behave differently.

## Logs

Everything temporary is under `/tmp/nv4j/` (macOS clears `/tmp` from time to time, nothing there is needed after a run):

| Path | Content |
|------|---------|
| `/tmp/nv4j/logs/test-<timestamp>.log` | full output of `tests/run.sh` |
| `/tmp/nv4j/logs/lsp.log` | Neovim LSP client log |
| `/tmp/nv4j/logs/latency.jsonl` | timing samples written by the checks |
| `/tmp/nv4j/jdtls-data/<project>-<hash>/` | jdt.ls workspace; its own log is `.metadata/.log` inside |
| `/tmp/nv4j/jdtls-config/<project>-<hash>/` | jdt.ls writable config copy |

The test run keeps its blink.cmp state in `/tmp/nv4j/state` so your own accepted completions never change test results, and never receives yours.

## Troubleshooting

| Symptom | What to do |
|---------|-----------|
| jdt.ls does not start | `<leader>cl` (LSP info), then read `/tmp/nv4j/logs/lsp.log` and `/tmp/nv4j/jdtls-data/<project>-<hash>/.metadata/.log`. Check `:Mason` that `jdtls` is installed. |
| Error "no JDK >= 21 found for jdtls. Searched: ..." | Install one: `sdk install java 25-amzn` (or any 21+), or set `JAVA_HOME` to a JDK 21+ before starting. The message lists the folders searched. |
| No ranking boost from project usage | `rg` is not on `PATH`. `brew install ripgrep`. Everything else still works. |
| Java files show strange old errors, or the project looks stuck | Quit Neovim, `rm -rf /tmp/nv4j/jdtls-data`, start again (the next start re-imports, about 15 s). |
| Red `pom.xml` notification | Read it, it is jdt.ls's reason (malformed XML, missing artifact). Fix the pom; it reloads on save with no prompt. |
| First start errors about tree-sitter parsers | Install the CLI: `brew install tree-sitter-cli`, then `:TSUpdate`. |
| `tests/run.sh`: "symlink missing" | Run the `ln -s` step from Install. |
| `tests/run.sh`: "JDK 25 not found" | `sdk install java 25-amzn`; the fixture needs a JDK 25 compiler. |

## Known limitations

- **Accept can wait up to about 0.8 s** the first time you accept a well documented type (`List`, `HashMap`, `ObjectMapper`) that the doc popup has not loaded yet. jdt.ls sends the auto-import only together with the javadoc, and blink waits up to 1.5 s for it so the import is never lost. Planned fix: apply the import asynchronously when the late resolve returns (`specs/features/diagnostics-imports-actions.md`, "Planned follow-ups"), with the P3 plan.
- **Frecency can blur ranking.** blink.cmp remembers what you accepted and boosts those labels, even with an empty prefix. After accepting `List` several times, `@` can show annotation noise first and push `RestController` far down. The checks are isolated from this, your own session is not. Planned: weight jdt.ls relevance and project usage above frecency for Java (`specs/002-p1-completion.md`, Follow-ups).
- **Usage counts are by name**, not resolved references: `save` on any receiver counts. They need `rg`.
- **Prefix-less `@`** gives `RestController` at 4 because the project uses annotations. In a project that has never used an annotation the list is jdt.ls's order. Typing one letter fixes it.
- **Unused local in a method that has an error** is not reported (jdt.ls skips that method). Unused imports are handled (Nv4J's own pass). That pass also treats a fully qualified use or the same name used as a local as a use, so it can miss an unused import (a false negative, not a false alarm).
- **Cosmetic gaps vs IntelliJ:** a blank line between every import group, `Objects.hash(name, Integer.valueOf(age))`, `toString` without quotes around strings, a numbered prompt for field selection.
- **Cold request edge:** the 400 ms first-completion budget is measured 1 s after jdt.ls is ready. A completion in that first second, or right after a `pom.xml` change reloads the project in the same session, can still cost 0.7 to 0.9 s once. A first-ever import of a project takes longer (about 15 s).
- **Only the project's own `pom.xml` and `.sdkmanrc` decide the project JDK.** A `release` inherited from a parent pom (not the Spring Boot starter parent) is not seen and falls back to `$JAVA_HOME` or the newest JDK.
- **Format-on-save is off** (`vim.g.autoformat = false`), and the Prettier extra was dropped, so YAML/JSON/Markdown such as `application.yml` do not format on save. `<leader>cf` formats Java and XML through the language servers.
- **Plugins update on their own:** lazy.nvim checks for updates in the background (it does not install them). `nvim/lazy-lock.json` pins what the tests ran with.
- **Terminal needs:** `<C-m>` needs the kitty keyboard protocol, `<D-Left>`/`<D-Right>` and Cmd+bracket terminal keys are for kitty on macOS.
- **Test harness limits:** the latency checks type each case in one step, not key by key (two cases cover the typed path); `lsp.complete` in the harness sends no completion context, the ranking path uses blink's own.

Each later plan (P2, P3, P4) updates the Capabilities and Not yet sections as its last task.
