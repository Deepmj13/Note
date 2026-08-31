import 'dart:convert';

import 'package:note_v4/data/local/database.dart';
import 'package:uuid/uuid.dart';

/// Thrown when an imported JSON payload is structurally invalid.
class NoteImportException implements Exception {
  const NoteImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parses notes from the standard JSON export schema (see
/// `implementation.md`) into local [Note] rows owned by [userId].
///
/// Unknown keys are ignored; missing optional fields fall back to safe
/// defaults. A payload without a `notes` list is rejected.
class NoteImporter {
  const NoteImporter._();

  static List<Note> fromJson(
    String source, {
    required String userId,
    String? folderId,
  }) {
    final decoded = _decode(source);
    final rawNotes = decoded['notes'];
    if (rawNotes is! List) {
      throw const NoteImportException(
        'Invalid export file: expected a "notes" array.',
      );
    }
    final notes = <Note>[];
    var baseTime = DateTime.now();
    for (final raw in rawNotes) {
      if (raw is! Map) continue;
      final now = baseTime;
      baseTime = baseTime.add(const Duration(milliseconds: 1));
      notes.add(_noteFromRaw(raw, userId, folderId, now));
    }
    return notes;
  }

  static Map<String, dynamic> _decode(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const NoteImportException('Invalid export file: expected JSON object.');
      }
      return decoded as Map<String, dynamic>;
    } on FormatException {
      throw const NoteImportException('Invalid export file: not valid JSON.');
    }
  }

  static Note _noteFromRaw(
    Map raw,
    String userId,
    String? folderId,
    DateTime fallbackTime,
  ) {
    DateTime parse(String? value, DateTime fallback) {
      if (value == null) return fallback;
      return DateTime.tryParse(value) ?? fallback;
    }

    final typeName = raw['note_type'] as String? ?? NoteType.text.name;
    final noteType = NoteType.values.asNameMap()[typeName] ?? NoteType.text;

    return Note(
      id: (raw['id'] as String?) ?? const Uuid().v4(),
      userId: userId,
      title: (raw['title'] as String?) ?? (raw['id'] as String?) ?? '',
      content: (raw['content'] as String?) ?? '',
      createdAt: parse(raw['created_at'] as String?, fallbackTime),
      updatedAt: parse(raw['updated_at'] as String?, fallbackTime),
      isDeleted: raw['is_deleted'] as bool? ?? false,
      isSynced: false,
      version: BigInt.from(raw['version'] as int? ?? 1),
      isFavorite: raw['is_favorite'] as bool? ?? false,
      isPinned: raw['is_pinned'] as bool? ?? false,
      noteType: noteType,
      folderId: raw['folder_id'] as String? ?? folderId,
    );
  }
}
