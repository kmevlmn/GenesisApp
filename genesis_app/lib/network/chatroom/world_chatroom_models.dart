part of 'world_chatroom_service.dart';

enum ConversationRoundPhase { submitting, awaitingRound, processing }

class ConversationRoundState {
  const ConversationRoundState({
    required this.phase,
    required this.startedAt,
    required this.deadlineAt,
    required this.generation,
    this.clientMsgId = '',
    this.conversationRoundId = '',
  });

  final ConversationRoundPhase phase;
  final String clientMsgId;
  final String conversationRoundId;
  final DateTime startedAt;
  final DateTime deadlineAt;
  final int generation;

  ConversationRoundState copyWith({
    ConversationRoundPhase? phase,
    String? clientMsgId,
    String? conversationRoundId,
  }) {
    return ConversationRoundState(
      phase: phase ?? this.phase,
      clientMsgId: clientMsgId ?? this.clientMsgId,
      conversationRoundId: conversationRoundId ?? this.conversationRoundId,
      startedAt: startedAt,
      deadlineAt: deadlineAt,
      generation: generation,
    );
  }
}

enum WorldContentUpdateKind { location, character }

class WorldContentUpdateNotice {
  const WorldContentUpdateNotice({
    required this.kind,
    required this.entityId,
    required this.name,
    required this.targetLocationId,
    required this.avatarUrl,
    required this.tickCount,
    this.contextLabel = '',
  });

  final WorldContentUpdateKind kind;
  final String entityId;
  final String name;
  final String targetLocationId;
  final String avatarUrl;
  final int tickCount;
  final String contextLabel;

  String get occurrenceKey => '${kind.name}:$entityId:$tickCount';
}

class WorldChatroomState {
  const WorldChatroomState({
    this.world,
    this.locationTree = const <LocationTreeNode<Map<String, dynamic>>>[],
    this.processedLocationTree,
    this.entitiesById = const <String, WorldChatroomEntity>{},
    this.entitiesByLocation = const <String, List<WorldChatroomEntity>>{},
    this.worldMessages = const <WorldChatroomMessage>[],
    this.messagesByLocation = const <String, List<WorldChatroomMessage>>{},
    this.streamMessagesByKey = const <String, WorldChatroomMessage>{},
    this.conversationRoundStatesByLocation =
        const <String, ConversationRoundState>{},
    this.historyGenerationByLocation = const <String, int>{},
    this.newestLocationMessageIds = const <String, int>{},
    this.historyHasMoreByLocation = const <String, bool>{},
    this.lastMessageId = 0,
    this.connected = false,
    this.joining = false,
    this.joinedLocationId = '',
    this.inputBlocked = false,
    this.reconnecting = false,
    this.latestSocketCurrentTime = '',
    this.latestSocketTickNo = 0,
    this.latestSocketSubTickNo = 0,
    this.latestSocketCurrentTimeRevision = 0,
    this.latestNewUserJoin,
    this.latestNewUserJoinRevision = 0,
    this.mapUpdatedRevision = 0,
    this.latestContentUpdateNotices = const <WorldContentUpdateNotice>[],
    this.contentUpdateNoticeRevision = 0,
    this.lastFailure,
  });

  final WorldDetail? world;
  final List<LocationTreeNode<Map<String, dynamic>>> locationTree;
  final ProcessedLocationTree<Map<String, dynamic>>? processedLocationTree;
  final Map<String, WorldChatroomEntity> entitiesById;
  final Map<String, List<WorldChatroomEntity>> entitiesByLocation;
  final List<WorldChatroomMessage> worldMessages;
  final Map<String, List<WorldChatroomMessage>> messagesByLocation;
  final Map<String, WorldChatroomMessage> streamMessagesByKey;
  final Map<String, ConversationRoundState> conversationRoundStatesByLocation;

