# Feature: Java completion ranking and filtering

Priority: P1. Status: implemented (Task 5), see "Implemented design" below; trial log and final numbers in `specs/002-p1-completion.md`. Baseline numbers are in `specs/002-p1-completion.md`.

Pass/fail tests: `tests/checks/10_completion_latency.lua` (latency, result counts) and `tests/checks/11_completion_ranking.lua` (rank of the expected item in the order the user sees).

## Sources read

| Repo | Local copy (read only, not committed) | Commit | License |
|------|----------------------------------------|--------|---------|
| intellij-community | `~/.cache/nv4j/intellij-community` | `b633034bb` | Apache 2.0 |
| eclipse.jdt.core | `~/.cache/nv4j/eclipse.jdt.core` | `cd40048` | EPL-2.0 |
| eclipse.jdt.ls | `~/.cache/nv4j/eclipse.jdt.ls` | `b52e20a` | EPL-2.0 |
| blink.cmp v1.10.2 | `~/.local/share/nv4j/lazy/blink.cmp` | `78336bc` | MIT |

The installed server is jdt.ls 1.63.0 with jdt.core 3.48.0 (Mason). The clones are current `master`, so line-level details can differ slightly from what runs. Nothing below is copied code. EPL-2.0 code must not be copied into this repo without its header and a note.

## How IntelliJ orders Java completion

IntelliJ sorts with a chain of "weighers". Each weigher gives every item a value. Items are compared by the first weigher, ties go to the next one, and so on. Some steps are "classifiers" that regroup items instead of comparing pairs.

### The chain

The base chain comes from `CompletionService.defaultSorter` in `platform/analysis-impl/src/com/intellij/codeInsight/completion/BaseCompletionService.java`. The weighers registered for the `completion` key are ordered in XML:

- `platform/analysis-impl/resources/intellij.platform.analysis.impl.xml`: `priority` (first), `prefix` (after priority), `stats` (after prefix), `grouping` (last).
- `platform/lang-impl/resources/intellij.platform.lang.impl.xml`: `explicitProximity` (after stats), `proximity` (after explicitProximity).

Java adds its own weighers in `JavaCompletionSorting.getSorter` (`java/java-impl/src/com/intellij/codeInsight/completion/JavaCompletionSorting.java`). Put together, the order for normal ("basic") completion is roughly:

1. **Start match** (`PreferStartMatching`, `platform/analysis-impl/src/com/intellij/codeInsight/completion/impl/PreferStartMatching.java`). Items whose name starts with the typed prefix come before items that only match in the middle.
2. **Prefer non-void** in a value position (`PreferNonVoid`, added "before middleMatching" when the reference is not in a void context).
3. **Priority** (`PriorityWeigher`): explicit priority set by a contributor, for example live templates.
4. **Real prefix match** (`prefix`): exact or case-matching prefix before fuzzy camel-hump matches.
5. **Statistics** (`StatisticsWeigher`, `platform/analysis-impl/src/com/intellij/codeInsight/completion/StatisticsWeigher.java`). How often the user picked this item before, in this context. The context key comes from `JavaCompletionStatistician` (`java/java-impl/.../JavaCompletionStatistician.java`): for a method or field it is the qualifier type plus the expected variable name, for a class it is "after `new` with expected type X" or "exception position" or plain. Locals, parameters and keywords get no statistics at all, so they are never pushed around by history.
6. **Kind** (`PreferByKindWeigher`, `java/java-impl/.../PreferByKindWeigher.java`). This is where locality lives. Its result enum is ordered best first: `annoMethod`, `probableKeyword`, `castVariable`, `expectedTypeVariable`, `lambda`, method refs, `variable`, `getter`, ... `normal`, ... `suitableClass`, `nonInitialized`, `classNameOrGlobalStatic`, `introducedVariable`, `unlikelyItem`, `improbableKeyword`. So locals, parameters and instance fields of the expected type come first, other locals and fields next, classes and global statics near the end, and keywords that do not fit the position last. Annotation positions prefer annotation types whose `@Target` allows the current element (`createSuitabilityCondition`). Catch and `throws` positions prefer exception classes actually thrown in the block.
7. **Expected type** (`PreferExpected`, enum `ExpectedTypeMatching`: `ofDefaultType`, `expected`, `maybeExpected`, `normal`, `unexpected`). Items assignable to the expected type rise; `new` and `null` count as "maybe expected" when a non-void type is expected. After `new`, this weigher moves even earlier (before `liftShorter`).
8. **Statics** (`preferStatics`), **recursion** (`RecursionWeigher`, pushes the method you are inside down), **similar ending names** (`PreferSimilarlyEnding`), **non-generic**, **simple**.
9. **Proximity** (`LookupElementProximityWeigher`, `platform/lang-impl/.../LookupElementProximityWeigher.java`), which itself is a chain registered under the `proximity` key: accessible, explicitly imported, opened in editor, same directory, same module, in resolve scope, and SDK or library last (`intellij.platform.lang.impl.xml`, `java/java-backend/resources/META-INF/JavaPlugin.xml`). This is why project classes beat JDK classes with the same prefix.
10. After proximity: most-used (`PreferMostUsedWeigher`), names containing words of the expected name (`PreferContainingSameWords`), shorter names (`PreferShorter`), technical overloads last.

