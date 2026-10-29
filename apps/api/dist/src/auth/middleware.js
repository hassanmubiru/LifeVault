import crypto from 'node:crypto';
import { z } from 'zod';
export function getJwtSecret() {
    return process.env.JWT_SECRET || crypto.randomBytes(32).toString('hex');
}
const ALGORITHM = 'aes-256-gcm';
const TOKEN_EXPIRY_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
const REFRESH_TOKEN_EXPIRY_MS = 90 * 24 * 60 * 60 * 1000; // 90 days
function base64UrlEncode(buffer) {
    return buffer.toString('base64url');
}
function base64UrlDecode(str) {
    return Buffer.from(str, 'base64url');
}
function createSignature(header, payload, secret) {
    return crypto
        .createHmac('sha384', secret)
        .update(`${header}.${payload}`)
        .digest('base64url');
}
export function generateAccessToken(userId, deviceId) {
    const secret = getJwtSecret();
    const now = Math.floor(Date.now() / 1000);
    const payload = {
        userId,
        deviceId,
        type: 'access',
        iat: now,
        exp: now + Math.floor(TOKEN_EXPIRY_MS / 1000),
    };
    const payloadJson = JSON.stringify(payload);
    const payloadB64 = base64UrlEncode(Buffer.from(payloadJson));
    const headerB64 = base64UrlEncode(Buffer.from('{"alg":"HS384","typ":"JWT"}'));
    const signature = createSignature(headerB64, payloadB64, secret);
    return `${headerB64}.${payloadB64}.${signature}`;
}
export function generateRefreshToken(userId, deviceId) {
    const secret = getJwtSecret();
    const now = Math.floor(Date.now() / 1000);
    const payload = {
        userId,
        deviceId,
        type: 'refresh',
        iat: now,
        exp: now + Math.floor(REFRESH_TOKEN_EXPIRY_MS / 1000),
    };
    const payloadJson = JSON.stringify(payload);
    const payloadB64 = base64UrlEncode(Buffer.from(payloadJson));
    const headerB64 = base64UrlEncode(Buffer.from('{"alg":"HS384","typ":"JWT"}'));
    const signature = createSignature(headerB64, payloadB64, secret);
    return `${headerB64}.${payloadB64}.${signature}`;
}
export function verifyToken(token) {
    const secret = getJwtSecret();
    const parts = token.split('.');
    if (parts.length !== 3)
        return null;
    const [headerB64, payloadB64, signature] = parts;
    const expectedSig = createSignature(headerB64, payloadB64, secret);
    const sigBuffer = Buffer.from(signature);
    const expectedBuffer = Buffer.from(expectedSig);
    if (sigBuffer.length !== expectedBuffer.length) {
        return null;
    }
    if (!crypto.timingSafeEqual(sigBuffer, expectedBuffer)) {
        return null;
    }
    try {
        const payloadJson = base64UrlDecode(payloadB64).toString();
        const payload = JSON.parse(payloadJson);
        const now = Math.floor(Date.now() / 1000);
        if (payload.exp < now)
            return null;
        return payload;
    }
    catch {
        return null;
    }
}
export function extractToken(authHeader) {
    if (!authHeader?.startsWith('Bearer '))
        return null;
    return authHeader.slice(7);
}
export function hashPassword(password) {
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.pbkdf2Sync(password, salt, 100000, 64, 'sha512').toString('hex');
    return `${salt}:${hash}`;
}
export function verifyPassword(password, stored) {
    const [salt, hash] = stored.split(':');
    if (!salt || !hash)
        return false;
    const verifyHash = crypto.pbkdf2Sync(password, salt, 100000, 64, 'sha512').toString('hex');
    return crypto.timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(verifyHash, 'hex'));
}
export function hashToken(token) {
    return crypto.createHash('sha256').update(token).digest('hex');
}
export const emailSchema = z.string().email().max(255);
export const passwordSchema = z.string().min(8).max(128);
export const uuidSchema = z.string().uuid();
export function isValidEmail(email) {
    return emailSchema.safeParse(email).success;
}
export function isValidPassword(password) {
    return passwordSchema.safeParse(password).success;
}
export function sanitizeEmail(email) {
    return email.toLowerCase().trim();
}
const RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000; // 15 minutes
const MAX_ATTEMPTS_PER_WINDOW = 5;
const rateLimitMap = new Map();
export function checkRateLimit(identifier) {
    const now = Date.now();
    const entry = rateLimitMap.get(identifier);
    if (!entry || entry.resetAt < now) {
        rateLimitMap.set(identifier, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
        return { allowed: true };
    }
    if (entry.count >= MAX_ATTEMPTS_PER_WINDOW) {
        return { allowed: false, retryAfter: Math.ceil((entry.resetAt - now) / 1000) };
    }
    entry.count++;
    return { allowed: true };
}
export function generateDeviceToken() {
    return crypto.randomBytes(32).toString('hex');
}
export function generateSecureId() {
    return crypto.randomUUID();
}
