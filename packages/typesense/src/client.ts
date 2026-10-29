import crypto from 'node:crypto';

const ALLOWED_FIELDS = ['type', 'tags', 'collectionId', 'collectionName', 'createdAt', 'updatedAt'] as const;
type AllowedField = typeof ALLOWED_FIELDS[number];

interface IndexedDocument {
  id: string;
  userId: string;
  [key: string]: any;
}

export class LifeVaultTypesenseClient {
  private apiKey: string;
  private host: string;
  private protocol: string;
  private port: number;

  constructor(apiKey: string, host: string) {
    this.apiKey = apiKey;
    const url = new URL(host.startsWith('http') ? host : `http://${host}`);
    this.protocol = url.protocol.replace(':', '');
    this.host = url.hostname;
    this.port = parseInt(url.port) || (this.protocol === 'https' ? 443 : 8108);
  }

  private async request<T>(path: string, method: string, body?: any): Promise<T> {
    const url = `${this.protocol}://${this.host}:${this.port}${path}`;
    const headers: Record<string, string> = {
      'X-Typesense-Api-Key': this.apiKey,
      'Content-Type': 'application/json',
    };

    const options: RequestInit = {
      method,
      headers,
    };

    if (body) {
      options.body = JSON.stringify(body);
    }

    const response = await fetch(url, options);
    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Typesense request failed: ${response.status} ${errorText}`);
    }

    return response.json() as Promise<T>;
  }

  private filterAllowedFields(data: Record<string, any>): Record<string, any> {
    const filtered: Record<string, any> = {};
    for (const key of ALLOWED_FIELDS) {
      if (key in data) {
        filtered[key] = data[key];
      }
    }
    return filtered;
  }

  async createCollection(name: string, fields: Array<{ name: string; type: string }>): Promise<any> {
    return this.request(`/collections/${name}`, 'PUT', {
      name,
      fields,
      default_sorting_field: 'createdAt',
    });
  }

  async indexApprovedMetadata(data: IndexedDocument): Promise<any> {
    const safeData = this.filterAllowedFields(data);
    const safeId = `${data.userId}_${data.id}`;

    return this.request(`/collections/documents/documents`, 'POST', {
      ...safeData,
      id: safeId,
      userId: data.userId,
    });
  }

  async search(query: string, userId: string, options?: {
    limit?: number;
    offset?: number;
    filterBy?: string;
    sortBy?: string;
  }): Promise<any> {
    const filterBy = options?.filterBy || `userId:=${userId}`;
    return this.request('/collections/documents/documents/search', 'POST', {
      q: query,
      filter_by: filterBy,
      limit: options?.limit || 20,
      offset: options?.offset || 0,
      sort_by: options?.sortBy || 'createdAt:desc',
    });
  }

  async deleteDocument(documentId: string, userId: string): Promise<any> {
    const safeId = `${userId}_${documentId}`;
    return this.request(`/collections/documents/documents/${safeId}`, 'DELETE');
  }

  async healthCheck(): Promise<boolean> {
    try {
      await this.request('/health', 'GET');
      return true;
    } catch {
      return false;
    }
  }
}

export function createTypesenseClient(): LifeVaultTypesenseClient | null {
  const apiKey = process.env.TYPESENSE_API_KEY;
  const host = process.env.TYPESENSE_HOST;

  if (!apiKey || !host) {
    console.warn('Typesense not configured - skipping cloud search');
    return null;
  }

  return new LifeVaultTypesenseClient(apiKey, host);
}
