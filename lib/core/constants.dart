import 'package:flutter/material.dart';

/// App identity.
const String kAppName = 'Khaata';
const String kAppTagline = 'Your money, on your device.';

/// Default (and only, for now) currency.
const String kCurrencySymbol = '₹';

/// Entry "kind" toggles inside the Add Transaction modal.
enum EntryKind { expense, income, people }

enum PeopleType { borrowed, lent }

class AppColors {
  static const expense = Color(0xFFFF6B6B); // red
  static const income = Color(0xFF4DA3FF); // blue-ish
  static const incomeGreen = Color(0xFF34C759); // green for income totals
  static const borrowedLent = Color(0xFF4DA3FF); // blue for People entries
  static const background = Color(0xFF15161B);
  static const surface = Color(0xFF1E2027);
  static const accent = Color(0xFFFF6650);

  /// Shared chart palette so every chart in the app stays consistent.
  static const chartPalette = [
    Color(0xFFFF7A59),
    Color(0xFFFFC24B),
    Color(0xFF4DA3FF),
    Color(0xFF34C759),
    Color(0xFFB388FF),
    Color(0xFFFF6B9D),
    Color(0xFF64D8CB),
    Color(0xFFFFD166),
  ];
}
