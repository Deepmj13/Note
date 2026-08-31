import jwt from 'jsonwebtoken';
import { JWT_EXPIRES_IN, JWT_SECRET } from './config.js';

export interface TokenPayload {
  sub: string;
  email: string;
}

export function signToken(payload: TokenPayload): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

export function verifyToken(token: string): TokenPayload {
  return jwt.verify(token, JWT_SECRET) as TokenPayload;
}
