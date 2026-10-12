import 'dart:async';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../features/dashboard/dashboard_page.dart';
import 'app_dependencies.dart';
import 'app_lifecycle_controller.dart';

class SmartWalkerApp extends StatefulWidget {
  const SmartWalkerApp({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  State<SmartWalkerApp> createState() => _SmartWalkerAppState();
}

class _SmartWalkerAppState extends State<SmartWalkerApp> {
  late final AppLifecycleController _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleController(widget.dependencies);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.dependencies.telemetry.foreground) {
        unawaited(widget.dependencies.devices.start(requestPermissions: true));
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Smart Walker',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: FLocalizations.localizationsDelegates,
    supportedLocales: FLocalizations.supportedLocales,
    theme: FTheme.neutral.light.touch.toApproximateMaterialTheme(),
    darkTheme: FTheme.neutral.dark.touch.toApproximateMaterialTheme(),
    themeMode: ThemeMode.system,
    builder: (context, child) => FTheme(
      data: Theme.of(context).brightness == Brightness.dark
          ? FTheme.neutral.dark.touch
          : FTheme.neutral.light.touch,
      child: FToaster(child: FTooltipGroup(child: child!)),
    ),
    home: DashboardPage(dependencies: widget.dependencies),
  );

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.dependencies.dispose();
    super.dispose();
  }
}
