# 002 - P1 completion: budget, baseline, trials

Status: done (P1). Every latency and ranking budget passes on 3 consecutive full runs (see "Final (Task 5)" and "Fix round 1"). `cold_first`, pinned at ServiceReady + 1.0 s since fix round 1, is 44-59 ms over 16 runs (budget 400 ms). Budgets are confirmed in `specs/001-architecture.md` (D13, "Budgets and results (P1, P2)"). Research and approach: `specs/features/completion-ranking.md`.

## Budget (confirmed)

| Metric | Budget | Check |
|--------|--------|-------|
| Warm completion round trip, p95 per case | <= 150 ms | `tests/checks/10_completion_latency.lua` |
| First completion request after jdtls is ready | <= 400 ms | same, `cold_first` |
| Expected item rank in the order the user sees | top 5, plus the case's relative rule | `tests/checks/11_completion_ranking.lua` |

These budgets were provisional until the Task 5 re-baseline and are now confirmed, unchanged (`specs/001-architecture.md`, D13). At the baseline below (before any tuning), `cold_first` and three ranking cases broke them, see "What the numbers show"; the final runs pass all of them.

## Fixture

`tests/fixtures/demo` is a Spring Boot 3.5.13 project (`spring-boot-starter-parent`, Java release 25, compiles with `mvn -q compile` on Corretto 25). Starters: web, data-jpa, security, validation, test, plus H2 (runtime). Sources:

- `DemoApplication` (`@SpringBootApplication`), `Customer` (`@Entity`, `@Table`, `@Column`, Bean Validation), `CustomerRepository` (`JpaRepository<Customer, Long>` plus two derived queries), `CustomerController` (`@RestController`, GET/POST/PUT), `SecurityConfig` (`@Configuration`, `HttpSecurity` DSL).
- The toy sources stay (`App`, `Person`, `Repo`, `MyAnno`, `Modern`), so the toy cases still run, now with Spring on the classpath too. Checks 00 and 01 pass.

## Method

- `tests/run.sh` runs each check in a fresh headless `nvim` (`NVIM_APPNAME=nv4j`) with a fresh jdtls process. The jdtls workspace (then `/tmp/nv4j/jdtls-data`, now `~/.cache/nv4j/jdtls-data`) persists between runs, so the index is warm; the JVM is not.
- Config under test: the unmodified copied config from Task 1 (blink.cmp v1.10.2 with the Rust matcher, jdt.ls 1.62.0, `maxResults = 200`, `filteredTypes = com.sun.*, sun.*, jdk.internal.*`, `debounce_text_changes = 500`). JDK: Corretto 25 pinned by `run.sh`.
- Each case types its trigger into the buffer in memory only (never saved; the buffer is restored and marked unmodified after each case), so the fixture on disk is unchanged. Helpers: `tests/lib/completion.lua`.
- Latency: per case, 1 first request (reported as "first", cold for that case), 3 warm-up requests (discarded), then 90 timed samples. Before every request the case line is set again, so jdtls receives a `didChange` and has to reconcile, like after a keystroke. The time is the full `textDocument/completion` round trip seen by Neovim (`lsp.complete`). Every request must return without error (`not r.err`, first request included). p50/p95/max use nearest rank. Samples go to `/tmp/nv4j/logs/latency.jsonl` as `{"case","ms","count"}`, plus `<case>.first`, `<case>.blink_sort`, `cold_first` and `jdtls_import`.
- `cold_first` is the very first completion request of the process (the `@` case in `CustomerController`), made right after `wait_ready` (project imported and first diagnostics published).
- Import time: `01_jdtls_ready` and `10_completion_latency` report "open to ready" (file opened until `java.project.getAll` lists the project and the first diagnostics for the buffer arrive). Measured once on an empty jdtls workspace (true import) and on every baseline run (warm workspace).
- Ranking: one request per case. "Rank" is the position in blink.cmp's order, computed by calling blink's own `fuzzy.fuzzy` with the config's fuzzy settings on the jdtls items. Other blink sources (snippets, buffer, path) are left out. The jdtls order (`sortText`) is reported too.
- Runs: one run on an empty jdtls workspace (log `/tmp/nv4j/logs/test-20261020-182828.log`), then 3 baseline runs on the warm workspace (logs `test-20261020-182958.log`, `-183109.log`, `-183222.log`). Samples: `/tmp/nv4j/logs/latency.jsonl` (3 baseline runs, 90 samples per case per run, 270 pooled).

