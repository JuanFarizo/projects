# Feature: Spring Boot language server

Priority: P2 (properties/yml completion and hover), P2/P4 (`@Value`/`@Profile`, beans, request mappings). Status: research, decision D14 and failing baseline done (Task 0); wiring is Task 3, completion/hover/navigation Task 4. Tests: `tests/checks/50_spring_ls.lua`. Spec: `specs/004-p2-spring-run-debug.md`.

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

## Trial log

| # | Change | Result | Kept |
|---|--------|--------|------|
| sp0 | `java -jar share/vscode-spring-boot-tools/language-server.jar` (symlink), stdin closed | starts (Boot 2.2.0-SNAPSHOT on JDK 21.0.12) in about 1 s, no class loading errors: the symlink path works. Logs go to stdout when `-Dlogging...` points nowhere else, so the stdio launch must keep logging off stdout (plugin: file-logging profile, `/dev/null` default) | evidence |
| sp1 | spring-boot.nvim on the rtp from the clone (not installed), `java_cmd` = `server_home()`, `root_dir` = fixture, jars added to jdt.ls bundles; probe script | client `spring-boot` initialized 667 ms after jdt.ls ready; first completion 205 ms, `server.port` rank 1 of 75; warm p95 5 ms (30 samples); hover 7 ms "**server.port** [java.lang.Integer] Default: *8080* Server HTTP port." | evidence for D14 |
| sp2 | same (repeat) | initialized +113 ms; first 195 ms; warm p95 6 ms; hover 7 ms | evidence |
| sp3 | same, RSS by process | RSS 298 MB | evidence |
| pc1 | `50_spring_ls` run with the sp1 wiring preloaded (positive control, scratch only), first request sent right at client init | 4/5 PASS; `props_first` FAIL: 0 items in 87 ms (the property index is still empty in that millisecond) | check changed: first request pinned at client init + 1.0 s (like D13) |
| pc2 | same after the pin (2 runs) | 5/5 PASS both: ready 72/103 ms after jdt.ls, first 87/76 ms rank 1, warm p95 4.0/4.1 ms, hover 7/6 ms, RSS 426/419 MB | the check can pass; the wiring itself is Task 3 |
