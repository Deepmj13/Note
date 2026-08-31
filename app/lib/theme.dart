import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/app_spacing.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.elevatedSurface,
    required this.primaryText,
    required this.secondaryText,
    required this.disabledText,
    required this.divider,
    required this.accent,
    required this.accentContainer,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.warning,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  final Color background;
  final Color surface;
  final Color elevatedSurface;
  final Color primaryText;
  final Color secondaryText;
  final Color disabledText;
  final Color divider;
  final Color accent;
  final Color accentContainer;
  final Color onAccent;
  final Color danger;
  final Color success;
  final Color warning;
  final Color skeletonBase;
  final Color skeletonHighlight;

  static const AppPalette light = AppPalette(
    background: Color(0xFFF7F6F2),
    surface: Color(0xFFFFFFFF),
    elevatedSurface: Color(0xFFFFFFFF),
    primaryText: Color(0xFF1B1B1E),
    secondaryText: Color(0xFF6E6A63),
    disabledText: Color(0xFFAFA9A0),
    divider: Color(0xFFE9E6DF),
    accent: Color(0xFF2E6BFF),
    accentContainer: Color(0xFFE3E9FF),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFD5484D),
    success: Color(0xFF2E8B57),
    warning: Color(0xFFC77A1E),
    skeletonBase: Color(0xFFECE9E2),
    skeletonHighlight: Color(0xFFF6F4EF),
  );

  static const AppPalette dark = AppPalette(
    background: Color(0xFF121214),
    surface: Color(0xFF1D1D20),
    elevatedSurface: Color(0xFF26262B),
    primaryText: Color(0xFFF2F1ED),
    secondaryText: Color(0xFF9B978E),
    disabledText: Color(0xFF5C5850),
    divider: Color(0xFF2B2B30),
    accent: Color(0xFF6C9BFF),
    accentContainer: Color(0xFF25314D),
    onAccent: Color(0xFF0E0E10),
    danger: Color(0xFFFF6B6B),
    success: Color(0xFF58C98D),
    warning: Color(0xFFE8A54D),
    skeletonBase: Color(0xFF26262A),
    skeletonHighlight: Color(0xFF303036),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? elevatedSurface,
    Color? primaryText,
    Color? secondaryText,
    Color? disabledText,
    Color? divider,
    Color? accent,
    Color? accentContainer,
    Color? onAccent,
    Color? danger,
    Color? success,
    Color? warning,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      disabledText: disabledText ?? this.disabledText,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      accentContainer: accentContainer ?? this.accentContainer,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      disabledText: Color.lerp(disabledText, other.disabledText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight: Color.lerp(
        skeletonHighlight,
        other.skeletonHighlight,
        t,
      )!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Inter';

  static ThemeData get lightTheme => _build(Brightness.light, AppPalette.light);

  static ThemeData get darkTheme => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
    );
    final scheme = baseScheme.copyWith(
      primary: palette.accent,
      onPrimary: palette.onAccent,
      primaryContainer: palette.accentContainer,
      onPrimaryContainer: palette.primaryText,
      surface: palette.background,
      onSurface: palette.primaryText,
      onSurfaceVariant: palette.secondaryText,
      outlineVariant: palette.divider,
      error: palette.danger,
      onError: Colors.white,
    );

    final textTheme = GoogleFonts.interTextTheme().apply(
      bodyColor: palette.primaryText,
      displayColor: palette.primaryText,
    );

    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      fontFamily: fontFamily,
      textTheme: textTheme,
      extensions: [palette],
      splashFactory: InkSparkle.splashFactory,
    );

    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: palette.primaryText,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: palette.primaryText,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.fab),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: palette.divider,
        dragHandleSize: const Size(36, 4),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: palette.disabledText,
        ),
        contentPadding: EdgeInsets.zero,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.accent,
        selectionColor: palette.accent.withValues(alpha: 0.30),
        selectionHandleColor: palette.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.primaryText,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.background,
        ),
        actionTextColor: palette.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        elevation: 6,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: palette.primaryText,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.secondaryText,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: palette.accentContainer,
        disabledColor: palette.divider,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        side: BorderSide(color: palette.divider),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: palette.primaryText,
        ),
        secondaryLabelStyle: textTheme.bodyMedium?.copyWith(
          color: palette.secondaryText,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.divider,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.primaryText,
          side: BorderSide(color: palette.divider),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: palette.primaryText,
        iconColor: palette.secondaryText,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(
          color: palette.primaryText,
        ),
      ),
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

extension NoteTextStyles on BuildContext {
  ThemeData get _t => Theme.of(this);

  TextStyle get screenTitle => _t.textTheme.headlineMedium!.copyWith(
    fontWeight: FontWeight.w700,
    color: palette.primaryText,
    fontSize: 30,
    height: 1.2,
  );

  TextStyle get sectionTitle => _t.textTheme.titleMedium!.copyWith(
    fontWeight: FontWeight.w600,
    color: palette.primaryText,
    fontSize: 20,
  );

  TextStyle get noteTitle => _t.textTheme.titleMedium!.copyWith(
    fontWeight: FontWeight.w600,
    color: palette.primaryText,
    fontSize: 18,
  );

  TextStyle get bodyText => _t.textTheme.bodyLarge!.copyWith(
    fontSize: 16,
    color: palette.primaryText,
    height: 1.45,
  );

  TextStyle get secondaryText => _t.textTheme.bodyMedium!.copyWith(
    fontSize: 14,
    color: palette.secondaryText,
  );

  TextStyle get metadataText => _t.textTheme.bodySmall!.copyWith(
    fontSize: 12,
    color: palette.secondaryText,
  );
}
