# Query Units and Retrieval Model

## Atomic Query Unit
A **Query Unit** is a single logical section defined by:

- A heading
- All content associated with that heading
- Terminated by the next heading of the same level

## Chunk Constraints
- Oversized sections are subdivided internally
- Subdivision preserves ordering and local context
- Unrelated sections are never merged

## Grounding and Traceability
Each query unit retains:
- Source identifier
- Snapshot identifier
- Original resource reference
- Full section breadcrumb
- Relative ordering information
