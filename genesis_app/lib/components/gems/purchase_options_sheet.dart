import 'package:flutter/material.dart';

import '../common/genesis_bottom_sheet_panel.dart';

enum PurchaseSheetTab { subscription, buyGems }

/// Shared purchase shell. Subscription is a presentation-only placeholder.
class PurchaseOptionsSheet extends StatefulWidget {
  const PurchaseOptionsSheet({
    super.key,
    required this.gemsBuilder,
    this.initialTab = PurchaseSheetTab.buyGems,
  });

  final WidgetBuilder gemsBuilder;
  final PurchaseSheetTab initialTab;

  @override
  State<PurchaseOptionsSheet> createState() => _PurchaseOptionsSheetState();
}

class _PurchaseOptionsSheetState extends State<PurchaseOptionsSheet> {
  late int _selected = widget.initialTab.index;
  late bool _gemsVisited = _selected == PurchaseSheetTab.buyGems.index;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GenesisBottomSheetPanel(
        title: '',
        height: constraints.maxHeight,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        titleWidget: SizedBox(
          height: 24,
          child: Row(
            children: [
              for (var index = 0; index < 2; index++) ...[
                if (index > 0) const SizedBox(width: 24),
                Flexible(
                  child: Semantics(
                    button: true,
                    selected: _selected == index,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        _selected = index;
                        _gemsVisited |= index == PurchaseSheetTab.buyGems.index;
                      }),
                      child: Text(
                        index == 0 ? 'Subscription' : 'Buy Gems',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GenesisBottomSheetPanel.titleStyle.copyWith(
                          color: _selected == index
                              ? const Color(0xFF111111)
                              : const Color(0xFF999999),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: GenesisBottomSheetCloseButton(
          buttonKey: const ValueKey('gem-purchase-sheet-close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        child: IndexedStack(
          index: _selected,
          sizing: StackFit.expand,
          children: [
            const SizedBox.expand(key: ValueKey('subscription-placeholder')),
            if (_gemsVisited)
              widget.gemsBuilder(context)
            else
              const SizedBox.expand(),
          ],
        ),
      ),
    );
  }
}