  /// Compatibility/debug view of server-confirmed active rounds. Submitting
  /// sends that have not received a round id yet are intentionally omitted.
  Map<String, String> get waitingConversationRoundIdsByLocation =>
      Map<String, String>.unmodifiable(<String, String>{
        for (final entry in conversationRoundStatesByLocation.entries)
          if (entry.value.conversationRoundId.trim().isNotEmpty)
            entry.key: entry.value.conversationRoundId,
      });
  final Map<String, int> historyGenerationByLocation;
  final Map<String, int> newestLocationMessageIds;
  final Map<String, bool> historyHasMoreByLocation;
  final int lastMessageId;
  final bool connected;
  final bool joining;
  final String joinedLocationId;
  final bool inputBlocked;
  final bool reconnecting;
  final String latestSocketCurrentTime;
  final int latestSocketTickNo;
  final int latestSocketSubTickNo;
  final int latestSocketCurrentTimeRevision;
  final ChatroomNewUserJoinEvent? latestNewUserJoin;
  final int latestNewUserJoinRevision;
  final int mapUpdatedRevision;
  final List<WorldContentUpdateNotice> latestContentUpdateNotices;
  final int contentUpdateNoticeRevision;
  final ChatroomFailureEvent? lastFailure;

  WorldChatroomState copyWith({
    WorldDetail? world,
    List<LocationTreeNode<Map<String, dynamic>>>? locationTree,
    ProcessedLocationTree<Map<String, dynamic>>? processedLocationTree,
    Map<String, WorldChatroomEntity>? entitiesById,
    Map<String, List<WorldChatroomEntity>>? entitiesByLocation,
    List<WorldChatroomMessage>? worldMessages,
    Map<String, List<WorldChatroomMessage>>? messagesByLocation,
    Map<String, WorldChatroomMessage>? streamMessagesByKey,
    Map<String, ConversationRoundState>? conversationRoundStatesByLocation,
    Map<String, int>? historyGenerationByLocation,
    Map<String, int>? newestLocationMessageIds,
    Map<String, bool>? historyHasMoreByLocation,
    int? lastMessageId,
    bool? connected,
    bool? joining,
    String? joinedLocationId,
    bool? inputBlocked,
    bool? reconnecting,
    String? latestSocketCurrentTime,
    int? latestSocketTickNo,
    int? latestSocketSubTickNo,
    int? latestSocketCurrentTimeRevision,
    ChatroomNewUserJoinEvent? latestNewUserJoin,
    int? latestNewUserJoinRevision,
    int? mapUpdatedRevision,
    List<WorldContentUpdateNotice>? latestContentUpdateNotices,
    int? contentUpdateNoticeRevision,
    ChatroomFailureEvent? lastFailure,
  }) {
    return WorldChatroomState(
      world: world ?? this.world,
      locationTree: locationTree ?? this.locationTree,
      processedLocationTree:
          processedLocationTree ?? this.processedLocationTree,
      entitiesById: entitiesById ?? this.entitiesById,
      entitiesByLocation: entitiesByLocation ?? this.entitiesByLocation,
      worldMessages: worldMessages ?? this.worldMessages,
      messagesByLocation: messagesByLocation ?? this.messagesByLocation,
      streamMessagesByKey: streamMessagesByKey ?? this.streamMessagesByKey,
      conversationRoundStatesByLocation:
          conversationRoundStatesByLocation ??
          this.conversationRoundStatesByLocation,
      historyGenerationByLocation:
          historyGenerationByLocation ?? this.historyGenerationByLocation,
      newestLocationMessageIds:
          newestLocationMessageIds ?? this.newestLocationMessageIds,
      historyHasMoreByLocation:
          historyHasMoreByLocation ?? this.historyHasMoreByLocation,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      connected: connected ?? this.connected,
      joining: joining ?? this.joining,
      joinedLocationId: joinedLocationId ?? this.joinedLocationId,
      inputBlocked: inputBlocked ?? this.inputBlocked,
      reconnecting: reconnecting ?? this.reconnecting,
      latestSocketCurrentTime:
          latestSocketCurrentTime ?? this.latestSocketCurrentTime,
      latestSocketTickNo: latestSocketTickNo ?? this.latestSocketTickNo,
      latestSocketSubTickNo:
          latestSocketSubTickNo ?? this.latestSocketSubTickNo,
      latestSocketCurrentTimeRevision:
          latestSocketCurrentTimeRevision ??
          this.latestSocketCurrentTimeRevision,
      latestNewUserJoin: latestNewUserJoin ?? this.latestNewUserJoin,
      latestNewUserJoinRevision:
          latestNewUserJoinRevision ?? this.latestNewUserJoinRevision,
      mapUpdatedRevision: mapUpdatedRevision ?? this.mapUpdatedRevision,
      latestContentUpdateNotices:
          latestContentUpdateNotices ?? this.latestContentUpdateNotices,
      contentUpdateNoticeRevision:
          contentUpdateNoticeRevision ?? this.contentUpdateNoticeRevision,
      lastFailure: lastFailure ?? this.lastFailure,
    );
  }
}

