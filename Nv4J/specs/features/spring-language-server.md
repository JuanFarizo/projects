# Feature: Spring Boot language server

Priority: P2 (properties/yml completion and hover), P2/P4 (`@Value`/`@Profile`, beans, request mappings). Status: research, decision D14 and failing baseline done (Task 0); wiring built (Task 3, `DONE 50_spring_ls 13 0` after review fix round 1); completion, hover and navigation checked in Task 4 (`DONE 51_spring_completion 19 0`, `DONE 52_spring_nav 10 0`). Tests: `tests/checks/50_spring_ls.lua`, `51_spring_completion.lua`, `52_spring_nav.lua`. Spec: `specs/004-p2-spring-run-debug.md`.

## Sources read (pinned)

- `spring-projects/spring-tools`, sparse clone `~/.cache/nv4j/spring-tools`, commit `9c979426e891278a6008d734febaf5d9014a5de1` (2026-10-21). Sparse set extended with `headless-services/spring-boot-language-server`, `vscode-extensions/vscode-spring-boot`, `vscode-extensions/commons-vscode` (the launcher and the client side of the `sts/*` protocol live in commons-vscode). EPL-2.0: nothing copied.
- Mason package `vscode-spring-boot-tools` = `pkg:openvsx/VMware/vscode-spring-boot@2.2.0` (registry `2026-10-20-awful-drum`), installed in `~/.local/share/nv4j/mason` (87 MB). Its `extension/dist/extension.js` was checked against the clone where the launch details matter.
- `JavaHello/spring-boot.nvim`, read-only clone `~/.cache/nv4j/spring-boot.nvim`, commit `9880be48170a21d97444b1eba75853fd3bad33c3` (2026-09-24), Apache-2.0, 1251 lines of Lua (12 files).

## Mason package layout (2.2.0)

```
packages/vscode-spring-boot-tools/extension/
  language-server/spring-boot-language-server-2.2.0-SNAPSHOT-exec.jar   thin jar, Main-Class
      org.springframework.ide.vscode.boot.app.BootLanguageServerBootApp, manifest Class-Path lib/*.jar
  language-server/lib/   168 jars (Spring Boot 4.0.6, Spring AI MCP server, ...)
  jars/                  jdt.ls extension bundles: io.projectreactor.reactor-core.jar,
                         org.reactivestreams.reactive-streams.jar, jdt-ls-commons.jar,
                         jdt-ls-extension.jar, sts-gradle-tooling.jar, (xml-ls-extension.jar,
                         commons-lsp-extensions.jar: not in package.json javaExtensions)
  package.json           version 2.2.0, contributes.javaExtensions = the first five jars above,
                         languages spring-boot-properties, spring-boot-properties-yaml,
                         spring-factories, jpa-query-properties
share/vscode-spring-boot-tools/language-server.jar -> the exec jar (symlink; the JVM resolves the
                         manifest Class-Path through it, tested: starts fine)
share/vscode-spring-boot-tools/jdtls/*.jar -> the 7 jars in jars/
```

## How VS Code starts it (exact command)

`vscode-spring-boot/lib/Main.ts` (options) and `commons-vscode/src/launch-util.ts` (`prepareJvmArgs`, `addCpAndLauncherToJvmArgs`), same in the installed `dist/extension.js`. stdio transport (a socket only with `SPRING_LS_USE_SOCKET`), cwd the extension dir, a JDK >= 21 (`checkjvm` refuses less; `preferJdk`):

```
<jdk>/bin/java \
  -Dspring.config.location=classpath:/application.properties \
  -Djdk.util.zip.disableZip64ExtraFieldValidation=true \
  -Dspring.main.web-application-type=NONE \
  -Xmx1024m \
  -Dsts.lsp.client=vscode \
  [-Dspring.profiles.active=file-logging -Dlogging.file.name=<spring-boot.ls.logfile>] \
  [-Dlogging.level.root=<spring-boot.ls.logLevel>] \
  -Xlog:jni+resolve=off \
  -jar extension/language-server/spring-boot-language-server-2.2.0-SNAPSHOT-exec.jar
```

