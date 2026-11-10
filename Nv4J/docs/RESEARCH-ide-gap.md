# Research: framework-agnostic Java IDE features vs Nv4J

Date: 2026-11-10. Read-only research; nothing run against jdt.ls. Spring and JPA features are out of scope.

## How to read this

- **Nv4J today** is taken from `docs/KEYS.md`, `docs/TODO.md`, `nvim/lua/config/keymaps.lua`, `nvim/lua/plugins/*.lua`, `nvim/lua/nv4j/*.lua`, `nvim/lazyvim.json` and `tests/checks/`. "LazyVim" means the key comes from LazyVim / the `lang.java` and `dap.core` extras that Nv4J enables (`nvim/lazyvim.json`), not from Nv4J code. "MISSING" means I grepped `nvim/`, `specs/`, `docs/`, `README.md` for the feature name and found nothing; it does not prove a LazyVim or plugin default does not exist (see section C).
- **Sources** (S1..S9 are used in the table):
  - S1 = jdt.ls source, `~/.cache/nv4j/eclipse.jdt.ls/org.eclipse.jdt.ls.core/src` (commit `b52e20a`). Files used: `.../handlers/` (the handler list), `.../corrections/CorrectionMessages.properties` (quick fixes and assists), `.../text/correction/SourceAssistProcessor.java` (source actions), `.../preferences/Preferences.java` (settings), `.../commands/` (refactor commands: `extractMethod`, `extractField`, `extractConstant`, `extractVariable(AllOccurrence)`, `extractInterface`, `introduceParameter`, `changeSignature`, `convertVariableToField`, `convertAnonymousClassToNestedCommand`, `invertVariable`, `moveFile/Type/InstanceMethod/StaticMember`, `assignField/assignVariable`).
  - S2 = installed jdt.ls: `~/.local/share/nv4j/mason/packages/jdtls` (plugins dir has buildship, m2e, lombok.jar; bundles java-debug-adapter and java-test are in `mason/packages`).
  - S3 = IntelliJ pinned sources `~/.cache/nv4j/intellij-community` (commit `b633034bb`). This checkout is partial: `java/java-impl-refactorings/src/com/intellij/refactoring/{changeSignature,inline,move,rename,safeDelete}` and `java/java-backend/resources/META-INF/JavaPlugin.xml` only. No inspection, intention, postfix or live-template sources are present, so those IntelliJ claims are from knowledge or docs and marked (K).
  - S4 = https://code.visualstudio.com/docs/java/java-editing (fetched)
  - S5 = https://code.visualstudio.com/docs/java/java-refactoring (fetched)
  - S6 = https://code.visualstudio.com/docs/java/java-debugging (fetched)
  - S7 = https://www.jetbrains.com/idea/features/editions_comparison_matrix.html (fetch returned only a title; edition split below is (K), see C)
  - S8 = https://netbeans.apache.org/download/nb126/ and the NetBeans site feature pages (search results only; details (K))
  - S9 = Nv4J's own `specs/features/refactors.md` (the IntelliJ audit of rename/move)
  - (K) = from my own knowledge, not verified in this session.
- IntelliJ column: CE = Community, U = Ultimate only. NetBeans column is the weakest (no local source, 404 on the KB page): treat as (K).
- Effort: S under half a day, M 1-3 days, L more. Value: for a daily Spring/Java developer.

## A. Feature table

### A1. Editing and completion