enum WorldChatroomEntityType { character, player }

class WorldChatroomEntity {
  const WorldChatroomEntity({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.type,
    required this.locationId,
    this.isAi = false,
  });

  final String id;
  final String name;
  final String avatarUrl;
  final WorldChatroomEntityType type;
  final String locationId;
  final bool isAi;
}

class WorldChatroomMessage {
  const WorldChatroomMessage({
    this.globalMessageId = 0,
    required this.messageId,
    int? locationMessageId,
    required this.conversationRoundId,
    required this.roundOrder,
    this.tickNo = 0,
    this.subTickNo = 0,
    required this.locationId,
    required this.senderType,
    String businessType = '',
    this.streamType = '',
    this.userId = '',
    required this.senderId,
    required this.senderName,
    this.clientMsgId = '',
    required this.content,
    this.messageType = chatroomTextMessageType,
    this.currentTime = '',
    required this.createdAt,
    this.streaming = false,
    this.isLlmStreamMessage = false,
    this.timelinePayload,
    this.v2TickPayload,
    this.minAppVersion = 0,
    this.rawPayload = const <String, dynamic>{},
  }) : locationMessageId = locationMessageId ?? 0,
       _businessType = businessType;

  final int globalMessageId;
  final int messageId;
  final int locationMessageId;
  final String conversationRoundId;
  final int roundOrder;
  final int tickNo;
  final int subTickNo;
  final String locationId;
  final String senderType;
  final String _businessType;
  final String streamType;
  final String userId;
  final String senderId;
  final String senderName;
  final String clientMsgId;
  final String content;
  final String messageType;
  final String currentTime;
  final DateTime? createdAt;
  final bool streaming;
  final bool isLlmStreamMessage;
  final ChatroomTimelinePayload? timelinePayload;
  final ChatroomV2TickPayload? v2TickPayload;
  final int minAppVersion;
  final Map<String, dynamic> rawPayload;

  String get businessType {
    final explicit = _businessType.trim().toLowerCase();
    if (explicit.isNotEmpty) return explicit;
    return senderType.trim().toLowerCase();
  }

  /// Whether the protocol supplied a V2 business `type`, rather than this
  /// model deriving one from the legacy `sender_type` field.
  bool get hasExplicitBusinessType => _businessType.trim().isNotEmpty;

  // A positive location cursor is authoritative even when a stored or
  // fallback Tick has no decoded V2 payload.
  bool get isV2LocationTick => businessType == 'tick' && locationMessageId > 0;

  bool get isCanonicalUserMessage =>
      businessType == 'user' &&
      clientMsgId.trim().isNotEmpty &&
      (globalMessageId > 0 || messageId > 0 || locationMessageId > 0);

  int get locationQueueMessageId => locationMessageId;

  int get conversationRoundNumber => int.tryParse(conversationRoundId) ?? 0;

  factory WorldChatroomMessage.fromHttpMessage(ChatroomHttpMessage message) {
    final timelinePayload = _resolvedChatroomTimelinePayload(
      senderType: message.senderType,
      rawPayload: message.content,
      senderId: message.senderId,
      locationId: message.locationId,
      content: message.content,
    );
    return WorldChatroomMessage(
      globalMessageId: message.globalMessageId,
      messageId: message.messageId,
      locationMessageId: _safeLocationMessageId(
        () => message.locationMessageId,
      ),
      conversationRoundId: '${message.conversationRoundId}',
      roundOrder: 0,
      tickNo: message.tickNo,
      subTickNo: message.subTickNo,
      locationId: message.locationId,
      senderType: message.senderType,
      businessType: message.businessType,
      streamType: message.streamType,
      userId: message.userId,
      senderId: message.senderId,
      senderName: message.senderName,
      clientMsgId: message.clientMsgId,
      content: message.content,
      messageType: message.messageType,
      currentTime: message.currentTime,
      createdAt: message.createdAt,
      timelinePayload: timelinePayload,
      v2TickPayload: message.v2TickPayload,
      minAppVersion: message.minAppVersion,
      rawPayload: message.payload,
    );
  }

