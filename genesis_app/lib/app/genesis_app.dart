import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/developer_debug_floating_button.dart';
import '../components/internal_build_indicator.dart';
import '../components/gems/membership_guest_login_gate.dart';
import 'agent_control/agent_control_host.dart';
import 'debug_page_tracker.dart';
import 'genesis_navigator.dart';
import 'telemetry/genesis_telemetry.dart';
import 'version/force_upgrade_gate.dart';
import '../routers/app_router.dart';
import '../ui/genesis_ui.dart';
import 'bootstrap/app_services_scope.dart';
import 'bootstrap/service_registry.dart';

class GenesisApp extends StatelessWidget {
  const GenesisApp({super.key, this.services, this.initialIndex = 0});

  final AppServices? services;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    var initialRoutePending = true;
    return AppServicesScope(
      services: services ?? ServiceRegistry.build(),
      child: AgentControlHost(
        child: MaterialApp(
          title: 'Worldo',
          debugShowCheckedModeBanner: false,
          theme: GenesisTheme.light(),
          scrollBehavior: const GenesisScrollBehavior(),
          initialRoute: RouteNames.home,
          navigatorKey: genesisNavigatorKey,
          navigatorObservers: [genesisRouteObserver, genesisPageRouteObserver],
          onGenerateInitialRoutes: (_) {
            initialRoutePending = false;
            return <Route<dynamic>>[
              AppRouter.onGenerateRoute(
                RouteSettings(name: RouteNames.home, arguments: initialIndex),
              ),
            ];
          },
          onGenerateRoute: (settings) {
            if (settings.name == RouteNames.home &&
                settings.arguments == null &&
                initialRoutePending) {
              initialRoutePending = false;
              return AppRouter.onGenerateRoute(
                RouteSettings(name: RouteNames.home, arguments: initialIndex),
              );
            }
            return AppRouter.onGenerateRoute(settings);
          },
          builder: (context, child) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: kGenesisDefaultSystemUiOverlayStyle,
              child: GenesisTelemetryTapRegion(
                child: GenesisBottomSystemBarBoundary(
                  child: InternalBuildIndicator(
                    child: ForceUpgradeGate(
                      child: DeveloperDebugFloatingButton(
                        navigatorKey: genesisNavigatorKey,
                        child: MembershipGuestLoginGate(
                          service: AppServicesScope.read(
                            context,
                          ).membershipPurchases,
                          navigatorKey: genesisNavigatorKey,
                          child: child ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
