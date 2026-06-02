import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:web/web.dart' as web;

class ThemeController extends GetxController {
  final themeMode = ThemeMode.system.obs;
  final Rx<Color> lightSeedColor = Rx<Color>(Colors.deepPurple);
  final Rx<Color> darkSeedColor = Rx<Color>(Colors.deepPurple);

  static const _themeModeKey = 'jh_theme_mode';
  static const _seedColorKey = 'jh_seed_color';
  static const _lightSeedColorKey = 'jh_light_seed_color';
  static const _darkSeedColorKey = 'jh_dark_seed_color';

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
    final legacyColor = _readColor(_seedColorKey);
    lightSeedColor.value =
        _readColor(_lightSeedColorKey) ?? legacyColor ?? Colors.deepPurple;
    darkSeedColor.value =
        _readColor(_darkSeedColorKey) ?? legacyColor ?? Colors.deepPurple;
  }

  Color? _readColor(String key) {
    final colorStr = web.window.localStorage.getItem(key);
    final colorVal = int.tryParse(colorStr ?? '');
    return colorVal == null ? null : Color(colorVal);
  }

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    web.window.localStorage.setItem(
        _themeModeKey,
        switch (mode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          _ => 'system',
        });
    Get.changeThemeMode(mode);
  }

  void setLightSeedColor(Color color) {
    lightSeedColor.value = color;
    web.window.localStorage
        .setItem(_lightSeedColorKey, color.toARGB32().toString());
    Get.changeTheme(buildTheme(Brightness.light, color));
    Get.forceAppUpdate();
  }

  void setDarkSeedColor(Color color) {
    darkSeedColor.value = color;
    web.window.localStorage
        .setItem(_darkSeedColorKey, color.toARGB32().toString());
    Get.changeTheme(buildTheme(Brightness.dark, color));
    Get.forceAppUpdate();
  }

  void setSeedColor(Color color) {
    setLightSeedColor(color);
    setDarkSeedColor(color);
    web.window.localStorage.setItem(_seedColorKey, color.toARGB32().toString());
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