### Cases

Spring cases (all in `src/main/java/demo/`):

| Case | File, place | Text typed (cursor at end unless noted) | Expected item |
|------|-------------|------------------------------------------|---------------|
| `spring_annotation_list` | CustomerController, class level | `@` | `RestController` |
| `anno_prefix_auto` (11: `spring_anno_auto`) | CustomerController, before the constructor | `@Auto` | `Autowired` |
| `anno_prefix_rest` (11: `spring_anno_rest`) | CustomerController, class level | `@Rest` | `RestController` |
| `table_attrs` | Customer, replaces `@Table(...)` | `@Table()` cursor inside `()` | `name` |
| `column_attrs` | Customer, replaces the email `@Column(...)` | `@Column()` cursor inside `()` | `nullable` |
| `http_dsl` | SecurityConfig, in `filterChain(HttpSecurity http)` | `http.` | `authorizeHttpRequests` |
| `jpa_repo_members` | CustomerController, in `create` | `repository.` | `save` |
| `spring_identifier_a` | CustomerController, in `update(..., Customer amended)` | `a` | `amended` above every non-project type |
| `spring_identifier_s` | CustomerController, in `search(String search)` | `s` | `search` above every non-project type |

Toy cases (unchanged): `system_members` (`System.` -> `out`), `java_util_pkg` (`java.util.` -> `List`), `new_person_ctor` (`new Person(` -> `Person`), `annotation_list` (`@` in Person -> `MyAnno`), `identifier_prefix` (`a` in Person -> `age`); ranking `local_expected_type`, `local_expected_type_empty`, `field_over_jdk_noise`, `annotation_prefix`.

## Baseline (Spring fixture)

### jdtls import and first request

| Measure | Empty workspace | Run 1 | Run 2 | Run 3 | Budget |
|---------|-----------------|-------|-------|-------|--------|
| Open to ready, check 01 (ms) | 15006 | 6140 | 6567 | 6207 | none (info) |
| Open to ready, check 10 (ms) | 5858 | 5863 | 5946 | 5797 | none (info) |
| `cold_first` (`@` in CustomerController, 200 items) (ms) | 740 | 818 | 827 | 752 | 400: **FAIL** |

The true import with Spring on the classpath (empty workspace) takes about 15 s. With a warm workspace, a new jdtls process still needs about 6 s before it can answer.

### Latency, per run (ms; first | p50 / p95 / max, 90 samples each)

| Case | Run 1 | Run 2 | Run 3 | Items | isIncomplete |
|------|-------|-------|-------|-------|--------------|
| `spring_annotation_list` | 818 \| 30 / 44 / 90 | 827 \| 30 / 43 / 63 | 752 \| 28 / 38 / 62 | 200 | true |
| `table_attrs` | 7 \| 5 / 10 / 24 | 12 \| 5 / 8 / 24 | 8 \| 6 / 13 / 28 | 5 | false |
| `column_attrs` | 11 \| 5 / 8 / 11 | 6 \| 5 / 10 / 15 | 8 \| 5 / 8 / 25 | 10 | false |
| `http_dsl` | 168 \| 18 / 27 / 44 | 188 \| 19 / 26 / 31 | 222 \| 19 / 26 / 47 | 102 | false |
| `jpa_repo_members` | 56 \| 19 / 22 / 40 | 58 \| 19 / 25 / 45 | 65 \| 17 / 22 / 52 | 52 | false |
| `anno_prefix_auto` | 14 \| 12 / 19 / 29 | 17 \| 9 / 13 / 23 | 20 \| 11 / 13 / 16 | 6 | false |
| `anno_prefix_rest` | 8 \| 11 / 18 / 22 | 8 \| 11 / 14 / 29 | 11 \| 9 / 13 / 34 | 2 | false |
| `spring_identifier_a` | 120 \| 25 / 30 / 32 | 122 \| 24 / 34 / 83 | 118 \| 26 / 32 / 60 | 203 | true |
| `spring_identifier_s` | 30 \| 28 / 32 / 51 | 31 \| 29 / 40 / 50 | 40 \| 28 / 32 / 33 | 211 | true |
| `system_members` | 27 \| 9 / 12 / 18 | 27 \| 10 / 14 / 39 | 24 \| 9 / 12 / 16 | 34 | false |
| `java_util_pkg` | 23 \| 23 / 28 / 50 | 20 \| 18 / 26 / 34 | 28 \| 24 / 34 / 52 | 124 | false |
| `new_person_ctor` | 29 \| 6 / 10 / 24 | 27 \| 7 / 10 / 16 | 32 \| 6 / 9 / 11 | 5 | false |
| `annotation_list` | 23 \| 28 / 31 / 37 | 32 \| 28 / 33 / 39 | 28 \| 27 / 33 / 46 | 200 | true |
| `identifier_prefix` | 52 \| 17 / 24 / 35 | 63 \| 21 / 24 / 33 | 57 \| 21 / 26 / 38 | 203 | true |

