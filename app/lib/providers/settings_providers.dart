import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/data/repositories/note_repository.dart';

enum AppNoteType { text, checklist }

/// Keys for values persisted in the local Drift key-value store.
class SettingsKeys {
  static const themeMode = 'setting:theme_mode';
  static const defaultNoteType = 'setting:default_note_type';
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final stored = await ref
        .read(noteRepositoryProvider)
        .readSetting(SettingsKeys.themeMode);
    if (stored == null) return;
    final mode = ThemeMode.values.asNameMap()[stored];
    if (mode != null && mode != state) {
      state = mode;
    }
  }

  Future<void> _persist(ThemeMode mode) async {
    await ref
        .read(noteRepositoryProvider)
        .writeSetting(SettingsKeys.themeMode, mode.name);
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _persist(mode);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class DefaultNoteTypeNotifier extends Notifier<AppNoteType> {
  @override
  AppNoteType build() {
    _load();
    return AppNoteType.text;
  }

  Future<void> _load() async {
    final stored = await ref
        .read(noteRepositoryProvider)
        .readSetting(SettingsKeys.defaultNoteType);
    if (stored == null) return;
    final type = AppNoteType.values.asNameMap()[stored];
    if (type != null && type != state) {
      state = type;
    }
  }

  void set(AppNoteType type) {
    state = type;
    ref
        .read(noteRepositoryProvider)
        .writeSetting(SettingsKeys.defaultNoteType, type.name);
  }
}

final defaultNoteTypeProvider =
    NotifierProvider<DefaultNoteTypeNotifier, AppNoteType>(
      DefaultNoteTypeNotifier.new,
    );
