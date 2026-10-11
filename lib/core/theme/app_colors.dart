import 'package:flutter/material.dart';

/// Colour tokens from the Figma "Theme" collection (VariableCollectionId:91:2),
/// shared with the web console so both surfaces speak the same colours.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textDim,
    required this.primary,
    required this.primaryTint,
    required this.onPrimary,
    required this.danger,
    required this.dangerTint,
    required this.warning,
    required this.warningTint,
    required this.success,
    required this.successTint,
    required this.info,
    required this.infoTint,
    required this.track,
    required this.placeholder,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color textDim;
  final Color primary;
  final Color primaryTint;
  final Color onPrimary;
  final Color danger;
  final Color dangerTint;
  final Color warning;
  final Color warningTint;
  final Color success;
  final Color successTint;
  final Color info;
  final Color infoTint;
  final Color track;
  final Color placeholder;

  static const light = AppColors(
    bg: Color(0xFFF4F6F9),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF5F7FA),
    border: Color(0xFFDDE1E7),
    text: Color(0xFF1C2028),
    textMuted: Color(0xFF6B7280),
    textDim: Color(0xFF9AA1AC),
    primary: Color(0xFF0D9494),
    primaryTint: Color(0xFFE2F4F3),
    onPrimary: Color(0xFFFFFFFF),
    danger: Color(0xFFDC2D37),
    dangerTint: Color(0xFFFBE6E7),
    warning: Color(0xFFC88214),
    warningTint: Color(0xFFFBF1DF),
    success: Color(0xFF16965F),
    successTint: Color(0xFFE4F3EA),
    info: Color(0xFF2563EB),
    infoTint: Color(0xFFEAF1FE),
    track: Color(0xFFE6E9EE),
    placeholder: Color(0xFFE4E8EE),
  );

  static const dark = AppColors(
    bg: Color(0xFF101218),
    surface: Color(0xFF1A1D26),
    surface2: Color(0xFF212530),
    border: Color(0xFF343947),
    text: Color(0xFFE6E8EE),
    textMuted: Color(0xFF969DAA),
    textDim: Color(0xFF6E7583),
    primary: Color(0xFF14AFAA),
    primaryTint: Color(0xFF123433),
    onPrimary: Color(0xFFFFFFFF),
    danger: Color(0xFFE94A4F),
    dangerTint: Color(0xFF2E1618),
    warning: Color(0xFFF0AA37),
    warningTint: Color(0xFF2C2210),
    success: Color(0xFF2DAF78),
    successTint: Color(0xFF12281E),
    info: Color(0xFF4682F0),
    infoTint: Color(0xFF152238),
    track: Color(0xFF2A2E39),
    placeholder: Color(0xFF262B36),
  );

  @override
  AppColors copyWith({Color? primary, Color? surface}) => AppColors(
        bg: bg,
        surface: surface ?? this.surface,
        surface2: surface2,
        border: border,
        text: text,
        textMuted: textMuted,
        textDim: textDim,
        primary: primary ?? this.primary,
        primaryTint: primaryTint,
        onPrimary: onPrimary,
        danger: danger,
        dangerTint: dangerTint,
        warning: warning,
        warningTint: warningTint,
        success: success,
        successTint: successTint,
        info: info,
        infoTint: infoTint,
        track: track,
        placeholder: placeholder,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      border: l(border, other.border),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textDim: l(textDim, other.textDim),
      primary: l(primary, other.primary),
      primaryTint: l(primaryTint, other.primaryTint),
      onPrimary: l(onPrimary, other.onPrimary),
      danger: l(danger, other.danger),
      dangerTint: l(dangerTint, other.dangerTint),
      warning: l(warning, other.warning),
      warningTint: l(warningTint, other.warningTint),
      success: l(success, other.success),
      successTint: l(successTint, other.successTint),
      info: l(info, other.info),
      infoTint: l(infoTint, other.infoTint),
      track: l(track, other.track),
      placeholder: l(placeholder, other.placeholder),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