### Latency, 3 runs pooled (270 warm samples per case, ms)

| Case | p50 | p95 | max | blink sort p95 | First (min-max of 3) | Warm budget |
|------|-----|-----|-----|----------------|----------------------|-------------|
| `spring_annotation_list` | 29.3 | 42.8 | 90.3 | 1.3 | 752-827 | PASS |
| `table_attrs` | 5.4 | 10.3 | 28.1 | 0.2 | 7-12 | PASS |
| `column_attrs` | 5.2 | 8.6 | 24.6 | 0.3 | 6-11 | PASS |
| `http_dsl` | 18.7 | 26.1 | 47.4 | 0.9 | 168-222 | PASS |
| `jpa_repo_members` | 18.3 | 22.4 | 51.6 | 0.6 | 56-65 | PASS |
| `anno_prefix_auto` | 10.8 | 14.0 | 28.9 | 0.2 | 14-20 | PASS |
| `anno_prefix_rest` | 10.9 | 13.7 | 33.7 | 0.2 | 8-11 | PASS |
| `spring_identifier_a` | 25.3 | 30.9 | 82.9 | 1.2 | 118-122 | PASS |
| `spring_identifier_s` | 28.4 | 32.7 | 51.2 | 1.3 | 30-40 | PASS |
| `system_members` | 9.3 | 12.3 | 38.8 | 0.3 | 24-27 | PASS |
| `java_util_pkg` | 21.6 | 29.9 | 52.2 | 0.9 | 20-28 | PASS |
| `new_person_ctor` | 6.4 | 9.7 | 23.9 | 0.2 | 27-32 | PASS |
| `annotation_list` | 27.8 | 32.3 | 45.8 | 1.3 | 23-32 | PASS |
| `identifier_prefix` | 20.5 | 24.9 | 38.0 | 1.2 | 52-63 | PASS |

### Ranks (identical in all 3 runs)

| Case | Rank shown (blink) | Rank in jdtls order | Relative rule | Result |
|------|--------------------|---------------------|---------------|--------|
| `spring_annotation_list` | `RestController` 6 of 200 | 6 | | **FAIL** |
| `spring_anno_auto` | `Autowired` 1 of 6 | 1 | | PASS |
| `spring_anno_rest` | `RestController` 1 of 2 | 1 | | PASS |
| `table_attrs` | `name` 3 of 5 | 3 | | PASS |
| `column_attrs` | `nullable` 5 of 10 | 5 | | PASS |
| `http_dsl` | `authorizeHttpRequests` 21 of 102 | 11 | | **FAIL** |
| `jpa_repo_members` | `save` 45 of 52 | 35 | | **FAIL** |
| `spring_identifier_a` | `amended` 1 of 203 | 1 | first non-project type at 2 | PASS |
| `spring_identifier_s` | `search` 1 of 211 | 1 | first non-project type at 3 | PASS |
| `local_expected_type` | `nobody` 1 | 1 | first keyword at 3 | PASS |
| `local_expected_type_empty` | `nobody` 1 | 1 | no keyword in list | PASS |
| `field_over_jdk_noise` | `age` 1 | 1 | first non-project type at 2 | PASS |
| `annotation_prefix` | `MyAnno` 1 | 1 | | PASS |

Checks 00 and 01 PASS in all runs. Check 10 FAILs only on `cold_first`; check 11 FAILs on the three cases above.

## What the numbers show

