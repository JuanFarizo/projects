# Feature: project root for a Maven module (aggregator)

Priority: P4. Status: built 2026-11-05 (`nv4j/root.lua` `maven_parent_root`, check `75_maven_parent`, 7 unit cases with a control). NOT yet run live with jdt.ls.

## IntelliJ behaviour (source read)

Pinned: `jetbrains/intellij-community` sparse clone `~/.cache/nv4j/intellij-community`, widened 2026-11-05 with `plugins/maven/src/main/java/org/jetbrains/idea/maven/{project,utils}`.

- `MavenProjectsTree.kt` `findAggregator` (line 597) returns `myModuleToAggregatorMapping[project.path]`: the aggregator is known only through the `<modules>` list of a pom that is already imported (managed). `findRootProject` follows it up. Nothing climbs from a submodule to a parent pom on its own.
- So in IntelliJ, opening the folder of a submodule alone imports that module only; opening (or importing) the parent imports the whole tree. The parent link is the user's choice of what to open.

## Nv4J rule

- Nv4J has no "open project" step: the jdt.ls root is derived from the file (`root.project`). Existing rule 2: the git root wins when it holds a build file; else the nearest build file.
- Gap found: a monorepo whose git root has no pom (`repo/backend/pom.xml` lists `app` and `core`) gave the module as root, so a sibling module did not resolve.
- Enhancement (deliberate difference from IntelliJ): after the nearest pom is found, climb while the parent directory's pom lists the directory below it in `<module>` (comment-stripped, `app/pom.xml` and a trailing slash accepted). The top one is the root. Never reaches $HOME or above. Gradle is separate (D29, nearest `settings.gradle*`).
- Escape: a `.nv4j` file in the module folder wins (rule 1) if you want a module alone.

## Cost if wrong

A user who wants only one module of a big aggregator now gets all its modules imported by jdt.ls (slower first start, more memory). `.nv4j` in the module is the way back. Not measured.

## Checks

`75_maven_parent` (unit, root.project only): parent_listed, parent_listed_core, two_levels, not_listed (a commented module does not count), module_pom_path, module_trailing_slash, no_parent. Control: removing the call fails 5 of 7 (`/tmp/nv4j/logs/control-75.log`).
To run when the machine is free: live case (two modules, app uses core, one jdt.ls, no error in app), plus checks 62, 64, 68 on this tree.
