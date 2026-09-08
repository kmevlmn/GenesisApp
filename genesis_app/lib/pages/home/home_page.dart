import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/startup/app_startup_coordinator.dart';
import '../../app/telemetry/firebase_performance_operation.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/auth/login_guard.dart';
import '../../components/common/list_loading_skeleton.dart';
import '../../components/gems/gem_assets.dart';
import '../../components/home/world_item_card.dart';
import '../../components/page_header.dart';
import '../../components/search_bar.dart';
import '../../network/api_exception.dart';
import '../../network/json_utils.dart';
import '../../platform/session/user_session_store.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_deleted_list_item_transition.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/components/genesis_refresh_indicator.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import 'home_feed_cache_store.dart';
import '../world/world_deletion_events.dart';
import '../world/world_page_result.dart';

part 'home_page_chrome.dart';
part 'home_my_world_feed.dart';
part 'home_world_feed_widgets.dart';

void _ignoreHomeFeedCacheWrite(Future<void> write) {
  unawaited(write.catchError((_) {}));
}

Future<void> _waitHomeInitialRequestMetricWindow(Duration delay) async {
  if (delay <= Duration.zero) return;
  await Future<void>.delayed(delay);
}

const Duration _homeInitialNetworkRetryDelay = Duration(seconds: 2);
const Duration _homeLocalRestoreTimeout = Duration(milliseconds: 500);

typedef HomeMyWorldsCacheLoader =
    Future<Map<String, dynamic>?> Function(String ownerUid);

bool _isNetworkLikeHomeError(Object error) {
  if (error is ApiException) {
    return error.kind == ApiExceptionKind.timeout ||
        error.kind == ApiExceptionKind.transport ||
        error.transportErrorKind == TransportErrorKind.timeout ||
        error.transportErrorKind == TransportErrorKind.connection;
  }
  if (error is TimeoutException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('timeout') ||
      text.contains('socket') ||
      text.contains('connection') ||
      text.contains('network') ||
      text.contains('host lookup');
}

_WorldListPage _parseHomeWorldListPage(
  Map<String, dynamic> data, {
  Set<String> locallyDeletedWorldIds = const <String>{},
}) {
  final list = data['list'];
  final items = list is List
      ? list
            .whereType<Map>()
            .map((raw) => WorldListItem.fromJson(asJsonMap(raw)))
            .where((item) => !locallyDeletedWorldIds.contains(item.wid.trim()))
            .toList(growable: false)
      : const <WorldListItem>[];
  return _WorldListPage(items: items, total: asInt(data['total']));
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.initialMyWorldsData,
    this.activationListenable,
    this.reselectionListenable,
    this.isActiveListenable,
    this.isFirstPageViewReported,
    this.onFirstPageViewReady,
    this.onOpenWorldo,
    this.initialRequestMetricWindow = Duration.zero,
    this.localRestoreTimeout = _homeLocalRestoreTimeout,
    this.myWorldsCacheLoader,
  });

  final Map<String, dynamic>? initialMyWorldsData;
  final ValueListenable<int>? activationListenable;
  final ValueListenable<int>? reselectionListenable;
  final ValueListenable<bool>? isActiveListenable;
  final bool Function(String action)? isFirstPageViewReported;
  final void Function(String action)? onFirstPageViewReady;
  final VoidCallback? onOpenWorldo;
  final Duration initialRequestMetricWindow;
  final Duration localRestoreTimeout;
  final HomeMyWorldsCacheLoader? myWorldsCacheLoader;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Feed widgets still observe this notifier for their own loading lifecycle;
  // startup permissions never change it.
  late final ValueNotifier<bool> _homeNetworkRequestsAllowed;

  @override
  void initState() {
    super.initState();
    _homeNetworkRequestsAllowed = ValueNotifier<bool>(true);
  }

  @override
  void dispose() {
    _homeNetworkRequestsAllowed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GenesisDarkTheme(
      child: ColoredBox(
        color: GenesisColors.darkBackground,
        child: _HomeScaffold(
          activationListenable: widget.activationListenable,
          reselectionListenable: widget.reselectionListenable,
          isActiveListenable: widget.isActiveListenable,
          isFirstPageViewReported: widget.isFirstPageViewReported,
          onFirstPageViewReady: widget.onFirstPageViewReady,
          onOpenWorldo: widget.onOpenWorldo,
          networkRequestsAllowed: _homeNetworkRequestsAllowed,
          keepInitialNetworkFailureLoading: false,
          initialRequestMetricWindow: widget.initialRequestMetricWindow,
          localRestoreTimeout: widget.localRestoreTimeout,
          myWorldsCacheLoader: widget.myWorldsCacheLoader,
          initialMyWorldsData: widget.initialMyWorldsData,
          initialMyWorldsRenderOperation: null,
          initialMyWorldsRequestAttempt: 0,
        ),
      ),
    );
  }
}