| Feature | IntelliJ | NetBeans | Eclipse JDT / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Basic completion with auto-import | CE | yes | yes (S4) | DONE: blink + jdt.ls, async import (D24), checks 10, 11, 31 | - | - | - |
| Ranking by usage | CE (PreferMostUsedWeigher, used as the model in D11) | partial | IntelliCode (S4) | DONE: `nv4j/usage.lua` | - | - | - |
| Postfix templates (`.var`, `.if`, `.for`, `.nn`) | CE (K) | yes (K) | jdt.ls postfix completions, default on (S1 `Preferences.java` postfixCompletionEnabled = true) | UNVERIFIED: not turned off in config, so probably present; no check | Open a Java file, type `list.for` and look at items; add a check | S | medium |
| Live templates (`sout`, `psvm`, `fori`) | CE | yes | jdt.ls snippets (S4) | PARTIAL: blink + friendly-snippets (`plugins/blink.lua`); no Java-specific check | Verify friendly-snippets java set loads; custom snippets in `snippets/java.json` | S | medium |
| Smart / chain completion (type-aware, `a.b().c()` chains) | CE smart + chain | partial | jdt.ls `java.completion.chain.enabled` exists (S1), default unverified | MISSING (setting not set) | Set `java.completion.chain.enabled=true`, check latency budget (D13) | S | low |
| Guess method arguments | CE | no | yes | DONE: `guessMethodArguments=insertBestGuessedArguments` | - | - | - |
| Static member favourites | CE | no | yes | DONE: `favoriteStaticMembers` (Assert, Mockito, AssertJ...) | - | - | - |
| Import order and star threshold | CE | yes | yes | DONE: `IMPORT_ORDER`, thresholds 99 | - | - | - |
| Organize / optimize imports | CE | yes | yes | DONE: `<leader>co`, check 31; unused imports while errors (D8) | - | - | - |
| Optimize imports on save / paste | CE | no | `java.saveActions.organizeImports`, `java.updateImportsOnPaste.enabled` (S1) | Save: off by ruling (D10). Paste: not set | Set `updateImportsOnPaste`; Neovim paste is a plain put, jdt.ls client support is VS Code only (K) | M | low |
| Expand / shrink selection | CE | yes | VS Code smart selection (S4); jdt.ls `selectionRange` handler (S1) | DONE: `<C-d>` + vim-expand-region; LSP `selectionRange` use UNVERIFIED | - | - | - |
| Parameter name inlay hints | CE | yes | yes (S1 `InlayHintsHandler`) | PARTIAL: LSP inlay hints available, off by default, toggle `<leader>uh` (`plugins/lsp.lua`) | - | - | low |
| Semantic highlighting | CE | yes | yes (S4) | UNVERIFIED (Neovim default consumes semantic tokens; not checked) | `:Inspect` in a Java buffer | S | low |
| Folding | CE | yes | jdt.ls foldingRange (S1) | DONE: `<A-->`/`<A-+>` (`keymaps.lua`) | - | - | - |
| Surround with (try/catch, if, for) | CE | yes | quick assist "Surround with try/catch" (S1 messages) | PARTIAL: via `<leader>ca` on a selection; no check | Check 32 add case | S | medium |
| Move line / duplicate line / comment | CE | yes | yes | DONE: `<A-Up/Down>`, `<C-S-d>`, `<D-/>` | - | - | - |
| Multiple cursors | CE | yes | yes | MISSING (Neovim has `cgn`/visual-block; no plugin) | multicursor.nvim / vim-visual-multi | S | low |
| Smart enter / complete statement (`Ctrl+Shift+Enter`) | CE | partial | jdt.ls `java.edit.smartSemicolonDetection.enabled` (S1) | MISSING | Custom map: append `;` and open line; M | M | medium |
| On-type formatting, auto-indent | CE | yes | `java.format.onType.enabled` (S1) | UNVERIFIED | `:set indentexpr?`; treesitter indent | S | low |
| Auto-close brackets / quotes | CE | yes | - | DONE: mini.pairs (LazyVim) | - | - | - |
| Rename tags / surround | - | - | - | DONE: mini.surround, ts-autotag | - | - | - |

### A2. Code generation

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Getters / setters | CE | yes | yes (S5, S1 `GenerateGetterSetterAction`) | DONE: `<leader>ca`, check 32 | - | - | - |
| Constructor (from fields, super) | CE | yes | yes | DONE: check 32 | - | - | - |
| equals / hashCode | CE | yes | yes; Nv4J sets `useJava7Objects` | DONE + preselect all fields (`nv4j/codegen.lua`) | - | - | - |
| toString | CE | yes | yes, template configured | DONE | - | - | - |
| Override / implement methods | CE | yes | yes ("Override/Implement Methods", S5) | DONE ("implement methods", check 32); override picker via `<leader>cA` UNVERIFIED | - | - | - |
| Delegate methods | CE | yes | yes (S5, `GenerateDelegateMethodsAction`) | UNVERIFIED (jdt.ls offers it; no check) | Add to check 32 | S | low |
| Builder generation | CE via plugin / refactor "Replace constructor with builder" (K) | no | not in jdt.ls (grep S1 found only unrelated "Builder" text) | MISSING | Lombok `@Builder` works with the agent (S2); custom Lua template | M | low |
| Lombok support | plugin bundled in CE (K) | plugin | jdt.ls with lombok agent | DONE: Mason lombok.jar via LazyVim java extra, check 32 | - | - | - |
| Record / enum / interface / annotation creation | CE | yes | yes | DONE: `<leader>jn` scaffold, check 61 | - | - | - |
| Create class / method / field from usage | CE | yes | yes (S1 quick fixes "Create ...") | DONE: check 32 | - | - | - |
| Generate test for class | CE | yes (K) | VS Code "Generate tests with Copilot" only | DONE: `<leader>jt` creates an empty test class | - | - | - |
| Generate Javadoc comment | CE | yes | jdt.ls javadoc completion (`JavadocCompletionProposal`, S1) | PARTIAL: `/**` completion exists in jdt.ls; not checked | Check: `/**` + Enter in a method | S | low |
| Sort members | CE (Rearrange code) | yes | jdt.ls Source "Sort members" (`SortMembers_*` in S1) | UNVERIFIED (reachable via `<leader>cA`) | Check on a fixture | S | low |
| Make fields/params `final` | inspection | hint | Source action "Change modifiers to final" (S5) | UNVERIFIED via `<leader>cA` | - | S | low |
| Convert class to record | CE (K) | hint (K) | jdt.ls `ConvertRecordSubProcessor` (S1) | UNVERIFIED | Fixture check | S | low |
| Convert to / from text block | CE | yes (K) | cleanup actions (`java.cleanup.actions`, S1) | MISSING (settings not set) | Enable cleanups; `java.saveActions.cleanup` | S | low |

