import { test } from 'node:test';
import assert from 'node:assert';
import { hashPassword, verifyPassword } from '../src/auth/security.js';

test('password hashing works', () => {
  const password = 'testpass123';
  const hash = hashPassword(password);
  assert.ok(hash.includes(':'));
  assert.ok(verifyPassword(password, hash));
  assert.ok(!verifyPassword('wrongpass', hash));
});
