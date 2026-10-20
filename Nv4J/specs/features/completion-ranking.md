# Feature: Java completion ranking and filtering

Priority: P1. Status: research done (Task 3), tuning pending (Task 5). Baseline numbers are in `specs/002-p1-completion.md`.

Pass/fail tests: `tests/checks/10_completion_latency.lua` (latency, result counts) and `tests/checks/11_completion_ranking.lua` (rank of the expected item in the order the user sees).

## Sources read

| Repo | Local copy (read only, not committed) | Commit | License |
|------|----------------------------------------|--------|---------|
| intellij-community | `~/.cache/nv4j/intellij-community` | `b633034bb` | Apache 2.0 |
| eclipse.jdt.core | `~/.cache/nv4j/eclipse.jdt.core` | `cd40048` | EPL-2.0 |
| eclipse.jdt.ls | `~/.cache/nv4j/eclipse.jdt.ls` | `b52e20a` | EPL-2.0 |
| blink.cmp v1.10.2 | `~/.local/share/nv4j/lazy/blink.cmp` | `78336bc` | MIT |

The installed server is jdt.ls 1.62.0 with jdt.core 3.48.0 (Mason). The clones are current `master`, so line-level details can differ slightly from what runs. Nothing below is copied code. EPL-2.0 code must not be copied into this repo without its header and a note.

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

## Pass/fail criteria

- Latency: p95 <= 150 ms warm per case, <= 400 ms for the first request after jdtls is ready (provisional, see 002).
- Ranking: expected item in the top 5 of the blink-visible order, plus the relative rule of each case (local above keywords, field above non-project types).
