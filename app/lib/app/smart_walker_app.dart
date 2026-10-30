import 'dart:async';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/desktop/desktop_workspace.dart';
import 'app_dependencies.dart';
import 'app_lifecycle_controller.dart';
import 'app_platform.dart';

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
    theme: appTheme(dark: false).toApproximateMaterialTheme(),
    darkTheme: appTheme(dark: true).toApproximateMaterialTheme(),
    themeMode: ThemeMode.system,
    builder: (context, child) => FTheme(
      data: appTheme(dark: Theme.of(context).brightness == Brightness.dark),
      child: FToaster(child: FTooltipGroup(child: child!)),
    ),
    home: isMacOSApp
        ? DesktopWorkspace(dependencies: widget.dependencies)
        : DashboardPage(dependencies: widget.dependencies),
  );

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.dependencies.dispose();
    super.dispose();
  }
}
