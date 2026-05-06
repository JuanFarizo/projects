# Web Documentation Ingestion

## Intended Use Case
Capture **complete framework or library documentation** (e.g. Spring, React, Mantine) into a frozen snapshot.

## Scope Rules
- Single root URL
- Single domain
- Documentation-specific path prefix

## Navigation Model
- Documentation is traversed as a graph, not by numeric depth
- All reachable documentation pages within scope are included
- Pages are visited exactly once
- Only content-area links produce new traversal targets

## Snapshot Semantics
- All pages are downloaded and stored locally
- Original HTML is preserved verbatim
- Queries never touch the live web
