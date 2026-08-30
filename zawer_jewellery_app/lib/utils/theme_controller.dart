import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier(ThemeMode.light);

  static Future<void> load() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final bool darkMode = prefs.getBool("darkMode") ?? false;

    mode.value = darkMode ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> setDarkMode(bool value) async {
    mode.value = value ? ThemeMode.dark : ThemeMode.light;

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool("darkMode", value);
  }

  static void toggle() {
    setDarkMode(mode.value != ThemeMode.dark);
  }
}