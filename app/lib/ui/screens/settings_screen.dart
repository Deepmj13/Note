import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/data/export/note_share.dart';
import 'package:note_v4/data/repositories/note_repository.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/providers/settings_providers.dart';
import 'package:note_v4/theme.dart';
import 'package:note_v4/ui/widgets/confirm_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final defaultType = ref.watch(defaultNoteTypeProvider);
    final user = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: [
          if (user != null) ...[
            const _SectionTitle('Account'),
            _SettingsGroup(
              children: [
                _SettingTile(
                  icon: Icons.person_outline,
                  title: user.email ?? 'Signed in',
                  enabled: false,
                ),
                const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
                _SettingTile(
                  icon: Icons.logout,
                  title: 'Sign out',
                  onTap: () => _confirmSignOut(context, ref),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          const _SectionTitle('Appearance'),
          _SettingsGroup(
            children: [
              _SettingTile(
                icon: Icons.light_mode_outlined,
                title: 'Light',
                selected: themeMode == ThemeMode.light,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.light),
              ),
              const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
              _SettingTile(
                icon: Icons.dark_mode_outlined,
                title: 'Dark',
                selected: themeMode == ThemeMode.dark,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.dark),
              ),
              const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
              _SettingTile(
                icon: Icons.brightness_auto_outlined,
                title: 'System default',
                selected: themeMode == ThemeMode.system,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.system),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle('Notes'),
          _SettingsGroup(
            children: [
              _SettingTile(
                icon: Icons.edit_note,
                title: 'Default note type',
                subtitle: 'Used when creating a new note',
                trailing: _ValueLabel(
                  defaultType == AppNoteType.checklist
                      ? 'Checklist'
                      : 'Text note',
                ),
                onTap: () => _showDefaultTypeSheet(context, ref),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle('Storage'),
          _SettingsGroup(
            children: [
              _SettingTile(
                icon: Icons.ios_share,
                title: 'Export data',
                subtitle: 'Export all notes as JSON',
                onTap: () => _exportAllNotes(context, ref),
              ),
              const Divider(
                indent: AppSpacing.md,
                endIndent: AppSpacing.md,
              ),
              const _SettingTile(
                icon: Icons.cleaning_services_outlined,
                title: 'Clear cache',
                subtitle: 'Coming soon',
                enabled: false,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle('About'),
          _SettingsGroup(
            children: [
              const _SettingTile(
                icon: Icons.info_outline,
                title: 'Version',
                trailing: _ValueLabel('1.0.0'),
                enabled: false,
              ),
              const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
              const _SettingTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy',
                enabled: false,
              ),
              const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
              const _SettingTile(
                icon: Icons.description_outlined,
                title: 'Terms',
                enabled: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportAllNotes(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final notes = await ref
        .read(noteRepositoryProvider)
        .watchActiveNotes(userId)
        .first;
    if (notes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No notes to export')),
      );
      return;
    }
    await NoteShare.exportJson(notes);
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showConfirmSheet(
      context,
      title: 'Sign out?',
      message: 'Your notes stay on the server and will be synced back the next '
          'time you sign in on this device.',
      confirmLabel: 'Sign out',
      icon: Icons.logout,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _showDefaultTypeSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(defaultNoteTypeProvider);
    final result = await showModalBottomSheet<AppNoteType>(
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
                child: Text('Default note type', style: context.sectionTitle),
              ),
              _TypeOption(
                icon: Icons.edit_note,
                label: 'Text note',
                selected: current == AppNoteType.text,
                onTap: () => Navigator.pop(context, AppNoteType.text),
              ),
              _TypeOption(
                icon: Icons.checklist,
                label: 'Checklist',
                selected: current == AppNoteType.checklist,
                onTap: () => Navigator.pop(context, AppNoteType.checklist),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      ref.read(defaultNoteTypeProvider.notifier).set(result);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: context.metadataText.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: ListTile(
        onTap: enabled ? onTap : null,
        leading: Icon(
          icon,
          size: 22,
          color: selected ? palette.accent : palette.secondaryText,
        ),
        title: Text(
          title,
          style: context.bodyText.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? palette.accent : palette.primaryText,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle!, style: context.metadataText)
            : null,
        trailing: trailing ??
            (selected
                ? Icon(Icons.check, size: 20, color: palette.accent)
                : null),
      ),
    );
  }
}

class _ValueLabel extends StatelessWidget {
  const _ValueLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: context.secondaryText);
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
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
              if (selected)
                Icon(Icons.check, size: 20, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}
