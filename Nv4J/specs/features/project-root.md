# Feature: project root for a Maven module (aggregator)

Priority: P4. Status: decided 2026-11-05 (user ruling): match IntelliJ, no code change in `root.lua`. Check `75_maven_parent` (6 unit cases) pins it.

## IntelliJ behaviour (source read)

Pinned: `jetbrains/intellij-community` sparse clone `~/.cache/nv4j/intellij-community`, widened 2026-11-05 with `plugins/maven/src/main/java/org/jetbrains/idea/maven/{project,utils}`.

- `MavenProjectsTree.kt` `findAggregator` (line 597) returns `myModuleToAggregatorMapping[project.path]`: a module's aggregator is known only through the `<modules>` list of a pom that is already imported. Nothing climbs from a submodule to a parent pom on its own.
- Opening the folder of a submodule imports that module only; opening the parent imports the tree.

## Nv4J rule (unchanged)

- The folder that holds a `.nv4j` file is where the project starts (D25): that folder is the jdt.ls root and every module below it is a child. To get siblings resolved, put `.nv4j` in the aggregator folder (`:Nv4jMark`).
- Without `.nv4j`: git root with a build file wins, else the nearest build file (a module opened alone is its own root, like IntelliJ).
- A `.nv4j` in a folder with no build file beside it does not swallow a module's pom (D25 kept).

## History

2026-11-05 a climb rule (`maven_parent_root`, commit `3fdc4e8`) was built and then removed the same day on the user's ruling: it went beyond IntelliJ. Control: with that code back, `module_alone` FAILS (`/tmp/nv4j/logs/control-75b.log`).

## Checks

`75_maven_parent` (unit, root.project only): module_alone, nv4j_parent, nv4j_parent_core, nv4j_two_levels, nv4j_no_pom, git_root_pom. Not run live with jdt.ls (a `.nv4j` aggregator with a module depending on a sibling: one jdt.ls, no error) because the machine is in use; do it when free.
