import 'package:note_v4/data/export/note_exporter.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:share_plus/share_plus.dart';

/// Shares note content to the platform share sheet (web falls back to a
/// download). Supports both the single JSON/Markdown export and plain text
/// sharing.
class NoteShare {
  const NoteShare._();

  /// Shares [note] as a Markdown text document.
  static Future<void> shareNote(Note note) async {
    final markdown = NoteExporter.toMarkdown(note);
    final file = NoteExporter.asXFile(markdown, _safeFilename(note, '.md'));
    await SharePlus.instance.share(
      ShareParams(files: [file], fileNameOverrides: [file.name]),
    );
  }

  /// Exports [notes] as a single JSON document shared via the share sheet.
  static Future<void> exportJson(List<Note> notes) async {
    final json = NoteExporter.toJson(notes);
    final file = NoteExporter.asXFile(
      json,
      'notes_export_${_timestamp()}.json',
    );
    await SharePlus.instance.share(
      ShareParams(files: [file], fileNameOverrides: [file.name]),
    );
  }

  static String _safeFilename(Note note, String ext) {
    final base = note.title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filename = base.isEmpty ? 'note' : base;
    return '$filename$ext';
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
