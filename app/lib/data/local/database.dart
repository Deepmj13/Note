import 'package:drift/drift.dart';

part 'database.g.dart';

enum NoteType { text, checklist }

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  Int64Column get version => int64()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  TextColumn get noteType =>
      textEnum<NoteType>().withDefault(Constant(NoteType.text.name))();
  TextColumn get folderId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get parentFolderId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncMeta extends Table {
  TextColumn get metaKey => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {metaKey};
}

@DriftDatabase(tables: [Notes, Folders, SyncMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.addColumn(notes, notes.isFavorite);
          await m.addColumn(notes, notes.isPinned);
          await m.addColumn(notes, notes.noteType);
          await m.addColumn(notes, notes.folderId);
          // `createTable` builds the folders table with the CURRENT column set,
          // which already includes user_id, is_synced and is_deleted. When the
          // table is created here we must therefore skip the folder-column
          // additions below (they would fail with "duplicate column name").
          await m.createTable(folders);
        } else {
          // Folders already exists from a schema that predates these columns.
          if (from < 3) {
            await m.addColumn(folders, folders.userId);
            await m.addColumn(folders, folders.isSynced);
          }
          if (from < 4) {
            await m.addColumn(folders, folders.isDeleted);
          }
        }
        if (from < 3) {
          await m.createTable(syncMeta);
        }
      },
    );
  }
}
