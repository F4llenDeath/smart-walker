import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    super.key,
  });
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => FCard(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(color: context.theme.colors.mutedForeground),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner(
    this.title, {
    this.message,
    this.destructive = false,
    super.key,
  });
  final String title;
  final String? message;
  final bool destructive;

  @override
  Widget build(BuildContext context) => FAlert(
    variant: destructive ? FAlertVariant.destructive : FAlertVariant.primary,
    title: Text(title),
    subtitle: message == null ? null : Text(message!),
  );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
}) async =>
    await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style,
        animation: animation,
        clipBehavior: Clip.antiAlias,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 24),
              FButton(
                variant: FButtonVariant.destructive,
                onPress: () => Navigator.pop(context, true),
                child: Text(action),
              ),
              const SizedBox(height: 8),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;

Future<void> showProblem(BuildContext context, Object exception) =>
    showFDialog<void>(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style,
        animation: animation,
        clipBehavior: Clip.antiAlias,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NoticeBanner(
                'Action could not be completed',
                message: '$exception',
                destructive: true,
              ),
              const SizedBox(height: 16),
              FButton(
                onPress: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );

Future<void> showPanel(BuildContext context, Widget child) {
  if (MediaQuery.sizeOf(context).width >= 700) {
    return showFDialog<void>(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style,
        animation: animation,
        clipBehavior: Clip.antiAlias,
        builder: (context, _) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: 0.9,
    useSafeArea: true,
    builder: (context) => FCard(
      style: FCardStyleDelta.delta(
        decoration: DecorationDelta.shapeDelta(
          color: context.theme.colors.card,
          shape: RoundedSuperellipseBorder(
            side: BorderSide(
              color: context.theme.colors.border,
              width: context.theme.style.borderWidth,
            ),
            borderRadius: BorderRadius.only(
              topLeft: context.theme.style.borderRadius.lg.topLeft,
              topRight: context.theme.style.borderRadius.lg.topRight,
            ),
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(
          label,
          style: TextStyle(color: context.theme.colors.mutedForeground),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    ),
  );
}
