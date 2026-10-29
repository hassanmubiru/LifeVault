import crypto from 'node:crypto';
import { pool } from '../db.js';

const MAX_RETRIES = 5;
const RETRY_DELAYS = [1000, 5000, 15000, 30000, 60000];

interface SyncQueueItem {
  id: string;
  user_id: string;
  device_id: string | null;
  operation: string;
  document_id: string | null;
  payload: any;
  retry_count: number;
}

async function processUpload(payload: any, userId: string, deviceId: string): Promise<boolean> {
  console.log(`Processing upload for user ${userId}, device ${deviceId}`);
  return true;
}

async function processDownload(documentId: string, userId: string): Promise<any> {
  console.log(`Processing download for document ${documentId}, user ${userId}`);
  return null;
}

async function processDelete(documentId: string, userId: string): Promise<boolean> {
  try {
    const result = await pool.query(
      `UPDATE documents SET deleted_at = $1, updated_at = $1
       WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL
       RETURNING id`,
      [new Date().toISOString(), documentId, userId]
    );
    return result.rows.length > 0;
  } catch (err) {
    console.error('Delete sync error:', err);
    return false;
  }
}

export async function processNextSyncItem(): Promise<{ processed: number; failed: number }> {
  const result = { processed: 0, failed: 0 };

  try {
    const itemResult = await pool.query(
      `SELECT * FROM sync_queue
       WHERE status = 'pending'
       ORDER BY created_at ASC
       LIMIT 1
       FOR UPDATE SKIP LOCKED`,
      []
    );

    if (itemResult.rows.length === 0) {
      return result;
    }

    const item = itemResult.rows[0] as unknown as SyncQueueItem;

    await pool.query(
      `UPDATE sync_queue SET status = 'processing' WHERE id = $1`,
      [item.id]
    );

    try {
      let success = false;

      switch (item.operation) {
        case 'upload':
          success = await processUpload(item.payload, item.user_id, item.device_id || '');
          break;
        case 'download':
          success = await processDownload(item.document_id || '', item.user_id) !== null;
          break;
        case 'delete':
          success = await processDelete(item.document_id || '', item.user_id);
          break;
        default:
          console.error(`Unknown sync operation: ${item.operation}`);
          success = false;
      }

      if (success) {
        await pool.query(
          `UPDATE sync_queue SET status = 'completed', processed_at = $1 WHERE id = $2`,
          [new Date().toISOString(), item.id]
        );
        result.processed++;
      } else {
        throw new Error(`Operation ${item.operation} failed`);
      }
    } catch (err: any) {
      const newRetryCount = item.retry_count + 1;

      if (newRetryCount >= MAX_RETRIES) {
        await pool.query(
          `UPDATE sync_queue SET status = 'failed', retry_count = $1 WHERE id = $2`,
          [newRetryCount, item.id]
        );
        result.failed++;
      } else {
        const delay = RETRY_DELAYS[Math.min(newRetryCount - 1, RETRY_DELAYS.length - 1)];
        const nextAttempt = new Date(Date.now() + delay).toISOString();

        await pool.query(
          `UPDATE sync_queue
           SET status = 'pending', retry_count = $1,
               payload = jsonb_set(payload, '{nextAttempt}', $2)
           WHERE id = $3`,
          [newRetryCount, JSON.stringify(nextAttempt), item.id]
        );
      }
    }
  } catch (err) {
    console.error('Sync queue processing error:', err);
  }

  return result;
}

export async function processSyncQueue(limit: number = 10): Promise<{ processed: number; failed: number }> {
  const result = { processed: 0, failed: 0 };

  for (let i = 0; i < limit; i++) {
    const itemResult = await processNextSyncItem();
    result.processed += itemResult.processed;
    result.failed += itemResult.failed;

    if (itemResult.processed === 0 && itemResult.failed === 0) {
      break;
    }
  }

  return result;
}

export async function getSyncStatus(userId: string, deviceId: string) {
  try {
    const pendingResult = await pool.query(
      `SELECT COUNT(*) as pending FROM sync_queue
       WHERE user_id = $1 AND device_id = $2 AND status = 'pending'`,
      [userId, deviceId]
    );

    const failedResult = await pool.query(
      `SELECT COUNT(*) as failed FROM sync_queue
       WHERE user_id = $1 AND device_id = $2 AND status = 'failed'`,
      [userId, deviceId]
    );

    const sessionResult = await pool.query(
      `SELECT * FROM sync_sessions
       WHERE user_id = $1 AND device_id = $2 AND status = 'active'
       ORDER BY created_at DESC LIMIT 1`,
      [userId, deviceId]
    );

    return {
      pending: parseInt(pendingResult.rows[0]?.pending || '0'),
      failed: parseInt(failedResult.rows[0]?.failed || '0'),
      lastSync: sessionResult.rows[0]?.last_sync_at || null,
    };
  } catch (err) {
    console.error('Get sync status error:', err);
    throw err;
  }
}

export async function createSyncSession(userId: string, deviceId: string) {
  const sessionId = crypto.randomUUID();
  const now = new Date().toISOString();

  await pool.query(
    `INSERT INTO sync_sessions (id, user_id, device_id, status, last_sync_at, created_at)
     VALUES ($1, $2, $3, 'active', $4, $4)`,
    [sessionId, userId, deviceId, now]
  );

  return sessionId;
}