import 'package:flutter/material.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/bootstrap/service_registry.dart';
import '../../platform/session/user_session_store.dart';
import 'gem_purchase_state.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/tokens/genesis_colors.dart';

/// Resolves purchase tabs before building either catalog; never requests login.
class PurchaseSessionBuilder extends StatefulWidget {
  const PurchaseSessionBuilder({
    super.key,
    required this.builder,
    this.backgroundColor = GenesisColors.darkBackground,
  });

  final Color backgroundColor;

  final Widget Function(BuildContext context, bool showBuyGems) builder;

  @override
  State<PurchaseSessionBuilder> createState() => _PurchaseSessionBuilderState();
}

class _PurchaseSessionBuilderState extends State<PurchaseSessionBuilder> {
  AppServices? _services;
  Future<String?>? _loginUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServicesScope.maybeOf(context);
    if (identical(services, _services)) return;
    _services?.sessionRevision.removeListener(_sessionChanged);
    _services = services;
    services?.sessionRevision.addListener(_sessionChanged);
    _loginUid = services?.sessionStore.readLoginUid();
  }

  void _sessionChanged() {
    setState(() {
      _loginUid = _services?.sessionStore.readLoginUid();
    });
  }

  @override
  void dispose() {
    _services?.sessionRevision.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_services == null) return widget.builder(context, false);
    return GenesisDarkTheme(
      child: FutureBuilder<String?>(
        future: _loginUid,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ColoredBox(
              color: widget.backgroundColor,
              child: const GemPurchaseLoading(),
            );
          }
          // A different account must not retain the previous tabs or Gems data.
          final uid = snapshot.hasError ? null : snapshot.data;
          return KeyedSubtree(
            key: ValueKey(uid),
            child: widget.builder(context, uid != null),
          );
        },
      ),
    );
  }
}
