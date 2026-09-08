import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:genesis_flutter_android/app/bootstrap/app_services_scope.dart';
import 'package:genesis_flutter_android/network/gateway_auth.dart';
import 'package:genesis_flutter_android/network/genesis_http_cache_manager.dart';
import 'package:genesis_flutter_android/platform/device/device_id_service.dart';

import '../../app/agent_control/agent_control_status.dart';
import '../../app/config/app_endpoint_overrides.dart';
import '../../app/config/app_config.dart';
import '../../app/config/app_global_config.dart';
import '../../app/debug_floating_button_visibility.dart';
import '../../app/debug_page_tracker.dart';
import '../../app/debug/location_chat_bubble_layout_settings.dart';
import '../../app/debug/location_chat_header_effect_settings.dart';
import '../../app/debug/origin_world_sheet_debug_settings.dart';
import '../../app/debug/world_new_content_debug_settings.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/common/genesis_bottom_sheet_panel.dart';
import '../../components/common/genesis_modal_routes.dart';
import '../../components/common/genesis_generation_wait_overlay.dart';
import '../../components/gems/gem_purchase_bottom_sheet.dart';
import '../../components/gems/daily_check_in_dialog.dart';
import '../../components/genesis_logo.dart';
import '../../components/tilemap/tilemap_settings_button_visibility.dart';
import '../../app/gems/gem_wallet_store.dart';
import '../../app/telemetry/telemetry_runtime_controller.dart';
import '../../app/telemetry/telemetry_upload_policy.dart';
import '../../network/genesis_api.dart';
import '../../network/chatroom/world_chatroom_service.dart';
import '../../network/models/gem_product.dart';
import '../../network/models/gem_wallet.dart';
import '../../network/models/world_history_settings.dart';
import '../../network/network_capture.dart';
import '../../network/websocket_capture.dart';
import '../../platform/app/app_metadata_service.dart';
import '../../platform/app/app_version_override_store.dart';
import '../../platform/billing/billing_models.dart';
import '../../platform/billing/billing_service.dart';
import '../../platform/session/user_session_store.dart';
import '../../routers/app_router.dart';
import '../../utils/gem_amount.dart';
import '../gems/gem_wallet_page.dart';
import '../world/world_update_push_banner.dart';
import '../../ui/genesis_ui.dart';
import 'about_us_page.dart';

part 'developer_endpoint_actions.dart';
part 'developer_version_actions.dart';
part 'developer_previews.dart';
part 'developer_components.dart';
part 'developer_app_config_section.dart';
part 'developer_capture_components.dart';
part 'developer_network_tab.dart';
part 'developer_websocket_tab.dart';
part 'developer_world_history_actions.dart';

const String _buildModeLabel = kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';

const List<String> _creatingPreviewWaitLines = [
  'Originator',
  'Eve',
  'A floating city where every district changes its laws at sunrise, and every resident keeps a private map of the rules they trust.',
  'Magic behaves like public infrastructure. Promises, debts, weather, and streetlights all run through the same civic engine.',
  'Mira: Exiled route-maker. Patient, skeptical, and protective of anyone who admits they are lost.',
  'Jon: Archive courier. Restless, charming, and far too willing to trade secrets for a shortcut.',
];

const List<String> _developerPageCoreTabs = <String>[
  'basic',
  'switch',
  'button',
];
const List<String> _developerPageDebugTabs = <String>[
  'basic',
  'switch',
  'button',
  'network',
  'websocket',
];

@visibleForTesting
List<String> developerPageTabsForBuild({required bool isDebugBuild}) {
  return isDebugBuild ? _developerPageDebugTabs : _developerPageCoreTabs;
}

final List<String> _developerPageTabs = developerPageTabsForBuild(
  isDebugBuild: kDebugMode,
);

int _developerPageLastTabIndex = 0;

@visibleForTesting
void resetDeveloperPageTabForTesting() {
  _developerPageLastTabIndex = 0;
}

class DeveloperPage extends StatelessWidget {
  const DeveloperPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: DeveloperPageContent(
          headerLeading: _DeveloperPageBackButton(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
    );
  }
}

class DeveloperPageSheet extends StatelessWidget {
  const DeveloperPageSheet({super.key, this.sheetScrollController});

