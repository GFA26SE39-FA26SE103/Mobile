import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Builds the Material theme from the shared colour tokens.
///
/// App bars sit on the surface colour with a 1px hairline (no solid teal
/// block); teal is kept for primary actions, the selected tab and states.
ThemeData buildTheme(AppColors c, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: c.primary, brightness: brightness).copyWith(
    primary: c.primary,
    onPrimary: c.onPrimary,
    surface: c.surface,
    onSurface: c.text,
    error: c.danger,
    outline: c.border,
  );
  final radius = BorderRadius.circular(12);
  final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);
  final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text);

  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    dividerColor: c.border,
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: text.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(fontSize: 12.5, color: c.textMuted, height: 1.4),
      labelSmall: text.labelSmall?.copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.textMuted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text, letterSpacing: -0.2),
      shape: Border(bottom: BorderSide(color: c.border)),
      systemOverlayStyle: (brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        disabledBackgroundColor: c.track,
        disabledForegroundColor: c.textDim,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: c.surface,
        foregroundColor: c.text,
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        minimumSize: const Size(48, 44),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: TextStyle(color: c.textDim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.danger, width: 1.5)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.primaryTint,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? c.primary : c.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? c.primary : c.textMuted, size: 23),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.text,
      contentTextStyle: TextStyle(color: c.bg, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : Colors.transparent),
      side: BorderSide(color: c.border, width: 1.5),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, linearTrackColor: c.track, circularTrackColor: c.track),
    extensions: [c],
  );
}
