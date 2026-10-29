export interface User {
  id: string;
  email: string;
}

export interface Device {
  id: string;
  userId: string;
  name: string;
  lastSeenAt: string;
  revokedAt?: string;
}

export interface Document {
  id: string;
  userId: string;
  title: string;
  type: string;
  size: number;
  hash: string;
  createdAt: string;
  updatedAt: string;
  tags?: string[];
  collectionId?: string;
}