1. **Budgets broken at Spring scale:** `cold_first` (740-827 ms against 400 ms, every run, including the empty-workspace run) and ranking for `@` at class level (`RestController` 6), `http.` (`authorizeHttpRequests` 21) and `repository.` (`save` 45). Every warm p95 still passes, with the worst at 43 ms (`@`, 200 items), three times under budget.
2. **The first request in a file is the slow one.** Besides `cold_first`, the first `http.` takes 168-222 ms and the first `a` in the controller about 120 ms, then the same requests settle at 20-30 ms. What the user feels right after opening a project or a new file is this cold cost (JIT, type caches in JDT), not the steady state. Toy `cold_first` (`System.`, no Spring) was about 125 ms, so the cold cost grows with the classpath, but the two runs used different first cases, so the number is not a clean A/B.
3. **Warm server latency still does not explain steady lag.** With web, data-jpa, security and validation on the classpath, the warm round trip stays under 45 ms p95 for every case. If the user still feels lag while typing, it must come from: (a) `isIncomplete = true` for `@`, `a` and `s` (`maxResults = 200` hit), which makes blink ask again on every keystroke; (b) cold requests after opening files; (c) things the headless check cannot see: menu drawing, documentation auto-show (`completionItem/resolve`), signature help, diagnostics after the 500 ms debounce; or (d) a real project much larger than this fixture.
4. **Postfix snippets bury member lists.** After `http.` and `repository.`, jdt.ls returns its postfix templates (`cast`, `nnull`, `null`, `opt`, `sysout`, `sysouf`, ...) first, and blink puts them first too. In the jdtls order `authorizeHttpRequests` is 11 and `save` 35; in blink's order they fall further to 21 and 45. This is the clearest ranking gap to IntelliJ, which puts the receiver's own members first and keeps postfix templates out of the plain list. Candidate Task 5 fixes: turn off postfix completion (`java.completion.postfix.enabled = false`) or give the snippet kind a negative `score_offset` in blink; also check why blink moves members down compared to jdtls.
5. **Prefixed annotations and attributes are fine.** `@Auto` and `@Rest` put the right item first; `@Table(`/`@Column(` attribute lists are short (5 and 10) and alphabetical, so the target is in the top 5 only because the list is short (`nullable` is exactly 5).
6. **Prefix-less `@` is alphabetical by group.** `java.lang` annotations and the project's `MyAnno` come before the Spring web annotations, so `RestController` misses top 5 by one. IntelliJ would use usage statistics here.
7. **JDK noise stays.** After `a`/`s`, `com.apple.laf.resources.aqua_*` and `standard_*` resource classes take ranks 2+ (not covered by `filteredTypes`).
8. blink's own sort costs at most 1.5 ms p95 even for 211 items.
9. Harness note: `lsp.complete` sends no `CompletionContext`, while blink sends `triggerKind` (and the trigger character for `.`/`@`). Known difference from the real client.

### Earlier toy baseline (before fix round 1)

JDK-only classpath, 30 samples per run x 3 (logs `test-20261020-181643/-181714/-181745.log`): pooled warm p95 `system_members` 20.9, `java_util_pkg` 39.4, `new_person_ctor` 12.8, `annotation_list` 35.3, `identifier_prefix` 26.6 ms; `cold_first` (`System.`) 109-127 ms; all four ranking cases rank 1. Every budget passed by 3x+, which is why the fixture was replaced: it could not tell good config from bad.

## Budget decision needed (at baseline; since decided)

Decided: budgets kept unchanged and confirmed (`specs/001-architecture.md`, D13); `cold_first` passes since fix round 1. What was open at baseline: keep the provisional budgets (not weakened). Open for the user before Task 5: whether `cold_first` <= 400 ms is the right target (it was then the only latency budget that failed), and whether the ranking expectation for prefix-less lists (`@`) should stay at top 5.

## Final (Task 5)

Config: `nvim/lua/plugins/java.lua`, `nvim/lua/plugins/blink.lua`, `nvim/lua/nv4j/{completion,usage,warmup}.lua`; design in `specs/features/completion-ranking.md` ("Implemented design"). Three consecutive full `tests/run.sh` runs (checks 00, 01, 10, 11, 20, PATH java = 21), all PASS: logs `/tmp/nv4j/logs/test-20261020-200327.log`, `-200456.log`, `-200627.log`; samples `/tmp/nv4j/logs/latency.jsonl` (these 3 runs only).

### Latency, 3 runs pooled (ms; round trip 270 samples, menu 90 samples per case)