  factory WorldChatroomMessage.fromStorageJson(Map<String, dynamic> json) {
    final senderId = asString(json['sender_id']);
    final senderType = asString(json['sender_type']);
    final locationId = asString(json['location_id']);
    final content = asString(json['content']);
    final rawPayload = json['payload'] is Map
        ? asJsonMap(json['payload'])
        : const <String, dynamic>{};
    final businessType = json.containsKey('type')
        ? asString(json['type']).trim().toLowerCase()
        : '';
    return WorldChatroomMessage(
      globalMessageId: asInt(
        json['global_message_id'],
        fallback: asInt(json['global_msg_id']),
      ),
      messageId: asInt(json['message_id'], fallback: asInt(json['msg_id'])),
      locationMessageId: asInt(
        json['location_message_id'],
        fallback: asInt(json['location_msg_id']),
      ),
      conversationRoundId: asString(
        json['conversation_round_id'],
        fallback: '${asInt(json['conversation_round_id'])}',
      ),
      roundOrder: asInt(json['round_order']),
      tickNo: asInt(json['tick_no']),
      subTickNo: asInt(json['sub_tick_no']),
      locationId: locationId,
      senderType: senderType,
      businessType: businessType,
      streamType: asString(json['stream_type']),
      userId: asString(json['user_id']),
      senderId: senderId,
      senderName: asString(json['sender_name']),
      clientMsgId: asString(json['client_msg_id']),
      content: content,
      messageType: resolveIncomingChatroomMessageType(
        hasMessageTypeField: json.containsKey('message_type'),
        rawMessageType: json['message_type'],
        senderId: senderId,
      ),
      currentTime: asString(json['current_time']),
      createdAt: asDateTime(json['created_at']) ?? asDateTime(json['ts']),
      isLlmStreamMessage: asBool(json['is_llm_stream']),
      timelinePayload: _resolvedChatroomTimelinePayload(
        senderType: senderType,
        rawPayload: content,
        senderId: senderId,
        locationId: locationId,
        content: content,
      ),
      v2TickPayload: _storedV2TickPayload(
        businessType: businessType,
        rawPayload: rawPayload,
      ),
      minAppVersion: asInt(json['min_app_version']),
      rawPayload: rawPayload,
    );
  }

  factory WorldChatroomMessage.fromUserMessage(ChatroomUserMessage message) {
    return WorldChatroomMessage(
      globalMessageId: message.globalMessageId,
      messageId: message.messageId,
      locationMessageId: _safeLocationMessageId(
        () => message.locationMessageId,
      ),
      conversationRoundId: message.conversationRoundId,
      roundOrder: message.roundOrder,
      locationId: message.locationId,
      senderType: message.senderType.isEmpty ? 'user' : message.senderType,
      businessType: message.businessType,
      streamType: message.streamType,
      userId: message.userId,
      senderId: message.senderId,
      senderName: message.senderName,
      clientMsgId: message.clientMsgId,
      content: message.content,
      messageType: message.messageType,
      currentTime: message.currentTime,
      createdAt: message.createdAt ?? message.ts,
      minAppVersion: message.minAppVersion ?? 0,
      rawPayload: message.rawPayload,
    );
  }

  factory WorldChatroomMessage.fromUserEnterLocationMessage(
    ChatroomUserEnterLocationMessage message,
  ) {
    return WorldChatroomMessage(
      globalMessageId: message.globalMessageId,
      messageId: message.messageId,
      locationMessageId: _safeLocationMessageId(
        () => message.locationMessageId,
      ),
      conversationRoundId: message.conversationRoundId,
      roundOrder: message.roundOrder,
      locationId: message.locationId,
      senderType: chatroomUserEnterLocationSenderType,
      userId: message.userId,
      senderId: message.senderId,
      senderName: message.senderName,
      content: message.content,
      messageType: message.messageType,
      currentTime: message.currentTime,
      createdAt: message.createdAt ?? message.ts,
      timelinePayload: ChatroomUserEnterLocationPayload(
        charId: message.senderId,
        toLocationId: message.locationId,
        text: message.content,
      ),
    );
  }

