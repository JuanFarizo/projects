# Implementation Steps

## MVP Boundary

End-to-end pipeline for **Markdown only**: ingest → normalize → chunk → embed → index → query via MCP.
All other source types (web, PDF, DOCX) are explicitly Phase 2.

---

## Phase 1 — MVP (Markdown + MCP)

### Step 1 — Project Bootstrap

- Create Maven project with `pom.xml` (Java 25, no parent framework)
- Dependencies: `picocli`, `commonmark-java`, `jackson-databind`, `lucene-core`, `mcp-sdk`
- Entry point: `Main.java` → Picocli command dispatcher
- Structure:
  ```
  src/main/java/
    com/notebookjmf/
      cli/          ← Picocli commands
      domain/       ← Java Records (pure model)
      ingestion/    ← Parsers and chunkers
      index/        ← Lucene wrapper
      mcp/          ← MCP server and tools
      storage/      ← Filesystem read/write
  ```

### Step 2 — Domain Model (Java Records)

```java
record Source(String id, String name, String description, Instant createdAt)
record Snapshot(String id, String sourceId, Instant createdAt)
record Resource(String id, String snapshotId, Path path, ResourceType type)
record NormalizedDocument(String id, String resourceId, String title, List<Section> sections)
record Section(String id, int level, String heading, String breadcrumb, List<Block> blocks, List<Section> children)
record Block(BlockType type, String content)      // PARAGRAPH, LIST_ITEM, CODE
record QueryUnit(String id, String sectionId, String snapshotId, String sourceId,
                 String text, String breadcrumb, int position, float[] embedding)
```

All records are immutable. `embedding` is populated after the embedding step.

### Step 3 — Filesystem Layout

```
data/
  sources/
    <source-id>/
      source.json
      snapshots/
        <snapshot-id>/
          snapshot.json
          raw/
            *.md                  ← verbatim copy of originals
          normalized/
            <file-hash>.json      ← NormalizedDocument per file
          query-units/
            <file-hash>.json      ← List<QueryUnit> per file
  indexes/
    <source-id>/
      <snapshot-id>/              ← Lucene index files
```

Implement `StorageLayout` class: given a source ID + snapshot ID, returns typed `Path` handles for each location.

### Step 4 — Markdown Parser

`MarkdownParser` takes a `.md` file and returns a `NormalizedDocument`:

1. Parse with commonmark-java into an AST
2. Walk the AST node by node
3. On `Heading`: open a new `Section` at the correct level; close child sections as needed
4. On `Paragraph`, `BulletList`, `FencedCodeBlock`: append `Block` to current open section
5. Title = first H1 heading text, or filename if absent
6. Build breadcrumb per section from ancestor heading texts

### Step 5 — Query Unit Chunker

`QueryUnitChunker` takes a `NormalizedDocument` and returns `List<QueryUnit>`:

1. Walk sections (depth-first, respecting hierarchy)
2. For each section: concatenate heading + all block texts into a single string
3. If text length > ~1800 characters: split into overlapping windows (500-char overlap)
4. Assign sequential `position` per document
5. Attach full `breadcrumb`, `sourceId`, `snapshotId`

### Step 6 — Storage Layer

Simple file-based repositories using Jackson:

- `SourceStore`: read/write `source.json`
- `SnapshotStore`: read/write `snapshot.json`
- `QueryUnitStore`: read/write `List<QueryUnit>` per file

No interfaces needed in MVP. Direct implementations.

### Step 7 — CLI: `ingest` Command

```
notebook ingest --source-id obsidian-notes --path /Users/juan/notes --name "Obsidian Notes"
```

Flow:
1. Create or load `Source` by ID
2. Create new `Snapshot` (UUID + timestamp)
3. Walk directory recursively for `.md` files
4. Copy each file to `raw/`
5. Parse → normalize → chunk
6. Persist `NormalizedDocument` to `normalized/` and `QueryUnit[]` to `query-units/`
7. Print summary (files, sections, units)

At this stage: no embedding yet. Verified by reading JSON output manually.

### Step 8 — Embedding

`OllamaEmbeddingClient` calls `POST localhost:11434/api/embeddings`:

```json
{ "model": "nomic-embed-text", "prompt": "<query unit text>" }
```

`EmbeddingStep` loads all QueryUnits for a snapshot, calls Ollama for each, writes back `embedding` field.
Runs as a sub-step of ingest or as a standalone `notebook embed` command.

### Step 9 — Lucene Vector Index

`LuceneIndexer`:
1. Open/create index at `data/indexes/<source-id>/<snapshot-id>/`
2. For each `QueryUnit` with a non-null embedding: index a `Document` with:
   - `KnnFloatVectorField("embedding", unit.embedding(), 768)`
   - `StoredField("queryUnitId", unit.id())`
3. Commit and close

`LuceneSearcher`:
1. Open index
2. Embed the query string via Ollama
3. `KnnFloatVectorQuery("embedding", queryVector, k=5)`
4. Load matching `QueryUnit` objects from disk by ID

### Step 10 — CLI: `search` Command (local validation)

```
notebook search --query "how to configure Spring Security" --source-id obsidian-notes
```

Prints top-5 results with breadcrumb and excerpt. Used to validate quality before wiring MCP.

### Step 11 — MCP Server

`McpServer` class:
1. Register tool `search_documentation` with input schema `{query: string, source_id?: string}`
2. Tool implementation calls `LuceneSearcher` and formats results as a structured JSON list
3. Launch stdio server via `io.modelcontextprotocol.sdk` `McpServer.stdio(...)` 

```
notebook mcp-server
```

Register in Claude config:
```json
{
  "mcpServers": {
    "notebookjmf": {
      "command": "java",
      "args": ["-jar", "/path/to/notebook.jar", "mcp-server"]
    }
  }
}
```

### Step 12 — End-to-End Validation

1. Ingest a real Markdown source
2. Embed + index
3. Run `notebook search` and verify relevance
4. Connect MCP to Claude, ask questions
5. Verify all answers are grounded in indexed sections
6. Verify breadcrumbs trace to real files

---

## Phase 2 — Post-MVP (priority order)

1. Web documentation ingestion (JSoup graph crawler + scope rules)
2. Reindex with diff detection (skip unchanged files by content hash)
3. Multi-source search (search across all sources in one query)
4. PDF ingestion (PDFBox)
5. DOCX ingestion (Apache POI)
6. Hybrid search: BM25 keyword + vector re-ranking
7. Upgrade embedding model (`snowflake-arctic-embed-m-long` for long-section documents)
