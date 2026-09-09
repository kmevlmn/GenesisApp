part of 'origin_editor_pages.dart';

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
    this.modified = false,
    this.wrapFirstSummaryLine = false,
    this.showDivider = true,
  });

  final String? icon;
  final String title;
  final String summary;
  final VoidCallback? onTap;
  final bool modified;
  final bool wrapFirstSummaryLine;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  key: ValueKey<String>('section-icon-$title'),
                  width: 24,
                  height: 24,
                  child: icon == null
                      ? null
                      : SvgPicture.asset(
                          icon!,
                          fit: BoxFit.contain,
                          colorFilter: const ColorFilter.mode(
                            GenesisColors.darkTextSecondary,
                            BlendMode.srcIn,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    key: ValueKey<String>('section-content-$title'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(
                                      color: GenesisColors.darkTextPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                if (modified) ...[
                                  const SizedBox(width: 6),
                                  _ModifiedSectionBadge(
                                    key: ValueKey('section-modified-$title'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (onTap != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              key: ValueKey<String>('section-chevron-$title'),
                              color: GenesisColors.darkTextTertiary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            int index = 0;
                            index < _summaryLines.length;
                            index++
                          )
                            SizedBox(
                              width: double.infinity,
                              child: Text.rich(
                                TextSpan(
                                  children: _summaryLineSpans(
                                    _summaryLines[index],
                                  ),
                                ),
                                key: ValueKey<String>(
                                  'section-summary-line-$title-$index',
                                ),
                                textAlign: TextAlign.left,
                                maxLines: wrapFirstSummaryLine && index == 0
                                    ? null
                                    : 1,
                                overflow: wrapFirstSummaryLine && index == 0
                                    ? null
                                    : TextOverflow.ellipsis,
                                softWrap: wrapFirstSummaryLine && index == 0,
                                style: TextStyle(
                                  color: summary == 'Not started yet'
                                      ? GenesisColors.darkTextTertiary
                                      : GenesisColors.darkTextSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showDivider)
            const Divider(
              height: 1,
              thickness: 1,
              color: GenesisColors.darkFaintFill,
            ),
        ],
      ),
    );
  }

  List<String> get _summaryLines {
    return summary
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  List<InlineSpan> _summaryLineSpans(String line) {
    final colonIndex = line.indexOf(':');
    if (colonIndex < 0) return <InlineSpan>[TextSpan(text: line)];
    return <InlineSpan>[
      TextSpan(
        text: line.substring(0, colonIndex + 1),
        style: const TextStyle(color: GenesisColors.darkTextTertiary),
      ),
      TextSpan(text: line.substring(colonIndex + 1)),
    ];
  }
}

class _ModifiedSectionBadge extends StatelessWidget {
  const _ModifiedSectionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: SvgPicture.asset(
        refreshModifiedIconAsset,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(
          GenesisColors.redSecondary,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
