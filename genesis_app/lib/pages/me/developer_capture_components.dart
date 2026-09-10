part of 'developer_page.dart';

class _DeveloperCaptureHeader extends StatelessWidget {
  const _DeveloperCaptureHeader({
    required this.title,
    required this.totalCount,
    required this.clearKey,
    required this.switchKey,
    required this.enabled,
    required this.onClear,
    required this.onEnabledChanged,
    this.visibleCount,
    this.enabledControl = true,
    this.countKey,
  });

  final String title;
  final int totalCount;
  final int? visibleCount;
  final Key? countKey;
  final Key clearKey;
  final Key switchKey;
  final bool enabled;
  final bool enabledControl;
  final VoidCallback? onClear;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final count = visibleCount == null || visibleCount == totalCount
        ? '$totalCount'
        : '${visibleCount!}/$totalCount';
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
        Text(
          count,
          key: countKey,
          style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          key: clearKey,
          behavior: HitTestBehavior.opaque,
          onTap: onClear,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Clear',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: onClear == null
                    ? const Color(0xFFBBBBBB)
                    : const Color(0xFFFF2442),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          height: 32,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Switch(
              key: switchKey,
              value: enabled,
              onChanged: enabledControl ? onEnabledChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeveloperCaptureFilterChip extends StatelessWidget {
  const _DeveloperCaptureFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFEDF0) : const Color(0xFFF2F2F4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFFF2442) : Colors.transparent,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? const Color(0xFFFF2442) : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeveloperCaptureDetailSection extends StatelessWidget {
  const _DeveloperCaptureDetailSection({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.content,
    required this.contentKey,
    this.copyLabel,
    this.copyKey,
    this.selectable = false,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final String content;
  final Key contentKey;
  final String? copyLabel;
  final Key? copyKey;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (copyLabel != null)
                  GestureDetector(
                    key: copyKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: content));
                      if (context.mounted) {
                        showGenesisToast(context, copyLabel!);
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.copy, size: 15),
                    ),
                  ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: selectable
                ? SelectionArea(child: _contentText())
                : _contentText(),
          ),
      ],
    );
  }

  Text _contentText() {
    return Text(
      content,
      key: contentKey,
      style: const TextStyle(
        fontFamily: GenesisTypography.fontFamily,
        fontFamilyFallback: GenesisTypography.fontFamilyFallback,
        fontSize: 11,
        height: 1.35,
        color: Color(0xFF333333),
      ),
    );
  }
}
