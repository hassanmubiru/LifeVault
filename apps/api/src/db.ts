import { PgPool } from 'streetjs';

export const pool = new PgPool({
  host: process.env.PG_HOST ?? 'localhost',
  port: Number(process.env.PG_PORT ?? 5432),
  user: process.env.PG_USER ?? 'postgres',
  password: process.env.PG_PASSWORD ?? 'postgres',
  database: process.env.PG_DATABASE ?? 'lifevault',
  minConnections: 1,
  maxConnections: 10,
  idleTimeoutMs: 30_000,
  acquireTimeoutMs: 5_000,
});

export async function connectDb(): Promise<void> {
  await pool.initialize();
}
