import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { signToken } from '../lib/jwt.js';
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
    const token = signToken({ sub: user.id, email: user.email });
    res.status(201).json({ token, user: publicUser(user) });
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

  const token = signToken({ sub: user.id, email: user.email });
  res.json({ token, user: publicUser(user) });
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
