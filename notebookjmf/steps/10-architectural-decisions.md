# Architectural Decisions

## ADR-001: No Framework — Plain Java with Purposeful Libraries

**Decision:** Use plain Java 25 with individual libraries (Picocli, commonmark-java, Lucene, MCP SDK). No Spring Boot, no Quarkus.

**Why:** This is a local personal tool, not a service. Frameworks add startup time, memory overhead, configuration complexity, and abstraction layers that don't pay off at this scale. Each library added has exactly one job.

**Tradeoff:** No DI container means manual wiring in `main()`. Acceptable for MVP; revisit if the codebase grows significantly.

---

## ADR-002: Filesystem as the Only Persistence Layer

**Decision:** All state (sources, snapshots, normalized documents, query units) is stored as JSON files on disk. No database (SQL or NoSQL).

**Why:** Debuggable by opening a file. Portable (copy the `data/` directory anywhere). Backed up with any file backup tool. No server to run, no schema to migrate.

**Tradeoff:** No transactional consistency. Acceptable because writes are append-only (new snapshots, never updates to existing ones).

---

## ADR-003: Snapshot Immutability

**Decision:** A snapshot, once created, is never modified. Re-ingesting a source creates a new snapshot.

**Why:** Guarantees reproducibility. If a query gives a different answer after re-ingesting, the old snapshot still exists for comparison. Audit trail is implicit.

**Tradeoff:** Disk grows over time. Mitigation: a `notebook prune` command (Phase 2) can remove old snapshots.

---

## ADR-004: Official MCP Java SDK over Spring AI MCP

**Decision:** Use `io.modelcontextprotocol.sdk:mcp` directly.

**Why:** Spring AI MCP requires Spring Boot as a runtime, adding ~50-100 MB to the JAR and 3-5s startup time. The official SDK is purpose-built for MCP, supports stdio out of the box, and has no transitive framework dependencies.

**Tradeoff:** No auto-configuration or Spring integration. Acceptable; MCP server has a single, stable interface.

---

## ADR-005: Picocli over Spring Shell

**Decision:** Use Picocli for the CLI layer.

**Why:** 408 KB JAR vs full Spring Boot dependency. Annotation-driven, supports subcommands, GraalVM native image compatible. Spring Shell requires Spring Boot and its full startup lifecycle — unnecessary for a CLI tool.

**Tradeoff:** No Spring DI in CLI commands; dependencies are wired manually. Trivial at MVP scale.

---

## ADR-006: nomic-embed-text as the Embedding Model

**Decision:** Use `nomic-embed-text` via Ollama (local inference).

**Why:** Zero cost. 270 MB model. Proven retrieval quality. Simple API. Runs entirely offline. No API key required.

**Tradeoff:** Embedding 1000+ documents takes minutes locally. Acceptable for a personal ingestion tool (not a real-time pipeline). Upgrade path: `snowflake-arctic-embed-m-long` for longer sections (8192-token context).

---

## ADR-007: Apache Lucene for Vector Indexing

**Decision:** Use Lucene's built-in HNSW KNN vector support.

**Why:** Embedded (no server), pure Java, battle-tested, free. Supports both exact and approximate (HNSW) KNN search. Index is stored on disk, regenerable at any time.

**Tradeoff:** No distributed search, no persistence of in-flight updates. Irrelevant for a single-user local tool.

---

## ADR-008: Pure Vector Search for MVP

**Decision:** Retrieval is semantic-only (vector KNN). No keyword (BM25) component in MVP.

**Why:** Simpler implementation. For technical documentation, semantic search captures intent well enough. Hybrid search (BM25 + vector re-ranking) is a Phase 2 option if quality proves insufficient.

**Tradeoff:** Pure vector can miss exact matches (e.g., searching a specific error code). Mitigated by: the user can always grep the raw files, and hybrid is one ADR revision away.

---

## ADR-009: Section as the Query Unit Boundary

**Decision:** Each Markdown heading + its content is one query unit. Subsections are independent units.

**Why:** Sections are the natural semantic unit in technical documentation. Smaller units (paragraphs) lose context. Larger units (full documents) exceed embedding token limits and dilute relevance.

**Tradeoff:** A very long section may be split mid-content. Mitigated by overlapping windows that preserve local context.
