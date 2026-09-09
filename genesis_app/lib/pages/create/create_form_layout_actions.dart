part of 'create_form_library.dart';

class CreateKeyboardDismissArea extends StatelessWidget {
  const CreateKeyboardDismissArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

class CreateFormCard extends StatelessWidget {
  const CreateFormCard({
    super.key,
    required this.title,
    required this.onDelete,
    required this.child,
    this.deleteEnabled = true,
    this.onDeleteDisabled,
    this.showBorder = true,
    this.titleFontSize = 16,
    this.titleSuffix,
  });

  final String title;
  final VoidCallback onDelete;
  final Widget child;
  final bool deleteEnabled;
  final VoidCallback? onDeleteDisabled;
  final bool showBorder;
  final double titleFontSize;
  final String? titleSuffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: showBorder
          ? const EdgeInsets.fromLTRB(18, 6, 18, 22)
          : const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: CreateFormTheme.colorOf(
          context,
          Colors.white,
          GenesisColors.darkBackground,
        ),
        borderRadius: BorderRadius.circular(8),
        border: showBorder
            ? Border.all(
                color: CreateFormTheme.colorOf(
                  context,
                  createFormBorder,
                  GenesisColors.darkFaintFill,
                ),
                width: 1.2,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: title,
                    children: [
                      if (titleSuffix?.trim().isNotEmpty == true)
                        TextSpan(
                          text: ' ${titleSuffix!.trim()}',
                          style: TextStyle(
                            color: CreateFormTheme.colorOf(
                              context,
                              const Color(0xFFA8A8AD),
                              GenesisColors.darkTextTertiary,
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    color: CreateFormTheme.colorOf(
                      context,
                      createFormText,
                      GenesisColors.darkTextPrimary,
                    ),
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
              GenesisDeleteButton(
                onPressed: onDelete,
                enabled: deleteEnabled,
                onDisabledPressed: onDeleteDisabled,
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

Future<bool> confirmCreateFormDelete(
  BuildContext context, {
  required String itemLabel,
}) async {
  final confirmed = await showGenesisDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          'Delete $itemLabel?',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: const Text('This item has content. Delete it anyway?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
