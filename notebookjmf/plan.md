# Personal Documentation Intelligence System (NotebookLM-like)

## 1. Purpose

The goal of this project is to build a **personal, local-first documentation intelligence system**, inspired by NotebookLM, with the following characteristics:

- Uses **user-controlled documentation** as the single source of truth
- Supports multiple documentation formats:
  - Markdown (primary source, Obsidian notes)
  - Web documentation (frameworks, libraries)
  - PDFs
  - Documents (e.g. DOCX)
- Avoids hallucinations by grounding all answers in indexed sources
- Is fully **snapshot-based**, reproducible, and auditable
- Can be queried by AI agents via **MCP**
- Runs with **zero or near-zero cost**, prioritizing local execution

This is a **personal knowledge infrastructure**.

---

## 2. Core Design Principles

1. **Source-controlled knowledge**
   Only content explicitly ingested into the system can be queried.

2. **Snapshot immutability**
   Ingested documentation is immutable. Updates create new snapshots.

3. **Filesystem as infrastructure**
   Raw and processed content is stored in the filesystem, not databases.

4. **Extensible by design**
   Adding new source types must not require redesign of the system.

5. **Structure-aware, not format-bound**
   Preserve minimal semantic structure across all document types.

6. **Local-first, cloud-optional**
   The system must work entirely offline.

---

## 3. Conceptual Model

### 3.1 Source (Logical Container)

A **Source** represents a logical collection of documentation.

Examples:

- Obsidian Notes
- Spring Boot Documentation
- Mantine UI Documentation

A source is **not** a file or a URL.
It is a conceptual container.

---

### 3.2 Snapshot

Each source has one or more **snapshots**.

- A snapshot represents the documentation at a point in time
- Snapshots are:
  - Immutable
  - Reproducible
  - Independently queryable

Updating documentation **always creates a new snapshot**.

---

### 3.3 Resource

A **Resource** is a physical artifact stored in the filesystem:

- Markdown file
- HTML page
- PDF file
- Document file

Resources belong to a snapshot.

---

### 3.4 Normalized Document

A resource is parsed into one or more **normalized documents**, which:

- Are format-agnostic
- Preserve minimal semantic structure
- Are the basis for querying and indexing

---

## 4. Filesystem Layout (Conceptual)

```text
sources/
  <source-id>/
    snapshots/
      <snapshot-id>/
        raw/
          (original files / html / pdf)
        normalized/
          (structured, format-agnostic representations)
indexes/
  (vector indexes, regenerable)
```

- `raw/` is the archival source of truth
- `normalized/` is the semantic representation
- Indexes are disposable and regenerable

---

## 5. Web Documentation Ingestion Model

### 5.1 Scope Definition

A web source is defined by:

- A single root URL
- A documentation-specific path
- A single domain

Only URLs that:

- Belong to the same domain
- Share the documentation path prefix

are considered part of the source.

---

### 5.2 Navigation Strategy

- Documentation is traversed as a **graph**, not by fixed depth
- All reachable, valid documentation pages are included
- Each page is visited once
- Navigation is extracted only from content-relevant areas

This enables capturing **complete framework documentation**
(e.g. Spring, React, Mantine).

---

### 5.3 Snapshot Semantics

- All pages are downloaded and stored locally
- HTML is preserved as raw input
- Parsed output is stored separately
- No live querying of the web occurs after snapshot creation

---

## 6. Minimal Preserved Structure

For all document types, the system preserves:

- Document title
- Section hierarchy (headings with levels)
- Content blocks:
  - paragraphs
  - lists
  - code blocks
- Ordering within the document
- Source references (path / URL)

Explicitly excluded:

- Navigation
- Menus
- Headers / footers
- Styling
- Scripts
- Non-content metadata

The goal is **semantic clarity**, not full document reconstruction.

---

## 7. Query Unit Definition

### 7.1 Atomic Query Unit

The atomic unit of retrieval is a **logical section**, defined as:

- A heading
- All direct content belonging to that heading
- Up to the next heading of the same level

Subsections are independent query units.

---

### 7.2 Size Constraints

- If a section becomes too large, it is split internally
- Splits preserve order and context
- No merging of unrelated sections

---

### 7.3 Metadata Requirements

Each query unit includes:

- Source identifier
- Snapshot identifier
- Original resource reference
- Full section breadcrumb (hierarchical path)
- Position within the document

This guarantees traceability and grounding.

---

## 8. Indexing and Retrieval (Conceptual)

- Query units are embedded and indexed
- Retrieval returns the most relevant units
- Responses are built exclusively from retrieved units
- Lack of information must be explicitly surfaced

Indexes are:

- Local
- Regenerable
- Not the source of truth

---

## 9. Agent Integration (MCP)

The system exposes its retrieval capabilities via **Model Context Protocol (MCP)**.

Key characteristics:

- Pure read-access to documentation
- Explicit source attribution
- No hidden inference beyond retrieved data
- Runs as a stdio MCP server (works with Claude, Cursor out of the box)
- Implemented with the **official MCP Java SDK** (not Spring AI)

This enables usage from:

- Claude
- Cursor
- Other MCP-compatible agents

---

## 10. MVP Scope

**In scope (MVP):** Markdown ingestion only, fully end-to-end:
`ingest → normalize → chunk → embed → index → query via MCP`

**Out of scope (Phase 2):** Web documentation, PDF, DOCX, hybrid search, REST API.

**Technology choices (zero cost):**
- CLI: Picocli (no framework)
- MCP: Official MCP Java SDK (no Spring)
- Embeddings: Ollama + `nomic-embed-text` (local)
- Vector index: Apache Lucene (embedded)
- Persistence: JSON files on disk (no database)

See `steps/10-architectural-decisions.md` for the rationale behind each choice.

---

## 11. Implementation Strategy

1. Define domain model as Java Records
2. Implement Markdown parser → normalization → chunking
3. Build filesystem persistence layer
4. Add embedding via Ollama
5. Build Lucene vector index
6. Wire CLI (Picocli)
7. Expose MCP server
8. Validate end-to-end with a real Markdown source

Implementation is strictly incremental. Each step is independently testable.

---

## 12. Non-Goals

This system explicitly does **not** aim to:

- Be a real-time web search engine
- Automatically discover new sources
- Modify or generate documentation
- Optimize for multi-user scenarios

---

## 13. Success Criteria

The system is considered successful if:

- Documentation answers are grounded and traceable
- New sources can be added without redesign
- The system remains understandable and debuggable
- All data is user-controlled and portable
