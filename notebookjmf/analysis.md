# NotebookJMF — Project Analysis & Decision Record

_Last updated: 2026-04-28_

---

## What We Are Building

A **personal, local-first documentation intelligence system** (NotebookLM alternative) designed for engineers. The system ingests technical documentation, indexes it locally, and exposes it to AI agents (Claude, Cursor) via **MCP (Model Context Protocol)**.

Core promises:
- Answers are grounded in indexed sources only — no hallucinations
- All data stays on your machine (local-first, cloud-optional)
- Zero or near-zero operational cost
- Fully snapshot-based: deterministic, auditable, reproducible

---

## Can We Adapt OpenKB to Fit Our Requirements?

_Deep analysis performed 2026-04-28 — source code reviewed._

### OpenKB Internal Architecture (what we actually found)

**Storage: 100% plain files — no database.**
```
wiki/
  summaries/{doc}.md       ← per-document summary (YAML frontmatter)
  concepts/{concept}.md    ← cross-document concept pages
  sources/{doc}.md|.json   ← converted content
  index.md                 ← catalog
  log.md                   ← append-only operation log
.openkb/
  hashes.json              ← SHA-256 registry (dedup / change detection)
  config.yaml              ← model, language, thresholds
  chats/{id}.json          ← chat sessions
```

**Ingestion pipeline:**
`hash check → copy to raw/ → Markitdown conversion → async LLM summary → concept synthesis → cross-reference updates`

**LLM integration:** via LiteLLM — provider-agnostic abstraction. One config line to switch model. Ollama is fully supported:
```yaml
model: ollama/llama3
```
No code changes needed.

**PageIndex:** fully open-source (Apache 2.0, separate repo). Used for long PDFs (≥20 pages). Works locally by default — no cloud needed. Optional cloud OCR via `PAGEINDEX_API_KEY` but that's opt-in.

---

### Requirement vs OpenKB Gap Analysis

| Our requirement | OpenKB today | Gap | Effort |
|---|---|---|---|
| Markdown ingestion | Yes — Markitdown | None | Zero |
| PDF ingestion (local) | Yes — pymupdf + PageIndex | None | Zero |
| HTML / web page (single page) | Yes — Markitdown handles HTML | None | Zero |
| Web graph crawling (full docs site) | No | Need a crawler on top | Medium |
| Local embeddings / zero LLM cost | No — LLM needed for wiki compilation | LLM API cost per ingestion | Unavoidable with OpenKB |
| MCP server (Cursor + Claude) | No | Must be added | **Low — 1-2 days** |
| Snapshot / immutability model | No | Must be added if needed | High |
| Grounded answers with source attribution | Partial — concepts link back to source files | Good enough for MVP | Low |

---

### The One Unavoidable Trade-off

OpenKB's core value is that an LLM **compiles** documents into a wiki — it reads your PDFs and Markdown and generates structured summaries and concept pages. This is what makes it powerful. But it means **every ingestion costs LLM API tokens**.

Our original design avoided this by using local Ollama embeddings (zero cost per ingestion). With OpenKB you either:
- Accept LLM API costs at ingestion time (pay per document added), OR
- Configure it to use a local Ollama model — slower but free

Using `ollama/llama3` as the compilation model is a real option. The wiki quality will be lower than GPT-4o but functional.

---

### What Adapting OpenKB Concretely Looks Like

**Step 1 — Fork and configure (Day 1)**
```bash
git clone https://github.com/VectifyAI/OpenKB my-kb
pip install -e my-kb
openkb init  # set model: ollama/llama3 for zero cost
```

**Step 2 — Add MCP server (Day 1-2)**

The wiki is plain files. An MCP server just reads them. No OpenKB internals need to change:

```python
# mcp_server.py — add alongside OpenKB, reads wiki/ directly
from mcp.server.stdio import stdio_server

@server.tool()
def search_wiki(query: str) -> str:
    # read wiki/index.md, wiki/summaries/, wiki/concepts/
    # return relevant content with source attribution
    ...

@server.tool()
def list_sources() -> list:
    # read .openkb/hashes.json
    ...
```

**Step 3 — Add web crawler (Phase 2, optional)**

OpenKB already handles a single HTML page. Add a crawler that downloads pages into `raw/` and OpenKB's watcher picks them up automatically:

```python
# crawler.py — feeds URLs into raw/ dir, OpenKB does the rest
def crawl(root_url: str, output_dir: str):
    # graph traversal, same-domain filter, download HTML to raw/
    ...
```

**Step 4 — Wire to Cursor / Claude**

Register the MCP server in Cursor's `mcp.json` or Claude Desktop's config:
```json
{
  "mcpServers": {
    "my-kb": {
      "command": "python",
      "args": ["path/to/mcp_server.py"]
    }
  }
}
```

---

### Effort Comparison

| Approach | Time to first working prototype | Long-term maintainability | Zero cost guarantee |
|---|---|---|---|
| Build from scratch (Java, current plan) | 4-6 weeks | High | Yes |
| Adapt OpenKB + add MCP | **3-5 days** | Medium (upstream dependency) | Only if using Ollama model |
| OpenKB as-is (no MCP) | 1 day | High (no changes) | No (no Cursor/Claude integration) |

