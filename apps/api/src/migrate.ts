import { connectDb, pool } from './db.js';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function migrate() {
  await connectDb();
  const migrationsDir = path.join(__dirname, '../migrations');
  const files = (await fs.readdir(migrationsDir)).filter((f: string) => f.endsWith('.sql')).sort();
  for (const file of files) {
    const sql = await fs.readFile(path.join(migrationsDir, file), 'utf-8');
    console.log(`Running migration ${file}`);
    await pool.query(sql);
  }
  console.log('Migrations complete');
}

migrate().catch((e: any) => {
  console.error(e);
  process.exit(1);
});
