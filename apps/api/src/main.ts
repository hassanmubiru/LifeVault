import 'reflect-metadata';
import { streetApp } from 'streetjs';
import { pool, connectDb } from './db.js';

const PORT = Number(process.env.PORT ?? 3000);
const app = streetApp({ port: PORT });

app.use(async (ctx, next) => {
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

app.start().then(async () => {
  try {
    await connectDb();
    console.log('Database connected');
  } catch (e) {
    console.error('Database connection failed:', e);
  }
  console.log(`LifeVault API running on port ${PORT}`);
});
