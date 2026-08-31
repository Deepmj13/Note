import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_page_route.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/data/export/note_importer.dart';
import 'package:note_v4/data/export/note_share.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/providers/folders_notifier.dart';
import 'package:note_v4/providers/notes_notifier.dart';
import 'package:note_v4/providers/settings_providers.dart';
import 'package:note_v4/theme.dart';
import 'package:note_v4/ui/screens/editor_screen.dart';
import 'package:note_v4/ui/screens/folders_screen.dart';
import 'package:note_v4/ui/screens/settings_screen.dart';
import 'package:note_v4/ui/widgets/confirm_sheet.dart';
import 'package:note_v4/ui/widgets/empty_state.dart';
import 'package:note_v4/ui/widgets/entrance.dart';
import 'package:note_v4/ui/widgets/folder_picker_sheet.dart';
import 'package:note_v4/ui/widgets/folder_name_dialog.dart';
import 'package:note_v4/ui/widgets/folders_view.dart';
import 'package:note_v4/ui/widgets/import_preview_sheet.dart';
import 'package:note_v4/ui/widgets/note_card.dart';
import 'package:note_v4/ui/widgets/note_creation_sheet.dart';
import 'package:note_v4/ui/widgets/selection_bar.dart';
import 'package:note_v4/ui/widgets/section_header.dart';
import 'package:note_v4/ui/widgets/skeleton_card.dart';
import 'package:note_v4/ui/widgets/note_options_sheet.dart';
import 'package:note_v4/ui/widgets/pressable_scale.dart';
import 'package:note_v4/ui/widgets/sync_status_banner.dart';
import 'package:uuid/uuid.dart';

enum _HomeFilter { all, favorites }

enum _NoteSort { updated, created, title }

