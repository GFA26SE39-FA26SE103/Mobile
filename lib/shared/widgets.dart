import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../data/models.dart';

/// Severity colours match the web console: critical red, warning amber, info blue.
({Color fg, Color bg}) severityColors(BuildContext context, Severity s) {
  final c = context.colors;
  return switch (s) {
    Severity.critical => (fg: c.danger, bg: c.dangerTint),
    Severity.warning => (fg: c.warning, bg: c.warningTint),
    Severity.info => (fg: c.info, bg: c.infoTint),
  };
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.fg, required this.bg, this.dot = false, this.solid = false, this.ellipsis = false});

  final String label;
  final Color fg;
  final Color bg;
  final bool dot;

  /// Solid pills (white text on the colour) are reserved for urgent states.
  final bool solid;

  /// Cuts a long label to fit a narrow column. Only for pills whose parent bounds the width
  /// (a Column inside Expanded), never as a direct child of a Row.
  final bool ellipsis;

  static TextStyle _style(Color color) => TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3);

  @override
  Widget build(BuildContext context) {
    final textColor = solid ? context.colors.onPrimary : fg;
    return DecoratedBox(
      decoration: BoxDecoration(color: solid ? fg : bg, borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: textColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          if (ellipsis)
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _style(textColor)))
          else
            Text(label, style: _style(textColor)),
        ]),
      ),
    );
  }
}

class SeverityChip extends StatelessWidget {
  const SeverityChip(this.severity, {super.key, this.suffix, this.solid = false});
  final Severity severity;
  final String? suffix;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final colors = severityColors(context, severity);
    return Pill(
      label: suffix == null ? severity.label : '${severity.label} · $suffix',
      fg: colors.fg,
      bg: colors.bg,
      solid: solid,
    );
  }
}

/// On shift / Off shift status shown in app bars.
class ShiftStatusPill extends StatelessWidget {
  const ShiftStatusPill({super.key, required this.onShift});
  final bool onShift;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pill(
      label: onShift ? 'On shift' : 'Off shift',
      fg: onShift ? c.success : c.textMuted,
      bg: onShift ? c.successTint : c.surface2,
      dot: true,
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.borderColor, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(14);
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: borderColor ?? c.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

enum BannerTone { info, success, warning, danger, brand }

/// An inline message that names the situation and, when possible, the next step.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.tone, required this.icon, required this.title, this.body, this.action});

  final BannerTone tone;
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fg, bg) = switch (tone) {
      BannerTone.info => (c.info, c.infoTint),
      BannerTone.success => (c.success, c.successTint),
      BannerTone.warning => (c.warning, c.warningTint),
      BannerTone.danger => (c.danger, c.dangerTint),
      BannerTone.brand => (c.primary, c.primaryTint),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 19, color: fg)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
              if (body != null) ...[
                const SizedBox(height: 2),
                Text(body!, style: TextStyle(color: c.text, fontSize: 13, height: 1.4)),
              ],
              if (action != null) ...[const SizedBox(height: 6), action!],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A row with a leading icon, used for location / time / measurement facts.
class FactLine extends StatelessWidget {
  const FactLine({super.key, required this.icon, required this.text, this.strong = false});
  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 17, color: c.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 14, color: strong ? c.text : c.textMuted, fontWeight: strong ? FontWeight.w500 : FontWeight.w400)),
        ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: c.primary, size: 26),
        ),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (body != null) ...[
          const SizedBox(height: 6),
          Text(body!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// Uppercase group label for lists ("TODAY", "EARLIER"); not used above headings.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
        ?trailing,
      ]),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.initials, {super.key, this.size = 40});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
      child: Text(initials, style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: size * 0.34)),
    );
  }
}
