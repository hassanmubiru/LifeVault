import crypto from 'node:crypto';
import { z } from 'zod';
import { pool } from '../db.js';
import { verifyToken, extractToken, uuidSchema } from '../auth/middleware.js';

const documentCreateSchema = z.object({
  title: z.string().min(1).max(512),
  type: z.string().min(1).max(64),
  mimeType: z.string().max(128).optional(),
  size: z.number().int().positive(),
  contentHash: z.string().min(64).max(64),
  collectionId: uuidSchema.optional(),
  tags: z.array(z.string().max(64)).max(20).optional(),
  metadata: z.record(z.unknown()).optional(),
});

const documentUpdateSchema = z.object({
  title: z.string().min(1).max(512).optional(),
  collectionId: uuidSchema.nullable().optional(),
  metadata: z.record(z.unknown()).optional(),
});

const tagCreateSchema = z.object({
  name: z.string().min(1).max(64),
});

const collectionCreateSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().max(1000).optional(),
});

async function authUser(ctx: any) {
  const token = extractToken(ctx.headers.authorization);
  if (!token) return null;
  return verifyToken(token);
}

export async function registerDocumentRoutes(app: any) {
  app.get('/documents', async (ctx: any) => {
    const payload = await authUser(ctx);
    if (!payload) return ctx.json({ error: 'Unauthorized' }, 401);

    const { userId } = payload;
    const { collectionId, tag, type, limit = 50, offset = 0 } = ctx.query;

    try {
      let query = `
        SELECT d.*,
          COALESCE(array_agg(DISTINCT t.name) FILTER (WHERE t.name IS NOT NULL), '{}') as tags,
          c.name as collection_name
        FROM documents d
        LEFT JOIN document_tags dt ON dt.document_id = d.id
        LEFT JOIN tags t ON t.id = dt.tag_id
        LEFT JOIN collections c ON c.id = d.collection_id
        WHERE d.user_id = $1 AND d.deleted_at IS NULL
      `;
      const params: any[] = [userId];
      let paramIndex = 2;

      if (collectionId) {
        query += ` AND d.collection_id = $${paramIndex++}`;
        params.push(collectionId);
      }

      if (tag) {
        query += ` AND t.name = $${paramIndex++}`;
        params.push(tag);
      }

      if (type) {
        query += ` AND d.type = $${paramIndex++}`;
        params.push(type);
      }

      query += ` GROUP BY d.id, c.name ORDER BY d.created_at DESC LIMIT $${paramIndex++} OFFSET $${paramIndex}`;
      params.push(Number(limit), Number(offset));

      const result = await pool.query(query, params);

      return ctx.json({ documents: result.rows });
    } catch (err: any) {
      console.error('Get documents error:', err.message);
      return ctx.json({ error: 'Failed to get documents' }, 500);
    }
  });

  app.get('/documents/:id', async (ctx: any) => {
    const payload = await authUser(ctx);
    if (!payload) return ctx.json({ error: 'Unauthorized' }, 401);

    const { userId } = payload;
    const { id } = ctx.params;

    try {
      const result = await pool.query(
        `SELECT d.*,
          COALESCE(array_agg(DISTINCT t.name) FILTER (WHERE t.name IS NOT NULL), '{}') as tags,
          c.name as collection_name
        FROM documents d
        LEFT JOIN document_tags dt ON dt.document_id = d.id
        LEFT JOIN tags t ON t.id = dt.tag_id
        LEFT JOIN collections c ON c.id = d.collection_id
        WHERE d.id = $1 AND d.user_id = $2 AND d.deleted_at IS NULL
        GROUP BY d.id, c.name`,
        [id, userId]
      );

      if (result.rows.length === 0) {
        return ctx.json({ error: 'Document not found' }, 404);
      }

      return ctx.json({ document: result.rows[0] });
    } catch (err: any) {
      console.error('Get document error:', err.message);
      return ctx.json({ error: 'Failed to get document' }, 500);
    }
  });

  app.post('/documents', async (ctx: any) => {
    const payload = await authUser(ctx);
    if (!payload) return ctx.json({ error: 'Unauthorized' }, 401);

    const { userId, deviceId } = payload;
    const parsed = documentCreateSchema.safeParse(ctx.body);
    if (!parsed.success) {
      return ctx.json({ error: 'Invalid input', details: parsed.error.errors }, 400);
    }

    const { title, type, mimeType, size, contentHash, collectionId, tags, metadata } = parsed.data;
    const docId = crypto.randomUUID();
    const now = new Date().toISOString();

    try {
      if (collectionId) {
        const colCheck = await pool.query(
          'SELECT id FROM collections WHERE id = $1 AND user_id = $2',
          [collectionId, userId]
        );
        if (colCheck.rows.length === 0) {
          return ctx.json({ error: 'Collection not found' }, 404);
        }
      }

      const docResult = await pool.query(
        `INSERT INTO documents (id, user_id, device_id, title, type, mime_type, size, content_hash, collection_id, metadata, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
         RETURNING *`,
        [docId, userId, deviceId, title, type, mimeType, size, contentHash, collectionId, JSON.stringify(metadata || {}), now, now]
      );

      if (tags && tags.length > 0) {
        for (const tagName of tags) {
          let tagId;
          const existingTag = await pool.query(
            'SELECT id FROM tags WHERE user_id = $1 AND name = $2',
            [userId, tagName]
          );

          if (existingTag.rows.length > 0) {
            tagId = existingTag.rows[0].id;
          } else {
            tagId = crypto.randomUUID();
            await pool.query(
              'INSERT INTO tags (id, user_id, name, created_at) VALUES ($1, $2, $3, $4)',
              [tagId, userId, tagName, now]
            );
          }

          await pool.query(
            'INSERT INTO document_tags (document_id, tag_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
            [docId, tagId]
          );
        }
      }

      return ctx.json({ document: docResult.rows[0] }, 201);
    } catch (err: any) {
      console.error('Create document error:', err.message);
      return ctx.json({ error: 'Failed to create document' }, 500);
    }
  });

  app.patch('/documents/:id', async (ctx: any) => {
    const payload = await authUser(ctx);
    if (!payload) return ctx.json({ error: 'Unauthorized' }, 401);

    const { userId } = payload;
    const { id } = ctx.params;
    const parsed = documentUpdateSchema.safeParse(ctx.body);
    if (!parsed.success) {
      return ctx.json({ error: 'Invalid input', details: parsed.error.errors }, 400);
    }

    const updates: string[] = [];
    const values: any[] = [];
    let paramIndex = 1;

    const { title, collectionId, metadata } = parsed.data;

    if (title !== undefined) {
      updates.push(`title = $${paramIndex++}`);
      values.push(title);
    }

    if (collectionId !== undefined) {
      updates.push(`collection_id = $${paramIndex++}`);
      values.push(collectionId);
    }

    if (metadata !== undefined) {
      updates.push(`metadata = $${paramIndex++}`);
      values.push(JSON.stringify(metadata));
    }

    if (updates.length === 0) {
      return ctx.json({ error: 'No updates provided' }, 400);
    }

    updates.push(`updated_at = $${paramIndex++}`);
    values.push(new Date().toISOString());
    values.push(id);
    values.push(userId);

    try {
      const result = await pool.query(
        `UPDATE documents SET ${updates.join(', ')}
         WHERE id = $${paramIndex++} AND user_id = $${paramIndex} AND deleted_at IS NULL
         RETURNING *`,
        values
      );

      if (result.rows.length === 0) {
        return ctx.json({ error: 'Document not found' }, 404);
      }

      return ctx.json({ document: result.rows[0] });
    } catch (err: any) {
      console.error('Update document error:', err.message);
      return ctx.json({ error: 'Failed to update document' }, 500);
    }
  });

  app.delete('/documents/:id', async (ctx: any) => {
    const payload = await authUser(ctx);
    if (!payload) return ctx.json({ error: 'Unauthorized' }, 401);

    const { userId } = payload;
    const { id } = ctx.params;

    try {
      const now = new Date().toISOString();

      const result = await pool.query(
        `UPDATE documents SET deleted_at = $1, updated_at = $1
         WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL
         RETURNING id`,
        [now, id, userId]
      );

      if (result.rows.length === 0) {
        return ctx.json({ error: 'Document not found' }, 404);
      }

      await pool.query(
        'INSERT INTO sync_tombstones (id, user_id, document_id, deleted_at) VALUES ($1, $2, $3, $4)',
        [crypto.randomUUID(), userId, id, now]
      );

      return ctx.json({ success: true });
    } catch (err: any) {
      console.error('Delete document error:', err.message);
      return ctx.json({ error: 'Failed to delete document' }, 500);
    }
  });

  app.get('/collections', async (ctx: any) => {
    const payload = await authUser(ctx);
    if (!payload) return ctx.json({ error: 'Unauthorized' }, 401);

    const { userId } = payload;

    try {
      const result = await pool.query(
        'SELECT * FROM collections WHERE user_id = $1 ORDER BY name',
        [userId]
      );
      return ctx.json({ collections: result.rows });
    } catch (err: any) {
      console.error('Get collections error:', err.message);
      return ctx.json({ error: 'Failed to get collections' }, 500);
    }
  });

  app.post('/collections', async (ctx: any) => {
    const payload = await authUser(ctx);
    if (!payload) return ctx.json({ error: 'Unauthorized' }, 401);

    const { userId } = payload;
    const parsed = collectionCreateSchema.safeParse(ctx.body);
    if (!parsed.success) {
      return ctx.json({ error: 'Invalid input', details: parsed.error.errors }, 400);
    }

    const { name, description } = parsed.data;
    const collectionId = crypto.randomUUID();
    const now = new Date().toISOString();

    try {
      const result = await pool.query(
        `INSERT INTO collections (id, user_id, name, description, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [collectionId, userId, name, description || null, now, now]
      );
      return ctx.json({ collection: result.rows[0] }, 201);
    } catch (err: any) {
      console.error('Create collection error:', err.message);
      return ctx.json({ error: 'Failed to create collection' }, 500);
    }
  });

  app.get('/tags', async (ctx: any) => {
    const payload = await authUser(ctx);
    if (!payload) return ctx.json({ error: 'Unauthorized' }, 401);

    const { userId } = payload;

    try {
      const result = await pool.query(
        'SELECT * FROM tags WHERE user_id = $1 ORDER BY name',
        [userId]
      );
      return ctx.json({ tags: result.rows });
    } catch (err: any) {
      console.error('Get tags error:', err.message);
      return ctx.json({ error: 'Failed to get tags' }, 500);
    }
  });

  app.post('/tags', async (ctx: any) => {
    const payload = await authUser(ctx);
    if (!payload) return ctx.json({ error: 'Unauthorized' }, 401);

    const { userId } = payload;
    const parsed = tagCreateSchema.safeParse(ctx.body);
    if (!parsed.success) {
      return ctx.json({ error: 'Invalid input', details: parsed.error.errors }, 400);
    }

    const { name } = parsed.data;
    const tagId = crypto.randomUUID();
    const now = new Date().toISOString();

    try {
      const result = await pool.query(
        `INSERT INTO tags (id, user_id, name, created_at)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, name) DO UPDATE SET name = EXCLUDED.name
         RETURNING *`,
        [tagId, userId, name, now]
      );
      return ctx.json({ tag: result.rows[0] }, 201);
    } catch (err: any) {
      console.error('Create tag error:', err.message);
      return ctx.json({ error: 'Failed to create tag' }, 500);
    }
  });
}
