# 002 - P1 completion: budget, baseline, trials

Status: baseline recorded (Task 3). Tuning: Task 5. Research and approach: `specs/features/completion-ranking.md`.

## Budget (provisional)

| Metric | Budget | Check |
|--------|--------|-------|
| Warm completion round trip, p95 per case | <= 150 ms | `tests/checks/10_completion_latency.lua` |
| First completion request after jdtls is ready | <= 400 ms | same, `cold_first` |
| Expected item rank in the order the user sees | top 5, plus the case's relative rule | `tests/checks/11_completion_ranking.lua` |

These numbers are still "confirm with the user after baseline" (plan, Global Constraints). The baseline passes all of them by a wide margin on the current fixture, see "What the numbers show".

## Method

- `tests/run.sh` runs each check in a fresh headless `nvim` (`NVIM_APPNAME=nv4j`) with a fresh jdtls process. The jdtls workspace in `/tmp/nv4j/jdtls-data` persists between runs, so the index is warm; the JVM is not.
- Config under test: the unmodified copied config from Task 1 (blink.cmp v1.10.2 with the Rust matcher, jdt.ls 1.62.0, `maxResults = 200`, `filteredTypes = com.sun.*, sun.*, jdk.internal.*`, `debounce_text_changes = 500`). JDK: Corretto 25 pinned by `run.sh`.
- Each case types its trigger into the buffer in memory only (never saved; the buffer is restored and marked unmodified after each case), so the fixture on disk is unchanged and checks 00/01 are unaffected. Helpers: `tests/lib/completion.lua`.
- Latency: per case, 1 first request, 3 warm-up requests (discarded), then 30 timed samples. Before every request the case line is set again, so jdtls receives a `didChange` and has to reconcile, like after a keystroke. The time is the full `textDocument/completion` round trip seen by Neovim (`lsp.complete`, includes flushing the change and decoding JSON). p50/p95/max use nearest rank. Every sample goes to `/tmp/nv4j/logs/latency.jsonl` as `{"case","ms","count"}`; blink's sort time goes there too as `<case>.blink_sort`.
- `cold_first` is the very first completion request of the process, made right after `wait_ready` (project imported and first diagnostics published).
- Ranking: one request per case. "Rank" is the position in blink.cmp's order, computed by calling blink's own `fuzzy.fuzzy` with the config's fuzzy settings on the jdtls items. This leaves out other blink sources (snippets, buffer, path), which can add items to the real menu. The jdtls order (`sortText`) is reported too.
- 3 full runs for variance (`tests/run.sh` x3, logs `/tmp/nv4j/logs/test-20261020-181643.log`, `-181714.log`, `-181745.log`).

### Cases

| Case | File | Text typed (cursor at end unless noted) | Reported item |
|------|------|------------------------------------------|---------------|
| `system_members` | App.java, in `main` | `System.` | `out` |
| `java_util_pkg` | App.java, in `main` | `java.util.` | `List` |
| `new_person_ctor` | App.java, in `main` | `Person p = new Person();` cursor inside `()` | `Person` |
| `annotation_list` | Person.java, class body | `@` | `MyAnno` |
| `identifier_prefix` | Person.java, in `getName` | `a` | `age` |
| `local_expected_type` | App.java, after `Person nobody = ...;` | `Person best = n` | `nobody` above every keyword |
| `local_expected_type_empty` | same | `Person best = ` | `nobody` above every keyword |
| `field_over_jdk_noise` | Person.java, in `getName` | `a` | field `age` above every non-project type |
| `annotation_prefix` | Person.java, class body | `@My` | `MyAnno` |

`identifier_prefix` was added to the latency list (not in the brief) because plain identifier typing is the most common case and the only one that hits `maxResults`.

## Baseline

### Latency, per run (ms)

| Case | Run 1 p50 / p95 / max | Run 2 p50 / p95 / max | Run 3 p50 / p95 / max | Items | isIncomplete |
|------|-----------------------|-----------------------|-----------------------|-------|--------------|
| `cold_first` (`System.`) | 126 | 109 | 127 | 34 | false |
| `system_members` | 18 / 23 / 25 | 15 / 18 / 19 | 13 / 17 / 18 | 34 | false |
| `java_util_pkg` | 26 / 39 / 41 | 26 / 40 / 46 | 26 / 32 / 44 | 124 | false |
| `new_person_ctor` | 11 / 29 / 33 | 8 / 13 / 14 | 8 / 10 / 10 | 5 | false |
| `annotation_list` | 22 / 35 / 44 | 22 / 27 / 36 | 21 / 39 / 45 | 52 | false |
| `identifier_prefix` | 20 / 27 / 39 | 16 / 23 / 37 | 17 / 27 / 31 | 203 | true |