| Case | p50 | p95 | max | menu p50 / p95 | First (3 runs) | Baseline p95 / first | Budget |
|------|-----|-----|-----|----------------|----------------|----------------------|--------|
| `spring_annotation_list` | 29.2 | 41.4 | 67.0 | 27.7 / 41.3 | 351, 366, 305 | 42.8 / 752-827 | PASS |
| `table_attrs` | 5.6 | 9.4 | 54.7 | 6.3 / 9.8 | 6, 6, 11 | 10.3 / 7-12 | PASS |
| `column_attrs` | 5.3 | 9.3 | 30.0 | 6.1 / 13.7 | 9, 12, 8 | 8.6 / 6-11 | PASS |
| `http_dsl` | 19.0 | 25.6 | 40.9 | 18.6 / 25.9 | 129, 153, 127 | 26.1 / 168-222 | PASS |
| `jpa_repo_members` | 17.7 | 24.5 | 87.8 | 18.0 / 28.6 | 75, 70, 60 | 22.4 / 56-65 | PASS |
| `anno_prefix_auto` | 10.5 | 20.8 | 157.2 | 10.6 / 14.6 | 15, 14, 15 | 14.0 / 14-20 | PASS |
| `anno_prefix_rest` | 11.1 | 17.1 | 44.5 | 10.6 / 19.0 | 9, 13, 8 | 13.7 / 8-11 | PASS |
| `spring_identifier_a` | 24.7 | 30.1 | 46.4 | 25.1 / 29.7 | 99, 152, 135 | 30.9 / 118-122 | PASS |
| `spring_identifier_s` | 27.6 | 34.6 | 76.5 | 27.6 / 34.3 | 40, 25, 32 | 32.7 / 30-40 | PASS |
| `system_members` | 8.6 | 13.4 | 31.7 | 11.1 / 17.0 | 26, 38, 37 | 12.3 / 24-27 | PASS |
| `java_util_pkg` | 22.3 | 27.4 | 50.9 | 22.9 / 26.8 | 26, 26, 23 | 29.9 / 20-28 | PASS |
| `new_person_ctor` | 7.2 | 14.4 | 33.1 | 6.8 / 10.2 | 30, 28, 22 | 9.7 / 27-32 | PASS |
| `annotation_list` | 25.7 | 34.1 | 53.5 | 26.2 / 34.3 | 38, 35, 32 | 32.3 / 23-32 | PASS |
| `identifier_prefix` | 20.0 | 25.0 | 44.5 | 21.1 / 24.6 | 70, 68, 66 | 24.9 / 52-63 | PASS |
| `cold_first` | | | | | 351, 366, 305 | 740-827 | PASS (400) |

Open to ready: 5902, 5882, 5860 ms (baseline about 5800-5950). Warm latency did not change measurably (it was already 3x under budget); the changes are ranking and the cold request.

### Ranks (identical in all 3 runs; blink pipeline order)

| Case | Baseline (blink pipeline, H) | Final | jdtls order |
|------|------------------------------|-------|-------------|
| `spring_annotation_list` `@` -> `RestController` | 6 | **4** | 6 |
| `http_dsl` `http.` -> `authorizeHttpRequests` | 19 | **2** | 11 |
| `jpa_repo_members` `repository.` -> `save` | 42 | **1** | 35 |
| `spring_identifier_a` / `_s` (field/param above non-project types) | 1, foreign at 2 / 3 | 1, foreign at 3 / 14-17 | 1 |
| all other baseline cases | 1-5 | unchanged (1-5) | |
| new: `http_dsl_prefix` `http.au`, `jpa_repo_prefix` `repository.sa` | - | 1, 1 | 3, 1 |
| new: `postfix_by_key` `http.va` -> `var` (request at `http.va`, and typed: list fetched at `http.`, filtered by blink) | - | 1, 1 | 1 |
| new rules: snippets after every member (`http.`, `repository.`); no filtered type and no qualified package for `a`, `s`, `m` | - | PASS | |

### What changed and why