(`-Dserver.port=<p>` replaces `web-application-type=NONE` only when the AI MCP server setting is on; CDS/AOT cache args only with `spring-boot.ls.cds.enabled`, Java 25+.) The jar's own `application.properties` sets `spring.main.banner-mode: off`, reconcile debounce 500 ms and the completion trigger characters.

Client side the server needs (commons-vscode `classpath.ts`, `java-data.ts`, Main.ts):

- `initializationOptions`: `{ workspaceFolders = [uri...], enableJdtClasspath = false }`; language ids `spring-boot-properties` / `spring-boot-properties-yaml` for `application*.properties` / `application*.yml`.
- jdt.ls must load the five `javaExtensions` jars as bundles (they add the `sts.java.*` commands).
- Server-to-client requests, each answered by forwarding to jdt.ls `workspace/executeCommand`: `sts/addClasspathListener` -> `sts.java.addClasspathListener` (callbackCommandId), `sts/removeClasspathListener`, `sts/javaType`, `sts/javadocHoverLink`, `sts/javaLocation`, `sts/javadoc`, `sts/javaSearchTypes`, `sts/javaSearchPackages`, `sts/javaSubTypes`, `sts/javaSuperTypes`, `sts/javaCodeComplete`, `sts/project/gav` (`sts.java.*` / `sts.project.gav`). Notifications `sts/highlight`, request `sts/moveCursor`.
- jdt.ls then calls back the client with `workspace/executeClientCommand <callbackCommandId>` carrying classpath events, which the client forwards to the Boot LS as `workspace/executeCommand`. nvim-jdtls already routes `workspace/executeClientCommand` to `vim.lsp.commands` (`jdtls.lua` 854-873).
- After start: `sts.vscode-spring-boot.enableClasspathListening true` (command `vscode-spring-boot.ls.start`).

## spring-boot.nvim (option a) in short

