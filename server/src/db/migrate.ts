import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { pool } from './pool.js';
import { logger } from '../lib/logger.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Applies pending database migrations (currently the idempotent `initial`
 * schema). Safe to call on every startup: schema_migrations tracks what has
 * already been applied. Does NOT close the pool so the server can keep using
 * it after boot.
 */
export async function runMigrations(): Promise<void> {
  const sql = await readFile(join(__dirname, 'schema.sql'), 'utf8');
  const client = await pool.connect();
  try {
    await client.query('begin');

    // Track what has been applied so schema.sql only runs once.
    await client.query(`
      create table if not exists schema_migrations (
        name text primary key,
        applied_at timestamptz not null default now()
      )
    `);

    const { rows } = await client.query(
      `select name from schema_migrations where name = 'initial'`,
    );
    if (rows.length === 0) {
      // Drain any legacy tables from an earlier/foreign schema so the fresh
      // schema below can be applied cleanly. Only runs on the initial
      // migration (approved: existing data is intentionally discarded).
      await client.query(`
        drop table if exists devices cascade;
        drop table if exists processed_operations cascade;
        drop table if exists refresh_tokens cascade;
        drop table if exists sync_changes cascade;
        drop table if exists notes cascade;
        drop table if exists folders cascade;
        drop table if exists users cascade;
      `);
      await client.query(sql);
      await client.query(
        `insert into schema_migrations (name) values ('initial')`,
      );
      logger.info('Applied initial schema.');
    } else {
      logger.info('Initial schema already applied; nothing to do.');
    }

    await client.query('commit');
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
}

// CLI entry point (`npm run migrate`): run migrations then close the pool.
// Only runs when this module is executed directly, not when imported by the
// server. Paths are normalized (lowercased) to handle Windows casing.
const thisPath = resolve(fileURLToPath(import.meta.url)).toLowerCase();
const argv1 = process.argv[1];
const isCli = !!argv1 && resolve(argv1).toLowerCase() === thisPath;
if (isCli) {
  runMigrations()
    .then(() => pool.end())
    .then(() => process.exit(0))
    .catch((err) => {
      logger.error({ err: err as object }, 'migration failed');
      process.exit(1);
    });
}
