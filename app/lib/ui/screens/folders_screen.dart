import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_page_route.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/providers/folders_notifier.dart';
import 'package:note_v4/ui/screens/home_screen.dart';
import 'package:note_v4/ui/widgets/folders_view.dart';
import 'package:note_v4/ui/widgets/folder_name_dialog.dart';
import 'package:uuid/uuid.dart';

class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Folders'),
      ),
      body: FoldersView(
        onFolderTap: (folder) {
          Navigator.of(context).push(
            appPageRoute(
              HomeScreen(folderId: folder.id, folderName: folder.name),
            ),
          );
        },
        onCreateFolder: () => _createFolder(context, ref),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New folder',
        onPressed: () => _createFolder(context, ref),
        child: const Icon(Icons.create_new_folder_outlined),
      ),
    );
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final name = await showFolderNameDialog(context);
    if (name == null || name.isEmpty || !context.mounted) return;
    final id = const Uuid().v4();
    final now = DateTime.now();
    await ref.read(foldersNotifierProvider.notifier).addFolder(
      Folder(
        id: id,
        userId: '',
        name: name,
        parentFolderId: null,
        createdAt: now,
        updatedAt: now,
        isDeleted: false,
        isSynced: false,
      ),
    );
  }
}