### A3. Refactoring

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Rename (symbol) | CE | yes | yes | DONE: `<F2>`, `<leader>cr` | - | - | - |
| Rename class / package with files, tests, variables | CE | yes | partial | DONE and audited against IntelliJ: `<leader>jr`, `<leader>jp`, check 62, S9 | - | - | - |
| Move class / package | CE | yes | yes | DONE `<leader>jm` (known diffs in S9: several classes, nested class) | - | - | - |
| Extract method | CE | yes | yes (S5) | DONE `<leader>cxm` (visual); check 32 | - | - | - |
| Extract variable (+ all occurrences) | CE | yes | yes | DONE `<leader>cxv` | - | - | - |
| Extract constant | CE | yes | yes | DONE `<leader>cxc` | - | - | - |
| Extract field | CE | yes | yes (S5) | UNVERIFIED (code action, no key) | `<leader>ca` in visual | S | medium |
| Extract parameter / introduce parameter | CE | yes | jdt.ls `introduceParameter` (S1) | UNVERIFIED | Check via code action | S | medium |
| Extract interface | CE | yes | jdt.ls `extractInterface` (S1) | UNVERIFIED | Check; needs a prompt handler in nvim | M | low |
| Extract superclass / delegate | CE | yes | not in jdt.ls (grep S1 found no handler) | MISSING, no server support | Would need own refactoring on top of text edits | L | low |
| Inline method / variable / constant | CE | yes | yes (S5) | DONE `<leader>ji`, check 62 | - | - | - |
| Change signature | CE | yes | yes (jdt.ls `changeSignature`) | DONE `<leader>js` (5 s ceiling for hierarchy) | - | - | - |
| Safe delete | CE | yes | no in jdt.ls | DONE (own) `<leader>jd` | - | - | - |
| Pull members up / push down | CE | yes | Eclipse JDT UI has it; jdt.ls does not (grep S1: no pullUp/pushDown) | MISSING, no server support | Own Lua over `textDocument/references` + edits | L | low |
| Move instance / static method | CE | yes | jdt.ls `moveInstanceMethod`, `moveStaticMember` (S1) | MISSING (no key) | Wire code actions with a target picker | M | low |
| Convert anonymous class to lambda | CE | yes | yes (S1 "Convert to lambda expression") | UNVERIFIED via `<leader>ca` | Check | S | medium |
| Convert lambda to method reference | CE | yes | yes (S1 "Convert to method reference") | UNVERIFIED | Check | S | low |
| Convert local variable to field | CE | yes | yes (S1) | UNVERIFIED | Check | S | low |
| Invert if / boolean (S1 `InvertBooleanUtility`) | CE | yes | yes | UNVERIFIED | Check | S | low |
| Encapsulate field | CE | yes | yes (S1 "Encapsulate Field") | UNVERIFIED | Check | S | low |
| Introduce parameter object / replace constructor with factory | CE | no | no | MISSING, no server support | - | L | low |
| Undo a refactoring as a unit | CE | yes | no | DONE (own): `<leader>ju` | - | - | - |
| Refactoring preview | CE | yes | VS Code partial | MISSING (jdt.ls applies edits directly) | Show changed files list (Nv4J lists touched files already) | M | low |
| Search in comments / strings on rename | CE | yes | no | MISSING (open in `docs/TODO.md`) | Ripgrep pass + prompt | M | low |

### A4. Navigation

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Go to definition / type / implementation / declaration | CE | yes | yes | DONE: `gd`, `gI`, `gy`, `<F12>`, `<C-Down>` | - | - | - |
| Go to super method | CE | yes | yes (`findLinks` handler, S1) | DONE `<leader>cgs` | - | - | - |
| Find usages | CE | yes | yes | DONE `gr`, `<C-Up>` (Telescope/Trouble) | - | - | - |
| Find usages split read / write, filter by scope | CE | partial | no | MISSING | Filter `textDocument/documentHighlight` kinds (jdt.ls returns Read/Write) | M | low |
| Type hierarchy | CE | yes | yes (`TypeHierarchyHandler`, S1) | DONE (no tree UI): `<leader>cS`, `<leader>cP` | - | - | - |
| Call hierarchy | CE | yes | yes (`CallHierarchyHandler`) | DONE: `<leader>ci`, `<leader>cO` | - | - | - |
| Go to class / symbol / file / action (search everywhere) | CE | yes | yes | PARTIAL: `<leader>ss`, `<leader>sS`, `<C-p>`; no "everything" mix | Telescope pickers exist | - | - |
| File structure / outline | CE | yes | yes | PARTIAL: `<C-m>` (needs kitty protocol), `<leader>ss`; no persistent outline sidebar (grep aerial: none; Trouble symbols from LazyVim UNVERIFIED) | aerial.nvim or Trouble `symbols` | S | medium |
| Recent files / locations | CE | yes | yes | DONE: `<leader>fr`, `<C-e>` | - | - | - |
| Bookmarks | CE | yes | yes (VS Code ext) | MISSING (grep "bookmark": none) | harpoon / marks | S | low |
| Back / forward navigation | CE | yes | yes | DONE: `<D-Left/Right>` | - | - | - |
| Navigate into library sources / decompiled | CE (decompiler built in) | yes | sources jar only; decompiler is a separate extension (K) | YES (corrected 2026-11-10, was "no decompiler"): jdt.ls 1.63.0 bundles IntelliJ's Fernflower and uses it for every class without a sources jar (`docs/RESEARCH-decompiler.md`); a Maven project fetches a missing sources jar lazily on navigation (jdt.ls `MavenSourceDownloader`, no setting); `java.eclipse.downloadSources=true` sent; CFR 0.152 as a backup when Fernflower fails (`nv4j/decompile.lua`, `specs/features/library-navigation.md`, check 95) | `java.maven.downloadSources` left off: it is an eager download of every dependency at import (m2e), not lazy; `vim.g.nv4j_maven_download_sources` turns it on | done | high |
| Go to test / go to subject | CE | yes | `jdtls.tests.goto_subjects` | DONE `<leader>jt`, `<leader>cgS` | - | - | - |
| Find usages of a file / quick doc / quick definition | CE | yes | hover | DONE `K` | - | - | - |
| Highlight usages in file | CE | yes | documentHighlight | UNVERIFIED (LazyVim illuminate-like `]]`/`[[` exist) | - | - | - |
| Show implementations code lens | CE gutter | yes | `java.implementationCodeLens` (S1) | PARTIAL: references lens on (`referencesCodeLens`), implementations lens not set | Set `implementationCodeLens=all`; S | S | medium |

