import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { signToken } from '../lib/jwt.js';
import { REFRESH_EXPIRES_DAYS } from '../lib/config.js';
import { asyncHandler } from '../middleware/async-handler.js';
import { requireAuth, type AuthenticatedRequest } from '../middleware/auth.js';

const router = Router();

const credentialsSchema = z.object({
  email: z.string().trim().email(),
  password: z.string().min(6, 'Password must be at least 6 characters'),
});

function publicUser(row: { id: string; email: string }) {
  return { id: row.id, email: row.email };
}

function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

async function issueRefreshToken(userId: string): Promise<string> {
  const token = randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + REFRESH_EXPIRES_DAYS * 24 * 60 * 60 * 1000);
  await pool.query(
    `insert into refresh_tokens (id, user_id, token_hash, expires_at)
     values ($1, $2, $3, $4)`,
    [randomUUID(), userId, hashToken(token), expiresAt],
  );
  return token;
}

/** Issue a fresh access + refresh token pair for a user. */
async function issueTokenPair(userId: string, email: string) {
  const token = signToken({ sub: userId, email });
  const refreshToken = await issueRefreshToken(userId);
  return { token, refreshToken };
}

router.post('/register', asyncHandler(async (req, res) => {
  const parsed = credentialsSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.issues[0]?.message ?? 'Invalid input' });
    return;
  }
  const { email, password } = parsed.data;
  const normalized = email.toLowerCase();

  const passwordHash = await bcrypt.hash(password, 10);
  try {
    const { rows } = await pool.query(
      `insert into users (email, password_hash)
       values ($1, $2)
       returning id, email`,
      [normalized, passwordHash],
    );
    const user = rows[0];
    const { token, refreshToken } = await issueTokenPair(user.id, user.email);
    res.status(201).json({ token, refreshToken, user: publicUser(user) });
  } catch (err) {
    // The email column is unique, so a concurrent registration with the same
    // email surfaces here as a unique-violation (SQLSTATE 23505) rather than
    // the pre-check above. Report it as a conflict instead of a 500.
    const code = (err as { code?: string } | null)?.code;
    if (code === '23505') {
      res.status(409).json({ error: 'An account with this email already exists' });
      return;
    }
    throw err;
  }
}));

router.post('/login', asyncHandler(async (req, res) => {
  const parsed = credentialsSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid email or password' });
    return;
  }
  const { email, password } = parsed.data;
  const normalized = email.toLowerCase();

  const { rows } = await pool.query(
    'select id, email, password_hash from users where email = $1',
    [normalized],
  );
  const user = rows[0];
  if (!user) {
    res.status(401).json({ error: 'Invalid email or password' });
    return;
  }

  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) {
    res.status(401).json({ error: 'Invalid email or password' });
    return;
  }

  const { token, refreshToken } = await issueTokenPair(user.id, user.email);
  res.json({ token, refreshToken, user: publicUser(user) });
}));

// Exchange a valid refresh token for a new access + refresh token pair.
// The presented refresh token is rotated (revoked) so a leaked token is only
// usable once; a stolen pair of old refresh tokens cannot both stay valid.
router.post('/refresh', asyncHandler(async (req, res) => {
  const parsed = z.object({ refresh_token: z.string().min(1) }).safeParse(req.body);
  if (!parsed.success) {
    res.status(401).json({ error: 'Refresh token is required' });
    return;
  }

  const { rows } = await pool.query(
    `select rt.id as rt_id, rt.revoked_at, rt.expires_at, u.id as user_id, u.email
     from refresh_tokens rt
     join users u on u.id = rt.user_id
     where rt.token_hash = $1`,
    [hashToken(parsed.data.refresh_token)],
  );
  const row = rows[0];
  if (!row || row.revoked_at || new Date(row.expires_at) <= new Date()) {
    res.status(401).json({ error: 'Invalid or expired refresh token' });
    return;
  }

  await pool.query('update refresh_tokens set revoked_at = now() where id = $1', [row.rt_id]);
  const { token, refreshToken } = await issueTokenPair(row.user_id, row.email);
  res.json({ token, refreshToken });
}));

// Revoke a refresh token so the app session cannot be resumed from it.
router.post('/logout', asyncHandler(async (req, res) => {
  const parsed = z.object({ refresh_token: z.string().optional() }).safeParse(req.body);
  const token = parsed.success ? parsed.data.refresh_token : undefined;
  if (token) {
    await pool.query(
      `update refresh_tokens set revoked_at = now()
       where token_hash = $1 and revoked_at is null`,
      [hashToken(token)],
    );
  }
  res.json({ ok: true });
}));

router.get('/me', requireAuth, asyncHandler(async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { rows } = await pool.query(
    'select id, email from users where id = $1',
    [authReq.userId],
  );
  const user = rows[0];
  if (!user) {
    res.status(404).json({ error: 'User not found' });
    return;
  }
  res.json({ user: publicUser(user) });
}));

export default router;
