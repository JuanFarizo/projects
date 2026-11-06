# Feature: JPA checks (Spring Data JPA)

Priority: P4 (D6 "JPA checks"). Status: 2026-11-05 research done, user rulings applied (below), derived-query diagnostic and Boot 4 fixture built; live checks against the real Spring LS and jdt.ls NOT yet run (machine in use); every statement about Nv4J below is read from the config or from the Spring Tools source, and each is marked `source` (read) or `probe needed` (must be measured on a real run before it is trusted).

## Sources read (pinned)

- `spring-projects/spring-tools`, sparse clone `~/.cache/nv4j/spring-tools`, commit `9c979426e891278a6008d734febaf5d9014a5de1` (2026-10-21), the same pin as `spring-language-server.md`. Code: `headless-services/spring-boot-language-server/src/main/java/org/springframework/ide/vscode/boot/java/data/` (`jpa/queries/`, `providers/`, `QueryMethodCodeActionProvider`, `DataRepositoryCompletionProcessor`, `DataRepositoryAotMetadataCodeLensProvider`); settings in `vscode-extensions/vscode-spring-boot/package.json`.
- IntelliJ: the JPA and Spring Data support is in the Ultimate plugin, not in Community (known limit, `001` "IntelliJ reference"). The reference is IntelliJ's visible behaviour (JPQL in `@Query` is highlighted and checked, derived query method names are completed from the entity's properties and flagged when a property does not exist, repository methods navigate to the entity). No Community source path exists for it.

## What the Spring LS offers for Spring Data (source)

| # | Feature | Where | Needs |
|---|---------|-------|-------|
| J1 | JPQL / HQL / SQL syntax errors in `@Query` and `@NamedQuery` strings (`JPQL_SYNTAX`, `HQL_SYNTAX`, `SQL_SYNTAX`, severity ERROR) | `jpa/queries/QueryJdtAstReconciler`, `QueryProblemType`; settings `boot-java.validation.data-query` (default ON), `boot-java.jpql` (default true) | `spring-data-jpa` or `spring-data-jdbc` on the classpath; HQL parser when `hibernate-core` is present, else JPQL |
| J2 | Completion of derived query method names in a repository interface (`findBy...`, keywords `And`, `Or`, `OrderBy`, `Containing`, property names of the domain type) | `DataRepositoryCompletionProcessor` with three providers (standard, query start, prefix sensitive) | repository interface resolved to a domain type |
| J3 | Semantic tokens for JPQL/HQL/SQL inside the query string; document highlights of query parts; inlay hints on queries | `jpa/queries/*SemanticTokens`, `JdtQueryDocHighlightsProvider`, `JdtDataQueriesInlayHintsProvider` | client with semantic tokens / inlay hints |
| J4 | Named queries in `META-INF/jpa-named-queries.properties` (language id `jpa-query-properties`): reconcile and tokens | `NamedQueryPropertiesReconcileEngine`, `JpaQueryPropertiesLanguageServerComponents` | the file must be served to the Spring LS |
| J5 | Code lens over a query method with the AOT-generated query, and the code action "Add `@Query`" | `DataRepositoryAotMetadataCodeLensProvider`, `QueryMethodCodeActionProvider`; settings `boot-java.java.codelens-over-query-methods` (default true), `FeatureFlag.ADD_QUERY_ANNOTATION` | `spring-data-jpa` major >= 4 (Spring Boot 4) AND AOT metadata generation (a build with `processAot`); `isValidProject` returns false otherwise |
| J6 | Go to definition from a query parameter (`:name`) to the method parameter | `jpa/queries/DataQueryParameterDefinitionProvider` | J1 prerequisites |

No problem type exists in the Spring LS for "this derived query method names a property the entity does not have" (`QueryProblemType` has the three syntax types only). IntelliJ Ultimate does flag it. This is a real difference, see Gaps.

## Nv4J today (source; `probe needed` for what actually shows)

