import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'services/background_refresh.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Registers the entry point Android calls when it runs the periodic
  // task. Whether that task is scheduled at all is a setting; this only
  // makes the callback reachable.
  Workmanager().initialize(backgroundCallbackDispatcher);

  runApp(const OmniApp());
}

class OmniApp extends StatelessWidget {
  const OmniApp({super.key});

  /// Used whenever the wallpaper palette isn't available or is turned off.
  static const seedColor = Color(0xFF6750A4);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, state, _) => DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            // Android 12+ exposes a palette derived from the wallpaper.
            // Everywhere else — and whenever the user opts out — fall back to
            // Omni's own seed.
            final useDynamic = state.useDynamicColour && lightDynamic != null;

            final light = useDynamic
                ? lightDynamic.harmonized()
                : ColorScheme.fromSeed(seedColor: seedColor);
            final dark = useDynamic && darkDynamic != null
                ? darkDynamic.harmonized()
                : ColorScheme.fromSeed(
                    seedColor: seedColor, brightness: Brightness.dark);

            return MaterialApp(
              title: 'Omni',
              debugShowCheckedModeBanner: false,
              themeMode: state.themeMode,
              theme: ThemeData(colorScheme: light, useMaterial3: true),
              darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
              home: const HomeScreen(),
            );
          },
        ),
      ),
    );
  }
}