On top of this, `liftShorter` lifts a shorter item above longer items that start with it (`List` above `ListIterator`).

### Filtering and limits

- **Classes that are not imported** are only added when the user typed at least one character: `InternalCompletionSettings.mayStartClassNameCompletion` returns true only for a non-empty prefix (`platform/analysis-api/src/com/intellij/codeInsight/completion/InternalCompletionSettings.java`). On the first invocation they are also filtered by scope and by the "exclude from completion" package list (`AllClassesGetter.isAcceptableInContext`, `JavaCompletionUtil.isInExcludedPackage`). Pressing the shortcut again (`getInvocationCount() >= 2`) widens the search: inaccessible classes, more chained calls, and so on (`JavaCompletionContributor.isClassNamePossible`, `JavaClassNameCompletionContributor.addAllClasses`).
- **Size limit**: `BaseCompletionLookupArranger.trimToHalfLimit` keeps at most the `ide.completion.variant.limit` registry value; when exceeded it keeps the top-priority, prefix-matching and best-ranked items, cuts to half, shows "not all variants are shown", and restarts completion on the next prefix change.
- **Top of the list**: `fillModelByRelevance` puts priority items, exact-prefix items and up to `MAX_PREFERRED_COUNT = 5` best-relevance items first, then freezes those top items so they do not jump while more results stream in.
- There is also an optional ML ranker (`plugins/completion-ml-ranking`), not used as reference here.

## How JDT (eclipse.jdt.core) scores proposals

JDT gives each proposal an integer relevance. It is a sum of constants from `org.eclipse.jdt.core/codeassist/org/eclipse/jdt/internal/codeassist/RelevanceConstants.java`, computed by the `computeRelevanceFor*` methods in `CompletionEngine.java` (around lines 4238 and 4827 to 5100). There is one score, not a chain of tie breakers.

