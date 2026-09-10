import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'chatroom/chatroom_timeline_payload.dart';
import 'http_transport.dart';
import 'json_utils.dart';
import 'mock_data/mock_message_data.dart';
import 'mock_data/mock_origin_data.dart';
import 'mock_data/mock_profile_data.dart';
import 'mock_data/mock_v1_data.dart';
import 'mock_data/mock_world_data.dart';

class LocalMockGenesisTransport implements HttpTransport {
  LocalMockGenesisTransport._();

  static final LocalMockGenesisTransport instance =
      LocalMockGenesisTransport._();

  final _state = _MockState();

  /// Adds an opt-in timeline bundle without changing the default mock seed.
  void seedChatroomTimelineMessages({
    required String worldId,
    required String locationId,
  }) {
    _state.seedChatroomTimelineMessages(
      worldId: worldId,
      locationId: locationId,
    );
  }

  /// Adds one canonical V2 tick with a positive location cursor.
  void seedChatroomV2TickMessage({
    required String worldId,
    required String locationId,
  }) {
    _state.seedChatroomV2TickMessage(worldId: worldId, locationId: locationId);
  }

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final path = request.uri.path;
    final query = request.uri.queryParameters;
    final method = request.method.toUpperCase();
    final body = _decodeBody(request.bodyBytes);

    if (method == 'POST' && path == '/api_internal/v1/membership/set') {
      return _ok({
        'err_no': 5000,
        'err_msg': 'manual membership setting unavailable in mock',
        'data': null,
      });
    }

    if (path == '/health') {
      return _ok({'status': 'ok'});
    }

    final isGatewayApiPath = path.startsWith('/apix/');
    final apiPath = path.startsWith('/api/')
        ? path.substring('/api/'.length)
        : isGatewayApiPath
        ? path.substring('/apix/'.length)
        : path.startsWith('/')
        ? path.substring(1)
        : path;

    if (apiPath == 'v1/heartbeat') {
      return _ok({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {'status': 'ok'},
      });
    }

    if (apiPath == 'v1/time') {
      return _ok({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {'server_time_ms': DateTime.now().millisecondsSinceEpoch},
      });
    }

    if (method == 'POST' && apiPath == 'v1/app/device/challenge') {
      return _ok({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {
          'register_id': 'mock-register',
          'challenge': 'mock-challenge',
          'expires_in': 300,
        },
      });
    }

    if (method == 'POST' && apiPath == 'v1/app/device/register') {
      return _ok({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {'key_id': 'mock-key'},
      });
    }

    if (isGatewayApiPath) {
      return _error(
        404,
        'mock gateway route not found: $method /apix/$apiPath',
      );
    }

    if (apiPath.startsWith('aitown-chat/')) {
      return _handleChatroomHttp(method, apiPath, query, body);
    }

    if (apiPath.startsWith('v2/')) {
      return _handleV2(method, apiPath.substring('v2/'.length), query, body);
    }

    if (apiPath.startsWith('v1/')) {
      return _handleV1(
        method,
        apiPath.substring('v1/'.length),
        query,
        body,
        _requestDeviceId(request),
        _requestHasAuthorization(request),
      );
    }

    if (method == 'GET' && apiPath == 'auth/me/public-profile') {
      if (!_state.isAuthenticated) {
        return _error(401, 'unauthorized');
      }
      return _ok(_state.me);
    }

    if (method == 'POST' &&
        (apiPath == 'auth/google' || apiPath == 'auth/apple')) {
      _state.markAuthenticated();
      return _ok({
        'token': 'mock-jwt-token',
        'user': _state.googleUserPayload(),
      });
    }

    if (method == 'POST' && apiPath == 'auth/logout') {
      _state.markLoggedOut();
      return _ok({'ok': true});
    }

    if (method == 'GET' && apiPath == 'origins') {
      return _ok({'origins': _state.origins});
    }

    if (method == 'GET' && apiPath == 'origins/create-limits') {
      return _ok({
        'ok': true,
        'ai_characters_max': 8,
        'locations_max': 10,
        'events_max': 20,
      });
    }

    if (method == 'POST' && apiPath == 'origins') {
      final created = _state.createOrigin(body);
      return _ok({'ok': true, ...created});
    }

    if (method == 'GET' && apiPath == 'origins/popular') {
      final limit = int.tryParse(query['limit'] ?? '') ?? 20;
      final items = _state.origins.take(limit).toList(growable: false);
      return _ok({'origins': items});
    }

    final detailMatch = RegExp(r'^origins/([^/]+)/detail$').firstMatch(apiPath);
    if (method == 'GET' && detailMatch != null) {
      final worldviewId = detailMatch.group(1) ?? '';
      final origin = _state.originByWorldview(worldviewId);
      if (origin == null) return _error(404, 'origin not found');
      return _ok(origin);
    }

    if (method == 'POST' && apiPath == 'worlds/launch') {
      final uid = '${body['user_id'] ?? _state.me['id']}';
      final worldviewId = '${body['worldview_id'] ?? ''}';
      final worldName = '${body['world_name'] ?? 'World'}';
      final launched = _state.launchWorld(
        userId: uid,
        worldviewId: worldviewId,
        worldName: worldName,
      );
      return _ok({'ok': true, ...launched});
    }

    final worldMetaMatch = RegExp(
      r'^worlds/([^/]+)/public-meta$',
    ).firstMatch(apiPath);
    if (method == 'GET' && worldMetaMatch != null) {
      final wid = worldMetaMatch.group(1) ?? '';
      final world = _state.worldByWid(wid);
      if (world == null) return _error(404, 'world not found');
      return _ok({
        'ok': true,
        'is_owner': true,
        'owner_user_id': world['owner_user_id'],
        'owner_display_name': _state.me['display_name'],
        'owner_user_code': _state.me['user_code'],
        'world_name': world['world_name'],
        'display_wid_str': world['display_wid_str'],
        'has_entered': true,
        'join_status': 'approved',
        'can_request_join': false,
        'can_enter': true,
        'is_full': false,
      });
    }

    if (method == 'GET' && apiPath == 'tick') {
      final wid = query['wid'] ?? '';
      final tick = _state.tickByWid(wid);
      if (tick == null) return _error(404, 'tick not found');
      return _ok(tick);
    }

    if (method == 'POST' && apiPath == 'tick') {
      final wid = query['wid'] ?? '';
      final updated = _state.progressTick(wid);
      if (updated == null) return _error(404, 'tick not found');
      return _ok(updated);
    }

    if (method == 'GET' && apiPath == 'worldview-map') {
      final wid = query['wid'] ?? '';
      final map = _state.worldMapByWid(wid);
      if (map == null) return _error(404, 'map not found');
      return _ok(map);
    }

    if (method == 'GET' && apiPath == 'characters') {
      final wid = query['wid'] ?? '';
      final chars = _state.charactersByWid(wid);
      if (chars == null) return _error(404, 'characters not found');
      return _ok(chars);
    }

    final pointMessagesMatch = RegExp(
      r'^points/([^/]+)/messages$',
    ).firstMatch(apiPath);
    if (method == 'GET' && pointMessagesMatch != null) {
      final pointId = pointMessagesMatch.group(1) ?? '';
      final limit = int.tryParse(query['limit'] ?? '') ?? 50;
      final messages = _state.messagesForPoint(pointId, limit: limit);
      return _ok({'messages': messages, 'has_more': false});
    }

    final enqueueMatch = RegExp(
      r'^points/([^/]+)/messages/enqueue$',
    ).firstMatch(apiPath);
    if (method == 'POST' && enqueueMatch != null) {
      final pointId = enqueueMatch.group(1) ?? '';
      final wid = '${body['wid'] ?? ''}';
      final message = _state.enqueuePointMessage(
        wid: wid,
        pointId: pointId,
        locationId: '${body['location_id'] ?? ''}',
        userId: '${body['user_id'] ?? _state.me['id']}',
        text: '${body['text'] ?? ''}',
      );
      return _ok({
        'ok': true,
        'user_message': {'id': message['id']},
      });
    }

    if (method == 'GET' && apiPath == 'worlds') {
      final userId = query['user_id'] ?? _state.me['id'];
      final worlds = _state.worldsForUser('$userId');
      return _ok({'worlds': worlds});
    }

    if (method == 'GET' && apiPath == 'search') {
      final raw = query['q'] ?? query['keyword'] ?? query['query'] ?? '';
      final q = raw.toString().trim();
      final result = _state.search(q);
      return _ok(result);
    }

    final joinMatch = RegExp(
      r'^worlds/([^/]+)/join-requests$',
    ).firstMatch(apiPath);
    if (method == 'POST' && joinMatch != null) {
      return _ok({'ok': true});
    }

