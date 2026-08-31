import { Router } from 'express';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { asyncHandler } from '../middleware/async-handler.js';
import { requireAuth, type AuthenticatedRequest } from '../middleware/auth.js';

const router = Router();

// ---------------------------------------------------------------------------
// Field helpers (all timestamps travel as ISO-8601 strings, same as the app)
// ---------------------------------------------------------------------------

function noteColumns() {
  return `id, user_id, title, content, created_at, updated_at,
          is_deleted, version, is_favorite, is_pinned, note_type, folder_id`;
}

function folderColumns() {
  return `id, user_id, name, parent_folder_id, created_at, updated_at, is_deleted`;
}

// ---------------------------------------------------------------------------
// Pull: rows updated after `since` (ISO string)
// ---------------------------------------------------------------------------

router.get('/notes', requireAuth, asyncHandler(async (req, res) => {
  const auth = req as AuthenticatedRequest;
  const since = z.string().optional().parse(req.query.since) ?? '1970-01-01T00:00:00.000Z';
  const { rows } = await pool.query(
    `select ${noteColumns()} from notes
     where user_id = $1 and updated_at > $2
     order by updated_at asc`,
[auth.userId, since],
  );
  res.json(rows);
}));

router.get('/folders', requireAuth, asyncHandler(async (req, res) => {
  const auth = req as AuthenticatedRequest;
  const since = z.string().optional().parse(req.query.since) ?? '1970-01-01T00:00:00.000Z';
  const { rows } = await pool.query(
    `select ${folderColumns()} from folders
     where user_id = $1 and updated_at > $2
     order by updated_at asc`,
[auth.userId, since],
  );
  res.json(rows);
}));

// ---------------------------------------------------------------------------
// Push: batch upsert. user_id is always taken from the JWT.
//
// Conflicts are resolved last-write-wins with a saturation guard: a stale
// row (lower version, or equal version with an older updated_at) is rejected
// instead of clobbering newer data. Each item is reported as applied or
// rejected so the client only clears its dirty flag for accepted writes.
//
// Rows are applied as a single multi-row `unnest` upsert (not row-by-row) so
// large batches settle in one round trip. `ON CONFLICT ... DO UPDATE ...
// WHERE` returns only the rows that were actually applied (new inserts plus
// accepted updates); rejected rows are absent and reported back to the client.
// ---------------------------------------------------------------------------

const MAX_BATCH = 500;

const noteSchema = z.object({
  id: z.string().min(1),
  title: z.string().default(''),
  content: z.string().default(''),
  created_at: z.string(),
  updated_at: z.string(),
  is_deleted: z.boolean().default(false),
  version: z.number().int().default(1),
  is_favorite: z.boolean().default(false),
  is_pinned: z.boolean().default(false),
  note_type: z.string().default('text'),
  folder_id: z.string().nullable().optional(),
});

router.post('/notes', requireAuth, asyncHandler(async (req, res) => {
  const auth = req as AuthenticatedRequest;
  const items = z
    .array(noteSchema)
    .max(MAX_BATCH)
    .parse(req.body ?? []);
  if (items.length === 0) {
    res.json({ count: 0, applied: [], rejected: [] });
    return;
  }

  const ids = items.map((n) => n.id);
  const userIds = items.map(() => auth.userId);
  const titles = items.map((n) => n.title);
  const contents = items.map((n) => n.content);
  const created = items.map((n) => n.created_at);
  const updated = items.map((n) => n.updated_at);
  const deleted = items.map((n) => n.is_deleted);
  const versions = items.map((n) => n.version);
  const favorites = items.map((n) => n.is_favorite);
  const pinned = items.map((n) => n.is_pinned);
  const noteTypes = items.map((n) => n.note_type);
  const folderIds = items.map((n) => n.folder_id ?? null);

  const { rows } = await pool.query<{ id: string }>(
    `insert into notes
       (id, user_id, title, content, created_at, updated_at,
        is_deleted, version, is_favorite, is_pinned, note_type, folder_id)
     select * from unnest(
       $1::uuid[], $2::uuid[], $3::text[], $4::text[], $5::timestamptz[],
       $6::timestamptz[], $7::boolean[], $8::bigint[], $9::boolean[],
       $10::boolean[], $11::text[], $12::uuid[]
     )
     on conflict (id) do update set
       title = excluded.title,
       content = excluded.content,
       updated_at = excluded.updated_at,
       is_deleted = excluded.is_deleted,
       version = excluded.version,
       is_favorite = excluded.is_favorite,
       is_pinned = excluded.is_pinned,
       note_type = excluded.note_type,
       folder_id = excluded.folder_id
     where notes.version < excluded.version
        or (notes.version = excluded.version
            and notes.updated_at <= excluded.updated_at)
     returning id`,
    [
      ids,
      userIds,
      titles,
      contents,
      created,
      updated,
      deleted,
      versions,
      favorites,
      pinned,
      noteTypes,
      folderIds,
    ],
  );

  const appliedSet = new Set(rows.map((r) => r.id));
  const applied = items
    .filter((i) => appliedSet.has(i.id))
    .map((i) => i.id);
  const rejected = items.filter((i) => !appliedSet.has(i.id)).map((i) => i.id);
  res.json({ count: applied.length, applied, rejected });
}));

const folderSchema = z.object({
  id: z.string().min(1),
  name: z.string().default(''),
  parent_folder_id: z.string().nullable().optional(),
  created_at: z.string(),
  updated_at: z.string(),
  is_deleted: z.boolean().default(false),
});

router.post('/folders', requireAuth, asyncHandler(async (req, res) => {
  const auth = req as AuthenticatedRequest;
  const items = z
    .array(folderSchema)
    .max(MAX_BATCH)
    .parse(req.body ?? []);
  if (items.length === 0) {
    res.json({ count: 0, applied: [], rejected: [] });
    return;
  }

  const ids = items.map((f) => f.id);
  const userIds = items.map(() => auth.userId);
  const names = items.map((f) => f.name);
  const parents = items.map((f) => f.parent_folder_id ?? null);
  const created = items.map((f) => f.created_at);
  const updated = items.map((f) => f.updated_at);
  const deleted = items.map((f) => f.is_deleted);

  const { rows } = await pool.query<{ id: string }>(
    `insert into folders
       (id, user_id, name, parent_folder_id, created_at, updated_at, is_deleted)
     select * from unnest(
       $1::uuid[], $2::uuid[], $3::text[], $4::uuid[], $5::timestamptz[],
       $6::timestamptz[], $7::boolean[]
     )
     on conflict (id) do update set
       name = excluded.name,
       parent_folder_id = excluded.parent_folder_id,
       updated_at = excluded.updated_at,
       is_deleted = excluded.is_deleted
     where folders.updated_at <= excluded.updated_at
     returning id`,
    [ids, userIds, names, parents, created, updated, deleted],
  );

  const appliedSet = new Set(rows.map((r) => r.id));
  const applied = items
    .filter((i) => appliedSet.has(i.id))
    .map((i) => i.id);
  const rejected = items.filter((i) => !appliedSet.has(i.id)).map((i) => i.id);
  res.json({ count: applied.length, applied, rejected });
}));

export default router;
