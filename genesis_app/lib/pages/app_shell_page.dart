import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/bootstrap/app_services_scope.dart';
import '../app/bootstrap/polling_scheduler.dart';
import '../app/gems/daily_check_in_coordinator.dart';
import '../app/startup/app_startup_coordinator.dart';
import '../app/telemetry/genesis_telemetry.dart';
import '../components/auth/login_guard.dart';
import '../components/bottom_tabs.dart';
import '../network/api_client.dart';
import '../network/models/unread_summary.dart';
import '../platform/auth/auth_session.dart';
import '../platform/billing/billing_models.dart';
import '../platform/privacy/app_tracking_transparency_service.dart';
import '../platform/session/user_session_store.dart';
import '../ui/system/genesis_system_ui.dart';
import '../ui/navigation/genesis_dark_page_route.dart';
import '../ui/tokens/genesis_colors.dart';
import 'create/create_origin_page.dart';
import 'home/home_page.dart';
import 'me/me_page.dart';
import 'messages/messages_page.dart';
import 'origin/origin_page.dart';

typedef AttAuthorizationStatusReader =
    Future<AppTrackingAuthorizationStatus> Function();
typedef AttAuthorizationRequester =
    Future<AppTrackingAuthorizationStatus> Function();

class AppShellPage extends StatefulWidget {
  const AppShellPage({
    super.key,
    required this.initialIndex,
    this.startupPlatform,
    this.trackingAuthorizationStatus =
        AppTrackingTransparencyService.authorizationStatus,
    this.requestTrackingAuthorization =
        AppTrackingTransparencyService.requestAuthorization,
  });

  final int initialIndex;
  final TargetPlatform? startupPlatform;
  final AttAuthorizationStatusReader trackingAuthorizationStatus;
  final AttAuthorizationRequester requestTrackingAuthorization;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage>
    with WidgetsBindingObserver {
  late int _selectedIndex;
  late final Set<int> _visitedTabIndexes;
  late final ValueNotifier<bool> _messagesTabActiveNotifier;
  late final ValueNotifier<bool> _meTabActiveNotifier;
  late final ValueNotifier<bool> _homeTabActiveNotifier;
  late final ValueNotifier<bool> _worldoTabActiveNotifier;
  late final ValueNotifier<int> _homeTabActivationNotifier;
  late final ValueNotifier<int> _worldoTabActivationNotifier;
  late final ValueNotifier<int> _meTabActivationNotifier;
  late final ValueNotifier<int> _homeTabReselectionNotifier;
  late final ValueNotifier<int> _messagesTabReselectionNotifier;
  late final ValueNotifier<int> _meTabReselectionNotifier;
  var _hasRecordedInitialTabPageView = false;
  final Set<String> _firstContentPageViewsReported = <String>{};
  var _worldoForYouContentReady = false;
  var _worldoFirstActivationPending = false;
  ValueListenable<int>? _sessionRevisionListenable;
  ValueListenable<String?>? _pendingLoginCheckInUid;
  ModalRoute<dynamic>? _mainRoute;
  bool _dailyCheckInScheduled = false;
  bool _dailyCheckInRunning = false;
  final Map<int, Widget> _tabPageCache = <int, Widget>{};
  PageStorageBucket _sessionPageStorageBucket = PageStorageBucket();
  var _sessionTabGeneration = 0;
  final ValueNotifier<UnreadSummary> _unreadSummaryNotifier =
      ValueNotifier<UnreadSummary>(UnreadSummary.zero);
  static const _messagesPollInterval = Duration(seconds: 30);
  late final GenesisPollingScheduler _messagesPoller;
  Timer? _attDelayTimer;
  var _attWaitingForResume = false;
  var _attScheduleStarted = false;
  var _initialBillingRecoveryStarted = false;
  late bool _hasSeenResumed;
  String? _lastBillingRecoveryUid;
  AppLifecycleState? _lifecycleState;

  @override
  void initState() {
    super.initState();
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    _hasSeenResumed = _lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    AppStartupCoordinator.postLaunchWorkAllowedListenable.addListener(
      _handlePostLaunchWorkAllowed,
    );
    _selectedIndex = _normalTabIndex(widget.initialIndex);
    _messagesTabActiveNotifier = ValueNotifier<bool>(_selectedIndex == 3);
    _meTabActiveNotifier = ValueNotifier<bool>(_selectedIndex == 4);
    _homeTabActiveNotifier = ValueNotifier<bool>(_selectedIndex == 0);
    _worldoTabActiveNotifier = ValueNotifier<bool>(_selectedIndex == 1);
    _homeTabActivationNotifier = ValueNotifier<int>(0);
    _worldoTabActivationNotifier = ValueNotifier<int>(0);
    _meTabActivationNotifier = ValueNotifier<int>(0);
    _homeTabReselectionNotifier = ValueNotifier<int>(0);
    _messagesTabReselectionNotifier = ValueNotifier<int>(0);
    _meTabReselectionNotifier = ValueNotifier<int>(0);
    _visitedTabIndexes = <int>{_selectedIndex};
    _messagesPoller = GenesisPollingScheduler(
      interval: _messagesPollInterval,
      onTick: _refreshMessagesData,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppStartupCoordinator.recordLaunchFirstFrame();
      // The final tab was selected before runApp. Keep route_ready_ms only as
      // a schema-v1 first-frame confirmation for existing dashboard data.
      AppStartupCoordinator.recordLaunchRouteReady();
      AppStartupCoordinator.recordLaunchPage();
      _startAppRuntime();
      _startPostLaunchWorkIfAllowed();
      _startInitialBillingRecoveryIfReady();
      _scheduleAttRequest();
      if (mounted) {
        // Startup can land on Worldo or Me with Home still unbuilt.
        final membership = AppServicesScope.read(context).membershipPurchases;
        if (membership != null) {
          unawaited(membership.checkGuestPurchasesOnHome());
        }
      }
    });
  }