### A5. Inspections and quick fixes

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Compile errors / warnings live | CE | yes | ECJ | DONE, check 30 (< 3 s) | - | - | - |
| Unused import / local / private member | CE | yes | ECJ (+ Nv4J D8) | DONE; "0 references" lens | - | - | - |
| Quick fix catalogue (~100 fixes: add throws, surround, create, cast...) | CE (K) | yes | jdt.ls `CorrectionMessages.properties` (S1): add throws, try/catch, add cases, remove unused, replace with null check, etc. | DONE via `<leader>ca`, check 32 | - | - | - |
| Null analysis (`@Nullable` / `@NonNull`) | CE annotations + inspection | partial | `java.compile.nullAnalysis.*` (S1) | MISSING (not configured) | Set mode `automatic` + nullable/nonnull lists (Spring annotations) | S | medium |
| Redundant code / "can be replaced with" (hundreds of IntelliJ inspections) | CE ~800 (K) | ~hints | ECJ + a few assists | MISSING mostly: ECJ only | Cleanup actions; SonarLint-ls is the only broad option (K) | L | medium |
| Convert loops to streams and back | CE | yes (K) | no (jdt.ls cleanup `lambdaExpression` only) (K) | MISSING | None in jdt.ls (K) | L | low |
| Java version migration (var, switch expr, text blocks, records, pattern matching) | CE (K) | hints | cleanup actions (K) | MISSING | `java.cleanup.actions` list; code actions | M | low |
| Static analysis: SpotBugs / PMD / Checkstyle | plugins | plugins | extension (VS Code checkstyle) | MISSING (grep: none) | nvim-lint + checkstyle/pmd CLI via Mason | M | medium |
| Duplicate code / data flow analysis | U (K) | no | no | MISSING | - | L | low |
| Suppress warnings quick fix | CE | yes | S1 `SuppressWarningsSubProcessor` | DONE via `<leader>ca` UNVERIFIED | - | - | - |
| Problems view (project-wide) | CE | yes | Problems panel | DONE: Trouble `<leader>xx` (open files + workspace diagnostics UNVERIFIED) | - | - | - |

### A6. Formatting and code style

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Reformat file / selection | CE | yes | jdt.ls formatter (S1 `FormatterHandler`) | DONE `<leader>cf`, on demand only | - | - | - |
| Import project style (Eclipse XML profile) | CE import | no | `java.format.settings.url` (S1) | MISSING (not set) | Point setting to a profile; per-project via `.nv4j` JSON | S | medium |
| `.editorconfig` | CE | yes | jdt.ls: not found in S1 (grep shows none); Neovim reads `.editorconfig` natively for indent | PARTIAL (Neovim built-in applies indent, not formatter rules) | - | - | low |
| google-java-format | plugin | plugin | VS Code ext | MISSING (grep: none) | conform.nvim formatter (LazyVim ships conform) with the jar via Mason | S | medium |
| Spotless / Checkstyle on build | plugin | plugin | via build | MISSING | Run `mvn spotless:apply` in a terminal (`<leader>tn`) | S | medium |
| Optimize / cleanup on save | CE | yes | `java.saveActions.cleanup` (S1) | MISSING (D10 keeps organize imports off) | Per-project opt-in | S | low |
| Code style hierarchy (file header, templates) | CE | yes | `java.templates.fileHeader` (S1) | PARTIAL: scaffold templates (`nv4j/scaffold.lua`) | - | - | low |

