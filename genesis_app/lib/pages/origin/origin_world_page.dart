import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderProxySliver, SliverHitTestResult;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/telemetry/genesis_telemetry.dart';
import '../../app/telemetry/firebase_performance_operation.dart';
import '../../app/debug/location_chat_bubble_layout_settings.dart';
import '../../components/auth/login_guard.dart';
import '../../components/chat/shared/chat_ui.dart';
import '../../components/chat/shared/location_chat_overlay_transition.dart';
import '../../components/common/genesis_image_viewer_overlay.dart';
import '../../components/common/genesis_modal_routes.dart';
import '../../components/common/genesis_report_actions.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/common/copyable_id_label.dart';
import '../../components/discuss/discuss_post_input.dart';
import '../../components/discuss/origin_discuss_list.dart';
import '../../components/login_sheet.dart';
import '../../components/origin/origin_role_launch_sheet.dart';
import '../../components/origin/origin_character_form.dart';
import '../../components/origin/origin_role_recommendation.dart';
import '../../components/origin/stat_item.dart';
import '../../components/tilemap/tilemap_renderer.dart';
import '../../components/tilemap/tilemap_settings_store.dart';
import '../../components/world_map.dart';
import '../../network/genesis_http_cache_manager.dart';
import '../../icons/custom_icon_assets.dart';
import '../../network/chatroom/world_chatroom_service.dart';
import '../../ui/components/genesis_static_network_image.dart';
import '../../network/genesis_api.dart';
import '../../network/json_utils.dart';
import '../../network/models/location_tree.dart';
import '../../network/models/origin.dart';
import '../create/create_form_widgets.dart';
import '../../platform/auth/auth_session.dart';
import '../../platform/keyboard/genesis_keyboard_animation.dart';
import '../../platform/session/user_session_store.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_avatar.dart';
import '../../ui/components/genesis_character_avatar.dart';
import '../../ui/components/genesis_edge_swipe_back.dart';
import '../../ui/components/genesis_map_top_glass_bar.dart';
import '../../ui/components/genesis_primary_button.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/components/genesis_search_field.dart';
import '../../ui/tokens/genesis_avatar_radii.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_radii.dart';
import '../../app/bootstrap/app_services_scope.dart';
import '../../app/gems/daily_check_in_coordinator.dart';
import '../../utils/entity_deleted.dart';
import '../../utils/genesis_timestamp_formatter.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/genesis_image_resource.dart';
import '../../utils/stat_count_formatter.dart';
import '../chat/location_chat_background_preloader.dart';
import '../chat/location_chat_page.dart';
import '../world/world_header.dart';
import '../world/world_map_bubble_candidates.dart';
import '../world/world_navigation.dart';
import 'origin_launch_flow.dart';
import 'origin_role_portrait_image_provider.dart';
import 'origin_world_layout.dart';

part 'origin_world_map_shell.dart';
part 'origin_world_sheet_interaction.dart';
part 'origin_world_detail_sheet.dart';
part 'origin_world_sections.dart';
part 'origin_world_role_setup.dart';
part 'origin_world_launched_worlds.dart';
part 'origin_world_characters.dart';
part 'origin_world_location_chat.dart';
part 'origin_world_map_data.dart';

class OriginWorldPage extends StatefulWidget {
  const OriginWorldPage({
    super.key,
    required this.oid,
    required this.originId,
    this.initialName = '',
    this.initialDefinitionVersion = 0,
    this.initialMapLocationId = '',
    this.showOpeningSheetOnEntry = false,
  });

  final String oid;
  final int originId;
  final String initialName;
  final int initialDefinitionVersion;
  final String initialMapLocationId;
  final bool showOpeningSheetOnEntry;

  @override
  State<OriginWorldPage> createState() => _OriginWorldPageState();
}

@visibleForTesting
const double originDetailSheetHorizontalPaddingForTesting = 12;

@visibleForTesting
const double originDetailSheetHeaderHeightForTesting =
    GenesisRadii.sheetTopRadiusValue + 6;

@visibleForTesting
const double originDetailSheetHeaderBodyGapForTesting = 0;

@visibleForTesting
const double originDetailSheetPageIndicatorTopOffsetForTesting = 4;

@visibleForTesting
const double originDetailSectionGapForTesting = 24;

@visibleForTesting
const double originOpeningDialogueRoleGapForTesting = 36;

@visibleForTesting
const double originOpeningKeyboardDialogueGapReductionForTesting = 10;

@visibleForTesting
const double originDetailSectionTitleIconGapForTesting = 8;

@visibleForTesting
bool originOpeningDialogueWarmupAllowedForTesting({
  required bool hasMessages,
  required bool autoExpansionPending,
  required bool keyboardMode,
  required bool roleEditing,
  required bool openingPageSettled,
  required bool sheetInteractionActive,
  required bool extentAnimationActive,
}) {
  return hasMessages &&
      !autoExpansionPending &&
      !keyboardMode &&
      !roleEditing &&
      openingPageSettled &&
      !sheetInteractionActive &&
      !extentAnimationActive;
}

