import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:note_v4/core/models/note_block.dart';
import 'package:note_v4/data/local/database.dart';

/// Formats notes into the standard JSON export schema and Markdown.
///
/// See `implementation.md` for the JSON contract. Markdown mirrors the note
/// title and content (with checklist lines rendered as `- [ ]` / `- [x]`).
class NoteExporter {
  const NoteExporter._();

  static const String appVersion = '1.0.0';

  /// Builds the JSON export payload for [notes].
  static String toJson(List<Note> notes) {
    final payload = {
      'app_version': appVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'notes': notes.map(_noteJson).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Builds a Markdown document for a single [note].
  static String toMarkdown(Note note) {
    final buffer = StringBuffer();
    if (note.title.trim().isNotEmpty) {
      buffer.writeln('# ${note.title}');
      buffer.writeln();
    }
    if (NoteBlock.isEncoded(note.content)) {
      for (final block in NoteBlock.fromStorage(note.content)) {
        final line = block.toMarkdown();
        if (line.isEmpty) continue;
        buffer.writeln(line.trimRight());
      }
      return buffer.toString().trimRight();
    }
    if (note.noteType == NoteType.checklist) {
      for (final line in note.content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('[x]')) {
          buffer.writeln('- [x] ${trimmed.substring(3).trim()}');
        } else if (trimmed.startsWith('[ ]')) {
          buffer.writeln('- [ ] ${trimmed.substring(3).trim()}');
        } else {
          buffer.writeln(trimmed);
        }
      }
    } else if (note.content.trim().isNotEmpty) {
      buffer.writeln(note.content);
    }
    return buffer.toString().trimRight();
  }

  /// Builds a single Markdown document containing every [note] in sequence.
  static String toMarkdownAll(List<Note> notes) {
    final buffer = StringBuffer();
    for (final note in notes) {
      buffer.write(toMarkdown(note));
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  static Map<String, dynamic> _noteJson(Note n) => {
        'id': n.id,
        'title': n.title,
        'content': n.content,
        'created_at': n.createdAt.toUtc().toIso8601String(),
        'updated_at': n.updatedAt.toUtc().toIso8601String(),
        'is_deleted': n.isDeleted,
        'version': n.version.toInt(),
        'note_type': n.noteType.name,
        'is_favorite': n.isFavorite,
        'is_pinned': n.isPinned,
        'folder_id': n.folderId,
      };

  /// Returns a name-appropriate, cross-platform file representation for
  /// [content]. Byte-based so it works on mobile, desktop and web without an
  /// intermediate filesystem path.
  static XFile asXFile(String content, String filename) {
    return XFile.fromData(
      utf8.encode(content),
      name: filename,
      mimeType: filename.endsWith('.json') ? 'application/json' : 'text/markdown',
    );
  }
}