### A7. Build tools

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Import Maven / Gradle project, multi-module | CE | yes | m2e + buildship in jdt.ls (S2) | DONE, checks 67-75 | - | - | - |
| Reload on pom/gradle change | CE | yes | yes | DONE (`updateBuildConfiguration=automatic`, `buildfile.lua`) | - | - | - |
| Build errors visible | CE | yes | yes | DONE ("Build file" error, check 71) | - | - | - |
| Maven lifecycle / goals tool window | CE | yes | VS Code "Maven" view | MISSING: terminal only (`<leader>tn`, `<leader>rS`) | `java.configuration.maven.*` has no goals API; overseer.nvim / Telescope picker over lifecycle phases + `mvn help` (K) | M | high |
| Gradle task list / run | CE | yes | VS Code Gradle ext | MISSING: `bootRun` only | Parse `./gradlew tasks --all`, pick, run in terminal | M | medium |
| Dependency tree / analyzer / conflicts | U for graph (K); CE has Maven tool window tree | yes | VS Code Maven view tree | MISSING (grep "dependency tree": none) | Run `mvn dependency:tree` / `gradlew dependencies` into a scratch buffer with filter | S | high |
| Add dependency (from search) | CE (Maven Central search) (K) | yes | VS Code "Add dependency" ext | MISSING | Telescope over search.maven.org API (K) | M | medium |
| Dependency version updates | CE inspection (K) | no | ext (Dependabot-style) | MISSING | `mvn versions:display-dependency-updates` in scratch buffer | S | medium |
| Profiles toggle (Maven) | CE | yes | yes | PARTIAL: Spring profile for run only (`<leader>rp`); Maven profile not | Set `-P` via `.nv4j` run settings (extend D27) | M | medium |
| Offline mode / settings.xml | CE | yes | `java.configuration.maven.userSettings` (S1) | MISSING (defaults) | Settings only | S | low |
| Maven wrapper / Gradle wrapper | CE | yes | yes | DONE for Gradle wrapper (D31) | - | - | - |
| Download sources/javadoc | CE | yes | `java.maven.downloadSources`, `java.eclipse.downloadSources` (S1) | MISSING (not set; see A4) | Two settings | S | high |
| pom.xml editing (completion of GAV, XML) | CE/U | yes | VS Code Maven ext | PARTIAL: lemminx for XML (Mason) | - | - | low |

### A8. Testing

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Run / debug test at cursor, class, project | CE | yes | yes | DONE `<leader>tr/tt/tp/td`, check 60 | - | - | - |
| Rerun failed / last | CE | partial | yes | DONE `<leader>tf/tl` | - | - | - |
| Results tree with counts, nested and parameterized | CE | yes | yes | DONE (2026-11-10): `<leader>tv` / `:Nv4JTestResults`, failed first, per-test time, message, trace, stdout, rerun one / failed, checks 93 and 94; counts + quickfix (`<leader>to`) stay. Not shown: a class > method hierarchy (flat list, nested and parameterized tests are separate rows) | - | - | - |
| JUnit 4 / 5, TestNG | CE | yes | yes | JUnit 4 and 5 DONE; TestNG via `<leader>tT` only | - | - | - |
| Coverage run + line markers | CE (IntelliJ runner / JaCoCo) | yes (JaCoCo plugin) | VS Code "Test coverage" (K) | MISSING (grep "coverage" hits only notes) | JaCoCo agent into the test JVM + parse `jacoco.xml` into signs; or `mvn jacoco:report` | L | medium |
| Test generation | CE (template); Ultimate AI (K) | yes | no | DONE (empty class, `<leader>jt`) | - | - | - |
| Parameterized test names, display names | CE | yes | yes | DONE (nested names parsed) | - | - | - |
| Run test from gutter icon | CE | yes | yes | PARTIAL: keys only; no gutter | Code lens `Run Test` from java-test (`<leader>cc`) UNVERIFIED | S | low |
| Watch / continuous test | U (K) | no | VS Code "auto run" | MISSING | autocmd on `BufWritePost` -> `<leader>tl` | S | low |
| Test in a Gradle build (own runner) | CE | yes | yes | By decision D28 no `gradle test` runner | - | - | - |

