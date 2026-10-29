import 'reflect-metadata';
import { streetApp } from 'streetjs';
import { pool, connectDb } from './db.js';
import { registerRoutes as registerAuthRoutes } from './auth/routes.js';
import { registerDocumentRoutes } from './documents/routes.js';
import { registerSyncRoutes } from './sync/routes.js';
import { initTypesenseCollection } from './search/typesense.js';

const PORT = Number(process.env.PORT ?? 3000);
const app = streetApp({ port: PORT });

app.use(async (ctx: any, next: any) => {
  if (ctx.method === 'GET' && ctx.path === '/health') {
    try {
      await pool.query('SELECT 1');
      return ctx.json({ status: 'ok', service: 'lifevault-api', database: 'connected' });
    } catch {
      return ctx.json({ status: 'degraded', service: 'lifevault-api', database: 'unavailable' }, 503);
    }
  }
  if (ctx.method === 'GET' && ctx.path === '/ready') {
    try {
      await pool.query('SELECT 1');
      return ctx.json({ status: 'ok', service: 'lifevault-api', database: 'connected' });
    } catch {
      return ctx.json({ status: 'degraded', service: 'lifevault-api', database: 'unavailable' }, 503);
    }
  }
  await next();
});

await registerAuthRoutes(app);
await registerDocumentRoutes(app);
await registerSyncRoutes(app);

app.listen(PORT, '0.0.0.0').then(async () => {
  try {
    await connectDb();
    console.log('Database connected');
  } catch (e) {
    console.error('Database connection failed:', e);
  }
  try {
    await initTypesenseCollection();
    console.log('Typesense initialized');
  } catch (e) {
    console.error('Typesense initialization failed:', e);
  }
  console.log(`LifeVault API listening on http://localhost:${PORT}`);
});
