import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/core/models/note_block.dart';
import 'package:note_v4/data/export/note_share.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/providers/notes_notifier.dart';
import 'package:note_v4/theme.dart';
import 'package:note_v4/ui/widgets/editor/block_row.dart';
import 'package:note_v4/ui/widgets/editor/block_toolbar.dart';
import 'package:note_v4/ui/widgets/entrance.dart';
import 'package:note_v4/ui/widgets/folder_picker_sheet.dart';
import 'package:note_v4/ui/widgets/note_options_sheet.dart';
import 'package:uuid/uuid.dart';

enum _SaveStatus { idle, saving, saved }

/// A block-based hybrid editor: one surface where text, headings, bullets and
/// checklists mix freely. The document is a JSON array of [NoteBlock]s stored
/// in `Note.content` (with lazy migration of legacy plain-text notes).
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, this.note, this.noteType, this.folderId});

  final Note? note;
  final NoteType? noteType;
  final String? folderId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _BlockUi {
  _BlockUi(NoteBlock block)
      : controller = TextEditingController(text: block.content),
        focusNode = FocusNode(),
        anchorKey = GlobalKey();

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Anchors the slash-menu popup to this block's row.
  final GlobalKey anchorKey;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late Note _note;
  late final TextEditingController _titleController;

  final List<NoteBlock> _blocks = [];
  final Map<String, _BlockUi> _uis = {};

  Timer? _debounce;
  _SaveStatus _status = _SaveStatus.idle;
  bool _inserted = false;
  bool _disposed = false;
  bool _allowPop = false;
  int? _focusedIndex;

  // ---- Undo / redo (in-memory document snapshots) ----

  static const int _historyLimit = 100;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  /// Coalesces a fast typing burst into a single undo step: a new snapshot is
  /// only pushed when the user starts typing in a new block or pauses.
  DateTime? _lastEditAt;
  int? _lastEditedIndex;
  static const _burstGap = Duration(milliseconds: 800);

  /// While non-null, the block whose content is exactly "/" and whose slash
  /// menu is (or was) open.
  String? _slashBlockId;

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

    final loaded = NoteBlock.fromStorage(_note.content);
    _blocks.addAll(loaded.isEmpty ? [NoteBlock.ofType(BlockType.text)] : loaded);
    for (final block in _blocks) {
      _ensureUi(block);
    }

    HardwareKeyboard.instance.addHandler(_onGlobalKeyEvent);

    if (!_inserted && _blocks.length == 1 && _blocks.first.content.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposed) _focusBlock(0);
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_onGlobalKeyEvent);
    _titleController.dispose();
    for (final ui in _uis.values) {
      ui.focusNode.removeListener(_onFocusChanged);
      ui.dispose();
    }
    super.dispose();
  }

  // ---- Block helpers ----

  _BlockUi _ensureUi(NoteBlock block) {
    return _uis.putIfAbsent(block.id, () {
      final ui = _BlockUi(block);
      ui.focusNode.addListener(_onFocusChanged);
      return ui;
    });
  }

  void _onFocusChanged() {
    int? index;
    for (var i = 0; i < _blocks.length; i++) {
      final ui = _uis[_blocks[i].id];
      if (ui != null && ui.focusNode.hasFocus) {
        index = i;
        break;
      }
    }
    if (index != _focusedIndex) setState(() => _focusedIndex = index);
  }

  void _focusBlock(int index, {bool placeCursorAtEnd = false}) {
    final ui = _ensureUi(_blocks[index]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      if (placeCursorAtEnd && ui.controller.text.isNotEmpty) {
        ui.controller.selection =
            TextSelection.collapsed(offset: ui.controller.text.length);
      }
      ui.focusNode.requestFocus();
    });
  }

  // ---- Undo / redo ----

  bool _onGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyZ:
        if (HardwareKeyboard.instance.isShiftPressed) {
          _redo();
        } else {
          _undo();
        }
        return true;
      case LogicalKeyboardKey.keyY:
        _redo();
        return true;
    }
    return false;
  }

  String _snapshot() => NoteBlock.encode(_blocks);

  void _pushSnapshot() {
    final snap = _snapshot();
    if (_undoStack.isNotEmpty && _undoStack.last == snap) return;
    _undoStack.add(snap);
    _trim(_undoStack);
  }

  void _trim(List<String> stack) {
    if (stack.length > _historyLimit) {
      stack.removeRange(0, stack.length - _historyLimit);
    }
  }

  /// True when this keystroke starts a new undo step (paused typing or the
  /// user moved to another block). Updates the burst bookkeeping.
  bool _shouldStartBurst(int index) {
    final now = DateTime.now();
    final isNew =
        _lastEditAt == null ||
        now.difference(_lastEditAt!) > _burstGap ||
        _lastEditedIndex != index;
    _lastEditAt = now;
    _lastEditedIndex = index;
    return isNew;
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final current = _snapshot();
    _redoStack.add(current);
    _trim(_redoStack);
    _restoreSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _pushSnapshot();
    _restoreSnapshot(_redoStack.removeLast());
  }

  void _restoreSnapshot(String encoded) {
    final restored = NoteBlock.decode(encoded);
    if (restored.isEmpty) return;

    String? focusedId;
    for (final b in _blocks) {
      final ui = _uis[b.id];
      if (ui != null && ui.focusNode.hasFocus) {
        focusedId = b.id;
        break;
      }
    }

    for (final ui in _uis.values) {
      ui.focusNode.removeListener(_onFocusChanged);
      ui.dispose();
    }
    _uis.clear();

    _blocks
      ..clear()
      ..addAll(restored);
    for (final b in _blocks) {
      _ensureUi(b);
    }

    _lastEditAt = null;
    _lastEditedIndex = null;
    _slashBlockId = null;

    if (mounted && !_disposed) setState(() {});

    var focusIndex = _blocks.indexWhere((b) => b.id == focusedId);
    if (focusIndex < 0) focusIndex = 0;
    _focusBlock(focusIndex);
    _markDirty();
  }

  void _moveBlock(int index, int delta) {
    if (index < 0 || index >= _blocks.length) return;
    final moved = delta < 0
        ? NoteDocument.moveUp(_blocks, index)
        : NoteDocument.moveDown(_blocks, index);
    if (!moved) return;
    _pushSnapshot();
    _lastEditAt = null;
    _lastEditedIndex = null;
    setState(() {});
    _focusBlock(index + delta);
    _markDirty();
  }

  void _handleContentChanged(int index, String value) {
    final wasEmpty = _blocks[index].content.isEmpty;
    if (_shouldStartBurst(index)) _pushSnapshot();
    _blocks[index].content = value;

    // Slash menu: typing "/" into an empty block opens the block picker.
    if (wasEmpty && value == '/' && _slashBlockId == null) {
      _slashBlockId = _blocks[index].id;
      setState(() {});
      _openSlashMenu(index);
    } else if (_slashBlockId != null && value != '/') {
      _slashBlockId = null;
    }

    _markDirty();
  }

  void _handleEnter(int index) {
    _pushSnapshot();
    final target = NoteDocument.pressEnter(_blocks, index);
    _lastEditAt = null;
    _lastEditedIndex = null;
    if (target != null) _ensureUi(_blocks[target]);
    setState(() {});
    if (target != null) _focusBlock(target, placeCursorAtEnd: true);
    _markDirty();
  }

  void _handleBackspaceEmpty(int index) => _deleteBlock(index);

  void _handleDeleteBlock(int index) => _deleteBlock(index);

  void _deleteBlock(int index) {
    _pushSnapshot();
    final removed = _blocks[index];
    final ui = _uis.remove(removed.id);
    ui?.focusNode.removeListener(_onFocusChanged);
    ui?.dispose();
    final focus = NoteDocument.deleteAt(_blocks, index);
    _lastEditAt = null;
    _lastEditedIndex = null;
    if (_slashBlockId == removed.id) _slashBlockId = null;
    _ensureUi(_blocks[focus]);
    setState(() {});
    _focusBlock(focus, placeCursorAtEnd: true);
    _markDirty();
  }

  void _handleToggleChecked(int index) {
    _pushSnapshot();
    NoteDocument.toggleChecked(_blocks[index]);
    setState(() {});
    _markDirty();
  }

  void _convertFocusedBlock(BlockType type) {
    var index = _focusedIndex;
    if (index == null || index < 0 || index >= _blocks.length) {
      index = _blocks.length - 1;
    }
    _pushSnapshot();
    NoteDocument.convertType(_blocks[index], type);
    _lastEditAt = null;
    _lastEditedIndex = null;
    setState(() {});
    _markDirty();
    _focusBlock(index, placeCursorAtEnd: true);
  }

  void _addBlockAtEnd() {
    _pushSnapshot();
    final target =
        NoteDocument.insertAfter(_blocks, _blocks.length - 1, type: BlockType.text);
    _lastEditAt = null;
    _lastEditedIndex = null;
    _ensureUi(_blocks[target]);
    setState(() {});
    _focusBlock(target);
    _markDirty();
  }

  // ---- Slash menu ----

  static const List<(BlockType, String, IconData)> _slashEntries = [
    (BlockType.text, 'Text', Icons.text_fields),
    (BlockType.heading, 'Heading', Icons.title),
    (BlockType.bullet, 'Bulleted list', Icons.format_list_bulleted),
    (BlockType.checklist, 'Checklist', Icons.check_box_outline_blank),
    (BlockType.quote, 'Quote', Icons.format_quote),
    (BlockType.code, 'Code', Icons.code),
  ];

  Future<void> _openSlashMenu(int index) async {
    final block = _blocks[index];
    final ui = _uis[block.id];
    final anchor = ui?.anchorKey.currentContext;
    if (anchor == null) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null) return;

    final origin =
        box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(
        origin.dx,
        origin.dy + box.size.height,
        box.size.width,
        0,
      ),
      Offset.zero & overlay.size,
    );

    final palette = context.palette;
    final selected = await showMenu<BlockType>(
      context: context,
      position: position,
      items: [
        for (final entry in _slashEntries)
          PopupMenuItem<BlockType>(
            value: entry.$1,
            height: 44,
            child: Row(
              children: [
                Icon(entry.$3, size: 20, color: palette.secondaryText),
                const SizedBox(width: AppSpacing.sm),
                Text(entry.$2, style: context.bodyText),
              ],
            ),
          ),
      ],
    );

    if (!mounted || _disposed) return;

    if (selected != null && _slashBlockId == block.id) {
      _pushSnapshot();
      NoteDocument.convertType(block, selected);
      block.content = '';
      _uis[block.id]?.controller.text = '';
      _lastEditAt = null;
      _lastEditedIndex = null;
      final focusIndex = _blocks.indexWhere((b) => b.id == block.id);
      if (focusIndex >= 0) {
        setState(() {});
        _focusBlock(focusIndex);
        _markDirty();
      }
    }
    _slashBlockId = null;
    if (mounted && !_disposed) setState(() {});
  }

  // ---- Autosave ----

  void _markDirty() {
    _debounce?.cancel();
    if (mounted) setState(() => _status = _SaveStatus.saving);
    _debounce = Timer(const Duration(milliseconds: 800), _persistNow);
  }

  /// Persists the current document. Returns true on success. Failures are
  /// surfaced to the user (snackbar) and never silently swallowed.
  Future<bool> _persistNow() async {
    final title = _titleController.text.trim();
    final content = NoteBlock.encode(_blocks);

    final hasContent = title.isNotEmpty ||
        _blocks.any((b) => b.content.trim().isNotEmpty || b.isChecked);

    if (!_inserted && !hasContent) {
      if (mounted) setState(() => _status = _SaveStatus.saved);
      return true;
    }

    final now = DateTime.now();
    final updated = _note.copyWith(
      title: title,
      content: content,
      updatedAt: now,
      version: _note.version + BigInt.one,
    );

    try {
      final notifier = ref.read(notesNotifierProvider.notifier);
      if (_inserted) {
        await notifier.updateNote(updated);
      } else {
        await notifier.addNote(updated);
        _inserted = true;
      }
      _note = updated;
    } catch (_) {
      if (mounted && !_disposed) {
        setState(() => _status = _SaveStatus.idle);
      }
      return false;
    }

    if (mounted && !_disposed) {
      setState(() => _status = _SaveStatus.saved);
    }
    return true;
  }

  Future<void> _flushAndPop() async {
    _debounce?.cancel();
    final ok = await _persistNow();
    if (!ok) {
      // Keep the user in the editor so nothing is lost; they can retry.
      if (mounted && !_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't save this note — please try again."),
          ),
        );
      }
      return;
    }
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
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              onPressed: _undoStack.isEmpty ? null : _undo,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: 'Redo',
              onPressed: _redoStack.isEmpty ? null : _redo,
            ),
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
            child: _buildEditor(context),
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
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
        BlockToolbar(
          activeType: _focusedBlockType,
          onSelected: _convertFocusedBlock,
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: _blocks.length + 1,
            itemBuilder: (context, i) {
              if (i == _blocks.length) return _buildAddRow(context);
              return _buildBlockRow(context, i);
            },
          ),
        ),
      ],
    );
  }

  BlockType? get _focusedBlockType {
    final index = _focusedIndex;
    if (index == null || index < 0 || index >= _blocks.length) return null;
    return _blocks[index].type;
  }

  Widget _buildBlockRow(BuildContext context, int index) {
    final block = _blocks[index];
    final ui = _ensureUi(block);
    final isHeading = block.type == BlockType.heading;

    return Entrance(
      key: ValueKey('block-${block.id}'),
      index: index.clamp(0, 12),
      child: Padding(
        padding: EdgeInsets.only(top: isHeading ? AppSpacing.sm : 0),
        child: BlockRow(
          block: block,
          controller: ui.controller,
          focusNode: ui.focusNode,
          anchorKey: ui.anchorKey,
          onContentChanged: (v) => _handleContentChanged(index, v),
          onEnter: () => _handleEnter(index),
          onBackspaceEmpty: () => _handleBackspaceEmpty(index),
          onDelete: () => _handleDeleteBlock(index),
          onToggleChecked: () => _handleToggleChecked(index),
          showMoveControls: _focusedIndex == index && _blocks.length > 1,
          enableMoveUp: index > 0,
          enableMoveDown: index < _blocks.length - 1,
          onMoveUp: () => _moveBlock(index, -1),
          onMoveDown: () => _moveBlock(index, 1),
        ),
      ),
    );
  }

  Widget _buildAddRow(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: InkWell(
        onTap: _addBlockAtEnd,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            children: [
              Icon(Icons.add, size: 22, color: palette.disabledText),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Add a block',
                style: context.secondaryText.copyWith(
                  color: palette.disabledText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}