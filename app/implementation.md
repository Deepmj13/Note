Building a cross-device, offline-first note-taking app with Flutter requires a solid **Sync Engine** and a clean **Data Architecture**. The core mechanism relies on writing locally first, then asynchronously syncing changes to the remote backend when connected.

---

## Recommended Tech Stack

| Layer                | Primary Recommendation                         | Alternatives    | Purpose                                                         |
| -------------------- | ---------------------------------------------- | --------------- | --------------------------------------------------------------- |
| **State Management** | **Riverpod 2.x** (Notifier/AsyncNotifier)      | Bloc / Provider | Predictable, compile-safe state management                      |
| **Local Database**   | **Isar** or **Drift (SQLite)**                 | Hive            | Fast, typed local storage with auto-indexing and fast querying  |
| **Backend / Auth**   | **Supabase**                                   | Firebase        | Auth, real-time database, and conflict-resolution APIs          |
| **HTTP / REST**      | **Dio** + **Retrofit**                         | `http` package  | Handles network requests, interceptors, and offline retry logic |
| **Import / Export**  | `file_picker` + `path_provider` + `share_plus` | -               | Accessing local files, reading/writing JSON/Markdown            |

---

## 5-Phase Implementation Plan

1. **Design Data Model & Synchronization Protocol:** Core Schema & Delta Sync Strategy.
   Establish a unified schema between your local database (Isar/Drift) and remote backend (PostgreSQL/Supabase).

- **Core Fields required on Note Entity:**
- `id` (UUID - generated client-side to prevent ID collisions before backend sync)
- `user_id` (UUID - foreign key tied to auth profile)
- `title` (String), `content` (Text or Delta JSON if rich text)
- `created_at` (DateTime ISO 8601 UTC)
- `updated_at` (DateTime ISO 8601 UTC - crucial for sync sorting)
- `is_deleted` (Boolean - soft deletion flag for tombstone sync)
- `is_synced` (Boolean - local-only flag to track pending changes)
- `version` or `server_updated_at` (BigInt/Timestamp for conflict checks)

- **Sync Strategy:** Use **Last-Write-Wins (LWW)** or **Delta Timestamp Sync**:

1. Fetch all local notes where `is_synced == false`.
2. Push pending local changes to remote backend API (`POST /sync`).
3. Query server for records updated after the client's last `last_synced_at` timestamp.
4. Apply incoming remote changes locally and mark synced items `is_synced = true`.

5. **Setup Authentication & Token Management:** Multi-Device Data Isolation.
   Implement JWT or OAuth authentication (Supabase Auth, Firebase Auth, or Custom JWT).

- Use `flutter_secure_storage` to persist JWT access and refresh tokens locally.
- Setup Dio Interceptors to attach `Authorization: Bearer <token>` automatically and handle auto-refreshing expired tokens.
- Clear local database tables on **Logout** or tag all local rows with `user_id` so switching users on the same device prevents cross-account data leaking.

3. **Implement Local Database & Offline Repository Layer:** Offline-First Data Access.
   Abstract all data access behind a unified **Repository Pattern**.

- The UI should **only read from and write to the local database**.
- When a user creates/edits a note:

1. Write immediately to local DB (`is_synced = false`).
2. UI updates instantly via local streams (`Isar` query watcher or Riverpod StreamProvider).
3. Trigger background sync worker/service via Dio.

4. **Build the Import & Export Module:** File Pickers & Formatting Engine.
   Provide reliable data portability in JSON and Markdown standard formats.

- **Export Engine:**

1. Query requested notes from local DB (either all notes or selected notes).
2. Format to **JSON** (full payload with metadata) or zip of **Markdown (`.md`)** files.
3. Save temporary file using `path_provider` and trigger standard OS share sheet via `share_plus`.

- **Import Engine:**

1. Pick file using `file_picker` (support `.json` and `.md`).
2. Validate schema structure (e.g., check for missing `title` or invalid formatting).
3. Parse payload into Note domain models and batch-insert into local DB with `is_synced = false`.
4. Trigger background sync worker to upload imported notes to backend.

5. **Integrate State Management & UI Layer:** Riverpod Setup & Real-time Connectivity.
   Connect offline database and network listeners to the Flutter UI layer using Riverpod.

- Listen to device connectivity status via `connectivity_plus`. Automatically trigger a sync sync-cycle when network transitions from offline to online.
- Manage UI states with standard Riverpod providers:
- `authNotifierProvider`: Manages auth tokens and active user profile.
- `notesListProvider`: Watches local database live queries.
- `syncStatusProvider`: Tracks current sync state (`idle`, `syncing`, `error`, `offline`).

---

## Import / Export Data Standard Format

For maximum compatibility, export structured JSON using this schema:

```json
{
  "app_version": "1.0.0",
  "exported_at": "2026-08-14T17:50:00Z",
  "notes": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "Project Architecture",
      "content": "# Notes\nSystem details here...",
      "created_at": "2026-08-10T10:00:00Z",
      "updated_at": "2026-08-14T12:30:00Z"
    }
  ]
}
```



