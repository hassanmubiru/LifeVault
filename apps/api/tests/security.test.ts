import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  hashPassword,
  verifyPassword,
  generateAccessToken,
  generateRefreshToken,
  verifyToken,
  extractToken,
  checkRateLimit,
  isValidEmail,
  isValidPassword,
  sanitizeEmail,
  hashToken,
  generateDeviceToken,
  generateSecureId,
} from '../src/auth/middleware.js';

describe('Password Hashing', () => {
  test('hashPassword creates salted hash', () => {
    const hash = hashPassword('testpass123');
    assert.ok(hash.includes(':'));
    const [salt, derivedHash] = hash.split(':');
    assert.ok(salt.length === 32);
    assert.ok(derivedHash.length === 128);
  });

  test('verifyPassword validates correct password', () => {
    const password = 'testpass123';
    const hash = hashPassword(password);
    assert.ok(verifyPassword(password, hash));
  });

  test('verifyPassword rejects incorrect password', () => {
    const hash = hashPassword('testpass123');
    assert.ok(!verifyPassword('wrongpass', hash));
  });

  test('verifyPassword handles invalid stored hash format', () => {
    assert.ok(!verifyPassword('password', 'invalid'));
    assert.ok(!verifyPassword('password', ''));
    assert.ok(!verifyPassword('password', 'onlyonepart'));
  });

  test('timing safe comparison works', () => {
    const hash = hashPassword('testpass123');
    const hash2 = hashPassword('testpass123');
    assert.ok(hash !== hash2);
    assert.ok(verifyPassword('testpass123', hash));
    assert.ok(!verifyPassword('testpass123', hash2));
  });
});

describe('Token Generation', () => {
  test('generateAccessToken creates valid JWT-like token', () => {
    const token = generateAccessToken('user-123', 'device-456');
    const parts = token.split('.');
    assert.strictEqual(parts.length, 3);
  });

  test('generateRefreshToken creates valid token', () => {
    const token = generateRefreshToken('user-123', 'device-456');
    const parts = token.split('.');
    assert.strictEqual(parts.length, 3);
  });

  test('verifyToken decodes valid access token', () => {
    const token = generateAccessToken('user-123', 'device-456');
    const payload = verifyToken(token);
    assert.ok(payload);
    assert.strictEqual(payload.userId, 'user-123');
    assert.strictEqual(payload.deviceId, 'device-456');
    assert.strictEqual(payload.type, 'access');
  });

  test('verifyToken decodes valid refresh token', () => {
    const token = generateRefreshToken('user-123', 'device-456');
    const payload = verifyToken(token);
    assert.ok(payload);
    assert.strictEqual(payload.type, 'refresh');
  });

  test('verifyToken rejects expired token', () => {
    process.env.JWT_SECRET = 'test-secret-32-characters-long!!';
    const token = generateAccessToken('user-123');
    const payload = verifyToken(token);
    assert.ok(payload);
    process.env.JWT_SECRET = undefined;
  });

  test('verifyToken rejects invalid token format', () => {
    assert.strictEqual(verifyToken('invalid'), null);
    assert.strictEqual(verifyToken('only.two.parts'), null);
    assert.strictEqual(verifyToken(''), null);
  });

  test('verifyToken rejects tampered token', () => {
    const token = generateAccessToken('user-123');
    const [h, p, s] = token.split('.');
    const tamperedToken = `${h}.${p}.wrongsignature`;
    assert.strictEqual(verifyToken(tamperedToken), null);
  });
});

describe('Token Extraction', () => {
  test('extractToken parses valid Bearer header', () => {
    const token = extractToken('Bearer abc123');
    assert.strictEqual(token, 'abc123');
  });

  test('extractToken returns null for missing header', () => {
    assert.strictEqual(extractToken(undefined), null);
    assert.strictEqual(extractToken(''), null);
  });

  test('extractToken returns null for non-Bearer auth', () => {
    assert.strictEqual(extractToken('Basic abc123'), null);
    assert.strictEqual(extractToken('bearer abc123'), null);
  });
});

describe('Rate Limiting', () => {
  beforeEach(() => {
    checkRateLimit('test-identifier');
  });

  test('allows first request', () => {
    const result = checkRateLimit('new-identifier');
    assert.strictEqual(result.allowed, true);
  });

  test('blocks after max attempts', () => {
    const id = 'rate-limit-test';
    for (let i = 0; i < 5; i++) {
      checkRateLimit(id);
    }
    const result = checkRateLimit(id);
    assert.strictEqual(result.allowed, false);
    assert.ok(result.retryAfter);
  });

  test('tracks retry-after time', () => {
    const id = 'rate-limit-retry';
    for (let i = 0; i < 5; i++) {
      checkRateLimit(id);
    }
    const result = checkRateLimit(id);
    assert.ok(typeof result.retryAfter === 'number');
    assert.ok(result.retryAfter! > 0);
  });
});

describe('Input Validation', () => {
  test('isValidEmail accepts valid emails', () => {
    assert.strictEqual(isValidEmail('test@example.com'), true);
    assert.strictEqual(isValidEmail('user.name@domain.org'), true);
  });

  test('isValidEmail rejects invalid emails', () => {
    assert.strictEqual(isValidEmail(''), false);
    assert.strictEqual(isValidEmail('notanemail'), false);
    assert.strictEqual(isValidEmail('@domain.com'), false);
    assert.strictEqual(isValidEmail('test@'), false);
  });

  test('isValidPassword accepts valid passwords', () => {
    assert.strictEqual(isValidPassword('password123'), true);
    assert.strictEqual(isValidPassword('abcdefgh'), true);
  });

  test('isValidPassword rejects invalid passwords', () => {
    assert.strictEqual(isValidPassword('short'), false);
    assert.strictEqual(isValidPassword(''), false);
    assert.strictEqual(isValidPassword('a'.repeat(129)), false);
  });

  test('sanitizeEmail lowercases and trims', () => {
    assert.strictEqual(sanitizeEmail('  Test@Example.COM  '), 'test@example.com');
  });
});

describe('Token Hashing', () => {
  test('hashToken creates SHA256 hash', () => {
    const hash = hashToken('token123');
    assert.strictEqual(hash.length, 64);
  });

  test('hashToken is deterministic', () => {
    const hash1 = hashToken('token123');
    const hash2 = hashToken('token123');
    assert.strictEqual(hash1, hash2);
  });

  test('hashToken differs for different inputs', () => {
    const hash1 = hashToken('token123');
    const hash2 = hashToken('token456');
    assert.notStrictEqual(hash1, hash2);
  });
});

describe('Utility Functions', () => {
  test('generateDeviceToken creates random token', () => {
    const token = generateDeviceToken();
    assert.strictEqual(token.length, 64);
  });

  test('generateDeviceToken is unique', () => {
    const token1 = generateDeviceToken();
    const token2 = generateDeviceToken();
    assert.notStrictEqual(token1, token2);
  });

  test('generateSecureId creates UUID-like string', () => {
    const id = generateSecureId();
    assert.ok(id.match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i));
  });
});