### A9. Debugging

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Line breakpoint, step, run to cursor | CE | yes | yes | DONE: `<leader>db/dO/di/do/dC`, check 40 | - | - | - |
| Conditional breakpoint | CE | yes | yes (S6) | DONE `<leader>dB` | - | - | - |
| Logpoint (log message without stopping) | CE | partial | yes (S6) | MISSING in Nv4J keys (nvim-dap supports `set_breakpoint(nil, nil, msg)`; grep "logpoint": none) | One key in `keymaps.lua`; java-debug supports logMessage (K) | S | high |
| Hit count breakpoint | CE | yes | java-debug supports `hitCondition` (K) | MISSING key | nvim-dap `set_breakpoint(cond, hit)` | S | medium |
| Exception breakpoint | CE | yes | yes (S6 "exceptions") | MISSING (grep: none; nvim-dap `set_exception_breakpoints`) | Key to toggle "caught/uncaught/all" | S | high |
| Method breakpoint | CE (slow) | yes | no in java-debug (K) | MISSING, low value | - | - | low |
| Field watchpoint / data breakpoint | CE | yes | VS Code "data breakpoints" (S6) | MISSING | java-debug `dataBreakpointInfo` (K) | M | low |
| Evaluate expression, watch | CE | yes | yes | DONE `<leader>de` (dap-ui), virtual text | - | - | - |
| Evaluate in condition with Java syntax | CE | yes | yes | UNVERIFIED | - | - | - |
| Hot code replace (HotSwap) | CE | yes | VS Code `java.debug.settings.hotCodeReplace` default `manual` (S6) | UNVERIFIED: not configured; java-debug supports it, nvim-jdtls provides `hotcodereplace` option (K) | Set `hotcodereplace = "auto"` in `jdtls.setup_dap`; build + check | S | high |
| Attach to remote JVM (host:port) | CE | yes | yes (S6) | MISSING (no config; nvim-dap `attach` config) | dap configuration `type=java request=attach hostName port`; prompt for port | S | high |
| Attach to local process (pick PID) | CE | yes | S6 | MISSING | dap attach with `processId` (java-debug supports through jdwp port discovery (K)) | M | low |
| Step filters (skip JDK, libs, constructors) | CE | yes | S6 `stepFilters` | MISSING | `stepFilters` in the dap config | S | medium |
| Stream debugger (trace chain) | CE (K) | no | no | MISSING, no protocol | - | L | low |
| Drop frame / reset frame | CE | yes | VS Code (K) | MISSING; nvim-dap `restart_frame` | One key | S | low |
| Smart step into | CE | yes | VS Code "step into targets" (K) | MISSING; nvim-dap `step_into({askForTargets=true})` | One key | S | low |
| Thread / frame view, variables, call stack | CE | yes | yes | DONE (dap-ui) | - | - | - |
| Debug run on Maven/Gradle test and Boot | CE | yes | yes | DONE: checks 40, 41, 89 | - | - | - |
| Debug-ready cleanup (no orphans) | - | - | - | DONE: `no_orphan` (checks 40, 41) | - | - | - |

### A10. Run configurations, SDK, profiling

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Run configs (named, VM args, env, program args) | CE | yes | launch.json | PARTIAL: one `.nv4j` JSON per project with profile, env, vm_args (D27); no named configs by ruling | - | - | - |
| Run main class | CE | yes | yes | DONE `<leader>rj` (terminal) | - | - | - |
| Run a single JShell / scratch file | CE (scratch) | JShell | JShell via ext | PARTIAL: scratch notes (not Java-run) | `jshell` in terminal; `:term jshell` | S | low |
| JDK discovery / switch per project | CE SDK table | yes | `java.configuration.runtimes` | DONE: `.sdkmanrc`, pom, Gradle toolchain (D7, D30) | - | - | - |
| Download JDK from IDE | CE | no | VS Code ext | MISSING (use SDKMAN in terminal) | `:!sdk install` wrapper | S | low |
| CPU / memory profiler | U (K) | built-in | VS Code JFR ext (K) | MISSING (grep "jfr": none for tooling; only warmup text) | Launch with `-XX:StartFlightRecording` flag via `.nv4j` vm_args and open the `.jfr` with `jfr print` / JMC | S (flag), L (UI) | medium |
| Heap dump / thread dump | U (K) | yes | no | MISSING | `jcmd <pid> Thread.print` in a terminal key | S | medium |
| Memory indicator for the IDE | CE | yes | - | DONE: warning at 2 GB (`memwatch.lua`) | - | - | - |

### A11. Documentation, VCS, tools

| Feature | IntelliJ | NetBeans | Eclipse / VS Code | Nv4J today | How in Neovim | Eff | Value |
|---|---|---|---|---|---|---|---|
| Quick documentation (Javadoc popup) | CE | yes | yes (S1 `java.hover.javadoc.enabled`) | DONE `K` | - | - | - |
| Parameter info | CE | yes | yes | DONE `gK`, `<C-k>` | - | - | - |
| Javadoc generation | CE | yes | no | MISSING | `mvn javadoc:javadoc` in terminal | S | low |
| Rendered Javadoc in editor | CE | no | no | MISSING | render-markdown is for markdown only | L | low |
| Git: blame, diff, hunks, stage | CE | yes | yes | DONE: gitsigns (`<leader>ghb/ghs/ghr`, `<leader>ghi`) | - | - | - |
| Git: history of file / line, log, compare with branch | CE | yes | partial | PARTIAL: `<leader>gs`, `<leader>gc`; per-file history UNVERIFIED (LazyVim) | diffview.nvim | S | medium |
| Local history (not Git) | CE | yes | VS Code timeline | MISSING; Neovim undo files cover part | `undofile` + undotree | S | low |
| Merge conflict tool | CE | yes | yes | MISSING | diffview / git-conflict.nvim | S | medium |
| Language injection (SQL / JSON / regex in strings) | U (CE for regex) (K) | no | no | PARTIAL: treesitter injections for SQL in strings UNVERIFIED; JPQL done separately | treesitter injection queries | S | low |
| HTTP client (`.http` files) | U (K) | no | VS Code REST ext | MISSING | kulala.nvim (K) | M | medium |
| Database tools | U (K) | yes | ext | MISSING (mention only) | vim-dadbod-ui | M | low |
| Docker / Compose | U (K) | yes (K) | ext | MISSING | terminal | S | low |
| Remote dev / SSH / containers | U Gateway (K) | no | VS Code Remote | N/A: Neovim over SSH or tmux | - | - | - |
| TODO tool window | CE | yes | yes | DONE: todo-comments (LazyVim) | - | - | - |
| Terminal inside the IDE | CE | yes | yes | DONE | - | - | - |
| AI assistance | JetBrains AI (paid) | no | Copilot | DONE: Claude, Cursor (`<leader>a*`; never run live, TODO) | - | - | - |
| Spell check / typo | CE | yes | no | MISSING; `vim.opt.spell` + treesitter | Low | S | low |
| Plugin ecosystem | yes | yes | yes | lazy.nvim | - | - | - |
| Android/Kotlin/Groovy | Android Studio / CE | partial | ext | OUT OF SCOPE | - | - | - |

