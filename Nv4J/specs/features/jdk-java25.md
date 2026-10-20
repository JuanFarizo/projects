# Feature: JDK selection and Java 25 correctness

Priority: P1. Status: done (Task 4). Tests: `tests/checks/20_java25.lua`.

## How JDTLS picks JVMs (two independent choices)

1. The JVM jdtls itself runs on. The Mason `jdtls` wrapper (`packages/jdtls/bin/jdtls.py`) uses `--java-executable=<path>` if given, else `$JAVA_HOME/bin/java` if that file exists, else `java` from PATH. It refuses Java < 21 (`--validate-java-version`). `--jvm-arg=...` only adds JVM options. Without our fix the server ran on whatever PATH had: with JDK 21 first, jdtls exited with code 13 on this project (red baseline of check 20, see trial log).
2. The JVM used to compile each project. jdtls (jdt.ls) maps `java.configuration.runtimes` (list of `{name="JavaSE-N", path, default}`) to Eclipse execution environments. A Maven project's `release`/`source` is matched to the runtime with that name; the `default` one is used when nothing matches. `java.jdt.ls.java.home` is a legacy alias of choice 1 and is not needed because we pass `--java-executable`.

## How IntelliJ does it

Project SDK and language level are separate settings (`ProjectRootManager` SDK vs `LanguageLevelProjectExtension`). The SDK table is filled by scanning known JDK locations (`JavaHomeFinder`, in `~/.cache/nv4j/intellij-community/java/java-impl`-adjacent code, `jdk` detectors under `platform/lang-impl/.../projectRoots`), and the Maven importer derives the language level from `maven.compiler.release/source/target`. We copy the idea, not code: scan all JDKs, register all, pick the default from the build file.

## Ruling (user, supersedes the brief)

Nothing is pinned to Corretto 25: the user switches JDKs with SDKMAN (lazily loaded, so `java` and `JAVA_HOME` are unreliable in a spawned nvim).

- `require("nv4j.jdk").discover()`: scans in order `$SDKMAN_DIR/candidates/java/*` (default `~/.sdkman`, skipping the `current` link), `~/Library/Java/JavaVirtualMachines/*/Contents/Home`, `/Library/Java/JavaVirtualMachines/*/Contents/Home`. Versions come from each home's `release` file (`JAVA_VERSION`), never from running `java`. `NV4J_JDK_ROOT` (":"-separated) replaces the scan list, tests only.
- `.server_home()`: `$JAVA_HOME` if it is a valid JDK >= 21, else the newest discovered >= 21, else a clear error (lists the searched dirs, suggests `sdk install java 25-amzn`). The result goes into `--java-executable=` and `cmd_env.JAVA_HOME`.
- `.runtimes(root)`: one `JavaSE-<n>` per major >= 8 (8 is `JavaSE-1.8`), preferring `$JAVA_HOME`'s then SDKMAN `current`'s JDK for its major, else the newest. `default=true` goes to the first match of: `.sdkmanrc` `java=` major, pom `maven.compiler.release`, `java.version`, `maven.compiler.source` (one level of `${prop}`), `$JAVA_HOME` major, newest. Only the project's own pom/.sdkmanrc is read (parent poms are not followed: a Spring Boot parent sets `java.version` itself in the child pom, which is covered).
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