@visibleForTesting
bool originOpeningDialogueShouldFullyCacheForTesting({
  required bool keyboardMode,
  required bool warmupCompleted,
}) {
  return keyboardMode || warmupCompleted;
}

enum _OriginWorldPageRenderStage { framework, detailShell, content }

class _OriginWorldPageState extends State<OriginWorldPage> {
  static const String _profileLocationChatRoleId = 'current-user';
  static const SystemUiOverlayStyle _transparentStatusBarStyle =
      kGenesisLightStatusIconsSystemUiOverlayStyle;
  OriginDetail? _origin;
  Object? _initialLoadError;
  _OriginWorldPageRenderStage _renderStage =
      _OriginWorldPageRenderStage.framework;
  bool _contentMountScheduled = false;
  int _originLoadGeneration = 0;
  FirebasePerformanceOperation? _initialRequestPerformanceOperation;
  FirebasePerformanceOperation? _initialRenderPerformanceOperation;
  var _initialRequestPerformanceAttempt = 0;
  var _initialContentRenderCompleted = false;
  TilemapVisualMode _tilemapVisualMode = tilemapVisualModeController.value;
  late final Future<void> _tilemapVisualModeLoad;
  bool _tilemapVisualModeReady = false;
  Future<List<OriginMyLaunchPresetCharacter>>? _launchedPresetRolesFuture;
  Future<List<OriginMyLaunchPresetCharacter>>?
  _launchedPresetRolesPreparationFuture;
  List<OriginMyLaunchPresetCharacter>? _launchedPresetRolesData;
  String _launchedPresetRolesCacheKey = '';
  String _launchedPresetRolesPreloadScheduledForOriginId = '';
  ValueListenable<int>? _userInfoRevisionListenable;
  OriginCustomRoleDraft? _cachedProfileRole;
  OriginCustomRoleDraft? _localProfileRoleOverride;
  OriginCustomRoleDraft? get _openingProfileRole =>
      _localProfileRoleOverride ?? _cachedProfileRole;
  String _selectedLocationChatRoleId = _profileLocationChatRoleId;
  int _cachedProfileRoleLoadGeneration = 0;
  final Set<String> _preloadedProfileRoleAvatarKeys = <String>{};
  final OriginRoleAvatarSnapshotStore _roleAvatarSnapshots =
      OriginRoleAvatarSnapshotStore();
  OriginLaunchSource? _activeLaunchSource;
  bool get _launching => _activeLaunchSource != null;
  late bool _waitingForOpeningSheetExpansion;
  final ValueNotifier<bool> _detailSheetRaisedNotifier = ValueNotifier<bool>(
    false,
  );
  _OriginLocationChatDescriptor? _activeChatLocation;
  final LocationChatBackgroundPreloader _locationChatBackgroundPreloader =
      LocationChatBackgroundPreloader();
  final _tilemapRestorationController = TilemapRestorationController();
  final GlobalKey _tilemapImplementationKey = GlobalKey(
    debugLabel: 'origin-detail-tilemap',
  );
  Set<String> _currentTilemapLocationIds = const <String>{};
  OriginDetail? _cachedMapPresentationOrigin;
  String _cachedMapPresentationPreferredLocationId = '';
  _OriginWorldMapPresentationData? _cachedMapPresentationData;

  SystemUiOverlayStyle get _baseStatusBarStyle => _transparentStatusBarStyle;

  _OriginWorldMapPresentationData _mapPresentationDataFor(
    OriginDetail origin, {
    required String preferredInitialMapLocationId,
  }) {
    final cached = _cachedMapPresentationData;
    if (cached != null &&
        identical(_cachedMapPresentationOrigin, origin) &&
        _cachedMapPresentationPreferredLocationId ==
            preferredInitialMapLocationId) {
      return cached;
    }
    final data = _originWorldMapPresentationDataFor(
      origin,
      preferredInitialMapLocationId: preferredInitialMapLocationId,
    );
    _cachedMapPresentationOrigin = origin;
    _cachedMapPresentationPreferredLocationId = preferredInitialMapLocationId;
    _cachedMapPresentationData = data;
    return data;
  }

  @override
  void initState() {
    super.initState();
    _waitingForOpeningSheetExpansion = widget.showOpeningSheetOnEntry;
    tilemapVisualModeController.addListener(_handleTilemapVisualModeChanged);
    _tilemapVisualModeLoad = _loadTilemapVisualMode();
    _scheduleInitialOriginLoadAfterFrameworkFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextRevisionListenable = AppServicesScope.read(
      context,
    ).sessionStore.userInfoRevision;
    if (identical(_userInfoRevisionListenable, nextRevisionListenable)) return;
    _userInfoRevisionListenable?.removeListener(_handleCachedUserInfoChanged);
    _userInfoRevisionListenable = nextRevisionListenable;
    nextRevisionListenable.addListener(_handleCachedUserInfoChanged);
    unawaited(_refreshCachedProfileRole());
  }

