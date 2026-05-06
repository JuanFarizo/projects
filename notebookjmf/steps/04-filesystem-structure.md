# Filesystem Structure

## Layout Responsibilities

- Each source has its own directory
- Each snapshot has a dedicated subdirectory
- Raw and normalized content are strictly separated

## Design Intent
- Debuggability
- Auditable history
- Easy backup and migration

Indexes are treated as **ephemeral artifacts** and may be safely recreated.
