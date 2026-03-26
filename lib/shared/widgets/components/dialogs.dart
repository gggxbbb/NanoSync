import 'package:fluent_ui/fluent_ui.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmText = '确定',
  String cancelText = '取消',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        Button(
          child: Text(cancelText),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          style: isDestructive
              ? ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(Colors.red),
                )
              : null,
          child: Text(confirmText),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String content,
  String buttonText = '确定',
}) async {
  await showDialog(
    context: context,
    builder: (context) => ContentDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        FilledButton(
          child: Text(buttonText),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}