| Signal | Constants | Where |
|--------|-----------|-------|
| Base | `R_DEFAULT = 30`, `R_RESOLVED = 1`, `R_INTERESTING = 5`, `R_NON_RESTRICTED = 3` (no access rule) | `computeBaseRelevance`, `computeRelevanceForResolution`, `computeRelevanceForInterestingProposal`, `computeRelevanceForRestrictions` |
| Name match | exact name `R_EXACT_NAME = 4`, same case `R_CASE = 10`, camel case `R_CAMEL_CASE = 5`, substring `R_SUBSTRING = -21`, subword `R_SUBWORD = -22` | `computeRelevanceForCaseMatching` |
| Expected type | exact type `R_EXACT_EXPECTED_TYPE = 30`, same package `R_PACKAGE_EXPECTED_TYPE = 25`, compatible or boxing-compatible `R_EXPECTED_TYPE = 20`; a `void` method when a type is expected gets `R_VOID = -5` | `computeRelevanceForExpectingType` |
| Position kind | the assist node expects a class/interface/enum/annotation/exception: `R_CLASS`, `R_INTERFACE`, `R_ENUM`, `R_ANNOTATION`, `R_EXCEPTION` = 20 each; enum constant of expected enum `+5`; annotation whose `@Target` fits `R_TARGET = 5` | `computeRelevanceForClass`, `...ForAnnotation`, `...ForAnnotationTarget`, `...ForException`, `...ForEnumConstant` |
| Qualification | unqualified access `R_UNQUALIFIED = 3`, qualified `R_QUALIFIED = 2`; non-static member in a qualified reference `R_NON_STATIC = 11`; member declared in the receiver type itself `R_NON_INHERITED = 2` | `computeRelevanceForQualification`, `...ForStatic`, `...ForInheritance` |
| Library | package starts with `java.` gets `R_JAVA_LIBRARY = 2` | `computeRelevanceForJavaLibrary` |
| Other | constructor `R_CONSTRUCTOR = 3`, final where final expected `R_FINAL = 3`, no problems `R_NO_PROBLEMS = 1` | |

Keywords are scored with the same base plus case matching (`findKeywords`, near line 9068); `true`/`false` get the boolean expected-type bonus. Static imports: members listed in `java.completion.favoriteStaticMembers` are proposed even when not imported (jdt.ls passes them to JDT as favourite references); they are scored like other members. In the baseline, `Objects.checkFromIndexSize` and friends appear after locals and project types with an empty prefix after `=`.

Compared with IntelliJ: JDT has expected type, name case, qualification and the "position wants a class/annotation/exception" bonus. It has no usage statistics, no proximity chain (same file, same module, project before library), and no "local beats field beats class" kind order except what falls out of unqualified and expected-type bonuses. A JDK class gets `+2` for being in `java.*`, which slightly favours the JDK over project code.

## How jdt.ls turns relevance into LSP items

- `CompletionProposalRequestor` (`org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/contentassist/CompletionProposalRequestor.java`) sorts proposals with `ProposalComparator`: relevance descending, then proposal kind, then name, then parameter count. Optional `CompletionRanking` providers can add up to 100 to the relevance (none are installed by default).
- It then keeps only the first `java.completion.maxResults` items (default 50). If more existed it sets `isIncomplete = true`, which tells the client to ask again on every keystroke.
- `SortTextHelper.computeSortText` writes `sortText = 999999999 - (relevance * 16 + kindOffset)`, so a client sorting by `sortText` ascending gets jdt.ls's order.
- `isFiltered` drops types matching `java.completion.filteredTypes`.

jdt.ls settings that matter here (`internal/preferences/Preferences.java`):

| Setting | Effect |
|---------|--------|
| `java.completion.maxResults` | Item cap. When hit, `isIncomplete = true` and the client re-requests on each keystroke. This config: 200. |
| `java.completion.filteredTypes` | Package or type patterns removed from results and auto-import. This config: `com.sun.*`, `sun.*`, `jdk.internal.*`. |
| `java.completion.favoriteStaticMembers` | Static members proposed without import (JUnit, Mockito, AssertJ, Objects in this config). |
| `java.completion.matchCase` | `firstLetter` or `off`: whether the first letter must match case. |
| `java.completion.guessMethodArguments` | Insert text for method arguments. Not ranking, but changes item size and resolve cost. |
| `java.completion.importOrder`, `java.completion.collapseCompletionItems`, `java.completion.chain.enabled`, `java.completion.postfix.enabled`, `java.completion.lazyResolveTextEdit.enabled` | Insert behaviour, overload collapsing, chain and postfix proposals (more items), lazy edits (cheaper first response). |

## How blink.cmp orders items

Source: `lua/blink/cmp/fuzzy/init.lua`, `fuzzy/sort.lua`, `fuzzy/rust/fuzzy.rs`, `config/fuzzy.lua`, `config/sources.lua`, `sources/lsp/completion.lua`.

