import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'views/main_screen.dart';
import 'windows_accent.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(480, 640));
  await windowManager.setSize(const Size(520, 894));
  await windowManager.center();
  runApp(const CompressApp());
}

class CompressApp extends StatefulWidget {
  const CompressApp({super.key});

  @override
  State<CompressApp> createState() => _CompressAppState();
}

class _CompressAppState extends State<CompressApp> with WidgetsBindingObserver {
  int _accentColor = 0xFF6750A4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _accentColor = getWindowsAccentColor();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'COMPRESS',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorSchemeSeed: Color(_accentColor),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Color(_accentColor),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const MainScreen(),
    );
  }
}
