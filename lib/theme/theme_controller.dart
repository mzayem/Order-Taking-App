import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// Light / dark / follow-the-system, like the ERP's erpTheme setting.
/// Saved on the phone; the default is to follow the system.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController._();
  static final instance = ThemeController._();

  static const _key = 'themeMode'; // 'system' | 'light' | 'dark'

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  bool get followsSystem => _mode == ThemeMode.system;
  bool get isDark => AppColors.isDark;

  /// Reads the saved choice and applies it before the first frame.
  Future<void> init() async {
    final saved = (await SharedPreferences.getInstance()).getString(_key);
    _mode = ThemeMode.values
        .firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
    AppColors.setDark(_effectiveDark());
    WidgetsBinding.instance.addObserver(this);
  }

  bool _effectiveDark() => switch (_mode) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark,
      };

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    _apply();
    await (await SharedPreferences.getInstance()).setString(_key, mode.name);
  }

  /// "Match system" switch.
  Future<void> setFollowSystem(bool follow) => setMode(follow
      ? ThemeMode.system
      : (AppColors.isDark ? ThemeMode.dark : ThemeMode.light));

  /// "Dark mode" switch (only used when not following the system).
  Future<void> setDark(bool dark) =>
      setMode(dark ? ThemeMode.dark : ThemeMode.light);

  @override
  void didChangePlatformBrightness() {
    if (followsSystem) _apply();
  }

  void _apply() {
    final dark = _effectiveDark();
    final changed = dark != AppColors.isDark;
    AppColors.setDark(dark);
    // Must be set BEFORE notifying: MyApp's listener checks it right away.
    // (It was set after, so only Theme-aware widgets updated until the page
    // changed.)
    if (changed) _needsFullRebuild = true;
    notifyListeners(); // MyApp rebuilds and marks every element dirty
  }

  bool _needsFullRebuild = false;

  /// AppColors are read at build time, so every widget must rebuild once
  /// after a brightness change. Only happens when the user flips the theme.
  void rebuildAllIfNeeded(BuildContext root) {
    if (!_needsFullRebuild) return;
    _needsFullRebuild = false;
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (root as Element).visitChildren(mark);
  }
}
