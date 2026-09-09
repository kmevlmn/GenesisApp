import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'app_request_headers.dart';
import 'chatroom/chatroom_http_api.dart';
import 'gateway_auth.dart';
import 'json_utils.dart';
import 'local_mock_runtime.dart';
import 'models/location_tree.dart';
import 'models/origin.dart';
import 'models/paged_response.dart';
import 'models/tilemap_definition.dart';
import 'models/user.dart';
import 'models/world.dart';
import 'models/world_message.dart';
import 'http_transport.dart';
import 'v1/genesis_v1_api.dart';
import 'v2/genesis_v2_api.dart';
import '../app/config/platform_config.dart';
import '../app/debug/location_chat_debug_http.dart';
import '../platform/auth/auth_session.dart';
import '../platform/auth/identity_auth_service.dart';
import '../platform/auth/provider_identity_auth_service.dart';
import '../platform/device/device_id_service.dart';
import '../platform/device/method_channel_device_id_service.dart';
import '../platform/session/method_channel_user_session_store.dart';
import '../platform/session/user_session_store.dart';
import '../utils/entity_deleted.dart';
import '../utils/genesis_image_resource.dart';

part 'genesis_api_context.dart';
part 'genesis_api_auth_operations.dart';
part 'genesis_api_origin_operations.dart';
part 'genesis_api_world_operations.dart';
part 'genesis_api_create_origin_operations.dart';
part 'genesis_api_contracts.dart';
part 'genesis_api_mapping_utils.dart';
part 'genesis_api_origin_mapper.dart';
part 'genesis_api_world_mapper.dart';
part 'genesis_api_search_mapper.dart';

class GenesisApi extends _GenesisApiContext
    with
        _GenesisApiAuthOperations,
        _GenesisApiOriginOperations,
        _GenesisApiWorldOperations,
        _GenesisApiCreateOriginOperations {
  static const String releaseBaseHost = 'https://api.worldo.ai';
  static const String debugBaseHost = 'https://dev.hushie.ai';
  static const String defaultBaseHost = kReleaseMode
      ? releaseBaseHost
      : debugBaseHost;
  static const String defaultApiBaseUrl = '$defaultBaseHost/api/';
  static const String defaultGatewayApiBaseUrl = '$defaultBaseHost/apix/';
  static const String defaultAssetBaseUrl = 'https://af.hushie.ai/html/';
  static const String defaultChatroomWsBaseUrl = kReleaseMode
      ? 'wss://api.worldo.ai/aitown-chat/ws'
      : 'wss://dev.hushie.ai/aitown-chat/ws';
  static const String defaultChatroomHttpBaseUrl = kReleaseMode
      ? '$releaseBaseHost/'
      : '$debugBaseHost/';

  GenesisApi({
    super.apiClient,
    super.gatewayApiClient,
    super.healthClient,
    super.chatroomHttpClient,
    super.transport,
    super.useMock,
    super.platformConfig,
    super.gatewayApiBaseUrl,
    super.chatroomHttpBaseUrl,
    super.deviceIdService,
    super.sessionStore,
    super.identityAuthService,
    super.appHeaderProvider,
    super.gatewayRequestInterceptor,
    super.onSessionExpired,
    super.onPageNotFound,
    super.onChatroomMessageMutationError,
  });
}

final Map<int, String> _originIdToWorldview = <int, String>{};