    return _error(404, 'mock route not found: $method $path');
  }

  Future<TransportResponse> _handleChatroomHttp(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic> body,
  ) async {
    if (method == 'GET' && path == 'aitown-chat/api/ulocation') {
      return _v1Ok(_state.chatroomUserLocations(query['world_id'] ?? ''));
    }

    if (method == 'GET' && path == 'aitown-chat/internal/world/messages') {
      return _v1Ok(_state.chatroomWorldMessages(query['world_id'] ?? ''));
    }

    if (method == 'GET' && path == 'aitown-chat/api/messages') {
      return _v1Ok(
        _state.chatroomHistoryMessages(
          worldId: query['world_id'] ?? '',
          locationId: query['location_id'] ?? '',
          since: int.tryParse(query['since'] ?? ''),
          limit: int.tryParse(query['limit'] ?? ''),
        ),
      );
    }

    if (method == 'GET' && path == 'aitown-chat/api/v2/messages') {
      final start = int.tryParse(query['start_conversation_round_id'] ?? '0');
      final end = int.tryParse(query['end_conversation_round_id'] ?? '0');
      if (start == null ||
          end == null ||
          !((start == 0 && end == 0) || (start > 0 && end >= start))) {
        return _v1BusinessError(1001, 'invalid conversation range');
      }
      return _v1Ok(
        _state.chatroomV2HistoryMessages(
          worldId: query['world_id'] ?? '',
          locationId: query['location_id'] ?? '',
          since: int.tryParse(query['since'] ?? ''),
          limit: int.tryParse(query['limit'] ?? ''),
          startConversationRoundId: start,
          endConversationRoundId: end,
        ),
      );
    }

    if (method == 'POST' &&
        RegExp(
          r'^aitown-chat/api/v1/worlds/[^/]+/locations/[^/]+/inspiration$',
        ).hasMatch(path)) {
      return _error(
        501,
        'Inspiration generation is not simulated by the local transport',
      );
    }

    final cards = RegExp(
      r'^aitown-chat/api/v1/worlds/[^/]+/locations/[^/]+/llm-messages/(cards|select)$',
    ).firstMatch(path);
    if (cards != null && method == 'GET' && cards.group(1) == 'cards') {
      final round = int.tryParse(query['conversation_round_id'] ?? '');
      if (round == null || round <= 0) {
        return _v1BusinessError(1001, 'Invalid conversation round');
      }
      // No regeneration runtime is simulated by the local HTTP transport.
      return _v1Ok({
        'conversation_round_id': round,
        'original_card_id': 0,
        'selected_card_id': 0,
        'active_card_id': 0,
        'confirmed': false,
        'can_regenerate': false,
        'can_confirm': false,
        'list': [],
        'total': 0,
      });
    }
    if (cards != null && method == 'POST' && cards.group(1) == 'select') {
      return _error(
        501,
        'Card selection is not simulated by the local transport',
      );
    }

    final mutation = RegExp(
      r'^aitown-chat/api/v1/worlds/([^/]+)/locations/([^/]+)/llm-messages/batch$',
    ).firstMatch(path);
    if (method == 'POST' && mutation != null) {
      if (body.containsKey('card_id')) {
        return _error(
          501,
          'Candidate mutation is not simulated by the local transport',
        );
      }
      return _ok(
        _state.mutateChatroomLlmMessages(
          worldId: Uri.decodeComponent(mutation.group(1)!),
          locationId: Uri.decodeComponent(mutation.group(2)!),
          body: body,
        ),
      );
    }

    if (method == 'POST' && path == 'aitown-chat/internal/tick/lock') {
      final worldId = '${query['world_id'] ?? body['world_id'] ?? ''}';
      return _v1Ok(_state.lockChatroomWorld(worldId));
    }

    if (method == 'GET' && path == 'aitown-chat/internal/tick/is_locked') {
      return _v1Ok(_state.chatroomTickLockStatus(query['world_id'] ?? ''));
    }

    if (method == 'GET' && path == 'aitown-chat/internal/tick/progress') {
      return _v1Ok(_state.chatroomTickProgress(query['world_id'] ?? ''));
    }

    if (method == 'POST' && path == 'aitown-chat/internal/tick/unlock') {
      return _v1Ok(_state.unlockChatroomWorld('${body['world_id'] ?? ''}'));
    }

    if (method == 'POST' && path == 'aitown-chat/internal/narrator/write') {
      return _v1Ok(_state.writeChatroomNarrator(body));
    }

    return _error(404, 'mock chatroom route not found: $method /$path');
  }

  Future<TransportResponse> _handleV2(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic> body,
  ) async {
    if (method == 'GET' && path == 'search') {
      if (kDebugMode) {
        debugPrint('[LocalMockGenesisTransport] GET /api/v2/search $query');
      }
      return _v1Ok(_state.v1Search(query));
    }

    if (method == 'GET' && path == 'origin/foredit') {
      final originId = (query['origin_id'] ?? '').trim();
      if (originId.isEmpty) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      if (!_state.v1OriginExists(originId)) {
        return _v1BusinessError(20101, 'ErrorOriginNotExist');
      }
      if (!_state.canEditV1Origin(originId)) {
        return _v1BusinessError(10011, 'ErrorUserNotAccess');
      }
      return _v1Ok(_state.v2OriginForEdit(originId));
    }

    if (method == 'POST' && path == 'origin/create') {
      return _v1Ok(_state.createV2Origin(body));
    }

    if (method == 'POST' && path == 'origin/update') {
      return _v1Ok(_state.updateV2Origin(body));
    }

    return _error(404, 'mock v2 route not found: $method /api/v2/$path');
  }

  Future<TransportResponse> _handleV1(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic> body,
    String deviceId,
    bool requestHasAuthorization,
  ) async {
    if (method == 'POST' && path == 'app/version/check') {
      return _v1Ok({
        'need_upgrade': false,
        'force_upgrade': false,
        'latest_version_name': '',
        'latest_version_code': 0,
        'min_version_code': 0,
        'upgrade_type': 0,
        'title': '',
        'content': '',
        'download_url': '',
        'store_url': '',
        'package_size': 0,
        'package_md5': '',
        'can_ignore': true,
      });
    }

    if (method == 'POST' &&
        (path == 'user/oauth/google' || path == 'user/oauth/apple')) {
      _state.markAuthenticated();
      return _v1Ok(_state.v1AuthPayload());
    }

    if (method == 'POST' && path == 'user/logout') {
      _state.markLoggedOut();
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'POST' && path == 'user/delete') {
      _state.markLoggedOut();
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'GET' && path == 'user/info') {
      final uid = (query['uid'] ?? '').trim();
      final viewerAuthenticated =
          _state.isAuthenticated || requestHasAuthorization;
      if (uid.isEmpty && !viewerAuthenticated) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      return _v1Ok(
        _state.v1UserInfo(uid, viewerAuthenticated: viewerAuthenticated),
      );
    }

    if (method == 'POST' && path == 'user/update') {
      return _v1Ok({'user': _state.updateV1User(body)});
    }

    if (method == 'POST' && path == 'user/block') {
      final targetUid = '${body['target_uid'] ?? ''}'.trim();
      if (targetUid.isEmpty) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      _state.blockV1User(targetUid);
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'POST' && path == 'user/unblock') {
      final targetUid = '${body['target_uid'] ?? ''}'.trim();
      if (targetUid.isEmpty) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      _state.unblockV1User(targetUid);
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'GET' && path == 'user/blocks') {
      return _v1Ok(_paged(_state.v1UserBlocks(), query));
    }

    if (method == 'GET' && path == 'user/world-history-settings') {
      return _v1Ok(_state.v1WorldHistorySettings());
    }

    if (method == 'PUT' && path == 'user/world-history-settings') {
      final highWatermark = asInt(body['high_watermark']);
      final lowWatermark = asInt(body['low_watermark']);
      if (highWatermark < 20 ||
          highWatermark > 30 ||
          lowWatermark < 10 ||
          lowWatermark > 20) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      return _v1Ok(
        _state.updateV1WorldHistorySettings(
          highWatermark: highWatermark,
          lowWatermark: lowWatermark,
        ),
      );
    }

    if (method == 'DELETE' && path == 'user/world-history-settings') {
      return _v1Ok(_state.resetV1WorldHistorySettings());
    }

    if (method == 'GET' && path == 'user/profile') {
      return _v1Ok(_state.v1UserProfile(query['uid']));
    }

    if (method == 'GET' && path == 'user/origins') {
      return _v1Ok(_paged(_state.v1OriginSummaries(), query));
    }

    if (method == 'GET' && path == 'user/worlds') {
      return _v1Ok(_paged(_state.v1WorldSummaries(), query));
    }

    if (method == 'POST' && path == 'user/follow') {
      _state.v1FollowResult(followed: true);
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'POST' && path == 'user/unfollow') {
      _state.v1FollowResult(followed: false);
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'GET' && path == 'user/following') {
      return _v1Ok(_state.v1UserList(query, type: 'following'));
    }

    if (method == 'GET' && path == 'user/followers') {
      return _v1Ok(_state.v1UserList(query, type: 'followers'));
    }

    if (method == 'GET' && path == 'user/relations') {
      return _v1Ok(_paged(_state.v1Relations(), query));
    }

    if (method == 'POST' && path == 'users/relations/status') {
      final uids = body['uids'] is List
          ? body['uids'] as List
          : const <Object?>[];
      return _v1Ok({'relations': _state.v1RelationStatus(uids)});
    }

    if (method == 'GET' && path == 'origin/list') {
      return _v1Ok(_state.v1OriginContractList(query));
    }

    if (method == 'GET' && path == 'origin/feed') {
      final startScore = int.tryParse(query['start_score'] ?? '') ?? 0;
      final rn = int.tryParse(query['rn'] ?? '') ?? 10;
      if (startScore < 0 || rn < 1 || rn > 100) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      return _v1Ok(
        _state.v1OriginFeed(startScore: startScore, rn: rn, deviceId: deviceId),
      );
    }

    if (method == 'POST' && path == 'origin/feed/exposure') {
      final rawIds = body['origin_ids'];
      final originIds = rawIds is List
          ? rawIds
                .map((id) => '$id'.trim())
                .where((id) => id.isNotEmpty)
                .toSet()
          : const <String>{};
      if (originIds.isEmpty || originIds.length > 100) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      return _v1Ok({
        'recorded_count': _state.recordV1OriginFeedExposures(
          deviceId: deviceId,
          originIds: originIds,
        ),
      });
    }

    if (method == 'GET' && path == 'origin/hot_tags') {
      return _v1Ok(_state.v1OriginHotTags());
    }

    if (method == 'GET' && path == 'app/config') {
      return _v1Ok({'show_opening_sheet': false, 'apiTraceSamplingRate': 1.0});
    }

    if (method == 'GET' && path == 'origin/my_launch_preset_characters') {
      final originId = (query['origin_id'] ?? '').trim();
      final limit = int.tryParse(query['limit'] ?? '') ?? 0;
      if (originId.isEmpty || limit <= 0) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      if (!_state.canViewV1OriginDetail(originId)) {
        return _v1BusinessError(20101, 'ErrorOriginNotExist');
      }
      return _v1Ok(
        _state.v1OriginMyLaunchPresetCharacters(originId, limit: limit),
      );
    }

    if (method == 'GET' && path == 'origin/detail') {
      final originId = (query['origin_id'] ?? query['oid'] ?? '').trim();
      if (originId.isEmpty) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      if (!_state.canViewV1OriginDetail(originId)) {
        return _v1BusinessError(20101, 'ErrorOriginNotExist');
      }
      return _v1Ok(_state.v1OriginContractDetail(originId));
    }

    if (method == 'GET' && path == 'origin/map') {
      final originId = (query['origin_id'] ?? '').trim();
      final locationId = (query['location_id'] ?? '').trim();
      if (originId.isEmpty || locationId.isEmpty) {
        return _v1BusinessError(4004, 'origin_id and location_id required');
      }
      return _v1Ok(_state.v1OriginMap(originId, locationId));
    }

    if (method == 'GET' && path == 'origin/info') {
      return _v1Ok(
        _state.v1OriginContractInfo(query['origin_id'] ?? query['oid']),
      );
    }

    if (method == 'POST' && path == 'origin/create') {
      return _v1Ok(_state.createV1Origin(body));
    }

    if (method == 'POST' && path == 'origin/update') {
      return _v1Ok(_state.updateV1Origin(body));
    }

    if (method == 'POST' && path == 'origin/launch') {
      return _v1Ok({
        'world_id': _state.launchV1World(
          '${body['origin_id'] ?? body['oid'] ?? ''}',
          presetCharacterId: '${body['preset_character_id'] ?? ''}',
        ),
      });
    }

    if (method == 'GET' && path == 'origin/versionlist') {
      return _v1Ok(_state.v1OriginVersionList(query['oid']));
    }

    if (method == 'POST' && path == 'origin/publish') {
      return _v1Ok(_state.publishV1Origin('${body['oid'] ?? ''}'));
    }

    if (method == 'POST' && path == 'origin/del') {
      _state.deleteV1Origin('${body['oid'] ?? ''}');
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'GET' && path == 'world/list') {
      return _v1Ok(_state.v1WorldContractList(query));
    }

    if (method == 'GET' && path == 'world/summary/latest') {
      if ((query['origin_id'] ?? '').trim().isEmpty &&
          (query['world_id'] ?? '').trim().isEmpty) {
        return _v1BusinessError(4004, 'origin_id or world_id required');
      }
      return _v1Ok(_state.v1WorldSummaryLatest(query));
    }

    if (method == 'GET' && path == 'world/detail') {
      return _v1Ok(_state.v1WorldContractDetail(query['world_id']));
    }

    if (method == 'GET' && path == 'world/map') {
      final worldId = (query['world_id'] ?? '').trim();
      final locationId = (query['location_id'] ?? '').trim();
      if (worldId.isEmpty || locationId.isEmpty) {
        return _v1BusinessError(4004, 'world_id and location_id required');
      }
      return _v1Ok(_state.v1WorldMap(worldId, locationId));
    }

    if (method == 'GET' && path == 'world/info') {
      return _v1Ok(_state.v1WorldContractInfo(query['world_id']));
    }

    if (method == 'GET' && path == 'world/tick/list') {
      final worldId = (query['world_id'] ?? '').trim();
      if (worldId.isEmpty) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      if (!_state.hasV1World(worldId)) {
        return _v1BusinessError(20201, 'ErrorWorldNotExist');
      }
      return _v1Ok(_state.v1WorldTickList(worldId: worldId, query: query));
    }

    if (method == 'GET' && path == 'world/origin_progress') {
      return _v1Ok(
        _state.v1WorldOriginProgress(
          uid: query['uid'] ?? '',
          originId: query['origin_id'] ?? '',
        ),
      );
    }

    if (method == 'POST' && path == 'world/apply') {
      return _v1Ok(
        _state.applyToV1World(
          worldId: '${body['world_id'] ?? ''}',
          message: body['message']?.toString(),
        ),
      );
    }

    if (method == 'GET' && path == 'world/apply/list') {
      return _v1Ok(_state.v1WorldApplyList(query));
    }

    if (method == 'POST' && path == 'world/apply/review') {
      return _v1Ok(
        _state.reviewV1WorldApply(
          applyId: '${body['apply_id'] ?? ''}',
          action: '${body['action'] ?? ''}',
          reviewMsg: body['review_msg']?.toString(),
        ),
      );
    }

    if (method == 'POST' && path == 'world/join') {
      return _v1Ok(
        _state.joinV1World(
          worldId: '${body['world_id'] ?? ''}',
          presetCharacterId: body['preset_character_id']?.toString(),
          customRole: body['custom_role'] is Map
              ? Map<String, dynamic>.from(body['custom_role'] as Map)
              : null,
        ),
      );
    }

    if (method == 'POST' && path == 'world/tick') {
      await Future<void>.delayed(const Duration(seconds: 3));
      return _v1Ok(_state.tickV1World('${body['world_id'] ?? ''}'));
    }

    if (method == 'POST' &&
        (path == 'world/synclastorigin' ||
            path == 'world/close' ||
            path == 'world/delete' ||
            path == 'world/del')) {
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'GET' && path == 'gem/products') {
      return _v1Ok(_state.v1GemProducts());
    }

    if (method == 'GET' && path == 'membership/products') {
      // No mock store catalog: mirror the documented empty-list response.
      // Device/store configurations must come from the real endpoint.
      final provider = query['provider'];
      if (provider != 'apple' && provider != 'google') {
        return _ok(<String, dynamic>{
          'err_no': 4004,
          'err_msg': 'param invalid',
          'data': <String, dynamic>{},
        });
      }
      return _v1Ok(<String, dynamic>{'list': <Object>[]});
    }

    if (method == 'POST' &&
        (path == 'membership/purchase/report' ||
            path == 'membership/guest/prepare' ||
            path == 'membership/guest/purchase/report' ||
            path == 'membership/guest/purchase/check' ||
            path == 'membership/claim')) {
      // Mock cannot verify receipts or determine actual guest ownership.
      return _ok(<String, dynamic>{
        'err_no': 5000,
        'err_msg': 'membership store unavailable in mock',
        'data': null,
      });
    }

    if (method == 'GET' && path == 'gem/tasks') {
      return _v1Ok(_state.v1GemTasks());
    }

    if (method == 'GET' && path == 'gem/wallet') {
      return _v1Ok(_state.v1GemWallet());
    }

    if (method == 'GET' && path == 'gem/model/list') {
      return _v1Ok(_state.v1GemModels(query['world_id'] ?? ''));
    }

    if (method == 'POST' && path == 'gem/model/select') {
      return _v1Ok(_state.v1GemModelSelect(body));
    }

    if (method == 'GET' && path == 'gem/records') {
      return _v1Ok(
        _paged(
          _state.v1GemRecords(query['scene']),
          query,
          defaultSize: 10,
          maxSize: 100,
        ),
      );
    }

    if (method == 'POST' && path == 'gem/purchase/report') {
      return _v1Ok(_state.v1GemPurchaseReport(body));
    }

    if (method == 'POST' && path == 'gem/task/report') {
      return _v1Ok(_state.v1GemTaskReport(body));
    }

    if (method == 'POST' && path == 'gem/task/claim') {
      return _v1Ok(_state.v1GemTaskClaim(body));
    }

    if (method == 'GET' && path == 'message/unread') {
      return _v1Ok(_state.v1UnreadSummary());
    }

    if (method == 'GET' && path == 'message/notifications') {
      final block = query['block']?.trim();
      final items = _state.v1Notifications().where((item) {
        return block == null ||
            block.isEmpty ||
            item['notice_block']?.toString() == block;
      }).toList();
      return _v1Ok(_paged(items, query));
    }

    if (method == 'POST' && path == 'message/read') {
      _state.markV1NotificationsRead(
        block: body['block']?.toString(),
        notificationId: body['notification_id']?.toString(),
      );
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'GET' && path == 'messages/followers') {
      return _v1Ok(_paged(_state.v1FollowerMessages(), query));
    }

    if (method == 'GET' && path == 'direct_message/conversations') {
      final afterMessageId = query['after_message_id']?.trim();
      if (afterMessageId != null && afterMessageId.isNotEmpty) {
        return _v1Ok(_state.v1DmConversationDeltas(afterMessageId));
      }
      return _v1Ok(
        _paged(_state.v1DmConversations(), query, defaultSize: 20, maxSize: 100)
          ..['next_after_message_id'] = _state.v1DmConversationCursor(),
      );
    }

    if (method == 'GET' && path == 'direct_message/list') {
      return _v1Ok(
        _paged(
          _state.v1DmMessagesForPeer(query['peer_uid']),
          query,
          defaultSize: 20,
          maxSize: 100,
        ),
      );
    }

    if (method == 'POST' && path == 'direct_message/send') {
      return _v1Ok(_state.sendV1DirectMessage(body));
    }

    if (method == 'POST' && path == 'direct_message/read') {
      _state.markV1DirectMessagesRead(body['peer_uid']?.toString());
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'GET' && path == 'direct_message/unread') {
      return _v1Ok({'unread_cnt': _state.v1DirectMessageUnreadCount()});
    }

    if (method == 'POST' && path == 'direct_message/block') {
      _state.blockV1DirectMessagePeer(body['target_uid']?.toString());
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'POST' && path == 'direct_message/unblock') {
      _state.unblockV1DirectMessagePeer(body['target_uid']?.toString());
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'GET' && path == 'direct_message/blocks') {
      return _v1Ok(_paged(_state.v1DirectMessageBlocks(), query));
    }

    if (method == 'GET' && path == 'discuss/list') {
      return _v1Ok(_state.v1DiscussList(query));
    }

    if (method == 'GET' && path == 'discuss/replies') {
      return _v1Ok(_state.v1DiscussReplies(query));
    }

    if (method == 'POST' && path == 'discuss/post') {
      return _v1Ok(_state.addV1Discuss(body));
    }

    if (method == 'POST' && path == 'discuss/like') {
      _state.likeV1Discuss('${body['discuss_id'] ?? ''}');
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'POST' && path == 'discuss/unlike') {
      _state.unlikeV1Discuss('${body['discuss_id'] ?? ''}');
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'POST' && path == 'discuss/delete') {
      _state.deleteV1Discuss('${body['discuss_id'] ?? ''}');
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'POST' && path == 'report/create') {
      final targetType = '${body['target_type'] ?? ''}'.trim();
      final targetId = '${body['target_id'] ?? ''}'.trim();
      final content = '${body['content'] ?? ''}'.trim();
      const supportedTypes = {
        'origin',
        'world',
        'tick',
        'message',
        'discuss',
        'user',
      };
      if (!supportedTypes.contains(targetType)) {
        return _v1BusinessError(20801, 'ErrorReportTargetTypeInvalid');
      }
      if (targetId.isEmpty || content.isEmpty) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      if (content.length > 1000) {
        return _v1BusinessError(20802, 'ErrorReportContentTooLong');
      }
      return _v1Ok({
        'report_id': 'rpt_mock_${DateTime.now().microsecondsSinceEpoch}',
      });
    }

    if (method == 'POST' && path == 'feedback/create') {
      final content = '${body['content'] ?? ''}'.trim();
      if (content.isEmpty) {
        return _v1BusinessError(4004, 'ErrorParamInvalid');
      }
      if (content.length > 1000) {
        return _v1BusinessError(20901, 'ErrorFeedbackContentTooLong');
      }
      return _v1Ok({
        'feedback_id': 'fbk_mock_${DateTime.now().microsecondsSinceEpoch}',
      });
    }

    if (method == 'GET' && path == 'search/suggest') {
      if (kDebugMode) {
        debugPrint(
          '[LocalMockGenesisTransport] GET /api/v1/search/suggest $query',
        );
      }
      return _v1Ok(_state.v1SearchSuggest(query));
    }

    if (method == 'GET' && path == 'home') {
      return _v1Ok(_state.v1Home());
    }

    if (method == 'GET' && path == 'home/following') {
      return _v1Ok(
        _paged(_state.v1FollowingFeed(), query)..['has_more'] = false,
      );
    }

    if (method == 'POST' && path == 'upload/image') {
      final now = DateTime.now();
      final y = now.year.toString().padLeft(4, '0');
      final m = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final objectKey = 'uploads/$y$m$d/mock_${now.microsecondsSinceEpoch}.png';
      return _v1Ok(_mockUploadedImageObject(objectKey));
    }

    if (method == 'POST' && path == 'common/upload') {
      return _v1Ok({
        'file_id': 'file_mock_${DateTime.now().millisecondsSinceEpoch}',
        'biz_type': 'mock',
        'file_url': 'https://mock.local/upload/mock.png',
        'width': 120,
        'height': 120,
        'file_size': 1024,
      });
    }

    if (method == 'POST' && path == 'common/drafts') {
      return _v1Ok(_state.saveV1Draft(body));
    }

    if (method == 'GET' && path == 'common/drafts') {
      return _v1Ok(_state.readV1Draft(query['draft_type']));
    }

    if (method == 'POST' && path == 'common/drafts/del') {
      _state.deleteV1Draft('${body['draft_id'] ?? ''}');
      return _v1Ok(<String, dynamic>{});
    }

    if (method == 'POST' && path == 'common/devices/register') {
      return _v1Ok(<String, dynamic>{});
    }

    return _error(404, 'mock v1 route not found: $method /api/v1/$path');
  }

  TransportResponse _ok(Map<String, dynamic> data) {
    return TransportResponse(
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(data),
    );
  }

  TransportResponse _error(int code, String message) {
    return TransportResponse(
      statusCode: code,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'error': message}),
    );
  }

  TransportResponse _v1Ok(Object? data) {
    return _ok({'err_no': 0, 'err_msg': 'succ', 'data': data});
  }

  TransportResponse _v1BusinessError(int code, String message) {
    return TransportResponse(
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'err_no': code, 'err_msg': message, 'data': {}}),
    );
  }

  Map<String, dynamic> _paged(
    List<Map<String, dynamic>> items,
    Map<String, String> query, {
    int? defaultSize,
    int? maxSize,
  }) {
    final parsedPage = int.tryParse(query['pn'] ?? '') ?? 1;
    final parsedSize =
        int.tryParse(query['rn'] ?? '') ?? defaultSize ?? items.length;
    final page = parsedPage < 1 ? 1 : parsedPage;
    final positiveSize = parsedSize < 1
        ? defaultSize ?? items.length
        : parsedSize;
    final size = maxSize == null || positiveSize <= maxSize
        ? positiveSize
        : maxSize;
    final rawStart = (page - 1) * size;
    final start = rawStart > items.length ? items.length : rawStart;
    final rawEnd = start + size;
    final end = rawEnd > items.length ? items.length : rawEnd;
    return {
      'list': items.sublist(start, end).map(_deepCopyMap).toList(),
      'total': items.length,
      'pn': page,
      'rn': size,
    };
  }

  Map<String, dynamic> _decodeBody(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return const <String, dynamic>{};
    final decodedText = utf8.decode(bytes, allowMalformed: true);
    Object? decoded;
    try {
      decoded = jsonDecode(decodedText);
    } catch (_) {
      if (decodedText.contains('Content-Disposition: form-data')) {
        return _decodeMultipartFields(decodedText);
      }
      return const <String, dynamic>{};
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry('$k', v));
    }
    return const <String, dynamic>{};
  }

  String _requestDeviceId(TransportRequest request) {
    for (final entry in request.headers.entries) {
      final name = entry.key.toLowerCase();
      if (name == 'x-device-id' || name == 'device-id') {
        final value = entry.value.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return 'local-mock-device';
  }

  bool _requestHasAuthorization(TransportRequest request) {
    for (final entry in request.headers.entries) {
      if (entry.key.toLowerCase() != 'authorization') continue;
      return entry.value.trim().isNotEmpty;
    }
    return false;
  }

  Map<String, dynamic> _decodeMultipartFields(String input) {
    final fields = <String, dynamic>{};
    final pattern = RegExp(
      r'name="([^"]+)"(?:\r?\n)+\r?\n([\s\S]*?)(?=\r?\n--)',
      multiLine: true,
    );
    for (final match in pattern.allMatches(input)) {
      final name = match.group(1)?.trim() ?? '';
      if (name.isEmpty) continue;
      fields[name] = match.group(2)?.trim() ?? '';
    }
    return fields;
  }
}

class _MockState {
  bool _authenticated = false;

  bool get isAuthenticated => _authenticated;

  final Map<String, dynamic> me = _deepCopyMap(kMockMeProfile);

  final List<Map<String, dynamic>> origins = kMockOrigins
      .map((item) => _deepCopyMap(item))
      .toList(growable: true);

  final Map<String, Map<String, dynamic>> _worlds = kMockWorlds.map(
    (key, value) => MapEntry(key, _deepCopyMap(value)),
  );

  final Map<String, int> _tickByWorld = Map<String, int>.from(kMockTickByWorld);

  final Map<String, List<Map<String, dynamic>>> _messagesByPoint =
      kMockMessagesByPoint.map(
        (key, value) =>
            MapEntry(key, value.map((item) => _deepCopyMap(item)).toList()),
      );

  final Map<String, dynamic> _v1User = _deepCopyMap(kMockV1User);
  final Map<String, dynamic> _v1PeerUser = _deepCopyMap(kMockV1PeerUser);
  late final List<Map<String, dynamic>> _v1DirectMessagePeers =
      _mockDirectMessagePeers();
  final List<Map<String, dynamic>> _v1Origins = _expandMockV1Origins()
      .map((item) => _deepCopyMap(item))
      .toList(growable: true);
  final List<Map<String, dynamic>> _v1Worlds = _expandMockV1Worlds()
      .map((item) => _deepCopyMap(item))
      .toList(growable: true);
  final Map<String, Map<String, int>> _v1PresetLaunchHistoryByOrigin =
      <String, Map<String, int>>{};
  final Map<String, Set<String>> _v1OriginFeedExposuresByDevice =
      <String, Set<String>>{};
  final Map<String, List<Map<String, dynamic>>> _v1TicksByWorld =
      <String, List<Map<String, dynamic>>>{};
  final List<Map<String, dynamic>> _v1WorldApplies = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _v1SearchUsers = _expandMockV1SearchUsers()
      .map((item) => _deepCopyMap(item))
      .toList(growable: true);
  late final Map<String, List<Map<String, dynamic>>> _v1DmMessagesByPeer =
      _mockDirectMessageMessagesByPeer();
  final Set<String> _v1BlockedDirectMessagePeers = <String>{};
  final Set<String> _v1BlockedUsers = <String>{'u_mock_peer'};
  final Map<String, int> _v1GrantedGemCentByPurchaseToken = <String, int>{};
  final Map<String, String> _v1SelectedGemModelByWorldId = <String, String>{};
  String _v1SelectedGemModelCode = 'top_pick_v3';
  final Map<String, String> _v1GemTaskStatuses = <String, String>{
    'create_first_worldo': 'in_progress',
    'launch_first_world': 'in_progress',
    'daily_checkin': 'in_progress',
    'send_message': 'in_progress',
    'discord_follow': 'in_progress',
  };
  int _v1GemBalanceCent = 43000;
  int _v1DirectMessageUnreadCount = 1;
  int _v1WorldHistoryHighWatermark = 25;
  int _v1WorldHistoryLowWatermark = 15;
  bool _v1WorldHistoryUsesDefault = true;
  String _v1DmConversationCursor = 'dm_sync_1';
  bool _v1DmConversationDeltaSent = false;
  final List<Map<String, dynamic>> _v1DiscussPosts = kMockV1DiscussPosts
      .map((item) => _deepCopyMap(item))
      .toList(growable: true);
  final List<Map<String, dynamic>> _v1DiscussReplies = kMockV1DiscussReplies
      .map((item) => _deepCopyMap(item))
      .toList(growable: true);
  final List<Map<String, dynamic>> _v1Notifications = kMockV1Notifications
      .map((item) => _deepCopyMap(item))
      .toList(growable: true);
  final Map<String, Map<String, dynamic>> _v1Drafts =
      <String, Map<String, dynamic>>{};
  int _v1WorldApplySeq = 0;
  final List<Map<String, dynamic>> _chatroomMessages = <Map<String, dynamic>>[];
  final Map<String, bool> _chatroomWorldLocks = <String, bool>{};
  final Map<String, int> _chatroomLocationMessageSeq = <String, int>{};
  int _chatroomMessageSeq = 1000;
  int _chatroomRoundSeq = 100;

  _MockState() {
    _ensureV1DiscussCoverage();
    _ensureChatroomMessages();
  }

  Map<String, dynamic> get _v1Origin => _v1Origins.first;

  Map<String, dynamic> get _v1World => _v1Worlds.first;

  Map<String, dynamic> v1WorldHistorySettings() {
    return <String, dynamic>{
      'high_watermark': _v1WorldHistoryHighWatermark,
      'low_watermark': _v1WorldHistoryLowWatermark,
      'stored_high_watermark': _v1WorldHistoryUsesDefault
          ? 0
          : _v1WorldHistoryHighWatermark,
      'stored_low_watermark': _v1WorldHistoryUsesDefault
          ? 0
          : _v1WorldHistoryLowWatermark,
      'source': _v1WorldHistoryUsesDefault ? 'default' : 'stored',
      'degraded': false,
    };
  }

  Map<String, dynamic> updateV1WorldHistorySettings({
    required int highWatermark,
    required int lowWatermark,
  }) {
    _v1WorldHistoryHighWatermark = highWatermark;
    _v1WorldHistoryLowWatermark = lowWatermark;
    _v1WorldHistoryUsesDefault = false;
    return v1WorldHistorySettings();
  }

  Map<String, dynamic> resetV1WorldHistorySettings() {
    _v1WorldHistoryHighWatermark = 25;
    _v1WorldHistoryLowWatermark = 15;
    _v1WorldHistoryUsesDefault = true;
    return v1WorldHistorySettings();
  }

  Map<String, dynamic> _v1UserPayload(Map<String, dynamic> user) {
    final copy = _deepCopyMap(user);
    copy['avatar'] = _mockImageObject(copy['avatar'] ?? copy['avatar_url']);
    return copy;
  }

  Map<String, dynamic> _v1OriginPayload(Map<String, dynamic> origin) {
    final copy = _deepCopyMap(origin);
    copy['cover'] = _mockImageObject(copy['cover']);
    return copy;
  }

  void markAuthenticated() {
    _authenticated = true;
  }

  void markLoggedOut() {
    _authenticated = false;
  }

  Map<String, dynamic> googleUserPayload() {
    return {
      'id': me['id'],
      'display_name': me['display_name'],
      'avatar_url': me['avatar_url'],
      'user_code': me['user_code'],
    };
  }

  Map<String, dynamic>? originByWorldview(String worldviewId) {
    for (final origin in origins) {
      if ('${origin['worldviewId']}' == worldviewId) return origin;
    }
    return null;
  }

  Map<String, dynamic> launchWorld({
    required String userId,
    required String worldviewId,
    required String worldName,
  }) {
    final seq = _worlds.length + 1;
    final wid = 'wid_mock_${seq.toString().padLeft(3, '0')}';
    _worlds[wid] = {
      'wid': wid,
      'display_wid_str': 'W_MOCK_${seq.toString().padLeft(3, '0')}',
      'world_name': worldName,
      'worldview_id': worldviewId,
      'owner_user_id': userId,
    };
    _tickByWorld[wid] = 0;
    return {'wid': wid, 'wid_str': _worlds[wid]!['display_wid_str']};
  }

  Map<String, dynamic> createOrigin(Map<String, dynamic> body) {
    final seq = origins.length + 1000;
    final oid = seq;
    final worldviewId = 'wv_mock_${seq.toString().padLeft(4, '0')}';
    final now = DateTime.now().toUtc().toIso8601String();
    final detail = <String, dynamic>{
      'Oid': oid,
      'worldviewId': worldviewId,
      'Oname': '${body['title'] ?? 'Untitled Origin'}',
      'Odescription': '${body['description'] ?? ''}',
      'Oworld_view_image': '${body['cover_image_url'] ?? ''}',
      'Omap_image': '',
      'Ocopycount': 0,
      'Oconnectcount': 0,
      'Oupdated_time': now,
      'Ocharacters': (body['npcs'] is List) ? body['npcs'] : const <dynamic>[],
      'Omap_points': (body['locations'] is List)
          ? (body['locations'] as List)
                .map(
                  (item) => {
                    'id': '${item is Map ? item['name'] ?? '' : ''}',
                    'name': '${item is Map ? item['name'] ?? '' : ''}',
                  },
                )
                .toList(growable: false)
          : const <dynamic>[],
      'Oevents': (body['events'] is List) ? body['events'] : const <dynamic>[],
    };
    origins.insert(0, detail);
    return {'worldview_id': worldviewId, 'detail': detail};
  }

  Map<String, dynamic>? worldByWid(String wid) => _worlds[wid];

  Map<String, dynamic>? tickByWid(String wid) {
    final world = _worlds[wid];
    if (world == null) return null;
    final tick = _tickByWorld[wid] ?? 0;
    return {
      'tick_index': tick,
      'current_day': 1,
      'current_time': '18:00',
      'current_worldview_id': world['worldview_id'],
      'current_worldview_name': world['world_name'],
      'global_narrative': 'The city adjusts to your last choice at tick $tick.',
      'location_chat_user_send_count': 42,
      'world_mutation': {'busy': false},
      'player_slot_last_location': {'player1': 'loc_hub'},
      'scenes': [
        {
          'location_id': 'loc_hub',
          'location_name': 'Central Hub',
          'character_ids': ['c_1'],
        },
        {
          'location_id': 'loc_gate',
          'location_name': 'Rail Gate',
          'character_ids': ['c_2'],
        },
      ],
      'tick_history': [
        {
          'tick_index': tick,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'global_narrative': 'Tick $tick completed.',
        },
      ],
    };
  }

  Map<String, dynamic>? progressTick(String wid) {
    if (!_worlds.containsKey(wid)) return null;
    _tickByWorld[wid] = (_tickByWorld[wid] ?? 0) + 1;
    return tickByWid(wid);
  }

  Map<String, dynamic>? worldMapByWid(String wid) {
    if (!_worlds.containsKey(wid)) return null;
    final positions = kMockWorldMapPositions
        .map((item) => _deepCopyMap(item))
        .toList(growable: false);
    return {'positions': positions, 'merged_positions': positions};
  }

  Map<String, dynamic>? charactersByWid(String wid) {
    if (!_worlds.containsKey(wid)) return null;
    return {
      'my_player_slot': 'player1',
      'characters_full': kMockCharactersFull
          .map((item) => _deepCopyMap(item))
          .toList(growable: false),
      'players': kMockPlayers
          .map((item) => _deepCopyMap(item))
          .toList(growable: false),
    };
  }

  List<Map<String, dynamic>> messagesForPoint(
    String pointId, {
    required int limit,
  }) {
    final list = _messagesByPoint[pointId] ?? const <Map<String, dynamic>>[];
    final newestFirst = list.reversed.toList(growable: false);
    return newestFirst.take(limit).map((item) => _deepCopyMap(item)).toList();
  }

  Map<String, dynamic> enqueuePointMessage({
    required String wid,
    required String pointId,
    required String locationId,
    required String userId,
    required String text,
  }) {
    final queue = _messagesByPoint.putIfAbsent(
      pointId,
      () => <Map<String, dynamic>>[],
    );
    final nextSeq = queue.isEmpty
        ? 1
        : (queue.last['chat_seq'] as int? ?? 0) + 1;
    final msg = {
      'id': 'm_${DateTime.now().millisecondsSinceEpoch}',
      'chat_seq': nextSeq,
      'role': 'user',
      'api_user_id': userId,
      'player_id': 'player1',
      'speaker': '${me['display_name']}',
      'content': text,
      'location_id': locationId,
      'wid': wid,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    queue.add(msg);
    _chatroomMessages.add(
      _newChatroomMessage(
        worldId: wid,
        locationId: locationId,
        conversationRoundId: ++_chatroomRoundSeq,
        roundOrder: 1,
        senderType: 'user',
        senderId: 'player1',
        senderName: '${me['display_name']}',
        userId: userId,
        content: text,
      ),
    );
    return _deepCopyMap(msg);
  }

  Map<String, dynamic> chatroomWorldMessages(String worldId) {
    final messages = _chatroomMessagesForWorld(worldId);
    messages.sort((a, b) {
      final roundCompare = ((b['conversation_round_id'] as int?) ?? 0)
          .compareTo((a['conversation_round_id'] as int?) ?? 0);
      if (roundCompare != 0) return roundCompare;
      return ((a['round_order'] as int?) ?? 0).compareTo(
        (b['round_order'] as int?) ?? 0,
      );
    });
    final latest = messages.take(50).toList(growable: false);
    final byLocation = <String, List<Map<String, dynamic>>>{};
    for (final message in latest) {
      final locationId = '${message['location_id']}';
      byLocation
          .putIfAbsent(locationId, () => <Map<String, dynamic>>[])
          .add(_chatroomResponseMessage(message));
    }
    return {
      'locations': [
        for (final entry in byLocation.entries)
          {'location_id': entry.key, 'messages': entry.value},
      ],
    };
  }

  Map<String, dynamic> chatroomUserLocations(String worldId) {
    final resolvedWorldId = _resolveChatroomWorldId(worldId);
    final playerLocations = <String, String>{};
    for (final message in _chatroomMessagesForWorld(resolvedWorldId)) {
      if (message['sender_type'] != 'user') continue;
      final locationId = asString(message['location_id']);
      final userId = asString(message['user_id'], fallback: asString(me['id']));
      if (locationId.isEmpty || userId.isEmpty) continue;
      playerLocations[userId] = locationId;
    }
    final byLocation = <String, List<Map<String, dynamic>>>{};
    for (final character in kMockV1Characters) {
      final payload = _contractCharacter(character);
      final playerUid = asString(payload['player_uid']);
      if (playerUid.isEmpty) continue;
      final locationId =
          playerLocations[playerUid] ?? asString(payload['location_id']);
      if (locationId.isEmpty) continue;
      payload['location_id'] = locationId;
      if (playerUid == asString(me['id'])) {
        payload['player_username'] = asString(me['display_name']);
      }
      byLocation.putIfAbsent(locationId, () => <Map<String, dynamic>>[]).add({
        'user_id': playerUid,
        'user_name': asString(
          payload['player_username'],
          fallback: asString(payload['name'], fallback: playerUid),
        ),
        'avatar': asImageUrl(payload['avatar']),
      });
    }
    return {
      'world_id': resolvedWorldId,
      'locations': [
        for (final entry in byLocation.entries)
          {'location_id': entry.key, 'users': entry.value},
      ],
    };
  }

  Map<String, dynamic> chatroomHistoryMessages({
    required String worldId,
    required String locationId,
    int? since,
    int? limit,
  }) {
    final size = limit == null || limit <= 0 ? 20 : limit;
    final messages =
        _chatroomMessagesForWorld(worldId)
            .where((message) {
              final sameLocation =
                  locationId.trim().isEmpty ||
                  message['location_id'] == locationId;
              final id =
                  (message['location_message_id'] as int?) ??
                  (message['message_id'] as int?) ??
                  0;
              final beforeCursor = since == null || since <= 0 || id < since;
              return sameLocation && beforeCursor;
            })
            .toList(growable: false)
          ..sort((a, b) {
            final bId =
                (b['location_message_id'] as int?) ??
                (b['message_id'] as int?) ??
                0;
            final aId =
                (a['location_message_id'] as int?) ??
                (a['message_id'] as int?) ??
                0;
            return bId.compareTo(aId);
          });
    final page = messages.take(size).map(_chatroomResponseMessage).toList();
    final newestId = _chatroomMessagesForWorld(worldId).fold<int>(0, (
      maxId,
      message,
    ) {
      final id = (message['message_id'] as int?) ?? 0;
      return id > maxId ? id : maxId;
    });
    return {
      'messages': page,
      'has_more': messages.length > page.length,
      'newest_message_id': newestId,
    };
  }

  Map<String, dynamic> chatroomV2HistoryMessages({
    required String worldId,
    required String locationId,
    int? since,
    int? limit,
    int startConversationRoundId = 0,
    int endConversationRoundId = 0,
  }) {
    final resolvedLocationId = locationId.trim();
    final size = limit == null || limit <= 0 ? 20 : limit.clamp(1, 100).toInt();
    final locationMessages = _chatroomMessagesForWorld(worldId)
        .where(
          (message) =>
              message['location_id'] == resolvedLocationId &&
              asInt(message['location_message_id']) > 0,
        )
        .toList(growable: false);
    final newestId = locationMessages.fold<int>(0, (maxId, message) {
      final id = asInt(message['location_message_id']);
      return id > maxId ? id : maxId;
    });
    final messages =
        locationMessages
            .where((message) {
              final round = asInt(message['conversation_round_id']);
              if (startConversationRoundId > 0 &&
                  (round < startConversationRoundId ||
                      round > endConversationRoundId)) {
                return false;
              }
              final id = asInt(message['location_message_id']);
              return since == null || since <= 0 || id < since;
            })
            .toList(growable: false)
          ..sort(
            (a, b) => asInt(
              b['location_message_id'],
            ).compareTo(asInt(a['location_message_id'])),
          );
    final page = messages
        .take(size)
        .map(_chatroomV2ResponseMessage)
        .toList(growable: false);
    return <String, dynamic>{
      'messages': page,
      'has_more': messages.length > page.length,
      'newest_message_id': newestId,
    };
  }

  // Local transport fixtures model persistence only; production permission
  // checks remain server-owned and are covered by the HTTP contract tests.
  final Set<String> _deletedChatroomLlmMessages = <String>{};

  Map<String, dynamic> mutateChatroomLlmMessages({
    required String worldId,
    required String locationId,
    required Map<String, dynamic> body,
  }) {
    Map<String, dynamic> failure(int code) => {
      'err_no': code,
      'err_msg': 'Batch was not committed',
      'data': false,
    };
    final round = body['conversation_round_id'];
    final operations = body['operations'];
    if (round is! int ||
        round <= 0 ||
        operations is! List ||
        operations.isEmpty ||
        operations.length > 100) {
      return failure(1001);
    }
    _ensureChatroomMessages();
    final ids = <int>{};
    final targets = <Map<String, dynamic>>[];
    for (final operation in operations) {
      if (operation is! Map ||
          !const {'edit', 'delete'}.contains(operation['action']) ||
          operation['global_message_id'] is! int ||
          operation['global_message_id'] <= 0 ||
          !ids.add(operation['global_message_id'] as int)) {
        return failure(1001);
      }
      if (operation['action'] == 'edit' &&
          (operation['content'] is! String ||
              (operation['content'] as String).trim().isEmpty)) {
        return failure(1009);
      }
      if (operation['action'] == 'delete' && operation.containsKey('content')) {
        return failure(1001);
      }
      final id = operation['global_message_id'];
      if (_deletedChatroomLlmMessages.contains('$worldId::$locationId::$id')) {
        return failure(2013);
      }
      final target = _chatroomMessages
          .where(
            (m) =>
                m['world_id'] == worldId &&
                m['location_id'] == locationId &&
                m['global_message_id'] == id,
          )
          .firstOrNull;
      if (target == null ||
          target['conversation_round_id'] != round ||
          !const {'character', 'narrator'}.contains(target['sender_type']) ||
          (asString(target['stream_type']).isNotEmpty &&
              target['stream_type'] != 'end') ||
          asInt(target['location_message_id']) <= 0) {
        return failure(2011);
      }
      targets.add(target);
    }
    // All validation precedes the synchronous commit: a failed batch changes nothing.
    final deletedIds = <int>{};
    final deletedCursors = <int>[];
    for (var i = 0; i < operations.length; i++) {
      final operation = operations[i] as Map;
      final target = targets[i];
      if (operation['action'] == 'edit') {
        target['content'] = operation['content'];
        target['status'] = 20;
        if (target['v2_payload'] is Map) {
          target['v2_payload'] = {
            ...asJsonMap(target['v2_payload']),
            'content': operation['content'],
          };
        }
      } else {
        deletedIds.add(target['global_message_id'] as int);
        deletedCursors.add(target['location_message_id'] as int);
        _deletedChatroomLlmMessages.add(
          '$worldId::$locationId::${target['global_message_id']}',
        );
      }
    }
    _chatroomMessages.removeWhere(
      (m) =>
          m['world_id'] == worldId &&
          m['location_id'] == locationId &&
          deletedIds.contains(m['global_message_id']),
    );
    var start = round;
    var end = round;
    var newest = 0;
    for (final message in _chatroomMessages.where(
      (m) => m['world_id'] == worldId && m['location_id'] == locationId,
    )) {
      final old = asInt(message['location_message_id']);
      final cursor = old - deletedCursors.where((id) => id < old).length;
      if (cursor != old) {
        message['location_message_id'] = cursor;
        final affectedRound = asInt(message['conversation_round_id']);
        if (affectedRound > end) end = affectedRound;
        if (affectedRound > 0 && affectedRound < start) start = affectedRound;
      }
      if (cursor > newest) newest = cursor;
    }
    _chatroomLocationMessageSeq['$worldId::$locationId'] = newest;
    return {
      'err_no': 0,
      'err_msg': 'succ',
      'data': {
        'start_conversation_round_id': start,
        'end_conversation_round_id': end,
        'newest_message_id': newest,
      },
    };
  }

  void seedChatroomV2TickMessage({
    required String worldId,
    required String locationId,
  }) {
    final resolvedWorldId = _resolveChatroomWorldId(worldId);
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty) return;
    final alreadySeeded = _chatroomMessages.any(
      (message) =>
          message['world_id'] == resolvedWorldId &&
          message['location_id'] == resolvedLocationId &&
          message['type'] == 'tick' &&
          message['v2_payload'] is Map,
    );
    if (alreadySeeded) return;
    _chatroomMessages.add(
      _newChatroomMessage(
        worldId: resolvedWorldId,
        locationId: resolvedLocationId,
        conversationRoundId: ++_chatroomRoundSeq,
        roundOrder: 1,
        senderType: 'tick',
        senderId: 'tick',
        senderName: 'SubTick',
        userId: '',
        content: 'The mock timeline advanced.',
        tickNo: 4,
        subTickNo: 1,
        businessType: 'tick',
        v2Payload: <String, Object?>{
          'current_time': 'Day 2, 10:00',
          'tick_no': 4,
          'sub_tick_no': 1,
          'global': 'The mock timeline advanced.',
          'story_events': <Map<String, Object?>>[
            <String, Object?>{
              'location_id': resolvedLocationId,
              'timestamp': 'Day 2, 10:00',
              'visibility': 'public',
              'visible_to': null,
              'text': 'The mock timeline advanced.',
              'clue': '',
            },
          ],
          'characters_moved': const <Map<String, Object?>>[],
        },
      ),
    );
  }

  void seedChatroomTimelineMessages({
    required String worldId,
    required String locationId,
  }) {
    final resolvedWorldId = _resolveChatroomWorldId(worldId);
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty) return;
    final alreadySeeded = _chatroomMessages.any(
      (message) =>
          message['world_id'] == resolvedWorldId &&
          message['location_id'] == resolvedLocationId &&
          message['sender_type'] == chatroomUserEnterLocationSenderType,
    );
    if (alreadySeeded) return;

    final roundId = ++_chatroomRoundSeq;
    final payloads = <ChatroomTimelinePayload>[
      ChatroomUserEnterLocationPayload(
        charId: 'c_mock_iris',
        toLocationId: resolvedLocationId,
        text: 'Iris Vale entered the location.',
      ),
      ChatroomStoryEventsPayload(
        locationId: resolvedLocationId,
        locationName: 'Mock Timeline Location',
        paragraphs: const [
          ChatroomStoryEventParagraph(
            timestamp: 'Day 2, 10:15',
            visibility: 'public',
            visibleTo: <String>[],
            text: 'The mock timeline advanced.',
            clue: '',
          ),
        ],
      ),
      ChatroomCharactersMovedPayload(
        movements: [
          ChatroomCharacterMovement(
            charId: 'c_mock_iris',
            toLocationId: resolvedLocationId,
          ),
        ],
      ),
    ];
    for (var index = 0; index < payloads.length; index += 1) {
      final payload = payloads[index];
      final content = switch (payload) {
        ChatroomUserEnterLocationPayload event => event.text,
        ChatroomStoryEventsPayload event when event.paragraphs.length == 1 =>
          jsonEncode(<String, Object?>{
            'location_id': event.locationId,
            ...event.paragraphs.single.toJson(),
          }),
        _ => encodeChatroomTimelinePayload(payload),
      };
      _chatroomMessages.add(
        _newChatroomMessage(
          worldId: resolvedWorldId,
          locationId: resolvedLocationId,
          conversationRoundId: roundId,
          roundOrder: index + 1,
          senderType: payload.senderType,
          senderId: payload is ChatroomUserEnterLocationPayload
              ? payload.charId
              : 'sub_tick',
          senderName: payload is ChatroomUserEnterLocationPayload
              ? 'Iris Vale'
              : 'sub_tick',
          userId: payload is ChatroomUserEnterLocationPayload
              ? 'u_mock_iris'
              : '',
          content: content,
          messageType: payload is ChatroomUserEnterLocationPayload
              ? 'text'
              : '',
          tickNo: 4,
          subTickNo: 1,
          locationMessageId: payload is ChatroomUserEnterLocationPayload
              ? null
              : 0,
        ),
      );
    }
  }

  Map<String, dynamic> lockChatroomWorld(String worldId) {
    final resolved = _resolveChatroomWorldId(worldId);
    _chatroomWorldLocks[resolved] = true;
    return {'locked': true};
  }

  Map<String, dynamic> unlockChatroomWorld(String worldId) {
    final resolved = _resolveChatroomWorldId(worldId);
    _chatroomWorldLocks[resolved] = false;
    return {'unlocked': true};
  }

  Map<String, dynamic> chatroomTickLockStatus(String worldId) {
    final resolved = _resolveChatroomWorldId(worldId);
    return {'is_locked': _chatroomWorldLocks[resolved] ?? false};
  }

  Map<String, dynamic> chatroomTickProgress(String worldId) {
    final resolved = _resolveChatroomWorldId(worldId);
    final locked = _chatroomWorldLocks[resolved] ?? false;
    return {
      'progress': locked ? 0 : 1,
      'pending_messages': locked ? 1 : 0,
      'active_llm_calls': locked ? 1 : 0,
    };
  }

  Map<String, dynamic> writeChatroomNarrator(Map<String, dynamic> body) {
    final worldId = _resolveChatroomWorldId('${body['world_id'] ?? ''}');
    final groups = body['location_groups'] is List
        ? body['location_groups'] as List
        : const <Object?>[];
    var firstMessageId = 0;
    for (final rawGroup in groups) {
      if (rawGroup is! Map) continue;
      final group = asJsonMap(rawGroup);
      final locationId = asString(group['location_id'], fallback: 'loc_hub');
      final dialogues = group['initial_dialogue'] is List
          ? group['initial_dialogue'] as List
          : const <Object?>[];
      if (dialogues.isEmpty) {
        final message = _newChatroomMessage(
          worldId: worldId,
          locationId: locationId,
          conversationRoundId: ++_chatroomRoundSeq,
          roundOrder: 1,
          senderType: 'narrator',
          senderId: 'nar',
          senderName: '旁白',
          userId: '',
          content: asString(group['location_summary']),
        );
        _chatroomMessages.add(message);
        firstMessageId = firstMessageId == 0
            ? message['message_id'] as int
            : firstMessageId;
        continue;
      }
      final roundId = ++_chatroomRoundSeq;
      var order = 1;
      for (final rawLine in dialogues) {
        if (rawLine is! Map) continue;
        final line = asJsonMap(rawLine);
        final senderId = asString(line['char_id']);
        final normalizedSenderId = senderId.trim().toLowerCase();
        final message = _newChatroomMessage(
          worldId: worldId,
          locationId: locationId,
          conversationRoundId: roundId,
          roundOrder: order++,
          senderType: 'narrator',
          senderId: senderId,
          senderName: asString(line['char_name'], fallback: '旁白'),
          userId: '',
          content: asString(line['content']),
          messageType:
              normalizedSenderId == 'nar_pic' || normalizedSenderId == 'image'
              ? 'image'
              : 'text',
        );
        _chatroomMessages.add(message);
        firstMessageId = firstMessageId == 0
            ? message['message_id'] as int
            : firstMessageId;
      }
    }
    return {
      'message_id': firstMessageId == 0
          ? ++_chatroomMessageSeq
          : firstMessageId,
    };
  }

  List<Map<String, dynamic>> worldsForUser(String userId) {
    return _worlds.values
        .where((w) => '${w['owner_user_id']}' == userId)
        .map(
          (w) => {
            'world_instance_id': w['wid'],
            'display_wid_str': w['display_wid_str'],
            'worldview_id': w['worldview_id'],
            'world_name': w['world_name'],
            'owner_id': w['owner_user_id'],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'location_chat_user_send_count': 42,
          },
        )
        .map((item) => _deepCopyMap(item))
        .toList(growable: false);
  }

  Map<String, dynamic> search(String query) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) {
      return const {
        'origins': <Map<String, dynamic>>[],
        'worlds': <Map<String, dynamic>>[],
        'users': <Map<String, dynamic>>[],
      };
    }

    bool containsAny(String input) => input.toLowerCase().contains(keyword);

    final originMatches = origins
        .where((item) {
          final name = '${item['Oname'] ?? ''}';
          final subtitle = '${item['Osubtitle'] ?? ''}';
          final description = '${item['Odescription'] ?? ''}';
          return containsAny(name) ||
              containsAny(subtitle) ||
              containsAny(description);
        })
        .map((item) => _deepCopyMap(item))
        .toList(growable: false);

    final worldMatches = _worlds.values
        .where((item) {
          final name = '${item['world_name'] ?? ''}';
          final wid = '${item['wid'] ?? ''}';
          return containsAny(name) || containsAny(wid);
        })
        .map(
          (item) => {
            'world_instance_id': item['wid'],
            'wid': item['wid'],
            'world_name': item['world_name'],
            'snapshot_cover_url': '',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
        )
        .map((item) => _deepCopyMap(item))
        .toList(growable: false);

    final userMatches = <Map<String, dynamic>>[];
    final displayName = '${me['display_name'] ?? ''}';
    final uid = '${me['id'] ?? ''}';
    final userCode = '${me['user_code'] ?? ''}';
    if (containsAny(displayName) || containsAny(uid) || containsAny(userCode)) {
      userMatches.add(
        _deepCopyMap({
          'id': uid,
          'display_name': displayName,
          'avatar_url': '${me['avatar_url'] ?? ''}',
          'user_code': userCode,
        }),
      );
    }

    return {
      'origins': originMatches,
      'worlds': worldMatches,
      'users': userMatches,
    };
  }

  Map<String, dynamic> v1AuthPayload() {
    return v1UserInfo(null, viewerAuthenticated: true);
  }

  Map<String, dynamic> v1UserInfo(String? uid, {bool? viewerAuthenticated}) {
    final profile = v1UserProfile(
      uid,
      viewerAuthenticated: viewerAuthenticated ?? _authenticated,
    );
    return {'token': 'mock-v1-token', ...profile};
  }

  Map<String, dynamic> updateV1User(Map<String, dynamic> body) {
    for (final key in ['name', 'avatar', 'bio']) {
      final value = body[key];
      if (value != null) _v1User[key] = value;
    }
    return _v1UserPayload(_v1User);
  }

  Map<String, dynamic> v1GemProducts() {
    return {
      'list': const [
        {
          'product_id': 'gem_pack_500',
          'apple_product_id': 'com.worldo.gems.500',
          'google_product_id': 'worldo_gems_500',
          'base_gems_cent': 50000,
          'bonus_gems_cent': 5000,
          'price_currency_code': 'USD',
          'price_amount': 149,
          'can_purchase': true,
          'activity_type': 'first_purchase_bonus',
          'activity_ext': {
            'google_purchase_option_id': '500-gems-new',
            'google_offer_id': '500-gems-new-discount',
          },
        },
        {
          'product_id': 'gem_pack_1100',
          'apple_product_id': 'com.worldo.gems.1100',
          'google_product_id': 'worldo_gems_1100',
          'base_gems_cent': 110000,
          'bonus_gems_cent': 11000,
          'price_currency_code': 'USD',
          'price_amount': 590,
          'can_purchase': true,
          'activity_type': 'first_purchase_bonus',
          'activity_ext': {},
        },
        {
          'product_id': 'gem_pack_4400',
          'apple_product_id': 'com.worldo.gems.4400',
          'google_product_id': 'worldo_gems_4400',
          'base_gems_cent': 440000,
          'bonus_gems_cent': 44000,
          'price_currency_code': 'USD',
          'price_amount': 1990,
          'can_purchase': true,
          'activity_type': 'first_purchase_bonus',
          'activity_ext': {},
        },
        {
          'product_id': 'gem_pack_8800',
          'apple_product_id': 'com.worldo.gems.8800',
          'google_product_id': 'worldo_gems_8800',
          'base_gems_cent': 880000,
          'bonus_gems_cent': 88000,
          'price_currency_code': 'USD',
          'price_amount': 3890,
          'can_purchase': true,
          'activity_type': 'first_purchase_bonus',
          'activity_ext': {},
        },
        {
          'product_id': 'gem_pack_16500',
          'apple_product_id': 'com.worldo.gems.16500',
          'google_product_id': 'worldo_gems_16500',
          'base_gems_cent': 1650000,
          'bonus_gems_cent': 165000,
          'price_currency_code': 'USD',
          'price_amount': 6990,
          'can_purchase': true,
          'activity_type': 'first_purchase_bonus',
          'activity_ext': {},
        },
        {
          'product_id': 'gem_pack_55000',
          'apple_product_id': 'com.worldo.gems.55000',
          'google_product_id': 'worldo_gems_55000',
          'base_gems_cent': 5500000,
          'bonus_gems_cent': 550000,
          'price_currency_code': 'USD',
          'price_amount': 19990,
          'can_purchase': true,
          'activity_type': 'first_purchase_bonus',
          'activity_ext': {},
        },
      ],
    };
  }

  Map<String, dynamic> v1GemTasks() {
    return {
      'list': [
        {
          'group_code': 'starter',
          'group_title': 'Starter',
          'tasks': [
            {
              'task_code': 'create_first_worldo',
              'title': 'Create your first worldo',
              'description': 'Create an Origin and launch a world.',
              'reward_gems_cent': 5000,
              'reward_valid_days': 30,
              'cycle_type': 'once',
              'cycle_key': '',
              'progress': 0,
              'target_count': 1,
              'progress_text': '0/1',
              'status': _v1GemTaskStatuses['create_first_worldo'],
              'action_text': _v1GemTaskActionText(
                'create_first_worldo',
                'Create',
              ),
            },
            {
              'task_code': 'launch_first_world',
              'title': 'Launch your first world',
              'description': 'Launch a Worldo and start your story.',
              'reward_gems_cent': 5000,
              'reward_valid_days': 30,
              'cycle_type': 'once',
              'cycle_key': '',
              'progress': 0,
              'target_count': 1,
              'progress_text': '0/1',
              'status': _v1GemTaskStatuses['launch_first_world'],
              'action_text': _v1GemTaskActionText('launch_first_world', 'Go'),
            },
          ],
        },
        {
          'group_code': 'daily',
          'group_title': 'Daily',
          'tasks': [
            {
              'task_code': 'daily_checkin',
              'title': 'Daily check-in',
              'description': 'Check in every day to collect gems.',
              'reward_gems_cent': 2000,
              'reward_valid_days': 30,
              'cycle_type': 'daily',
              'cycle_key': 'today',
              'progress': 0,
              'target_count': 1,
              'progress_text': '0/1',
              'status': _v1GemTaskStatuses['daily_checkin'],
              'action_text': _v1GemTaskActionText('daily_checkin', 'Check in'),
            },
            {
              'task_code': 'send_message',
              'title': 'Send a message (0/3)',
              'description': 'Send messages in a location chat today.',
              'reward_gems_cent': 5000,
              'reward_valid_days': 30,
              'cycle_type': 'daily',
              'cycle_key': 'today',
              'progress': 0,
              'target_count': 3,
              'progress_text': '0/3',
              'status': _v1GemTaskStatuses['send_message'],
              'action_text': _v1GemTaskActionText('send_message', 'Go'),
            },
          ],
        },
        {
          'group_code': 'join_us',
          'group_title': 'Join us',
          'tasks': [
            {
              'task_code': 'discord_follow',
              'title': 'Discord',
              'description': 'Join our Discord community.',
              'reward_gems_cent': 2000,
              'reward_valid_days': 30,
              'cycle_type': 'once',
              'cycle_key': '',
              'progress': 0,
              'target_count': 1,
              'progress_text': '0/1',
              'status': _v1GemTaskStatuses['discord_follow'],
              'action_text': _v1GemTaskActionText('discord_follow', 'Follow'),
            },
          ],
        },
      ],
    };
  }

  Map<String, dynamic> v1GemWallet() {
    return {
      'wallet': {'balance_cent': _v1GemBalanceCent},
      'membership': {
        'membership_status': 0,
        'plan_code': '',
        'expires_at': null,
        'auto_renew': false,
        'blue_gems_cent': 0,
        'has_overlap': false,
      },
    };
  }

  Map<String, dynamic> v1GemModels(String worldId) {
    return {
      'selected_model_code':
          _v1SelectedGemModelByWorldId[worldId] ?? 'top_pick_v3',
      'list': const [
        {
          'group_code': 'recommended',
          'group_title': 'Recommended',
          'models': [
            {
              'model_code': 'top_pick_v3',
              'title': 'Top Pick V3',
              'tag': ['hot'],
              'estimated_next_message_gems_cent': 400,
              'estimated_next_tick_gems_cent': 400,
              'description':
                  'Most recommended. Best storytelling model with a balanced price.',
              'range_text': '4-320 gems (memory from 2K to 156K)',
            },
            {
              'model_code': 'top_pick_v3_5',
              'title': 'Top Pick V3.5',
              'tag': [],
              'estimated_next_message_gems_cent': 600,
              'estimated_next_tick_gems_cent': 600,
              'description':
                  'Most recommended. Best storytelling model with a balanced price.',
              'range_text': '6-480 gems (memory from 2K to 156K)',
            },
            {
              'model_code': 'luxury_selection_v4',
              'title': 'Luxury Selection V4.0',
              'tag': ['new'],
              'estimated_next_message_gems_cent': 800,
              'estimated_next_tick_gems_cent': 800,
              'description': 'Luxurious, pricey, but the best model of all.',
              'range_text': '8-640 gems (memory from 2K to 156K)',
            },
            {
              'model_code': 'sake_pro',
              'title': 'Sake Pro',
              'tag': ['new'],
              'estimated_next_message_gems_cent': 300,
              'estimated_next_tick_gems_cent': 300,
              'description':
                  'An experimental model exploring flexible storytelling.',
              'range_text': '3-160 gems (memory from 2K to 156K)',
            },
          ],
        },
      ],
    };
  }

  Map<String, dynamic> v1GemModelSelect(Map<String, dynamic> body) {
    final worldId = '${body['world_id'] ?? ''}'.trim();
    final modelCode = '${body['model_code'] ?? ''}'.trim();
    if (worldId.isNotEmpty && modelCode.isNotEmpty) {
      _v1SelectedGemModelByWorldId[worldId] = modelCode;
      _v1SelectedGemModelCode = modelCode;
    }
    return {'selected_model_code': modelCode};
  }

  String _v1GemTaskActionText(String taskCode, String inProgressText) {
    return switch (_v1GemTaskStatuses[taskCode]) {
      'claimable' => 'Claim',
      'claimed' => 'Claimed',
      _ => inProgressText,
    };
  }

  Map<String, dynamic> v1GemTaskReport(Map<String, dynamic> body) {
    final taskCode = '${body['task_code'] ?? ''}'.trim();
    switch (taskCode) {
      case 'daily_checkin':
        if (_v1GemTaskStatuses[taskCode] != 'claimed') {
          _v1GemTaskStatuses[taskCode] = 'claimed';
          _v1GemBalanceCent += 2000;
        }
        break;
      case 'discord_follow':
        if (_v1GemTaskStatuses[taskCode] != 'claimed') {
          _v1GemTaskStatuses[taskCode] = 'claimable';
        }
        break;
    }
    return {'status': _v1GemTaskStatuses[taskCode] ?? 'in_progress'};
  }

  Map<String, dynamic> v1GemTaskClaim(Map<String, dynamic> body) {
    final taskCode = '${body['task_code'] ?? ''}'.trim();
    if (_v1GemTaskStatuses[taskCode] == 'claimable') {
      _v1GemTaskStatuses[taskCode] = 'claimed';
      _v1GemBalanceCent += switch (taskCode) {
        'discord_follow' => 2000,
        _ => 0,
      };
    }
    final status = _v1GemTaskStatuses[taskCode] ?? 'in_progress';
    return {
      'status': status,
      if (status == 'claimed') ...{
        'reward_gems_cent': _v1GemTaskRewardCent(taskCode),
        'balance_cent': _v1GemBalanceCent,
      },
    };
  }

  List<Map<String, dynamic>> v1GemRecords(String? scene) {
    final normalizedScene = (scene ?? 'all').trim().toLowerCase();
    final now = _unixSeconds();
    final records = [
      {
        'ledger_id': 'gl_mock_purchase_1',
        'order_id': 'ord_mock_purchase_1',
        'amount_cent': 55000,
        'scene': 'purchase',
        'reason_code': 'google_purchase',
        'title': 'Gem purchase',
        'subtitle': '500 Gems pack',
        'created_at': now,
        'expires_at': 0,
      },
      {
        'ledger_id': 'gl_mock_task_1',
        'order_id': 'ord_mock_task_1',
        'amount_cent': 2000,
        'scene': 'task',
        'reason_code': 'daily_checkin',
        'title': 'Daily check-in',
        'subtitle': 'Starter reward',
        'created_at': now - 3600,
        'expires_at': now + 86400 * 30,
      },
      {
        'ledger_id': 'gl_mock_spent_1',
        'order_id': 'ord_mock_spent_1',
        'amount_cent': -2000,
        'scene': 'world_tick',
        'reason_code': 'world_tick',
        'title': 'World progress',
        'subtitle': '#Thorn Haven',
        'created_at': now - 7200,
        'expires_at': 0,
      },
      {
        'ledger_id': 'gl_mock_task_2',
        'order_id': 'ord_mock_task_2',
        'amount_cent': 5000,
        'scene': 'task',
        'reason_code': 'send_message',
        'title': 'Send a message',
        'subtitle': 'Daily task',
        'created_at': now - 86400,
        'expires_at': now + 86400 * 29,
      },
    ];
    return records
        .where((record) {
          if (normalizedScene.isEmpty || normalizedScene == 'all') return true;
          if (normalizedScene == 'earned') {
            return asInt(record['amount_cent']) > 0 &&
                record['scene'] != 'purchase';
          }
          if (normalizedScene == 'spent') {
            return asInt(record['amount_cent']) < 0;
          }
          return record['scene'] == normalizedScene;
        })
        .map((record) => Map<String, dynamic>.from(record))
        .toList();
  }

  Map<String, dynamic> v1GemPurchaseReport(Map<String, dynamic> body) {
    final purchaseToken = '${body['purchase_token'] ?? ''}'.trim();
    final productId = '${body['product_id'] ?? ''}'.trim();
    final transactionId = '${body['transaction_id'] ?? ''}'.trim();
    final previousGrant = _v1GrantedGemCentByPurchaseToken[purchaseToken];
    final grantedGemsCent = previousGrant ?? _gemTotalCentForProduct(productId);
    if (previousGrant == null) {
      _v1GrantedGemCentByPurchaseToken[purchaseToken] = grantedGemsCent;
      _v1GemBalanceCent += grantedGemsCent;
    }
    return {
      'status': 'completed',
      'granted_gems_cent': grantedGemsCent,
      if (transactionId.isNotEmpty) 'transaction_id': transactionId,
    };
  }

  int _gemTotalCentForProduct(String productId) {
    return switch (productId) {
      'gem_pack_500' => 55000,
      'gem_pack_1100' => 121000,
      'gem_pack_4400' => 484000,
      'gem_pack_8800' => 968000,
      'gem_pack_16500' => 1815000,
      'gem_pack_55000' => 6050000,
      _ => 0,
    };
  }

  int _v1GemTaskRewardCent(String taskCode) {
    return switch (taskCode) {
      'create_first_worldo' || 'launch_first_world' || 'send_message' => 5000,
      'daily_checkin' || 'discord_follow' => 2000,
      _ => 0,
    };
  }

  Map<String, dynamic> v1UserProfile(
    String? uid, {
    bool viewerAuthenticated = false,
  }) {
    final normalizedUid = uid?.trim() ?? '';
    final targetsCurrentUser =
        normalizedUid.isEmpty || normalizedUid == _v1User['uid'];
    final isSelf = viewerAuthenticated && targetsCurrentUser;
    final user = targetsCurrentUser ? _v1User : _v1UserForUid(normalizedUid);
    final profile = <String, dynamic>{
      'user': _v1UserPayload(user),
      'relation': _deepCopyMap(
        isSelf ? kMockV1SelfRelation : _relationForSearchUser(user),
      ),
    };
    if (isSelf) {
      profile['uuid'] = '4b74ec68-7abc-4cce-a223-e997e31dc811';
      profile['selected_model_code'] = _v1SelectedGemModelCode;
      profile['wallet'] = {'balance_cent': _v1GemBalanceCent};
    }
    return profile;
  }

  void blockV1User(String? targetUid) {
    final uid = targetUid?.trim();
    if (uid == null || uid.isEmpty || uid == _v1User['uid']) return;
    _v1BlockedUsers.add(uid);
  }

  void unblockV1User(String? targetUid) {
    final uid = targetUid?.trim();
    if (uid == null || uid.isEmpty) return;
    _v1BlockedUsers.remove(uid);
  }

  List<Map<String, dynamic>> v1UserBlocks() {
    return _v1BlockedUsers
        .map((uid) {
          final user = _v1UserForUid(uid);
          return {
            'user': _v1UserPayload(user),
            'relation': {..._relationForSearchUser(user), 'is_blocked': true},
          };
        })
        .toList(growable: false);
  }

  Map<String, dynamic> _v1UserForUid(String uid) {
    if (uid == _v1PeerUser['uid']) return _v1PeerUser;
    for (final user in [..._v1DirectMessagePeers, ..._v1SearchUsers]) {
      if (user['uid'] == uid) return user;
    }
    return {
      ..._v1UserPayload(_v1PeerUser),
      'uid': uid,
      'name': uid,
      'bio': 'Mock profile for $uid.',
    };
  }

  List<Map<String, dynamic>> v1OriginSummaries() {
    return _v1Origins.map(_v1OriginSummary).toList();
  }

  Map<String, dynamic> v1OriginContractList(Map<String, String> query) {
    final includeDiscusses = _isPopularOriginScene(query['scene']);
    final items = _filterV1Origins(query).map((origin) {
      final item = _v1OriginContractItem(origin);
      if (includeDiscusses) {
        item['discusses'] = _latestV1OriginDiscusses('${origin['oid'] ?? ''}');
      }
      return item;
    }).toList();
    return _v1Paged(items, query);
  }

  Map<String, dynamic> v1OriginFeed({
    required int startScore,
    required int rn,
    required String deviceId,
  }) {
    final start = startScore.clamp(0, _v1Origins.length);
    final end = (start + rn).clamp(0, _v1Origins.length);
    final exposedIds = _v1OriginFeedExposuresByDevice[deviceId] ?? const {};
    final inspected = _v1Origins.sublist(start, end);
    final items = inspected
        .where((origin) => !exposedIds.contains('${origin['oid'] ?? ''}'))
        .map(_v1OriginContractItem)
        .toList(growable: false);
    return {
      'list': items,
      'rn': rn,
      'next_score': end > start ? end : startScore,
      'has_more': end < _v1Origins.length,
    };
  }

  int recordV1OriginFeedExposures({
    required String deviceId,
    required Set<String> originIds,
  }) {
    final exposedIds = _v1OriginFeedExposuresByDevice.putIfAbsent(
      deviceId,
      () => <String>{},
    );
    var recordedCount = 0;
    for (final originId in originIds) {
      if (exposedIds.add(originId)) recordedCount += 1;
    }
    return recordedCount;
  }

  Map<String, dynamic> v1OriginHotTags() {
    return {
      'list': const ['校园', '恋爱', '玄幻', '都市', '冒险'],
    };
  }

  Map<String, dynamic> v1OriginMyLaunchPresetCharacters(
    String originId, {
    required int limit,
  }) {
    final origin = _findV1Origin(originId);
    final history =
        _v1PresetLaunchHistoryByOrigin[originId] ?? const <String, int>{};
    final items =
        _originEditCharacters(origin)
            .where((character) {
              final type = '${character['type'] ?? 'ai'}'.trim().toLowerCase();
              final charId =
                  '${character['character_id'] ?? character['char_id'] ?? ''}'
                      .trim();
              return type == 'ai' && history.containsKey(charId);
            })
            .map((character) {
              final payload = _contractCharacter(character);
              final charId = '${payload['char_id'] ?? ''}'.trim();
              return <String, dynamic>{
                'char_id': charId,
                'type': 'ai',
                'name': payload['name'],
                'identity': payload['identity'],
                'brief': payload['brief'],
                'goal': payload['goal'],
                'avatar': payload['avatar'],
                'initial_location_id': payload['initial_location_id'],
                'last_launched_at': history[charId] ?? 0,
                'world_id': _v1World['wid'],
                'tick_no': asInt(_v1World['tick_cnt']),
                'sub_tick_no': asInt(_v1World['sub_tick_no']),
                'connect_cnt': asInt(_v1World['connect_cnt']),
                'current_time':
                    _v1World['current_time'] ??
                    'Day ${_v1World['tick_cnt'] ?? 0}',
                'last_active_at': _mockEpoch(
                  _v1World['last_active_at'] ??
                      _v1World['last_progress_at'] ??
                      _v1World['updated_at'],
                ),
              };
            })
            .toList(growable: false)
          ..sort((a, b) {
            final activeCompare = asInt(
              b['last_active_at'],
            ).compareTo(asInt(a['last_active_at']));
            if (activeCompare != 0) return activeCompare;
            return '${a['char_id']}'.compareTo('${b['char_id']}');
          });
    return {'list': items.take(limit).toList(growable: false)};
  }

  List<Map<String, dynamic>> _filterV1Origins(Map<String, String> query) {
    final scene = (query['scene'] ?? '').trim();
    var origins = _v1Origins;
    if (scene == 'mine') {
      origins = _v1OriginsForOwner('${_v1User['uid'] ?? ''}');
    } else if (scene == 'uid') {
      origins = _v1OriginsForOwner(
        query['uid'] ?? query['owner_uid'] ?? query['owner_id'] ?? '',
      );
    } else if (scene == 'tag') {
      final tag = (query['tag'] ?? query['tag_name'] ?? '').trim();
      if (tag.isNotEmpty) {
        origins = _v1Origins
            .where(
              (origin) => _stringList(
                origin['tags'],
              ).map((item) => item.toLowerCase()).contains(tag.toLowerCase()),
            )
            .toList(growable: false);
      }
    }
    return origins;
  }

  List<Map<String, dynamic>> _v1OriginsForOwner(String ownerUid) {
    final normalizedOwner = ownerUid.trim();
    if (normalizedOwner.isEmpty) return const <Map<String, dynamic>>[];
    return _v1Origins
        .where(
          (origin) =>
              '${origin['owner_uid'] ?? origin['created_uid']}'.trim() ==
              normalizedOwner,
        )
        .toList(growable: false);
  }

  bool canViewV1OriginDetail(String originId) {
    Map<String, dynamic>? origin;
    for (final item in _v1Origins) {
      if ('${item['oid'] ?? ''}'.trim() == originId.trim()) {
        origin = item;
        break;
      }
    }
    if (origin == null) return false;
    final reviewStatus = asInt(origin['review_status'], fallback: 20);
    if (reviewStatus == 20) return true;
    final ownerUid = '${origin['owner_uid'] ?? origin['created_uid'] ?? ''}'
        .trim();
    return _authenticated && ownerUid == '${_v1User['uid'] ?? ''}'.trim();
  }

  bool v1OriginExists(String originId) {
    return _v1Origins.any(
      (item) => '${item['oid'] ?? ''}'.trim() == originId.trim(),
    );
  }

  bool canEditV1Origin(String originId) {
    for (final origin in _v1Origins) {
      if ('${origin['oid'] ?? ''}'.trim() != originId.trim()) continue;
      final ownerUid = '${origin['owner_uid'] ?? origin['created_uid'] ?? ''}'
          .trim();
      return ownerUid == '${_v1User['uid'] ?? ''}'.trim();
    }
    return false;
  }

  Map<String, dynamic> v1OriginDetail(String? oid) {
    final origin = _findV1Origin(oid);
    return _originDetailPayload(origin);
  }

  Map<String, dynamic> v1OriginContractDetail(String? originId) {
    final origin = _findV1Origin(originId);
    final contract = _v1OriginContractItem(origin);
    final info = _mapFromObject(contract['info']);
    return {
      ...contract,
      'info': <String, dynamic>{
        for (final key in const <String>[
          'origin_id',
          'origin_name',
          'origin_version',
          'origin_version_time',
          'definition_version',
          'language',
          'current_time',
          'owner_uid',
          'owner_name',
          'owner_user',
          'brief',
          'tags',
          'metric',
          'created_at',
          'cover',
          'map_url',
          'status',
        ])
          if (info.containsKey(key)) key: info[key],
      },
      'init_location_group': _originContractInitLocationGroup(origin),
      'characters': _originEditCharacters(
        origin,
      ).map(_contractOriginDetailCharacter).toList(),
      'locations': _originEditLocations(origin)
          .map(
            (location) =>
                _contractLocation(location, includeLocationDescription: false),
          )
          .toList(),
      'ticks': _originContractTicks(origin),
    };
  }

  Map<String, dynamic> v1OriginContractInfo(String? originId) {
    final origin = _findV1Origin(originId);
    final remaining = asInt(origin['_v2_info_polls_remaining']);
    if (remaining > 0) {
      origin['_v2_info_polls_remaining'] = remaining - 1;
    } else if (origin['_v2_processing'] == true) {
      origin['status'] = 10;
      origin['_v2_processing'] = false;
    }
    return _v1OriginContractItem(origin);
  }

  Map<String, dynamic> v1OriginMap(String originId, String locationId) {
    final origin = _findV1Origin(originId);
    if ((origin['definition_version'] ?? 2) != 2) {
      return <String, dynamic>{};
    }
    return _v1TilemapDefinition(locationId);
  }

  Map<String, dynamic> v2OriginForEdit(String originId) {
    final detail = v1OriginContractDetail(originId);
    final info = _mapFromObject(detail['info']);
    detail['info'] = <String, dynamic>{
      for (final key in const <String>[
        'origin_id',
        'origin_name',
        'origin_version',
        'origin_version_time',
        'definition_version',
        'language',
        'current_time',
        'owner_uid',
        'owner_name',
        'owner_user',
        'brief',
        'tags',
        'metric',
        'created_at',
        'cover',
        'map_url',
        'status',
      ])
        if (info.containsKey(key)) key: info[key],
    };
    return detail;
  }

  Map<String, dynamic> createV1Origin(Map<String, dynamic> body) {
    final now = DateTime.now().toUtc().toIso8601String();
    final oid = 'o_mock_${DateTime.now().millisecondsSinceEpoch}';
    final created = {
      ..._deepCopyMap(_v1Origin),
      'oid': oid,
      'name': '${body['origin_name'] ?? _v1Origin['name']}',
      'display_subtitle': '${body['brief'] ?? _v1Origin['display_subtitle']}',
      'world_view':
          '${body['setting'] ?? body['brief'] ?? _v1Origin['world_view']}',
      'world_setting': '${body['setting'] ?? _v1Origin['world_setting']}',
      'cover': '${body['cover'] ?? _v1Origin['cover']}',
      'map_url': '${body['map_url'] ?? body['cover'] ?? _v1Origin['map_url']}',
      'definition_version':
          body['definition_version'] ?? _v1Origin['definition_version'],
      if (body['tile_types'] is Map)
        'tile_types': _deepCopyMap(_mapFromObject(body['tile_types'])),
      'tags': body['tags'] is List ? body['tags'] : const <Object?>[],
      'metric': body['metric'] is Map
          ? _deepCopyMap(_mapFromObject(body['metric']))
          : _deepCopyMap(kMockV1Metric),
      'start_time': '${body['started_at'] ?? _v1Origin['start_time']}',
      'tick_duration_days':
          _tickDurationDaysFromOriginCreateBody(body) ??
          _v1Origin['tick_duration_days'],
      'created_at': now,
      'updated_at': now,
      'character_cnt': body['characters'] is List
          ? (body['characters'] as List).length
          : _v1Origin['character_cnt'],
      'location_cnt': body['locations'] is List
          ? (body['locations'] as List).length
          : _v1Origin['location_cnt'],
      if (body['characters'] is List)
        '_edit_characters': _deepCopyList(body['characters'] as List),
      if (body['locations'] is List)
        '_edit_locations': _deepCopyList(body['locations'] as List),
      if (body['events'] is List)
        '_edit_events': _deepCopyList(body['events'] as List),
    };
    _v1Origins.insert(0, created);
    return {
      ..._v1OriginContractItem(created),
      'characters': body['characters'] is List
          ? (body['characters'] as List)
                .map((item) => _contractCharacter(_mapFromObject(item)))
                .toList(growable: false)
          : kMockV1Characters.map(_contractCharacter).toList(),
      'locations': body['locations'] is List
          ? (body['locations'] as List)
                .map((item) => _contractLocation(_mapFromObject(item)))
                .toList(growable: false)
          : kMockV1Locations.map(_contractLocation).toList(),
      'ticks': const <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> updateV1Origin(Map<String, dynamic> body) {
    final origin = _findV1Origin('${body['origin_id'] ?? body['oid'] ?? ''}');
    final originName = body['origin_name'] ?? body['name'];
    final brief = body['brief'] ?? body['world_view'];
    final setting = body['setting'] ?? body['world_setting'];
    if (originName != null) origin['name'] = originName;
    if (brief != null) origin['display_subtitle'] = brief;
    if (setting != null) {
      origin['world_view'] = setting;
      origin['world_setting'] = setting;
    }
    if (body['cover'] != null) origin['cover'] = body['cover'];
    if (body['map_url'] != null) origin['map_url'] = body['map_url'];
    if (body['definition_version'] != null) {
      origin['definition_version'] = body['definition_version'];
    }
    if (body['tile_types'] is Map) {
      origin['tile_types'] = _deepCopyMap(_mapFromObject(body['tile_types']));
    }
    if (body['tags'] is List) origin['tags'] = body['tags'];
    if (body['metric'] is Map) {
      origin['metric'] = _deepCopyMap(_mapFromObject(body['metric']));
    }
    if (body['started_at'] != null) origin['start_time'] = body['started_at'];
    final tickDurationDays = _tickDurationDaysFromOriginCreateBody(body);
    if (tickDurationDays != null) {
      origin['tick_duration_days'] = tickDurationDays;
    }
    if (body['update_notes'] != null) {
      origin['update_notes'] = body['update_notes'];
    }
    if (body['characters'] is List) {
      origin['_edit_characters'] = _deepCopyList(body['characters'] as List);
      origin['character_cnt'] = (body['characters'] as List).length;
    }
    if (body['locations'] is List) {
      origin['_edit_locations'] = _deepCopyList(body['locations'] as List);
      origin['location_cnt'] = (body['locations'] as List).length;
    }
    if (body['events'] is List) {
      origin['_edit_events'] = _deepCopyList(body['events'] as List);
    }
    origin['version_num'] = asInt(origin['version_num'], fallback: 1) + 1;
    origin['updated_at'] = DateTime.now().toUtc().toIso8601String();
    return {
      ..._v1OriginContractItem(origin),
      'characters': body['characters'] is List
          ? (body['characters'] as List)
                .map((item) => _contractCharacter(_mapFromObject(item)))
                .toList(growable: false)
          : kMockV1Characters.map(_contractCharacter).toList(),
      'locations': body['locations'] is List
          ? (body['locations'] as List)
                .map((item) => _contractLocation(_mapFromObject(item)))
                .toList(growable: false)
          : kMockV1Locations.map(_contractLocation).toList(),
      'ticks': const <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> createV2Origin(Map<String, dynamic> body) {
    final created = createV1Origin(body);
    final info = _mapFromObject(created['info']);
    final origin = _findV1Origin('${info['origin_id'] ?? ''}');
    origin['version_num'] = 1;
    origin['definition_version'] = 2;
    origin['tile_types'] = _deepCopyMap(
      _mapFromObject(_v1TilemapDefinition('root')['tile_types']),
    );
    origin['status'] = 20;
    origin['init_location_group'] = body['init_location_group'];
    origin['_v2_processing'] = true;
    origin['_v2_info_polls_remaining'] = 1;
    final normalizedInfo = _mapFromObject(
      _v1OriginContractItem(origin)['info'],
    );
    return _originUpsertResponse(normalizedInfo);
  }

  Map<String, dynamic> updateV2Origin(Map<String, dynamic> body) {
    final updated = updateV1Origin(body);
    final info = _mapFromObject(updated['info']);
    final origin = _findV1Origin('${info['origin_id'] ?? ''}');
    origin['definition_version'] = 2;
    origin['tile_types'] = _deepCopyMap(
      _mapFromObject(_v1TilemapDefinition('root')['tile_types']),
    );
    origin['status'] = 20;
    origin['init_location_group'] = body['init_location_group'];
    origin['_v2_processing'] = true;
    origin['_v2_info_polls_remaining'] = 1;
    return _originUpsertResponse(info);
  }

  Map<String, dynamic> _originUpsertResponse(Map<String, dynamic> info) {
    return {
      'origin_id': info['origin_id'],
      'origin_version': info['origin_version'],
      'origin_version_time': info['origin_version_time'],
      'origin_name': info['origin_name'],
    };
  }

  Map<String, dynamic> publishV1Origin(String oid) {
    final origin = _findV1Origin(oid);
    origin['status'] = 2;
    return _originDetailPayload(origin);
  }

  void deleteV1Origin(String oid) {
    final origin = _findV1Origin(oid);
    if (oid.isNotEmpty && oid == origin['oid']) {
      origin['status'] = 0;
    }
  }

  Map<String, dynamic> v1OriginVersionList(String? oid) {
    final origin = _findV1Origin(oid);
    return {
      'list': [
        {
          'version_num': origin['version_num'],
          'update_notes':
              origin['update_notes'] ??
              'Initial mock version for ${oid ?? origin['oid']}',
          'status': origin['status'],
          'created_at': origin['created_at'],
        },
      ],
      'total': 1,
    };
  }

  String launchV1World(String oid, {String? presetCharacterId}) {
    if (oid.isNotEmpty) _v1World['oid'] = oid;
    final charId = (presetCharacterId ?? '').trim();
    if (oid.isNotEmpty && charId.isNotEmpty) {
      _v1PresetLaunchHistoryByOrigin.putIfAbsent(
        oid,
        () => <String, int>{},
      )[charId] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    return '${_v1World['wid']}';
  }

  List<Map<String, dynamic>> v1WorldSummaries() {
    return _v1Worlds.map(_v1WorldSummary).toList();
  }

  Map<String, dynamic> v1WorldContractList(Map<String, String> query) {
    final worlds = _filterV1Worlds(query);
    return _v1Paged(worlds.map(_v1WorldContractItem).toList(), query);
  }

  List<Map<String, dynamic>> _filterV1Worlds(Map<String, String> query) {
    final originId = (query['origin_id'] ?? '').trim();
    List<Map<String, dynamic>> filterByOrigin(
      List<Map<String, dynamic>> worlds,
    ) => originId.isEmpty
        ? worlds
        : worlds
              .where((world) => '${world['oid'] ?? ''}'.trim() == originId)
              .toList(growable: false);
    final scene = (query['scene'] ?? '').trim();
    if (scene == 'mine') {
      return filterByOrigin(_v1WorldsForOwner('${_v1User['uid'] ?? ''}'));
    }
    if (scene == 'uid') {
      return filterByOrigin(
        _v1WorldsForOwner(
          query['uid'] ?? query['owner_uid'] ?? query['owner_id'] ?? '',
        ),
      );
    }
    if (scene == 'tag') {
      final tag = (query['tag'] ?? query['tag_name'] ?? '').trim();
      if (tag.isEmpty) return filterByOrigin(_v1Worlds);
      return filterByOrigin(
        _v1Worlds
            .where(
              (world) => _stringList(
                world['tags'],
              ).map((item) => item.toLowerCase()).contains(tag.toLowerCase()),
            )
            .toList(growable: false),
      );
    }
    final ownerUid = (query['owner_uid'] ?? '').trim();
    if (ownerUid.isEmpty) return filterByOrigin(_v1Worlds);
    return filterByOrigin(_v1WorldsForOwner(ownerUid));
  }

  List<Map<String, dynamic>> _v1WorldsForOwner(String ownerUid) {
    final normalizedOwner = ownerUid.trim();
    if (normalizedOwner.isEmpty) return const <Map<String, dynamic>>[];
    return _v1Worlds
        .where(
          (world) =>
              '${world['owner_uid'] ?? world['created_uid']}'.trim() ==
              normalizedOwner,
        )
        .toList(growable: false);
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map(asString)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> v1WorldOriginProgress({
    required String uid,
    required String originId,
  }) {
    final normalizedUid = uid.trim();
    final normalizedOriginId = originId.trim();
    if (normalizedUid.isEmpty || normalizedOriginId.isEmpty) {
      return {'world_id': '', 'tick_cnt': 0};
    }

    Map<String, dynamic>? bestWorld;
    for (final world in _v1Worlds) {
      if ('${world['oid'] ?? ''}'.trim() != normalizedOriginId) continue;
      if (!_v1WorldBelongsToUser(world, normalizedUid)) continue;
      final tickCnt = ((world['tick_cnt'] as num?)?.toInt() ?? 0);
      final bestTickCnt = ((bestWorld?['tick_cnt'] as num?)?.toInt() ?? -1);
      if (bestWorld == null || tickCnt > bestTickCnt) bestWorld = world;
    }

    if (bestWorld == null) return {'world_id': '', 'tick_cnt': 0};
    return {
      'world_id': '${bestWorld['wid'] ?? ''}',
      'tick_cnt': ((bestWorld['tick_cnt'] as num?)?.toInt() ?? 0),
    };
  }

  Map<String, dynamic> v1WorldSummaryLatest(Map<String, String> query) {
    final originId = (query['origin_id'] ?? '').trim();
    final worldId = (query['world_id'] ?? '').trim();
    final world = worldId.isEmpty ? null : _findV1World(worldId);
    final resolvedOriginId = originId.isNotEmpty
        ? originId
        : '${world?['oid'] ?? ''}'.trim();
    if (resolvedOriginId.isEmpty) {
      return {'list': const <Map<String, dynamic>>[]};
    }
    if (originId.isNotEmpty &&
        world != null &&
        '${world['oid'] ?? ''}'.trim() != originId) {
      return {'list': const <Map<String, dynamic>>[]};
    }

    final seenWorldIds = <String>{};
    final items = <Map<String, dynamic>>[];
    for (final candidate in _v1Worlds) {
      final candidateWorldId = '${candidate['wid'] ?? ''}'.trim();
      if (candidateWorldId.isEmpty || !seenWorldIds.add(candidateWorldId)) {
        continue;
      }
      if (worldId.isNotEmpty && candidateWorldId == worldId) continue;
      if ('${candidate['oid'] ?? ''}'.trim() != resolvedOriginId) continue;
      final summary = '${candidate['last_progress_summary'] ?? ''}'.trim();
      if (summary.isEmpty) continue;
      final tickTime = _mockEpoch(candidate['last_progress_at']);
      items.add({
        'world_id': candidateWorldId,
        'origin_id': '${candidate['oid'] ?? ''}',
        'tick_no': asInt(candidate['tick_cnt']),
        'sub_tick_no': asInt(candidate['sub_tick_no']),
        'summary': summary,
        'tick_time': tickTime,
        'created_at': tickTime + 10,
      });
    }

    items.sort((a, b) {
      final tickTimeCompare = asInt(
        b['tick_time'],
      ).compareTo(asInt(a['tick_time']));
      if (tickTimeCompare != 0) return tickTimeCompare;
      return asInt(b['created_at']).compareTo(asInt(a['created_at']));
    });
    return {'list': items.take(5).toList(growable: false)};
  }

  bool _v1WorldBelongsToUser(Map<String, dynamic> world, String uid) {
    final ownerUid = '${world['owner_uid'] ?? world['created_uid'] ?? ''}'
        .trim();
    if (ownerUid == uid) return true;
    final worldId = '${world['wid'] ?? ''}'.trim();
    if (worldId.isEmpty) return false;
    return _v1WorldApplies.any(
      (apply) =>
          '${apply['world_id'] ?? ''}'.trim() == worldId &&
          '${apply['applicant_uid'] ?? ''}'.trim() == uid &&
          apply['status'] == 40,
    );
  }

  Map<String, dynamic> v1WorldDetail(String? wid) {
    final world = _findV1World(wid);
    return {
      'world': _deepCopyMap(world),
      'character_list': kMockV1Characters.map(_deepCopyMap).toList(),
      'metric': _deepCopyMap(kMockV1Metric),
      'location_list': kMockV1Locations.map(_deepCopyMap).toList(),
      'tick_list': kMockV1Ticks.map(_deepCopyMap).toList(),
      'action_button_state': 'progress',
    };
  }

  Map<String, dynamic> v1WorldContractDetail(String? worldId) {
    final world = _findV1World(worldId);
    final contractItem = _v1WorldContractItem(world);
    final info = asJsonMap(contractItem['info']);
    return {
      ...contractItem,
      'info': {
        ...info,
        'last_chat_location_id': asString(
          world['last_chat_location_id'],
          fallback: 'loc_gate',
        ),
      },
      'relation_status': _v1WorldRelationStatus(world),
      'characters': kMockV1Characters.map(_contractCharacter).toList(),
      'locations': kMockV1Locations.map(_contractLocation).toList(),
      'ticks': _v1WorldTicks(world).map(_deepCopyMap).toList(),
    };
  }

  Map<String, dynamic> v1WorldContractInfo(String? worldId) {
    return _v1WorldContractItem(_findV1World(worldId));
  }

  Map<String, dynamic> v1WorldMap(String worldId, String locationId) {
    final world = _findV1World(worldId);
    if ((world['definition_version'] ?? 2) != 2) {
      return <String, dynamic>{};
    }
    return _v1TilemapDefinition(locationId);
  }

  Map<String, dynamic> v1WorldTickList({
    required String worldId,
    required Map<String, String> query,
  }) {
    final world = _findV1World(worldId.trim());
    final indexedTicks =
        _v1WorldTicks(world).indexed
            .where((entry) => (entry.$2['status'] as num?)?.toInt() == 50)
            .toList(growable: false)
          ..sort((a, b) {
            final aTickNo = (a.$2['tick_no'] as num?)?.toInt() ?? 0;
            final bTickNo = (b.$2['tick_no'] as num?)?.toInt() ?? 0;
            final tickNoCompare = bTickNo.compareTo(aTickNo);
            if (tickNoCompare != 0) return tickNoCompare;
            return b.$1.compareTo(a.$1);
          });
    final ticks = indexedTicks
        .map((entry) => _deepCopyMap(entry.$2))
        .toList(growable: false);
    return _v1Paged(ticks, query);
  }

  Map<String, dynamic> applyToV1World({
    required String worldId,
    String? message,
  }) {
    final world = _findV1World(worldId.trim());
    final applicantUid = '${_v1User['uid']}';
    for (final apply in _v1WorldApplies) {
      if (apply['world_id'] == world['wid'] &&
          apply['applicant_uid'] == applicantUid &&
          (apply['status'] == 10 || apply['status'] == 20)) {
        return {'apply_id': apply['apply_id'], 'status': apply['status']};
      }
    }
    final apply = _newV1WorldApply(
      applyId: 'apl_mock_${(++_v1WorldApplySeq).toString().padLeft(3, '0')}',
      worldId: '${world['wid']}',
      message: message,
    );
    _v1WorldApplies.add(apply);
    return {'apply_id': apply['apply_id'], 'status': apply['status']};
  }

  Map<String, dynamic> v1WorldApplyList(Map<String, String> query) {
    final worldId = (query['world_id'] ?? '').trim();
    final status = int.tryParse((query['status'] ?? '').trim());
    final applies = _v1WorldApplies
        .where((apply) {
          final matchesWorld = worldId.isEmpty || apply['world_id'] == worldId;
          final matchesStatus = status == null || apply['status'] == status;
          return matchesWorld && matchesStatus;
        })
        .toList(growable: false);
    return _v1Paged(applies, query);
  }

  Map<String, dynamic> reviewV1WorldApply({
    required String applyId,
    required String action,
    String? reviewMsg,
  }) {
    final apply = _findV1WorldApply(applyId);
    final normalizedAction = action.trim().toLowerCase();
    final status = normalizedAction == 'reject' ? 30 : 20;
    apply['status'] = status;
    apply['reviewer_uid'] = _v1User['uid'];
    apply['review_msg'] = reviewMsg ?? '';
    apply['reviewed_at'] = _unixSeconds();
    final world = _findV1World('${apply['world_id']}');
    _v1Notifications.add({
      'notification_id':
          'ntf_mock_world_apply_review_${DateTime.now().microsecondsSinceEpoch}',
      'notice_block': 'world_apply',
      'notice_type': 'world_apply_review',
      'sender': _deepCopyMap(_v1User),
      'biz_type': 2,
      'biz_id': apply['world_id'],
      'obj_id': apply['apply_id'],
      'world_name': world['name'] ?? world['world_name'] ?? world['wid'],
      'status': status,
      'content':
          'request to ${world['name'] ?? world['world_name'] ?? world['wid']}',
      'is_read': false,
      'created_at': _unixSeconds(),
    });
    return {'apply_id': apply['apply_id'], 'status': status};
  }

  Map<String, dynamic> joinV1World({
    required String worldId,
    String? presetCharacterId,
    Map<String, dynamic>? customRole,
  }) {
    final world = _findV1World(worldId.trim());
    final applicantUid = '${_v1User['uid']}';
    Map<String, dynamic>? apply;
    for (final item in _v1WorldApplies) {
      if (item['world_id'] == world['wid'] &&
          item['applicant_uid'] == applicantUid) {
        apply = item;
      }
    }
    if (apply == null) {
      apply = _newV1WorldApply(
        applyId: 'apl_mock_${(++_v1WorldApplySeq).toString().padLeft(3, '0')}',
        worldId: '${world['wid']}',
      );
      apply['status'] = 20;
      _v1WorldApplies.add(apply);
    }
    final wasJoined = apply['status'] == 40;
    apply['status'] = 40;
    apply['joined_at'] = _unixSeconds();

    final presetId = (presetCharacterId ?? '').trim();
    final customCharId = (customRole?['char_id'] ?? '').toString().trim();
    final charId = presetId.isNotEmpty
        ? presetId
        : customCharId.isNotEmpty
        ? customCharId
        : 'char_U_MOCK';
    if (!wasJoined) {
      world['player_cnt'] = ((world['player_cnt'] as num?)?.toInt() ?? 0) + 1;
      if (presetId.isEmpty) {
        world['ai_character_cnt'] =
            ((world['ai_character_cnt'] as num?)?.toInt() ?? 0) + 1;
      }
    }
    return {'world_id': world['wid'], 'char_id': charId};
  }

  String _v1WorldRelationStatus(Map<String, dynamic> world) {
    final applicantUid = '${_v1User['uid']}';
    if ('${world['owner_uid']}' == applicantUid) return 'owner';
    Map<String, dynamic>? currentApply;
    for (final apply in _v1WorldApplies) {
      if (apply['world_id'] == world['wid'] &&
          apply['applicant_uid'] == applicantUid) {
        currentApply = apply;
      }
    }
    switch (currentApply?['status']) {
      case 10:
        return 'pending';
      case 20:
        return 'approved';
      case 30:
        return 'rejected';
      case 40:
        return 'joined';
      default:
        return 'none';
    }
  }

  Map<String, dynamic> tickV1World(String worldId) {
    final world = _findV1World(worldId);
    final tickCount = ((world['tick_cnt'] as num?)?.toInt() ?? 0) + 1;
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    final nowEpoch = _mockUnixTimestamp(now);
    world['tick_cnt'] = tickCount;
    world['last_progress_at'] = nowIso;
    world['last_progress_summary'] = 'Mock tick $tickCount completed.';
    world['updated_at'] = nowIso;
    final lastTick = {
      'tick_id': 'tick_${world['wid']}_$tickCount',
      'tick_no': tickCount,
      'sub_tick_no': 1,
      'status': 50,
      'created_at': nowEpoch,
      'tick_result': {
        'current_time': nowIso,
        'narrator': world['last_progress_summary'],
        'paragraphs': const <Map<String, dynamic>>[],
        'location_groups': const <Map<String, dynamic>>[],
      },
    };
    _v1WorldTicks(world).add(lastTick);
    return {
      'world_id': world['wid'],
      'tick_cnt': tickCount,
      'last_tick': _deepCopyMap(lastTick),
    };
  }

  List<Map<String, dynamic>> v1Notifications() {
    return _v1Notifications.map(_v1NotificationPayload).toList();
  }

  Map<String, dynamic> _v1NotificationPayload(Map<String, dynamic> item) {
    final payload = _deepCopyMap(item);
    if (payload['notice_block'] == 'interaction' &&
        '${payload['origin_name'] ?? ''}'.trim().isEmpty) {
      final origin = _findV1Origin('${payload['biz_id'] ?? ''}');
      payload['origin_name'] = origin['name'] ?? origin['origin_name'] ?? '';
    }
    return payload;
  }

  Map<String, dynamic> v1UnreadSummary() {
    final worldApplyUnread = _v1UnreadCount('world_apply');
    final followUnread = _v1UnreadCount('follow');
    final interactionUnread = _v1UnreadCount('interaction');
    final directMessageUnread = v1DirectMessageUnreadCount();
    return {
      'world_apply_unread': worldApplyUnread,
      'follow_unread': followUnread,
      'interaction_unread': interactionUnread,
      'direct_message_unread': directMessageUnread,
      'total_unread':
          worldApplyUnread +
          followUnread +
          interactionUnread +
          directMessageUnread,
    };
  }

  void markV1NotificationsRead({
    required String? block,
    required String? notificationId,
  }) {
    for (final notification in _v1Notifications) {
      final id = notification['notification_id']?.toString();
      final matchesId =
          notificationId != null &&
          notificationId.isNotEmpty &&
          id == notificationId;
      final matchesBlock =
          (block == null || block.isEmpty || block == 'all') ||
          notification['notice_block']?.toString() == block;
      if (matchesId ||
          (notificationId == null || notificationId.isEmpty) && matchesBlock) {
        notification['is_read'] = true;
      }
    }
  }

  int _v1UnreadCount(String block) {
    return _v1Notifications.where((notification) {
      return notification['notice_block']?.toString() == block &&
          notification['is_read'] != true;
    }).length;
  }

  List<Map<String, dynamic>> v1FollowerMessages() {
    return [
      {
        ..._v1UserPayload(_v1PeerUser),
        'created_at': kMockV1Now,
        'is_read': false,
        'relation': _deepCopyMap(kMockV1PeerRelation),
      },
    ];
  }

  Map<String, dynamic> v1UserList(
    Map<String, String> query, {
    required String type,
  }) {
    final users = type == 'following'
        ? _v1FollowingUsers()
        : _v1FollowerUsers();
    final pagedUsers = _v1PageItems(users, query);
    return {
      'total': users.length,
      'pn': int.tryParse(query['pn'] ?? '') ?? 1,
      'rn': int.tryParse(query['rn'] ?? '') ?? 10,
      'list': pagedUsers.map((item) {
        final user = _v1UserPayload(item);
        final relation = user.remove('relation');
        return {
          'user': user,
          'relation': relation is Map<String, dynamic>
              ? _deepCopyMap(relation)
              : _deepCopyMap(kMockV1PeerRelation),
        };
      }).toList(),
    };
  }

  List<Map<String, dynamic>> v1Relations() => v1FollowerMessages();

  List<Map<String, dynamic>> _v1FollowingUsers() {
    return _v1SearchUsers
        .skip(1)
        .take(36)
        .map((item) {
          final user = _deepCopyMap(item);
          user['is_followed'] = true;
          user['i_followed'] = true;
          user['followed_me'] = item['followed_me'] ?? false;
          user['is_friend'] = item['is_friend'] ?? false;
          user['follow_button_state'] = 'following';
          user['relation'] = _relationForFollowUser(user, followed: true);
          return user;
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _v1FollowerUsers() {
    return _v1SearchUsers
        .skip(2)
        .take(42)
        .map((item) {
          final user = _deepCopyMap(item);
          final followed = item['i_followed'] == true;
          user['is_followed'] = followed;
          user['i_followed'] = followed;
          user['followed_me'] = true;
          user['is_friend'] = followed && item['is_friend'] == true;
          user['follow_button_state'] = followed ? 'following' : 'follow_back';
          user['relation'] = _relationForFollowUser(user, followed: followed);
          return user;
        })
        .toList(growable: false);
  }

  Map<String, dynamic> _relationForFollowUser(
    Map<String, dynamic> user, {
    required bool followed,
  }) {
    final followedMe = user['followed_me'] == true;
    final isFriend = followed && followedMe;
    return {
      'target_user_id': user['uid'],
      'is_self': user['uid'] == _v1User['uid'],
      'is_followed': followed,
      'i_followed': followed,
      'followed_me': followedMe,
      'is_friend': isFriend,
      'follow_button_state': followed
          ? 'following'
          : followedMe
          ? 'follow_back'
          : 'follow',
      'can_send_dm': true,
      'dm_permission': isFriend ? 'unlimited' : 'pingpong',
    };
  }

  Map<String, dynamic> _v1Paged(
    List<Map<String, dynamic>> items,
    Map<String, String> query,
  ) {
    return {
      'list': _v1PageItems(items, query),
      'total': items.length,
      'pn': int.tryParse(query['pn'] ?? '') ?? 1,
      'rn': int.tryParse(query['rn'] ?? '') ?? 10,
    };
  }

  List<Map<String, dynamic>> _v1PageItems(
    List<Map<String, dynamic>> items,
    Map<String, String> query,
  ) {
    final parsedPage = int.tryParse(query['pn'] ?? '') ?? 1;
    final parsedSize = int.tryParse(query['rn'] ?? '') ?? items.length;
    final page = parsedPage < 1 ? 1 : parsedPage;
    final size = parsedSize < 1 ? items.length : parsedSize;
    final rawStart = (page - 1) * size;
    final start = rawStart > items.length ? items.length : rawStart;
    final rawEnd = start + size;
    final end = rawEnd > items.length ? items.length : rawEnd;
    return items.sublist(start, end).map(_deepCopyMap).toList();
  }

  Map<String, dynamic> v1RelationStatus(List<Object?> uids) {
    return {
      for (final uid in uids)
        '$uid': {
          ..._deepCopyMap(kMockV1PeerRelation),
          'target_user_id': '$uid',
        },
    };
  }

  Map<String, dynamic> v1FollowResult({required bool followed}) {
    return {
      'followed': followed,
      'relation': {
        ..._deepCopyMap(kMockV1PeerRelation),
        'is_followed': followed,
        'i_followed': followed,
        'is_friend': followed,
        'follow_button_state': followed ? 'friends' : 'follow_back',
        'dm_permission': followed ? 'unlimited' : 'pingpong',
      },
      'follower_count': followed ? 13 : 12,
      'following_count': followed ? 9 : 8,
      'friend_count': followed ? 4 : 3,
    };
  }

  List<Map<String, dynamic>> v1DmConversations() {
    return [
      _v1DirectMessageConversation(),
      for (var index = 1; index < _v1DirectMessagePeers.length; index += 1)
        _conversationForPeer('${_v1DirectMessagePeers[index]['uid']}'),
    ];
  }

  String v1DmConversationCursor() => _v1DmConversationCursor;

  Map<String, dynamic> v1DmConversationDeltas(String afterMessageId) {
    if (afterMessageId != _v1DmConversationCursor ||
        _v1DmConversationDeltaSent) {
      return {
        'list': <Map<String, dynamic>>[],
        'total': 0,
        'next_after_message_id': _v1DmConversationCursor,
      };
    }
    _v1DmConversationDeltaSent = true;
    _v1DmConversationCursor = 'dm_sync_2';
    final updatedPrimary = _v1DirectMessageConversation()
      ..['last_message_id'] = 'DM_MOCK_DELTA_001'
      ..['last_message'] = 'Incremental mock direct message update.'
      ..['last_message_at'] = _mockUnixTimestamp(DateTime.now())
      ..['last_sender_uid'] = _v1PeerUser['uid']
      ..['unread_cnt'] = 2;
    final newConversation = _mockDirectMessageConversation(1)
      ..['conv_id'] = 'DMC_MOCK_DELTA_001'
      ..['last_message_id'] = 'DM_MOCK_DELTA_002'
      ..['last_message'] = 'Brand new incremental conversation.'
      ..['last_message_at'] = _mockUnixTimestamp(
        DateTime.now().add(const Duration(seconds: 1)),
      )
      ..['unread_cnt'] = 1;
    return {
      'list': [updatedPrimary, newConversation],
      'total': 2,
      'next_after_message_id': _v1DmConversationCursor,
    };
  }

  List<Map<String, dynamic>> v1DmMessagesForPeer(String? peerUid) {
    final messages = _messagesForPeer(peerUid);
    return messages.reversed.map(_deepCopyMap).toList(growable: false);
  }

  Map<String, dynamic> sendV1DirectMessage(Map<String, dynamic> body) {
    final peerUid = '${body['peer_uid'] ?? _v1PeerUser['uid']}';
    final now = _mockUnixTimestamp(DateTime.now());
    final message = {
      'msg_id': 'DM_MOCK_${DateTime.now().millisecondsSinceEpoch}',
      'conv_id': _conversationIdForPeer(peerUid),
      'sender_uid': _v1User['uid'],
      'receiver_uid': peerUid,
      'content': '${body['content'] ?? ''}',
      'created_at': now,
    };
    _messagesForPeer(peerUid).add(message);
    return {
      'message': _deepCopyMap(message),
      'conversation': _conversationForPeer(peerUid),
    };
  }

  void markV1DirectMessagesRead(String? peerUid) {
    if (peerUid == null || peerUid.isEmpty || peerUid == _v1PeerUser['uid']) {
      _v1DirectMessageUnreadCount = 0;
    }
  }

  int v1DirectMessageUnreadCount() => _v1DirectMessageUnreadCount;

  void blockV1DirectMessagePeer(String? targetUid) {
    final uid = targetUid?.trim();
    if (uid == null || uid.isEmpty) return;
    _v1BlockedDirectMessagePeers.add(uid);
  }

  void unblockV1DirectMessagePeer(String? targetUid) {
    final uid = targetUid?.trim();
    if (uid == null || uid.isEmpty) return;
    _v1BlockedDirectMessagePeers.remove(uid);
  }

  List<Map<String, dynamic>> v1DirectMessageBlocks() {
    return [
      if (_v1BlockedDirectMessagePeers.contains(_v1PeerUser['uid']))
        _v1UserPayload(_v1PeerUser),
    ];
  }

  Map<String, dynamic> _v1DirectMessageConversation() {
    final conversation = _deepCopyMap(kMockV1DmConversation);
    final messages = _messagesForPeer('${_v1PeerUser['uid']}');
    final latest = messages.isEmpty ? null : messages.last;
    if (latest != null) {
      conversation['last_message'] = latest['content'];
      conversation['last_message_id'] = latest['msg_id'];
      conversation['last_message_at'] = latest['created_at'];
      conversation['last_sender_uid'] = latest['sender_uid'];
    }
    final iBlockedPeer = _v1BlockedDirectMessagePeers.contains(
      _v1PeerUser['uid'],
    );
    conversation['unread_cnt'] = _v1DirectMessageUnreadCount;
    conversation['i_blocked_peer'] = iBlockedPeer;
    conversation['peer_blocked_me'] = false;
    conversation['can_send_next_message'] = !iBlockedPeer;
    return conversation;
  }

  Map<String, dynamic> _conversationForPeer(String? peerUid) {
    final uid = (peerUid ?? '').trim();
    if (uid.isEmpty || uid == _v1PeerUser['uid']) {
      return _v1DirectMessageConversation();
    }
    final index = _v1DirectMessagePeers.indexWhere(
      (peer) => peer['uid'] == uid,
    );
    final conversation = index < 0
        ? _mockDirectMessageConversation(1)
        : _mockDirectMessageConversation(index);
    final messages = _messagesForPeer(uid);
    final latest = messages.isEmpty ? null : messages.last;
    if (latest != null) {
      conversation['last_message'] = latest['content'];
      conversation['last_message_id'] = latest['msg_id'];
      conversation['last_message_at'] = latest['created_at'];
      conversation['last_sender_uid'] = latest['sender_uid'];
    }
    return conversation;
  }

  String _conversationIdForPeer(String? peerUid) {
    final uid = (peerUid ?? '').trim();
    if (uid.isEmpty || uid == _v1PeerUser['uid']) return 'DMC_MOCK_001';
    final index = _v1DirectMessagePeers.indexWhere(
      (peer) => peer['uid'] == uid,
    );
    if (index < 0) return 'DMC_MOCK_UNKNOWN';
    return 'DMC_MOCK_${(index + 1).toString().padLeft(3, '0')}';
  }

  List<Map<String, dynamic>> _messagesForPeer(String? peerUid) {
    final uid = '${peerUid ?? _v1PeerUser['uid']}'.trim();
    final effectiveUid = uid.isEmpty ? '${_v1PeerUser['uid']}' : uid;
    return _v1DmMessagesByPeer.putIfAbsent(
      effectiveUid,
      () => <Map<String, dynamic>>[],
    );
  }

  Map<String, List<Map<String, dynamic>>> _mockDirectMessageMessagesByPeer() {
    final result = <String, List<Map<String, dynamic>>>{
      '${_v1PeerUser['uid']}': kMockV1DmMessages
          .map((item) => _deepCopyMap(item))
          .toList(growable: true),
    };
    for (var index = 1; index < _v1DirectMessagePeers.length; index += 1) {
      final peer = _v1DirectMessagePeers[index];
      final peerUid = '${peer['uid']}';
      final messageCount = _mockDirectMessageCountForPeerIndex(index);
      result[peerUid] = List<Map<String, dynamic>>.generate(messageCount, (
        messageIndex,
      ) {
        final senderIsPeer = messageIndex.isEven;
        final shortConversation = messageCount <= 2;
        return {
          'msg_id':
              'DM_${peerUid}_${(messageIndex + 1).toString().padLeft(3, '0')}',
          'conv_id': 'DMC_MOCK_${(index + 1).toString().padLeft(3, '0')}',
          'sender_uid': senderIsPeer ? peerUid : _v1User['uid'],
          'receiver_uid': senderIsPeer ? _v1User['uid'] : peerUid,
          'content': shortConversation
              ? _shortDirectMessageContent(index, messageIndex, peer['name'])
              : 'Mock message ${messageIndex + 1} with ${peer['name']}.',
          'created_at': _mockUnixTimestamp(
            DateTime.now().subtract(
              shortConversation
                  ? Duration(minutes: index * 7 + messageCount - messageIndex)
                  : Duration(minutes: (28 - messageIndex) * 11 + index),
            ),
          ),
        };
      }, growable: true);
    }
    return result;
  }

  int _mockDirectMessageCountForPeerIndex(int index) {
    return switch (index) {
      1 => 1,
      2 => 2,
      3 => 1,
      4 => 2,
      _ => 28,
    };
  }

  String _shortDirectMessageContent(
    int peerIndex,
    int messageIndex,
    Object? peerName,
  ) {
    final displayName = '$peerName'.trim().isEmpty
        ? 'this contact'
        : '$peerName';
    if (peerIndex == 1) {
      return 'One-message mock chat with $displayName.';
    }
    if (peerIndex == 2) {
      return messageIndex == 0
          ? 'First short mock message from $displayName.'
          : 'Second short mock reply.';
    }
    if (peerIndex == 3) {
      return 'Single short conversation for layout testing.';
    }
    return messageIndex == 0
        ? 'Tiny two-message thread starts here.'
        : 'And ends here.';
  }

  List<Map<String, dynamic>> _mockDirectMessagePeers() {
    return [
      _v1UserPayload(_v1PeerUser),
      for (var index = 2; index <= 25; index += 1)
        {
          'uid': 'u_mock_dm_${index.toString().padLeft(3, '0')}',
          'name': 'DM Contact $index',
          'avatar': '',
          'bio': 'Mock direct message contact $index.',
          'last_login_at': _mockUnixTimestamp(
            DateTime.utc(2026, 5, (index % 20) + 1, 10),
          ),
          'create_at': _mockUnixTimestamp(
            DateTime.utc(2026, 4, (index % 28) + 1, 8),
          ),
          'follower_cnt': 10 + index,
          'following_cnt': 6 + index,
          'friend_cnt': index % 7,
          'create_origin_cnt': index % 5,
          'launch_world_cnt': index % 4,
          'join_world_cnt': 2 + index,
        },
    ];
  }

  Map<String, dynamic> _mockDirectMessageConversation(int index) {
    final peer = _v1DirectMessagePeers[index];
    final timestamp = _mockUnixTimestamp(
      DateTime.now().subtract(Duration(minutes: index * 23)),
    );
    return {
      'conv_id': 'DMC_MOCK_${(index + 1).toString().padLeft(3, '0')}',
      'peer': _v1UserPayload(peer),
      'last_message_id':
          'DM_MOCK_CONV_${(index + 1).toString().padLeft(3, '0')}',
      'last_message': 'Mock conversation ${index + 1} preview message.',
      'last_message_at': timestamp,
      'last_sender_uid': index.isEven ? peer['uid'] : _v1User['uid'],
      'unread_cnt': index % 4 == 0 ? index % 9 + 1 : 0,
      'is_friend': index.isEven,
      'i_blocked_peer': false,
      'peer_blocked_me': false,
      'can_send_next_message': true,
    };
  }

  void _ensureV1DiscussCoverage() {
    for (final entry in _v1Origins.indexed) {
      final originIndex = entry.$1;
      final origin = entry.$2;
      final oid = '${origin['oid'] ?? ''}'.trim();
      if (oid.isEmpty) continue;

      final existingTopCount = _v1DiscussPosts
          .where((item) => item['biz_type'] == 1 && item['biz_id'] == oid)
          .length;
      for (var slot = existingTopCount; slot < 2; slot++) {
        final comment = _mockV1DiscussPost(
          origin: origin,
          originIndex: originIndex,
          slot: slot,
        );
        _v1DiscussPosts.add(comment);
        _v1DiscussReplies.add(
          _mockV1DiscussReply(
            origin: origin,
            comment: comment,
            originIndex: originIndex,
            slot: slot,
          ),
        );
      }
    }
  }

  Map<String, dynamic> _mockV1DiscussPost({
    required Map<String, dynamic> origin,
    required int originIndex,
    required int slot,
  }) {
    final oid = '${origin['oid']}';
    final title = '${origin['name']}';
    final idPart = _safeDiscussIdPart(oid);
    final author = (originIndex + slot).isEven ? _v1User : _v1PeerUser;
    return {
      'discuss_id': 'dis_mock_auto_${idPart}_$slot',
      'biz_type': 1,
      'biz_id': oid,
      'world_id': _worldIdForOrigin(oid),
      'author': _v1UserPayload(author),
      'content': slot.isEven
          ? '$title 的最新分支很适合继续推进角色关系。'
          : '我在 $title 里补了一条 mock discuss，用来验证列表预览。',
      'images': <String>[],
      'root_discuss_id': '',
      'parent_discuss_id': '',
      'reply_to_uid': '',
      'level': 1,
      'reply_cnt': 1,
      'like_cnt': (originIndex + slot) % 9,
      'is_liked': (originIndex + slot) % 4 == 0,
      'created_at': _mockDiscussTimestamp(originIndex: originIndex, slot: slot),
    };
  }

  Map<String, dynamic> _mockV1DiscussReply({
    required Map<String, dynamic> origin,
    required Map<String, dynamic> comment,
    required int originIndex,
    required int slot,
  }) {
    final oid = '${origin['oid']}';
    final idPart = _safeDiscussIdPart(oid);
    final author = (originIndex + slot).isEven ? _v1PeerUser : _v1User;
    return {
      'discuss_id': 'dis_mock_auto_${idPart}_${slot}_reply',
      'biz_type': 1,
      'biz_id': oid,
      'author': _v1UserPayload(author),
      'content': '收到，这条讨论会出现在 ${origin['name']} 的最新回复里。',
      'images': <String>[],
      'root_discuss_id': comment['discuss_id'],
      'parent_discuss_id': comment['discuss_id'],
      'reply_to_uid':
          '${comment['author'] is Map ? comment['author']['uid'] : ''}',
      'level': 2,
      'reply_cnt': 0,
      'like_cnt': slot,
      'is_liked': false,
      'created_at': _mockDiscussTimestamp(
        originIndex: originIndex,
        slot: slot,
        minuteOffset: 2,
      ),
    };
  }

  Map<String, dynamic> v1DiscussList(Map<String, String> query) {
    final bizType = _positiveInt(query['biz_type'], fallback: 1);
    final bizId = query['biz_id'] ?? '${_v1Origin['oid']}';
    final page = _positiveInt(query['pn'], fallback: 1);
    final pageSize = _positiveInt(query['rn'], fallback: 10);
    final topComments =
        _v1DiscussPosts
            .where(
              (item) =>
                  item['biz_type'] == bizType &&
                  (bizId.isEmpty || item['biz_id'] == bizId),
            )
            .toList()
          ..sort(_compareDiscussCreatedDesc);
    final roots = topComments.map((item) => item['discuss_id']).toSet();
    final replies = _v1DiscussReplies
        .where(
          (item) =>
              item['biz_type'] == bizType &&
              (bizId.isEmpty || item['biz_id'] == bizId) &&
              roots.contains(item['root_discuss_id']),
        )
        .toList();
    final rawStart = (page - 1) * pageSize;
    final start = rawStart > topComments.length ? topComments.length : rawStart;
    final rawEnd = start + pageSize;
    final end = rawEnd > topComments.length ? topComments.length : rawEnd;
    final pageItems = topComments.sublist(start, end);
    return {
      'list': pageItems.map((comment) {
        final enrichedComment = _deepCopyMap(comment);
        enrichedComment.putIfAbsent(
          'world_id',
          () => _worldIdForOrigin('${comment['biz_id'] ?? ''}'),
        );
        return {
          'comment': enrichedComment,
          'latest_replies': _latestV1DiscussReplies('${comment['discuss_id']}'),
        };
      }).toList(),
      'top_total': topComments.length,
      'total_all': topComments.length + replies.length,
      'pn': page,
      'rn': pageSize,
    };
  }

  Map<String, dynamic> v1DiscussReplies(Map<String, String> query) {
    final rootDiscussId = (query['root_discuss_id'] ?? '').trim();
    final page = _positiveInt(query['pn'], fallback: 1);
    final pageSize = _positiveInt(query['rn'], fallback: 20);
    final replies =
        _v1DiscussReplies
            .where((item) => item['root_discuss_id'] == rootDiscussId)
            .toList()
          ..sort(_compareDiscussCreatedDesc);
    final rawStart = (page - 1) * pageSize;
    final start = rawStart > replies.length ? replies.length : rawStart;
    final rawEnd = start + pageSize;
    final end = rawEnd > replies.length ? replies.length : rawEnd;
    return {
      'list': replies.sublist(start, end).map(_deepCopyMap).toList(),
      'total': replies.length,
      'pn': page,
      'rn': pageSize,
    };
  }

  Map<String, dynamic> addV1Discuss(Map<String, dynamic> body) {
    final rootDiscussId = '${body['root_discuss_id'] ?? ''}';
    final isReply = rootDiscussId.trim().isNotEmpty;
    final parentDiscussId = '${body['parent_discuss_id'] ?? ''}'.trim();
    final discussId = 'dis_mock_${DateTime.now().microsecondsSinceEpoch}';
    final parentId = isReply
        ? (parentDiscussId.isEmpty ? rootDiscussId : parentDiscussId)
        : '';
    final parent = _findV1Discuss(parentId);
    final item = {
      'discuss_id': discussId,
      'biz_type': _positiveInt('${body['biz_type'] ?? ''}', fallback: 1),
      'biz_id': '${body['biz_id'] ?? _v1Origin['oid']}',
      'world_id': _worldIdForOrigin('${body['biz_id'] ?? _v1Origin['oid']}'),
      'author': _v1UserPayload(_v1User),
      'content': '${body['content'] ?? ''}',
      'images': body['images'] is List ? body['images'] : <String>[],
      'root_discuss_id': isReply ? rootDiscussId : '',
      'parent_discuss_id': parentId,
      'reply_to_uid':
          '${parent?['author'] is Map ? parent!['author']['uid'] : ''}',
      'level': isReply ? 2 : 1,
      'reply_cnt': 0,
      'like_cnt': 0,
      'is_liked': false,
      'created_at': _mockSqlTimestamp(),
    };
    if (isReply) {
      _v1DiscussReplies.insert(0, item);
      final root = _findV1Discuss(rootDiscussId);
      if (root != null) {
        root['reply_cnt'] = (root['reply_cnt'] as int? ?? 0) + 1;
      }
    } else {
      _v1DiscussPosts.insert(0, item);
      _adjustV1OriginDiscussCount('${item['biz_id']}', 1);
    }
    return {
      'discuss_id': discussId,
      'root_discuss_id': isReply ? rootDiscussId : '',
      'level': isReply ? 2 : 1,
    };
  }

  void likeV1Discuss(String discussId) {
    final item = _findV1Discuss(discussId);
    if (item == null || (item['is_liked'] as bool? ?? false)) return;
    item['is_liked'] = true;
    item['like_cnt'] = (item['like_cnt'] as int? ?? 0) + 1;
  }

  void unlikeV1Discuss(String discussId) {
    final item = _findV1Discuss(discussId);
    if (item == null || !(item['is_liked'] as bool? ?? false)) return;
    item['is_liked'] = false;
    final next = (item['like_cnt'] as int? ?? 0) - 1;
    item['like_cnt'] = next < 0 ? 0 : next;
  }

  void deleteV1Discuss(String discussId) {
    final removedReply = _v1DiscussReplies
        .where((item) => item['discuss_id'] == discussId)
        .toList();
    _v1DiscussReplies.removeWhere((item) => item['discuss_id'] == discussId);
    for (final reply in removedReply) {
      final root = _findV1Discuss('${reply['root_discuss_id']}');
      if (root != null) {
        final next = (root['reply_cnt'] as int? ?? 0) - 1;
        root['reply_cnt'] = next < 0 ? 0 : next;
      }
    }
    final removedTop = _v1DiscussPosts
        .where((item) => item['discuss_id'] == discussId)
        .toList();
    _v1DiscussPosts.removeWhere((item) => item['discuss_id'] == discussId);
    for (final comment in removedTop) {
      _adjustV1OriginDiscussCount('${comment['biz_id']}', -1);
    }
  }

  List<Map<String, dynamic>> _latestV1DiscussReplies(String rootDiscussId) {
    final replies =
        _v1DiscussReplies
            .where((item) => item['root_discuss_id'] == rootDiscussId)
            .toList()
          ..sort(_compareDiscussCreatedDesc);
    return replies.take(3).map(_deepCopyMap).toList();
  }

  List<Map<String, dynamic>> _latestV1OriginDiscusses(String oid) {
    final comments =
        _v1DiscussPosts
            .where(
              (item) =>
                  item['biz_type'] == 1 &&
                  '${item['biz_id'] ?? ''}'.trim() == oid.trim(),
            )
            .toList()
          ..sort(_compareDiscussCreatedDesc);
    return comments.take(2).map((comment) {
      final copy = _deepCopyMap(comment);
      copy.putIfAbsent('review_status', () => 10);
      copy.putIfAbsent('world_id', () => _worldIdForOrigin(oid));
      return copy;
    }).toList();
  }

  bool _isPopularOriginScene(String? scene) {
    final normalized = (scene ?? '').trim();
    return normalized.isEmpty || normalized == 'popular';
  }

  Map<String, dynamic>? _findV1Discuss(String discussId) {
    for (final item in [..._v1DiscussPosts, ..._v1DiscussReplies]) {
      if (item['discuss_id'] == discussId) return item;
    }
    return null;
  }

  String _worldIdForOrigin(String oid) {
    final world = _v1Worlds.cast<Map<String, dynamic>?>().firstWhere(
      (item) => '${item?['oid'] ?? ''}' == oid,
      orElse: () => null,
    );
    return '${world?['wid'] ?? ''}'.trim();
  }

  int _compareDiscussCreatedDesc(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return '${b['created_at']}'.compareTo('${a['created_at']}');
  }

  String _mockSqlTimestamp() {
    return _formatMockDateTime(DateTime.now());
  }

  int _mockUnixTimestamp(DateTime value) {
    return value.millisecondsSinceEpoch ~/ 1000;
  }

  int _mockEpoch(Object? value) {
    if (value is num) return value.toInt();
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return kMockV1NowEpoch;
    return parsed.toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  String _formatMockDateTime(DateTime value) {
    final now = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  String _mockDiscussTimestamp({
    required int originIndex,
    required int slot,
    int minuteOffset = 0,
  }) {
    final day = ((originIndex + slot) % 28) + 1;
    final hour = 8 + ((originIndex + slot) % 10);
    final minute = ((originIndex * 3) + (slot * 11) + minuteOffset) % 60;
    return '2026-05-${day.toString().padLeft(2, '0')} '
        '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}:00';
  }

  String _safeDiscussIdPart(String oid) {
    return oid.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
  }

  void _adjustV1OriginDiscussCount(String originId, int delta) {
    final origin = _v1Origins.firstWhere(
      (item) => item['oid'] == originId,
      orElse: () => <String, dynamic>{},
    );
    if (origin.isEmpty) return;
    final next = (origin['discuss_cnt'] as int? ?? 0) + delta;
    origin['discuss_cnt'] = next < 0 ? 0 : next;
  }

  Map<String, dynamic> v1Search(Map<String, String> query) {
    final raw = query['keyword'] ?? query['query'] ?? '';
    final normalized = raw.trim().toLowerCase();
    final requestedType = (query['type'] ?? '').trim().toLowerCase();
    final page = _positiveInt(query['pn'], fallback: 1);
    final pageSize = _positiveInt(query['rn'], fallback: 20);
    bool matches(Object? value) =>
        normalized.isEmpty || '$value'.toLowerCase().contains(normalized);
    List<Map<String, dynamic>> tagMatches(Object? value) {
      if (normalized.isEmpty || value is! List) {
        return const <Map<String, dynamic>>[];
      }
      final result = <Map<String, dynamic>>[];
      for (var index = 0; index < value.length; index += 1) {
        final tag = '${value[index]}';
        final start = tag.toLowerCase().indexOf(normalized);
        if (start < 0) continue;
        result.add({
          'field': 'tag',
          'tag_index': index,
          'highlight_ranges': [
            {'start': start, 'length': normalized.length},
          ],
        });
      }
      return result;
    }

    final originResults = _v1Origins
        .where(
          (origin) =>
              matches(origin['oid']) ||
              matches(origin['name']) ||
              matches(origin['display_subtitle']) ||
              matches(origin['created_user_name']) ||
              matches((origin['tags'] as List?)?.join(' ')),
        )
        .map((origin) {
          final contract = _v1OriginContractItem(origin);
          final info = _mapFromObject(contract['info']);
          return <String, dynamic>{
            'origin_id': info['origin_id'],
            'origin_name': info['origin_name'],
            'origin_version': info['origin_version'],
            'brief': info['brief'],
            'language': info['language'],
            'cover': info['cover'],
            'tags': info['tags'],
            'characters': _originEditCharacters(origin)
                .map(
                  (character) => <String, dynamic>{
                    'character_id':
                        character['character_id'] ?? character['char_id'] ?? '',
                    'name': character['name'] ?? '',
                  },
                )
                .toList(growable: false),
            'owner': _searchV2Owner(info['owner_user']),
            'stats': contract['stats'],
            'matches': tagMatches(info['tags']),
            'matches_truncated': false,
          };
        })
        .toList();

    final worldResults = _v1Worlds
        .where(
          (world) =>
              matches(world['wid']) ||
              matches(world['name']) ||
              matches(world['display_subtitle']) ||
              matches(world['owner_name']) ||
              matches((world['tags'] as List?)?.join(' ')),
        )
        .map((world) {
          final contract = _v1WorldContractItem(world);
          final info = _mapFromObject(contract['info']);
          final stats = _mapFromObject(contract['stats']);
          final ownerUid = '${info['owner_uid'] ?? ''}';
          return <String, dynamic>{
            'world_id': info['world_id'],
            'world_name': info['world_name'],
            'origin_id': info['origin_id'],
            'language': world['language'] ?? '',
            'cover': info['cover'],
            'tags': world['tags'] ?? const <String>[],
            'owner': _searchV2Owner(
              _contractPublicUser(
                ownerUid,
                fallbackName: '${info['owner_name'] ?? ''}',
              ),
            ),
            'stats': {
              'tick_cnt': stats['tick_cnt'],
              'connect_cnt': stats['connect_cnt'],
              'character_cnt': stats['character_cnt'],
              'player_cnt': stats['player_cnt'],
            },
            'created_at': info['created_at'],
            'matches': tagMatches(world['tags']),
          };
        })
        .toList();

    final userResults = _v1SearchUsers
        .where(
          (item) =>
              matches(item['uid']) ||
              matches(item['name']) ||
              matches(item['bio']) ||
              matches(item['user_code']),
        )
        .map(
          (item) => <String, dynamic>{
            'uid': item['uid'] ?? '',
            'name': item['name'] ?? '',
            'avatar': _mockImageObject(item['avatar']),
            'matches': const <Map<String, dynamic>>[],
          },
        )
        .toList();

    Map<String, dynamic> section(
      String type,
      List<Map<String, dynamic>> items,
    ) {
      final include =
          requestedType.isEmpty ||
          requestedType == 'all' ||
          requestedType == type;
      final visibleItems = include ? items : <Map<String, dynamic>>[];
      return {
        'list': _pageSearchResults(visibleItems, page, pageSize),
        'total': visibleItems.length,
        'pn': page,
        'rn': pageSize,
      };
    }

    return {
      'keyword': raw,
      'type': requestedType == 'all' ? '' : requestedType,
      'origins': section('origin', originResults),
      'worlds': section('world', worldResults),
      'users': section('user', userResults),
    };
  }

  int _positiveInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value ?? '') ?? fallback;
    return parsed < 1 ? fallback : parsed;
  }

  Map<String, dynamic> _searchV2Owner(Object? value) {
    final owner = _mapFromObject(value);
    return <String, dynamic>{
      'uid': owner['uid'] ?? '',
      'name': owner['name'] ?? '',
      'avatar': owner['avatar'] ?? _mockImageObject(''),
    };
  }

  List<Map<String, dynamic>> _pageSearchResults(
    List<Map<String, dynamic>> items,
    int page,
    int pageSize,
  ) {
    final rawStart = (page - 1) * pageSize;
    final start = rawStart > items.length ? items.length : rawStart;
    final rawEnd = start + pageSize;
    final end = rawEnd > items.length ? items.length : rawEnd;
    return items.sublist(start, end).map(_deepCopyMap).toList();
  }

  Map<String, dynamic> _relationForSearchUser(Map<String, dynamic> item) {
    if (item['uid'] == _v1User['uid']) return _deepCopyMap(kMockV1SelfRelation);
    final uid = '${item['uid'] ?? ''}'.trim();
    return {
      ..._deepCopyMap(kMockV1PeerRelation),
      'target_user_id': item['uid'],
      'is_followed': item['is_followed'] ?? item['i_followed'] ?? false,
      'i_followed': item['i_followed'] ?? false,
      'followed_me': item['followed_me'] ?? false,
      'is_friend': item['is_friend'] ?? false,
      'is_blocked': uid.isNotEmpty && _v1BlockedUsers.contains(uid),
      'follow_button_state': item['follow_button_state'] ?? 'follow',
    };
  }

  Map<String, dynamic> v1SearchSuggest(Map<String, String> query) {
    final result = v1Search(query);
    final sections = [result['origins'], result['worlds'], result['users']];
    return {
      'list': sections
          .expand((section) => ((section as Map)['list'] as List))
          .cast<Map<String, dynamic>>()
          .take(int.tryParse(query['limit'] ?? '') ?? 10)
          .map(_deepCopyMap)
          .toList(),
    };
  }

  Map<String, dynamic> v1Home() {
    return {
      'default_tab': 'my_world',
      'my_world': {'list': v1WorldSummaries()},
      'popular': {'list': v1OriginSummaries()},
      'following': {'list': v1FollowingFeed()},
    };
  }

  List<Map<String, dynamic>> v1FollowingFeed() {
    return [
      {
        'event_type': 'world_launch',
        'event_time': kMockV1Now,
        'actor': _v1UserPayload(_v1PeerUser),
        'target': {
          'oid': _v1Origin['oid'],
          'wid': _v1World['wid'],
          'name': _v1World['name'],
          'cover': _mockImageObject(_v1World['cover']),
          'tick_cnt': _v1World['tick_cnt'],
        },
        'summary': 'Penny launched a local mock world.',
      },
    ];
  }

  Map<String, dynamic> saveV1Draft(Map<String, dynamic> body) {
    final draftType = '${body['draft_type'] ?? 'origin_create'}';
    final draftId =
        '${body['draft_id'] ?? 'draft_${DateTime.now().millisecondsSinceEpoch}'}';
    final draft = {
      'draft_id': draftId,
      'draft_type': draftType,
      'draft_data': body['draft_data'] is Map ? body['draft_data'] : {},
      'update_time': DateTime.now().toUtc().toIso8601String(),
      'expire_time': DateTime.now()
          .toUtc()
          .add(const Duration(days: 7))
          .toIso8601String(),
    };
    _v1Drafts[draftType] = _deepCopyMap(draft);
    return _deepCopyMap(draft);
  }

  Map<String, dynamic>? readV1Draft(String? draftType) {
    return _deepCopyMap(
      _v1Drafts[draftType ?? 'origin_create'] ??
          {
            'draft_id': 'draft_mock_default',
            'draft_type': draftType ?? 'origin_create',
            'draft_data': {'name': 'Draft Steam Kingdom'},
            'update_time': kMockV1Now,
            'expire_time': '2026-05-27T10:00:00Z',
          },
    );
  }

  void deleteV1Draft(String draftId) {
    _v1Drafts.removeWhere((_, draft) => draft['draft_id'] == draftId);
  }

  List<Map<String, dynamic>> _originEditCharacters(
    Map<String, dynamic> origin,
  ) {
    final stored = origin['_edit_characters'];
    if (stored is List) {
      return stored
          .map((item) => _deepCopyMap(_mapFromObject(item)))
          .toList(growable: false);
    }
    return kMockV1Characters.map(_deepCopyMap).toList(growable: false);
  }

  List<Map<String, dynamic>> _originEditLocations(Map<String, dynamic> origin) {
    final stored = origin['_edit_locations'];
    if (stored is List) {
      return stored
          .map((item) => _deepCopyMap(_mapFromObject(item)))
          .toList(growable: false);
    }
    return kMockV1Locations.map(_deepCopyMap).toList(growable: false);
  }

  List<String> _originEditEvents(Map<String, dynamic> origin) {
    final stored = origin['_edit_events'];
    if (stored is List) {
      return stored
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return kMockV1Events
        .map((event) => '${event['content'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _originContractTicks(Map<String, dynamic> origin) {
    return kMockV1Ticks
        .map((tick) {
          final contracted = _contractTick(tick);
          final result = _mapFromObject(contracted['tick_result']);
          result.remove('location_groups');
          final paragraphs = result['paragraphs'];
          if (paragraphs is List) {
            result['paragraphs'] = paragraphs
                .map((paragraph) {
                  final normalized = _mapFromObject(paragraph);
                  normalized['character_deltas'] =
                      const <Map<String, dynamic>>[];
                  return normalized;
                })
                .toList(growable: false);
          }
          contracted['tick_result'] = result;
          return contracted;
        })
        .toList(growable: false);
  }

  Map<String, dynamic>? _originContractInitLocationGroup(
    Map<String, dynamic> origin,
  ) {
    final stored = origin['init_location_group'];
    if (stored is Map) {
      final normalized = _normalizeOriginInitLocationGroup(
        origin,
        _mapFromObject(stored),
      );
      if (normalized != null) return normalized;
    }

    final locations = _originEditLocations(origin).toList(growable: false)
      ..sort(
        (left, right) => '${left['location_id'] ?? ''}'.compareTo(
          '${right['location_id'] ?? ''}',
        ),
      );
    for (final location in locations) {
      final normalized = _normalizeOriginInitLocationGroup(origin, {
        'location_id': location['location_id'],
        'initial_dialogue': location['dialogue'],
      });
      if (normalized != null) return normalized;
    }
    return null;
  }

  Map<String, dynamic>? _normalizeOriginInitLocationGroup(
    Map<String, dynamic> origin,
    Map<String, dynamic> group,
  ) {
    final locationId = '${group['location_id'] ?? ''}'.trim();
    final rawDialogue = group['initial_dialogue'] ?? group['dialogue'];
    if (locationId.isEmpty || rawDialogue is! List) return null;

    final charactersById = <String, String>{
      for (final character in _originEditCharacters(origin))
        '${character['character_id'] ?? character['char_id'] ?? ''}'.trim():
            '${character['name'] ?? ''}'.trim(),
    }..remove('');
    final dialogue = rawDialogue
        .whereType<Map>()
        .map((rawLine) {
          final line = _mapFromObject(rawLine);
          final charId = '${line['char_id'] ?? ''}'.trim();
          final content = '${line['content'] ?? ''}';
          if (charId.isEmpty || content.trim().isEmpty) return null;
          final normalizedType = charId.toLowerCase();
          final generatedName =
              normalizedType == 'nar' || normalizedType == 'nar_pic'
              ? 'Narrator'
              : charactersById[charId] ?? '';
          return <String, dynamic>{
            'char_id': charId,
            'char_name': generatedName,
            'content': content,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    if (dialogue.isEmpty) return null;
    return {'location_id': locationId, 'initial_dialogue': dialogue};
  }

  Map<String, dynamic> _originDetailPayload(Map<String, dynamic> origin) {
    return {
      'origin': _v1OriginPayload(origin),
      'character_list': _originEditCharacters(origin),
      'metric': _deepCopyMap(kMockV1Metric),
      'location_list': _originEditLocations(origin),
      'event_list': _originEditEvents(
        origin,
      ).map((content) => <String, dynamic>{'content': content}).toList(),
    };
  }

  Map<String, dynamic> _v1OriginSummary(Map<String, dynamic> origin) {
    return {
      'oid': origin['oid'],
      'status': origin['status'],
      'version_num': origin['version_num'],
      'name': origin['name'],
      'cover': _mockImageObject(origin['cover']),
      'display_subtitle': origin['display_subtitle'],
      'world_view': origin['world_view'],
      'created_uid': origin['created_uid'],
      'created_user_name': origin['created_user_name'],
      'created_at': origin['created_at'],
      'updated_at': origin['updated_at'],
      'tags': origin['tags'],
      'copy_cnt': origin['copy_cnt'],
      'connect_cnt': origin['connect_cnt'],
      'discuss_cnt': origin['discuss_cnt'],
      'character_cnt': origin['character_cnt'],
      'location_cnt': origin['location_cnt'],
    };
  }

  Map<String, dynamic> _v1WorldSummary(Map<String, dynamic> world) {
    return {
      'oid': world['oid'],
      'origin_version_num': world['origin_version_num'],
      'origin_version_create_at': world['origin_version_create_at'],
      'wid': world['wid'],
      'status': world['status'],
      'name': world['name'],
      'cover': _mockImageObject(world['cover']),
      'display_subtitle': world['display_subtitle'],
      'created_uid': world['created_uid'],
      'created_user_name': world['created_user_name'],
      'owner_uid': world['owner_uid'],
      'owner_name': world['owner_name'],
      'created_at': world['created_at'],
      'updated_at': world['updated_at'],
      'last_progress_at': world['last_progress_at'],
      'last_tick': {
        'tick_no': world['tick_cnt'],
        'tick_index': world['tick_cnt'],
        'current_time': 'Day ${world['tick_cnt'] ?? 1}, 08:00',
        'created_at': world['last_progress_at'],
        'narrator': world['last_progress_summary'],
        'paragraphs': const <Map<String, dynamic>>[],
      },
      'tags': world['tags'],
      'tick_cnt': world['tick_cnt'],
      'connect_cnt': world['connect_cnt'],
      'ai_character_cnt': world['ai_character_cnt'],
      'player_cnt': world['player_cnt'],
      'location_cnt': world['location_cnt'],
    };
  }

  Map<String, dynamic> _v1OriginContractItem(Map<String, dynamic> origin) {
    final ownerUid = '${origin['owner_uid'] ?? origin['created_uid'] ?? ''}';
    final ownerName =
        '${origin['owner_name'] ?? origin['created_user_name'] ?? ''}';
    return {
      'info': {
        'origin_id': origin['oid'],
        'origin_name': origin['name'],
        'origin_version': '${origin['version_num'] ?? 1}',
        'origin_version_time': _mockEpoch(origin['updated_at']),
        'definition_version': origin['definition_version'] ?? 2,
        'default_map_location_id': origin['default_map_location_id'] ?? 'root',
        'language': origin['language'] ?? 'en',
        'current_time': origin['current_time'] ?? 'Day 3, 09:20',
        'owner_uid': ownerUid,
        'owner_name': ownerName,
        'owner_user': _contractPublicUser(ownerUid, fallbackName: ownerName),
        'brief': origin['display_subtitle'],
        'setting': origin['world_setting'],
        'events': _originEditEvents(origin),
        'tags': origin['tags'],
        'metric': origin['metric'] is Map
            ? _deepCopyMap(_mapFromObject(origin['metric']))
            : _deepCopyMap(kMockV1Metric),
        'created_at': _mockEpoch(origin['created_at']),
        'started_at': origin['start_time'],
        'tick_duration_days': origin['tick_duration_days'],
        'cover': _mockImageObject(origin['cover']),
        'map_url': origin['map_url'] ?? origin['cover'],
        'status': asInt(origin['status']) == 20 ? 20 : 10,
      },
      'stats': {
        'copy_cnt': origin['copy_cnt'],
        'discuss_cnt': origin['discuss_cnt'],
        'character_cnt': origin['character_cnt'],
        'connect_cnt': origin['connect_cnt'],
        'location_cnt': origin['location_cnt'],
        'max_tick_cnt': origin['max_tick_cnt'] ?? origin['tick_cnt'] ?? 0,
      },
    };
  }

  Map<String, dynamic> _v1WorldContractItem(Map<String, dynamic> world) {
    return {
      'info': {
        'world_id': world['wid'],
        'world_name': world['name'],
        'origin_id': world['oid'],
        'origin_version': '${world['origin_version_num'] ?? 1}',
        'origin_version_time': world['origin_version_create_at'],
        'definition_version': world['definition_version'] ?? 2,
        'default_map_location_id': world['default_map_location_id'] ?? 'root',
        'owner_uid': world['owner_uid'],
        'owner_name': world['owner_name'],
        'brief': world['display_subtitle'],
        'setting': world['world_setting'],
        'events': kMockV1Events.map((event) => event['content']).toList(),
        'metric': _deepCopyMap(kMockV1Metric),
        'created_at': _mockEpoch(world['created_at']),
        'last_active_at': _mockEpoch(
          world['last_active_at'] ??
              world['last_progress_at'] ??
              world['updated_at'],
        ),
        'started_at': '${world['created_at']}',
        'tick_duration_days': 30,
        'cover': _mockImageObject(world['cover']),
        'map_url': world['map_url'] ?? world['cover'],
        'status': world['status'],
      },
      'stats': {
        'character_cnt': world['ai_character_cnt'],
        'connect_cnt': world['connect_cnt'],
        'location_cnt': world['location_cnt'],
        'tick_cnt': world['tick_cnt'],
        'player_cnt': world['player_cnt'],
      },
    };
  }

  Map<String, dynamic> _contractCharacter(Map<String, dynamic> character) {
    final playerUid = '${character['player_uid'] ?? ''}'.trim();
    final playerUser = _contractPublicUser(
      playerUid,
      fallbackName: '${character['player_username'] ?? ''}',
    );
    final rawType = '${character['type'] ?? 'ai'}'.trim().toLowerCase();
    return {
      'char_id': character['character_id'] ?? character['char_id'],
      'type': rawType == 'custom' || rawType == 'player' ? 'custom' : 'ai',
      'player_uid': playerUid,
      'player_username': playerUid.isEmpty
          ? ''
          : '${character['player_username'] ?? playerUser['name'] ?? ''}',
      'player_user': playerUser,
      'player_joined_at': playerUid.isEmpty
          ? 0
          : character['player_joined_at'] ?? kMockV1NowEpoch,
      'name': character['name'],
      'identity': character['identity'],
      'brief': character['tagline'] ?? character['personality'],
      'description': character['description'] ?? character['bio'],
      'goal': character['goal'],
      'avatar': _mockImageObject(character['avatar']),
      'initial_location_id':
          character['initial_location_id'] ?? character['location_id'] ?? '',
      'location_id':
          character['location_id'] ?? character['initial_location_id'] ?? '',
      'metric_value': character['metric_value'] ?? 0,
      'delta': character['delta'] ?? 0,
    };
  }

  Map<String, dynamic> _contractOriginDetailCharacter(
    Map<String, dynamic> character,
  ) {
    final contract = _contractCharacter(character);
    contract.remove('description');
    return {
      ...contract,
      'type': 'ai',
      'player_uid': '',
      'player_username': '',
      'player_user': _contractPublicUser(''),
      'player_joined_at': 0,
      'is_recommend': asInt(character['is_recommend']),
    };
  }

  Map<String, dynamic> _contractLocation(
    Map<String, dynamic> location, {
    bool includeLocationDescription = true,
  }) {
    return {
      'location_id': location['location_id'],
      'level': location['level'] ?? 1,
      'location_pid': location['location_pid'] ?? '',
      'location_name': location['location_name'] ?? location['name'],
      if (includeLocationDescription)
        'location_description':
            location['location_description'] ?? location['description'],
      'location_paragraph': location['location_paragraph'] ?? '',
      'location_timestamp': location['location_timestamp'] ?? '',
      'location_summary':
          location['location_summary'] ?? location['description'] ?? '',
      'image': _mockImageObject(location['image']),
      'x_percent': location['x_percent'],
      'y_percent': location['y_percent'],
      'x': location['x'] ?? 0.0,
      'y': location['y'] ?? 0.0,
      'map_url': location['map_url'] ?? location['image'],
      'dialogue': location['dialogue'] ?? const <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _v1TilemapDefinition(String locationId) {
    return {
      'tile_types': {
        'mock_tile': 'https://cdn.example.com/tilemap/mock_tile.png',
      },
      'map_json': {
        'width': 1,
        'height': 1,
        'tiles': <Object?>[
          <String, Object?>{
            'x': 0,
            'y': 0,
            'type': 'mock_tile',
            'shadow': 0,
            if (locationId == 'root') 'location_id': 'loc_hub',
          },
        ],
      },
    };
  }

  List<Map<String, dynamic>> _v1WorldTicks(Map<String, dynamic> world) {
    final worldId = '${world['wid'] ?? ''}'.trim();
    return _v1TicksByWorld.putIfAbsent(
      worldId,
      () => kMockV1Ticks.map(_contractTick).toList(growable: true),
    );
  }

  Map<String, dynamic> _contractTick(Map<String, dynamic> tick) {
    final paragraphs = tick['paragraphs'] is List
        ? (tick['paragraphs'] as List)
              .map((item) {
                final paragraph = item is Map
                    ? Map<String, dynamic>.from(item)
                    : const <String, dynamic>{};
                return {
                  'location_id': paragraph['location_id'] ?? 'loc_hub',
                  'timestamp':
                      paragraph['timestamp'] ??
                      tick['created_at'] ??
                      kMockV1Now,
                  'text': paragraph['text'] ?? tick['summary'] ?? '',
                  'visibility': paragraph['visibility'] ?? 'public',
                  'visible_to': paragraph['visible_to'] ?? const <String>[],
                  'clue': paragraph['clue'] ?? '',
                  'character_deltas':
                      paragraph['character_deltas'] ??
                      const <Map<String, dynamic>>[],
                };
              })
              .toList(growable: false)
        : [
            {
              'location_id': 'loc_hub',
              'timestamp': tick['created_at'] ?? kMockV1Now,
              'text': tick['summary'] ?? '',
              'visibility': 'public',
              'visible_to': const <String>[],
              'clue': '',
              'character_deltas': const <Map<String, dynamic>>[],
            },
          ];
    return {
      'tick_id': 'tick_mock_${tick['tick_no'] ?? 1}',
      'tick_no': tick['tick_no'] ?? 1,
      'sub_tick_no': tick['sub_tick_no'] ?? 1,
      'status': tick['status'] ?? 50,
      'created_at': _mockEpoch(tick['created_at']),
      'tick_result': {
        'current_time':
            tick['current_time'] ?? 'Day ${tick['tick_no'] ?? 1}, 09:00',
        'narrator': tick['summary'] ?? '',
        'paragraphs': paragraphs,
        'location_groups': const <Map<String, dynamic>>[],
      },
    };
  }

  Map<String, dynamic> _contractPublicUser(
    String uid, {
    String fallbackName = '',
  }) {
    if (uid.trim().isEmpty) {
      return {
        'uid': '',
        'name': '',
        'avatar': _mockImageObject(''),
        'deleted': false,
        'follower_cnt': 0,
        'following_cnt': 0,
        'friend_cnt': 0,
        'create_origin_cnt': 0,
        'launch_world_cnt': 0,
        'join_world_cnt': 0,
      };
    }
    final user = _v1UserPayload(_v1UserForUid(uid));
    return {
      'uid': uid,
      'name': '${user['name'] ?? fallbackName}',
      'avatar': user['avatar'] ?? _mockImageObject(''),
      'deleted': user['deleted'] ?? false,
      'follower_cnt': user['follower_cnt'] ?? 0,
      'following_cnt': user['following_cnt'] ?? 0,
      'friend_cnt': user['friend_cnt'] ?? 0,
      'create_origin_cnt': user['create_origin_cnt'] ?? 0,
      'launch_world_cnt': user['launch_world_cnt'] ?? 0,
      'join_world_cnt': user['join_world_cnt'] ?? 0,
    };
  }

  Map<String, dynamic> _findV1Origin(String? oid) {
    if (oid == null || oid.isEmpty) return _v1Origin;
    return _v1Origins.firstWhere(
      (item) => item['oid'] == oid,
      orElse: () => {..._v1Origin, 'oid': oid},
    );
  }

  Map<String, dynamic> _findV1World(String? wid) {
    if (wid == null || wid.isEmpty) return _v1World;
    return _v1Worlds.firstWhere(
      (item) => item['wid'] == wid,
      orElse: () => {..._v1World, 'wid': wid},
    );
  }

  bool hasV1World(String wid) {
    final resolvedWorldId = wid.trim();
    return resolvedWorldId.isNotEmpty &&
        _v1Worlds.any((item) => item['wid'] == resolvedWorldId);
  }

  void _ensureChatroomMessages() {
    if (_chatroomMessages.isNotEmpty) return;
    final worldId = _resolveChatroomWorldId('');
    final seed = <Map<String, Object?>>[
      {
        'location_id': 'loc_hub',
        'conversation_round_id': 100,
        'round_order': 1,
        'sender_type': 'user',
        'sender_id': 'player1',
        'sender_name': 'Mock User',
        'user_id': 'u_mock_001',
        'content': '大家好',
        'created_at': '2026-05-29 10:00:00',
      },
      {
        'location_id': 'loc_hub',
        'conversation_round_id': 100,
        'round_order': 2,
        'sender_type': 'character',
        'sender_id': 'c_mock_iris',
        'sender_name': 'Iris Vale',
        'user_id': '',
        'content': '你好呀',
        'created_at': '2026-05-29 10:00:05',
      },
      {
        'location_id': 'loc_gate',
        'conversation_round_id': 101,
        'round_order': 1,
        'sender_type': 'narrator',
        'sender_id': 'nar',
        'sender_name': '旁白',
        'user_id': '',
        'content': '夜幕降临...',
        'created_at': '2026-05-29 11:00:00',
      },
    ];
    for (final item in seed) {
      _chatroomMessages.add(
        _newChatroomMessage(
          worldId: worldId,
          locationId: '${item['location_id']}',
          conversationRoundId: item['conversation_round_id'] as int,
          roundOrder: item['round_order'] as int,
          senderType: '${item['sender_type']}',
          senderId: '${item['sender_id']}',
          senderName: '${item['sender_name']}',
          userId: '${item['user_id']}',
          content: '${item['content']}',
          createdAt: '${item['created_at']}',
        ),
      );
    }
  }

  String _resolveChatroomWorldId(String worldId) {
    final trimmed = worldId.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return '${_v1World['wid']}';
  }

  List<Map<String, dynamic>> _chatroomMessagesForWorld(String worldId) {
    _ensureChatroomMessages();
    final resolved = _resolveChatroomWorldId(worldId);
    return _chatroomMessages
        .where((message) => message['world_id'] == resolved)
        .map(_deepCopyMap)
        .toList(growable: false);
  }

  Map<String, dynamic> _newChatroomMessage({
    required String worldId,
    required String locationId,
    required int conversationRoundId,
    required int roundOrder,
    required String senderType,
    required String senderId,
    required String senderName,
    required String userId,
    required String content,
    String messageType = 'text',
    int tickNo = 0,
    int subTickNo = 0,
    int? locationMessageId,
    String? createdAt,
    String businessType = '',
    String streamType = '',
    String clientMsgId = '',
    int minAppVersion = 0,
    Map<String, Object?>? v2Payload,
  }) {
    final resolvedWorldId = _resolveChatroomWorldId(worldId);
    final messageId = ++_chatroomMessageSeq;
    final locationSeqKey = '$resolvedWorldId::$locationId';
    final resolvedLocationMessageId =
        locationMessageId ??
        ((_chatroomLocationMessageSeq[locationSeqKey] ?? 100) + 1);
    if (locationMessageId == null) {
      _chatroomLocationMessageSeq[locationSeqKey] = resolvedLocationMessageId;
    }
    return {
      'global_message_id': messageId,
      'message_id': messageId,
      'location_message_id': resolvedLocationMessageId,
      'world_id': resolvedWorldId,
      'location_id': locationId,
      'conversation_round_id': conversationRoundId,
      'round_order': roundOrder,
      'tick_no': tickNo,
      if (subTickNo > 0) 'sub_tick_no': subTickNo,
      'sender_type': senderType,
      'sender_id': senderId,
      'sender_name': senderName,
      'user_id': userId,
      'content': content,
      'message_type': messageType,
      'current_time': '',
      'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
      if (businessType.isNotEmpty) 'type': businessType,
      if (streamType.isNotEmpty) 'stream_type': streamType,
      if (clientMsgId.isNotEmpty) 'client_msg_id': clientMsgId,
      'min_app_version': minAppVersion,
      if (v2Payload != null) 'v2_payload': v2Payload,
    };
  }

  Map<String, dynamic> _chatroomResponseMessage(Map<String, dynamic> message) {
    final copy = _deepCopyMap(message);
    copy.remove('world_id');
    copy.remove('round_order');
    copy.remove('type');
    copy.remove('stream_type');
    copy.remove('v2_payload');
    copy.remove('min_app_version');
    if (isChatroomTimelinePayloadSenderType(copy['sender_type']) &&
        copy['sender_type'] != chatroomUserEnterLocationSenderType) {
      copy['location_id'] = '';
    }
    return copy;
  }

  Map<String, dynamic> _chatroomV2ResponseMessage(
    Map<String, dynamic> message,
  ) {
    final senderType = asString(message['sender_type']);
    final senderId = asString(message['sender_id']);
    final createdAt = asString(message['created_at']);
    final storedPayload = message['v2_payload'];
    final payload = storedPayload is Map
        ? _deepCopyMap(asJsonMap(storedPayload))
        : <String, dynamic>{'content': asString(message['content'])};
    return <String, dynamic>{
      'type': _chatroomV2BusinessType(senderType, senderId, message['type']),
      'stream_type': asString(message['stream_type']),
      'ts': asInt(
        message['ts'],
        fallback:
            DateTime.tryParse(createdAt)?.millisecondsSinceEpoch ??
            asInt(message['message_id']),
      ),
      'world_id': asString(message['world_id']),
      'location_id': asString(message['location_id']),
      if (asString(message['session_id']).isNotEmpty)
        'session_id': asString(message['session_id']),
      'global_message_id': asInt(message['global_message_id']),
      'message_id': asInt(message['message_id']),
      'location_message_id': asInt(message['location_message_id']),
      'conversation_round_id': asInt(message['conversation_round_id']),
      'sender_type': senderType,
      'sender_id': senderId,
      'sender_name': asString(message['sender_name']),
      'user_id': asString(message['user_id']),
      if (asString(message['client_msg_id']).isNotEmpty)
        'client_msg_id': asString(message['client_msg_id']),
      'message_type': asString(message['message_type'], fallback: 'text'),
      'min_app_version': asInt(message['min_app_version']),
      'created_at': createdAt,
      'payload': payload,
      'err_no': 0,
      'err_msg': '',
    };
  }

  Map<String, dynamic> _findV1WorldApply(String? applyId) {
    final id = (applyId ?? '').trim();
    for (final apply in _v1WorldApplies) {
      if (id.isEmpty || apply['apply_id'] == id) return apply;
    }
    final apply = _newV1WorldApply(
      applyId: id.isEmpty
          ? 'apl_mock_${(++_v1WorldApplySeq).toString().padLeft(3, '0')}'
          : id,
      worldId: '${_v1World['wid']}',
    );
    _v1WorldApplies.add(apply);
    return apply;
  }

  Map<String, dynamic> _newV1WorldApply({
    required String applyId,
    required String worldId,
    String? message,
  }) {
    return {
      'apply_id': applyId,
      'world_id': worldId,
      'applicant_uid': _v1User['uid'],
      'message': message ?? '',
      'status': 10,
      'reviewer_uid': '',
      'review_msg': '',
      'reviewed_at': 0,
      'joined_at': 0,
      'created_at': _unixSeconds(),
    };
  }

  int _unixSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

String _chatroomV2BusinessType(
  String senderType,
  String senderId,
  Object? storedType,
) {
  final normalizedSenderType = senderType.trim().toLowerCase();
  if (normalizedSenderType == 'narrator') {
    return const <String>{
          'nar',
          'nar_pic',
        }.contains(senderId.trim().toLowerCase())
        ? 'narrator'
        : 'character';
  }
  final explicitType = asString(storedType).trim().toLowerCase();
  if (explicitType.isNotEmpty) return explicitType;
  return normalizedSenderType.isEmpty ? 'character' : normalizedSenderType;
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    result[key] = _deepCopyValue(value);
  });
  return result;
}

Map<String, dynamic> _mapFromObject(Object? source) {
  if (source is Map<String, dynamic>) return source;
  if (source is Map) return source.map((key, value) => MapEntry('$key', value));
  return const <String, dynamic>{};
}

int? _tickDurationDaysFromOriginCreateBody(Map<String, dynamic> body) {
  if (body['tick_duration_days'] is num) {
    return (body['tick_duration_days'] as num).toInt();
  }
  final value = '${body['tick_duration_time'] ?? ''}'.trim();
  if (value.isEmpty) return null;
  return int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '');
}

List<dynamic> _deepCopyList(List<dynamic> source) {
  return source.map(_deepCopyValue).toList(growable: true);
}

List<Map<String, dynamic>> _expandMockV1Origins() {
  const names = [
    '重生归来做首富',
    '重生 2005',
    'Steam Kingdom',
    'Neon Harbor',
    'Verdant Academy',
    'Dust Radio',
    'Moonlit Diner',
    'Glass Orchard',
    'Paper Armada',
    'Signal Monastery',
    'Copper Carnival',
    'Aurora Market',
  ];
  const subtitles = [
    '重生后从一间小公司开始逆袭都市商战，在资本围猎、旧友背叛和时代风口之间重新改写命运。',
    '老肖回到 2005 的创业线，带着未来记忆修正家庭遗憾、抢占产业窗口，并面对更早到来的竞争者。',
    kMockV1SteamSubtitle,
    kMockV1NeonSubtitle,
    kMockV1VerdantSubtitle,
    kMockV1DustSubtitle,
    kMockV1MoonlitSubtitle,
    'Transparent forest intrigue where every orchard branch shows a different possible betrayal before the morning council convenes.',
    'Fleet of folded cities sailing across paper seas while captains bargain with storms, cartographers, and runaway districts.',
    'Quiet mountain transmissions from a signal monastery where novice operators decode prophecies hidden inside static.',
    'Festival below old factories where performers, workers, and forgotten machines compete to control the final night parade.',
    'Polar bazaar of wishes where aurora merchants price every miracle against memory, warmth, and unfinished promises.',
  ];
  const tagPairs = [
    ['重生', '商战'],
    ['老肖', '年代'],
    ['steampunk', 'politics'],
    ['cyberpunk', 'mystery'],
    ['fantasy', 'academy'],
    ['survival', 'roadtrip'],
    ['slice-of-life', 'supernatural'],
    ['nature', 'intrigue'],
    ['naval', 'city'],
    ['monastery', 'signal'],
    ['festival', 'industrial'],
    ['aurora', 'market'],
  ];

  return List<Map<String, dynamic>>.generate(100, (index) {
    final base = kMockV1Origins[index % kMockV1Origins.length];
    final name = names[index % names.length];
    final subtitle = subtitles[index % subtitles.length];
    final seq = index + 1;
    return {
      ...base,
      'oid': 'o_mock_${seq.toString().padLeft(3, '0')}',
      'version_num': 1 + (index % 5),
      'name': '$name ${seq.toString().padLeft(2, '0')}',
      'display_subtitle': subtitle,
      'world_view': '$subtitle story seed #$seq, shaped by scene ${index % 7}.',
      'world_setting':
          'Players explore ${name.toLowerCase()} with conflict layer ${index % 9}.',
      'created_uid': index.isEven ? 'u_mock_001' : 'u_mock_peer',
      'created_user_name': index.isEven ? 'Mock User' : 'Penny Hardaway',
      'created_at':
          '2026-04-${((index % 28) + 1).toString().padLeft(2, '0')}T08:00:00Z',
      'updated_at':
          '2026-05-${((index % 20) + 1).toString().padLeft(2, '0')}T10:00:00Z',
      'tags': tagPairs[index % tagPairs.length],
      'copy_cnt': _mockStatCount(index, offset: 0),
      'connect_cnt': _mockStatCount(index, offset: 3),
      'discuss_cnt': _mockStatCount(index, offset: 1),
      'character_cnt': _mockStatCount(index, offset: 2),
      'location_cnt': _mockStatCount(index, offset: 4),
      'start_time': 'Day ${(index % 12) + 1} 08:00',
      'tick_duration_days': 7 + (index % 30),
    };
  });
}

List<Map<String, dynamic>> _expandMockV1Worlds() {
  final origins = _expandMockV1Origins();
  const suffixes = [
    'Live',
    'Night Shift',
    'Term One',
    'Caravan',
    'Regulars',
    'Expedition',
    'Council',
    'After Hours',
    'Crossroads',
    'Archive',
  ];

  return List<Map<String, dynamic>>.generate(100, (index) {
    final base = kMockV1Worlds[index % kMockV1Worlds.length];
    final origin = origins[index];
    final seq = index + 1;
    final suffix = suffixes[index % suffixes.length];
    return {
      ...base,
      'oid': origin['oid'],
      'origin_version_num': origin['version_num'],
      'origin_version_create_at': origin['created_at'],
      'wid': 'w_mock_${seq.toString().padLeft(3, '0')}',
      'status': 1,
      'is_join': index % 3 == 0 ? 0 : 1,
      'apply_status': index % 3 == 0 ? 'none' : 'success',
      'name': '${origin['name']} $suffix',
      'display_subtitle': origin['display_subtitle'],
      'world_view': origin['world_view'],
      'world_setting': origin['world_setting'],
      'created_uid': origin['created_uid'],
      'created_user_name': origin['created_user_name'],
      'owner_uid': origin['created_uid'],
      'owner_name': origin['created_user_name'],
      'created_at':
          '2026-05-${((index % 20) + 1).toString().padLeft(2, '0')}T09:00:00Z',
      'updated_at':
          '2026-05-${((index % 20) + 1).toString().padLeft(2, '0')}T18:00:00Z',
      'last_progress_at':
          '2026-05-${((index % 20) + 1).toString().padLeft(2, '0')}T18:00:00Z',
      'last_progress_summary':
          'Mock world #$seq progressed through ${origin['display_subtitle']}.',
      'tags': origin['tags'],
      'tick_cnt': _mockStatCount(index, offset: 0),
      'connect_cnt': _mockStatCount(index, offset: 3),
      'ai_character_cnt': _mockStatCount(index, offset: 2),
      'player_cnt': _mockStatCount(index, offset: 1),
      'location_cnt': _mockStatCount(index, offset: 4),
    };
  });
}

int _mockStatCount(int index, {required int offset}) {
  const samples = [
    2300,
    18500,
    240000,
    4400000,
    12300000,
    980000000,
    2500000000,
    7300000000000,
  ];
  return samples[(index + offset) % samples.length];
}

List<Map<String, dynamic>> _expandMockV1SearchUsers() {
  const names = [
    '老肖',
    '肖老板',
    'Penny Hardaway',
    'Mock User',
    'Iris Vale',
    'Marshal Crow',
    'Lena Gearwright',
    'Noah Signal',
    'Mira Glass',
    'Otto Fold',
    'Sage Greenhouse',
    'Vera Nightport',
    'Kai Copper',
    'June Aurora',
  ];
  const bios = [
    '重生故事线的核心玩家，擅长经营和决策。',
    '老肖账号，用于搜索页中文用户结果调试。',
    'Writes origin prompts for clockwork frontier stories.',
    'Builds cozy worlds and tests local search flows.',
    'Collects botanical mysteries and academy rumors.',
    'Runs survival scenes across long desert routes.',
    'Curates supernatural slice-of-life diners.',
    'Maps transparent forests and quiet signal towers.',
    'Launches paper cities into collaborative worlds.',
    'Tracks market wishes under polar lights.',
  ];

  return List<Map<String, dynamic>>.generate(72, (index) {
    final seq = index + 1;
    final isSelf = index == 0;
    final isPeer = index == 1;
    final uid = isSelf
        ? kMockV1User['uid'] as String
        : isPeer
        ? kMockV1PeerUser['uid'] as String
        : 'u_mock_search_${seq.toString().padLeft(3, '0')}';
    final name = isSelf
        ? kMockV1User['name'] as String
        : isPeer
        ? kMockV1PeerUser['name'] as String
        : '${names[index % names.length]} ${seq.toString().padLeft(2, '0')}';
    return {
      'uid': uid,
      'user_code': 'U_${seq.toString().padLeft(5, '0')}',
      'name': name,
      'avatar': '',
      'bio': '${bios[index % bios.length]} #$seq',
      'last_login_at':
          '2026-05-${((index % 20) + 1).toString().padLeft(2, '0')}T10:00:00Z',
      'create_at':
          '2026-04-${((index % 28) + 1).toString().padLeft(2, '0')}T08:00:00Z',
      'follower_cnt': 10 + index * 2,
      'following_cnt': 6 + index,
      'friend_cnt': index % 9,
      'create_origin_cnt': 1 + (index % 6),
      'launch_world_cnt': 1 + (index % 5),
      'join_world_cnt': 2 + (index % 8),
      'is_followed': index % 3 == 0,
      'i_followed': index % 3 == 0,
      'followed_me': index % 4 == 0,
      'is_friend': index % 9 == 0,
      'follow_button_state': index % 3 == 0 ? 'following' : 'follow',
    };
  });
}

dynamic _deepCopyValue(dynamic value) {
  if (value is Map<String, dynamic>) return _deepCopyMap(value);
  if (value is Map) {
    return value.map((key, v) => MapEntry('$key', _deepCopyValue(v)));
  }
  if (value is List) return _deepCopyList(value);
  return value;
}

Map<String, dynamic> _mockImageObject(Object? raw) {
  if (raw is Map<String, dynamic>) return _deepCopyMap(raw);
  if (raw is Map) {
    return raw.map((key, value) => MapEntry('$key', _deepCopyValue(value)));
  }
  final url = '${raw ?? ''}'.trim();
  if (url.isEmpty) {
    return const {'sm_url': '', 'xl_url': '', 'object_key': ''};
  }
  return {'sm_url': url, 'xl_url': url, 'object_key': url};
}

Map<String, dynamic> _mockUploadedImageObject(String objectKey) {
  final smKey = objectKey.replaceFirst(RegExp(r'(\.[^.]+)$'), r'_400_300$1');
  final xlKey = objectKey.replaceFirst(RegExp(r'(\.[^.]+)$'), r'_800_600$1');
  return {
    'sm_url': 'https://mock.local/$smKey',
    'xl_url': 'https://mock.local/$xlKey',
    'object_key': xlKey,
  };
}