  factory WorldChatroomMessage.fromNarratorMessage(
    ChatroomNarratorMessage message,
  ) {
    final senderType = message.senderType.trim().toLowerCase();
    return WorldChatroomMessage(
      globalMessageId: message.globalMessageId,
      messageId: message.messageId,
      locationMessageId: _safeLocationMessageId(
        () => message.locationMessageId,
      ),
      conversationRoundId: message.conversationRoundId,
      roundOrder: message.roundOrder,
      locationId: message.locationId,
      senderType:
          senderType == 'narrator' && _senderIdIsNarrator(message.senderId)
          ? 'narrator'
          : 'character',
      businessType: message.businessType,
      streamType: message.streamType,
      userId: message.userId,
      senderId: message.senderId,
      senderName: message.senderName,
      content: message.content,
      messageType: message.messageType,
      currentTime: message.currentTime,
      createdAt: message.createdAt ?? message.ts,
      minAppVersion: message.minAppVersion ?? 0,
      rawPayload: message.rawPayload,
    );
  }

  factory WorldChatroomMessage.fromTickAdvanceMessage(
    ChatroomTickAdvanceMessage message,
  ) {
    return WorldChatroomMessage(
      globalMessageId: message.globalMessageId,
      messageId: message.messageId,
      locationMessageId: _safeLocationMessageId(
        () => message.locationMessageId,
      ),
      conversationRoundId: message.conversationRoundId,
      roundOrder: message.roundOrder,
      tickNo: message.tickNo,
      subTickNo: message.subTickNo,
      locationId: message.locationId,
      senderType: 'tick',
      businessType: message.businessType,
      streamType: message.streamType,
      userId: message.userId,
      senderId: message.senderId,
      senderName: message.senderName,
      content: message.content.isEmpty ? message.currentTime : message.content,
      messageType: message.messageType,
      currentTime: message.currentTime,
      createdAt: message.ts,
      v2TickPayload: message.v2TickPayload,
      minAppVersion: message.minAppVersion ?? 0,
      rawPayload: message.rawPayload.isNotEmpty
          ? message.rawPayload
          : message.v2TickPayload?.toJson().cast<String, dynamic>() ??
                const <String, dynamic>{},
    );
  }

  factory WorldChatroomMessage.fromStoryEventsMessage(
    ChatroomStoryEventsMessage message,
  ) {
    return WorldChatroomMessage(
      globalMessageId: message.globalMessageId,
      messageId: message.messageId,
      locationMessageId: _safeLocationMessageId(
        () => message.locationMessageId,
      ),
      conversationRoundId: message.conversationRoundId,
      roundOrder: message.roundOrder,
      tickNo: message.tickNo,
      subTickNo: message.subTickNo,
      locationId: message.locationId,
      senderType: chatroomStoryEventsSenderType,
      userId: message.userId,
      senderId: message.senderId,
      senderName: message.senderName,
      content: message.content,
      currentTime: message.currentTime,
      createdAt: message.createdAt ?? message.ts,
      timelinePayload: message.timelinePayload,
    );
  }

  factory WorldChatroomMessage.fromCharactersMovedMessage(
    ChatroomCharactersMovedMessage message,
  ) {
    return WorldChatroomMessage(
      globalMessageId: message.globalMessageId,
      messageId: message.messageId,
      locationMessageId: _safeLocationMessageId(
        () => message.locationMessageId,
      ),
      conversationRoundId: message.conversationRoundId,
      roundOrder: message.roundOrder,
      tickNo: message.tickNo,
      subTickNo: message.subTickNo,
      locationId: message.locationId,
      senderType: chatroomCharactersMovedSenderType,
      userId: message.userId,
      senderId: message.senderId,
      senderName: message.senderName,
      content: message.content,
      currentTime: message.currentTime,
      createdAt: message.createdAt ?? message.ts,
      timelinePayload: message.timelinePayload,
    );
  }