  @override
  void dispose() {
    _attDelayTimer?.cancel();
    _sessionRevisionListenable?.removeListener(_handleSessionChanged);
    _pendingLoginCheckInUid?.removeListener(_schedulePendingDailyCheckIn);
    AppStartupCoordinator.postLaunchWorkAllowedListenable.removeListener(
      _handlePostLaunchWorkAllowed,
    );
    WidgetsBinding.instance.removeObserver(this);
    _stopMessagesPolling();
    _messagesTabActiveNotifier.dispose();
    _meTabActiveNotifier.dispose();
    _homeTabActiveNotifier.dispose();
    _worldoTabActiveNotifier.dispose();
    _homeTabActivationNotifier.dispose();
    _worldoTabActivationNotifier.dispose();
    _meTabActivationNotifier.dispose();
    _homeTabReselectionNotifier.dispose();
    _messagesTabReselectionNotifier.dispose();
    _meTabReselectionNotifier.dispose();
    _unreadSummaryNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previousState = _lifecycleState;
    final isFirstObservedResume = !_hasSeenResumed;
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _schedulePendingDailyCheckIn();
      _hasSeenResumed = true;
      _startInitialBillingRecoveryIfReady();
      if (!isFirstObservedResume &&
          previousState != AppLifecycleState.resumed) {
        unawaited(_recoverBilling(BillingRecoverySource.foreground));
      }
      if (_attWaitingForResume) {
        _attWaitingForResume = false;
        _requestAttIfNeeded();
      }
      if (AppStartupCoordinator.isPostLaunchWorkAllowed) {
        _startMessagesPolling();
        _notifyActiveTabActivated();
      }
    } else {
      _stopMessagesPolling();
    }
  }

  void _scheduleAttRequest() {
    if (!mounted || _attScheduleStarted) return;
    if ((widget.startupPlatform ?? defaultTargetPlatform) !=
        TargetPlatform.iOS) {
      _attScheduleStarted = true;
      return;
    }
    _attScheduleStarted = true;
    _attDelayTimer = Timer(const Duration(seconds: 2), () {
      _attDelayTimer = null;
      _requestAttIfNeeded();
    });
  }

  void _requestAttIfNeeded() {
    if (!mounted) return;
    if (_lifecycleState != null &&
        _lifecycleState != AppLifecycleState.resumed) {
      _attWaitingForResume = true;
      return;
    }
    if (!AppStartupCoordinator.claimAttRequest()) return;
    unawaited(_requestAtt());
  }

  Future<void> _requestAtt() async {
    try {
      final status = await widget.trackingAuthorizationStatus();
      if (status != AppTrackingAuthorizationStatus.notDetermined) return;
      final result = await widget.requestTrackingAuthorization();
      debugPrint('[ATT] authorization result: $result');
    } catch (error, stackTrace) {
      debugPrint('[ATT] authorization request failed: $error');
      debugPrint('[ATT] stacktrace:\n$stackTrace');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mainRoute = ModalRoute.of(context);
    final services = AppServicesScope.of(context);
    final pendingCheckIn = services.pendingLoginCheckInUid;
    if (!identical(_pendingLoginCheckInUid, pendingCheckIn)) {
      _pendingLoginCheckInUid?.removeListener(_schedulePendingDailyCheckIn);
      _pendingLoginCheckInUid = pendingCheckIn;
      pendingCheckIn.addListener(_schedulePendingDailyCheckIn);
    }
    final sessionRevision = services.sessionRevision;
    if (!identical(_sessionRevisionListenable, sessionRevision)) {
      _sessionRevisionListenable?.removeListener(_handleSessionChanged);
      _sessionRevisionListenable = sessionRevision;
      sessionRevision.addListener(_handleSessionChanged);
    }
    _schedulePendingDailyCheckIn();
  }

  bool _canShowLoginCheckIn() {
    return mounted &&
        _mainRoute?.isCurrent == true &&
        (_lifecycleState == null ||
            _lifecycleState == AppLifecycleState.resumed);
  }

  void _schedulePendingDailyCheckIn() {
    if (_dailyCheckInScheduled ||
        _dailyCheckInRunning ||
        _pendingLoginCheckInUid?.value == null ||
        !_canShowLoginCheckIn()) {
      return;
    }
    _dailyCheckInScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dailyCheckInScheduled = false;
      if (_canShowLoginCheckIn()) unawaited(_showPendingDailyCheckIn());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showPendingDailyCheckIn() async {
    if (_dailyCheckInRunning) return;
    _dailyCheckInRunning = true;
    try {
      await showPendingDailyCheckInAfterLogin(
        context,
        canShow: _canShowLoginCheckIn,
      );
    } finally {
      _dailyCheckInRunning = false;
      _schedulePendingDailyCheckIn();
    }
  }

  void _startMessagesPolling() {
    if (!mounted) return;
    _messagesPoller.start();
  }

  void _stopMessagesPolling() {
    _messagesPoller.stop();
  }

  void _handlePostLaunchWorkAllowed() {
    _startPostLaunchWorkIfAllowed();
  }

  void _startPostLaunchWorkIfAllowed() {
    if (!AppStartupCoordinator.isPostLaunchWorkAllowed) return;
    if (!_hasRecordedInitialTabPageView) {
      _hasRecordedInitialTabPageView = true;
      _recordSelectedTabPageView();
    }
    _startMessagesPolling();
    if (_selectedIndex == 4 && _meTabActivationNotifier.value == 0) {
      _notifyActiveTabActivated();
    }
  }

  void _startAppRuntime() {
    if (!mounted) return;
    final services = AppServicesScope.read(context);
    AppStartupCoordinator.startFirebasePerformance();
    AppStartupCoordinator.startWarmUp(services);
    unawaited(AppStartupCoordinator.initializeTelemetry(services: services));
  }

  Future<void> _refreshMessagesData() async {
    try {
      if (!await _hasLocalLoginSession()) {
        if (mounted && _unreadSummaryNotifier.value != UnreadSummary.zero) {
          _unreadSummaryNotifier.value = UnreadSummary.zero;
        }
        return;
      }
      if (!mounted) return;
      final services = AppServicesScope.read(context);
      final requests = <Future<void>>[
        _refreshUnreadSummary(),
        services.directMessageConversations.syncConversations(
          tracePolicy: ApiRequestTracePolicy.excluded,
        ),
      ];
      await Future.wait(requests);
    } catch (e, st) {
      debugPrint('[Messages][Poll] refresh failed: $e');
      debugPrint('[Messages][Poll] stacktrace:\n$st');
    }
  }

  Future<void> _refreshUnreadSummary() async {
    try {
      final summary = await AppServicesScope.read(context).api.v1.messages
          .unreadSummary(tracePolicy: ApiRequestTracePolicy.excluded);
      if (!mounted) return;
      _unreadSummaryNotifier.value = summary;
    } catch (e, st) {
      debugPrint('[Messages][Unread] unreadSummary polling failed: $e');
      debugPrint('[Messages][Unread] stacktrace:\n$st');
    }
  }

  Future<void> _onTapNav(int index) async {
    if (index == 0) {
      if (_selectedIndex == 0) {
        _homeTabReselectionNotifier.value += 1;
        return;
      }
      _selectTab(0);
      return;
    }

    if (index == 1) {
      if (_selectedIndex == 1) {
        _worldoTabActivationNotifier.value += 1;
        return;
      }
      _selectTab(1);
      return;
    }

    if (index == 2) {
      if (!await _ensureMainTabLogin()) return;
      if (!mounted) return;
      await Navigator.of(context).push(
        GenesisDarkPageRoute<void>(builder: (_) => const CreateOriginPage()),
      );
      return;
    }

    if (index == 3) {
      if (!await _ensureMainTabLogin()) return;
      if (!mounted) return;
      if (_selectedIndex == 3) {
        _messagesTabReselectionNotifier.value += 1;
        return;
      }
      _selectTab(3);
      unawaited(_messagesPoller.runNow());
      return;
    }

    if (index == 4) {
      if (_selectedIndex == 4) {
        _meTabReselectionNotifier.value += 1;
        return;
      }
      _selectTab(4);
      return;
    }
  }

  Future<bool> _ensureMainTabLogin() => ensureGenesisLogin(context);

  Future<bool> _hasLocalLoginSession() async {
    final services = AppServicesScope.read(context);
    return await services.sessionStore.readLoginUid() != null;
  }

  Future<bool> _loginWithProvider(IdentityProvider provider) async {
    debugPrint('[Auth][AppShell] onLogin start provider=$provider');
    final services = AppServicesScope.read(context);
    final session = await services.identityAuth.signIn(provider);
    final user = await services.backendAuth.loginWithIdentity(session);
    if (user.uid.trim().isNotEmpty) {
      await services.sessionStore.saveUid(user.uid);
    }
    final cachedUserInfo = await services.sessionStore.readUserInfo();
    final loginUserInfo = <String, dynamic>{
      if (cachedUserInfo != null) ...cachedUserInfo,
      'uid': user.uid,
      'login_provider': provider.name,
    };
    if (user.nickname.trim().isNotEmpty) {
      loginUserInfo['name'] = user.nickname;
    }
    if (user.avatar.trim().isNotEmpty) {
      loginUserInfo['avatar'] = user.avatar;
    }
    await services.sessionStore.saveUserInfo(loginUserInfo);
    services.notifySessionChanged();
    unawaited(_messagesPoller.runNow());
    debugPrint('[Auth][AppShell] backend login success uid=${user.uid}');
    return true;
  }

  int _normalTabIndex(int index) {
    return switch (index) {
      0 || 1 || 3 || 4 => index,
      _ => 0,
    };
  }

  void _selectTab(int index) {
    if (_selectedIndex == index && _visitedTabIndexes.contains(index)) {
      return;
    }
    final previousIndex = _selectedIndex;
    setState(() {
      _selectedIndex = index;
      _visitedTabIndexes.add(index);
    });
    _messagesTabActiveNotifier.value = _selectedIndex == 3;
    _meTabActiveNotifier.value = _selectedIndex == 4;
    _homeTabActiveNotifier.value = _selectedIndex == 0;
    _worldoTabActiveNotifier.value = _selectedIndex == 1;
    if (previousIndex != index) {
      _recordSelectedTabPageView();
      _notifyActiveTabActivated();
    }
  }

  void _recordSelectedTabPageView() {
    switch (_selectedIndex) {
      case 1:
        const action = 'worldo_list_tab';
        if (_isFirstContentPageViewReported(action)) {
          GenesisTelemetry.collectLog(actionType: 'pageview', action: action);
        } else {
          _worldoFirstActivationPending = true;
          _tryRecordFirstWorldoPageView();
        }
        return;
      case 3:
        GenesisTelemetry.collectLog(
          actionType: 'pageview',
          action: 'messages_home',
        );
        return;
      case 4:
        unawaited(_recordMeTabPageView());
        return;
    }
  }

  bool _isFirstContentPageViewReported(String action) {
    return _firstContentPageViewsReported.contains(action);
  }

  void _recordFirstContentPageView(String action) {
    if (!_firstContentPageViewsReported.add(action)) return;
    GenesisTelemetry.collectLog(actionType: 'pageview', action: action);
  }

  void _handleWorldoForYouFirstPageReady() {
    _worldoForYouContentReady = true;
    _tryRecordFirstWorldoPageView();
  }

  void _tryRecordFirstWorldoPageView() {
    const action = 'worldo_list_tab';
    if (!mounted ||
        _selectedIndex != 1 ||
        !_worldoFirstActivationPending ||
        !_worldoForYouContentReady ||
        _isFirstContentPageViewReported(action)) {
      return;
    }
    _recordFirstContentPageView(action);
  }

  Future<void> _recordMeTabPageView() async {
    final isLoggedIn = await _hasLocalLoginSession();
    GenesisTelemetry.collectLog(
      actionType: 'pageview',
      action: 'me',
      object1: isLoggedIn ? 'logged_in' : 'logged_out',
    );
  }

  void _notifyActiveTabActivated() {
    if (!mounted) return;
    switch (_selectedIndex) {
      case 0:
        _homeTabActivationNotifier.value += 1;
      case 4:
        _meTabActivationNotifier.value += 1;
    }
  }

  void _handleMeLoggedOut() {
    _resetSessionBoundState(selectedIndex: 4);
    unawaited(
      AppServicesScope.read(context).directMessageConversations.loadFromDb(),
    );
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    _resetSessionBoundState(selectedIndex: _selectedIndex);
    final services = AppServicesScope.read(context);
    services.billing?.resetForSession();
    unawaited(
      _recoverBilling(BillingRecoverySource.foreground, onlyIfUidChanged: true),
    );
    unawaited(services.directMessageConversations.loadFromDb());
    if (_selectedIndex == 3) {
      unawaited(_messagesPoller.runNow());
    }
    if (_selectedIndex == 4) {
      _notifyActiveTabActivated();
    }
  }

  void _startInitialBillingRecoveryIfReady() {
    if (_initialBillingRecoveryStarted) return;
    final lifecycleState = _lifecycleState;
    if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _initialBillingRecoveryStarted = true;
    unawaited(_recoverBilling(BillingRecoverySource.appStart));
  }

  Future<void> _recoverBilling(
    BillingRecoverySource source, {
    bool onlyIfUidChanged = false,
  }) async {
    try {
      if (!mounted) return;
      final services = AppServicesScope.read(context);
      final uid = await services.sessionStore.readLoginUid();
      if (!mounted) return;
      if (uid == null) {
        _lastBillingRecoveryUid = null;
        return;
      }
      if (onlyIfUidChanged && uid == _lastBillingRecoveryUid) return;
      await services.billing?.recover(source);
      if (!mounted) return;
      final currentUid = (await services.sessionStore.readUid())?.trim() ?? '';
      if (mounted && currentUid == uid) {
        _lastBillingRecoveryUid = uid;
      }
    } catch (error, stackTrace) {
      debugPrint('[Billing] background recovery failed ($source): $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _resetSessionBoundState({required int selectedIndex}) {
    setState(() {
      _tabPageCache.clear();
      _sessionPageStorageBucket = PageStorageBucket();
      _sessionTabGeneration += 1;
      _visitedTabIndexes
        ..clear()
        ..add(selectedIndex);
      _selectedIndex = selectedIndex;
    });
    _unreadSummaryNotifier.value = UnreadSummary.zero;
    _messagesTabActiveNotifier.value = _selectedIndex == 3;
    _meTabActiveNotifier.value = _selectedIndex == 4;
    _homeTabActiveNotifier.value = _selectedIndex == 0;
    _worldoTabActiveNotifier.value = _selectedIndex == 1;
  }

  Widget _cachedTabPage(int index) {
    return _tabPageCache.putIfAbsent(index, () {
      return switch (index) {
        0 => HomePage(
          key: ValueKey<String>('home-session-$_sessionTabGeneration'),
          activationListenable: _homeTabActivationNotifier,
          reselectionListenable: _homeTabReselectionNotifier,
          isActiveListenable: _homeTabActiveNotifier,
          isFirstPageViewReported: _isFirstContentPageViewReported,
          onFirstPageViewReady: _recordFirstContentPageView,
          onOpenWorldo: () => unawaited(_onTapNav(1)),
        ),
        1 => OriginPage(
          key: ValueKey<String>('worldo-session-$_sessionTabGeneration'),
          isInitialPage: widget.initialIndex == 1,
          onForYouFirstPageReady: _handleWorldoForYouFirstPageReady,
          activationListenable: _worldoTabActivationNotifier,
          isActiveListenable: _worldoTabActiveNotifier,
        ),
        3 => ValueListenableBuilder<UnreadSummary>(
          key: ValueKey<String>('messages-session-$_sessionTabGeneration'),
          valueListenable: _unreadSummaryNotifier,
          builder: (context, unreadSummary, _) {
            return MessagesPage(
              unreadSummary: unreadSummary,
              onMessagesDataRefresh: _messagesPoller.runNow,
              isActiveListenable: _messagesTabActiveNotifier,
              reselectionListenable: _messagesTabReselectionNotifier,
            );
          },
        ),
        4 => MePage(
          key: ValueKey<String>('me-session-$_sessionTabGeneration'),
          onLoggedOut: _handleMeLoggedOut,
          onLogin: _loginWithProvider,
          onLoginCompleted: () => scheduleDailyCheckInAfterLogin(context),
          activationListenable: _meTabActivationNotifier,
          reselectionListenable: _meTabReselectionNotifier,
          isActiveListenable: _meTabActiveNotifier,
        ),
        _ => const SizedBox.shrink(),
      };
    });
  }

  Widget _buildTabSlot(int index) {
    if (!_visitedTabIndexes.contains(index)) {
      return const SizedBox.shrink();
    }
    switch (index) {
      case 0:
        return _cachedTabPage(index);
      case 3:
        return _cachedTabPage(index);
      case 4:
        return _cachedTabPage(index);
      case 1:
        return _cachedTabPage(index);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        for (var index = 0; index < 5; index += 1) _buildTabSlot(index),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          _selectedIndex == 0 ||
              _selectedIndex == 1 ||
              _selectedIndex == 3 ||
              _selectedIndex == 4
          ? kGenesisLightSystemUiOverlayStyle
          : kGenesisDefaultSystemUiOverlayStyle,
      child: Scaffold(
        backgroundColor:
            _selectedIndex == 0 ||
                _selectedIndex == 1 ||
                _selectedIndex == 3 ||
                _selectedIndex == 4
            ? GenesisColors.darkBackground
            : null,
        // Home and Origin own the iOS status-bar gesture so they can route it
        // to their explicitly controlled active list.
        primary: _selectedIndex != 0 && _selectedIndex != 1,
        body: PageStorage(
          bucket: _sessionPageStorageBucket,
          child: _buildBody(),
        ),
        bottomNavigationBar: ValueListenableBuilder<UnreadSummary>(
          valueListenable: _unreadSummaryNotifier,
          builder: (context, unreadSummary, _) {
            return BottomTabs(
              currentIndex: _selectedIndex,
              messagesUnreadCount: unreadSummary.totalUnread,
              onTap: (index) => unawaited(_onTapNav(index)),
            );
          },
        ),
      ),
    );
  }
}
