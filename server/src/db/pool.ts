import 'dotenv/config';
import pg from 'pg';

const { Pool } = pg;

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error('DATABASE_URL is not set. Copy server/.env.example to server/.env and configure it.');
}

export const pool = new Pool({
  connectionString,
  // Neon (managed Postgres) requires TLS. We use a permissive SSL config so
  // local/self-signed or managed (Neon) hosts all connect without friction.
  ssl: { rejectUnauthorized: false },
});
