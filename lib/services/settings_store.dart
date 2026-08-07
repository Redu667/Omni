import 'package:shared_preferences/shared_preferences.dart';

/// Small app-level preferences that aren't tied to any one source.
class SettingsStore {
  static const _openInAppKey = 'omni_open_in_app';

  Future<bool> loadOpenInApp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_openInAppKey) ?? true;
  }

  Future<void> saveOpenInApp(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_openInAppKey, value);
  }
}
