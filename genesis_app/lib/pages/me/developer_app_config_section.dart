part of 'developer_page.dart';

class _DeveloperAppConfigSection extends StatelessWidget {
  const _DeveloperAppConfigSection();

  @override
  Widget build(BuildContext context) {
    final store = AppServicesScope.of(context).appGlobalConfig;
    return ValueListenableBuilder<AppGlobalConfigRequestState>(
      valueListenable: store.requestState,
      builder: (context, state, _) {
        final data = state.data;
        final status = state.isLoading
            ? 'Request in progress…'
            : state.error != null
            ? 'Request failed: ${state.error}'
            : data == null
            ? 'No response received yet.'
            : data.isEmpty
            ? 'Response data is empty.'
            : '${data.length} keys';
        return _DeveloperTestSectionPanel(
          key: const ValueKey<String>('developer-app-config-panel'),
          child: ExpansionTile(
            key: const PageStorageKey<String>('developer-app-config-expanded'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            shape: const Border(),
            collapsedShape: const Border(),
            iconColor: Colors.black,
            collapsedIconColor: Colors.black,
            title: const _DeveloperSectionTitle('App Config'),
            subtitle: const Text(
              'GET /api/v1/app/config',
              style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                status,
                // SelectableText has its own scroll position. Keep its stored
                // offset separate from ExpansionTile's boolean expanded state.
                key: const PageStorageKey<String>(
                  'developer-app-config-status',
                ),
                style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
              ),
              if (data != null && data.isNotEmpty) ...[
                if (state.isLoading || state.error != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Last successful response',
                    style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                  ),
                ],
                const SizedBox(height: 12),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(1.2),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.top,
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: Color(0xFFE1E1E3)),
                  ),
                  children: [
                    const TableRow(
                      children: [
                        _DeveloperAppConfigCell(
                          'Key',
                          key: PageStorageKey<String>(
                            'developer-app-config-header-key',
                          ),
                          isKey: true,
                        ),
                        _DeveloperAppConfigCell(
                          'Value',
                          key: PageStorageKey<String>(
                            'developer-app-config-header-value',
                          ),
                          isKey: true,
                        ),
                      ],
                    ),
                    for (final entry in data.entries)
                      TableRow(
                        children: [
                          _DeveloperAppConfigCell(
                            entry.key,
                            key: PageStorageKey<String>(
                              'developer-app-config-key-${entry.key}',
                            ),
                            isKey: true,
                          ),
                          _DeveloperAppConfigCell(
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(entry.value),
                            key: PageStorageKey<String>(
                              'developer-app-config-value-${entry.key}',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DeveloperAppConfigCell extends StatelessWidget {
  const _DeveloperAppConfigCell(this.text, {super.key, this.isKey = false});

  final String text;
  final bool isKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
      child: SelectableText(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: isKey ? Colors.black : const Color(0xFF666666),
          fontWeight: isKey ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