Feature rows: 164 (counted in the tables above). JetBrains Fleet, Android Studio and the Eclipse JDT UI wizards (as opposed to jdt.ls) were not compared row by row: Fleet uses its own backend (K), and Eclipse JDT UI has pull up / push down, extract superclass and "use supertype" that jdt.ls dropped.

## B. Top 15 gaps worth closing

Ordering: value for a daily developer first, then effort. Each has the exact test. All tests use the repo's style (headless nvim with a check in `tests/checks/NN_name.lua`, plus a control that must fail with the feature off). jdt.ls tests need a real run.

1. **Library sources / decompiler (go to definition into a jar shows real code).** Set `java.eclipse.downloadSources` and `java.maven.downloadSources` to true; add a decompiler bundle (S1 shows no decompiler). Test: new check on `tests/fixtures/demo`; open a class that calls `org.springframework.util.StringUtils.hasText`, run `vim.lsp.buf.definition()`, wait for a `jdt://` buffer; assert it contains the text `public static boolean hasText` and not `// Failed to get sources` (and that line count is over 20). Control: setting off must fail the assertion.
2. **Hot code replace.** Set `hotcodereplace = "auto"` for jdtls DAP. Test: extend check 40: launch a main that prints a `static String msg()` in a loop under the debugger, change the method body on disk, trigger build (the `refresh_and_build` path), assert the debuggee's later output contains the new string without restart and no `hotcodereplace` failed event in the dap log. Control: setting `never` keeps the old string.
3. **Logpoints, exception breakpoints, hit count (one key family).** Keys `<leader>dL` (log message), `<leader>dX` (exception breakpoints: caught/uncaught). Test: in `40_debug`, set a logpoint at a line in the test fixture main, run, assert the debug console/REPL output contains the message and that the session did not stop (no `stopped` event for that line); exception test: throw `IllegalStateException` in fixture, assert `stopped` with reason `exception` at that frame.
4. **Attach to a remote JVM.** Key `<leader>da` asks host and port and starts an `attach` config. Test: start the fixture main with `-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005` from the check, call the Nv4J attach function with port 5005, set a breakpoint, trigger it, assert `stopped` at the line; assert terminate leaves the debuggee running (attach must not kill it).
5. **Dependency tree / analyzer (Maven and Gradle) in a buffer with filter.** Key `<leader>mD` runs `mvn dependency:tree -Dverbose` or `gradlew dependencies` and opens a scratch buffer. Test: on the Maven fixture assert the buffer contains `spring-boot-starter` and a `[INFO]` free tree; on the Gradle fixture assert `runtimeClasspath` section; assert a conflict omitted line (`omitted for conflict`) is highlighted/listed when a pom forces a conflict (add a fixture pom with two versions).
6. **Maven lifecycle and Gradle task picker.** `<leader>mm` picks `clean|compile|test|verify|package|install` (and Gradle tasks from `gradlew tasks --all`) and runs in a terminal tab with the project's JDK. Test: run `compile` on the fixture, assert exit 0 and `target/classes/.../Foo.class` exists; assert `JAVA_HOME` of the run equals `nv4j.jdk` project JDK (read `ps eww` or echo env in a fixture exec-maven-plugin goal).
7. **Dependency update check and add dependency.** `mvn versions:display-dependency-updates` into a buffer; "add dependency" via Maven Central search API. Test (offline): feed a canned search JSON, pick an artifact, assert the pom.xml gains `<dependency>` with correct groupId, artifactId, version and jdt.ls re-imports (new type resolvable via `java.project.getClasspaths` or a diagnostic-free use). Online variant is a probe only.
8. **Null analysis for Spring annotations.** Set `java.compile.nullAnalysis.mode=automatic`, `nonnull`/`nullable` to Spring and JSpecify lists. Test: fixture method `void f(@NonNull String s)` called with `null`; assert a jdt.ls diagnostic of severity warning with text containing `Null type mismatch`. Control: mode `disabled` produces none.
9. **(DONE 2026-11-10, flat list, checks 93 and 94) Test results tree and re-run from tree.** Dedicated buffer with class > method > status, `<CR>` jumps to source, `r` reruns that node. Test: run fixture suite with one failing and one parameterized test; assert tree lines (counts equal those in `tests.lua` summary), `<CR>` on the failing node puts the cursor on the assertion line, `r` reruns only that method (assert JUnit launcher args contain the method name).
10. **Coverage (JaCoCo).** Run tests with the jacoco agent, read `jacoco.exec`/XML, put signs (green/red) on lines. Test: fixture class with one covered and one uncovered branch; assert signs on exact lines via `vim.fn.sign_getplaced`; assert `<leader>tc` leaves no stale signs after the next run.
11. **File outline sidebar + type hierarchy tree.** aerial.nvim (outline) plus a tree view of `typeHierarchy` results. Test: open fixture class with 5 methods; assert the outline lists them in file order and `<CR>` jumps to the right line; hierarchy tree for an interface lists all implementers found by `textDocument/implementation`.
12. **Format with project style (google-java-format / Eclipse profile / `.editorconfig` check).** Provide `java.format.settings.url` from `.nv4j` and optional conform formatter. Test: unformatted fixture file with a style profile that uses 2 spaces; run `<leader>cf`; assert the exact expected text (golden file); control: without profile the text differs.
13. **Surround, extract field, introduce parameter, convert to lambda, convert to method reference, delegate, sort members: batch of already-offered jdt.ls code actions, proven and keyed.** Test: in `32_code_actions`, one case per action: request `codeAction` at a fixed range, assert the title from S1 appears (for example `Extract to field`, `Convert to lambda expression`, `Convert to method reference`, `Introduce Parameter`), apply, assert the resulting text compiles (no jdt.ls error diagnostics after 3 s).
14. **Implementation code lens and chain completion toggles.** Set `java.implementationCodeLens=all`; test: interface with 2 implementers shows a lens `2 implementations` (`vim.lsp.codelens.get` result), and `<CR>` or `gI` lists both. For chain completion: a completion probe asserting an item containing a two-call chain appears and warm p95 stays under the 150 ms budget (check 10).
15. **Profiling and thread-dump helpers.** `<leader>rJ` runs with `-XX:StartFlightRecording=filename=...,dumponexit=true`; `<leader>rT` runs `jcmd <pid> Thread.print` into a buffer. Test: run fixture main, send thread dump key, assert buffer contains `"main"` thread; run with JFR, stop, assert `.jfr` file exists and `jfr summary` lists `jdk.CPULoad` or `jdk.ExecutionSample`.