- Score per item = fuzzy match score + `score_offset` + frecency bonus + proximity bonus (`fuzzy.rs`). Frecency (items you accepted recently and often) and proximity (label appears in the 30 lines around the cursor) are on by default, but only add when at least one character is typed.
- Provider `score_offset` defaults: lsp 0, path +3, snippets -1 (plus -3 from `snippets.score_offset`), buffer -3. Deprecated LSP items get -2.
- Default `fuzzy.sorts = { 'score', 'sort_text' }`. This config keeps the default (it tried a kind sort before and dropped it, see the comment in `nvim/lua/plugins/blink.lua`). Other built-in sorts: `exact`, `kind`, `label`; any Lua function `(a, b) -> boolean|nil` can be a sort step, which turns off the Rust sort path.
- `max_typos` is set to 0 in this config, so only real fuzzy matches survive.
- `completion.list.max_items` default 200.
- With an empty prefix every score is equal, so blink shows exactly jdt.ls's `sortText` order. With a prefix, items with a better fuzzy match (start of word, case) win first and `sortText` only breaks ties.
- If the LSP returns `isIncomplete = true`, blink re-requests on each keystroke instead of filtering the cached list.

## Gap analysis (from the baseline)

| IntelliJ behaviour | What we have | Gap |
|--------------------|--------------|-----|
| Expected-type local first | jdt.ls ranks `nobody` (local of expected type) first; blink keeps it | none on the fixture |
| Field before library classes with same prefix | `age` first, but ranks 2 to 11 are `com.apple.laf.resources.aqua_*` JDK internals | noise not filtered; IntelliJ hides it by scope and proximity |
| Project classes before JDK (proximity) | only `R_JAVA_LIBRARY` (+2 for JDK), the opposite direction | missing; partly fixable with a blink sort that boosts items whose package starts with the project package |
| Usage statistics | blink frecency, keyed by item label and kind, global, not per context | weaker than IntelliJ's per-context stats, but present |
| Annotation list prefers fitting project annotation | `@`: `MyAnno` rank 5, after the four `java.lang` annotations | small gap |
| Package member list (`java.util.`) ranked by usefulness | strictly alphabetical, `List` rank 57 of 124 | JDT has no usage signal here; only frecency helps |
| Non-imported classes only after a typed character | after `Person best = ` (empty prefix) jdt.ls returned 29 items: locals, project types and favourite statics, no JDK type flood | none seen |
| Result cap that keeps the best and refreshes | `maxResults = 200`, `isIncomplete = true` on `a` (203 items) so every keystroke is a new server round trip | latency risk on large classpaths |
| `new Person(` | returns 5 items: `Person` constructor plus `toString`/`toIdentityString` | not a ranking problem; the useful thing there is signature help, already enabled |

## Candidate Neovim approaches, ranked

Ranked by expected gain against cost and risk. Task 5 tries them one at a time and keeps only what improves a number.

1. **Extend `java.completion.filteredTypes`** with `com.apple.*` (and other platform internals that show up, such as `apple.*`, `javax.swing.plaf.*` if seen). Config only, removes the visible noise in the identifier case, also shrinks lists and keeps them under the cap.
2. **Tune `java.completion.maxResults`** against the cap and `isIncomplete` trade-off: a lower cap makes each response cheaper but forces a re-request per keystroke; a higher cap lets blink filter locally. Measure both on a larger classpath before deciding.
3. **Blink sort with a project-first tie breaker**: keep `score` and `sort_text`, and add a Lua sort function after `score` that prefers locals/fields and project-package types over library types when scores tie (the IntelliJ proximity idea). Risk: Lua sorts disable the Rust sort path; the baseline shows blink sorting costs under 2 ms for 200 items, so the cost is acceptable. Must not repeat the earlier mistake of a pure kind sort that buried keywords.
4. **Keep frecency on** (default) as the statistics substitute. Nothing to change, but checks should run with a stable frecency DB so ranks stay reproducible.
5. **Lazy resolve and fewer extras**: `java.completion.lazyResolveTextEdit.enabled`, `guessMethodArguments` off or `insertParameterNames`, chain/postfix off if they add items. Only if latency on a large project needs it.
6. **Small Lua re-ranker** using `labelDetails.description` (package) and the buffer's package declaration. Only if 1 to 3 are not enough. More code to keep.