  @override
  void didUpdateWidget(covariant OriginWorldPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.oid != widget.oid) {
      unawaited(_initialRequestPerformanceOperation?.cancel());
      unawaited(_initialRenderPerformanceOperation?.cancel());
      _initialRequestPerformanceOperation = null;
      _initialRenderPerformanceOperation = null;
      _initialRequestPerformanceAttempt = 0;
      _initialContentRenderCompleted = false;
      _launchedPresetRolesFuture = null;
      _launchedPresetRolesPreparationFuture = null;
      _launchedPresetRolesData = null;
      _launchedPresetRolesCacheKey = '';
      _launchedPresetRolesPreloadScheduledForOriginId = '';
      _originLoadGeneration += 1;
      _preloadedProfileRoleAvatarKeys.clear();
      _roleAvatarSnapshots.clear(notify: false);
      _origin = null;
      _initialLoadError = null;
      _renderStage = _OriginWorldPageRenderStage.framework;
      _contentMountScheduled = false;
      _activeChatLocation = null;
      _localProfileRoleOverride = null;
      _selectedLocationChatRoleId = _profileLocationChatRoleId;
      _currentTilemapLocationIds = const <String>{};
      _tilemapRestorationController.clear();
      _locationChatBackgroundPreloader.preload(const <Object?>[]);
      _waitingForOpeningSheetExpansion = widget.showOpeningSheetOnEntry;
      _detailSheetRaisedNotifier.value = false;
      _scheduleInitialOriginLoadAfterFrameworkFrame();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    setState(() {
      _launchedPresetRolesFuture = null;
      _launchedPresetRolesPreparationFuture = null;
      _launchedPresetRolesData = null;
      _launchedPresetRolesCacheKey = '';
      _launchedPresetRolesPreloadScheduledForOriginId = '';
    });
    unawaited(_fetchOriginDetail());
  }

  @override
  void dispose() {
    unawaited(_initialRequestPerformanceOperation?.cancel());
    unawaited(_initialRenderPerformanceOperation?.cancel());
    _originLoadGeneration += 1;
    _cachedProfileRoleLoadGeneration += 1;
    _userInfoRevisionListenable?.removeListener(_handleCachedUserInfoChanged);
    _locationChatBackgroundPreloader.dispose();
    _roleAvatarSnapshots.dispose();
    _tilemapRestorationController.dispose();
    _detailSheetRaisedNotifier.dispose();
    tilemapVisualModeController.removeListener(_handleTilemapVisualModeChanged);
    super.dispose();
  }

  void _handleCachedUserInfoChanged() {
    unawaited(_refreshCachedProfileRole());
    if (!mounted) return;
    setState(() {
      _localProfileRoleOverride = null;
      _launchedPresetRolesFuture = null;
      _launchedPresetRolesPreparationFuture = null;
      _launchedPresetRolesData = null;
      _launchedPresetRolesCacheKey = '';
      _launchedPresetRolesPreloadScheduledForOriginId = '';
    });
    _scheduleLaunchedPresetRolesPreload();
  }

  Future<void> _refreshCachedProfileRole() async {
    final generation = ++_cachedProfileRoleLoadGeneration;
    try {
      final services = AppServicesScope.read(context);
      final uid = await services.sessionStore.readLoginUid();
      OriginCustomRoleDraft? nextRole;
      if (uid != null) {
        final userInfo = await services.sessionStore.readUserInfo();
        final cachedName = userInfo == null
            ? ''
            : _mapString(userInfo, const [
                'name',
                'nickname',
                'user_name',
                'displayName',
                'display_name',
              ]);
        nextRole = OriginCustomRoleDraft(
          avatarUrl: userInfo == null
              ? ''
              : _resolvedProfileAvatar(userInfo, ''),
          name: cachedName.isEmpty ? uid : cachedName,
          identity: userInfo == null
              ? ''
              : _mapString(userInfo, const ['identity']),
          personality: userInfo == null
              ? ''
              : _mapString(userInfo, const ['bio', 'description']),
        );
      }
      if (!mounted || generation != _cachedProfileRoleLoadGeneration) return;
      if (nextRole != null) {
        _precacheProfileRoleAvatar(nextRole);
      }
      if (_sameOriginProfileRole(_cachedProfileRole, nextRole)) return;
      setState(() => _cachedProfileRole = nextRole);
    } catch (error, stackTrace) {
      debugPrint(
        '[OriginWorldPage] cached profile role preload failed: '
        '$error\n$stackTrace',
      );
      if (!mounted || generation != _cachedProfileRoleLoadGeneration) return;
      if (_cachedProfileRole != null) {
        setState(() => _cachedProfileRole = null);
      }
    }
  }