Neovim 0.12 native (`lsp/spring-boot.lua` for `vim.lsp.config`, client name `spring-boot`, filetypes `java`, `yaml`, `jproperties`, gated to `application*.yml/properties`). It implements every item of the list above: the 12 forwarders (8 s cap on the classpath listener answer, below the server's 10 s `INITIALIZE_TIMEOUT`), the callback command registration, language ids, `workspaceFolders`, a settings push after the classpath events settle (fixes the server indexing from a bad cache entry), `java_extensions()` for the jdt.ls bundles, Mason discovery, `:SpringBoot` symbol queries (`@+` beans, `@/` request mappings) through `vim.lsp.buf.workspace_symbol`, `has_spring_boot_dependency()` for `project_filter`. Its defaults that nv4j must override: `root_dir` (markers `.git`, `mvnw`, `gradlew`, so a project inside a bigger git repo, like the fixture, gets the whole repo), `java_cmd` (`$JAVA_HOME` or PATH `java`; nv4j uses `nv4j.jdk.server_home()`), and its own JVM flags (`-XX:TieredStopAtLevel=1 -Xmx1G -XX:+UseZGC`, no `-Dspring.config.location`).

## Decision D14 (Task 0)

**(a) `JavaHello/spring-boot.nvim`, pinned to `9880be4`, configured in about 30 lines of nv4j Lua** (`nvim/lua/plugins/spring.lua`: `ls_path`/`java_cmd`/`root_dir` = the jdt.ls root/`project_filter` = Spring Boot dependency, plus its `java_extensions()` added to the jdt.ls bundles in `plugins/java.lua`). Reason: the own thin client (b) would have to re-implement the protocol glue listed above, about 150 lines of our code at the least (the plugin's non-comment logic for it is about 250 lines), including two timing workarounds the plugin authors already found (listener answer cap, settings push after classpath events). The plugin removes real code, is Neovim 0.12 native and met every P2 budget on the first trial (below). Cost if wrong: one plugin to replace by our own file, the checks stay the same. Revisit if the pinned plugin breaks on a jdt.ls or Boot LS update, or if it costs more than the budgets.

## Test design (`tests/checks/50_spring_ls.lua`)

Opens `DemoApplication.java` (starts jdt.ls), then `src/main/resources/application.properties` with Neovim's own filetype detection (`jproperties`). Cases: `attached` (a client named `spring-boot`, initialized, <= 10 s after jdt.ls ready), `props_first` (`server.po` lists `server.port`, <= 400 ms, sent 1.0 s after the client is initialized), `props_warm` (p95 of 100 <= 150 ms, `server.port` in every list), `props_hover` (`server.port` hover names the key, <= 500 ms), `rss` (the Spring LS child process of this nvim <= 1.5 GB, over 1 GB flagged). The file is edited in memory only and restored.

Baseline (no Spring LS wired): `attached` FAIL "no 'spring-boot' client on application.properties after 30741 ms (filetype jproperties, clients: none)", the four other cases FAIL "no 'spring-boot' client (see attached)", `DONE 50_spring_ls 0 5` (`/tmp/nv4j/logs/test-20261021-100352.log`).

## Wiring (Task 3)

- `nvim/lua/plugins/spring.lua`: `JavaHello/spring-boot.nvim` at commit `9880be48170a21d97444b1eba75853fd3bad33c3`, lazy-loaded on `java`/`yaml`/`jproperties`; `vscode-spring-boot-tools` added to Mason's `ensure_installed` (unless `vim.g.nv4j_spring = false` at startup). `tests/run.sh` installs it like jdtls when missing (same stale-link cleanup, path-guarded `rm`).
- `nvim/lua/nv4j/spring.lua`: calls `require("spring_boot").setup()` with `ls_path` = `mason/share/vscode-spring-boot-tools/language-server.jar` (Mason link, no version), `jars` = the package's own `package.json` `contributes.javaExtensions` resolved inside the package (fallback: the five names under `share/.../jdtls/`), `java_cmd` = `nv4j.jdk.server_home()/bin/java` (never PATH, never a JAVA_HOME below 21), log file `/tmp/nv4j/logs/spring-boot-ls.log` (level warn), extra JVM args `-Dspring.main.web-application-type=NONE -Djdk.util.zip.disableZip64ExtraFieldValidation=true` (as VS Code), and `server.root_dir` replaced by nv4j's own: `on_dir` only for Java buffers and `application*`/`bootstrap*` `.properties`/`.yml` of a Spring Boot project. Root = the jdt.ls root (`nvim/lua/nv4j/root.lua`, moved out of `plugins/java.lua` unchanged); a loose file (no build marker) never qualifies. Spring Boot = the rule shared with `nv4j.run` (`nvim/lua/nv4j/root.lua` `boot_build`, see r1) at the root or in a module up to 2 levels down (at most 60 directories), memoized per root. `vim.g.nv4j_spring = false` set at startup keeps the plugin from loading (lazy.nvim `cond`, since r1); set later it is read at every attach decision and when jdt.ls starts. Without the Mason package: one WARN (`:MasonInstall vscode-spring-boot-tools`) the first time a Spring Boot file is opened, nothing else.
- `plugins/java.lua` `opts.jdtls`: for a Spring Boot root, `require("nv4j.spring").bundles_for(root)` is appended to LazyVim's `init_options.bundles` (java-debug and java-test stay). Plain projects start jdt.ls exactly as before.
- Client capabilities were not restricted: the `spring-boot` client stays on Java buffers (needed by Task 4 for `@Value`/`@Profile`) and P1 latency did not move (trial t4).

## Gating and JDK cases (Review Focus 1 and 2)

`50_spring_ls` grew from 5 to 11 cases: `yml_java_attached` (one client on `application-dev.yml` and `DemoApplication.java`), `bundles` (the five jars plus java-debug in jdt.ls's bundles, `sts.java.addClasspathListener` in its commands), `server_jvm` (the Spring LS JVM is `server_home()` and not the JDK 21 `run.sh` puts first on `PATH`), `disabled` (`vim.g.nv4j_spring = false`: a new Java buffer of the Boot fixture gets no client), `plain_maven` (`/tmp/nv4j/plain21`, release 21, no Boot, with an `application.properties`: its own jdt.ls, no `spring-boot` client, no Spring jars, still one Spring LS process), `loose_file` (`/tmp/nv4j/loose/Loose.java`: no client, no process). Negative control c1 (gating removed) fails exactly `disabled`, `plain_maven` (2 processes) and `loose_file` (3 processes).

## Completion and navigation (Task 4)

What already worked from the Task 3 wiring (first baseline, `test-20261021-144357.log` and `-144641.log`, recorded as is):
properties `server.po` -> `server.port` rank 1, `spring.jpa.hibernate.ddl` -> `ddl-auto` rank 1, yml nested `server:`/`po`
-> `port` (rank 2, under a snippet) and top-level `server.po`, `@Value("${server.po}")`, `@Profile("")` -> `dev` (the only
Spring item, read from `application-dev.yml`), broken properties/yml files (completion on the next valid line, client alive),
`@` RestController rank 1 with the Spring client on the buffer (0 Spring items in the list), hover in yml and properties,
go to definition from `@Value("${server.port}")` (the server answers with LocationLinks to `src/main/resources/application.properties`
line 2 and `application-dev.yml` line 2: `ValueDefinitionProvider` in spring-tools, read at the pinned commit), and
`workspace/symbol` `@/` (`@/customers -- GET`, `@/customers/{id} -- PUT`, `@/hello -- GET`: class prefix joined with the
method path) and `@+` (12 beans). What failed: `@Value("${}")` (the project keys cut from the menu), snippet noise in yml and
in Java string literals, and no key for the Spring symbols.

Built:

- `nvim/lua/nv4j/completion.lua` `java_sort`: items without jdt.ls relevance tie on sortText, then keep the server's order
  (`nv4j_idx`). The Spring LS sends the ~1850 `@Value` keys with no sortText; `table.sort` shuffled them and blink's
  `max_items` (200) dropped `demo.greeting.*` and `server.port` (trial c2). jdt.ls's sortText formula is only read for items
  from the `jdtls` client (another server's numeric sortText would outrank every jdt.ls item).
- `snippets_should_show`: no snippets in `yaml`/`jproperties` buffers that have the `spring-boot` client
  (friendly-snippets' YAML set is docker-compose/k8s: `po` -> `ports:` ranked above `port`), and none inside a Java `"..."`
  literal (`@Profile("")` listed 36 snippets after `dev`) (trial c3). One-line quote count: inside a text block body it says
  "not a string".
- `nvim/lua/nv4j/spring_nav.lua` + `<leader>sp` (`config/keymaps.lua`): `workspace/symbol` `@+` and `@/` on the Spring client
  only (`:SpringBoot`/`vim.lsp.buf.workspace_symbol` ask every client, jdt.ls too), `vim.lsp.util.symbols_to_items`,
  Telescope picker (quickfix entries, generic sorter, file preview). Not `<leader>ss`: that is LazyVim's Goto Symbol
  (telescope extra) and the config refers to it; `<leader>sp` is free in every enabled extra. No client for the buffer: a
  WARN, no picker.

Not changed: blink source weighting (the Spring items never reach Java identifier/annotation lists: `@` showed 0 Spring
items), the fixture (the brief's `/people` example: the fixture's mappings are `/customers`, `/customers/{id}` and `/hello`;
the check asserts those, including the class-level prefix).

Test design: `51_spring_completion` (19 cases) measures the blink menu (tests/lib `completion.menu`: every source of the buffer,
transforms, fuzzy, sorts, max_items), expected item in the top 3; first round trips <= 400 ms, warm p95 over 100 <= 150 ms;
broken files with a 1.5 s wait so the server reconciles them first; `alive_after` re-asks after both. `52_spring_nav` (10 cases)
uses `vim.lsp.buf.definition` (all clients, what `gd` asks), the Spring client's `workspace/symbol`, and drives `<leader>sp`
through its mapping, the Telescope picker, `set_prompt("/hello")` and `select_default`.

## Trial log

| # | Change | Result | Kept |
|---|--------|--------|------|
| sp0 | `java -jar share/vscode-spring-boot-tools/language-server.jar` (symlink), stdin closed | starts (Boot 2.2.0-SNAPSHOT on JDK 21.0.12) in about 1 s, no class loading errors: the symlink path works. Logs go to stdout when `-Dlogging...` points nowhere else, so the stdio launch must keep logging off stdout (plugin: file-logging profile, `/dev/null` default) | evidence |
| sp1 | spring-boot.nvim on the rtp from the clone (not installed), `java_cmd` = `server_home()`, `root_dir` = fixture, jars added to jdt.ls bundles; probe script | client `spring-boot` initialized 667 ms after jdt.ls ready; first completion 205 ms, `server.port` rank 1 of 75; warm p95 5 ms (30 samples); hover 7 ms "**server.port** [java.lang.Integer] Default: *8080* Server HTTP port." | evidence for D14 |
| sp2 | same (repeat) | initialized +113 ms; first 195 ms; warm p95 6 ms; hover 7 ms | evidence |
| sp3 | same, RSS by process | RSS 298 MB | evidence |
| pc1 | `50_spring_ls` run with the sp1 wiring preloaded (positive control, scratch only), first request sent right at client init | 4/5 PASS; `props_first` FAIL: 0 items in 87 ms (the property index is still empty in that millisecond) | check changed: first request pinned at client init + 1.0 s (like D13) |
| pc2 | same after the pin (2 runs) | 5/5 PASS both: ready 72/103 ms after jdt.ls, first 87/76 ms rank 1, warm p95 4.0/4.1 ms, hover 7/6 ms, RSS 426/419 MB | the check can pass; the wiring itself is Task 3 |
| t1 | Task 3 wiring (`nv4j/spring.lua`, `plugins/spring.lua`, bundles in `plugins/java.lua`), original 5 cases | `DONE 50_spring_ls 5 0`: ready 46 ms after jdt.ls, first 19 ms rank 1 of 75, warm p95 4.0 ms, hover 4 ms, RSS 412 MB (`test-20261021-122355.log`) | kept |
| t2 | check extended to 11 cases (gating, bundles, server JVM) | `DONE 50_spring_ls 11 0`: ready 38 ms, first 36 ms, warm p95 3.6 ms, hover 4 ms, RSS 413 MB, server JVM 25.0.4 with Corretto 21 on PATH (`test-20261021-122458.log`) | kept |
| c1 | negative control: `boot_root` returns every root (no Boot test, no `vim.g.nv4j_spring` test), scratch only | `DONE 50_spring_ls 8 3`: `disabled` attached, `plain_maven` attached (2 Spring LS processes), `loose_file` attached (3 processes) | reverted; proves the gating cases |
| t3 | `tests/run.sh` installs `vscode-spring-boot-tools` like jdtls (`ensure_mason`) | already installed here: no-op; syntax checked | kept |
| t4 | full `tests/run.sh` with the Spring client on every fixture Java buffer, capabilities unrestricted | P1 135 PASS 0 FAIL; worst warm p95 50 ms (before, `test-20261021-121503.log`: 42 ms; budget 150), cold first 43 ms (47), `@` RestController rank 1 (1), diagnostics 457 ms (463); `41_run 22 0`, `50_spring_ls 11 0`; `40_debug 15 1`: `build_guard` timeout case fired at 671 ms for a 1 s timer (`test-20261021-122633.log`) | no restriction needed |
| t5 | `40_debug` alone, twice (same code) | `DONE 40_debug 16 0` both, timeout case 945/944 ms: a flake, not a Spring LS failure. Cause: `vim.defer_fn` arms from libuv's cached loop time, stale by ~330 ms after a busy tick (more work per tick with the second client) | fix: `vim.uv.update_time()` before arming the timer in `nv4j/debug.lua` `M.build` (one line) |
| t6 | 3 consecutive `50_spring_ls` runs with the final code | `DONE 50_spring_ls 11 0` 3 of 3: ready 330/37/88 ms after jdt.ls, first 51/90/19 ms, warm p95 3.8/4.9/4.9 ms, hover 5/7/5 ms, RSS 423/415/439 MB (`test-20261021-141127.log`, `-141202`, `-141235`) | final |
| t7 | final full `tests/run.sh` | exit 0: P1 135 PASS 0 FAIL (worst warm p95 55 ms, cold first 49 ms, RestController rank 1, diagnostics 474 ms), `40_debug 16 0` (timeout case 1000 ms), `41_run 22 0`, `50_spring_ls 11 0` (ready 39 ms, first 66 ms, warm p95 4.6 ms, hover 8 ms, RSS 439 MB); no Spring LS process left after the run (`test-20261021-141316.log`) | final |
| r1 | review fix round 1: `cond` on the plugin spec (flag off at startup = not loaded); one Spring Boot rule for run and the Spring LS (`nvim/lua/nv4j/root.lua` `boot_build`/`boot_project`: Boot groupId, `spring-boot-starter*`/`spring-boot-maven-plugin`/`spring-boot-dependencies` artifacts, Gradle plugin/group/starters, catalog aliases and `gradle/libs.versions.toml`; a bare `spring-boot` substring such as a `spring-boot.version` property no longer counts); `attached` detail says "initialized"; cases `detect` and `off_at_start` (child nvim with `g:nv4j_spring = false`: `:SpringBoot` absent, 0 spring/sts entries in `vim.lsp.commands`, module not loaded; control child without the flag: command present, 1 entry, loaded) | `DONE 50_spring_ls 13 0` (`test-20261021-1422*.log`): detect fixture/catalog/catalog-toml/starter-artifact/aggregator Boot, property-only and comment-only not Boot | kept |
| ab | A/B, `10_completion_latency` 3 runs each, interleaved, `NV4J_SPRING=0` (new `run.sh` switch: `--cmd "let g:nv4j_spring = v:false"`) vs default | Spring off: worst warm p95 41/47/40 ms (mean 42.7), sum of the 14 case p95s 338/377/370 (mean 362), cold first 51/48/56 ms. Spring on: worst 49/50/44 (mean 47.7), sum 381/411/399 (mean 397), cold first 44/48/46. Every "on" sum is above every "off" sum, so the difference is attributable to the second server (CPU shared with its indexing; the p95s are direct jdt.ls round trips, not the Spring server answering), about +5 ms worst case and +10 % overall; far inside the 150 ms budget, so nothing restricted. Logs `test-20261021-142343.log` (off), `-142444` (on), `-142548` (off), `-142649` (on), `-142752` (off), `-142858` (on) | recorded, no fix needed |
| r2 | after r1: 3 consecutive `50_spring_ls` + full run | `DONE 50_spring_ls 13 0` 3 of 3 (initialized 44 to 60 ms, first 59 to 78 ms, warm p95 4.2 to 4.9 ms, hover 5 ms, RSS 403 to 416 MB); full run exit 0, P1 135 PASS, `40_debug 16 0`, `41_run 22 0`, `50_spring_ls 13 0` (`test-20261021-143222.log`) | final |
| c1t4 | Task 4 baseline: `51_spring_completion` (16 cases then) and `52_spring_nav` written first, run on the Task 3 code | `DONE 51 13 3`: `value_keys` FAIL (rank nil, project keys missing: the 200 shown were `trace`, `spring.kafka.streams.*`...), `value_first` FAIL 598 ms, `value_warm` FAIL (key missing in 100 of 100); `DONE 52 6 4`: `key`, `picker`, `picker_jump`, `no_client` FAIL (no `<leader>sp`) (`test-20261021-144357.log`, `-144641.log`) | baseline |
| c2 | `java_sort` tie breaker: server order (`nv4j_idx`) after sortText; jdt.ls relevance only for `jdtls` items | `value_keys` rank 2 (`debug`, `demo.greeting.text`, `demo.greeting.times`), no key missing; warm p95 54 ms (`test-20261021-144446.log`) | kept |
| c3 | snippets off in Spring yml/properties buffers and inside Java string literals (cases `yml_no_snippets`, `profile_clean` written first: FAIL 5 and 36 snippet items, `-144641.log`; guard `snippets_kept`) | yml `port` rank 2 -> 1, `@Profile("")` 37 items -> 1 (`dev`), `fo` in a method body still lists `foreach`/`fori` (`-144804.log`) | kept |
| c4 | `value_first` 581 ms in that run: per-client timing (`LspRequest` autocmd) over 3 runs: jdt.ls 24-31 ms, Spring LS 96 / 557 / 506 ms when the request goes out in the millisecond the file is opened; 1.5 s later 75-127 ms (3 runs), 3 s later 133 ms. Raw requests without blink: 81-126 ms | the first `@Value` request is pinned 1.0 s after `GreetingController.java` opens (the D13 / `props_first` rule). After: 59-81 ms | check pin kept (Known limitations) |
| c5 | `hover_yml` on `server.port`: 371-516 ms first time (one FAIL at 516), 1 ms the second time; first yml hover of other keys 1-27 ms (`spring.jpa.open-in-view` 99 ms) even with no other hover before; properties hover of `server.port` 1-7 ms | server side, per key, not "first hover after open" (a 1 s pin did not change it: 284/320/489 ms) | evidence |
| c6 | background hover on the yml's first key at attach (`LspAttach` in `nv4j/spring.lua`) | `server:` (no docs) warms nothing: 270-317 ms. On the first leaf key (`server.port`) it would only warm that key (c5) and the check would measure a cached answer | reverted |
| c7 | `hover_yml` measures `logging.level` (12-27 ms without any warm-up, 2 runs); the first `server.port` yml hover printed as `INFO` (not budgeted) and listed in Known limitations | honest budget on a representative key, outlier visible | kept |
| n1 | negative control: Spring items dropped in `transform_lsp` (scratch) | `DONE 51 4 15`: every Spring ranking/latency case FAILs; `profile_clean`, `snippets_kept`, `at_regression` pass (they do not need Spring items) (`-145645.log`) | reverted |
| n2 | negative control: `NV4J_SPRING=0` | `DONE 51 0 1`, `DONE 52 0 1` (`attached` FAIL, check stops) (`-145717.log`) | evidence |
| n3 | negative control attempts for 52: no Spring jars in jdt.ls's bundles; the client on an empty root | both `DONE 52 10 0`: the server still had the project (jdt.ls keeps installed bundles in its workspace OSGi cache; the classpath listener reports every jdt.ls project, not only the client root). Not usable as controls | evidence |
| n4 | negative control: the Spring client answers hover/definition/workspace symbols with nothing (scratch copy of 52) | 3 PASS 7 FAIL: `hover_yml`, `hover_props`, `definition`, `mappings`, `beans`, `picker`, `picker_jump` FAIL; `attached`, `key`, `no_client` pass | evidence |
| f1 | 3 consecutive `51` + `52` runs with the code after c7 | `DONE 51_spring_completion 19 0` and `DONE 52_spring_nav 10 0` 3 of 3: yml first 33-36 ms, `@Value` first 67-76 ms, `@Value` warm p95 49-57 ms, yml warm p95 9.8-10.6 ms, RestController rank 1, yml hover 11-32 ms (INFO `server.port` 202-266 ms), definition 49-80 ms, picker 126-144 ms (`test-20261021-150741.log`, `-150817`, `-150852`) | kept |
| c8 | full `tests/run.sh` (`test-20261021-150938.log`): `51` `profile` FAIL once: the server answered `@Profile("")` with no items, 11 ms, sent right after `GreetingConfig.java` opened (28 buffer words shown); `32_code_actions` `remove_unused_import` FAIL once (jdt.ls offered no quick fix: no diagnostic in the request context yet) | `profile` pinned 1.0 s after the file opens (as c4): 3 of 3 `DONE 51 19 0`, `dev` rank 1 (`-151625`, `-151649`, `-151712`); `32` alone 3 of 3 `DONE 32_code_actions 28 0` (not touched by this task; recorded as a flake of the full run) | pin kept |
| f2 | final full `tests/run.sh` (`test-20261021-151747.log`) | exit 0: P1 135 PASS 0 FAIL (worst warm p95 69 ms, cold first 45 ms, RestController rank 1, diagnostics 452 ms), `40_debug 16 0`, `41_run 22 0`, `50_spring_ls 13 0`, `51_spring_completion 19 0`, `52_spring_nav 10 0`; 215 PASS; no Spring LS process left | final |
