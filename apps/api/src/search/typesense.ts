import { pool } from '../db.js';

const TYPESENSE_API_KEY = process.env.TYPESENSE_API_KEY || '';
const TYPESENSE_HOST = process.env.TYPESENSE_HOST || 'localhost';
const TYPESENSE_PORT = process.env.TYPESENSE_PORT || 8108;
const TYPESENSE_URL = `http://${TYPESENSE_HOST}:${TYPESENSE_PORT}`;

const ALLOWED_FIELDS = ['type', 'tags', 'collectionId', 'collectionName', 'createdAt', 'updatedAt'] as const;
type AllowedField = typeof ALLOWED_FIELDS[number];

interface SearchDocument {
  id: string;
  type: string;
  tags: string[];
  collectionId: string | null;
  collectionName: string | null;
  createdAt: number;
  updatedAt: number;
}

async function typesenseRequest(path: string, method: string = 'GET', body?: object) {
  const res = await fetch(`${TYPESENSE_URL}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Typesense-Api-Key': TYPESENSE_API_KEY,
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    const error = await res.text();
    throw new Error(`Typesense error ${res.status}: ${error}`);
  }

  return res.json();
}

export async function initTypesenseCollection(): Promise<void> {
  try {
    await typesenseRequest('/collections/documents', 'GET');
  } catch {
    try {
      await typesenseRequest('/collections', 'POST', {
        name: 'documents',
        fields: [
          { name: 'id', type: 'string' },
          { name: 'type', type: 'string' },
          { name: 'tags', type: 'string[]' },
          { name: 'collectionId', type: 'string', optional: true },
          { name: 'collectionName', type: 'string', optional: true },
          { name: 'createdAt', type: 'int64' },
          { name: 'updatedAt', type: 'int64' },
        ],
        default_sorting_field: 'updatedAt',
      });
      console.log('Typesense collection created');
    } catch (e) {
      console.error('Failed to create Typesense collection:', e);
    }
  }
}

export async function indexDocument(doc: SearchDocument): Promise<void> {
  const docId = doc.id;
  const safeDoc: Record<string, unknown> = { id: docId };

  for (const field of ALLOWED_FIELDS) {
    if (field in doc) {
      safeDoc[field] = (doc as any)[field];
    }
  }

  try {
    await typesenseRequest('/collections/documents/documents', 'POST', safeDoc);
  } catch (e) {
    console.error('Failed to index document:', e);
  }
}

export async function updateDocumentIndex(docId: string, updates: Partial<SearchDocument>): Promise<void> {
  const safeUpdates: Record<string, unknown> = {};

  for (const field of ALLOWED_FIELDS) {
    if (field in updates) {
      safeUpdates[field] = (updates as any)[field];
    }
  }

  try {
    await typesenseRequest(`/collections/documents/documents/${docId}`, 'PATCH', safeUpdates);
  } catch (e) {
    console.error('Failed to update document index:', e);
  }
}

export async function removeFromIndex(docId: string): Promise<void> {
  try {
    await typesenseRequest(`/collections/documents/documents/${docId}`, 'DELETE');
  } catch (e) {
    console.error('Failed to remove document from index:', e);
  }
}

export async function searchDocuments(
  query: string,
  filters?: { field: AllowedField; value: string | number | boolean }[],
  limit: number = 20,
  offset: number = 0
): Promise<{ hits: SearchDocument[]; total: number }> {
  const filterParts = (filters || []).map(f => `${f.field}:=${f.value}`);
  const filterStr = filterParts.length > 0 ? filterParts.join(' && ') : undefined;

  try {
    const result = await typesenseRequest('/collections/documents/documents/search', 'POST', {
      q: query,
      query_by: 'type,tags,collectionName',
      filter_by: filterStr,
      limit,
      offset,
    });

    return {
      hits: (result.hits || []).map((h: any) => h.document as SearchDocument),
      total: result.found || 0,
    };
  } catch (e) {
    console.error('Typesense search error:', e);
    return { hits: [], total: 0 };
  }
}

export async function syncDocumentToTypesense(documentId: string): Promise<void> {
  try {
    const result = await pool.query(
      `SELECT d.id, d.type, d.created_at, d.updated_at,
              COALESCE(d.metadata->>'tags', '[]') as tags,
              d.collection_id,
              c.name as collection_name
       FROM documents d
       LEFT JOIN collections c ON d.collection_id = c.id
       WHERE d.id = $1 AND d.deleted_at IS NULL`,
      [documentId]
    );

    if (result.rows.length > 0) {
      const row = result.rows[0];
      await indexDocument({
        id: row.id as string,
        type: row.type as string,
        tags: JSON.parse(row.tags || '[]'),
        collectionId: row.collection_id,
        collectionName: row.collection_name,
        createdAt: new Date(row.created_at ?? Date.now()).getTime(),
        updatedAt: new Date(row.updated_at ?? Date.now()).getTime(),
      });
    }
  } catch (e) {
    console.error('Failed to sync document to Typesense:', e);
  }
}