## Findings added in Task 5

- **Why blink pushed members below postfix templates.** jdt.ls sends postfix templates as Snippet items whose `filterText` repeats the receiver (`http.cast`) and whose edit starts at the receiver. blink guesses the match needle from that text (`keyword.rs` `guess_keyword_range`), so it matches `http.` against `http.cast` and scores 89, while real members score 0 against the empty keyword. That is why ranks were worse in blink's order than in jdt.ls's.
- **Member lists are alphabetical in jdt.ls.** After `http.` every member has the same relevance (`sortText` 999999035), so without usage data the order is alphabetical: removing the postfix templates alone leaves `authorizeHttpRequests` at 9 and `save` at 32.
- **IntelliJ's `PreferMostUsedWeigher`** (`java/java-impl/src/com/intellij/codeInsight/completion/PreferMostUsedWeigher.java`) ranks members by their compile-time occurrence count in the project, skips `java.lang.Object`'s methods (`hashCode`, `equals`, `toString`, ...) and helper methods taking or returning `Object`. It sits after the kind, expected-type and proximity weighers.
- **JDT gives `java.*` types +2** (`R_JAVA_LIBRARY`), which in sortText is exactly the gap between `@Deprecated`/`@SuppressWarnings` (999998732) and the project's imported annotations (999998764).
- **Packages are not filtered.** jdt.ls applies `filteredTypes` to types, constructors and methods (`CompletionProposalRequestor.isFiltered`), not to `PACKAGE_REF`; a bare `s` returned 187 fully qualified `sun.*` packages out of 211 items.
- **The 200-item cap on `@` is alphabetical by package.** The class-level `@` list has 504 candidates; with `maxResults = 200` it ends inside `jakarta.*`, so `@Service`/`@Component` only appear after a letter is typed (the list is `isIncomplete`, blink asks again).
- **The first type list after start is slow** (0.7 to 0.9 s with Spring Boot) because JDT opens the library jars and reads the binary type of every candidate (JFR: `ZipFile$Source.initCEN`, `BinaryTypeFactory.readType`); later lists reuse that. A prefixed completion, a `workspace/symbol` query, an idle wait, a CDS archive, ParallelGC and `maxResults` 50 or 1000 do not change it. The cache survives the start-up build (fix round 1: a request at `Started` fills it, the one at ServiceReady then takes about 70 ms; an earlier note here said the build resets it, which was a measurement error).
- IntelliJ's postfix completion contributor is not in the sparse clone; "postfix templates after members" is IntelliJ's visible behaviour, not verified from source.

## Implemented design (Task 5)

All Java-only; other filetypes get blink's defaults (Rust sort path, no transform).

1. `java.completion.filteredTypes` (`nvim/lua/nv4j/completion.lua` `DEFAULT_FILTERED_TYPES`, user override `vim.g.nv4j_filtered_types`, see 002): `com.sun.*`, `sun.*`, `jdk.internal.*`, `jdk.javadoc.internal.*`, `com.apple.*`, `apple.*`, `java.applet.*`, `aj.*`, `org.aspectj.internal.*`, `java.awt.List`, `java.awt.peer.*`. Public `jdk.*` APIs, `java.awt.*` and `javax.swing.*` stay visible.
2. blink `sources.providers.lsp.transform_items` (`nvim/lua/nv4j/completion.lua`):
   - postfix templates: `filterText` reduced to the template key and `score_offset - 6`, so they come after members (and after deprecated members, -2) but stay reachable by key (`http.va` lists `var` first);
   - fully qualified packages dropped for a bare identifier, root packages kept unless `filteredTypes` removes the whole root;
   - per item: jdt.ls relevance from `sortText` minus the `java.*` bonus, project usage count, jdt.ls position.
