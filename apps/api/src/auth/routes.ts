import { z } from 'zod';
import { pool } from '../db.js';
import {
  hashPassword,
  verifyPassword,
  generateAccessToken,
  generateRefreshToken,
  generateDeviceToken,
  generateSecureId,
  verifyToken,
  extractToken,
  checkRateLimit,
  sanitizeEmail,
} from './middleware.js';

const registerSchema = z.object({
  email: z.string().email().max(255),
  password: z.string().min(8).max(128),
  deviceName: z.string().min(1).max(255).optional(),
});

const loginSchema = z.object({
  email: z.string().email().max(255),
  password: z.string().min(1).max(128),
  deviceName: z.string().min(1).max(255).optional(),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

export async function registerRoutes(app: any) {
  app.post('/auth/register', async (ctx: any) => {
    const body = ctx.body;
    const parsed = registerSchema.safeParse(body);
    if (!parsed.success) {
      return ctx.json({ error: 'Invalid input', details: parsed.error.errors }, 400);
    }

    const { email, password, deviceName } = parsed.data;
    const cleanEmail = sanitizeEmail(email);

    const rateLimitKey = `register:${cleanEmail}`;
    const rateLimit = checkRateLimit(rateLimitKey);
    if (!rateLimit.allowed) {
      return ctx.json({ error: 'Too many attempts', retryAfter: rateLimit.retryAfter }, 429);
    }

    const passwordHash = hashPassword(password);
    const userId = generateSecureId();
    const deviceId = generateSecureId();
    const deviceToken = generateDeviceToken();
    const now = new Date().toISOString();

    try {
      const existingUser = await pool.query(
        'SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL',
        [cleanEmail]
      );
      if (existingUser.rows.length > 0) {
        return ctx.json({ error: 'Email already registered' }, 409);
      }

      await pool.query(
        `INSERT INTO users (id, email, password_hash, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5)`,
        [userId, cleanEmail, passwordHash, now, now]
      );

      await pool.query(
        `INSERT INTO devices (id, user_id, name, public_key, created_at, last_seen_at)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [deviceId, userId, deviceName || 'Primary Device', null, now, now]
      );

      const accessToken = generateAccessToken(userId, deviceId);
      const refreshToken = generateRefreshToken(userId, deviceId);

      return ctx.json({
        user: { id: userId, email: cleanEmail },
        device: { id: deviceId, name: deviceName || 'Primary Device' },
        accessToken,
        refreshToken,
      }, 201);
    } catch (err: any) {
      console.error('Registration error:', err.message);
      return ctx.json({ error: 'Registration failed' }, 500);
    }
  });

  app.post('/auth/login', async (ctx: any) => {
    const body = ctx.body;
    const parsed = loginSchema.safeParse(body);
    if (!parsed.success) {
      return ctx.json({ error: 'Invalid input', details: parsed.error.errors }, 400);
    }

    const { email, password, deviceName } = parsed.data;
    const cleanEmail = sanitizeEmail(email);

    const rateLimitKey = `login:${cleanEmail}`;
    const rateLimit = checkRateLimit(rateLimitKey);
    if (!rateLimit.allowed) {
      return ctx.json({ error: 'Too many attempts', retryAfter: rateLimit.retryAfter }, 429);
    }

    try {
      const userResult = await pool.query(
        'SELECT id, password_hash, email FROM users WHERE email = $1 AND deleted_at IS NULL',
        [cleanEmail]
      );

      if (userResult.rows.length === 0) {
        return ctx.json({ error: 'Invalid credentials' }, 401);
      }

      const user = userResult.rows[0] as { id: string; password_hash: string; email: string };
      if (!user.password_hash || !verifyPassword(password, user.password_hash)) {
        return ctx.json({ error: 'Invalid credentials' }, 401);
      }

      const deviceId = generateSecureId();
      const deviceToken = generateDeviceToken();
      const now = new Date().toISOString();

      await pool.query(
        `INSERT INTO devices (id, user_id, name, public_key, created_at, last_seen_at)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [deviceId, user.id, deviceName || 'Unknown Device', null, now, now]
      );

      const accessToken = generateAccessToken(user.id, deviceId);
      const refreshToken = generateRefreshToken(user.id, deviceId);

      return ctx.json({
        user: { id: user.id, email: user.email },
        device: { id: deviceId, name: deviceName || 'Unknown Device' },
        accessToken,
        refreshToken,
      });
    } catch (err: any) {
      console.error('Login error:', err.message);
      return ctx.json({ error: 'Login failed' }, 500);
    }
  });

  app.post('/auth/refresh', async (ctx: any) => {
    const body = ctx.body;
    const parsed = refreshSchema.safeParse(body);
    if (!parsed.success) {
      return ctx.json({ error: 'Invalid input' }, 400);
    }

    const { refreshToken } = parsed.data;
    const payload = verifyToken(refreshToken);
    if (!payload || payload.type !== 'refresh') {
      return ctx.json({ error: 'Invalid refresh token' }, 401);
    }

    const { userId, deviceId } = payload;
    const newAccessToken = generateAccessToken(userId, deviceId || '');

    return ctx.json({ accessToken: newAccessToken });
  });

  app.post('/auth/logout', async (ctx: any) => {
    const authHeader = ctx.headers.authorization;
    const token = extractToken(authHeader);
    if (!token) {
      return ctx.json({ error: 'Unauthorized' }, 401);
    }

    const payload = verifyToken(token);
    if (!payload) {
      return ctx.json({ error: 'Invalid token' }, 401);
    }

    const { userId, deviceId } = payload;

    try {
      if (deviceId) {
        await pool.query(
          'UPDATE devices SET revoked_at = $1 WHERE id = $2 AND user_id = $3',
          [new Date().toISOString(), deviceId, userId]
        );
      }

      return ctx.json({ success: true });
    } catch (err: any) {
      console.error('Logout error:', err.message);
      return ctx.json({ error: 'Logout failed' }, 500);
    }
  });

  app.get('/auth/me', async (ctx: any) => {
    const authHeader = ctx.headers.authorization;
    const token = extractToken(authHeader);
    if (!token) {
      return ctx.json({ error: 'Unauthorized' }, 401);
    }

    const payload = verifyToken(token);
    if (!payload) {
      return ctx.json({ error: 'Invalid or expired token' }, 401);
    }

    const { userId } = payload;

    try {
      const userResult = await pool.query(
        'SELECT id, email, created_at FROM users WHERE id = $1 AND deleted_at IS NULL',
        [userId]
      );

      if (userResult.rows.length === 0) {
        return ctx.json({ error: 'User not found' }, 404);
      }

      const devicesResult = await pool.query(
        'SELECT id, name, last_seen_at, revoked_at, created_at FROM devices WHERE user_id = $1 ORDER BY created_at DESC',
        [userId]
      );

      return ctx.json({
        user: userResult.rows[0],
        devices: devicesResult.rows,
      });
    } catch (err: any) {
      console.error('Get user error:', err.message);
      return ctx.json({ error: 'Failed to get user info' }, 500);
    }
  });

  app.delete('/auth/devices/:deviceId', async (ctx: any) => {
    const authHeader = ctx.headers.authorization;
    const token = extractToken(authHeader);
    if (!token) {
      return ctx.json({ error: 'Unauthorized' }, 401);
    }

    const payload = verifyToken(token);
    if (!payload) {
      return ctx.json({ error: 'Invalid or expired token' }, 401);
    }

    const { userId } = payload;
    const { deviceId } = ctx.params;

    if (!deviceId) {
      return ctx.json({ error: 'Device ID required' }, 400);
    }

    try {
      const result = await pool.query(
        'UPDATE devices SET revoked_at = $1 WHERE id = $2 AND user_id = $3 RETURNING id',
        [new Date().toISOString(), deviceId, userId]
      );

      if (result.rows.length === 0) {
        return ctx.json({ error: 'Device not found' }, 404);
      }

      return ctx.json({ success: true });
    } catch (err: any) {
      console.error('Revoke device error:', err.message);
      return ctx.json({ error: 'Failed to revoke device' }, 500);
    }
  });
}
