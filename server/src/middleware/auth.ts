import type { NextFunction, Request, Response } from 'express';
import { verifyToken } from '../lib/jwt.js';

export interface AuthenticatedRequest extends Request {
  userId: string;
  userEmail: string;
}

/**
 * Verifies the `Authorization: Bearer <token>` header and attaches the
 * authenticated user id/email to the request. Always the source of truth for
 * `user_id` in the sync endpoints.
 */
export function requireAuth(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing or invalid authorization header' });
    return;
  }
  const token = header.slice('Bearer '.length).trim();
  try {
    const payload = verifyToken(token);
    (req as AuthenticatedRequest).userId = payload.sub;
    (req as AuthenticatedRequest).userEmail = payload.email;
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}
