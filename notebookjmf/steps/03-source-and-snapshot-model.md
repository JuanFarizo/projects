# Source and Snapshot Model

## Source
A **Source** is a logical container representing a coherent body of documentation.

Examples:
- Obsidian Markdown Notes
- Spring Framework Official Documentation
- Mantine UI Documentation

A source is not an individual file or URL; it is a *conceptual boundary*.

## Snapshot
A **Snapshot** represents the full content of a source at a well-defined point in time.

Snapshot characteristics:
- Immutable
- Self-contained
- Fully reproducible
- Queryable independently from other snapshots

Any update to a source produces a new snapshot.
