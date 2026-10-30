import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../shared/widgets/panels.dart';
import 'device_status_panel.dart';

class ConnectionStatusButton extends StatefulWidget {
  const ConnectionStatusButton({
    required this.dependencies,
    this.usePopover = false,
    super.key,
  });

  final AppDependencies dependencies;
  final bool usePopover;

  @override
  State<ConnectionStatusButton> createState() => _ConnectionStatusButtonState();
}

class _ConnectionStatusButtonState extends State<ConnectionStatusButton> {
  final FocusNode _focus = FocusNode(debugLabel: 'Sensor connections');

  Widget _button(VoidCallback onPress) => ListenableBuilder(
    listenable: widget.dependencies.telemetry,
    builder: (context, _) {
      final telemetry = widget.dependencies.telemetry;
      return FButton(
        focusNode: _focus,
        variant: FButtonVariant.outline,
        mainAxisSize: MainAxisSize.min,
        prefix: const Icon(FLucideIcons.bluetooth),
        onPress: onPress,
        child: Text(
          telemetry.simulating ? 'SIM' : '${telemetry.snapshot.readyCount}/3',
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.usePopover) {
      return _button(
        () => showPanel(
          context,
          DeviceStatusPanel(dependencies: widget.dependencies),
        ),
      );
    }
    return FPopover(
      childFocusNode: _focus,
      popoverAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      constraints: FPortalConstraints(
        minWidth: 320,
        maxWidth: 360,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      popoverClipBehavior: Clip.antiAlias,
      popoverBuilder: (context, controller) => DeviceStatusPanel(
        dependencies: widget.dependencies,
        onClose: () => controller.hide(),
      ),
      builder: (context, controller, _) => _button(() => controller.toggle()),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }
}
