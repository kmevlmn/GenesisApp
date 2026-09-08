import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/components/genesis_refresh_indicator.dart';
import '../../app/bootstrap/app_services_scope.dart';
import '../../app/debug_page_tracker.dart';
import '../../app/gems/gem_task_analytics.dart';
import '../../app/gems/gem_wallet_store.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/common/genesis_modal_routes.dart';
import '../../components/gems/daily_check_in_dialog.dart';
import '../../components/gems/gem_assets.dart';
import '../../components/gems/gem_billing_purchase_dialog.dart';
import '../../components/gems/gem_colors.dart';
import '../../components/gems/gem_purchase_catalog.dart';
import '../../components/page_header.dart';
import '../../network/models/gem_product.dart';
import '../../network/models/gem_task.dart';
import '../../network/models/gem_task_action.dart';
import '../../platform/billing/billing_models.dart';
import '../../platform/billing/billing_service.dart';
import '../../routers/app_router.dart';
import '../../utils/gem_amount.dart';

part 'gem_wallet_data_actions.dart';
part 'gem_wallet_billing_flow.dart';
part 'gem_wallet_content.dart';
part 'gem_wallet_state_panels.dart';

typedef GemTaskActionHandler =
    Future<GemTaskActionResult> Function(String taskCode);
typedef GemProductsLoader =
    Future<List<GemProduct>> Function(BuildContext context);
typedef GemTasksLoader =
    Future<List<GemTaskGroup>> Function(BuildContext context);
typedef DiscordLauncher = Future<bool> Function(Uri uri);

class GemWalletPage extends StatefulWidget {
  const GemWalletPage({
    super.key,
    this.productsLoader,
    this.tasksLoader,
    this.walletStore,
    this.billingService,
    this.taskReporter,
    this.taskClaimer,
    this.discordLauncher,
  });

  final GemProductsLoader? productsLoader;
  final GemTasksLoader? tasksLoader;
  final GemWalletStore? walletStore;
  final BillingService? billingService;
  final GemTaskActionHandler? taskReporter;
  final GemTaskActionHandler? taskClaimer;
  final DiscordLauncher? discordLauncher;

  @override
  State<GemWalletPage> createState() => _GemWalletPageState();
}

Future<void> showGemBillingPurchaseOverlayPreview(BuildContext context) async {
  final state = ValueNotifier<GemBillingPurchaseDialogState>(
    GemBillingPurchaseDialogState.processing(attemptId: 'developer_preview'),
  );
  Timer? successTimer;
  successTimer = Timer(const Duration(milliseconds: 1200), () {
    state.value = GemBillingPurchaseDialogState.success(
      attemptId: 'developer_preview',
      grantedText: '550',
    );
  });
  await showGenesisGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Center(
        child: GemBillingPurchaseDialog(
          state: state,
          onConfirm: () => Navigator.of(dialogContext).pop(),
        ),
      );
    },
  );
  successTimer.cancel();
  state.dispose();
}

class _GemWalletPageState extends State<GemWalletPage>
    with WidgetsBindingObserver, RouteAware {
  static final Uri _discordUri = Uri.parse('https://discord.gg/wuKHk7cyX7');
  List<GemProduct>? _products;
  List<GemTaskGroup>? _taskGroups;
  Object? _productsError;
  Object? _tasksError;
  bool _productsLoading = false;
  bool _tasksLoading = false;
  bool _primaryLoading = true;
  BillingService? _billingService;
  StreamSubscription<BillingUiEvent>? _billingEvents;
  PageRoute<dynamic>? _subscribedRoute;
  int _productsRequestGeneration = 0;
  int _tasksRequestGeneration = 0;
  final Set<String> _loadingTaskCodes = <String>{};
  final Map<String, String> _taskStatusOverrides = <String, String>{};
  final ValueNotifier<BillingState> _idleBillingState =
      ValueNotifier<BillingState>(BillingState());
  late final String _payTrackPageId = newBillingTrackPageId();
  ValueNotifier<GemBillingPurchaseDialogState>? _billingPurchaseDialogState;
  bool _billingPurchaseDialogShowing = false;
  bool _billingPurchaseDialogDismissing = false;
  bool _storeRecoveryStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _trackBuyGemsPageView();
    unawaited(_refreshAll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    genesisPageRouteObserver.unsubscribe(this);
    _billingEvents?.cancel();
    _disposeBillingPurchaseDialogState();
    _idleBillingState.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && !identical(route, _subscribedRoute)) {
      genesisPageRouteObserver.unsubscribe(this);
      _subscribedRoute = route;
      genesisPageRouteObserver.subscribe(this, route);
    }
    final billingService =
        widget.billingService ?? AppServicesScope.maybeOf(context)?.billing;
    if (billingService != null) _bindBillingService(billingService);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAll(silent: _hasPageData));
    }
  }

  @override
  void didPopNext() {
    // Do not refresh Gems data when an overlay route is dismissed.
  }

  bool get _hasPageData => _products != null || _taskGroups != null;

  void _trackBuyGemsPageView() {
    GenesisTelemetry.collectLog(
      actionType: 'pay_event',
      action: 'buy_page_show',
      object1: BillingPurchaseSource.buyGemsPage.value,
      object2: billingPageTrackId(_payTrackPageId),
    );
  }

  void _updateState(VoidCallback callback) => setState(callback);

  @override
  Widget build(BuildContext context) {
    final walletStateListenable = _walletStateListenable;
    return PopScope(
      canPop: !_billingPurchaseDialogShowing,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: GenesisBackAppBar(
          pageName: 'Buy Gems',
          systemOverlayStyle: kGenesisDefaultSystemUiOverlayStyle,
          actions: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  Navigator.of(context).pushNamed(RouteNames.gemRecords),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 20, 10),
                child: Text(
                  'Records',
                  style: TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 12,
                    height: 18 / 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(child: _buildBody(walletStateListenable)),
      ),
    );
  }

  Widget _buildBody(ValueListenable<GemWalletState> walletStateListenable) {
    if (_primaryLoading) {
      return const _GemWalletLoading();
    }
    if (!_hasPageData && _productsError != null && _tasksError != null) {
      return _GemWalletError(onRetry: () => unawaited(_refreshAll()));
    }
    return GenesisRefreshIndicator(
      color: kGemAccentColor,
      onRefresh: () => _refreshAll(silent: true),
      child: _GemWalletContent(
        products: _products,
        taskGroups: _taskGroups,
        productsLoading: _productsLoading,
        tasksLoading: _tasksLoading,
        productsError: _productsError,
        tasksError: _tasksError,
        walletStateListenable: walletStateListenable,
        billingStateListenable: _billingStateListenable,
        onPurchase: _purchaseProduct,
        onRetryProducts: () => unawaited(_refreshProducts()),
        onRetryTasks: () => unawaited(_refreshTasks()),
        taskStatusFor: _taskStatus,
        isTaskLoading: _loadingTaskCodes.contains,
        onTaskTap: _handleTaskTap,
        onJoinUsTap: _handleJoinUsRowTap,
      ),
    );
  }
}
