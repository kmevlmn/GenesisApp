part of 'gem_wallet_page.dart';

class _TaskActionButton extends StatelessWidget {
  const _TaskActionButton({
    required this.task,
    required this.status,
    required this.isLoading,
    required this.onTap,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.textHeight,
    this.alignment = Alignment.center,
  });

  final GemTask task;
  final String status;
  final bool isLoading;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double borderRadius;
  final double textHeight;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final enabled =
        !isLoading && (status == 'in_progress' || status == 'claimable');
    final foregroundColor = switch (status) {
      'claimable' => GenesisColors.redSecondary,
      'in_progress' => kGemTaskProgressForegroundColor,
      'claimed' => kGemTaskClaimedForegroundColor,
      _ => kGemTaskActionColor,
    };
    final actionText = status == task.status
        ? task.actionText
        : switch (status) {
            'claimable' => 'Claim',
            'claimed' => 'Claimed',
            _ => task.actionText,
          };
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        key: ValueKey<String>('gem-task-action-${task.taskCode}'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : () {},
        child: Container(
          width: width,
          height: height,
          alignment: alignment,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Text(
            actionText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: textHeight,
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _GemSectionStatePanel extends StatelessWidget {
  const _GemSectionStatePanel({
    required this.isLoading,
    required this.hasError,
    required this.errorMessage,
    required this.onRetry,
  });

  final bool isLoading;
  final bool hasError;
  final String errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return isLoading || !hasError
        ? const SizedBox(height: 96, child: GemPurchaseLoading(size: 20))
        : GemPurchaseState(message: errorMessage, height: 96, onRetry: onRetry);
  }
}