enum _MoreAction { sort, folders, settings }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.folderId, this.folderName});

  final String? folderId;
  final String? folderName;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  String _query = '';
  bool _searchActive = false;
  _NoteSort _sort = _NoteSort.updated;
  _HomeFilter _filter = _HomeFilter.all;

  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  bool _isWide = false;
  int _railIndex = 0;
  String? _activeFolderId;
  String? _activeFolderName;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _folderFilterMode =>
      _isWide ? _activeFolderId != null : widget.folderId != null;

  String? get _folderFilter => _isWide ? _activeFolderId : widget.folderId;

  String? get _folderFilterName =>
      _isWide ? _activeFolderName : widget.folderName;

  bool get _favoritesOnly =>
      _isWide ? _railIndex == 1 : _filter == _HomeFilter.favorites;

  bool get _searching => _searchActive || _query.isNotEmpty;

  // ---- Filtering & sorting ----

  List<Note> _applyFilter(List<Note> notes) {
    var result = notes;
    final folder = _folderFilter;
    if (folder != null) {
      result = result.where((n) => n.folderId == folder).toList();
    } else if (_favoritesOnly) {
      result = result.where((n) => n.isFavorite).toList();
    }

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where(
            (n) =>
                n.title.toLowerCase().contains(q) ||
                n.content.toLowerCase().contains(q),
          )
          .toList();
    }

    final sorted = [...result];
    switch (_sort) {
      case _NoteSort.updated:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _NoteSort.created:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _NoteSort.title:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return sorted;
  }

  // ---- Header ----

  Widget _buildHeader(Map<String, String> folderNames) {
    final palette = context.palette;

    final Widget header;
    if (_selectionMode) {
      header = Padding(
        key: const ValueKey('header-selection'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          0,
        ),
        child: SelectionBar(
          count: _selected.length,
          onClose: () => setState(_selected.clear),
          onToggleFavorite: _favoriteSelected,
          onPin: _pinSelected,
          onMove: () => _moveSelected(folderNames),
          onDelete: _deleteSelected,
        ),
      );
    } else if (_searching) {
      header = Padding(
        key: const ValueKey('header-search'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.md, 0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Exit search',
              onPressed: _exitSearch,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: palette.divider),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search notes…',
                    icon: Icon(Icons.search, color: palette.secondaryText),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _clearSearch,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      final isFolder = _folderFilterMode;
      final title = isFolder
          ? (_folderFilterName ?? 'Notes')
          : _isWide
          ? _railTitle
          : 'Notes';
      final subtitle = isFolder
          ? 'Folder'
          : _isWide
          ? _railSubtitle
          : '';

      header = Padding(
        key: const ValueKey('header-normal'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            if (isFolder && !_isWide)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.screenTitle),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.secondaryText),
                  ],
                ],
              ),
            ),
            _HeaderIconButton(
              icon: Icons.search,
              tooltip: 'Search',
              onPressed: () => setState(() => _searchActive = true),
            ),
            _HeaderIconButton(
              icon: Icons.swap_vert,
              tooltip: 'Sort',
              onPressed: _showSortSheet,
            ),
            _HeaderIconButton(
              icon: Icons.more_vert,
              tooltip: 'More',
              onPressed: () => _showMoreMenu(folderNames),
            ),
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: AppDuration.quick,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: header,
    );
  }

  String get _railTitle {
    if (_activeFolderId != null) return _activeFolderName ?? 'Folder';
    switch (_railIndex) {
      case 1:
        return 'Favorites';
      case 2:
        return 'Folders';
      default:
        return 'All Notes';
    }
  }

  String get _railSubtitle {
    if (_activeFolderId != null) return 'Folder';
    switch (_railIndex) {
      case 1:
        return 'Your starred notes';
      case 2:
        return 'Organize your notes';
      default:
        return '';
    }
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          _PillChip(
            label: 'All',
            selected: _filter == _HomeFilter.all,
            onTap: () => setState(() => _filter = _HomeFilter.all),
          ),
          const SizedBox(width: AppSpacing.xs),
          _PillChip(
            label: 'Favorites',
            selected: _filter == _HomeFilter.favorites,
            onTap: () => setState(() => _filter = _HomeFilter.favorites),
          ),
          const SizedBox(width: AppSpacing.xs),
          _PillChip(
            label: 'Folders',
            selected: false,
            onTap: () {
              setState(() => _filter = _HomeFilter.all);
              Navigator.of(context).push(
                appPageRoute(const FoldersScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value);
    });
    setState(() {}); // refresh clear button
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _query = '');
  }

  void _exitSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _searchActive = false;
    });
  }

  // ---- Sort & more ----

  Future<void> _showSortSheet() async {
    final result = await showModalBottomSheet<_NoteSort>(
      context: context,
      builder: (context) {
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
                  child: Text('Sort by', style: context.sectionTitle),
                ),
                _SortOption(
                  label: 'Recently modified',
                  icon: Icons.schedule,
                  selected: _sort == _NoteSort.updated,
                  onTap: () => Navigator.pop(context, _NoteSort.updated),
                ),
                _SortOption(
                  label: 'Created date',
                  icon: Icons.event,
                  selected: _sort == _NoteSort.created,
                  onTap: () => Navigator.pop(context, _NoteSort.created),
                ),
                _SortOption(
                  label: 'Alphabetical',
                  icon: Icons.sort_by_alpha,
                  selected: _sort == _NoteSort.title,
                  onTap: () => Navigator.pop(context, _NoteSort.title),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result != null && mounted) setState(() => _sort = result);
  }

  Future<void> _showMoreMenu(Map<String, String> folderNames) async {
    final result = await showModalBottomSheet<_MoreAction>(
      context: context,
      builder: (context) => SafeArea(
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
                child: Text('More', style: context.sectionTitle),
              ),
              _SheetActionRow(
                icon: Icons.swap_vert,
                label: 'Sort notes',
                onTap: () => Navigator.pop(context, _MoreAction.sort),
              ),
              _SheetActionRow(
                icon: Icons.folder_outlined,
                label: 'Folders',
                onTap: () => Navigator.pop(context, _MoreAction.folders),
              ),
              _SheetActionRow(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => Navigator.pop(context, _MoreAction.settings),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _MoreAction.sort:
        await _showSortSheet();
      case _MoreAction.folders:
        Navigator.of(context).push(
          appPageRoute(const FoldersScreen()),
        );
      case _MoreAction.settings:
        Navigator.of(context).push(
          appPageRoute(const SettingsScreen()),
        );
    }
  }

  // ---- Context Menu ----

  Future<void> _showNoteOptions(Note note) async {
    final option = await showNoteOptionsSheet(context, note: note);
    if (option == null || !mounted) return;

    final notifier = ref.read(notesNotifierProvider.notifier);
    switch (option) {
      case NoteOption.favorite:
        notifier.setFavorite(note.id, !note.isFavorite);
      case NoteOption.pin:
        notifier.setPinned(note.id, !note.isPinned);
      case NoteOption.move:
        final folders = ref.read(foldersNotifierProvider).valueOrNull ?? const <Folder>[];
        final folderNames = {for (final f in folders) f.id: f.name};
        await _moveSingleNoteToFolder(note, folderNames);
      case NoteOption.select:
        setState(() => _selected.add(note.id));
      case NoteOption.share:
        await NoteShare.shareNote(note);
      case NoteOption.export:
        await NoteShare.exportJson([note]);
    }
  }

  Future<void> _moveSingleNoteToFolder(
    Note note,
    Map<String, String> folderNames,
  ) async {
    final result = await showFolderPickerSheet(context);
    if (result == null || !mounted) return;

    final notifier = ref.read(notesNotifierProvider.notifier);
    final previousFolderId = note.folderId;
    await notifier.moveToFolder(note.id, result.folderId);

    final folderName = result.folderId == null
        ? 'No folder'
        : folderNames[result.folderId] ?? 'folder';
    _showUndo('Moved to $folderName', () {
      notifier.moveToFolder(note.id, previousFolderId);
    });
  }

  // ---- Selection actions ----

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  List<Note> _selectedNotes() {
    final notes = ref.read(notesNotifierProvider).value ?? const <Note>[];
    return notes.where((n) => _selected.contains(n.id)).toList();
  }

  void _favoriteSelected() {
    final selectedNotes = _selectedNotes();
    if (selectedNotes.isEmpty) return;
    final allFavorite =
        selectedNotes.every((n) => n.isFavorite);
    final target = !allFavorite;
    for (final note in selectedNotes) {
      ref
          .read(notesNotifierProvider.notifier)
          .setFavorite(note.id, target);
    }
  }

  void _pinSelected() {
    final selectedNotes = _selectedNotes();
    if (selectedNotes.isEmpty) return;
    final allPinned = selectedNotes.every((n) => n.isPinned);
    final target = !allPinned;
    for (final note in selectedNotes) {
      ref.read(notesNotifierProvider.notifier).setPinned(note.id, target);
    }
  }

  Future<void> _moveSelected(Map<String, String> folderNames) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final previous = <String, String?>{};
    final notes = ref.read(notesNotifierProvider).value ?? const <Note>[];
    for (final note in notes) {
      if (ids.contains(note.id)) previous[note.id] = note.folderId;
    }

    final result = await showFolderPickerSheet(context);
    if (result == null || !mounted) return;

    final notifier = ref.read(notesNotifierProvider.notifier);
    for (final id in ids) {
      await notifier.moveToFolder(id, result.folderId);
    }
    setState(_selected.clear);

    final folderName = result.folderId == null
        ? 'No folder'
        : folderNames[result.folderId] ?? 'folder';
    _showUndo('Moved ${ids.length} note${ids.length == 1 ? '' : 's'} to $folderName', () {
      for (final entry in previous.entries) {
        notifier.moveToFolder(entry.key, entry.value);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final confirmed = await showConfirmSheet(
      context,
      title: 'Delete ${ids.length} note${ids.length == 1 ? '' : 's'}?',
      message: 'The notes will be moved to trash and can be restored later.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline,
    );
    if (!confirmed || !mounted) return;

    final notifier = ref.read(notesNotifierProvider.notifier);
    for (final id in ids) {
      notifier.deleteNote(id);
    }
    setState(_selected.clear);
    _showUndo('${ids.length} note${ids.length == 1 ? '' : 's'} deleted', () {
      for (final id in ids) {
        notifier.restoreNote(id);
      }
    });
  }

  void _showUndo(String message, VoidCallback onUndo) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'UNDO', onPressed: onUndo),
      ),
    );
  }

  // ---- Creation ----

  /// Creates a note of the persisted default type directly (fast path),
  /// while [showNoteCreationSheet] still offers an explicit Text/Checklist
  /// override.
  void _createNoteOfDefaultType() {
    final defaultType = ref.read(defaultNoteTypeProvider);
    final type = switch (defaultType) {
      AppNoteType.text => NoteType.text,
      AppNoteType.checklist => NoteType.checklist,
    };
    Navigator.of(context).push(
      appPageRoute(EditorScreen(noteType: type, folderId: _folderFilter)),
    );
  }

  Future<void> _openCreateSheet() async {
    final action = await showNoteCreationSheet(context);
    if (action == null || !mounted) return;
    switch (action) {
      case CreateAction.textNote:
        Navigator.of(context).push(
          appPageRoute(
            EditorScreen(
              noteType: NoteType.text,
              folderId: _folderFilter,
            ),
          ),
        );
      case CreateAction.checklist:
        Navigator.of(context).push(
          appPageRoute(
            EditorScreen(
              noteType: NoteType.checklist,
              folderId: _folderFilter,
            ),
          ),
        );
      case CreateAction.import:
        await _importFromFiles();
    }
  }

  Future<void> _importFromFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'json'],
    );
    if (result.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    final userId = ref.read(currentUserIdProvider) ?? '';
    final entries = <ImportFileEntry>[];
    final notes = <Note>[];
    var baseTime = DateTime.now();

    for (final file in result) {
      try {
        final bytes = await file.readAsBytes();
        final content = String.fromCharCodes(bytes);
        final isJson = file.name.toLowerCase().endsWith('.json');
        if (isJson) {
          final parsed = NoteImporter.fromJson(
            content,
            userId: userId,
            folderId: _folderFilter,
          );
          if (parsed.isEmpty) {
            messenger.showSnackBar(
              SnackBar(content: Text('No notes found in "${file.name}"')),
            );
            continue;
          }
          for (final note in parsed) {
            notes.add(note);
            entries.add(
              ImportFileEntry(
                name: '${note.title.isNotEmpty ? note.title : 'Untitled note'}.txt',
                content: note.content,
              ),
            );
          }
        } else {
          final entry = ImportFileEntry(name: file.name, content: content);
          entries.add(entry);
          final note = Note(
            id: const Uuid().v4(),
            userId: userId,
            title: entry.title,
            content: content,
            createdAt: baseTime,
            updatedAt: baseTime,
            isDeleted: false,
            isSynced: false,
            version: BigInt.from(1),
            isFavorite: false,
            isPinned: false,
            noteType: NoteType.text,
            folderId: _folderFilter,
          );
          baseTime = baseTime.add(const Duration(seconds: 1));
          notes.add(note);
        }
      } on NoteImportException catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('${file.name}: ${e.message}')),
        );
      } catch (_) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Could not read "${file.name}"')),
        );
      }
    }
    if (entries.isEmpty || !mounted) return;

    final confirmed = await showImportPreviewSheet(
      context,
      files: entries,
    );
    if (!confirmed || !mounted) return;
    if (notes.isEmpty) return;

    messenger.showSnackBar(
      const SnackBar(content: Text('Importing notes…')),
    );

    await ref.read(notesNotifierProvider.notifier).importNotes(notes);

    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${notes.length} ${notes.length == 1 ? 'note' : 'notes'} imported',
          ),
        ),
      );
    }
  }

  void _openNote(Note note) {
    Navigator.of(context).push(
      appPageRoute(EditorScreen(note: note)),
    );
  }

  // ---- Content ----

  Widget _buildNotesArea(
    AsyncValue<List<Note>> notesAsync,
    Map<String, String> folderNames,
  ) {
    return notesAsync.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          96,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
          child: SkeletonCard(),
        ),
      ),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: "Couldn't load notes",
        message: 'Something went wrong while loading your notes.',
      ),
      data: (allNotes) {
        final notes = _applyFilter(allNotes);
        if (notes.isEmpty) return _buildEmptyState();

        final folderFilter = _folderFilter;
        final showRecentHeader =
            !_searching && !_favoritesOnly && folderFilter == null && _isWide == false;

        return CustomScrollView(
          slivers: [
            if (showRecentHeader)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: AppSpacing.lg),
                  child: SectionHeader(title: 'Recent'),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                96,
              ),
              sliver: SliverList.separated(
                itemCount: notes.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final note = notes[index];
                  final isSelected = _selected.contains(note.id);
                  return Entrance(
                    key: ValueKey('note-${note.id}'),
                    index: index,
                    child: PressableScale(
                      onTap: () {
                        if (_selectionMode) {
                          _toggleSelect(note.id);
                        } else {
                          _openNote(note);
                        }
                      },
                      onLongPress: () => _showNoteOptions(note),
                      child: NoteCard(
                        note: note,
                        selectionMode: _selectionMode,
                        selected: isSelected,
                        highlight: _query,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    if (_searching) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No results',
        message: 'No notes match "$_query".',
        actionLabel: 'Clear search',
        onAction: _exitSearch,
      );
    }
    if (_folderFilterMode) {
      return EmptyState(
        icon: Icons.folder_open,
        title: 'This folder is empty',
        message: 'Move or create a note here.',
        actionLabel: 'Create a note',
        onAction: _openCreateSheet,
      );
    }
    return EmptyState(
      icon: Icons.edit_note,
      title: 'No notes yet',
      message: 'Capture your ideas, tasks and thoughts.',
      actionLabel: 'Create your first note',
      onAction: _openCreateSheet,
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    _isWide = MediaQuery.sizeOf(context).width >= 720;

    final notesAsync = ref.watch(notesNotifierProvider);
    final foldersAsync = ref.watch(foldersNotifierProvider);

    final folders = foldersAsync.valueOrNull ?? const <Folder>[];
    final folderNames = {for (final f in folders) f.id: f.name};

    if (_isWide) return _buildWide(notesAsync, folderNames);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(folderNames),
            const SyncStatusBanner(),
            if (!_searching &&
                !_selectionMode &&
                widget.folderId == null &&
                !_isWide)
              _buildFilterChips(),
            Expanded(child: _buildNotesArea(notesAsync, folderNames)),
          ],
        ),
      ),
      floatingActionButton: _selectionMode ? null : _buildFab(),
    );
  }

  Widget _buildFab() {
    final palette = context.palette;
    return FloatingActionButton.extended(
      tooltip: 'New note',
      onPressed: _createNoteOfDefaultType,
      icon: const Icon(Icons.add),
      label: const Text('Create'),
      elevation: 2.0,
      backgroundColor: palette.surface,
      foregroundColor: palette.accent,
    );
  }

  Widget _buildWide(
    AsyncValue<List<Note>> notesAsync,
    Map<String, String> folderNames,
  ) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _railIndex,
              onDestinationSelected: (index) {
                _debounce?.cancel();
                _searchController.clear();
                setState(() {
                  _query = '';
                  _searchActive = false;
                  _railIndex = index;
                  _activeFolderId = null;
                  _activeFolderName = null;
                });
              },
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Icon(
                  Icons.edit_note,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.sticky_note_2_outlined),
                  selectedIcon: Icon(Icons.sticky_note_2),
                  label: Text('All'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.star_outline),
                  selectedIcon: Icon(Icons.star),
                  label: Text('Favorites'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: Text('Folders'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(folderNames),
                  const SyncStatusBanner(),
                  Expanded(
                    child:
                        _railIndex == 2 && _activeFolderId == null
                            ? FoldersView(
                                compact: true,
                                onFolderTap: (folder) {
                                  _debounce?.cancel();
                                  _searchController.clear();
                                  setState(() {
                                    _query = '';
                                    _searchActive = false;
                                    _activeFolderId = folder.id;
                                    _activeFolderName = folder.name;
                                  });
                                },
                                onCreateFolder: _createFolderInline,
                              )
                            : _buildNotesArea(notesAsync, folderNames),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          _selectionMode || (_railIndex == 2 && _activeFolderId == null)
          ? null
          : _buildFab(),
    );
  }

  Future<void> _createFolderInline() async {
    final name = await showFolderNameDialog(context);
    if (name == null || name.isEmpty || !mounted) return;
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

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 24),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(AppSpacing.xs),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.quick,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected ? palette.accentContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected
                ? palette.accent.withValues(alpha: 0.5)
                : palette.divider,
          ),
        ),
        child: Text(
          label,
          style: context.secondaryText.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? palette.accent : palette.secondaryText,
          ),
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
              Icon(
                icon,
                size: 22,
                color: selected ? palette.accent : palette.secondaryText,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: context.bodyText.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? palette.accent : palette.primaryText,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, size: 20, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  const _SheetActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
              Icon(icon, size: 22, color: palette.secondaryText),
              const SizedBox(width: AppSpacing.md),
              Text(label, style: context.bodyText),
            ],
          ),
        ),
      ),
    );
  }
}
