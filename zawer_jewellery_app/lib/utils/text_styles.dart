import 'package:flutter/material.dart';

class AppFonts {
  static TextStyle cinzel({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Fraunces',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
      decoration: decoration,
      height: height,
    );
  }

  static TextStyle poppins({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
      decoration: decoration,
      height: height,
    );
  }

  static TextStyle cormorantGaramond({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'PinyonScript',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
      decoration: decoration,
      height: height,
    );
  }
}
