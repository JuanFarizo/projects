# Feature: JDK selection and Java 25 correctness

Priority: P1. Status: done (Task 4). Tests: `tests/checks/20_java25.lua`.

## How JDTLS picks JVMs (two independent choices)

1. The JVM jdtls itself runs on. The Mason `jdtls` wrapper (`packages/jdtls/bin/jdtls.py`) uses `--java-executable=<path>` if given, else `$JAVA_HOME/bin/java` if that file exists, else `java` from PATH. It refuses Java < 21 (`--validate-java-version`). `--jvm-arg=...` only adds JVM options. Without our fix the server ran on whatever PATH had: with JDK 21 first, jdtls exited with code 13 on this project (red baseline of check 20, see trial log).
2. The JVM used to compile each project. jdtls (jdt.ls) maps `java.configuration.runtimes` (list of `{name="JavaSE-N", path, default}`) to Eclipse execution environments. A Maven project's `release`/`source` is matched to the runtime with that name; the `default` one is used when nothing matches. `java.jdt.ls.java.home` is a legacy alias of choice 1 and is not needed because we pass `--java-executable`.

## How IntelliJ does it

Not verified from source. The local clone `~/.cache/nv4j/intellij-community` is sparse (about 1900 files, only parts of `java/` and `platform/`), and it contains none of `JavaHomeFinder`, `ProjectJdkTable`, `ProjectRootManager`, `LanguageLevelProjectExtension` or Maven importer code (searched by file name). What is stated here is general product behaviour, not sourced: IntelliJ keeps a Project SDK and a language level as separate settings, fills its SDK table by detecting installed JDKs, and the Maven import sets the language level from the pom. nv4j copies that idea only: discover all JDKs, register all, pick the default from the build file.

## Ruling (user, supersedes the brief)

Nothing is pinned to Corretto 25: the user switches JDKs with SDKMAN (lazily loaded, so `java` and `JAVA_HOME` are unreliable in a spawned nvim).

- `require("nv4j.jdk").discover()`: scans in order `$SDKMAN_DIR/candidates/java/*` (default `~/.sdkman`, skipping the `current` link), `~/Library/Java/JavaVirtualMachines/*/Contents/Home`, `/Library/Java/JavaVirtualMachines/*/Contents/Home`. Versions come from each home's `release` file (`JAVA_VERSION`), never from running `java`. `NV4J_JDK_ROOT` (":"-separated) replaces the scan list, tests only.
- `.server_home()`: `$JAVA_HOME` if it is a valid JDK >= 21, else the newest discovered >= 21, else a clear error (lists the searched dirs, suggests `sdk install java 25-amzn`). The result goes into `--java-executable=` and `cmd_env.JAVA_HOME`.
- `.runtimes(root)`: one `JavaSE-<n>` per major >= 8 (8 is `JavaSE-1.8`), preferring `$JAVA_HOME`'s then SDKMAN `current`'s JDK for its major, else the newest. `default=true` goes to the first match of: `.sdkmanrc` `java=` major (only if that major is installed, else falls through), pom `maven.compiler.release`, `java.version`, `maven.compiler.source` (plugin-level `<release>`/`<source>`/`<target>` and `maven.compiler.target` too; `${prop}` resolved up to 5 deep), `$JAVA_HOME` major, newest. Limit: only the project's own pom and `.sdkmanrc` are read. A `java.version`/release inherited from a parent pom (other than the Spring Boot starter parent, whose child pom normally sets `java.version` itself) is not seen and falls through to `$JAVA_HOME`/newest. JDKs without a `release` file (SDKMAN 8.x) get their major from the directory name; `$JAVA_HOME`'s JDK is registered even outside the scan roots; early-access builds are skipped when choosing "newest".
- Set per project in `opts.jdtls` as a function (LazyVim passes it the built config, so `root_dir` is known).
- `java25()` was dropped; nothing needs it.
- jdtls `-configuration` moved to `/tmp/nv4j/jdtls-config/<project>` (`paths.lua`). Equinox creates it itself; the shared config stays read-only in Mason. `/tmp/nv4j/*` base dirs are re-created on every start by `paths.lua`.

## Test design

`tests/run.sh` scrubs `JAVA_HOME` and puts a JDK of `NV4J_PATH_JDK` (default 21) first on PATH; `mvn compile` of the fixture alone gets JAVA_HOME=JDK 25 in its own environment. Check 20 asserts (case 1, fixture release 25): zero errors on `Modern.java`, jdtls reports source/compliance/target 25 and a JDK 25 `vm.location` (via `java.project.getSettings`), and the server process's `java` is `server_home()` and is not PATH's 21. Case 2: a temp Maven project (release 21, sealed/records/pattern switch) under `/tmp/nv4j/proj21` reports 21 and a JDK 21 location with zero errors.

## Trial log

1. Pin JAVA_HOME in run.sh (Task 2 workaround): check passes by construction; proves nothing. Removed.
2. Check 20 (old form) with JDK 21 first on PATH, config untouched: FAIL, `jdtls quit with exit code 13`.
3. Pin Corretto 25 only (first Task 4 implementation): PASS with PATH 21 and 25. Rejected by the user ruling above.
4. Discovery design: PASS with PATH 21 and 25, both cases. Server resolves to SDKMAN `25.0.4-amzn` (newest >= 21), the 21 project to Corretto 21.0.12 (newer than SDKMAN's 21.0.11-graal).
5. Empty scan root: error "no JDK >= 21 found for jdtls. Searched: ..." in the log, nvim exits normally; check 20 reports FAIL only after its own 120 s attach timeout (no hang in nvim).
