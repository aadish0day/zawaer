import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xff8B0000);

  static const Color gold = Color(0xffD4AF37);

  static const Color white = Colors.white;

  static const Color black = Color(0xff111111);

  static const Color grey = Color(0xffF5F5F5);

  static const Color darkGrey = Color(0xff2E2E2E);

  static const Color textGrey = Colors.grey;

  static const Color background = Color(0xffFAFAFA);

  static const Color success = Colors.green;

  static const Color error = Colors.red;

  // Theme-aware brand color: gold in dark mode for contrast,
  // primary (deep red) in light mode.
  static Color brand(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? gold
        : primary;
  }
}