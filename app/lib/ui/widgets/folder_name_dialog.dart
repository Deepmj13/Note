import 'package:flutter/material.dart';

Future<String?> showFolderNameDialog(
  BuildContext context, {
  String title = 'New folder',
  String? initialValue,
  String confirmLabel = 'Create',
}) {
  final controller = TextEditingController(text: initialValue ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(hintText: 'Folder name'),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) {
          final trimmed = v.trim();
          if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final trimmed = controller.text.trim();
            if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