  final ScrollController? sheetScrollController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GenesisBottomSheetPanel(
          key: const ValueKey<String>('developer-page-sheet'),
          title: '',
          height: constraints.maxHeight,
          showHeader: false,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: DeveloperPageContent(
            dismissBeforePreview: true,
            sheetScrollController: sheetScrollController,
            headerTrailing: GenesisBottomSheetCloseButton(
              buttonKey: const ValueKey<String>('developer-page-sheet-close'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            onDismissBeforePreview: () async {
              await Navigator.of(context).maybePop();
            },
          ),
        );
      },
    );
  }
}

class DeveloperPageContent extends StatefulWidget {
  const DeveloperPageContent({
    super.key,
    this.dismissBeforePreview = false,
    this.onDismissBeforePreview,
    this.headerLeading,
    this.headerTrailing,
    this.sheetScrollController,
  });

  final bool dismissBeforePreview;
  final Future<void> Function()? onDismissBeforePreview;
  final Widget? headerLeading;
  final Widget? headerTrailing;
  final ScrollController? sheetScrollController;

  @override
  State<DeveloperPageContent> createState() => _DeveloperPageContentState();
}

class _DeveloperPageContentState extends State<DeveloperPageContent>
    with SingleTickerProviderStateMixin {
  static const double _itemGap = 8;
  static const String _productionEndpointHost = 'api.worldo.ai';
  static const String _testEndpointHost = 'dev.hushie.ai';
  static final String _defaultEndpointHost =
      AppEndpointOverrideStore.displayDomain(GenesisApi.defaultApiBaseUrl);

  late final Future<DeviceIdDiagnostics> _deviceIdDiagnosticsFuture;
  late Future<AppVersionInfo> _appVersionFuture;
  late final Future<AppVersionInfo> _buildAppVersionFuture;
  late final Future<_DeveloperAccountIdentity> _accountIdentityFuture;
  late final TextEditingController _apiBaseUrlController;
  late final TextEditingController _gatewayApiBaseUrlController;
  late final TextEditingController _chatroomWsBaseUrlController;
  late final TextEditingController _versionNameController;
  late final TextEditingController _versionCodeController;
  late final TextEditingController _worldHistoryHighWatermarkController;
  late final TextEditingController _worldHistoryLowWatermarkController;
  late final TabController _tabController;
  late int _selectedTabIndex;
  bool _clearingDirectMessageCache = false;
  bool _clearingImageCache = false;
  bool _clearingGatewayAuth = false;
  bool _verifyingGatewaySignature = false;
  bool _loadingEndpointOverrides = true;
  bool _savingEndpointOverrides = false;
  bool _loadingVersionOverrides = true;
  bool _savingVersionOverrides = false;
  bool _hasVersionOverrides = false;
  bool _loadingTilemapSettingsButtonVisibility = true;
  bool _savingTilemapSettingsButtonVisibility = false;
  bool _loadingOriginWorldSheetDebugSettings = kDebugMode;
  bool _savingOriginWorldSheetDebugSettings = false;
  bool _loadingWorldNewContentDebugSettings = kDebugMode;
  bool _savingWorldNewContentDebugSettings = false;
  final Set<TelemetryChannel> _savingTelemetryChannels = <TelemetryChannel>{};
  bool _showTilemapSettingsButton = tilemapSettingsButtonVisibility.value;
  bool _expandOriginWorldSheetOnEntry =
      originWorldSheetDebugSettings.expandOnEntry;
  bool _forceWorldNewBadges = worldNewContentDebugSettings.forceNewBadges;
  bool _dailyCheckInPreviewClaimed = false;
  bool _loadingWorldHistoryAccess = true;
  bool _hasWorldHistoryAccess = false;
  String? _worldHistoryBusyAction;
  WorldHistorySettings? _worldHistorySettings;
  String? _gatewaySignatureVerifyResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _developerPageTabs.length,
      initialIndex: _developerPageLastTabIndex.clamp(
        0,
        _developerPageTabs.length - 1,
      ),
      vsync: this,
    );
    _selectedTabIndex = _tabController.index;
    _tabController.addListener(_rememberSelectedTab);
    final deviceId = AppServicesScope.read(context).deviceId;
    _deviceIdDiagnosticsFuture = deviceId is DeviceIdDiagnosticsService
        ? (deviceId as DeviceIdDiagnosticsService).getDeviceIdDiagnostics()
        : deviceId.getDeviceId().then(
            (value) => DeviceIdDiagnostics(deviceId: value),
          );
    _appVersionFuture = AppMetadataService.appVersion();
    _buildAppVersionFuture = AppMetadataService.buildAppVersion();
    _accountIdentityFuture = _loadAccountIdentity();
    _apiBaseUrlController = TextEditingController();
    _gatewayApiBaseUrlController = TextEditingController();
    _chatroomWsBaseUrlController = TextEditingController();
    _versionNameController = TextEditingController();
    _versionCodeController = TextEditingController();
    _worldHistoryHighWatermarkController = TextEditingController();
    _worldHistoryLowWatermarkController = TextEditingController();
    _apiBaseUrlController.addListener(_handleEndpointTextChanged);
    _gatewayApiBaseUrlController.addListener(_handleEndpointTextChanged);
    _chatroomWsBaseUrlController.addListener(_handleEndpointTextChanged);
    _loadEndpointOverrides();
    unawaited(_loadVersionOverrides());
    unawaited(_loadWorldHistoryAccess());
    unawaited(_loadTilemapSettingsButtonVisibility());
    if (kDebugMode) {
      unawaited(_loadOriginWorldSheetDebugSettings());
      unawaited(_loadWorldNewContentDebugSettings());
    }
    unawaited(locationChatBubbleLayoutSettings.load());
    unawaited(locationChatHeaderEffectSettings.load());
    unawaited(AppServicesScope.read(context).gemWallet.refresh());
  }

  @override
  void dispose() {
    _tabController.removeListener(_rememberSelectedTab);
    _tabController.dispose();
    _apiBaseUrlController.removeListener(_handleEndpointTextChanged);
    _gatewayApiBaseUrlController.removeListener(_handleEndpointTextChanged);
    _chatroomWsBaseUrlController.removeListener(_handleEndpointTextChanged);
    _apiBaseUrlController.dispose();
    _gatewayApiBaseUrlController.dispose();
    _chatroomWsBaseUrlController.dispose();
    _versionNameController.dispose();
    _versionCodeController.dispose();
    _worldHistoryHighWatermarkController.dispose();
    _worldHistoryLowWatermarkController.dispose();
    super.dispose();
  }

  void _rememberSelectedTab() {
    final index = _tabController.index;
    _developerPageLastTabIndex = index;
    if (_selectedTabIndex != index && mounted) {
      setState(() => _selectedTabIndex = index);
    }
  }

  void _updateState(VoidCallback callback) => setState(callback);

  Future<void> _loadTilemapSettingsButtonVisibility() async {
    final visible = await tilemapSettingsButtonVisibility.load();
    if (!mounted) return;
    _updateState(() {
      _showTilemapSettingsButton = visible;
      _loadingTilemapSettingsButtonVisibility = false;
    });
  }

  Future<void> _setTilemapSettingsButtonVisibility(bool visible) async {
    if (_loadingTilemapSettingsButtonVisibility ||
        _savingTilemapSettingsButtonVisibility) {
      return;
    }
    final previousValue = _showTilemapSettingsButton;
    _updateState(() {
      _showTilemapSettingsButton = visible;
      _savingTilemapSettingsButtonVisibility = true;
    });
    try {
      await tilemapSettingsButtonVisibility.setVisible(visible);
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _showTilemapSettingsButton = previousValue);
      showGenesisToast(context, 'Save failed: $error');
    } finally {
      if (mounted) {
        _updateState(() => _savingTilemapSettingsButtonVisibility = false);
      }
    }
  }

  Future<void> _loadOriginWorldSheetDebugSettings() async {
    final enabled = await originWorldSheetDebugSettings.load();
    if (!mounted) return;
    _updateState(() {
      _expandOriginWorldSheetOnEntry = enabled;
      _loadingOriginWorldSheetDebugSettings = false;
    });
  }

  Future<void> _setOriginWorldSheetExpandOnEntry(bool enabled) async {
    if (_loadingOriginWorldSheetDebugSettings ||
        _savingOriginWorldSheetDebugSettings) {
      return;
    }
    final previousValue = _expandOriginWorldSheetOnEntry;
    _updateState(() {
      _expandOriginWorldSheetOnEntry = enabled;
      _savingOriginWorldSheetDebugSettings = true;
    });
    try {
      await originWorldSheetDebugSettings.setExpandOnEntry(enabled);
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _expandOriginWorldSheetOnEntry = previousValue);
      showGenesisToast(context, 'Save failed: $error');
    } finally {
      if (mounted) {
        _updateState(() => _savingOriginWorldSheetDebugSettings = false);
      }
    }
  }

  Future<void> _loadWorldNewContentDebugSettings() async {
    final enabled = await worldNewContentDebugSettings.load();
    if (!mounted) return;
    _updateState(() {
      _forceWorldNewBadges = enabled;
      _loadingWorldNewContentDebugSettings = false;
    });
  }

  Future<void> _setWorldNewContentForceNewBadges(bool enabled) async {
    if (_loadingWorldNewContentDebugSettings ||
        _savingWorldNewContentDebugSettings) {
      return;
    }
    final previousValue = _forceWorldNewBadges;
    _updateState(() {
      _forceWorldNewBadges = enabled;
      _savingWorldNewContentDebugSettings = true;
    });
    try {
      await worldNewContentDebugSettings.setForceNewBadges(enabled);
    } catch (error) {
      if (!mounted) return;
      _updateState(() => _forceWorldNewBadges = previousValue);
      showGenesisToast(context, 'Save failed: $error');
    } finally {
      if (mounted) {
        _updateState(() => _savingWorldNewContentDebugSettings = false);
      }
    }
  }

  Future<void> _setTelemetryUploadOverride(
    TelemetryChannel channel,
    bool enabled,
  ) async {
    if (_savingTelemetryChannels.contains(channel)) return;
    _updateState(() => _savingTelemetryChannels.add(channel));
    try {
      await TelemetryRuntimeController.setDebugOverrideEnabled(
        config: AppServicesScope.read(context).config,
        channel: channel,
        enabled: enabled,
      );
    } catch (error) {
      if (mounted) showGenesisToast(context, 'Save failed: $error');
    } finally {
      if (mounted) {
        _updateState(() => _savingTelemetryChannels.remove(channel));
      }
    }
  }

  Future<void> _saveLocationChatHeaderEffectSettings() async {
    try {
      await locationChatHeaderEffectSettings.save();
    } catch (error) {
      if (mounted) showGenesisToast(context, 'Save failed: $error');
    }
  }

  Future<void> _saveLocationChatBubbleLayoutSettings() async {
    try {
      await locationChatBubbleLayoutSettings.save();
    } catch (error) {
      if (mounted) showGenesisToast(context, 'Save failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontalContentPadding = widget.dismissBeforePreview ? 0.0 : 20.0;
    final tabs = SecendTabs(
      labels: _developerPageTabs,
      controller: _tabController,
      horizontalPadding: horizontalContentPadding,
      labelPadding: const EdgeInsets.only(right: 16),
      verticalPadding: 0,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return SizedBox(
          height: height,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalContentPadding,
                ),
                child: SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      if (widget.headerLeading != null) ...[
                        widget.headerLeading!,
                        const SizedBox(width: 8),
                      ],
                      const Expanded(
                        child: Text(
                          'Developer Page',
                          key: ValueKey<String>('developer-page-title'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      if (widget.headerTrailing != null) ...[
                        const SizedBox(width: 8),
                        widget.headerTrailing!,
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 0.5),
              tabs,
              const SizedBox(height: 4),
              Expanded(
                child: TabBarView(
                  key: const ValueKey<String>('developer-page-tab-view'),
                  controller: _tabController,
                  children: [
                    _buildInfoTab(
                      horizontalContentPadding,
                      scrollController: _selectedTabIndex == 0
                          ? widget.sheetScrollController
                          : null,
                    ),
                    _buildTestSwitchTab(
                      horizontalContentPadding,
                      scrollController: _selectedTabIndex == 1
                          ? widget.sheetScrollController
                          : null,
                    ),
                    _buildTestButtonTab(
                      horizontalContentPadding,
                      scrollController: _selectedTabIndex == 2
                          ? widget.sheetScrollController
                          : null,
                    ),
                    if (kDebugMode) ...[
                      _DeveloperNetworkTab(
                        key: const ValueKey<String>('developer-network-tab'),
                        horizontalPadding: horizontalContentPadding,
                      ),
                      _DeveloperWebSocketTab(
                        key: const ValueKey<String>('developer-websocket-tab'),
                        horizontalPadding: horizontalContentPadding,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoTab(
    double horizontalPadding, {
    ScrollController? scrollController,
  }) {
    return ListView(
      key: const PageStorageKey<String>('developer-info-tab-scroll'),
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        10,
        horizontalPadding,
        20,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        FutureBuilder<_DeveloperAccountIdentity>(
          future: _accountIdentityFuture,
          builder: (context, snapshot) => _buildAccountIdentityRows(snapshot),
        ),
        const SizedBox(height: _itemGap),
        _buildGemBalanceInfoRow(),
        const SizedBox(height: _itemGap),
        FutureBuilder<DeviceIdDiagnostics>(
          future: _deviceIdDiagnosticsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _DeveloperInfoSingleLineRow(
                title: 'Device ID',
                content: 'Loading...',
              );
            }
            return _buildDeviceIdDiagnostics(snapshot.data);
          },
        ),
        const SizedBox(height: _itemGap),
        FutureBuilder<AppVersionInfo>(
          future: _appVersionFuture,
          builder: (context, snapshot) {
            final value = snapshot.connectionState == ConnectionState.done
                ? _versionLabel(snapshot.data)
                : 'Loading...';
            return _DeveloperInfoRow(title: 'Version', content: value);
          },
        ),
        const SizedBox(height: _itemGap),
        const _DeveloperInfoRow(title: 'Build', content: _buildModeLabel),
        const SizedBox(height: _itemGap),
        ValueListenableBuilder<String>(
          valueListenable: genesisCurrentPageClassName,
          builder: (context, pageName, _) {
            return _DeveloperInfoRow(title: 'Current Page', content: pageName);
          },
        ),
        const SizedBox(height: _itemGap),
        ValueListenableBuilder<AgentControlStatus>(
          valueListenable: agentControlStatus,
          builder: (context, status, _) {
            return _DeveloperInfoRow(
              title: 'Agent CLI',
              content: _formatAgentControlStatus(status),
            );
          },
        ),
        const SizedBox(height: 18),
        ..._buildEndpointSection(),
        const SizedBox(height: 18),
        ..._buildVersionOverrideSection(),
        const SizedBox(height: 18),
        const _DeveloperAppConfigSection(),
      ],
    );
  }

  List<Widget> _buildVersionOverrideSection() {
    final enabled = !_loadingVersionOverrides && !_savingVersionOverrides;
    return [
      Row(
        children: [
          const Expanded(
            child: _DeveloperSectionTitle('Runtime version override'),
          ),
          if (_hasVersionOverrides)
            const Text(
              'Active',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      FutureBuilder<AppVersionInfo>(
        future: _buildAppVersionFuture,
        builder: (context, snapshot) {
          final value = snapshot.connectionState == ConnectionState.done
              ? _versionLabel(snapshot.data)
              : 'Loading...';
          return Text(
            'Build version: $value. New version reads use the values below.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF777777),
              height: 1.35,
            ),
          );
        },
      ),
      const SizedBox(height: 10),
      _DeveloperVersionField(
        key: const ValueKey<String>('developer-version-name-field'),
        label: 'Version Name',
        controller: _versionNameController,
        enabled: enabled,
      ),
      const SizedBox(height: _itemGap),
      _DeveloperVersionField(
        key: const ValueKey<String>('developer-version-code-field'),
        label: 'Version Code',
        controller: _versionCodeController,
        enabled: enabled,
        digitsOnly: true,
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey<String>('developer-version-reset'),
              onPressed: enabled
                  ? () => unawaited(_resetVersionOverrides())
                  : null,
              child: const Text('Reset'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const ValueKey<String>('developer-version-save'),
              onPressed: enabled
                  ? () => unawaited(_saveVersionOverrides())
                  : null,
              child: Text(_savingVersionOverrides ? 'Saving...' : 'Save'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildEndpointSection() {
    return [
      _DeveloperEndpointHeader(
        isTestEnvironment: _isUsingTestEndpointHost,
        enabled: !_loadingEndpointOverrides && !_savingEndpointOverrides,
        onPressed: () => unawaited(_switchEndpointEnvironment()),
      ),
      const SizedBox(height: 12),
      _DeveloperEndpointField(
        key: const ValueKey<String>('developer-api-base-url-field'),
        label: 'API HTTPS',
        scheme: 'https://',
        hintText: _defaultEndpointHost,
        controller: _apiBaseUrlController,
      ),
      const SizedBox(height: _itemGap),
      _DeveloperEndpointField(
        key: const ValueKey<String>('developer-gateway-api-base-url-field'),
        label: 'Gateway',
        scheme: 'https://',
        hintText: _defaultEndpointHost,
        controller: _gatewayApiBaseUrlController,
      ),
      const SizedBox(height: _itemGap),
      _DeveloperEndpointField(
        key: const ValueKey<String>('developer-chatroom-ws-base-url-field'),
        label: 'Chat WSS',
        scheme: 'wss://',
        hintText: _defaultEndpointHost,
        controller: _chatroomWsBaseUrlController,
      ),
    ];
  }

  Widget _buildTestSwitchTab(
    double horizontalPadding, {
    ScrollController? scrollController,
  }) {
    return ListView(
      key: const PageStorageKey<String>('developer-test-switch-tab-scroll'),
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        10,
        horizontalPadding,
        20,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (!_loadingEndpointOverrides &&
            !_loadingWorldHistoryAccess &&
            _isUsingTestEndpointHost &&
            _hasWorldHistoryAccess) ...[
          _DeveloperWorldHistoryWatermarkPanel(
            highWatermarkController: _worldHistoryHighWatermarkController,
            lowWatermarkController: _worldHistoryLowWatermarkController,
            busyAction: _worldHistoryBusyAction,
            settings: _worldHistorySettings,
            onFetch: _fetchWorldHistorySettings,
            onUpdate: _updateWorldHistorySettings,
            onDelete: _resetWorldHistorySettings,
          ),
          const SizedBox(height: 18),
        ],
        ValueListenableBuilder<TelemetryUploadState>(
          valueListenable: TelemetryUploadPolicy.state,
          builder: (context, telemetry, _) {
            return _DeveloperTelemetryUploadPanel(
              state: telemetry,
              savingChannels: _savingTelemetryChannels,
              onChanged: (channel, enabled) {
                unawaited(_setTelemetryUploadOverride(channel, enabled));
              },
            );
          },
        ),
        const SizedBox(height: 18),
        _DeveloperTestSectionPanel(
          key: const ValueKey<String>('developer-tilemap-panel'),
          child: _DeveloperToggleRow(
            sectionTitle: 'Tilemap',
            label: 'Show settings button',
            value: _showTilemapSettingsButton,
            enabled:
                !_loadingTilemapSettingsButtonVisibility &&
                !_savingTilemapSettingsButtonVisibility,
            switchKey: const ValueKey<String>(
              'developer-tilemap-settings-button-switch',
            ),
            onChanged: (value) {
              unawaited(_setTilemapSettingsButtonVisibility(value));
            },
          ),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 18),
          _DeveloperTestSectionPanel(
            key: const ValueKey<String>('developer-world-force-new-panel'),
            child: _DeveloperToggleRow(
              sectionTitle: 'World',
              label: 'Force is_new = true',
              value: _forceWorldNewBadges,
              enabled:
                  !_loadingWorldNewContentDebugSettings &&
                  !_savingWorldNewContentDebugSettings,
              switchKey: const ValueKey<String>(
                'developer-world-force-new-switch',
              ),
              onChanged: (value) {
                unawaited(_setWorldNewContentForceNewBadges(value));
              },
            ),
          ),
          const SizedBox(height: 18),
          _DeveloperTestSectionPanel(
            key: const ValueKey<String>('developer-origin-world-sheet-panel'),
            child: _DeveloperToggleRow(
              sectionTitle: 'Worldo detail',
              label: 'Expand sheet on entry',
              value: _expandOriginWorldSheetOnEntry,
              enabled:
                  !_loadingOriginWorldSheetDebugSettings &&
                  !_savingOriginWorldSheetDebugSettings,
              switchKey: const ValueKey<String>(
                'developer-origin-world-sheet-expand-switch',
              ),
              onChanged: (value) {
                unawaited(_setOriginWorldSheetExpandOnEntry(value));
              },
            ),
          ),
        ],
        const SizedBox(height: 18),
        ValueListenableBuilder<LocationChatBubbleLayoutSettings>(
          valueListenable: locationChatBubbleLayoutSettings,
          builder: (context, bubbleLayoutSettings, _) {
            return ValueListenableBuilder<LocationChatHeaderEffectSettings>(
              valueListenable: locationChatHeaderEffectSettings,
              builder: (context, headerEffectSettings, _) {
                final transparencyLabel =
                    headerEffectSettings.transparencyStrength <= 0
                    ? 'Off'
                    : '${(headerEffectSettings.transparencyStrength * 100).round()}%';
                final blurLabel = headerEffectSettings.blurSigma <= 0
                    ? 'Off'
                    : headerEffectSettings.blurSigma.toStringAsFixed(0);
                final crowdedWidthLabel = bubbleLayoutSettings
                    .crowdedEffectiveWidthThreshold
                    .toStringAsFixed(0);
                return _DeveloperTestSectionPanel(
                  key: const ValueKey<String>('developer-location-chat-panel'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _DeveloperSectionTitle(
                        'Location chat header & input bar',
                      ),
                      const SizedBox(height: 8),
                      _DeveloperSliderControl(
                        label: 'Surface opacity',
                        valueLabel: transparencyLabel,
                        value: headerEffectSettings.transparencyStrength,
                        min: LocationChatHeaderEffectSettings
                            .minTransparencyStrength,
                        max: LocationChatHeaderEffectSettings
                            .maxTransparencyStrength,
                        divisions: 20,
                        sliderKey: const ValueKey<String>(
                          'developer-location-chat-header-transparency-slider',
                        ),
                        onChanged: locationChatHeaderEffectSettings
                            .previewTransparencyStrength,
                        onChangeEnd: (_) {
                          unawaited(_saveLocationChatHeaderEffectSettings());
                        },
                      ),
                      const SizedBox(height: _itemGap),
                      _DeveloperSliderControl(
                        label: 'Gaussian blur radius',
                        valueLabel: blurLabel,
                        value: headerEffectSettings.blurSigma,
                        min: LocationChatHeaderEffectSettings.minBlurSigma,
                        max: LocationChatHeaderEffectSettings.maxBlurSigma,
                        divisions: 20,
                        sliderKey: const ValueKey<String>(
                          'developer-location-chat-header-blur-slider',
                        ),
                        onChanged:
                            locationChatHeaderEffectSettings.previewBlurSigma,
                        onChangeEnd: (_) {
                          unawaited(_saveLocationChatHeaderEffectSettings());
                        },
                      ),
                      const SizedBox(height: 14),
                      const _DeveloperSectionTitle(
                        'Self & character message bubbles',
                      ),
                      const SizedBox(height: 8),
                      _DeveloperSliderControl(
                        label: 'Crowded width threshold',
                        valueLabel: '$crowdedWidthLabel logical px',
                        value:
                            bubbleLayoutSettings.crowdedEffectiveWidthThreshold,
                        min: LocationChatBubbleLayoutSettings
                            .minCrowdedEffectiveWidthThreshold,
                        max: LocationChatBubbleLayoutSettings
                            .maxCrowdedEffectiveWidthThreshold,
                        divisions: 40,
                        sliderKey: const ValueKey<String>(
                          'developer-location-chat-crowded-width-slider',
                        ),
                        onChanged: locationChatBubbleLayoutSettings
                            .previewCrowdedEffectiveWidthThreshold,
                        onChangeEnd: (_) {
                          unawaited(_saveLocationChatBubbleLayoutSettings());
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildTestButtonTab(
    double horizontalPadding, {
    ScrollController? scrollController,
  }) {
    return ListView(
      key: const PageStorageKey<String>('developer-test-button-tab-scroll'),
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        10,
        horizontalPadding,
        20,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          children: [
            Expanded(
              child: GenesisPrimaryButton(
                key: const ValueKey<String>('developer-world-update-push-only'),
                label: 'Push only',
                onPressed: () => _showWorldUpdatePushPreview(multiple: false),
                backgroundColor: const Color(0xFFE1E1E3),
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(width: _itemGap),
            Expanded(
              child: GenesisPrimaryButton(
                key: const ValueKey<String>(
                  'developer-world-update-push-multi',
                ),
                label: 'Push multi',
                onPressed: () => _showWorldUpdatePushPreview(multiple: true),
                backgroundColor: const Color(0xFFE1E1E3),
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: _itemGap),
        GenesisPrimaryButton(
          label: 'Creating',
          onPressed: _showCreatingWaitOverlayPreview,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
        const SizedBox(height: _itemGap),
        GenesisPrimaryButton(
          label: 'Preview Gem purchase sheet',
          onPressed: _showGemPurchaseSheetPreview,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
        const SizedBox(height: _itemGap),
        GenesisPrimaryButton(
          label: 'Preview purchase overlay',
          onPressed: _showGemPurchaseOverlayPreview,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
        const SizedBox(height: _itemGap),
        GenesisPrimaryButton(
          label: 'Preview Daily Check-in',
          onPressed: _showDailyCheckInPreview,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
        const SizedBox(height: _itemGap),
        GenesisPrimaryButton(
          label: _clearingDirectMessageCache
              ? 'Clearing...'
              : 'Clear direct message cache',
          onPressed: _clearingDirectMessageCache
              ? null
              : _clearDirectMessageCache,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
        const SizedBox(height: _itemGap),
        GenesisPrimaryButton(
          label: _clearingImageCache ? 'Clearing...' : 'Clear image cache',
          onPressed: _clearingImageCache ? null : _clearImageCache,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
        const SizedBox(height: _itemGap),
        GenesisPrimaryButton(
          label: _clearingGatewayAuth ? 'Clearing...' : 'Clear Gateway auth',
          onPressed: _clearingGatewayAuth ? null : _clearGatewayAuth,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
        const SizedBox(height: _itemGap),
        GenesisPrimaryButton(
          label: _verifyingGatewaySignature
              ? 'Testing Gateway signature...'
              : 'Test Gateway signature',
          onPressed: _verifyingGatewaySignature
              ? null
              : _verifyGatewaySignature,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
        if (_gatewaySignatureVerifyResult != null) ...[
          const SizedBox(height: _itemGap),
          _DeveloperInfoBlock(
            title: 'Gateway signature response',
            content: _gatewaySignatureVerifyResult!,
          ),
        ],
        const SizedBox(height: _itemGap),
        GenesisPrimaryButton(
          label: 'Hide debug button',
          onPressed: _hideDebugButton,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
      ],
    );
  }
}

String _telemetryStatusLabel(TelemetryUploadState state) {
  if (state.automaticEnabled) {
    return 'Production policy active';
  }
  if (state.performanceEnabled &&
      state.blockReason == TelemetryUploadBlockReason.nonProductionEndpoint) {
    return 'Performance active · other uploads blocked by endpoint';
  }
  if (state.debugOverrides.anyEnabled) {
    return 'Debug channels enabled · test';
  }
  final reason = switch (state.blockReason) {
    TelemetryUploadBlockReason.none => 'disabled',
    TelemetryUploadBlockReason.nonReleaseBuild => 'non-release build',
    TelemetryUploadBlockReason.internalFlavor => 'internal flavor',
    TelemetryUploadBlockReason.nonProductionEndpoint =>
      'non-production endpoint',
  };
  return 'Automatic upload blocked · $reason';
}

class _DeveloperPageBackButton extends StatelessWidget {
  const _DeveloperPageBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: IconButton(
        tooltip: 'Back',
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(24),
          maximumSize: const Size.square(24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.black,
          size: 17,
        ),
      ),
    );
  }
}
