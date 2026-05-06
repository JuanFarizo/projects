# Core Design Principles

1. **Immutability by Default**  
All ingested documentation is immutable. Changes always create new snapshots.

2. **Filesystem as the Source of Truth**  
Raw and normalized content live on disk, not in databases or remote services.

3. **Explicit Knowledge Boundaries**  
Only content explicitly ingested can be queried.

4. **Structure-Preserving Normalization**  
Preserve headings, sections, and logical boundaries across formats.

5. **Incremental Expandability**  
New source types must be addable without redesigning existing components.

6. **Local-First Execution**  
All core flows must work fully offline.
