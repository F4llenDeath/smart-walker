import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app_dependencies.dart';
import 'app/smart_walker_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<AppDependencies> _dependencies = AppDependencies.create();

  @override
  Widget build(BuildContext context) => FutureBuilder<AppDependencies>(
    future: _dependencies,
    builder: (context, snapshot) {
      if (snapshot.hasData) return SmartWalkerApp(dependencies: snapshot.data!);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) =>
            FTheme(data: FTheme.neutral.light.touch, child: child!),
        home: FScaffold(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError
                        ? 'Unable to open Smart Walker'
                        : 'Opening Smart Walker…',
                  ),
                  if (snapshot.hasError) ...[
                    const SizedBox(height: 16),
                    Text('${snapshot.error}'),
                    const SizedBox(height: 16),
                    FButton(
                      onPress: () => setState(() {
                        _dependencies = AppDependencies.create();
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
