import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/theme.dart';

class ImportFileEntry {
  const ImportFileEntry({
    required this.name,
    required this.content,
  });

  final String name;
  final String content;

  String get title {
    final lastSlash = name.lastIndexOf(RegExp(r'[/\\]'));
    final base = lastSlash == -1 ? name : name.substring(lastSlash + 1);
    return base.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
  }

  String get preview {
    final trimmed = content.trim();
    if (trimmed.length <= 120) return trimmed;
    return '${trimmed.substring(0, 120)}…';
  }
}

/// Shows a bottom sheet previewing the selected files and returns `true` if
/// the user confirms the import.
Future<bool> showImportPreviewSheet(
  BuildContext context, {
  required List<ImportFileEntry> files,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ImportPreviewSheet(files: files),
  );
  return result ?? false;
}

class _ImportPreviewSheet extends StatelessWidget {
  const _ImportPreviewSheet({required this.files});

  final List<ImportFileEntry> files;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                'Import ${files.length} ${files.length == 1 ? 'note' : 'notes'}',
                style: context.sectionTitle,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const Divider(
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                  ),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: palette.accentContainer,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.small),
                            ),
                            child: Icon(
                              Icons.description_outlined,
                              color: palette.accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.title,
                                  style: context.bodyText.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (file.preview.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    file.preview,
                                    style: context.metadataText.copyWith(
                                      height: 1.4,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Import'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
