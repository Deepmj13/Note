import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/core/utils/date_format.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/theme.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    this.selected = false,
    this.selectionMode = false,
    this.highlight = '',
  });

  final Note note;
  final bool selected;
  final bool selectionMode;
  final String highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isSelected = selectionMode && selected;

    return AnimatedContainer(
      duration: AppDuration.micro,
      decoration: BoxDecoration(
        color: isSelected ? palette.accentContainer : palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isSelected
              ? palette.accent.withValues(alpha: 0.6)
              : palette.divider,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectionMode) ...[
            AnimatedScale(
              scale: isSelected ? 1 : 0.85,
              duration: AppDuration.quick,
              child: Icon(
                isSelected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: isSelected ? palette.accent : palette.disabledText,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title.isEmpty ? 'Untitled' : note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.noteTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: AppSpacing.xs),
                _Preview(note: note, highlight: highlight),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  NoteDateFormatter.dateTime(note.updatedAt),
                  style: context.metadataText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.note, required this.highlight});

  final Note note;
  final String highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (note.noteType == NoteType.checklist) {
      final checked = _countChecked(note.content);
      final total = _countItems(note.content);
      return Row(
        children: [
          Icon(
            checked == total && total > 0
                ? Icons.check_circle
                : Icons.checklist,
            size: 16,
            color: palette.secondaryText,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              total == 0 ? 'Checklist' : '$checked of $total completed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.metadataText.copyWith(fontSize: 13),
            ),
          ),
        ],
      );
    }

    final text = note.content.trim();
    if (text.isEmpty) {
      return Text(
        'No additional text',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.metadataText.copyWith(fontStyle: FontStyle.italic),
      );
    }

    return _HighlightedText(
      text: text,
      query: highlight,
      maxLines: 1,
      style: context.secondaryText.copyWith(fontSize: 13.5, height: 1.3),
    );
  }

  int _countItems(String content) {
    final lines = content.split('\n');
    var count = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[ ]') || trimmed.startsWith('[x]')) count++;
    }
    return count;
  }

  int _countChecked(String content) {
    final lines = content.split('\n');
    var count = 0;
    for (final line in lines) {
      if (line.trim().startsWith('[x]')) count++;
    }
    return count;
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.maxLines,
    required this.style,
  });

  final String text;
  final String query;
  final int maxLines;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (query.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (start < text.length) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            color: palette.accent,
            fontWeight: FontWeight.w700,
            backgroundColor: palette.accentContainer,
          ),
        ),
      );
      start = index + query.length;
    }

    return Text.rich(
      TextSpan(children: spans, style: style),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