---

### Recommendation

**Yes, you can adapt OpenKB — and it is the faster path.**

The practical approach:
1. Fork OpenKB, configure `ollama/llama3` as the model (free, local)
2. Add a Python MCP server on top that reads the `wiki/` directory — 1-2 days of work
3. Use `openkb watch` so documents auto-reprocess when you drop files
4. Add the web crawler later when you need it — it feeds into the existing pipeline naturally

What you give up vs. building from scratch:
- No snapshot/immutability model (OpenKB has no versioning)
- Slightly lower quality with local Ollama models vs. GPT-4o
- Dependency on an upstream project that is still in early development (v0.1.3)

What you gain:
- Working Cursor + Claude integration in days, not weeks
- PDF, Markdown, HTML ingestion already solved
- Active project with community momentum

---

## Why Not Use NotebookLM (Google)?
- Cloud-only — your documents leave your machine
- No MCP integration — agents cannot query it
- Closed, not extensible
- Paid/freemium

---

## Our System — Confirmed Design Decisions

### Source Model
| Concept | Description |
|---|---|
| **Source** | Logical container (e.g. "Spring Boot Docs", "My Obsidian Notes") |
| **Snapshot** | Immutable point-in-time capture of a source |
| **Resource** | Physical file (`.md`, `.pdf`, `.html`) within a snapshot |
| **Normalized Document** | Format-agnostic semantic representation of a resource |
| **Query Unit** | Atomic retrieval unit — one heading + its direct content |

### Filesystem Layout
```
sources/
  <source-id>/
    snapshots/
      <snapshot-id>/
        raw/         ← original files, preserved as-is
        normalized/  ← format-agnostic parsed output (JSON)
indexes/
  <source-id>/
    <snapshot-id>/   ← Lucene HNSW index, regenerable
```

### Technology Stack (all free, all local)
| Concern | Technology | Notes |
|---|---|---|
| Language | Java 25 | Records, built-in HttpClient |
| Build | Maven | |
| CLI | Picocli 4.7.x | Subcommands: ingest, reindex, search, list |
| Markdown parsing | commonmark-java | AST: headings, paragraphs, lists, code blocks |
| JSON persistence | Jackson | Domain model serialized to disk |
| Embeddings | Ollama + nomic-embed-text | Local, 768-dim vectors, zero cost |
| Vector index | Apache Lucene (HNSW KNN) | Embedded, no external service |
| MCP server | Official MCP Java SDK | stdio transport — works with Claude + Cursor |

**No framework (Spring/Quarkus).** Plain Java with purposeful libraries.

### Future Parsers (already planned in stack)
| Format | Library | Status |
|---|---|---|
| Markdown | commonmark-java | **MVP** |
| PDF | Apache PDFBox | Phase 2 |
| Web / HTML | JSoup | Phase 2 |
| DOCX | Apache POI | Phase 2 |

---

## Your Specific Questions — Answered

### Can markdown and PDF processing be done locally?
**Yes, fully locally.**
- Markdown: commonmark-java parses to AST with no network calls
- PDF: Apache PDFBox (planned Phase 2) runs entirely embedded — no API, no cloud
- Embeddings: Ollama runs on `localhost:11434` — no external calls
- Everything stays on your machine

### Can the system be extended to parse web URLs / HTML in the future?
**Yes — it is already planned and architecturally supported.**
- JSoup is the chosen library (already in the tech stack doc)
- The web ingestion model is designed around graph traversal:
  - Single root URL + domain scope
  - Crawls all reachable documentation pages
  - HTML stored as raw, parsed output stored separately
  - No live web queries after snapshot creation
- Extensibility is a core design principle: adding a new source type does not require redesigning the system

### Can Cursor and Claude agents use this?
**Yes — that is the primary integration target.**
- The system runs as a **stdio MCP server** using the official MCP Java SDK
- This is the exact transport that both Claude Desktop and Cursor use natively
- The MVP tool exposed: `search_documentation(query, source_id?)`
- Agents get back grounded answers with full source attribution

---

## MVP Scope (What We Build First)

**In scope:**
- Markdown ingestion: `ingest → normalize → chunk → embed → index → query via MCP`
- CLI with Picocli
- Local embeddings via Ollama + nomic-embed-text
- Lucene vector index (HNSW)
- MCP server (stdio)
- End-to-end validation with a real Markdown source

**Out of scope (Phase 2):**
- Web/HTML crawling (JSoup)
- PDF extraction (PDFBox)
- DOCX parsing (Apache POI)
- Hybrid search (BM25 + vector)
- REST API

---

## Implementation Order

1. Domain model as Java Records
2. Markdown parser → normalization → chunking
3. Filesystem persistence layer (JSON)
4. Embedding via Ollama
5. Lucene vector index
6. CLI (Picocli)
7. MCP server
8. End-to-end validation with real Markdown source

Each step is independently testable.

---

## What We Have Not Built Yet

No code exists. The project currently contains only:
- `plan.md` — consolidated design document
- `steps/01` through `steps/10` — detailed design step files covering vision, principles, source model, filesystem, web ingestion, normalization, query units, tech stack, future steps, and architectural decisions

Next action: start implementation (Step 1 — Java Records domain model).
