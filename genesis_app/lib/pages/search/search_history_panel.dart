part of 'search_page.dart';

class _SearchHistoryPanel extends StatelessWidget {
  const _SearchHistoryPanel({required this.queries, required this.onSelect});

  final List<String> queries;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (queries.isEmpty) return const SizedBox.shrink();

    final visibleQueries = queries.take(20);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxTagWidth = constraints.maxWidth - 32;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Search history',
                  style: TextStyle(
                    color: GenesisColors.darkTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  children: [
                    for (final query in visibleQueries)
                      _SearchHistoryTag(
                        query: query,
                        maxWidth: maxTagWidth,
                        onTap: () => onSelect(query),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchHistoryTag extends StatelessWidget {
  const _SearchHistoryTag({
    required this.query,
    required this.maxWidth,
    required this.onTap,
  });

  final String query;
  final double maxWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: GenesisColors.darkFaintFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 30,
              child: Center(
                widthFactor: 1,
                child: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GenesisColors.darkTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
