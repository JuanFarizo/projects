# Feature: JPA checks (Spring Data JPA)

Priority: P4 (D6 "JPA checks"). Status: research only (2026-11-05). Nothing is built and nothing was run live; every statement about Nv4J below is read from the config or from the Spring Tools source, and each is marked `source` (read) or `probe needed` (must be measured on a real run before it is trusted).

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

## Gaps and decisions proposed (Claude, the user can overturn)

| # | Proposal | Cost if wrong |
|---|----------|---------------|
| P1 | First measure, then build: one probe script that opens `CustomerRepository` with a planted bad `@Query("selec c from Customer c")`, and one with `findBy` completion, against the real Spring LS. What shows decides what is a check, what is a fix, what is a known limit. | none |
| P2 | J1 and J2 become checks if the probe shows they work; if a setting does not reach the server, fix by pushing it (small Lua). | a missing setting push is a one-line fix |
| P3 | J4: serve `META-INF/jpa-named-queries.properties` to the Spring LS only if the probe shows the server answers for it (needs the plugin gate widened; touches spring-boot.nvim config). | gate change affects every `.properties` file; keep it to this one name |
| P4 | J5: not tested on the demo fixture (Boot 3.5). Testing it needs a Boot 4 fixture and an AOT build (slow, network). Left out until the user wants it. | the feature may exist for the user's real Boot 4 project and be unverified |
| P5 | Unknown property in a derived query name: no check, listed as a known difference from IntelliJ Ultimate. Building our own would mean a second source of truth beside the Spring LS (jdt.ls can resolve the entity's properties, but a derived-query name parser is real work, not lazy). | the user does not get the IntelliJ warning |

## Pass/fail checks (to write after the probe, run when the machine is free)

Proposed check `76_jpa` (Spring LS and jdt.ls live), cases and controls, budget-free (no latency number is promised before it is measured):

- `jpql_error`: a planted bad `@Query` string gets a diagnostic from the Spring LS with an ERROR on that string; the good fixture query gets none. Control: setting `boot-java.validation.data-query = OFF` removes it.
- `derived_complete`: `findBy` in `CustomerRepository` completes `Email` and `FullName` (the entity's properties). Control: a repository for a type without those fields does not offer them.
- `named_queries_file` (only if P3 is accepted): a bad query in `jpa-named-queries.properties` gets a diagnostic.
- `defaults_pushed`: the settings the server received contain the keys we depend on (reads the push log).

## Open items

- Probe not yet written or run (P1).
- Whether Neovim shows semantic tokens for the JPQL string (J3) is unmeasured.
