/**
 * Encrypted Synchronization Protocol
 * 
 * - Device identity & registration
 * - Encrypted payloads (end-to-end)
 * - Integrity verification
 * - Idempotent operations
 * - Versioning & conflict resolution
 * - Tombstones for deletions
 * - Resume/retry on interruption
 */
export interface SyncMessage {
  id: string;
  deviceId: string;
  userId: string;
  type: 'upload' | 'download' | 'delete' | 'sync_request';
  version: number;
  timestamp: number;
  payload: string; // encrypted
  signature?: string;
}

export interface SyncConflict {
  documentId: string;
  localVersion: number;
  remoteVersion: number;
  resolution: 'local' | 'remote' | 'merge' | 'manual';
}