Close misses (not in top 15): Maven profile toggle; git file history/diffview; merge conflict tool; HTTP client (kulala); `updateImportsOnPaste`; multiple cursors; surround-with refinements.

## C. Claims I could not verify

1. The edition split of IntelliJ (HTTP client, database, profiler, coverage, Spring, language injection beyond regex as Ultimate-only). The JetBrains comparison page fetch returned only its title twice and the search gave an unreadable copy. Taken from memory (K).
2. Every NetBeans cell. The NetBeans KB URL returned 404; search returned only release notes of 12.x. Rows say "yes" where NetBeans is well known for it (K), none checked in this session.
3. IntelliJ inspections count (~800), postfix templates, live templates, stream debugger, intentions: the pinned IntelliJ checkout (S3) has none of those source folders, so they are knowledge (K).
4. ~~Whether a decompiler is bundled in the installed jdt.ls (S2). I found no decompiler in the source grep (S1) but did not list every plugin in `mason/packages/jdtls/plugins` beyond the first screen. The behaviour of `jdt://` without sources attached was not tested.~~ Answered 2026-11-10 (`docs/RESEARCH-decompiler.md`): it IS bundled (`wrapped.com.jetbrains.intellij.java.java-decompiler-engine_253.29346.240.jar`, provider `fernflowerContentProvider` in jdt.ls core's `plugin.xml`; S1 was a sparse checkout). A `jdt://` class without sources opens as Fernflower output; `specs/features/library-navigation.md`.
5. Whether `java.completion.chain.enabled` defaults to false: the field is declared and read in `Preferences.java`, but I did not find its initial value. Postfix defaulting to true is verified (line 1001).
6. Whether these jdt.ls code actions work in the Nv4J UI (extract field, introduce parameter, convert to lambda, delegate methods, sort members, record conversion, surround): offered by S1, but not proven in Nv4J (no check). `nvim-jdtls` prompts for some of them (extract interface, move) and the UI path may need a handler.
7. LazyVim defaults I did not exercise: `<leader>gf` (file history), Trouble symbols, `<leader>gg` lazygit (Nv4J enables the telescope extra; the snacks lazygit may or may not be present), illuminate-style reference highlighting, semantic tokens.
8. Hot code replace, logMessage, `hitCondition`, `stepFilters`, smart step-into, data breakpoints, attach by PID: that java-debug (S2 bundle) supports each is knowledge of its README (K); VS Code docs (S6) confirm hot code replace, logpoints, data breakpoints, remote attach, step filters for the VS Code client of the same adapter. That nvim-dap/nvim-jdtls can pass them was not tried.
9. That jdt.ls has no pull-up / push-down / extract-superclass: I only grepped S1 (`pullUp|pushDown` returned nothing; refactor command list above). A newer jdt.ls could add them.
10. Coverage in IntelliJ CE uses its own runner and JaCoCo (K). VS Code test coverage for Java (K).
11. Maven Central search API shape and kulala.nvim, diffview.nvim, aerial.nvim, overseer.nvim as suitable choices: not checked in this session (K).
12. The `lombok` row for IntelliJ ("bundled plugin") and `Builder` generation (K).
13. The `nvim/lazy-lock` and plugin versions: not inspected; the effort estimates S/M/L are my judgement.