3. blink `fuzzy.sorts` for Java: `score`, then `java_sort` (relevance without the `java.*` bonus, then project usage, then jdt.ls order). It replaces `sort_text`, so blink sorts in Lua for Java buffers (strict weak order, about 1 ms).
4. Project usage (`nvim/lua/nv4j/usage.lua`): ripgrep counts `.name` and `@Name` tokens in the project's `.java` files (import/package lines skipped) in the background at attach (`java.lua` on_attach, the only place), and again 1.5 s after the last `.java` write (debounced). A run where either rg fails (exit >= 2) or passes 10 s (process group killed) keeps the previous counts. Name level, not resolved references (`save` used on any receiver counts). Object's methods get no count. Without ripgrep the step is a no-op. Check: `tests/checks/12_usage_index.lua`.
5. blink `sources.providers.snippets.should_show_items`: no live templates after `.` or `@`.
6. Warm-up (`nvim/lua/nv4j/warmup.lua`): one completion request at an existing annotation (`@|Foo`) or `new |Foo` position on jdt.ls `Started` (pays the one-time cost during import, before the start-up build competes) and one on `ServiceReady` (about 70 ms then); results discarded, buffer untouched, once per client and phase.

What was tried and dropped is in the 002 trial log.

## Pass/fail criteria

- Latency: p95 <= 150 ms warm per case, <= 400 ms for the first request after jdtls is ready (confirmed, `specs/001-architecture.md` D13).
- Ranking: expected item in the top 5 of the blink-visible order, plus the relative rule of each case (local above keywords, field above non-project types).
- Task 5 added: ranks measured through blink's own pipeline (`M.menu` in `tests/lib/completion.lua`), `menu_p95` under the same 150 ms budget, typed-prefix and postfix-key cases, and rule cases (snippets after every member after `.`; no filtered type or qualified package for a bare identifier).

## Experiments after the reference map (docs/REFERENCE-MAP.md finding 2)

One change at a time, each measured with `tests/checks/10_completion_latency.lua`, `11_completion_ranking.lua` and the new `13_completion_tiebreak.lua` (ranks through blink's pipeline). Run with the worktree config (`XDG_CONFIG_HOME` pointing at a folder whose `nv4j` link is this repo's `nvim`), machine idle (load under 1), one run at a time. Baseline before any experiment: check 10 `DONE 17 0` (menu p95 8 to 40 ms, noise about 5 ms), check 11 `DONE 26 0`. Source of the tie-breaker ideas: IntelliJ `JavaCompletionSorting.java` (`PreferShorter` `:738`, `PreferNonGeneric` `:519`, `isTooGeneric` `:545`; they sit after the stats and proximity weighers, so they only break ties).

Check 13 is written to fail on the baseline: jdt.ls gives every `java.util` type the same relevance and lists them alphabetically, so `List` is 57th of 124 and `java.io.File` is 26th of 84.

