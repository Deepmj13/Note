import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/theme.dart';
import 'package:note_v4/ui/widgets/entrance.dart';

enum CreateAction { textNote, checklist, import }

Future<CreateAction?> showNoteCreationSheet(BuildContext context) {
  return showModalBottomSheet<CreateAction>(
    context: context,
    builder: (context) => const _NoteCreationSheet(),
  );
}

class _NoteCreationSheet extends StatelessWidget {
  const _NoteCreationSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
                child: Text('Create note', style: context.sectionTitle),
              ),
              const SizedBox(height: AppSpacing.xs),
              Entrance(
                index: 0,
                child: _CreateOption(
                  icon: Icons.edit_note,
                  color: palette.accentContainer,
                  iconColor: palette.accent,
                  title: 'Text note',
                  subtitle: 'Capture your thoughts',
                  onTap: () => Navigator.pop(context, CreateAction.textNote),
                ),
              ),
              Entrance(
                index: 1,
                child: _CreateOption(
                  icon: Icons.checklist,
                  color: palette.accentContainer,
                  iconColor: palette.accent,
                  title: 'Checklist',
                  subtitle: 'Track tasks and to-dos',
                  onTap: () => Navigator.pop(context, CreateAction.checklist),
                ),
              ),
              Entrance(
                index: 2,
                child: const _CreateOption(
                  icon: Icons.gesture,
                  color: Color(0xFFFFF3E0),
                  iconColor: Color(0xFFB26A00),
                  title: 'Drawing',
                  subtitle: 'Coming soon',
                  enabled: false,
                ),
              ),
              Entrance(
                index: 3,
                child: _CreateOption(
                  icon: Icons.file_upload_outlined,
                  color: const Color(0xFFE8F5E9),
                  iconColor: const Color(0xFF2E7D32),
                  title: 'Import from file',
                  subtitle: 'Import .txt files as notes',
                  onTap: () => Navigator.pop(context, CreateAction.import),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.bodyText),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: context.metadataText,
                        ),
                      ],
                    ],
                  ),
                ),
                if (enabled)
                  Icon(
                    Icons.chevron_right,
                    color: palette.disabledText,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
