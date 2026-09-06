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

class CreateFormDeleteButton extends StatelessWidget {
  const CreateFormDeleteButton({
    super.key,
    required this.onPressed,
    this.buttonKey,
    this.decorationKey,
    this.size = 24,
    this.iconSize = 14,
    this.backgroundColor = const Color(0xE6F4F4F6),
    this.iconColor = const Color(0xFF666666),
    this.borderSide = const BorderSide(color: Color(0xFFD8D8DE)),
    this.borderRadius,
    this.enabled = true,
    this.onDisabledPressed,
  });

  final VoidCallback onPressed;
  final Key? buttonKey;
  final Key? decorationKey;
  final double size;
  final double iconSize;
  final Color backgroundColor;
  final Color iconColor;
  final BorderSide borderSide;
  final BorderRadius? borderRadius;
  final bool enabled;
  final VoidCallback? onDisabledPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? null : onDisabledPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                key: decorationKey,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  border: Border.fromBorderSide(borderSide),
                  borderRadius: borderRadius ?? BorderRadius.circular(size / 4),
                ),
              ),
              IconButton(
                key: buttonKey,
                onPressed: enabled ? onPressed : null,
                padding: EdgeInsets.all((size - iconSize) / 2),
                constraints: BoxConstraints.tightFor(width: size, height: size),
                icon: SvgPicture.asset(
                  createFormDeleteIconAsset,
                  width: iconSize,
                  height: iconSize,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                ),
                splashRadius: size / 2,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: showBorder
            ? Border.all(color: createFormBorder, width: 1.2)
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
                          style: const TextStyle(
                            color: Color(0xFFA8A8AD),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    color: createFormText,
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
              CreateFormDeleteButton(
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
