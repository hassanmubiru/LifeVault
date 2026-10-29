# Local Search Strategy

## Implementation
- Use SQLite FTS5 for local full-text search (on-device)
- FTS5 is built into SQLite, works offline, fast, well-supported on mobile
- Indexes title and extracted_text
- Triggers keep FTS index in sync

## Why not Typesense for local?
- Typesense typically runs as a server - not ideal for fully local/offline on mobile
- FTS5 is embedded, no external process needed
- Better for privacy (data never leaves device)
- Lower resource usage

## Cloud Search (Typesense)
- Typesense will be used only for explicitly approved, non-sensitive metadata
- Never index private plaintext document contents by default
- Server-side access only with proper authz