1. **Postfix templates after members** (largest effect: `http.` 19 -> 9). jdt.ls puts the receiver into their `filterText`, blink scores that 89 against `http.` while members score 0. Matching on the key only and an offset of -6 puts them last, like IntelliJ, and `http.va` still finds `var`.
2. **Project usage as a tie breaker** (`http.` 9 -> 2, `repository.` 32 -> 1). jdt.ls gives all members of a receiver the same relevance, so its order is alphabetical. IntelliJ's `PreferMostUsedWeigher` ranks by how often the project uses a member. nv4j counts `.name`/`@Name` in the project with ripgrep and uses the count only after jdt.ls relevance, skipping Object's methods like IntelliJ.
3. **No `java.*` relevance bonus** (`@` 7 -> 4): JDT's +2 for SDK types kept `@Deprecated`/`@SuppressWarnings` above the project's own annotations.
4. **Less flooding**: `filteredTypes` for platform/desktop/shaded packages, qualified packages dropped for bare identifiers (`s`: 200 -> 34 shown), no live templates after `.`/`@` (`http.`: 138 -> 102 shown).
5. **Warm-up on ServiceReady** (`cold_first` 740-870 -> 305-366 in these runs): the user's first completion no longer pays the whole one-time JDT cost.

### What did not help

ParallelGC, AppCDS, codelens off during start, prefixed or symbol warm-ups, `maxResults` 50 or 1000, `lazyResolveTextEdit` (small gain, accept then depends on resolve within 100 ms). Details in the trial log. (Warming before ServiceReady was first listed here; fix round 1 showed it works when combined with a second request at ServiceReady, see below.)

### What the headless checks cannot see

Menu drawing (colorful-menu labels, treesitter in the menu), documentation auto-show and its `completionItem/resolve`, signature help, ghost text, diagnostics redraw after the 500 ms debounce, and the real keystroke-to-screen time. `menu_p95` covers everything up to the sorted list; the rest needs `:CompletionProfile on` (`nvim/lua/util/profile.lua`, keystroke-to-menu stamps and per-update menu snapshots) in a real session. The checks also type each case in one step: blink's cached-list path is covered only by the two `_typed` cases.

## Follow-ups (logged in Task 6 fix round 1, for the P3 plan)

- **Frecency noise on empty-prefix lists.** blink.cmp's frecency boosts every item whose label the user accepted, even with an empty prefix. In testing, accepting `List` a few times pushed the nested `@...List` container annotations to the top of `@` and `RestController` fell from rank 4 to 27. The checks are isolated from it (`XDG_STATE_HOME=/tmp/nv4j/state`, frecency writes stubbed in check 31), but the user's own sessions are not. Candidate: for Java, weight jdt.ls relevance and project usage above frecency (e.g. frecency only as a tie breaker after `nv4j_rel`, or off for empty prefixes). **Built in P3 Task 1:** with nothing typed, frecency is a tie breaker after score_offset, relevance and usage (`java_sort_empty`); root cause: blink v1.10.2's Rust adds the bonus whenever its database is open (`use_frecency` is never read). `63_async_import` `frecency_at`/`frecency_http`, `specs/features/async-import.md`.
- **Async import apply**: built in P3 Task 1 (`specs/features/async-import.md`).

### Concerns for the user

- `cold_first` (Task 5 concern) resolved in fix round 1: pinned at ServiceReady + 1.0 s, 44-59 ms over 16 runs.
- **`@` with an empty prefix** passes at rank 4 thanks to project usage; on a project that has never used an annotation, the list is jdt.ls's (java.lang and imported first, cut at 200 inside `jakarta.*`). Typing one letter fixes it.
- Usage counts are name level (`save` on any receiver counts) and need ripgrep; without it ranking falls back to jdt.ls order.
- `filteredTypes`: fix round 1 narrowed it; `java.awt.*`/`javax.swing.*` visible by default, override via `vim.g.nv4j_filtered_types`.
- lazyvim.json no longer loads `formatting.prettier`: YAML/JSON/Markdown files (e.g. `application.yml`) lose prettier format-on-save.

## Fix round 1 (Task 5 review)

Changes after review; three more full runs, see row F1 at the end of the trial log.

