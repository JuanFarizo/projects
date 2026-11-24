# Feature: faster run and debug start

Status: measured and one change kept (2026-11-23). Code: `nvim/lua/nv4j/run.lua` (`boot_configs`). Probe: `tests/probes/run_timing.sh` + `run_timing.lua`. Cases: `tests/checks/41_run.lua` `config_same`, `config_requests`, `config_fresh`. Related: `run.md`, `debug-run.md`.

## Where the time goes (before)

`tests/probes/run_timing.sh <maven|gradle> run,run,debug_bp,test` copies the fixture to `/tmp/nv4j/probe-<pid>`, waits for jdt.ls, then times each launch in one Neovim from the key (`R.spring_boot` / `tests.run`). Steps, in ms from the key: **main** = main class + launch config until the build starts; **build** = `nv4j.debug.refresh_and_build` (refresh + two incremental builds); **start** = process or debug session started; **out** = first output line; **up** = Boot's "Started ... in" (run), the breakpoint stop (debug_bp). Machine was shared with other agents (load 2 to 17): numbers are min / median of repeated runs, A/B alternated in the same minutes.

Maven fixture (`demo`), warm = 2nd run onward in the same jdt.ls, cold = 1st launch after jdt.ls was ready:

| step | run cold | run warm | debug bp cold | debug bp warm |
|------|---------:|---------:|--------------:|--------------:|
| main class + config (main) | 200 | 67 | 169 | 59 |
| build (refresh + 2 builds) | 6 | 4 | 6 | 3 |
| until process/session started | 206 | 71 | 413 | 144 |
| first output line | 692 | 473 | 910 | 546 |
| Started / breakpoint hit | 3117 | 2823 | 3438 | 2878 |

Gradle fixture, same columns: run cold 132 / warm 31 main, start 136 / 34, out 543 / 384, up 1341 / 1124; debug bp warm main 30, start 106, out 476, up 1256. (The very first Gradle launch of a fresh checkout compiles the project: build 3968 ms once; that compile is needed by any launch.)

So the part Nv4J controls (main + build, before the JVM starts) is 40 to 100 ms warm, 3 to 7 % of a run, and the JVM start plus Spring (out to up, 2.3 s Maven, 0.75 s Gradle fixture) is the rest. A debug launch adds about 70 ms (java-debug session) and about 0.1 to 0.3 s of JDWP overhead in the JVM.

## What was tried, one change at a time

1. **Build only the owning project** (`java/buildProjects` takes `ProjectBuildParams{identifiers, isFullBuild}`; read from jdt.ls 1.63.0 `BuildWorkspaceHandler`): not built. Both builds are 1 to 3 ms each here (nothing changed since the last launch), and when something changed the same project is compiled either way; the fixtures have one project per workspace. No gain to measure; the incremental builder already skips untouched projects. Reconsider only for a root with many modules, measured.
2. **Classpath and main class without `fetch_main_configs`: kept.** `fetch_main_configs` does a second `resolveMainClass`, then `resolveJavaExecutable`, `checkProjectSettings`, `resolveClasspath` for every main class of the workspace (3 in `demo`), of which only the Boot one is run. `boot_configs` now reuses the one `resolveMainClass` and sends `checkProjectSettings` + `resolveClasspath` for the Boot mains only (no java executable: the launch uses the project JDK). The config has the same fields (case `config_same`). Maven warm main 67 to 36 ms (n 15 each), start 71 to 38; cold main 200 to 126; Gradle warm main 31 to 18, cold 132 to 81; debug bp warm main 59 to 40 (Maven), start 144 to 122. The JVM part is unchanged (within noise).
3. **Cache the launch config per root until a build file changes: not built.** After (2) only about 36 ms are left (resolveMainClass about 20, classpath about 10 to 15). The main class set has to be asked again anyway (a new `@SpringBootApplication` file), so a cache would save at most the classpath request, 10 to 15 ms (0.5 %), and costs the risk of a stale or partial classpath (jdt.ls once answered a classpath without the Maven dependencies right after start, `debug.lua` item 2; a cached bad answer would stay until a build file changed). Case `config_fresh` pins "every launch asks jdt.ls for the classpath", which is what makes a pom or Gradle change that jdt.ls re-imported visible at the next launch.
4. **Skip refresh / serialize waits when jdt.ls is idle: not built.** The serialize gate is already open after the first classpath (`WARMS`), and the refresh is a notification. The two builds cost 2 to 6 ms in total warm; the second one is what catches files the refresh brought in (`debug.lua` `build`), so it stays.

## Not changed

Test run (`<leader>tr`): about 0.6 s for the one-file `GreetingPropertiesTest` run on Maven and Gradle (`test.findTestTypesAndMethods` 150 ms cold, 2 ms warm, `test.junit.argument` 30 to 140 ms); it does not use `boot_configs` and nothing in Nv4J's part stands out. The cold first compile (Gradle 4 s) and Spring's own start are the user's project.

## Unverified

A pom or Gradle edit followed by a launch with a real jdt.ls re-import is not exercised by a check (it is by construction: no cache); a root with many modules was not measured for item 1.
