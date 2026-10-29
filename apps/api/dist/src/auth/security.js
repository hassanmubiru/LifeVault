import crypto from 'node:crypto';
const jwtSecret = process.env.JWT_SECRET || crypto.randomBytes(32).toString('hex');
export function hashPassword(password) {
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.pbkdf2Sync(password, salt, 100000, 64, 'sha512').toString('hex');
    return `${salt}:${hash}`;
}
export function verifyPassword(password, stored) {
    const [salt, hash] = stored.split(':');
    const verifyHash = crypto.pbkdf2Sync(password, salt, 100000, 64, 'sha512').toString('hex');
    return hash === verifyHash;
}
export function generateToken() {
    return crypto.randomBytes(32).toString('hex');
}
export function hashToken(token) {
    return crypto.createHash('sha256').update(token).digest('hex');
}
