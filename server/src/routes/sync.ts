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
// Pull: rows updated after `since` (ISO string), served in pages.
//
// Responses are `{ rows, has_more, next_cursor }`. The client repeats the
// request passing the returned `next_cursor` (opaque `updatedAtIso|id` tuple)
// until `has_more` is false, so large result sets are fetched incrementally
// without loading everything into memory at once.
//
// The first page filters by `since`; subsequent pages use the keyset cursor
// `(updated_at, id) > (cursor)`, which cannot miss or duplicate rows that
// share a timestamp across page boundaries.
// ---------------------------------------------------------------------------

const DEFAULT_LIMIT = 500;
const MAX_LIMIT = 1000;

const limitSchema = z.coerce.number().int().min(1).max(MAX_LIMIT).default(DEFAULT_LIMIT);

async function pullPage(
  table: 'notes' | 'folders',
  userId: string,
  since: string,
  limit: number,
  cursor?: string,
): Promise<{ rows: object[]; hasMore: boolean; nextCursor: string | null }> {
  const columns = table === 'notes' ? noteColumns() : folderColumns();
  const pageSize = limit + 1;

  let rows: object[];
  if (cursor && cursor.length > 0) {
    const bar = cursor.lastIndexOf('|');
    if (bar <= 0 || bar === cursor.length - 1) {
      throw new z.ZodError([{ code: 'custom', path: ['cursor'], message: 'Invalid cursor' }]);
    }
    const cursorUpdatedAt = cursor.slice(0, bar);
    const cursorId = cursor.slice(bar + 1);
    const { rows: result } = await pool.query(
      `select ${columns} from ${table}
       where user_id = $1 and (updated_at, id) > ($2, $3::uuid)
       order by updated_at asc, id asc
       limit $4`,
      [userId, cursorUpdatedAt, cursorId, pageSize],
    );
    rows = result;
  } else {
    const { rows: result } = await pool.query(
      `select ${columns} from ${table}
       where user_id = $1 and updated_at > $2
       order by updated_at asc, id asc
       limit $3`,
      [userId, since, pageSize],
    );
    rows = result;
  }

  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  let nextCursor: string | null = null;
  if (hasMore && page.length > 0) {
    const last = page[page.length - 1] as { updated_at: Date | string; id: string };
    const ts = last.updated_at instanceof Date ? last.updated_at.toISOString() : String(last.updated_at);
    nextCursor = `${ts}|${last.id}`;
  }
  return { rows: page, hasMore, nextCursor };
}

router.get('/notes', requireAuth, asyncHandler(async (req, res) => {
  const auth = req as AuthenticatedRequest;
  const since = z.string().optional().parse(req.query.since) ?? '1970-01-01T00:00:00.000Z';
  const limit = limitSchema.parse(req.query.limit ?? DEFAULT_LIMIT);
  const cursor = typeof req.query.cursor === 'string' ? req.query.cursor : undefined;
  const { rows, hasMore, nextCursor } = await pullPage('notes', auth.userId, since, limit, cursor);
  res.json({ rows, has_more: hasMore, next_cursor: nextCursor });
}));

router.get('/folders', requireAuth, asyncHandler(async (req, res) => {
  const auth = req as AuthenticatedRequest;
  const since = z.string().optional().parse(req.query.since) ?? '1970-01-01T00:00:00.000Z';
  const limit = limitSchema.parse(req.query.limit ?? DEFAULT_LIMIT);
  const cursor = typeof req.query.cursor === 'string' ? req.query.cursor : undefined;
  const { rows, hasMore, nextCursor } = await pullPage('folders', auth.userId, since, limit, cursor);
  res.json({ rows, has_more: hasMore, next_cursor: nextCursor });
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

  // Folder integrity: a note may only reference a folder the user owns. Any
  // other folder_id (never-created, another user's, or long gone) is written
  // as NULL instead of creating a dangling reference server-side.
  const distinctFolderIds = [
    ...new Set(items.map((n) => n.folder_id).filter((f): f is string => !!f)),
  ];
  let validFolderIds = new Set<string>();
  if (distinctFolderIds.length > 0) {
    const { rows: folderRows } = await pool.query<{ id: string }>(
      'select id from folders where user_id = $1 and id = any($2::uuid[])',
      [auth.userId, distinctFolderIds],
    );
    validFolderIds = new Set(folderRows.map((r) => r.id));
  }
  const folderIds = items.map((n) =>
    n.folder_id != null && validFolderIds.has(n.folder_id) ? n.folder_id : null,
  );

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
  const applied = items.filter((i) => appliedSet.has(i.id));
  const rejected = items.filter((i) => !appliedSet.has(i.id)).map((i) => i.id);

  // Folder integrity: when a folder is (soft) deleted, detach its notes so no
  // note stays hidden inside a folder that no longer exists on the server.
  const deletedAppliedIds = applied.filter((f) => f.is_deleted).map((f) => f.id);
  if (deletedAppliedIds.length > 0) {
    await pool.query(
      `update notes set folder_id = null
       where user_id = $1 and folder_id = any($2::uuid[])`,
      [auth.userId, deletedAppliedIds],
    );
  }

  res.json({ count: applied.length, applied, rejected });
}));

// ---------------------------------------------------------------------------
// Purge: permanently delete note rows (trash "delete forever").
//
// Called by the app after it has hard-deleted the same rows locally. Deleting
// on the server before the client pulls guarantees a purged row can never be
// resurrected by a later pull. Scoped to the authenticated user.
// ---------------------------------------------------------------------------

router.post('/purge', requireAuth, asyncHandler(async (req, res) => {
  const auth = req as AuthenticatedRequest;
  const { ids } = z
    .object({ ids: z.array(z.string().min(1)).max(MAX_BATCH) })
    .parse(req.body ?? {});
  if (ids.length === 0) {
    res.json({ count: 0, purged: [] });
    return;
  }
  await pool.query(
    `delete from notes where user_id = $1 and id = any($2::uuid[])`,
    [auth.userId, ids],
  );
  res.json({ count: ids.length, purged: ids });
}));

export default router;
