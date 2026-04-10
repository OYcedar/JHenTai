import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:web/web.dart' as web;

class ThemeController extends GetxController {
  final themeMode = ThemeMode.system.obs;
  final Rx<Color> seedColor = Rx<Color>(Colors.deepPurple);

  static const _themeModeKey = 'jh_theme_mode';
  static const _seedColorKey = 'jh_seed_color';

  static const seedColors = <Color>[
    Colors.deepPurple,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
    Colors.grey,
  ];

  @override
  void onInit() {
    super.onInit();
    _loadFromStorage();
  }

  void _loadFromStorage() {
    final modeStr = web.window.localStorage.getItem(_themeModeKey);
    if (modeStr != null) {
      themeMode.value = switch (modeStr) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    }
    final colorStr = web.window.localStorage.getItem(_seedColorKey);
    if (colorStr != null) {
      final colorVal = int.tryParse(colorStr);
      if (colorVal != null) {
        seedColor.value = Color(colorVal);
      }
    }
  }

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    web.window.localStorage.setItem(_themeModeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
    Get.changeThemeMode(mode);
  }

  void setSeedColor(Color color) {
    seedColor.value = color;
    web.window.localStorage.setItem(_seedColorKey, color.toARGB32().toString());
    Get.changeTheme(buildTheme(Brightness.light, color));
    Get.changeTheme(buildTheme(Brightness.dark, color));
    Get.forceAppUpdate();
  }

  static ThemeData buildTheme(Brightness brightness, Color seed) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
      ),
    );
  }
}
