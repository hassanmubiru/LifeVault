import crypto from 'node:crypto';
import { pool } from '../db.js';
import { verifyToken, extractToken } from '../auth/middleware.js';
import { syncDocumentToTypesense } from '../search/typesense.js';

const STORAGE_PATH = process.env.DOCUMENT_STORAGE_PATH || '/tmp/lifevault_docs';
const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB

async function ensureStorageDir() {
  const fs = await import('fs/promises');
  try {
    await fs.mkdir(STORAGE_PATH, { recursive: true });
  } catch {}
}

function encryptBuffer(data: Buffer, key: Buffer): { encrypted: Buffer; iv: Buffer; authTag: Buffer } {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(data), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return { encrypted, iv, authTag };
}

function decryptBuffer(encrypted: Buffer, key: Buffer, iv: Buffer, authTag: Buffer): Buffer {
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]);
}

function deriveKey(password: string, salt: Buffer): Buffer {
  return crypto.pbkdf2Sync(password, salt, 100000, 32, 'sha512');
}

export async function registerSyncRoutes(app: any) {
  await ensureStorageDir();

  app.get('/sync/status', async (ctx: any) => {
    const token = extractToken(ctx.headers.authorization);
    if (!token) return ctx.json({ error: 'Unauthorized' }, 401);

    const payload = verifyToken(token);
    if (!payload) return ctx.json({ error: 'Invalid token' }, 401);

    const { userId, deviceId } = payload;

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

      return ctx.json({
        pending: parseInt(pendingResult.rows[0]?.pending || '0'),
        failed: parseInt(failedResult.rows[0]?.failed || '0'),
        lastSync: sessionResult.rows[0]?.last_sync_at || null,
        serverTime: new Date().toISOString(),
      });
    } catch (err: any) {
      console.error('Get sync status error:', err.message);
      return ctx.json({ error: 'Failed to get sync status' }, 500);
    }
  });

  app.post('/sync/upload', async (ctx: any) => {
    const token = extractToken(ctx.headers.authorization);
    if (!token) return ctx.json({ error: 'Unauthorized' }, 401);

    const payload = verifyToken(token);
    if (!payload) return ctx.json({ error: 'Invalid token' }, 401);

    const { userId, deviceId } = payload;

    try {
      const body = ctx.body;
      const { documentId, encryptedData, iv, authTag, contentHash } = body;

      if (!documentId || !encryptedData || !iv || !authTag) {
        return ctx.json({ error: 'Missing required fields' }, 400);
      }

      const dataBuffer = Buffer.from(encryptedData, 'base64');
      if (dataBuffer.length > MAX_FILE_SIZE) {
        return ctx.json({ error: 'File too large' }, 413);
      }

      const salt = crypto.randomBytes(16);
      const key = deriveKey(documentId, salt);

      const { encrypted, iv: newIv, authTag: newAuthTag } = encryptBuffer(dataBuffer, key);

      const storageDir = `${STORAGE_PATH}/${userId}`;
      await ensureStorageDir();

      const fs = await import('fs/promises');
      await fs.mkdir(storageDir, { recursive: true });

      const filePath = `${storageDir}/${documentId}.enc`;
      const metaPath = `${storageDir}/${documentId}.meta`;

      await fs.writeFile(filePath, Buffer.concat([newIv, newAuthTag, encrypted]));
      await fs.writeFile(metaPath, JSON.stringify({
        salt: salt.toString('base64'),
        contentHash,
        uploadedAt: new Date().toISOString(),
        deviceId,
      }));

      const now = new Date().toISOString();
      await pool.query(
        `INSERT INTO sync_queue (id, user_id, device_id, operation, document_id, payload, status, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, 'completed', $7)`,
        [crypto.randomUUID(), userId, deviceId, 'upload', documentId, JSON.stringify({ filePath, contentHash }), now]
      );

      syncDocumentToTypesense(documentId).catch(err => {
        console.error('Typesense sync failed:', err);
      });

      return ctx.json({
        success: true,
        documentId,
        storagePath: filePath,
      });
    } catch (err: any) {
      console.error('Sync upload error:', err.message);
      return ctx.json({ error: 'Upload failed' }, 500);
    }
  });

  app.get('/sync/download/:documentId', async (ctx: any) => {
    const token = extractToken(ctx.headers.authorization);
    if (!token) return ctx.json({ error: 'Unauthorized' }, 401);

    const payload = verifyToken(token);
    if (!payload) return ctx.json({ error: 'Invalid token' }, 401);

    const { userId } = payload;
    const { documentId } = ctx.params;

    try {
      const storageDir = `${STORAGE_PATH}/${userId}`;
      const filePath = `${storageDir}/${documentId}.enc`;
      const metaPath = `${storageDir}/${documentId}.meta`;

      const fs = await import('fs/promises');

      try {
        const metaData = JSON.parse(await fs.readFile(metaPath, 'utf-8'));
        const fileData = await fs.readFile(filePath);

        const saltBuffer = Buffer.from(metaData.salt, 'base64');
        const key = deriveKey(documentId, saltBuffer);

        const ivFromFile = fileData.subarray(0, 12);
        const authTagFromFile = fileData.subarray(12, 28);
        const encryptedData = fileData.subarray(28);

        const decrypted = decryptBuffer(encryptedData, key, ivFromFile, authTagFromFile);

        return ctx.json({
          documentId,
          encryptedData: decrypted.toString('base64'),
          iv: ivFromFile.toString('base64'),
          authTag: authTagFromFile.toString('base64'),
          contentHash: metaData.contentHash,
        });
      } catch {
        return ctx.json({ error: 'Document not found' }, 404);
      }
    } catch (err: any) {
      console.error('Sync download error:', err.message);
      return ctx.json({ error: 'Download failed' }, 500);
    }
  });

  app.delete('/sync/document/:documentId', async (ctx: any) => {
    const token = extractToken(ctx.headers.authorization);
    if (!token) return ctx.json({ error: 'Unauthorized' }, 401);

    const payload = verifyToken(token);
    if (!payload) return ctx.json({ error: 'Invalid token' }, 401);

    const { userId } = payload;
    const { documentId } = ctx.params;

    try {
      const storageDir = `${STORAGE_PATH}/${userId}`;
      const filePath = `${storageDir}/${documentId}.enc`;
      const metaPath = `${storageDir}/${documentId}.meta`;

      const fs = await import('fs/promises');

      try {
        await fs.unlink(filePath);
        await fs.unlink(metaPath);
      } catch {}

      await pool.query(
        `INSERT INTO sync_tombstones (id, user_id, document_id, deleted_at)
         VALUES ($1, $2, $3, $4)`,
        [crypto.randomUUID(), userId, documentId, new Date().toISOString()]
      );

      return ctx.json({ success: true });
    } catch (err: any) {
      console.error('Sync delete error:', err.message);
      return ctx.json({ error: 'Delete failed' }, 500);
    }
  });

  app.get('/sync/queue', async (ctx: any) => {
    const token = extractToken(ctx.headers.authorization);
    if (!token) return ctx.json({ error: 'Unauthorized' }, 401);

    const payload = verifyToken(token);
    if (!payload) return ctx.json({ error: 'Invalid token' }, 401);

    const { userId, deviceId } = payload;
    const { limit = 50, offset = 0 } = ctx.query;

    try {
      const result = await pool.query(
        `SELECT id, operation, document_id, payload, status, retry_count, created_at
         FROM sync_queue
         WHERE user_id = $1 AND device_id = $2
         ORDER BY created_at DESC
         LIMIT $3 OFFSET $4`,
        [userId, deviceId, Number(limit), Number(offset)]
      );

      return ctx.json({ queue: result.rows });
    } catch (err: any) {
      console.error('Get sync queue error:', err.message);
      return ctx.json({ error: 'Failed to get queue' }, 500);
    }
  });

  app.post('/sync/process', async (ctx: any) => {
    const token = extractToken(ctx.headers.authorization);
    if (!token) return ctx.json({ error: 'Unauthorized' }, 401);

    const payload = verifyToken(token);
    if (!payload) return ctx.json({ error: 'Invalid token' }, 401);

    const { userId, deviceId } = payload;

    try {
      let processed = 0;
      let failed = 0;

      for (let i = 0; i < 10; i++) {
        const itemResult = await pool.query(
          `SELECT * FROM sync_queue
           WHERE user_id = $1 AND device_id = $2 AND status = 'pending'
           ORDER BY created_at ASC
           LIMIT 1
           FOR UPDATE SKIP LOCKED`,
          [userId, deviceId]
        );

        if (itemResult.rows.length === 0) break;

        const item = itemResult.rows[0];

        await pool.query(
          `UPDATE sync_queue SET status = 'processing' WHERE id = $1`,
          [item.id]
        );

        try {
          const op = item.operation;
          let success = false;

          if (op === 'upload' || op === 'download' || op === 'delete') {
            success = true;
          }

          if (success) {
            await pool.query(
              `UPDATE sync_queue SET status = 'completed', processed_at = $1 WHERE id = $2`,
              [new Date().toISOString(), item.id]
            );
            processed++;
          } else {
            throw new Error(`Operation ${op} failed`);
          }
        } catch (err: any) {
          const newRetry = (item.retry_count ?? 0) + 1;
          if (newRetry >= 5) {
            await pool.query(
              `UPDATE sync_queue SET status = 'failed', retry_count = $1 WHERE id = $2`,
              [newRetry, item.id]
            );
            failed++;
          } else {
            await pool.query(
              `UPDATE sync_queue SET status = 'pending', retry_count = $1 WHERE id = $2`,
              [newRetry, item.id]
            );
          }
        }
      }

      return ctx.json({ processed, failed });
    } catch (err: any) {
      console.error('Sync process error:', err.message);
      return ctx.json({ error: 'Process failed' }, 500);
    }
  });
}
