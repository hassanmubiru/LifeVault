# LifeVault Architecture

## Components
1. Flutter Mobile App (local-first)
   - Import & document management
   - Local SQLite database
   - Local file storage (protected)
   - Local search index (FTS5)
   - Local encryption & key management
   - Sync client

2. StreetJS API Backend
   - Authentication & device management
   - Authorization
   - Encrypted document sync
   - PostgreSQL persistence
   - Private object storage
   - Sync recovery
   - Typesense integration (explicitly approved data only)

## Privacy Boundaries
- Local document search independent of cloud
- Document contents encrypted end-to-end
- Server stores only encrypted blobs and metadata
- Typesense only indexes explicitly approved, non-sensitive metadata