### Latency, 3 runs pooled (90 samples per case, ms)

| Case | p50 | p95 | max | blink sort p95 |
|------|-----|-----|-----|----------------|
| `system_members` | 14.7 | 20.9 | 25.2 | 0.5 |
| `java_util_pkg` | 25.7 | 39.4 | 46.3 | 0.9 |
| `new_person_ctor` | 8.7 | 12.8 | 32.8 | 0.2 |
| `annotation_list` | 21.5 | 35.3 | 44.8 | 0.6 |
| `identifier_prefix` | 17.7 | 26.6 | 39.3 | 0.8 |
| `cold_first` | 126 (median of 3) | | 127 | |

### Ranks (identical in all 3 runs)

| Case | Rank shown (blink) | Rank in jdtls order | Relative rule | Result |
|------|--------------------|---------------------|---------------|--------|
| `local_expected_type` | `nobody` 1 | 1 | first keyword (`new`) at 3 | PASS |
| `local_expected_type_empty` | `nobody` 1 | 1 | no keyword in list | PASS |
| `field_over_jdk_noise` | `age` 1 | 1 | first non-project type at 2 | PASS |
| `annotation_prefix` | `MyAnno` 1 | 1 | | PASS |
| `system_members` (info) | `out` 4 | 4 | | |
| `java_util_pkg` (info) | `List` 57 of 124 | 57 | | |
| `new_person_ctor` (info) | `Person` 1 | 4 | | |
| `annotation_list` (info) | `MyAnno` 5 of 52 | 5 | | |
| `identifier_prefix` (info) | `age` 1 | 1 | | |

All checks PASS in all three runs.

## What the numbers show

1. **The fixture does not reproduce the lag the user feels.** Every warm p95 is under 50 ms, three times below budget, and the first request is about 125 ms. The fixture has only the JDK on its classpath and five tiny classes. Before tuning, Task 5 should measure on something closer to real use: a fixture with Spring Boot dependencies on the classpath (thousands of library types), or the user's real project. Tuning against these numbers would optimise nothing.
2. **The likely latency risk is `isIncomplete`, not one request.** Typing a single letter returns 203 items and `isIncomplete = true` because `maxResults = 200` is hit. blink then asks jdtls again on every keystroke instead of filtering locally. On the fixture each round trip is cheap; on a large classpath it is the per-keystroke cost.
3. **blink adds almost nothing.** Its sort takes under 1 ms p95 even for 200 items. Lag that is not in the server round trip must come from somewhere the headless check cannot see: drawing the menu (colorful-menu), documentation auto-show (one `completionItem/resolve` per selected item), signature help, or jdtls diagnostics running after the 500 ms `didChange` debounce.
4. **Ranking is already good on the expected-type and locality cases.** jdt.ls's relevance puts the local of the expected type and the field first, and blink keeps that order. The visible problem is noise: ranks 2 to 11 after typing `a` are `com.apple.laf.resources.aqua_*` JDK internals, which `filteredTypes` does not cover.
5. **Where IntelliJ is clearly better:** lists without a prefix. `java.util.` is alphabetical (`List` at 57), `@` puts four `java.lang` annotations before the project's `MyAnno`. IntelliJ uses usage statistics and project-first proximity for these; JDT has neither. blink's frecency can partly cover this after real use.
6. **`new Person(` returns odd items** (`toString`, `toIdentityString`). The useful help there is signature help, which is on. Not a ranking target. blink shows `Person` at 1 while the jdtls `sortText` order has it at 4; the cause was not investigated (the cursor sits between `(` and `)`, so blink's keyword handling differs from a plain sortText sort).
7. Harness note: `lsp.complete` sends no `CompletionContext`, while blink sends `triggerKind` (and the trigger character for `.`/`@`). jdt.ls results looked the same in spot checks, but this is a known difference from the real client.

## Budget decision needed

The provisional budgets hold with a large margin on this fixture, so they cannot tell good config from bad. Options for the user: keep the numbers and make the fixture realistic (recommended), or keep the fixture and lower the budget. To confirm with the user before Task 5 starts.

## Trial log (Task 5)

One change per trial. Keep a change only if a number improves. Columns: trial, change, p50/p95 per case, ranks, kept or reverted.

| # | Change | Latency (p50 / p95) | Ranks | Kept |
|---|--------|---------------------|-------|------|
