# Reference map: where the reference projects implement what Nv4J copies

Date: 2026-11-21. Scope: only features already decided in `specs/`. Nothing here is a new feature.

Reference clones live in `/home/farins/storage/nv4j-intellij-eclipse-spring-tool-repos` (shallow, no history):
`eclipse.jdt.ls`, `eclipse.jdt.core`, `eclipse.jdt.ui`, `spring-tools` (commit `29a3f5f`, 2026-11-20; the specs pin `9c97942`), `intellij-community` (sparse: `java`, `plugins/java-decompiler`, `platform/lang-impl`, `platform/lang-api`).

How this was made: four read-only agents mapped the specs to the code. Paths were checked with grep. "How it works" lines are mostly inferred from names and specs, not from reading every method body. No speed number here is new; they come from the specs or are marked as expectations.

Not in the clones (needed for some rows): `vscode-java-test` (jdt.ls test running), `java-debug`, IntelliJ `plugins/junit`, `plugins/testng`, `platform/smRunner`, IntelliJ Maven importer code. The jdt.ls clone may be newer than the installed jdt.ls 1.63.0, and the installed Spring LS (Mason, built 2026-06-05) is older than the clone, so "exists upstream" is not "exists in the server Nv4J runs".

## Prefixes

- `JLS` = `eclipse.jdt.ls/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal`
- `JUI` = `eclipse.jdt.ui`
- `REF` = `eclipse.jdt.ui/org.eclipse.jdt.core.manipulation/refactoring/org/eclipse/jdt/internal/corext/refactoring`
- `BOOT` = `spring-tools/headless-services/spring-boot-language-server/src/main/java/org/springframework/ide/vscode/boot`
- `IJ` = `intellij-community`

## Findings that change something (ranked by value)

1. **Gradle AOT lens (jpa.md, parked).** Cause is most likely version drift, not a Nv4J bug. The installed `jdt-ls-commons.jar` has no `GradleTasksStore` and its `ProjectBuild` has no `tasks` field; the installed `DataRepositoryAotMetadataService` has no Gradle regenerate branch. Gradle metadata is read from a classpath source folder named `aotResources` (`BOOT/java/data/DataRepositoryAotMetadataService.java:260-266`), which Buildship probably does not expose for `build/generated/aotResources`. Two probes settle it: print the build record in the classpath events (`spring.lua` `count_events`), and check whether `java.project.getClasspaths` lists an `aotResources` folder. Fix path: pin a newer `vscode-spring-boot-tools`.
2. **Completion ranking.** jdt.ls sorts by JDT relevance and cuts to `maxResults` (200) before Nv4J's Lua re-rank sees the items (`JLS/contentassist/CompletionProposalRequestor.java:292`). That cut is why `@Service` stays hidden until a letter is typed. Warm p95 is under 45 ms, so the server is not the steady-state cost; remaining latency is the cold type list and the per-item Javadoc resolve (not cached, 750 ms timeout, `CompletionResolveHandler.java:366-378`). Candidate changes, each to be measured alone: `java.completion.matchCase=firstLetter` (opt-in), `collapseCompletionItems`, cheaper `guessMethodArguments`, `favoriteStaticMembers` generated from the classpath, tie-breakers in `java_sort` (shorter name, non-generic, same-package proximity, from IntelliJ `JavaCompletionSorting.java:96-157`), longer documentation auto-show delay. Only real fix for the cap: a small jdt.ls bundle implementing `ICompletionRankingProvider` (`CompletionProposalRequestor.java:381-404`), high cost.
3. **Results view (tests-runner.md).** Eclipse builds the test tree up front from `%TSTTREE` and updates nodes by id (`JUI/org.eclipse.jdt.junit.core/.../model/TestRunSession.java:295,721,741,792,828`). Nv4J redraws the whole buffer per event (`testresultsui.lua:79`). Changes: pre-seed class > method tree, add running/not-run state (`TestElement.java:30-37`), throttle refresh, put the cursor on the first failure once (`TestViewer.registerFailedForAutoScroll`). IntelliJ reruns leaf tests only (`JavaRerunFailedTestsAction.java:23-30`); decide the policy for class-level failures. TestNG has no reference in the clones.
4. **Library navigation (library-navigation.md).** Reopen the buffer when the lazy sources download finishes (jdt.ls waits 3 s, `MavenSourceDownloader.java:48`). IntelliJ starts decompiling before the editor needs it (`IdeaDecompiler.kt:55,80,124`); Nv4J could start CFR in parallel for jar classes with no sources jar. Bound the unbounded decompile cache (jdt.ls uses an LRU, `DecompilerImpl.java:30-55`). Check that CFR output includes inner classes (IntelliJ feeds them with the outer class, `IdeaDecompiler.kt:136-137`).
5. **Hierarchy (hierarchy.md).** Subtypes are the slow request (`TypeHierarchyHandler.java:162-163` builds a workspace hierarchy; 68 to 1300 ms measured). Cache level-1 answers per item so a repeat press is instant.
6. **Refactors (refactors.md).** `refactor.lua` (3847 lines) hand-writes what JDT does natively: variable renaming (jdt.ls `similarDeclarations`, `REF/rename/RenameTypeProcessor.java`), package rename merge and clash logic (`RenamePackageProcessor.java`), move conflict checks (up to 30 reference requests; `JavaMoveProcessor.java`, `MoveHandler.getMoveDestinations` `:103`). Send a folder move to `willRenameFiles` in one request. Verify each trim against the audit table before removing code.
7. **Code actions (code-actions.md).** Possible quick wins to verify against jdt.ls 1.63.0 first: text block (`QuickAssistProcessor.java:1252`), class to record (`:264`), extract interface (`RefactorProposalUtility.java:1096`), extract field `initializeIn` scopes (`:701`, `:772`). Replace the `vim.fn.input` number picker for override and delegate with `vim.ui.select` multi-select.
8. **Smaller, cheap.** Add `SDKMAN_CANDIDATES_DIR` to `jdk.lua` discovery (`IJ/platform/lang-impl/.../JavaHomeFinderBasic.java:~278-354`; mise and asdf homes too). Expand `$ENV$` in `.nv4j` `vm_args` like `JavaParametersUtil.java:60-79`. Build only the owning project before run (`BuildWorkspaceHandler.java:68` builds all). Print the AOT validity predicate in `:Nv4JHealth` (`QueryMethodCodeActionProvider.java:55-64`). Cache `route_client` results per root.

## Stale statements in the specs

- `specs/features/jdk-java25.md` says IntelliJ `JavaHomeFinder*`, `JavaParametersUtil` and `JavaCommandLineState` are absent; they are in the clone now.
- `specs/features/project-root.md` cites the IntelliJ Maven importer (`MavenProjectsTree`, `findAggregator`); it is not in the clone, so the row cannot be re-checked.
- jdt.ls rows saying "not offered in 1.63.0" (extract interface, text block, class to record) may be true only for the installed version.

## Row tables

The agents' full tables (about 130 rows with file:line and symbol) were returned in the session and are summarised above. Re-run the mapping per feature when starting its work; do not trust a row without re-grepping, because the clones will move.