| # | Experiment | Result | Decision |
|---|------------|--------|----------|
| 1a | Shorter type name first, after usage (`java_sort`, and after frecency in `java_sort_empty`) | `java.util.` `List` 57 -> 4 (check 10 `java_util_pkg`, check 13 `shorter_java_util`), `java.io.` `File` 26 -> 1 (`shorter_java_io`); check 10 `DONE 17 0`, check 11 `DONE 26 0`; menu p95 unchanged within noise. First variant (every item kind) broke check 11 `column_attrs` (`nullable` 5 -> 6) and moved `http.` `authorizeHttpRequests` 2 -> 4, so only types get a length. Side effect: `@RestController` of the Spring annotation list 1 -> 2 (budget 5), `MyAnno` of the plain `@` list 2 -> 1 | kept, types only |
| 1c | Same-package proximity after usage, before length: type whose `labelDetails.description` is the file's package (tier 0), shares its first two package segments (tier 1), other (tier 2); package read from the buffer's `package` line | check 13 (without 1c the same run: `near_S` 4, `near_Mod` 2, FAIL; with it `near_S` 3, `near_Mod` 1): from the baseline `C` first demo type 14 -> 2, `S` 16 -> 3, `Mod` `demo.Modern` 3 -> 1, `Se` `demo.SecurityConfig` 2 -> 1; check 10 `DONE 17 0`, check 11 `DONE 26 0`, menu p95 unchanged within noise. Fixed in the same commit: a type and a non-type item of equal relevance compared `nil < number` in `java_sort` since 1a (latent, not hit by the checks) | kept |
| 1b | Non-generic methods first, after usage (IntelliJ `PreferNonGeneric`): a method whose return type (`labelDetails.description`) is a bare type variable (`C apply(C)`, `S save(S)`). IntelliJ tests that the type parameter belongs to the method; jdt.ls does not say, so a class-level `T get()` is treated the same (a guess) | check 13 `generic_last_http`: `apply` 10 -> 58 of 102, after `userDetailsService` (51); without the change the same case FAILs (10 vs 57, `e1c_ctl` run). Usage still goes first, so `repository.` `save` stays 1; check 10 `DONE 17 0`, check 11 `DONE 26 0`, check 13 `DONE 8 0` | kept |
| 2 | `favoriteStaticMembers` from the test classpath (`nvim/lua/nv4j/favorites.lua`): JDK groups (`Objects.*`, `Collectors.*`, `Map.entry`) always, `Mockito` + `ArgumentMatchers`, `MockMvcRequestBuilders`/`ResultMatchers`/`ResultHandlers` (spring-test), Hamcrest, AssertJ, JUnit 4/5 only when their jar is in `java.project.getClasspaths` (scope test); asked once per jdt.ls client at ServiceReady (`warmup.lua`), pushed with `workspace/didChangeConfiguration`; the client starts with the JDK groups only. Before: five fixed groups sent to every project | check 14 `DONE 7 0` (new). Baseline of the same cases (fixed five groups): `post` of MockMvcRequestBuilders not listed (nil), `anyString` not listed (nil), `Collectors.toList` not listed (nil). With the change: `post` 1, `anyString` 3, `toList` 1, `Map.entry` 1; client settings hold 12 favourites on the demo fixture (it has spring-boot-starter-test). Control (the ServiceReady hook commented out, `e2_ctl` run): `live_settings`, `mockmvc_post`, `matchers_any_string` FAIL, the JDK-group cases still pass, as expected. Checks 10 `DONE 17 0` (menu p95 7 to 38 ms, same as baseline), 11 `DONE 26 0`, 13 `DONE 8 0`. Not measured: a project without the libraries (the demo fixture has them all; the pure case `pure_jdk_only` covers the selection), and Gradle projects (same request, not run here) | kept |
| 3 | `java.completion.matchCase = firstLetter`, opt-in: `vim.g.nv4j_match_case_first = true` before jdt.ls starts (`plugins/java.lua`); default `off` (jdt.ls's own default, now sent explicitly) | check 15 `DONE 4 0` with the flag; the same check without it (`NV4J_MATCHCASE_CONTROL=1`, runs `e3_ctl*`) FAILs `client_setting`, `lower_prefix_no_types`, `list_complete`. Prefix `a` in `Person.java`: 189 of the 200 shown items are types without the flag, 0 with it (21 items shown, `age` still 1); server answer 203 items, `isIncomplete = true` -> 14 items, `isIncomplete = false`, so the following keystrokes are filtered by blink without a request; menu p95 54 to 62 ms -> 45 to 48 ms (3 runs each, machine load 2 to 6 from other processes, so only the direction counts). Prefix `A` unchanged (200 types). Cost to the user: a lower-case prefix no longer finds a class (`hashmap` does not list `HashMap`). Checks 10 `DONE 17 0`, 11 `DONE 26 0` with the default | kept, opt-in, default off |
| 6a | `completion.documentation.auto_show_delay_ms` 200 -> 450 (`plugins/blink.lua`) | check 16 `delay_scroll` (new): the cursor passes 10 menu items, one per 300 ms, then rests; blink's own `docs.auto_show_item` timer decides how many `sources.resolve` calls (each a jdt.ls javadoc render, 0.4 to 0.8 s) are made: 10 with 200 ms (run `e6a_ctl`, `delay_config` and `delay_scroll` FAIL), 1 with 450 ms (`DONE 16_completion_docs 2 0`). Cost: the documentation window of a resting item appears 250 ms later. Headless limits: the menu is not drawn (window check stubbed open) and resolve is counted, not answered, so the saved jdt.ls time is not measured, only the request count | kept |
| 4 | `java.completion.collapseCompletionItems = true` (set through a temporary `vim.g` in `config/options.lua`, run `e4_on`) | Menu length: `http.` 102 -> 69, `repository.` 52 -> 42, `new Person(` 43 -> 42, `System.` 34 -> 31; lists with identifiers or types unchanged. Ranks in checks 10 and 11 identical (`DONE 17 0`, `DONE 26 0`, `authorizeHttpRequests` 2, `save` 1). Check 13 `generic_last_http` FAILs (`apply` 10, not after `userDetailsService` 52 of 69): a collapsed item has no `detail` and its `labelDetails.description` is `2 overloads` instead of the return type, so the menu loses return types of every overloaded method (`csrf`, `apply`, `wait`...) and the non-generic tie-breaker has nothing to read. IntelliJ lists each overload | reverted (a ranking check goes red and the menu shows less) |
| 5 | Cheaper `guessMethodArguments`: `insertParameterNames`, and `off`, against the current `insertBestGuessedArguments` (check 10, warm p95 and menu p95 in ms, same run order interleaved because the machine had load 4 to 9 from other processes) | `http.`: best-guess 30 / menu 24 and 63 / 43 (two runs), `off` 26 / 21 and 29 / 21, `insertParameterNames` 30 / 29 and 30 / 31 (earlier, load 9). `repository.`: best-guess 26 / 22 and 35 / 22, `off` 21 / 25 and 22 / 22, `insertParameterNames` 26 / 25 and 24 / 28. `System.`, `new Person(`, `@`, identifier lists: no difference. Check 10 `DONE 17 0` in every run. So `off` saves 3 to 5 ms of p95 on method lists (budget 150 ms, all runs under 65) and `insertParameterNames` saves nothing measurable, while `off` drops the guessed arguments on accept | reverted (gain inside the load noise, feature lost); not re-measured on an idle machine |
| 6b | Resolve cache per completion session (`nv4j.completion.resolve_cached`, installed as `sources.providers.lsp.override.resolve`): inside one blink context an answer of a jdt.ls item is reused for items with the same label, detail, package and kind; only documentation, detail and import-only `additionalTextEdits` are reused (never `textEdit`), answers with other edits and answers from other contexts are not | check 16 `DONE 5 0`: `resolve_cache_hit` (a second item object with the same content, same context: 0 jdt.ls `completionItem/resolve` requests, same documentation; control `NV4J_RESOLVE_CONTROL=1`, run `e6b_ctl`: 1 request, FAIL), `resolve_cache_keeps_edits` (the second item keeps its own textEdit, the import edit is still there, 1 and 1), `resolve_cache_new_context` (a new context asks again, 1). Checks 10 `17 0`, 11 `26 0`, 13 `8 0`, 14 `7 0`, 15 `4 0`. Check 63 async import: `DONE 63 27 1` with the one failure `rf_closed` ("Invalid buffer id: 1" in `plugins/blink.lua`), identical on the main repo's config without these changes, so not caused here; check 12 `DONE 5 2` (`no_rg_fallback`, `loose_root_skipped`) also identical on the main repo. Limit: the second item is a deep copy of the first, because blink reuses the objects of a complete list and an isIncomplete list could not be provoked in the headless harness; the saved javadoc time (0.4 to 0.8 s per repeated resolve) is counted as requests, not timed | kept |

How these runs were made: `~/.config/nv4j` points at the main repo, so a plain `tests/run.sh` loads the main repo Lua. The runs above set `XDG_CONFIG_HOME` to a folder whose `nv4j` link is this checkout `nvim/`; check 14 passing proves it (`nv4j/favorites.lua` exists only here). Rows 4 and 5 (reverted) leave no code behind; the measurements are in this table only.
