import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/data/export/note_share.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/providers/notes_notifier.dart';
import 'package:note_v4/theme.dart';
import 'package:note_v4/ui/widgets/entrance.dart';
import 'package:note_v4/ui/widgets/folder_picker_sheet.dart';
import 'package:note_v4/ui/widgets/note_options_sheet.dart';
import 'package:uuid/uuid.dart';

enum _SaveStatus { idle, saving, saved }

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, this.note, this.noteType, this.folderId});

  final Note? note;
  final NoteType? noteType;
  final String? folderId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _CheckItem {
  _CheckItem({required this.done, required this.text})
      : id = const Uuid().v4();

  final String id;
  bool done;
  String text;
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode();

  void syncController() {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late Note _note;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  final TextEditingController _addItemController = TextEditingController();

  final List<_CheckItem> _items = [];
  Timer? _debounce;
  _SaveStatus _status = _SaveStatus.idle;
  bool _inserted = false;
  bool _disposed = false;
  bool _allowPop = false;

  bool get _isChecklist => _note.noteType == NoteType.checklist;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _note =
        widget.note ??
        Note(
          id: const Uuid().v4(),
          userId: ref.read(currentUserIdProvider) ?? '',
          title: '',
          content: '',
          createdAt: now,
          updatedAt: now,
          isDeleted: false,
          isSynced: false,
          version: BigInt.from(1),
          isFavorite: false,
          isPinned: false,
          noteType: widget.noteType ?? NoteType.text,
          folderId: widget.folderId,
        );
    _inserted = widget.note != null;

    _titleController = TextEditingController(text: _note.title);
    _bodyController = TextEditingController(text: _note.content);

    if (_isChecklist) {
      _loadChecklist(_note.content);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    _addItemController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  // ---- Checklist helpers ----

  void _loadChecklist(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final done = trimmed.startsWith('[x]');
      final text = done
          ? trimmed.substring(3).trim()
          : trimmed.startsWith('[ ]')
          ? trimmed.substring(3).trim()
          : trimmed;
      final item = _CheckItem(done: done, text: text);
      item.syncController();
      _items.add(item);
    }
  }

  String _checklistContent() {
    final buffer = StringBuffer();
    for (final item in _items) {
      buffer.writeln(
        '${item.done ? '[x]' : '[ ]'} ${item.text.trim()}',
      );
    }
    return buffer.toString().trimRight();
  }

  void _addCheckItem(String text, {bool focus = true}) {
    final item = _CheckItem(done: false, text: text);
    setState(() => _items.add(item));
    _markDirty();
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) item.focusNode.requestFocus();
      });
    }
  }

  void _removeCheckItem(int index) {
    final item = _items.removeAt(index);
    item.dispose();
    setState(() {});
    _markDirty();
  }

  void _insertCheckItemAfter(int index) {
    final item = _CheckItem(done: false, text: '');
    setState(() {
      _items.insert(index + 1, item);
    });
    _markDirty();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) item.focusNode.requestFocus();
    });
  }

  // ---- Autosave ----

  void _markDirty() {
    _debounce?.cancel();
    if (mounted) setState(() => _status = _SaveStatus.saving);
    _debounce = Timer(const Duration(milliseconds: 800), _persistNow);
  }

  Future<void> _persistNow() async {
    final title = _titleController.text.trim();
    final content = _isChecklist ? _checklistContent() : _bodyController.text;

    final hasContent = title.isNotEmpty ||
        (_isChecklist
            ? _items.any((i) => i.text.trim().isNotEmpty || i.done)
            : content.trim().isNotEmpty);

    if (!_inserted && !hasContent) {
      if (mounted) setState(() => _status = _SaveStatus.saved);
      return;
    }

    final now = DateTime.now();
    final updated = _note.copyWith(
      title: title,
      content: content,
      updatedAt: now,
      version: _note.version + BigInt.one,
    );

    final notifier = ref.read(notesNotifierProvider.notifier);
    if (_inserted) {
      await notifier.updateNote(updated);
    } else {
      await notifier.addNote(updated);
      _inserted = true;
    }
    _note = updated;

    if (mounted && !_disposed) {
      setState(() => _status = _SaveStatus.saved);
    }
  }

  Future<void> _flushAndPop() async {
    _debounce?.cancel();
    await _persistNow();
    _allowPop = true;
    if (mounted && !_disposed) Navigator.of(context).pop();
  }

  // ---- Note options ----

  Future<void> _handleOption(NoteOption option) async {
    switch (option) {
      case NoteOption.favorite:
        setState(() {
          _note = _note.copyWith(isFavorite: !_note.isFavorite);
        });
        _markDirty();
      case NoteOption.pin:
        setState(() {
          _note = _note.copyWith(isPinned: !_note.isPinned);
        });
        _markDirty();
      case NoteOption.move:
        final result = await showFolderPickerSheet(
          context,
          currentFolderId: _note.folderId,
        );
        if (result == null || !mounted) return;
        setState(() {
          _note = _note.copyWith(folderId: Value(result.folderId));
        });
        await ref
            .read(notesNotifierProvider.notifier)
            .moveToFolder(_note.id, result.folderId);
      case NoteOption.select:
        break;
      case NoteOption.share:
        await _persistNow();
        await NoteShare.shareNote(_note);
      case NoteOption.export:
        await _persistNow();
        await NoteShare.exportJson([_note]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _flushAndPop();
      },
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: AnimatedSwitcher(
            duration: AppDuration.micro,
            child: Text(
              _status == _SaveStatus.saving ? 'Saving…' : 'Saved',
              key: ValueKey(_status),
              style: context.metadataText.copyWith(
                color: _status == _SaveStatus.saving
                    ? palette.secondaryText
                    : palette.disabledText,
              ),
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More options',
              onPressed: () async {
                final option = await showNoteOptionsSheet(context, note: _note);
                if (option != null && mounted) {
                  await _handleOption(option);
                }
              },
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
            ),
            child: _isChecklist ? _buildChecklist() : _buildTextEditor(),
          ),
        ),
      ),
    );
  }

  Widget _buildTextEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _titleController,
          onChanged: (_) => _markDirty(),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: context.palette.primaryText,
          ),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Title'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: TextField(
            controller: _bodyController,
            onChanged: (_) => _markDirty(),
            maxLines: null,
            minLines: null,
            keyboardType: TextInputType.multiline,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            style: context.bodyText.copyWith(fontSize: 16.5),
            decoration: const InputDecoration(hintText: 'Start writing…'),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklist() {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _titleController,
          onChanged: (_) => _markDirty(),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: palette.primaryText,
          ),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Title'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: _items.length + 1,
            itemBuilder: (context, index) {
              if (index == _items.length) {
                return _buildAddItemRow();
              }
              return _buildCheckItemRow(index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCheckItemRow(int index) {
    final palette = context.palette;
    final item = _items[index];
    return Entrance(
      key: ValueKey('check-${item.id}'),
      index: index,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: GestureDetector(
              onTap: () {
                setState(() => item.done = !item.done);
                _markDirty();
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedScale(
                scale: item.done ? 1 : 0.9,
                duration: AppDuration.quick,
                child: Icon(
                  item.done
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: item.done ? palette.success : palette.disabledText,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              controller: item.controller,
              focusNode: item.focusNode,
              onChanged: (value) {
                item.text = value;
                _markDirty();
              },
              onSubmitted: (_) => _insertCheckItemAfter(index),
              textCapitalization: TextCapitalization.sentences,
              style: context.bodyText.copyWith(
                decoration: item.done ? TextDecoration.lineThrough : null,
                decorationColor: palette.secondaryText,
                color: item.done ? palette.secondaryText : palette.primaryText,
              ),
              decoration: InputDecoration(
                hintText: 'Item',
                hintStyle: context.secondaryText.copyWith(
                  color: palette.disabledText,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: palette.disabledText,
            tooltip: 'Remove item',
            onPressed: () => _removeCheckItem(index),
          ),
        ],
      ),
    );
  }

  Widget _buildAddItemRow() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Icon(Icons.add, size: 22, color: palette.disabledText),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: _addItemController,
              onSubmitted: (value) {
                _addCheckItem(value.trim());
              },
              textCapitalization: TextCapitalization.sentences,
              style: context.bodyText,
              decoration: InputDecoration(
                hintText: 'Add item',
                hintStyle: context.secondaryText.copyWith(
                  color: palette.disabledText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
