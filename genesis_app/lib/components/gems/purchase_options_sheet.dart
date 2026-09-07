import 'package:flutter/material.dart';

import '../common/genesis_bottom_sheet_panel.dart';
import '../common/genesis_modal_routes.dart';
import '../page_header.dart';
import 'pro_subscription_content.dart';
import 'wallet_purchase_tabs.dart';

enum PurchaseSheetTab { subscription, buyGems }

/// Shared purchase shell with Wallet's tabs and subscription presentation.
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

class _PurchaseOptionsSheetState extends State<PurchaseOptionsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late bool _gemsVisited;

  @override
  void initState() {
    super.initState();
    _gemsVisited = widget.initialTab == PurchaseSheetTab.buyGems;
    _tabs = TabController(
      length: 2,
      initialIndex: widget.initialTab.index,
      vsync: this,
    );
    _tabs.addListener(_visitGems);
    _tabs.animation!.addListener(_visitGems);
  }

  void _visitGems() {
    if (!_gemsVisited &&
        (_tabs.index == PurchaseSheetTab.buyGems.index ||
            _tabs.animation!.value > 0)) {
      setState(() => _gemsVisited = true);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_visitGems);
    _tabs.animation!.removeListener(_visitGems);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GenesisBottomSheetPanel(
        title: '',
        height: constraints.maxHeight,
        // Retain the existing close center (32px) and body start (64px).
        padding: const EdgeInsets.fromLTRB(0, 7, 0, 10),
        titleBottomSpacing: 7,
        titleWidget: SizedBox(
          height: kGenesisTopBarHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Center(child: WalletPurchaseTabs(controller: _tabs)),
              ),
              Positioned(
                right: 20,
                child: GenesisBottomSheetCloseButton(
                  buttonKey: const ValueKey('gem-purchase-sheet-close'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
        child: TabBarView(
          key: const ValueKey('purchase-sheet-pages'),
          controller: _tabs,
          children: [
            const _PurchaseSheetPage(child: ProSubscriptionContent()),
            _PurchaseSheetPage(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _gemsVisited
                    ? Builder(builder: widget.gemsBuilder)
                    : const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseSheetPage extends StatefulWidget {
  const _PurchaseSheetPage({required this.child});

  final Widget child;

  @override
  State<_PurchaseSheetPage> createState() => _PurchaseSheetPageState();
}

class _PurchaseSheetPageState extends State<_PurchaseSheetPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GenesisBottomSheetDragDismissArea(
      onDismiss: () {
        // The route can also be dismissed by its native header drag.
        if (ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      },
      child: widget.child,
    );
  }
}