- **filteredTypes narrowed.** `jdk.*` hid public APIs (`jdk.jfr`, `jdk.incubator.vector`, `jdk.net`, `jdk.management`) and `java.awt.*` hid `BufferedImage`/`Color`/`Graphics2D`. Defaults are now only what was measured as noise or is not public API: `com.sun.*`, `sun.*`, `jdk.internal.*`, `jdk.javadoc.internal.*` (the `standard_*` resource classes seen after `s`), `com.apple.*`, `apple.*`, `java.applet.*`, `aj.*`, `org.aspectj.internal.*`, `java.awt.List`, `java.awt.peer.*`. Why `java.awt.List`: measured in `App.java` (no import), `List` lists `java.awt.List` first and `java.util.List` second without it, and `java.util.List` first with it (new case `list_type_not_imported`). `java.awt.peer.ListPeer` was next to it. `java.awt.*` and `javax.swing.*` stay visible by default: no measured case needs them hidden and server code uses AWT imaging classes.
- **User override.** Set before jdtls starts (e.g. in `nvim/lua/config/options.lua`): `vim.g.nv4j_filtered_types = { add = { "java.awt.*", "javax.swing.*" }, remove = { "java.awt.List" } }`. Defaults live in `nvim/lua/nv4j/completion.lua` (`DEFAULT_FILTERED_TYPES`, `filtered_types()`).
- **Usage index robustness** (`nv4j/usage.lua`): the exit status of both rg commands is reported separately on stderr (a sh pipeline only returns the last command's); exit >= 2, a signal, or more than 10 s (the whole process group is killed, so rg cannot hold the pipe open) keeps the previous counts; reruns after `.java` writes are debounced (1.5 s trailing); `watch` is started only from `java.lua` on_attach. New check `tests/checks/12_usage_index.lua`: counts, rg failing keeps counts, rg timing out keeps counts, a burst of 5 writes costs 1 run, no rg on PATH means no counts and the Java transform still works.
- **cold_first pinned.** Check 10 now sends the first completion exactly 1.0 s after jdt.ls ServiceReady (timestamp `vim.g.nv4j_service_ready_ms`, set by `nv4j/warmup.lua`; real-time polling, `vim.wait`'s own timeout overshot by about 260 ms). It reports the warm-up state. With the Task 5 warm-up (ServiceReady only), the pinned check gave 440, 452, 419, 378 ms, so it failed.
- **Warm-up split.** It now sends one request at language/status `Started` and one at `ServiceReady`. `Started` comes about 1.5 s before ServiceReady on a warm workspace; that request takes 1.4-1.8 s while jdt.ls imports, and the one at ServiceReady then takes 56-89 ms. Pinned cold_first over 16 consecutive runs: 44-59 ms (all <= 400). On an empty workspace (true import), the `Started` request took 6.7 s and cold_first was 67 ms.
- **What the cold check covers.** The pinned request goes out 1.0 s after ServiceReady, when the `Started` warm-up has already finished (about 1.5 s before ServiceReady on a warm workspace). A completion in the first second after ServiceReady, or before the `Started` request finishes (for example on a first import, where it took 6.7 s), is not covered and can still cost up to the full 0.7-0.9 s.
- **Once-per-client guard.** Each warm-up phase is sent once per jdtls client. A project reload in the same client (e.g. after a pom.xml change) pays the full one-time cost again on its first empty-prefix type list.

## Trial log (Task 5)

One change per trial. Keep a change only if a number improves. Columns: trial, change, p50/p95 per case, ranks, kept or reverted.

| # | Change | Latency (p50 / p95) | Ranks | Kept |
|---|--------|---------------------|-------|------|
| H | Harness, not config: ranks and a second latency series now come from blink's own pipeline (`tests/lib/completion.lua` `M.menu`: blink Context, `sources.request_completions` with every provider enabled for Java and a real CompletionContext, `transform_items`, deprecated -2, `completion.list.fuzzy`; blink's blocked trigger characters and its "hide when the triggering source is empty" rule). `menu_p95` (30 samples per case) must meet the same 150 ms budget. Report lines are written straight to stdout on their own line (a status echo had glued two PASS lines together). | unchanged; `menu_p95` 9-40 | `@` 6, `http.` 19, `repository.` 42 (snippet source mixed in; `local_expected_type_empty` passes once space is treated as blink does, as <C-Space>) | n/a |
| 1 | `filteredTypes` += `jdk.*`, `com.apple.*`, `apple.*`, `java.awt.*`, `javax.swing.*`, `java.applet.*`, `aj.*`, `org.aspectj.internal.*` | unchanged (`cold_first` 779) | ranks unchanged; `a`: `aqua_*`/`ajc*` gone; `s`: first non-project type 3 -> 7 | kept, revised in fix round 1 (row F1): `jdk.*` -> `jdk.internal.*` + `jdk.javadoc.internal.*`, `java.awt.*`/`javax.swing.*` -> `java.awt.List` + `java.awt.peer.*` |
| 2 | Postfix templates (jdt.ls Snippet items with `filterText` "http.cast"): match on the key only, `score_offset` -6 | unchanged | `http.` 19 -> 9, `repository.` 42 -> 32 | kept |
| 3 | Drop fully qualified packages for a bare identifier (roots kept unless filtered as a whole) | unchanged | `s`: shown 200 -> 34 items, first non-project type 7 -> 17; `a`: `aj.*`/`apple.*` packages gone | kept |
| 4 | blink `snippets` source hidden after `.` and `@` in Java | unchanged | `http.` shown 138 -> 102, `repository.` 88 -> 52, `@My` 3 -> 1 | kept |
| 5 | Project usage as tie breaker after jdt.ls relevance (`nv4j/usage.lua`, ripgrep count of `.name`/`@Name`), Object's methods excluded (as IntelliJ's mostUsed weigher) | blink sort moves to Lua for Java (no visible change in p95) | `http.` 9 -> 2, `repository.` 32 -> 1, `@` 6 -> 7 (`@Valid`, 2 uses, moves up within its bucket) | kept |
| 6 | Take JDT's `java.*` +2 relevance bonus back out (IntelliJ proximity: project before SDK) | unchanged | `@` 7 -> 4 | kept |
| 7 | Warm-up completion at an existing `@`/`new` position on ServiceReady (`nv4j/warmup.lua`) | `cold_first` 864 -> 309, 401, 612, 350 (check 10 runs); first `@` 66 ms when the warm-up finished first | unchanged | kept |
| 8 | jdt.ls JVM `-XX:+UseParallelGC` | first `@` 339-361 vs 225-287 without | - | reverted |
| 9 | jdt.ls JVM AppCDS (`-XX:+AutoCreateSharedArchive`, needs `-XX:+AllowArchivingWithJavaAgent` for Lombok and `-Xlog:disable`, else CDS messages on stdout break LSP) | first `@` without warm-up 710-761 vs 700-870; open to ready about -300 ms | - | reverted (no gain on the target, fragile) |
| 10 | `referencesCodeLens` off during start | first `@` 212-418, same as on | - | reverted |
| 11 | Warm-up variants: prefixed completion (`@R`), `workspace/symbol`, 5 s idle, warm-up at `Started` instead of `ServiceReady` | first `@` 734, 649, 769, 410 | - | not used then. Fix round 1 found the `Started` reading was wrong: with the check pinned to ServiceReady + 1.0 s, warming at `Started` and again at `ServiceReady` gives 44-67 ms (see Fix round 1) |
| 12 | `maxResults` 50 / 1000 | 50: first `@` 775-905 (no change). 1000: `@` complete (504 items, `isIncomplete=false`), identifier menu p95 31 -> 49, payloads 5x | 1000: same ranks | reverted, 200 kept |
| 13 | `lazyResolveTextEdit` on | big lists p95 about -5 ms (`s` 33 -> 24) | same | reverted: the insert text then depends on `completionItem/resolve` finishing inside blink's 100 ms resolve timeout on accept |
| 14 | lazyvim.json: drop `lang.typescript.vtsls` and `formatting.prettier` (nothing in the config uses them; Java formats through jdt.ls, XML through lemminx) | - | - | kept |
| F1 | Fix round 1: narrowed `filteredTypes` (+ `java.awt.List`, `java.awt.peer.*`, override `vim.g.nv4j_filtered_types`), robust usage index, warm-up at `Started` + `ServiceReady`, cold_first pinned at ServiceReady + 1.0 s | 3 full runs (logs `test-20261020-203152/-203323/-203458.log`), 68 PASS each: warm p95 worst 38.1 ms (`@`), menu p95 worst 37.3 ms; cold_first 54, 52, 54 ms; 16 extra cold-only runs 44-59 ms, empty workspace 67 ms. Check 01 open to ready 6393-6446 ms (before 6504-6595). Check 10's `jdtls_import` now includes the pinned cold phase (about 7.3 s) and is not comparable with earlier rows | unchanged: `@` 4, `http.` 2, `repository.` 1; new `list_type_not_imported` 1; no_noise a/s/m/List PASS | kept |