  factory WorldChatroomMessage.fromAiStreamStart(ChatroomAiStreamStart event) {
    return WorldChatroomMessage(
      globalMessageId: event.globalMessageId,
      messageId: event.messageId,
      locationMessageId: _safeLocationMessageId(() => event.locationMessageId),
      conversationRoundId: event.conversationRoundId,
      roundOrder: event.roundOrder,
      tickNo: 0,
      locationId: event.locationId,
      senderType: event.senderType,
      businessType: event.businessType,
      streamType: event.streamType,
      userId: '',
      senderId: event.senderId,
      senderName: event.senderName,
      content: '',
      currentTime: event.currentTime,
      createdAt: null,
      streaming: true,
      isLlmStreamMessage: true,
      minAppVersion: event.minAppVersion ?? 0,
      rawPayload: event.rawPayload,
    );
  }

  WorldChatroomMessage copyWith({
    int? globalMessageId,
    int? messageId,
    int? locationMessageId,
    String? conversationRoundId,
    int? roundOrder,
    int? tickNo,
    int? subTickNo,
    String? locationId,
    String? senderType,
    String? businessType,
    String? streamType,
    String? userId,
    String? senderId,
    String? senderName,
    String? clientMsgId,
    String? content,
    String? messageType,
    String? currentTime,
    DateTime? createdAt,
    bool? streaming,
    bool? isLlmStreamMessage,
    ChatroomTimelinePayload? timelinePayload,
    ChatroomV2TickPayload? v2TickPayload,
    int? minAppVersion,
    Map<String, dynamic>? rawPayload,
  }) {
    return WorldChatroomMessage(
      globalMessageId: globalMessageId ?? this.globalMessageId,
      messageId: messageId ?? this.messageId,
      locationMessageId: locationMessageId ?? this.locationMessageId,
      conversationRoundId: conversationRoundId ?? this.conversationRoundId,
      roundOrder: roundOrder ?? this.roundOrder,
      tickNo: tickNo ?? this.tickNo,
      subTickNo: subTickNo ?? this.subTickNo,
      locationId: locationId ?? this.locationId,
      senderType: senderType ?? this.senderType,
      businessType: businessType ?? _businessType,
      streamType: streamType ?? this.streamType,
      userId: userId ?? this.userId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      clientMsgId: clientMsgId ?? this.clientMsgId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      currentTime: currentTime ?? this.currentTime,
      createdAt: createdAt ?? this.createdAt,
      streaming: streaming ?? this.streaming,
      isLlmStreamMessage: isLlmStreamMessage ?? this.isLlmStreamMessage,
      timelinePayload: timelinePayload ?? this.timelinePayload,
      v2TickPayload: v2TickPayload ?? this.v2TickPayload,
      minAppVersion: minAppVersion ?? this.minAppVersion,
      rawPayload: rawPayload ?? this.rawPayload,
    );
  }
}

ChatroomV2TickPayload? _storedV2TickPayload({
  required String businessType,
  required Map<String, dynamic> rawPayload,
}) {
  if (businessType != 'tick' || rawPayload.isEmpty) return null;
  try {
    return ChatroomV2TickPayload.fromJson(rawPayload);
  } catch (_) {
    return null;
  }
}

ChatroomTimelinePayload? _resolvedChatroomTimelinePayload({
  required Object? senderType,
  required Object? rawPayload,
  required String senderId,
  required String locationId,
  required String content,
}) {
  final decoded = tryDecodeChatroomTimelinePayload(
    senderType: senderType,
    rawPayload: rawPayload,
  );
  if (decoded != null) return decoded;
  if ('$senderType'.trim().toLowerCase() !=
      chatroomUserEnterLocationSenderType) {
    return null;
  }
  final resolvedSenderId = senderId.trim();
  final resolvedLocationId = locationId.trim();
  if (resolvedSenderId.isEmpty ||
      resolvedLocationId.isEmpty ||
      content.trim().isEmpty) {
    return null;
  }
  return ChatroomUserEnterLocationPayload(
    charId: resolvedSenderId,
    toLocationId: resolvedLocationId,
    text: content,
  );
}

int _safeLocationMessageId(int Function() read) {
  try {
    return read();
  } on TypeError {
    return 0;
  }
}

bool _senderIdIsNarrator(String senderId) {
  return const {'nar', 'nar_pic'}.contains(senderId.trim().toLowerCase());
}
