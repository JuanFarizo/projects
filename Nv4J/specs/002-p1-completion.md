# 002 - P1 completion: budget, baseline, trials

Status: baseline recorded at Spring scale (Task 3, fix round 1). Tuning: Task 5. Research and approach: `specs/features/completion-ranking.md`.

## Budget (provisional)

| Metric | Budget | Check |
|--------|--------|-------|
| Warm completion round trip, p95 per case | <= 150 ms | `tests/checks/10_completion_latency.lua` |
| First completion request after jdtls is ready | <= 400 ms | same, `cold_first` |
| Expected item rank in the order the user sees | top 5, plus the case's relative rule | `tests/checks/11_completion_ranking.lua` |

These numbers are still "confirm with the user after baseline" (plan, Global Constraints). They were not changed in fix round 1. With Spring on the classpath, `cold_first` and three ranking cases break them, see "What the numbers show".

## Fixture

`tests/fixtures/demo` is a Spring Boot 3.5.13 project (`spring-boot-starter-parent`, Java release 25, compiles with `mvn -q compile` on Corretto 25). Starters: web, data-jpa, security, validation, test, plus H2 (runtime). Sources:

- `DemoApplication` (`@SpringBootApplication`), `Customer` (`@Entity`, `@Table`, `@Column`, Bean Validation), `CustomerRepository` (`JpaRepository<Customer, Long>` plus two derived queries), `CustomerController` (`@RestController`, GET/POST/PUT), `SecurityConfig` (`@Configuration`, `HttpSecurity` DSL).
- The toy sources stay (`App`, `Person`, `Repo`, `MyAnno`, `Modern`), so the toy cases still run, now with Spring on the classpath too. Checks 00 and 01 pass.

## Method

- `tests/run.sh` runs each check in a fresh headless `nvim` (`NVIM_APPNAME=nv4j`) with a fresh jdtls process. The jdtls workspace in `/tmp/nv4j/jdtls-data` persists between runs, so the index is warm; the JVM is not.
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

## Budget decision needed

Keep the provisional budgets (not weakened). Open for the user before Task 5: whether `cold_first` <= 400 ms is the right target (it is now the only latency budget that fails), and whether the ranking expectation for prefix-less lists (`@`) should stay at top 5.

## Trial log (Task 5)

One change per trial. Keep a change only if a number improves. Columns: trial, change, p50/p95 per case, ranks, kept or reverted.

| # | Change | Latency (p50 / p95) | Ranks | Kept |
|---|--------|---------------------|-------|------|