- Spring LS runs for Boot projects only (`50_spring_ls`), with the five jdt.ls bundles. Nothing in `nvim/lua` mentions `jpql`, `boot-java` or `data-query`: every setting above is at the server's default. `probe needed`: whether the defaults reach the server (spring-boot.nvim pushes `workspace/didChangeConfiguration`; what it contains was not read for these keys).
- `nvim/lua/plugins/lsp.lua`: codelens enabled, inlay hints disabled, semantic tokens not touched (Neovim 0.12 default is on). So J3 inlay hints are off by our choice, J3 tokens and J5 lens depend on the server.
- spring-boot.nvim serves `application*.yml/properties` only (`spring-language-server.md`): `jpa-named-queries.properties` (J4) is NOT served.
- Fixture `tests/fixtures/demo`: Boot 3.5.13, `Customer` (`@Entity`), `CustomerRepository` (`JpaRepository<Customer, Long>`, two derived queries, no `@Query`). Spring Data JPA is 3.x there, so J5 cannot apply; J1, J2, J3, J6 can.

## Rulings (user, 2026-11-05) and what was built

| # | Ruling | State |
|---|--------|-------|
| R1 | J5 (code lens over query methods, "Add `@Query`") must be supported and tested, whatever it costs (network, time): the tests get a Spring Boot 4 / Spring Data JPA 4 fixture. | Fixture `tests/fixtures/jpa4` built (Boot 4.0.8, Java 25, `spring-boot-maven-plugin`, `Customer` with an `@Embedded` `Address`, `CustomerRepository` with 3 derived methods and one `@Query`). `mvn compile` and `spring-boot:process-aot` run on it; `target/spring-aot/main/resources/jpa4/CustomerRepository.json` holds the generated query of each method (what the lens shows). The demo fixture stays on Boot 3.5 (28 other checks depend on it). Live run 2026-11-06 (check 82, 8 cases, control `/tmp/nv4j/logs/control-82.log`): J1 (HQL error as ERROR from `vscode-spring-boot`), J2 (`findBy` offers the properties, `And`/`Or`/`OrderBy`), J3 (semantic tokens answered), J5 (lens over every query method with the generated query, `Turn into @Query`, `Go To Implementation`, `Refresh AOT Metadata`; code action `Add @Query` offered on derived methods only and applied through `workspace/executeCommand` -> `workspace/applyEdit`) all work. FOUND: the Spring LS does not run the AOT build for this client, it hands it to the client as `maven.goal.custom` / `gradle.runBuild` (lens `Show AOT-generated Implementation...`); Nv4J had no handler, so without hand-made AOT metadata J5 showed nothing. Built `nv4j/aot.lua` (check 83, 7 cases): runs the wrapper or tool in the project folder with the server's env, else the project JDK from `nv4j.jdk` (a Java 25 project failed on the PATH JDK 21), notifies, refreshes the lenses. Without the handler check 82 fails 4 cases. |
| R2 | Reproduce IntelliJ's warning for a derived query method naming a property the entity does not have ("try to replicate the behaviour, based on the code or how it should work"). | Built as our own code (the Spring LS has no such problem type): `nvim/lua/nv4j/dataquery.lua`. Rules are Spring Data's own (`PartTree`, `Part.Type` keywords, `PropertyPath.create`: camel-case head/tail, `_` split, `Or`/`And` only before an uppercase letter, `OrderBy`). Message is Spring's: `No property 'emial' found for type 'Customer'`, ERROR, on exactly the bad text. Entity read through jdt.ls definition + treesitter (fields, record components, getters, superclasses, nested types, collections' element type); a type that is not read (library class, generic parameter, jdt.ls gives no file) accepts anything, so no false warning. Checks 76 (46 unit cases, 2 controls) and 77 (11 buffer cases with a stub jdt.ls, 3 controls) pass. Pending: live with the real jdt.ls (`78_jpa`), and the oracle below. |
| R4 | Completion inside `@Query` strings (user, 2026-11-05: "suggest the entity fields for the query, for a where", also fields of a joined entity). Neither the Spring LS (checked: the only completion in `data/` is derived method names, `DataRepositoryCompletionProcessor` and its providers) nor Nv4J offered it; IntelliJ Ultimate does (entities after `FROM`/`JOIN`, aliases, fields after `alias.` and `alias.path.`). | Step 1 built: pure part `nvim/lua/nv4j/jpql.lua` (alias map for FROM / JOIN / JOIN FETCH / comma / `JOIN Entity` / legacy `IN (x.y) a` / UPDATE; cursor context: member, entity, alias, expr, param, none; members of a path through joins and collections; unresolved gives nothing). Check 78 (49 cases; control with JOIN parsing off fails 8, log `/tmp/nv4j/logs/control-78.log`). Steps 2-3 built: `nv4j.jpqlcomplete` (the @Query literal under the cursor, string or text block, not `nativeQuery`; entities read through `nv4j.dataquery`, other entities by jdt.ls `workspace/symbol`; `@Entity` names by `rg`; `:param` names from the method) and the blink source `nv4j.jpqlsource` wired in `plugins/blink.lua` (provider `jpql`, first source for Java). Check 79: 15 cases with a stub jdt.ls (controls: named load off and nativeQuery ignored fail 2, `/tmp/nv4j/logs/control-79.log`). Step 4: check 80 written (real jdt.ls on `jpa4`, now with `Booking` + `BookingRepository`, Spring's process-aot accepts both queries), NOT RUN yet (heavy). The blink menu itself (UI) is unmeasured until a live session. |
| R3 | Mason fresh install: the user tests it. | Not mine. |

Known limits of R2 (said plainly): an entity that extends a library class (`AbstractPersistable<Long>`) is not judged; derived methods of repositories declared with `@RepositoryDefinition` are not found (only `extends ...Repository<T, ID>`); Spring's custom-fragment methods and `@Query`-less methods named on purpose for a fragment would be flagged (`findByNonsense` implemented by a fragment); property names with `@Column(name=)` differences do not matter (Java names are used, like Spring).

Oracle for R2 (to do with the live run): Spring Data itself rejects a bad derived name when `spring-boot:process-aot` runs on `jpa4`. The live check puts every name of check 76's list into a repository of the fixture, runs `process-aot` (must succeed) and then the bad names (must fail naming each property), so the parser is compared with the real implementation and not only with my reading of it.

## J8 plan: JPQL completion (R4)

1. DONE pure parser and context (`nv4j.jpql`, check 78).
(2 and 3 DONE, see R4; 4 written, not run.)
2. Buffer layer: find the `@Query` string under the cursor (string literal or text block, method inside a `...Repository<Entity, Id>` interface, not `nativeQuery = true`), unescape to the query text with an offset map, call `analyze`. Entity types: the repository's own entity from the generics, other entity names through jdt.ls `workspace/symbol` then the same definition + treesitter read as `nv4j.dataquery` (split the reader into a shared module). Unread type = nothing offered.
3. Completion source for blink.cmp (`sources.providers`, Java filetype only) returning fields (Field kind, type as description), entities, aliases, keywords, `:param` names from the method's `@Param`/parameter names; jdt.ls items inside the string are filtered out in the same place if they add noise.
4. Live check: bad/good fixture queries on `jpa4` with a second entity, real jdt.ls. Run only when the machine is free.

Known limits: native queries are not completed; entity superclasses from libraries limit the field list (same as R2); `FROM Branch` without alias is not completed; embedded `KEY()/VALUE()` map functions are ignored.

## Pass/fail checks (to write after the probe, run when the machine is free)

Proposed check `76_jpa` (Spring LS and jdt.ls live), cases and controls, budget-free (no latency number is promised before it is measured):

- `jpql_error`: a planted bad `@Query` string gets a diagnostic from the Spring LS with an ERROR on that string; the good fixture query gets none. Control: setting `boot-java.validation.data-query = OFF` removes it.
- `derived_complete`: `findBy` in `CustomerRepository` completes `Email` and `FullName` (the entity's properties). Control: a repository for a type without those fields does not offer them.
- `named_queries_file` (only if P3 is accepted): a bad query in `jpa-named-queries.properties` gets a diagnostic.
- `defaults_pushed`: the settings the server received contain the keys we depend on (reads the push log).

## Open items

- Probe done (2026-11-06): J1, J2, J3, J5 work (see R1). Settings: Nv4J pushes no `boot-java.*` (client settings `{}`), the server defaults apply and all of the above worked with them. Still unprobed: J4 (`jpa-named-queries.properties` is not served by spring-boot.nvim), J6 (`:param` go to definition).
- Gradle path of `nv4j.aot` (`gradle.runBuild`) has only the unit check (83); no live Gradle JPA 4 project was run.
- Whether Neovim shows semantic tokens for the JPQL string (J3) is unmeasured.
