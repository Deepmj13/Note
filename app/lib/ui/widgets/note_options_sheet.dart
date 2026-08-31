import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/theme.dart';
import 'package:note_v4/ui/widgets/entrance.dart';

enum NoteOption { favorite, pin, move, export, share, select }

Future<NoteOption?> showNoteOptionsSheet(
  BuildContext context, {
  required Note note,
}) {
  return showModalBottomSheet<NoteOption>(
    context: context,
    builder: (context) => _NoteOptionsSheet(note: note),
  );
}

class _NoteOptionsSheet extends StatelessWidget {
  const _NoteOptionsSheet({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Text('Note options', style: context.sectionTitle),
              ),
              const SizedBox(height: AppSpacing.xs),
              Entrance(
                index: 0,
                child: _GroupOption(
                  label: note.isFavorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  icon: note.isFavorite ? Icons.star : Icons.star_border,
                  onTap: () => Navigator.pop(context, NoteOption.favorite),
                ),
              ),
              Entrance(
                index: 1,
                child: _GroupOption(
                  label: note.isPinned ? 'Unpin' : 'Pin',
                  icon: note.isPinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  onTap: () => Navigator.pop(context, NoteOption.pin),
                ),
              ),
              Entrance(
                index: 2,
                child: _GroupOption(
                  label: 'Move',
                  icon: Icons.drive_file_move_outline,
                  onTap: () => Navigator.pop(context, NoteOption.move),
                ),
              ),
              const Divider(height: AppSpacing.xl),
              Entrance(
                index: 3,
                child: _GroupOption(
                  label: 'Share',
                  icon: Icons.share_outlined,
                  onTap: () => Navigator.pop(context, NoteOption.share),
                ),
              ),
              Entrance(
                index: 4,
                child: _GroupOption(
                  label: 'Export',
                  icon: Icons.ios_share,
                  onTap: () => Navigator.pop(context, NoteOption.export),
                ),
              ),
              Entrance(
                index: 5,
                child: _GroupOption(
                  label: 'Select',
                  icon: Icons.select_all,
                  onTap: () => Navigator.pop(context, NoteOption.select),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupOption extends StatelessWidget {
  const _GroupOption({required this.label, required this.icon, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = palette.primaryText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: foreground),
              const SizedBox(width: AppSpacing.md),
              Text(
                label,
                style: context.bodyText.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
