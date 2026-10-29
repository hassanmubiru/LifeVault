import crypto from 'node:crypto';
import { pool } from '../db.js';
const MAX_RETRIES = 5;
const RETRY_DELAYS = [1000, 5000, 15000, 30000, 60000];
const STORAGE_PATH = process.env.DOCUMENT_STORAGE_PATH || '/tmp/lifevault_docs';
function deriveKey(password, salt) {
    return crypto.pbkdf2Sync(password, salt, 100000, 32, 'sha512');
}
async function ensureStorageDir(userId) {
    const fs = await import('fs/promises');
    const storageDir = `${STORAGE_PATH}/${userId}`;
    try {
        await fs.mkdir(storageDir, { recursive: true });
    }
    catch { }
    return storageDir;
}
async function processUpload(payload, userId, deviceId) {
    try {
        const { documentId, encryptedData, iv, authTag, contentHash, salt } = payload;
        const dataBuffer = Buffer.from(encryptedData, 'base64');
        const ivBuffer = Buffer.from(iv, 'base64');
        const authTagBuffer = Buffer.from(authTag, 'base64');
        const saltBuffer = Buffer.from(salt, 'base64');
        const key = deriveKey(documentId, saltBuffer);
        const storageDir = await ensureStorageDir(userId);
        const filePath = `${storageDir}/${documentId}.enc`;
        const metaPath = `${storageDir}/${documentId}.meta`;
        const fs = await import('fs/promises');
        const encrypted = Buffer.concat([ivBuffer, authTagBuffer, dataBuffer]);
        await fs.writeFile(filePath, encrypted);
        await fs.writeFile(metaPath, JSON.stringify({
            salt,
            contentHash,
            uploadedAt: new Date().toISOString(),
            deviceId,
        }));
        await pool.query(`UPDATE documents SET synced = true, storage_path = $1, updated_at = $2
       WHERE id = $3 AND user_id = $4`, [filePath, new Date().toISOString(), documentId, userId]);
        console.log(`Upload processed for document ${documentId}, user ${userId}`);
        return true;
    }
    catch (err) {
        console.error('Upload process error:', err);
        return false;
    }
}
async function processDownload(documentId, userId) {
    try {
        const storageDir = `${STORAGE_PATH}/${userId}`;
        const filePath = `${storageDir}/${documentId}.enc`;
        const metaPath = `${storageDir}/${documentId}.meta`;
        const fs = await import('fs/promises');
        const metaData = JSON.parse(await fs.readFile(metaPath, 'utf-8'));
        const fileData = await fs.readFile(filePath);
        const saltBuffer = Buffer.from(metaData.salt, 'base64');
        const key = deriveKey(documentId, saltBuffer);
        const ivFromFile = fileData.subarray(0, 12);
        const authTagFromFile = fileData.subarray(12, 28);
        const encryptedData = fileData.subarray(28);
        const decipher = crypto.createDecipheriv('aes-256-gcm', key, ivFromFile);
        decipher.setAuthTag(authTagFromFile);
        const decrypted = Buffer.concat([decipher.update(encryptedData), decipher.final()]);
        console.log(`Download processed for document ${documentId}, user ${userId}`);
        return {
            encryptedData: decrypted.toString('base64'),
            iv: ivFromFile.toString('base64'),
            authTag: authTagFromFile.toString('base64'),
            contentHash: metaData.contentHash,
        };
    }
    catch (err) {
        console.error('Download process error:', err);
        return null;
    }
}
async function processDelete(documentId, userId) {
    try {
        const result = await pool.query(`UPDATE documents SET deleted_at = $1, updated_at = $1
       WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL
       RETURNING id`, [new Date().toISOString(), documentId, userId]);
        return result.rows.length > 0;
    }
    catch (err) {
        console.error('Delete sync error:', err);
        return false;
    }
}
export async function processNextSyncItem() {
    const result = { processed: 0, failed: 0 };
    try {
        const itemResult = await pool.query(`SELECT * FROM sync_queue
       WHERE status = 'pending'
       ORDER BY created_at ASC
       LIMIT 1
       FOR UPDATE SKIP LOCKED`, []);
        if (itemResult.rows.length === 0) {
            return result;
        }
        const item = itemResult.rows[0];
        await pool.query(`UPDATE sync_queue SET status = 'processing' WHERE id = $1`, [item.id]);
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
                await pool.query(`UPDATE sync_queue SET status = 'completed', processed_at = $1 WHERE id = $2`, [new Date().toISOString(), item.id]);
                result.processed++;
            }
            else {
                throw new Error(`Operation ${item.operation} failed`);
            }
        }
        catch (err) {
            const newRetryCount = item.retry_count + 1;
            if (newRetryCount >= MAX_RETRIES) {
                await pool.query(`UPDATE sync_queue SET status = 'failed', retry_count = $1 WHERE id = $2`, [newRetryCount, item.id]);
                result.failed++;
            }
            else {
                const delay = RETRY_DELAYS[Math.min(newRetryCount - 1, RETRY_DELAYS.length - 1)];
                const nextAttempt = new Date(Date.now() + delay).toISOString();
                await pool.query(`UPDATE sync_queue
           SET status = 'pending', retry_count = $1,
               payload = jsonb_set(payload, '{nextAttempt}', $2)
           WHERE id = $3`, [newRetryCount, JSON.stringify(nextAttempt), item.id]);
            }
        }
    }
    catch (err) {
        console.error('Sync queue processing error:', err);
    }
    return result;
}
export async function processSyncQueue(limit = 10) {
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
export async function getSyncStatus(userId, deviceId) {
    try {
        const pendingResult = await pool.query(`SELECT COUNT(*) as pending FROM sync_queue
       WHERE user_id = $1 AND device_id = $2 AND status = 'pending'`, [userId, deviceId]);
        const failedResult = await pool.query(`SELECT COUNT(*) as failed FROM sync_queue
       WHERE user_id = $1 AND device_id = $2 AND status = 'failed'`, [userId, deviceId]);
        const sessionResult = await pool.query(`SELECT * FROM sync_sessions
       WHERE user_id = $1 AND device_id = $2 AND status = 'active'
       ORDER BY created_at DESC LIMIT 1`, [userId, deviceId]);
        return {
            pending: parseInt(pendingResult.rows[0]?.pending || '0'),
            failed: parseInt(failedResult.rows[0]?.failed || '0'),
            lastSync: sessionResult.rows[0]?.last_sync_at || null,
        };
    }
    catch (err) {
        console.error('Get sync status error:', err);
        throw err;
    }
}
export async function createSyncSession(userId, deviceId) {
    const sessionId = crypto.randomUUID();
    const now = new Date().toISOString();
    await pool.query(`INSERT INTO sync_sessions (id, user_id, device_id, status, last_sync_at, created_at)
     VALUES ($1, $2, $3, 'active', $4, $4)`, [sessionId, userId, deviceId, now]);
    return sessionId;
}