  void _precacheProfileRoleAvatar(OriginCustomRoleDraft profileRole) {
    if (!mounted) return;
    final snapshotSourceKey = _resolveAssetUrl(profileRole.avatarUrl).trim();
    final avatarUrl = _originRoleCardAvatarUrl(context, snapshotSourceKey);
    if (avatarUrl.isEmpty) return;

    final devicePixelRatio = genesisImageDevicePixelRatio(
      MediaQuery.devicePixelRatioOf(context),
      maxDevicePixelRatio: originWorldOpeningRoleAvatarMaxDevicePixelRatio,
    );
    final outputSize = (_OriginSetupRoleSection._cardWidth * devicePixelRatio)
        .ceil();
    final snapshotSize = math.max(
      1,
      (_originLocationChatRolePillAvatarSize * devicePixelRatio).ceil(),
    );
    final cacheKey = '$avatarUrl@$outputSize';
    if (!_preloadedProfileRoleAvatarKeys.add(cacheKey)) return;

    final provider = OriginRolePortraitImageProvider.fromUrl(
      imageUrl: avatarUrl,
      outputSize: outputSize,
      snapshotStore: _roleAvatarSnapshots,
      snapshotSourceKey: snapshotSourceKey,
      snapshotSize: snapshotSize,
    );
    unawaited(
      precacheImage(
        provider,
        context,
        onError: (error, stackTrace) {
          _preloadedProfileRoleAvatarKeys.remove(cacheKey);
          debugPrint(
            '[OriginWorldPage] profile role avatar precache failed '
            'url="$avatarUrl": $error',
          );
        },
      ),
    );
  }

  void _saveProfileRoleLocally(OriginCustomRoleDraft profileRole) {
    if (!mounted) return;
    _precacheProfileRoleAvatar(profileRole);
    setState(() => _localProfileRoleOverride = profileRole);
  }

  Color get _tilemapLoadingBackgroundColor =>
      tilemapVisualStyleFor(_tilemapVisualMode).backgroundColor;

  Future<void> _loadTilemapVisualMode() async {
    if (tilemapVisualModeController.isHydrated) {
      _tilemapVisualModeReady = true;
      return;
    }
    try {
      await const TilemapSettingsStore().load().timeout(
        const Duration(seconds: 2),
      );
    } catch (error) {
      debugPrint(
        '[OriginWorldPage] tilemap settings load failed; using defaults: '
        '$error',
      );
    } finally {
      _tilemapVisualModeReady = true;
    }
  }

  void _handleTilemapVisualModeChanged() {
    final visualMode = tilemapVisualModeController.value;
    if (!mounted || _tilemapVisualMode == visualMode) return;
    setState(() => _tilemapVisualMode = visualMode);
  }

