# Concrete Technology Stack

## Language and Runtime

- Java 25 (LTS)

## Build

- Maven

## CLI

- **Picocli 4.7.x** (408 KB JAR)
  - Annotation-driven command parsing
  - Subcommands: `ingest`, `reindex`, `search`, `list`
  - No framework required; wires directly into a `main()` method

## Markdown Ingestion

- **commonmark-java**
  - Parses Markdown into an AST (headings, paragraphs, lists, code blocks)
  - Drives normalization and section extraction

## Data Representation

- Java Records (domain model, immutable by design)
- **Jackson** for JSON serialization to disk
- No database; filesystem is the persistence layer

## HTTP Client (Ollama)

- Java built-in `HttpClient` (Java 11+, zero dependencies)
- Used only to call the local Ollama embedding API

## Embedding Model

- **Ollama** (local inference, zero cost)
- Model: **nomic-embed-text** (270 MB, 768-dim vectors)
  - Proven retrieval quality; outperforms OpenAI ada-002 on benchmarks
  - Fast local inference; low RAM footprint
  - Future option: `snowflake-arctic-embed-m-long` (8192-token context, 110 MB)
- Ollama must be running on `localhost:11434` before indexing or search

## Vector Indexing

- **Apache Lucene** (HNSW KNN vectors)
  - Embedded; no external service
  - Index files stored under `data/indexes/<source-id>/<snapshot-id>/`
  - Disposable: regenerable from query units at any time

## Retrieval Strategy

- **Pure semantic vector search** (MVP)
  - Query text → embed with same model → KNN in Lucene → top-K QueryUnits
  - No keyword (BM25) component in MVP; hybrid is a Phase 2 option

## MCP Server

- **Official MCP Java SDK** (`io.modelcontextprotocol.sdk:mcp`)
  - Maintained by the MCP team (Anthropic + Spring)
  - Stdio transport: works with Claude and Cursor out of the box
  - MCP server runs as a separate process; tools registered programmatically
  - MVP tool: `search_documentation(query, source_id?)`

## Web Documentation Parsing (future)

- JSoup

## PDF Extraction (future)

- Apache PDFBox

## Document Parsing / DOCX (future)

- Apache POI

---

## Stack Summary

| Concern | Technology | Cost |
|---|---|---|
| Runtime | Java 25 | Free |
| CLI | Picocli | Free |
| Markdown parse | commonmark-java | Free |
| JSON | Jackson | Free |
| HTTP (Ollama) | Java built-in HttpClient | Free |
| Embeddings | Ollama + nomic-embed-text | Free (local) |
| Vector index | Apache Lucene | Free |
| MCP server | Official MCP Java SDK | Free |

**No framework (Spring/Quarkus) in MVP.** Plain Java with purposeful libraries.
This keeps startup instant, JAR size minimal, and the codebase fully understandable.
