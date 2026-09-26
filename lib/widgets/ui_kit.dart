import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';

// ---------------------------------------------------------------------------
// Money formatting — Indian digit grouping (₹1,23,456), one place for the app.
// ---------------------------------------------------------------------------
final NumberFormat _inr0 = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0);
final NumberFormat _inr2 = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);

/// `₹1,234` (or `₹1,234.50` when [decimals] is true). Negative values get a '-'.
String fmtMoney(double v, {bool decimals = false}) {
  final threshold = decimals ? 0.005 : 0.5;
  final neg = v < 0 && v.abs() >= threshold;
  final n = (decimals ? _inr2 : _inr0).format(v.abs());
  return '${neg ? '-' : ''}$kCurrencySymbol$n';
}

/// Always carries a sign: `+₹500` / `-₹500`.
String fmtSigned(double v, {bool decimals = false}) {
  final sign = v < 0 ? '-' : '+';
  return '$sign${fmtMoney(v.abs(), decimals: decimals)}';
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.fromLTRB(12, 6, 12, 6),
    this.color,
    this.borderColor,
    this.onTap,
    this.onLongPress,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: r,
        border: Border.all(color: borderColor ?? Colors.white10),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat card — the "Income / Expense / Net ..." tiles
// ---------------------------------------------------------------------------
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.subtitle,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: color.withOpacity(selected ? 0.18 : 0.09),
      borderColor: color.withOpacity(selected ? 0.9 : 0.28),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
                  child: Icon(icon, size: 13, color: color),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color)),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two widgets side by side, always the same height.
class TwoUp extends StatelessWidget {
  final Widget left;
  final Widget right;
  final EdgeInsetsGeometry padding;
  const TwoUp({
    super.key,
    required this.left,
    required this.right,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section heading
// ---------------------------------------------------------------------------
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 6)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Friendly placeholder for empty lists.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: Colors.white24),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label, e.g. "Yearly", "Settled".
class MiniTag extends StatelessWidget {
  final String text;
  final Color color;
  const MiniTag(this.text, {super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w700)),
    );
  }
}