  void _scheduleInitialOriginLoadAfterFrameworkFrame() {
    final scheduledGeneration = _originLoadGeneration;
    final scheduledOriginId = widget.oid.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _origin != null ||
          scheduledGeneration != _originLoadGeneration ||
          scheduledOriginId != widget.oid.trim()) {
        return;
      }
      unawaited(_fetchOriginDetail(isInitial: true));
    });
  }

  Future<void> _fetchOriginDetail({bool isInitial = false}) async {
    final generation = ++_originLoadGeneration;
    final requestedOriginId = widget.oid.trim();
    FirebasePerformanceOperation? requestOperation;
    if (isInitial && !_initialContentRenderCompleted) {
      final attempt = ++_initialRequestPerformanceAttempt;
      requestOperation = await FirebasePerformanceOperation.start(
        surface: FirebasePerformanceSurface.originWorldPage,
        phase: FirebasePerformancePhase.request,
        attempt: attempt,
      );
      if (!mounted ||
          generation != _originLoadGeneration ||
          widget.oid.trim() != requestedOriginId) {
        unawaited(requestOperation.cancel());
        return;
      }
      _initialRequestPerformanceOperation = requestOperation;
    }
    try {
      final origin = await AppServicesScope.read(
        context,
      ).api.getOrigin(requestedOriginId);
      if (!mounted ||
          generation != _originLoadGeneration ||
          widget.oid.trim() != requestedOriginId) {
        unawaited(requestOperation?.cancel());
        return;
      }
      if (identical(_initialRequestPerformanceOperation, requestOperation)) {
        _initialRequestPerformanceOperation = null;
      }
      unawaited(requestOperation?.succeed());
      final shouldStageInitialContent =
          isInitial ||
          _origin == null ||
          _renderStage != _OriginWorldPageRenderStage.content;
      setState(() {
        _origin = origin;
        _initialLoadError = null;
        if (shouldStageInitialContent) {
          _renderStage = _OriginWorldPageRenderStage.detailShell;
          _contentMountScheduled = false;
        }
      });
      _preloadCurrentTilemapLocationBackgrounds(origin);
      if (!shouldStageInitialContent) {
        _scheduleDeferredOriginPreloads(origin, generation);
      }
    } catch (error, stackTrace) {
      if (!mounted ||
          generation != _originLoadGeneration ||
          widget.oid.trim() != requestedOriginId) {
        unawaited(requestOperation?.cancel());
        return;
      }
      if (identical(_initialRequestPerformanceOperation, requestOperation)) {
        _initialRequestPerformanceOperation = null;
      }
      unawaited(
        requestOperation?.fail(errorType: firebasePerformanceErrorType(error)),
      );
      if (_origin == null) {
        setState(() => _initialLoadError = error);
      } else {
        debugPrint(
          '[OriginWorldPage] detail refresh failed: $error\n$stackTrace',
        );
        if (_renderStage == _OriginWorldPageRenderStage.detailShell) {
          unawaited(_mountContentAfterDetailShell(_origin!, generation));
        }
      }
    }
  }

  void _scheduleContentMountAfterDetailShellFrame(OriginDetail origin) {
    if (_renderStage != _OriginWorldPageRenderStage.detailShell ||
        _contentMountScheduled) {
      return;
    }
    final generation = _originLoadGeneration;
    _contentMountScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _originLoadGeneration ||
          !identical(_origin, origin) ||
          _renderStage != _OriginWorldPageRenderStage.detailShell) {
        _contentMountScheduled = false;
        return;
      }
      if (origin.definitionVersion != 2 ||
          _tilemapVisualModeReady ||
          tilemapVisualModeController.isHydrated) {
        unawaited(_mountContentAfterDetailShell(origin, generation));
        return;
      }
      unawaited(_mountContentAfterTilemapVisualModeLoad(origin, generation));
    });
  }

  Future<void> _mountContentAfterTilemapVisualModeLoad(
    OriginDetail origin,
    int generation,
  ) async {
    if (origin.definitionVersion == 2) {
      await _tilemapVisualModeLoad;
    }
    await _mountContentAfterDetailShell(origin, generation);
  }

  Future<void> _mountContentAfterDetailShell(
    OriginDetail origin,
    int generation,
  ) async {
    if (!mounted ||
        generation != _originLoadGeneration ||
        !identical(_origin, origin) ||
        _renderStage != _OriginWorldPageRenderStage.detailShell) {
      _contentMountScheduled = false;
      return;
    }
    _launchedPresetRolesPreloadScheduledForOriginId = widget.oid.trim();
    await _ensureLaunchedPresetRolesLoaded();
    if (!mounted ||
        generation != _originLoadGeneration ||
        !identical(_origin, origin) ||
        _renderStage != _OriginWorldPageRenderStage.detailShell) {
      _contentMountScheduled = false;
      return;
    }
    FirebasePerformanceOperation? renderOperation;
    if (!_initialContentRenderCompleted &&
        _initialRenderPerformanceOperation == null) {
      renderOperation = await FirebasePerformanceOperation.start(
        surface: FirebasePerformanceSurface.originWorldPage,
        phase: FirebasePerformancePhase.render,
        attempt: _initialRequestPerformanceAttempt == 0
            ? 1
            : _initialRequestPerformanceAttempt,
        timeout: FirebasePerformanceOperation.renderTimeout,
      );
      if (!mounted ||
          generation != _originLoadGeneration ||
          !identical(_origin, origin) ||
          _renderStage != _OriginWorldPageRenderStage.detailShell) {
        unawaited(renderOperation.cancel());
        _contentMountScheduled = false;
        return;
      }
      _initialRenderPerformanceOperation = renderOperation;
    }
    setState(() {
      _contentMountScheduled = false;
      _renderStage = _OriginWorldPageRenderStage.content;
    });
    if (renderOperation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _originLoadGeneration ||
            !identical(_initialRenderPerformanceOperation, renderOperation) ||
            !identical(_origin, origin) ||
            _renderStage != _OriginWorldPageRenderStage.content) {
          if (identical(_initialRenderPerformanceOperation, renderOperation)) {
            _initialRenderPerformanceOperation = null;
          }
          unawaited(renderOperation?.cancel());
          return;
        }
        _initialRenderPerformanceOperation = null;
        _initialContentRenderCompleted = true;
        unawaited(renderOperation?.succeed());
      });
    }
    _scheduleDeferredOriginPreloads(origin, generation);
  }

  void _scheduleDeferredOriginPreloads(OriginDetail origin, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _originLoadGeneration ||
          !identical(_origin, origin) ||
          _renderStage != _OriginWorldPageRenderStage.content) {
        return;
      }
      _precacheRoleCardAvatarImages(origin);
      _scheduleLaunchedPresetRolesPreload();
    });
  }

  void _scheduleLaunchedPresetRolesPreload() {
    final originId = widget.oid.trim();
    if (originId.isEmpty ||
        _launchedPresetRolesPreloadScheduledForOriginId == originId) {
      return;
    }
    _launchedPresetRolesPreloadScheduledForOriginId = originId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.oid.trim() != originId) return;
      unawaited(_ensureLaunchedPresetRolesLoaded());
    });
  }

  void _precacheRoleCardAvatarImages(OriginDetail origin) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) return;
    final urls = origin.characters
        .map(
          (character) => selectGenesisImageUrl(
            _resolveAssetUrl(character.avatar),
            logicalWidth: _OriginSetupRoleSection._cardWidth,
            logicalHeight: _OriginSetupRoleSection._cardWidth,
            devicePixelRatio: mediaQuery.devicePixelRatio,
          ).trim(),
        )
        .where((url) => url.isNotEmpty && !url.startsWith('assets/'))
        .toSet();
    for (final url in urls) {
      unawaited(_precacheOriginAvatarFile(url));
    }
  }

  Future<void> _precacheOriginAvatarFile(String url) async {
    try {
      await GenesisHttpCacheManager().getSingleFile(url);
    } catch (error) {
      debugPrint('[OriginWorldPage] avatar precache failed url="$url": $error');
    }
  }

  void _refreshOriginDetail() {
    unawaited(_fetchOriginDetail());
  }

  void _openChatForPoint(OriginDetail origin, WorldPoint point) {
    final pointId = point.pointId.trim().isNotEmpty
        ? point.pointId.trim()
        : point.id.trim();
    final locationId = point.sceneId.trim().isNotEmpty
        ? point.sceneId.trim()
        : pointId;
    if (locationId.isEmpty) return;
    final openingPreviewMessages = _originLocationOpeningPreviewMessages(
      origin,
      [locationId, pointId, point.id],
    );
    final openingPreviewEntities = _originLocationOpeningPreviewEntities(
      origin.characters,
      openingPreviewMessages,
      locationId,
    );
    GenesisTelemetry.collectLog(
      actionType: 'pageview',
      action: 'worldo_map',
      object1: origin.oid,
      object2: locationId,
    );
    GenesisTelemetry.collectLog(
      actionType: 'pageview',
      action: 'worldo_location_chat',
      object1: origin.oid,
      object2: locationId,
    );

    setState(() {
      _activeChatLocation = _OriginLocationChatDescriptor(
        originId: origin.oid,
        locationId: locationId,
        locationName: point.name,
        backgroundImageUrl: point.iconUrl.trim().isNotEmpty
            ? point.iconUrl
            : point.mapImageUrl,
        backgroundPreviewImageUrl: '',
        isLeafLocation: point.isLeafLocation,
        openingPreviewMessages: openingPreviewMessages,
        openingPreviewEntities: openingPreviewEntities,
      );
    });
  }

  void _recordWorldoMapClick(OriginDetail origin) {
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'worldo_map_click',
      object1: origin.oid,
    );
  }

  void _recordWorldoTilemapClick(OriginDetail origin) {
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'worldo_tilemap_click',
      object1: origin.oid,
    );
  }

  void _closeLocationChat() {
    if (_activeChatLocation == null || _launching) return;
    setState(() => _activeChatLocation = null);
  }

  void _setLocationChatRoleId(String roleId) {
    if (roleId == _selectedLocationChatRoleId) return;
    setState(() => _selectedLocationChatRoleId = roleId);
  }

  void _handleOriginPopBlocked() {
    if (_activeChatLocation == null) return;
    _closeLocationChat();
  }

  void _enterLaunchedWorld(
    String worldId, {
    String initialLocationId = '',
    String initialMessageToSend = '',
    ChatMentionCatalog? initialMentionCatalog,
  }) {
    final navigator = Navigator.of(context);
    openWorldFromMyWorldsRoot(
      navigator,
      arguments: {
        'wid': worldId,
        if (initialLocationId.trim().isNotEmpty)
          'initial_location_id': initialLocationId.trim(),
        if (initialMessageToSend.trim().isNotEmpty)
          'initial_message_to_send': initialMessageToSend,
        if (initialMentionCatalog != null)
          'initial_mention_catalog': initialMentionCatalog,
      },
    );
  }

  Future<List<OriginMyLaunchPresetCharacter>>
  _ensureLaunchedPresetRolesLoaded() {
    final preparation = _launchedPresetRolesPreparationFuture;
    if (preparation != null) return preparation;
    late final Future<List<OriginMyLaunchPresetCharacter>> trackedPreparation;
    trackedPreparation = _prepareLaunchedPresetRoles().whenComplete(() {
      if (identical(
        _launchedPresetRolesPreparationFuture,
        trackedPreparation,
      )) {
        _launchedPresetRolesPreparationFuture = null;
      }
    });
    _launchedPresetRolesPreparationFuture = trackedPreparation;
    return trackedPreparation;
  }

  Future<List<OriginMyLaunchPresetCharacter>>
  _prepareLaunchedPresetRoles() async {
    final originId = widget.oid.trim();
    if (originId.isEmpty) return const <OriginMyLaunchPresetCharacter>[];
    try {
      final services = AppServicesScope.read(context);
      final uid = await services.sessionStore.readLoginUid();
      if (!mounted || widget.oid.trim() != originId || uid == null) {
        return const <OriginMyLaunchPresetCharacter>[];
      }

      final cacheKey = '$originId::$uid';
      final cachedFuture = _launchedPresetRolesFuture;
      if (_launchedPresetRolesCacheKey == cacheKey && cachedFuture != null) {
        return cachedFuture;
      }

      final request = _requestLaunchedPresetRoles(
        originId: originId,
        cacheKey: cacheKey,
      );
      _launchedPresetRolesCacheKey = cacheKey;
      _launchedPresetRolesFuture = request;
      return request;
    } catch (error, stackTrace) {
      debugPrint(
        '[OriginWorldPage] launched preset roles preparation failed: '
        '$error\n$stackTrace',
      );
      return const <OriginMyLaunchPresetCharacter>[];
    }
  }

  Future<List<OriginMyLaunchPresetCharacter>> _requestLaunchedPresetRoles({
    required String originId,
    required String cacheKey,
  }) async {
    try {
      final roles = await AppServicesScope.read(context).api
          .getMyLaunchPresetCharacters(
            originId,
            limit: originLaunchedWorldPreviewLimitForTesting,
          );
      if (mounted && _launchedPresetRolesCacheKey == cacheKey) {
        setState(() => _launchedPresetRolesData = roles);
      }
      return roles;
    } catch (error, stackTrace) {
      debugPrint(
        '[OriginWorldPage] launched preset roles preload failed: '
        '$error\n$stackTrace',
      );
      if (_launchedPresetRolesCacheKey == cacheKey) {
        _launchedPresetRolesCacheKey = '';
        _launchedPresetRolesFuture = null;
        _launchedPresetRolesData = null;
      }
      return const <OriginMyLaunchPresetCharacter>[];
    }
  }

  Future<String?> _launchOrigin(
    OriginDetail origin,
    OriginRoleLaunchSelection roleSelection, {
    required String telemetryRoleId,
    required OriginLaunchSource launchSource,
    String initialLocationId = '',
    String initialMessageToSend = '',
    ChatMentionCatalog? initialMentionCatalog,
    bool enterWorldOnSuccess = true,
  }) async {
    if (_launching) return null;
    setState(() => _activeLaunchSource = launchSource);
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: launchSource.startAction,
      object1: origin.oid,
      object2: telemetryRoleId,
    );
    final launchedWorldId = await startOriginLaunch(
      context: context,
      origin: origin,
      roleSelection: roleSelection,
      launchSource: launchSource,
    );
    if (!mounted) return null;
    if (launchedWorldId == null) {
      setState(() => _activeLaunchSource = null);
      return null;
    }
    setState(() {
      _activeLaunchSource = null;
      _launchedPresetRolesFuture = null;
      _launchedPresetRolesPreparationFuture = null;
      _launchedPresetRolesData = null;
      _launchedPresetRolesCacheKey = '';
    });
    if (enterWorldOnSuccess) {
      _enterLaunchedWorld(
        launchedWorldId,
        initialLocationId: initialLocationId,
        initialMessageToSend: initialMessageToSend,
        initialMentionCatalog: initialMentionCatalog,
      );
    }
    return launchedWorldId;
  }

  Future<OriginCustomRoleDraft?> _customRoleFromProfile() async {
    if (!await _ensureProfileFillLogin()) return null;
    if (!mounted) return null;
    final services = AppServicesScope.read(context);
    final userInfo = await services.sessionStore.readUserInfo();
    if (userInfo == null || userInfo.isEmpty) {
      if (mounted) {
        showGenesisToast(
          context,
          'No saved profile found',
          brightness: Brightness.dark,
        );
      }
      return null;
    }
    final cachedUser = userInfo;
    final cachedName = _mapString(cachedUser, const [
      'name',
      'nickname',
      'user_name',
      'displayName',
      'display_name',
    ]);
    final resolvedAvatar = _resolvedProfileAvatar(cachedUser, '');

    return OriginCustomRoleDraft(
      avatarUrl: resolvedAvatar,
      name: cachedName,
      identity: _mapString(cachedUser, const ['identity']),
      personality: _mapString(cachedUser, const ['bio', 'description']),
    );
  }

  Future<bool> _ensureProfileFillLogin() async {
    if (await _hasLocalLoginSession()) return true;
    if (!mounted) return false;
    final loggedIn = await showLoginSheet(
      context: context,
      onLogin: _loginWithProvider,
    );
    if (!mounted || !loggedIn) return false;
    await showDailyCheckInAfterLogin(context);
    if (!mounted) return false;
    return _hasLocalLoginSession();
  }

  Future<bool> _hasLocalLoginSession() async {
    final services = AppServicesScope.read(context);
    return await services.sessionStore.readLoginUid() != null;
  }

  Future<bool> _loginWithProvider(IdentityProvider provider) async {
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
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = GenesisSafeAreaInsets.top(context);
    return _buildPageContent(topPadding);
  }

  Widget _buildPageContent(double topPadding) {
    final origin = _origin;
    if (origin == null) {
      if (_initialLoadError != null) {
        return Scaffold(
          backgroundColor: GenesisColors.darkBackground,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Load failed',
                  style: TextStyle(color: GenesisColors.darkTextSecondary),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () {
                    setState(() => _initialLoadError = null);
                    unawaited(_fetchOriginDetail(isInitial: true));
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      return _buildInitialLoadingScaffold(topPadding);
    }
    if (_renderStage != _OriginWorldPageRenderStage.content) {
      _scheduleContentMountAfterDetailShellFrame(origin);
      return _buildInitialLoadingScaffold(topPadding, origin: origin);
    }

    final preferredInitialMapLocationId =
        origin.definitionVersion == 2 &&
            widget.initialDefinitionVersion == origin.definitionVersion
        ? widget.initialMapLocationId
        : '';
    final mapPresentationData = _mapPresentationDataFor(
      origin,
      preferredInitialMapLocationId: preferredInitialMapLocationId,
    );
    final deferTilemapRendering =
        origin.definitionVersion == 2 &&
        _waitingForOpeningSheetExpansion &&
        widget.initialMapLocationId.trim().isEmpty;
    final Widget map = deferTilemapRendering
        ? ColoredBox(
            key: const ValueKey<String>('origin-opening-sheet-map-background'),
            color: _tilemapLoadingBackgroundColor,
          )
        : ValueListenableBuilder<bool>(
            valueListenable: _detailSheetRaisedNotifier,
            builder: (context, detailSheetRaised, _) => WorldMap.origin(
              definitionVersion: origin.definitionVersion,
              originId: origin.oid,
              common: WorldMapCommonConfig(
                locationNodes: mapPresentationData.locationNodes,
                messageBubbles: _activeChatLocation == null
                    ? mapPresentationData.messageBubbles
                    : const <WorldMapMessageBubble>[],
                messageBubblePlaybackPaused: _activeChatLocation != null,
                onMapTap: () => _recordWorldoMapClick(origin),
                onPointTap: (point) => _openChatForPoint(origin, point),
              ),
              legacy: LegacyWorldMapConfig(
                implementationKey: PageStorageKey<String>(
                  'origin-map-${origin.oid}',
                ),
                points: mapPresentationData.points,
                listPoints: mapPresentationData.listPoints,
                listLocationNodes: mapPresentationData.listLocationNodes,
                mapImageUrl: mapPresentationData.mapImageUrl,
                initialZoomScale: 1.2,
                enableAvatarScaleReboundHint: true,
                pointsListOuterScrollHandoff: false,
                overlayTop: topPadding + 8 + 48,
              ),
              tilemap: WorldMapTilemapOptions(
                implementationKey: _tilemapImplementationKey,
                locationId: mapPresentationData.initialTilemapLocationId,
                locationNodes: mapPresentationData.listLocationNodes,
                preferredFocusLocationId:
                    origin.initLocationGroup?.locationId.trim() ?? '',
                centerContentInitially: true,
                showVisualModeToggle: true,
                animationsPaused: detailSheetRaised,
                locationImageFlowPaused: detailSheetRaised,
                visualModeToggleTop:
                    topPadding + 8 + genesisSearchFieldHeight + 8,
                visualModeToggleRight: 12,
                restorationController: _tilemapRestorationController,
                onMapTap: () => _recordWorldoTilemapClick(origin),
                onCurrentLocationsChanged:
                    _handleCurrentTilemapLocationsChanged,
              ),
            ),
          );

    return PopScope(
      canPop: _activeChatLocation == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleOriginPopBlocked();
      },
      child: _buildMapOnlyScaffold(
        topPadding: topPadding,
        mapOverlay: _buildPersistentMapOverlay(topPadding, origin: origin),
        bottomSheetOverlayBuilder: (minChildSize) =>
            _OriginDetailDraggableSheet(
              origin: origin,
              roleAvatarSnapshots: _roleAvatarSnapshots,
              minChildSize: minChildSize,
              initiallyExpanded: widget.showOpeningSheetOnEntry,
              autoExpansionPending: _waitingForOpeningSheetExpansion,
              onRaisedChanged: _handleDetailSheetRaisedChanged,
              onFullyExpanded: _handleOpeningSheetFullyExpanded,
              onAutoExpansionInterrupted:
                  _handleOpeningSheetExpansionInterrupted,
              onOriginChanged: _refreshOriginDetail,
              activeLaunchSource: _activeLaunchSource,
              launchedPresetRoles: _launchedPresetRolesData,
              onEnterLaunchedWorld: (role) {
                final worldId = role.worldId.trim();
                if (worldId.isEmpty) return;
                _enterLaunchedWorld(worldId);
              },
              profileRole: _openingProfileRole,
              onSaveProfileRole: _saveProfileRoleLocally,
              locationChatRole: _locationChatRoleOption(origin),
              onSelectLocationChatRole: (roleId) =>
                  _selectLocationChatRole(roleId),
              onSendLocationChatMessage:
                  (locationId, message, mentionCatalog) =>
                      _launchLocationChatMessage(
                        origin,
                        locationId: locationId,
                        message: message,
                        mentionCatalog: mentionCatalog,
                      ),
            ),
        topOverlay: _buildLocationChatOverlay(),
        map: WorldKeepAlivePage(child: map),
      ),
    );
  }

  void _handleDetailSheetRaisedChanged(bool raised) {
    if (!mounted || _detailSheetRaisedNotifier.value == raised) return;
    _detailSheetRaisedNotifier.value = raised;
  }

  void _handleOpeningSheetFullyExpanded() {
    if (!mounted || !_waitingForOpeningSheetExpansion) return;
    setState(() => _waitingForOpeningSheetExpansion = false);
  }

  void _handleOpeningSheetExpansionInterrupted() {
    if (!mounted || !_waitingForOpeningSheetExpansion) return;
    setState(() => _waitingForOpeningSheetExpansion = false);
  }
}
