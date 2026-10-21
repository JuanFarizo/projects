# Feature: Run and debug (Spring Boot)

Priority: P2 (blocker for the rest of P2). Status: debug works (Task 1: `DONE 40_debug 13 0`, 5 of 5 consecutive runs, see "Task 1: fixes"); run is Task 2. Research and failing baseline: Task 0. Tests: `tests/checks/40_debug.lua`. Spec: `specs/004-p2-spring-run-debug.md`.

## How debug works today (installed versions)

- LazyVim `lang.java` extra (LazyVim `99970099`, 2026-09-08) passes `init_options.bundles` to jdt.ls: `$MASON/share/java-debug-adapter/com.microsoft.java.debug.plugin-*jar` (java-debug 0.53.2) plus every jar in `$MASON/share/java-test/` (java-test 0.43.1, 34 files: the plugin twice, the runner fat jar, jacoco agent, JUnit 5 and 6 jars, asm). On `LspAttach` it calls `jdtls.setup_dap()` and `jdtls.dap.setup_dap_main_class_configs()` (its `dap_main = {}` option).
- nvim-jdtls (`6e9d953`, 2026-05-20) `jdtls.dap.fetch_main_configs` (used by `setup_dap_main_class_configs`, `:JdtUpdateDebugConfig` and nv4j's `<leader>rj`): `vscode.java.resolveMainClass`, then for every main class, in parallel, `vscode.java.checkProjectSettings` / java exec lookup and `vscode.java.resolveClasspath` (`lua/jdtls/dap.lua` 617-660). Each config is `request = launch`, `console = integratedTerminal`.
- nvim-dap (`cfa2d58`, 2026-09-11) asks jdt.ls for a debug session port (`vscode.java.startDebugSession`) and runs the debuggee through `runInTerminal` in a terminal buffer. nvim-dap-ui (`cc9dd33`) opens its windows on start.
- jdt.ls 1.62 (Mason `jdtls`, plugins dated 2026-09), m2e.jdt 2.5.300, jdt.launching 3.24.400. Reference clone `~/.cache/nv4j/eclipse.jdt.ls` at `b52e20aa46fa53e2372948aac26310597a78f25a` (sparse: read files with `git show HEAD:<path>`).

## Step 1: the reproduced warning

Seen in the user session and in the jdt.ls log of the fixture workspace (`~/.cache/nv4j/jdtls-data/demo-c21cad66/.metadata/.log`, sessions 2026-10-20 23:10 and 2026-10-21 09:43), right after `>> build jobs finished` / `>> registerWatchers`, about 5 s after jdt.ls start:

```
!MESSAGE Referenced classpath provider does not exist: org.eclipse.m2e.launchconfig.classpathProvider
java.lang.Exception: Failed to resolve classpath: Referenced classpath provider does not exist: org.eclipse.m2e.launchconfig.classpathProvider
	at com.microsoft.java.debug.plugin.internal.ResolveClasspathsHandler.resolveClasspaths(ResolveClasspathsHandler.java:79)
	at com.microsoft.java.debug.plugin.internal.JavaDebugDelegateCommandHandler.executeCommand(JavaDebugDelegateCommandHandler.java:62)
	at org.eclipse.jdt.ls.core.internal.handlers.WorkspaceExecuteCommandHandler$1.run(WorkspaceExecuteCommandHandler.java:230)
Caused by: org.eclipse.core.runtime.CoreException: Referenced classpath provider does not exist: org.eclipse.m2e.launchconfig.classpathProvider
	at org.eclipse.jdt.launching.JavaRuntime.abort(JavaRuntime.java:1915)
	at org.eclipse.jdt.launching.JavaRuntime.getClasspathProvider(JavaRuntime.java:1187)
	at org.eclipse.jdt.launching.JavaRuntime.computeUnresolvedRuntimeClasspath(JavaRuntime.java:1703)
	at com.microsoft.java.debug.plugin.internal.ResolveClasspathsHandler.computeClassPath(ResolveClasspathsHandler.java:231)
```

In Neovim nvim-jdtls prints: `Could not resolve classpath and modulepath for demo/demo.DemoApplication: Failed to resolve classpath: Referenced classpath provider does not exist: org.eclipse.m2e.launchconfig.classpathProvider`. Each session that failed failed exactly one of the three main classes, and a later `:JdtUpdateDebugConfig` in the same session worked.

## Step 2: root cause

**A race in JDT launching, triggered by nvim-jdtls's parallel classpath requests on the first use after jdt.ls starts.** Not a missing bundle, not bundle order, not m2e on Corretto 25.

Evidence:

1. The provider exists. `org.eclipse.m2e.jdt_2.5.300` (installed) declares it in `plugin.xml`: extension point `org.eclipse.jdt.launching.classpathProviders`, id `org.eclipse.m2e.launchconfig.classpathProvider`, class `org.eclipse.m2e.jdt.internal.launch.MavenRuntimeClasspathProvider`. The same bundle's `MavenLaunchConfigurationListener` is what writes that id into every launch configuration of a Maven project, so whenever the attribute is set, m2e.jdt is active.
2. The lookup is not thread safe. `javap -c` of the installed `org.eclipse.jdt.launching.JavaRuntime` (3.24.400): `getClasspathProviders()` calls `initializeProviders()` when the static `fgPathProviders` is null; `initializeProviders()` does `fgPathProviders = new HashMap(n)` (putstatic) **before** the loop that fills it from the extension registry, with no lock. A second thread that enters while the first one is still filling sees a non-null, empty or partial map, `get(id)` returns null and `getClasspathProvider` aborts with "Referenced classpath provider does not exist". Later calls see the full map, which is why a retry works.
3. jdt.ls runs `workspace/executeCommand` on the ForkJoin pool (`JDTLanguageServer.lambda$64` -> `CompletableFuture`), so the parallel requests nvim-jdtls sends (one per main class: App, DemoApplication, Modern in the fixture) really run concurrently, and the very first ones race on that lazy init.
4. Controlled trials below (probe with LazyVim's at-attach call disabled, so the probe's calls are the first): three parallel `resolveClasspath` failed one call in 2 of 3 runs; three sequential calls never failed (3 of 3). The same parallel race with only the java-debug bundle (no java-test jars) still failed (1 of 3), so the bundle list is not the cause.

What the user sees: LazyVim's `setup_dap_main_class_configs` at attach is the first caller, so in a fresh session one main class often has no debug config. Worse, nvim-jdtls `fetch_main_configs` returns on an error without checking `remaining == 0` (`dap.lua` 632-634): when the failed call is the last to answer, the callback never fires, so `dap.configurations.java` gets no main-class configs at all and `<leader>rj` does nothing. Seen in `40_debug`: "no callback, no callback, no callback" and "3, 3, 1!".

Fix options for Task 1 (Task 0 text; what was done: "Task 1: fixes" below): make the first `resolveClasspath` of a session run alone (one sequential warm-up call before the parallel ones, e.g. serialize nvim-jdtls's calls until one succeeds), or retry a call that failed with this message. Both are client side and need no jdt.ls patch. An upstream fix would be in `JavaRuntime.initializeProviders` (fill a local map, then publish).

## Other debug blockers found (Task 1 input)

1. **Files added on disk while jdt.ls is down are not built.** jdt.ls refreshes a Maven project from disk on startup only when `pom.xml` is newer than the last saved workspace state (`MavenProjectImporter.updateProjects` / `needsMavenUpdate`, eclipse.jdt.ls `managers/MavenProjectImporter.java` 439-482). The four fixture classes added in this task (`GreetingProperties`, `GreetingConfig`, `GreetingController`, `StartupRunner`) stayed out of jdt.ls's build for several sessions: jdt.ls wrote `StartupRunner.class` with "Unresolved compilation problems: GreetingProperties cannot be resolved to a type" into `target/classes` (shared with Maven, so it overwrote the good class from `mvn compile`), and the app died with `NoClassDefFoundError: GreetingProperties`. Opened buffers reconcile clean (0 problems), so nothing in the editor shows it.
2. **nvim-jdtls does not build before launch.** VS Code's java-debug builds the workspace before every launch (`java.debug.settings.forceBuildBeforeLaunch`, default true); nvim-jdtls and LazyVim do not (no `java/buildWorkspace` in `jdtls/dap.lua`). One incremental `java/buildWorkspace` (2.6 s) compiled the missing classes and the next launch stopped at the breakpoint in 3.2 s.
3. **The debuggee survives `dap.terminate()`.** With `console = integratedTerminal` the JVM was still running 10 to 13 s after terminate in every run where it started (probes d6, d7; `40_debug` runs 1 and 3). Review Focus 5.
4. **A stray jdt.ls start on every debug launch.** nvim-dap's terminal setup calls `vim.filetype.get_option("java", "path")` (`dap/session.lua` 203), which creates a scratch buffer with `filetype=java`; LazyVim's `FileType` autocmd then calls `attach_jdtls` for it, nv4j's `root_dir("")` returns `"."` (`vim.fs.dirname("")`), and a second jdt.ls is started with `-data .../jdtls-data/.-cdb4ee2a`, which fails `initialize` with `IllegalArgumentException: URI has an authority component`. The error is raised through `vim.schedule` and can abort whatever is waiting (it aborted probe d1). Fix: ignore unnamed buffers in `root_dir` / the attach.
5. Observed once (`40_debug` run 2): the debuggee died with `NoClassDefFoundError: org/springframework/boot/SpringApplication`, a classpath without the Maven dependencies. Not reproduced yet; re-check after the race fix. (Task 1: reproduced at will by a source-folder refresh at ServiceReady, trial f6, where every `resolveClasspath` of the startup burst returned 1 entry instead of 71; never seen in the 69 runs from f6 on, without that refresh.)

## Task 1: fixes

All in `nvim/lua/nv4j/debug.lua`, wired from `nvim/lua/plugins/java.lua` (`setup()` in the nvim-jdtls opts, `on_attach(client)` in LazyVim's `opts.on_attach`, which runs after LazyVim's `setup_dap`). Nothing in jdt.ls, java-debug or nvim-jdtls is patched on disk.

1. **First JDT launching calls one at a time** (`serialize_until_warm`). The jdtls client's `request` is wrapped: `workspace/executeCommand` for `vscode.java.*` (java-debug, java-test) and `java.project.getClasspaths` go out one at a time, queued in order, until one `resolveClasspath`, `test.junit.argument` or `getClasspaths` succeeded; then everything is sent in parallel as before. Wrapping the client covers nvim-jdtls's `util.execute_command` and `util.with_java_executable` (which calls `client:request` directly). Retrying on the error message alone was tried first (f2) and missed a second face of the race: `vscode.java.resolveJavaExecutable` answered `null` (java-debug catches the `CoreException`), nvim-jdtls printed "Could not resolve java executable" and dropped that main class (f3). Evidence: 69 of 69 runs from f6 on pass `classpath_first` and `configs` (baseline: 0 of 4).
2. **Refresh + build before every Java launch** (wrapped `dap.adapters.java`, `request = launch` only). A `workspace/didChangeWatchedFiles` "Changed" event for every `src` folder of the project (jdt.ls runs `refreshLocal(DEPTH_INFINITE)` on it, `IBuildSupport.refresh`), then two incremental `java/buildWorkspace` (the refresh runs on jdt.ls's own `WorkspaceEventsHandler` thread and can take the workspace lock after the first build; the second build is a no-op when nothing changed). A build that ends with errors only warns (`Build before debug has compile errors; launching anyway`); VS Code asks instead. Without the refresh an incremental build never compiles a file added while jdt.ls was down (s1 re-check, below).
3. **No orphan**: for every Java launch session the terminal job (taken at `initialized`, when java-debug has started the debuggee) is stopped with `jobstop` when the session closes (terminate, disconnect, adapter gone). Only an explicit detach (`disconnect` with `terminateDebuggee = false`) leaves it running. Control f10: without it the JVM was still running 10 s after terminate.
4. **No stray jdt.ls**: `jdtls.start_or_attach` returns early for an unnamed buffer (nvim-dap's `vim.filetype.get_option("java", "path")` scratch buffer). Control f11: without it a jdt.ls start with root "." on every launch.
5. **JUnit launcher version** (`junit_launcher`, a `dap.listeners.on_config` hook). Found while adding the JUnit case: in about 1 of 4 jdt.ls sessions the test launch died with `ClassNotFoundException: org.junit.platform.engine.OutputDirectoryCreator` (or `NoSuchMethodError` on it). JDT's `JUnitLaunchConfigurationDelegate` adds its own bundled `junit-platform-launcher` (1.14.4, an OSGi bundle folder under `jdtls-config/.../org.eclipse.osgi/<n>/0/.cp`) when the project classpath it computed has none; that launcher needs platform engine 1.14 and Spring Boot 3.5.13 brings 1.12.2. In the other sessions the project classpath carried `junit-platform-launcher-1.12.2.jar` and the bundle was not added: 25 of 25 logged sessions match (bundle present = failed run). Why the project classpath has the launcher in some sessions only was not found. Fix: when a `RemoteTestRunner` config has a `junit-platform-engine-<v>.jar` from the Maven repo, no project launcher and the bundled launcher folder, the folder is replaced by `junit-platform-launcher/<v>/junit-platform-launcher-<v>.jar` from the same repo (if downloaded). Prepending it instead of replacing was tried (f13) and still failed. In the 15 runs that report it the replacement kicked in 3 times, and the test stopped and passed every time.

Project JDK: the debuggee runs on 25 with JDK 21 first on PATH and `JAVA_HOME` unset (`debuggee_jdk`, `test_debuggee_jdk`, `System.getProperty("java.version")` evaluated at the stop = `25.0.4`). nvim-jdtls takes the java executable from `vscode.java.resolveJavaExecutable`, which answers the project's VM from `java.configuration.runtimes` (nv4j.jdk); no change was needed.

Keys (LazyVim `dap.core`, unchanged): `<leader>db` breakpoint, `<leader>dc` continue/start (pick a main-class config), `<leader>dt` terminate, `<leader>tr` / `<leader>tt` debug the nearest test / the test class (LazyVim java extra).

### Final numbers (Task 1)

5 consecutive `NV4J_CHECKS=40_debug tests/run.sh` (logs `/tmp/nv4j/logs/test-20261021-111905.log`, `-111923`, `-111940`, `-111957`, `-112014`): `DONE 40_debug 13 0` in 5 of 5. `breakpoint_hit` 2941 to 3095 ms (budget 20 s, includes refresh and two builds), `test_breakpoint_hit` 715 to 894 ms. `classpath_first` and `configs` passed in all 69 runs from f6 on (control runs included).

### s1 re-check (Task 0 review note)

Probe (scratch, logs `/tmp/nv4j/logs/probe-s1-recheck.log`): a new class written while jdt.ls is down, then jdt.ls started on the fixture. Without a refresh (4 runs): the class was not compiled at ready, not after 5 s, not after an incremental build (status 1, success: jdt.ls does not know the file) and not after a second one. With the folder refresh before the build (3 runs + 1 polling run): the first build failed in 3 of 4 runs with "The project was not built since the source file /demo/src/main/java/demo/ProbeS1<old>.java could not be read" (a file of the previous probe run, deleted while jdt.ls was down, still in its workspace) and compiled nothing; the second build compiled the new class. Answer to s1: Task 0's "autobuild compiled it after 5 s" and s3/s4's "incremental build compiled it" were runs where something else had refreshed the folder (a file of that folder opened in a buffer creates its resource); "the class was gone after the build" fits the stale-deleted-file failure above (the project is not built at all). Hence fix 2 refreshes first and builds twice.

## Test design (`tests/checks/40_debug.lua`)

Task 1 added `variable`, `debuggee_jdk`, `one_jdtls` (counts every jdt.ls start/attach by root: the stray server dies in `initialize`, so live clients miss it), `test_breakpoint_hit`, `test_variable`, `test_debuggee_jdk`, `test_finished` and `junit_launcher` (synthetic classpath), made `no_orphan` require the marked JVM alive before terminate (it passed vacuously when the app died by itself) and moved the breakpoint to the line after `text` is assigned. Every Java launch gets the `-Dnv4j.check=40_debug` marker through a `dap.listeners.on_config` hook. Failure details name the jdt.ls commands of the test launch, the notifications and the debuggee's terminal output.

Task 0 cases: `attached`, `classpath_first` (no nvim-jdtls classpath error; LazyVim's own fetch at attach plus 3 more `fetch_main_configs` sent from `LspAttach`), `configs` (each fetch calls back with all 3 main classes), `breakpoint_hit` (DemoApplication launched with the user's config through `dap.run`, `--server.port=0` and a `-Dnv4j.check=40_debug` marker; stop at the breakpoint in `LateRunner<N>.run` within 20 s), `no_orphan` (JVM gone 10 s after terminate). `LateRunner<N>` and `LateGreeting<N>` are written before jdt.ls starts, with a new `N` each run (a name jdt.ls saw before, even deleted, behaves differently: two runs with fixed names passed `breakpoint_hit`), only the runner is opened; the check removes both and their class files, and always kills the marked JVM. Waits record errors raised by other callbacks and keep waiting (item 4 above).

Baseline (before any fix), 3 runs of `NV4J_CHECKS=40_debug tests/run.sh` (logs `/tmp/nv4j/logs/test-20261021-100947.log`, `-101122.log`, `-101216.log`): `classpath_first` FAIL 3/3 (1 to 2 classpath errors), `configs` FAIL 3/3, `breakpoint_hit` FAIL 3/3 (`LateGreeting<N>.class` missing at launch; the app runs without the runner or dies), `no_orphan` FAIL 2/3 (PASS 1/3 only because the app died by itself; with the full run below, 2 of 4 runs passed this way). The full run after the fixture change (`test-20261021-101339.log`) failed the same way: `classpath_first`, `configs`, `breakpoint_hit` FAIL, `no_orphan` PASS (app died). The race is timing dependent, so `classpath_first` can pass in a lucky run before the fix; `breakpoint_hit` and `no_orphan` carry the baseline.

## Trial log

Probe scripts were scratch files (not committed): they start the fixture like `run.sh` (JDK 21 first on PATH, `JAVA_HOME` unset, `NVIM_APPNAME=nv4j`, `XDG_STATE_HOME=/tmp/nv4j/state`) and wrap `require("jdtls").start_or_attach` to change one thing. Logs: `/tmp/nv4j/logs/probe-<tag>.log`.

| # | Change (one at a time) | Result | Kept |
|---|------------------------|--------|------|
| t0 | First probe run: wrapped `start_or_attach` before mason.nvim was loaded | jdtls cmd started with `""` (no `$MASON`), EACCES; harness mistake, probe now loads mason.nvim first | n/a |
| t1 | Default bundles (34), sequential calls after ready, LazyVim at-attach fetch left on | all 3 `resolveClasspath` OK (71 entries), but the log shows the at-attach fetch failed once in the same session | evidence |
| t2 | Default bundles, LazyVim at-attach fetch off, 3 **parallel** calls as the first ones (3 runs) | 2 of 3 runs: one call failed with the m2e provider error | evidence (race) |
| t3 | Same, 3 **sequential** first calls (3 runs) | 0 of 3 runs failed | evidence (race) |
| t4 | Only the java-debug bundle (no java-test jars), parallel (3 runs) | 1 of 3 runs failed: bundles are not the cause | rejected (bundle order/missing bundle) |
| t5 | "Clean" bundles (no runner fat jar, jacoco agent, duplicate plugin jar, asm), parallel (2 runs) | 0 of 2 failed (too few runs to separate from t2; t4 already rules bundles out) | rejected |
| t6 | Default, at-attach fetch on, sequential after | OK, no failure that session (race did not hit) | evidence |
| - | "Project not yet built" candidate | the failure happens on calls 5 s after start and never on later calls in the same session, also after the import: timing, not build state | rejected |
| - | "Corretto 25 vs m2e" candidate | same jdt.ls JVM (25.0.4-amzn) resolves fine when calls are sequential | rejected |
| d1-d4 | Launch DemoApplication through `dap.run` with breakpoint in `StartupRunner` | never stopped: app died with `NoClassDefFoundError: GreetingProperties` (jdt.ls build had not seen the new files) | evidence (stale build) |
| d5 | `workspace/didChangeWatchedFiles` (Created) for the 4 new files, wait 20 s | class still missing after 20 s, launch failed | rejected as the fix alone |
| d6 | `java/buildWorkspace` incremental (2.6 s) before launch | `GreetingProperties.class` written; stopped at `StartupRunner.run` line 18 after 3.2 s; JVM still alive after terminate | candidate fix (build before launch) |
| d7 | Traceback on any `start_or_attach` from an unnamed buffer | stray jdt.ls from nvim-dap's `vim.filetype.get_option("java", "path")`; stop after 3.0 s; JVM still alive after terminate | evidence (items 3, 4) |
| s1 | New file written while jdt.ls down, incremental build after ready | autobuild had compiled it after 5 s; after the incremental build the class was gone (not understood, one run) | evidence |
| s2 | Same, plus `didChangeWatchedFiles` Created | not compiled at start; compiled 3 s after the event | evidence |
| s3, s4 | Same as s1 (2 runs) | not compiled at start; incremental build compiled it | evidence |
| c1 | `40_debug` with fixed names `LateRunner`/`LateGreeting` (3 runs) | run 1 failed (`Unresolved compilation problem` in the runner); runs 2 and 3 passed `breakpoint_hit` (4.4 s, 4.5 s): reused names are not "new" files | rejected, names made unique |
| c2 | `40_debug` race through raw `executeCommand` burst (9 calls at attach) | failed 1 of 3 runs; raw calls also bypass any client-side fix | rejected, burst goes through `fetch_main_configs` |
| f1 | Task 1: build before launch only (one incremental `java/buildWorkspace` in a wrapped `dap.adapters.java`), race untouched | `breakpoint_hit` FAIL: build "has compile errors", `LateRunner<N>` compiled with "LateGreeting<N> cannot be resolved" (jdt.ls never saw `LateGreeting<N>`); `configs` "3, no callback, 3" | kept, not enough |
| f2 | + retry `executeCommand` answers with the m2e provider message (wrap of `jdtls.util.execute_command`), + `didChangeWatchedFiles` folder refresh before the build, build again if the first did not succeed | `DONE 40_debug 12 0`; jdt.ls log: first build "Error occured while building workspace", second fine (the refresh landed after build 1) | refresh kept, retry replaced (f3, f8) |
| f3 | + refresh at ServiceReady, launch-time refresh disabled (one run) | build errors 0, `breakpoint_hit` PASS; `configs` FAIL "Could not resolve java executable for demo.Modern": `resolveJavaExecutable` answered `null` in the burst | evidence (second face of the race) |
| f4 | retry also a `null` `resolveJavaExecutable`, moved to a wrap of the client's `request` (nvim-jdtls's `with_java_executable` calls it directly, and `jdtls.lua` keeps a local copy of `util.with_java_executable`) | `breakpoint_hit` FAIL `NoClassDefFoundError: SpringApplication`; classpath sizes logged: one main class with 1 entry instead of 71 | evidence |
| f5 | replaced the retry by serializing the launching commands until one classpath resolved (3 runs) | all three fetches 1 entry per main class, `breakpoint_hit` FAIL 3/3 | evidence |
| f6 | f5 with the ServiceReady refresh removed (2 runs) | every classpath 71 entries; the ServiceReady refresh was what emptied them | ServiceReady refresh dropped |
| f7 | same, more runs (11 runs, f6 included) | JUnit case failed in 4 of 11, silent: notifications none, launch started | evidence |
| f8 | command trace + terminal output in the failure detail (22 runs) | 4 failures, all `ClassNotFoundException: org.junit.platform.engine.OutputDirectoryCreator`; `classpath_first`/`configs` pass in every run from here (69 of 69 from f6 to the final runs) | serialization kept |
| f9 | jdt.ls log, test launch classpaths of 25 sessions | bundled `junit-platform-launcher` 1.14.4 present = run failed, project `junit-platform-launcher-1.12.2.jar` present = run passed, 25 of 25 | evidence (fix 5) |
| f10 | control: orphan kill disabled (one run) | `no_orphan` FAIL "debuggee JVM still running 10 s after terminate" | fix 3 confirmed |
| f11 | control: unnamed-buffer guard disabled (one run, `one_jdtls` counting start calls) | `one_jdtls` FAIL "1 with another root than the project: ." | fix 4 confirmed |
| f12 | `one_jdtls` counting live clients instead (control run) | PASS without the guard: the stray server dies in `initialize` before it is counted | rejected as a test, counts start calls now |
| f13 | JUnit fix by prepending the engine-matching launcher (10 runs) | 1 failure: `NoSuchMethodError` on `org.junit.platform.engine.Output...` (classes only in the bundled 1.14.4 launcher still load from it) | rejected |
| f14 | replace the bundled launcher folder (24 runs, plus the 2 control runs f10/f11) | 24 of 24 `DONE 40_debug 13 0`; replacement used in 3 of the 15 runs that report it | kept (fix 5) |
| f15 | s1 re-check probe (8 runs, above) | without refresh never compiled; with refresh the second build compiles | build twice after the refresh, always |
