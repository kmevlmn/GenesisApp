import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../app/debug/location_chat_debug_slice.dart';
import '../genesis_api.dart';
import '../api_exception.dart';
import '../http_transport.dart';
import '../json_utils.dart';
import '../models/location_tree.dart';
import '../models/world.dart';
import 'chatroom_client.dart';
import 'chatroom_connection_controller.dart';
import 'chatroom_http_models.dart';
import 'chatroom_message_type.dart';
import 'chatroom_message_storage.dart';
import 'chatroom_models.dart';
import 'chatroom_reply_actions_controller.dart';
import 'chatroom_reply_action_storage.dart';
import 'chatroom_inspiration_controller.dart';
import 'chatroom_inspiration_storage.dart';

export 'chatroom_reply_actions_controller.dart';
import 'chatroom_timeline_payload.dart';

part 'world_chatroom_connection.dart';
part 'world_chatroom_history_repository.dart';
part 'world_chatroom_message_mutations.dart';
part 'world_chatroom_event_projection.dart';
part 'world_chatroom_message_reducer.dart';
part 'world_chatroom_world_projection.dart';
part 'world_chatroom_models.dart';

const _maxMessagesPerLocation = 200;
const _maxRecoverableLocationMessageGap = 50;
const _maxLocationMessageGapFillAttempts = 3;
const _defaultLocationQueueInitConcurrency = 4;
const _transientCharactersMovedMessageIdBase = 0x10000000000000;
const _transientCharactersMovedRoundPrefix = 'ws-event:';
const _closedConversationRoundRetention = Duration(minutes: 5);
const conversationRoundFallbackTimeout = Duration(seconds: 30);

bool get _chatroomHydrateMetricsEnabled => kDebugMode || kProfileMode;

void _logChatroomHydrateMetric(String message) {
  if (!_chatroomHydrateMetricsEnabled) return;
  debugPrint('[WorldChatroomHydrate] $message');
}

void _logChatroomSocketEvent(String message) {
  if (!_chatroomHydrateMetricsEnabled) return;
  debugPrint('[WorldChatroomSocket] $message');
}

class WorldChatroomOlderMessagesPage {
  const WorldChatroomOlderMessagesPage({
    required this.loadedCount,
    required this.hasMore,
  });

  final int loadedCount;
  final bool hasMore;
}

/// The transport-level acknowledgement for a submitted chat message.
///
/// V2 ACK frames intentionally do not contain canonical message ids. Those
/// arrive on [ChatroomSendHandle.canonicalMessage] via the user echo.
class ChatroomSendReceipt {
  const ChatroomSendReceipt({
    required this.clientMsgId,
    required this.receivedAt,
  });

  final String clientMsgId;
  final DateTime? receivedAt;

  factory ChatroomSendReceipt.fromAck(
    ChatroomAck ack, {
    required String fallbackClientMsgId,
  }) {
    return ChatroomSendReceipt(
      clientMsgId: ack.clientMsgId.trim().isEmpty
          ? fallbackClientMsgId
          : ack.clientMsgId.trim(),
      receivedAt: ack.ts,
    );
  }
}

/// A two-stage V2 send operation.
///
/// [receipt] confirms that the server accepted the command. The authoritative
/// ids and conversation round are available only from [canonicalMessage].
class ChatroomSendHandle {
  const ChatroomSendHandle({
    required this.clientMsgId,
    required this.receipt,
    required this.canonicalMessage,
  });

  final String clientMsgId;
  final Future<ChatroomSendReceipt> receipt;
  final Future<WorldChatroomMessage> canonicalMessage;
}

enum GemBalanceAlertKind { insufficient, low }

class GemBalanceAlert {
  const GemBalanceAlert({
    required this.kind,
    this.balanceCent = 0,
    this.message = '',
  });

  final GemBalanceAlertKind kind;
  final int balanceCent;
  final String message;
}

class _LocationMessageGap {
  const _LocationMessageGap({required this.lower, required this.upper});

  final int lower;
  final int upper;

  int get missingCount => upper - lower - 1;
}

class _ChatroomStreamAccumulator {
  _ChatroomStreamAccumulator({required this.message, int firstSequence = 1})
    : nextSequence = firstSequence;

  WorldChatroomMessage message;
  int nextSequence;
  final SplayTreeMap<int, String> chunks = SplayTreeMap<int, String>();

  bool addChunk(int sequence, String content) {
    if (sequence < nextSequence || chunks.containsKey(sequence)) return false;
    chunks[sequence] = content;
    final contiguous = StringBuffer();
    while (chunks.containsKey(nextSequence)) {
      contiguous.write(chunks.remove(nextSequence));
      nextSequence += 1;
    }
    if (contiguous.isEmpty) return false;
    message = message.copyWith(content: '${message.content}$contiguous');
    return true;
  }
}

class WorldChatroomService {
  WorldChatroomService({
    required GenesisApi api,
    required ChatroomClient client,
    required ChatroomMessageStorage messageStorage,
    Duration heartbeatInterval = const Duration(seconds: 2),
    Duration reconnectInterval = const Duration(seconds: 5),
    Duration conversationRoundTimeout = conversationRoundFallbackTimeout,
    bool refreshInitialSnapshotOnConnect = true,
    ChatroomReplyActionStorage? replyActionStorage,
    ChatroomInspirationStorage? inspirationStorage,
  }) : _api = api,
       _client = client,
       _replyActionStorage = replyActionStorage,
       _inspirationStorage = inspirationStorage,
       _messageStorage = messageStorage,
       _heartbeatInterval = heartbeatInterval,
       _reconnectInterval = reconnectInterval,
       _conversationRoundTimeout = conversationRoundTimeout,
       _refreshInitialSnapshotOnConnect = refreshInitialSnapshotOnConnect;

  final ChatroomReplyActionStorage? _replyActionStorage;
  ChatroomReplyActionsController? _replyActionsController;
  final ChatroomInspirationStorage? _inspirationStorage;
  ChatroomInspirationController? _inspirations;
  final _inspirationValidatedLocations = <String>{};
  int _inspirationConnectionGeneration = 0;
  String? _inspirationReplacementLocation;

  ChatroomInspirationController? get inspirations {
    if (replyActions == null) return null;
    return _inspirations ??= ChatroomInspirationController(
      ownerUid: _storageOwnerUid,
      worldId: _worldId,
      httpApi: _api.chatroomHttp,
      storage: _inspirationStorage,
    );
  }

  Future<void> ensureInspirationHistory(String locationId) async {
    if (_inspirationValidatedLocations.contains(locationId)) return;
    final generation = _inspirationConnectionGeneration;
    await _fetchLatestLocationMessages(
      locationId: locationId,
      limit: 20,
      emitLatestFetched: false,
    );
    if (_disposed || generation != _inspirationConnectionGeneration) {
      throw StateError('The active chat changed');
    }
    _inspirationValidatedLocations.add(locationId);
    _syncInspirationContexts();
  }

  void _syncInspirationContexts() {
    final controller = _inspirations;
    final replies = _replyActionsController;
    if (controller == null || replies == null) return;
    for (final location in replies.locationIds) {
      if (!_inspirationValidatedLocations.contains(location)) continue;
      final round = replies.stateFor(location)!;
      controller.observe(
        location,
        roundId: round.roundId,
        tailMessageId: round.inspirationTailMessageId,
        replacing: _inspirationReplacementLocation == location,
      );
    }
  }

  void _suspendInspirations() {
    _inspirationConnectionGeneration++;
    _inspirationValidatedLocations.clear();
    _inspirations?.suspend();
  }

  final _completedReplyRounds = <String>{};
  Future<void> Function()? _replyWalletRefresher;

  void setReplyWalletRefresher(Future<void> Function() refresh) {
    _replyWalletRefresher = refresh;
  }

  /// Lazily owns candidate state; ordinary history never stores candidates.
  ChatroomReplyActionsController? get replyActions {
    if (_disposed || _worldId.isEmpty || _storageOwnerUid.isEmpty) return null;
    final existing = _replyActionsController;
    if (existing != null) return existing;
    final controller = ChatroomReplyActionsController(
      worldId: _worldId,
      ownerUid: _storageOwnerUid,
      httpApi: _api.chatroomHttp,
      session: () => _session,
      isReady: (location) =>
          !_disposed && _state.connected && _state.joinedLocationId == location,
      isTickLocked: () => _state.inputBlocked,
      refreshFormalRange: (location, start, end) => _requestHistoryReplacement(
        locationId: location,
        start: start,
        end: end,
        requireCurrent: true,
      ),
      replaceCompletedRound: _replaceCompletedReplyRound,
      onGoOnAccepted: (location, round) => _bindWaitingConversationRound(
        locationId: location,
        conversationRoundId: '$round',
      ),
      refreshLatestHistory: (location) =>
          refreshLocationHistory(locationId: location),
      refreshWallet: () async {
        await _replyWalletRefresher?.call();
      },
      storage: _replyActionStorage,
    );
    _replyActionsController = controller;
    controller.addListener(_syncInspirationContexts);
    _observeReplyHistory();
    return controller;
  }

  Future<void> _replaceCompletedReplyRound(String location, int round) async {
    final world = _worldId;
    final owner = _storageOwnerUid;
    _completedReplyRounds.add('$location:$round');
    // Events already queued before the round end must settle before replacement.
    await _eventQueue;
    if (_disposed || world != _worldId || owner != _storageOwnerUid) {
      throw StateError('The active chat changed during reply recovery');
    }
    bool inRound(WorldChatroomMessage message) =>
        message.locationId == location &&
        message.conversationRoundNumber == round;
    _streamAccumulators.removeWhere((_, value) => inRound(value.message));
    _setState(
      _state.copyWith(
        streamMessagesByKey: {
          for (final entry in _state.streamMessagesByKey.entries)
            if (!inRound(entry.value)) entry.key: entry.value,
        },
        messagesByLocation: {
          ..._state.messagesByLocation,
          location: [
            for (final message
                in _state.messagesByLocation[location] ??
                    const <WorldChatroomMessage>[])
              if (!inRound(message) || !message.streaming) message,
          ],
        },
        worldMessages: [
          for (final message in _state.worldMessages)
            if (!inRound(message) || !message.streaming) message,
        ],
      ),
    );
    await _requestHistoryReplacement(
      locationId: location,
      start: round,
      end: round,
      requireCurrent: true,
    );
  }

  void _observeReplyHistory() {
    final controller = _replyActionsController;
    if (controller == null) return;
    for (final entry in _state.messagesByLocation.entries) {
      final round = int.tryParse(
        _state
                .conversationRoundStatesByLocation[entry.key]
                ?.conversationRoundId ??
            '',
      );
      controller.observeMessages(
        entry.key,
        entry.value,
        activeRoundIds: {if (round != null && round > 0) round},
      );
    }
  }

  final GenesisApi _api;
  final ChatroomClient _client;
  final ChatroomMessageStorage _messageStorage;
  final Duration _heartbeatInterval;
  final Duration _reconnectInterval;
  final Duration _conversationRoundTimeout;
  final bool _refreshInitialSnapshotOnConnect;
  final _states = StreamController<WorldChatroomState>.broadcast();
  final _failures = StreamController<ChatroomFailureEvent>.broadcast();
  final _balanceAlerts = StreamController<GemBalanceAlert>.broadcast();
  final _latestFetchedMessages =
      StreamController<List<WorldChatroomMessage>>.broadcast();

  WorldChatroomState _state = const WorldChatroomState();
  ChatroomSession? _session;
  ChatroomConnectionIdentity? _identity;
  String _worldId = '';
  String _desiredLocationId = '';
  String _lastUserEnterLocationCommandId = '';
  String _pendingUserEnterLocationCommandId = '';
  bool _userDisconnected = true;
  bool _disposed = false;
  Completer<void>? _connectCompleter;
  Completer<ChatroomJoined>? _joinCompleter;
  final Map<String, Future<void>> _localHydratingMessageFutures =
      <String, Future<void>>{};
  final Set<String> _localHydratedMessageKeys = <String>{};
  int _localMessageCacheGeneration = 0;
  int _userLocationsRefreshGeneration = 0;
  bool _userLocationsRefreshPending = false;
  String _pendingUserLocationsSocketCurrentTime = '';
  Future<void>? _userLocationsRefreshDrain;
  bool _latestWorldMessagesRefreshPending = false;
  Future<void>? _latestWorldMessagesRefreshDrain;
  bool _worldRefreshPending = false;
  bool _pendingMapContentDetection = false;
  bool _pendingCharacterContentDetection = false;
  String _pendingWorldRefreshSocketCurrentTime = '';
  Future<WorldDetail?>? _worldRefreshDrain;
  final Map<ChatroomWorldNotification, Future<WorldDetail?>>
  _queuedNotificationWorldRefreshes =
      Map<ChatroomWorldNotification, Future<WorldDetail?>>.identity();
  final Set<String> _publishedContentUpdateOccurrences = <String>{};
  int _transientCharactersMovedSequence = 0;
  final Map<String, Future<List<WorldChatroomMessage>>>
  _latestMessageFetchFutures = <String, Future<List<WorldChatroomMessage>>>{};
  final Map<String, Completer<WorldChatroomMessage>> _canonicalEchoCompleters =
      <String, Completer<WorldChatroomMessage>>{};
  int _historySessionGeneration = 0;
  final _pendingMessageMutationKeys = <String>{};
  final _historyRefreshes = <String, _LocationHistoryRefresh>{};
  final _locationWrites = <String, Future<void>>{};
  final _deletedMessageIds = <String, Set<int>>{};

  final Map<String, _ChatroomStreamAccumulator> _streamAccumulators =
      <String, _ChatroomStreamAccumulator>{};
  int _sendClientMessageSequence = 0;
  int _conversationRoundGeneration = 0;
  bool _heartbeatInFlight = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  final Map<String, Timer> _conversationRoundTimers = <String, Timer>{};
  final Map<String, DateTime> _closedConversationRoundExpirations =
      <String, DateTime>{};
  StreamSubscription<ChatroomEvent>? _eventSubscription;
  StreamSubscription<ChatroomFailureEvent>? _failureSubscription;
  StreamSubscription<ChatroomErrorEvent>? _errorSubscription;
  Future<void> _eventQueue = Future<void>.value();

  Stream<WorldChatroomState> get states => _states.stream;

  Stream<ChatroomFailureEvent> get failures => _failures.stream;

  Stream<GemBalanceAlert> get balanceAlerts => _balanceAlerts.stream;

  Stream<List<WorldChatroomMessage>> get latestFetchedMessages =>
      _latestFetchedMessages.stream;

  WorldChatroomState get state => _state;

  ChatroomConnectionIdentity? get identity => _identity;

  bool get isDisposed => _disposed;

  void setInputBlocked(bool blocked) {
    _throwIfDisposed();
    if (_state.inputBlocked == blocked) return;
    _setState(_state.copyWith(inputBlocked: blocked));
  }

  void _startSubmittingConversationRound({
    required String locationId,
    required String clientMsgId,
  }) {
    final resolvedLocationId = locationId.trim();
    final resolvedClientMsgId = clientMsgId.trim();
    if (resolvedLocationId.isEmpty || resolvedClientMsgId.isEmpty) return;
    final existing =
        _state.conversationRoundStatesByLocation[resolvedLocationId];
    if (existing != null) {
      if (existing.clientMsgId == resolvedClientMsgId) return;
      throw const ChatroomProtocolException(
        'a conversation round is already active for this location',
      );
    }
    final startedAt = DateTime.now();
    final roundState = ConversationRoundState(
      phase: ConversationRoundPhase.submitting,
      clientMsgId: resolvedClientMsgId,
      startedAt: startedAt,
      deadlineAt: startedAt.add(_conversationRoundTimeout),
      generation: ++_conversationRoundGeneration,
    );
    _replaceConversationRoundState(resolvedLocationId, roundState);
    _scheduleConversationRoundTimeout(resolvedLocationId, roundState);
  }

  void _markConversationRoundAccepted({
    required String locationId,
    required String clientMsgId,
  }) {
    final resolvedLocationId = locationId.trim();
    final current =
        _state.conversationRoundStatesByLocation[resolvedLocationId];
    if (current == null || current.clientMsgId != clientMsgId.trim()) return;
    if (current.phase != ConversationRoundPhase.submitting) return;
    _replaceConversationRoundState(
      resolvedLocationId,
      current.copyWith(phase: ConversationRoundPhase.awaitingRound),
    );
  }

  void _bindWaitingConversationRound({
    required String locationId,
    required String conversationRoundId,
  }) {
    final resolvedLocationId = locationId.trim();
    final resolvedRoundId = conversationRoundId.trim();
    if (resolvedLocationId.isEmpty || resolvedRoundId.isEmpty) return;
    if (_isRecentlyClosedConversationRound(
      resolvedLocationId,
      resolvedRoundId,
    )) {
      return;
    }
    final current =
        _state.conversationRoundStatesByLocation[resolvedLocationId];
    if (current != null &&
        (current.conversationRoundId.isEmpty ||
            current.conversationRoundId == resolvedRoundId)) {
      if (current.phase == ConversationRoundPhase.processing &&
          current.conversationRoundId == resolvedRoundId) {
        return;
      }
      _replaceConversationRoundState(
        resolvedLocationId,
        current.copyWith(
          phase: ConversationRoundPhase.processing,
          conversationRoundId: resolvedRoundId,
        ),
      );
      return;
    }

    // A server-started round (for example automatic P3) has no local send.
    // If it replaces an older round, its own 30-second window starts now.
    final startedAt = DateTime.now();
    final roundState = ConversationRoundState(
      phase: ConversationRoundPhase.processing,
      conversationRoundId: resolvedRoundId,
      startedAt: startedAt,
      deadlineAt: startedAt.add(_conversationRoundTimeout),
      generation: ++_conversationRoundGeneration,
    );
    _replaceConversationRoundState(resolvedLocationId, roundState);
    _scheduleConversationRoundTimeout(resolvedLocationId, roundState);
  }

  void _bindCanonicalConversationRound(WorldChatroomMessage message) {
    if (!message.isCanonicalUserMessage) return;
    final locationId = message.locationId.trim();
    final clientMsgId = message.clientMsgId.trim();
    final conversationRoundId = message.conversationRoundId.trim();
    if (locationId.isEmpty ||
        clientMsgId.isEmpty ||
        conversationRoundId.isEmpty) {
      return;
    }
    final current = _state.conversationRoundStatesByLocation[locationId];
    if (current == null ||
        current.clientMsgId != clientMsgId ||
        current.conversationRoundId.isNotEmpty) {
      return;
    }
    _replaceConversationRoundState(
      locationId,
      current.copyWith(
        phase: ConversationRoundPhase.processing,
        conversationRoundId: conversationRoundId,
      ),
    );
  }

  void _completeConversationRound({
    required String locationId,
    required String conversationRoundId,
  }) {
    final resolvedLocationId = locationId.trim();
    final resolvedRoundId = conversationRoundId.trim();
    final current =
        _state.conversationRoundStatesByLocation[resolvedLocationId];
    if (resolvedRoundId.isEmpty) return;
    _rememberClosedConversationRound(resolvedLocationId, resolvedRoundId);
    if (current == null || current.conversationRoundId != resolvedRoundId) {
      return;
    }
    _clearConversationRound(
      resolvedLocationId,
      expectedGeneration: current.generation,
      action: 'conversationRoundEnded',
    );
  }

  void _failSubmittingConversationRound({
    required String locationId,
    required String clientMsgId,
  }) {
    final resolvedLocationId = locationId.trim();
    final current =
        _state.conversationRoundStatesByLocation[resolvedLocationId];
    if (current == null || current.clientMsgId != clientMsgId.trim()) return;
    _clearConversationRound(
      resolvedLocationId,
      expectedGeneration: current.generation,
      action: 'conversationRoundSendFailed',
    );
  }

  void _completeLegacyCharacterRound(WorldChatroomMessage message) {
    if (_session?.protocolVersion != ChatroomProtocolVersion.legacy ||
        message.streaming ||
        message.senderType.trim().toLowerCase() != 'character') {
      return;
    }
    _completeConversationRound(
      locationId: message.locationId,
      conversationRoundId: message.conversationRoundId,
    );
  }

  void _replaceConversationRoundState(
    String locationId,
    ConversationRoundState roundState,
  ) {
    final next = <String, ConversationRoundState>{
      ..._state.conversationRoundStatesByLocation,
      locationId: roundState,
    };
    _setState(
      _state.copyWith(
        conversationRoundStatesByLocation:
            Map<String, ConversationRoundState>.unmodifiable(next),
      ),
    );
  }

  void _scheduleConversationRoundTimeout(
    String locationId,
    ConversationRoundState roundState,
  ) {
    _conversationRoundTimers.remove(locationId)?.cancel();
    final remaining = roundState.deadlineAt.difference(DateTime.now());
    _conversationRoundTimers[locationId] = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        final current = _state.conversationRoundStatesByLocation[locationId];
        if (current == null || current.generation != roundState.generation) {
          return;
        }
        _clearConversationRound(
          locationId,
          expectedGeneration: roundState.generation,
          action: 'conversationRoundTimedOut',
        );
      },
    );
  }

  void _clearConversationRound(
    String locationId, {
    required int expectedGeneration,
    required String action,
  }) {
    final current = _state.conversationRoundStatesByLocation[locationId];
    if (current == null || current.generation != expectedGeneration) return;
    _rememberClosedConversationRound(locationId, current.conversationRoundId);
    _conversationRoundTimers.remove(locationId)?.cancel();
    final next = <String, ConversationRoundState>{
      ..._state.conversationRoundStatesByLocation,
    }..remove(locationId);
    _setState(
      _state.copyWith(
        conversationRoundStatesByLocation:
            Map<String, ConversationRoundState>.unmodifiable(next),
      ),
    );
    _recordServiceQueueDebug(
      action: action,
      locationId: locationId,
      details: <String, Object?>{
        'clientMsgId': current.clientMsgId,
        'conversationRoundId': current.conversationRoundId,
        'elapsedMs': DateTime.now()
            .difference(current.startedAt)
            .inMilliseconds,
      },
    );
  }

  void _clearAllConversationRounds() {
    for (final timer in _conversationRoundTimers.values) {
      timer.cancel();
    }
    _conversationRoundTimers.clear();
    _closedConversationRoundExpirations.clear();
    if (_state.conversationRoundStatesByLocation.isEmpty) return;
    _setState(
      _state.copyWith(
        conversationRoundStatesByLocation:
            const <String, ConversationRoundState>{},
      ),
    );
  }

  bool _isRecentlyClosedConversationRound(
    String locationId,
    String conversationRoundId,
  ) {
    final now = DateTime.now();
    _closedConversationRoundExpirations.removeWhere(
      (_, expiresAt) => !expiresAt.isAfter(now),
    );
    final expiresAt =
        _closedConversationRoundExpirations['$locationId:$conversationRoundId'];
    return expiresAt?.isAfter(now) ?? false;
  }

  void _rememberClosedConversationRound(
    String locationId,
    String conversationRoundId,
  ) {
    final resolvedLocationId = locationId.trim();
    final resolvedRoundId = conversationRoundId.trim();
    if (resolvedLocationId.isEmpty || resolvedRoundId.isEmpty) return;
    _closedConversationRoundExpirations['$resolvedLocationId:$resolvedRoundId'] =
        DateTime.now().add(_closedConversationRoundRetention);
  }

  void applyWorldSnapshot(WorldDetail world) {
    _throwIfDisposed();
    final entities = _entitiesFromWorld(world);
    _setState(
      _state.copyWith(
        world: world,
        locationTree: world.locationTree,
        processedLocationTree: world.processedLocationTree,
        entitiesById: entities,
        entitiesByLocation: _entitiesByLocation(entities),
        messagesByLocation: _leafLocationMessageQueues(
          world,
          _state.messagesByLocation,
        ),
      ),
    );
  }

  Future<WorldDetail?> refreshWorldSnapshot() {
    _throwIfDisposed();
    final activeDrain = _worldRefreshDrain;
    if (activeDrain != null) return activeDrain;
    return _scheduleWorldRefresh();
  }

  Future<void> refreshUserLocations() async {
    _throwIfDisposed();
    if (_worldId.trim().isEmpty) return;
    await _scheduleUserLocationsRefresh();
  }

  Future<void> connect({
    required String worldId,
    required ChatroomConnectionIdentity identity,
  }) async {
    _throwIfDisposed();
    final nextWorldId = worldId.trim();
    if (_worldId != nextWorldId ||
        (_identity != null && _identity!.userId != identity.userId)) {
      _replyActionsController?.dispose();
      _replyActionsController = null;
      _inspirations?.dispose();
      _inspirations = null;
      _suspendInspirations();
      _completedReplyRounds.clear();
      _cancelHistoryRefreshes();
      _deletedMessageIds.clear();
      _publishedContentUpdateOccurrences.clear();
    }
    _worldId = nextWorldId;
    if (_worldId.isEmpty) {
      throw const ChatroomProtocolException('worldId is required');
    }
    _identity = identity;
    _userDisconnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_desiredLocationId.isNotEmpty) {
      unawaited(_hydrateLocalMessagesForLocation(_desiredLocationId));
    }
    await _connectOnce();
  }

  Future<ChatroomJoined> join({
    required String locationId,
    bool announceUserEntry = true,
  }) async {
    _throwIfDisposed();
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty) {
      throw const ChatroomProtocolException('locationId is required');
    }
    _desiredLocationId = resolvedLocationId;
    if (_lastUserEnterLocationCommandId != resolvedLocationId) {
      _lastUserEnterLocationCommandId = resolvedLocationId;
      _pendingUserEnterLocationCommandId = announceUserEntry
          ? resolvedLocationId
          : '';
    } else if (!announceUserEntry &&
        _pendingUserEnterLocationCommandId == resolvedLocationId) {
      _pendingUserEnterLocationCommandId = '';
    }
    unawaited(_hydrateLocalMessagesForLocation(resolvedLocationId));
    final existing = _joinCompleter;
    if (existing != null) return existing.future;

    final completer = Completer<ChatroomJoined>();
    _joinCompleter = completer;
    unawaited(_joinDesiredLocation(completer));
    return completer.future;
  }

  Future<void> hydrateLocalMessages({
    required String worldId,
    required String locationId,
    String? ownerUid,
    Iterable<String> locationAliases = const <String>[],
  }) async {
    final stopwatch = _chatroomHydrateMetricsEnabled
        ? (Stopwatch()..start())
        : null;
    _throwIfDisposed();
    final resolvedWorldId = worldId.trim();
    final resolvedLocationId = locationId.trim();
    if (resolvedWorldId.isEmpty || resolvedLocationId.isEmpty) return;
    if (_worldId.isEmpty) _worldId = resolvedWorldId;
    final storageLocationIds = _orderedNonEmpty([
      ...locationAliases,
      resolvedLocationId,
    ]);
    _logChatroomHydrateMetric(
      'request start world=$resolvedWorldId state=$resolvedLocationId '
      'storageAliases=${storageLocationIds.join(',')} '
      'owner=${ownerUid?.trim().isNotEmpty == true ? 'provided' : 'service'}',
    );
    LocationChatDebugSlice.recordEvent(
      source: 'service',
      action: 'hydrateStart',
      worldId: resolvedWorldId,
      locationId: resolvedLocationId,
      details: {
        'storageAliases': storageLocationIds,
        'ownerSource': ownerUid?.trim().isNotEmpty == true
            ? 'provided'
            : 'service',
      },
    );
    final hydrations = storageLocationIds.map(
      (storageLocationId) => _hydrateLocalMessagesForLocation(
        storageLocationId,
        worldId: resolvedWorldId,
        ownerUid: ownerUid,
        stateLocationId: resolvedLocationId,
      ),
    );
    await Future.wait(hydrations);
    _logChatroomHydrateMetric(
      'request done world=$resolvedWorldId state=$resolvedLocationId '
      'stateCount=${_state.messagesByLocation[resolvedLocationId]?.length ?? 0} '
      'elapsed=${stopwatch?.elapsedMilliseconds}ms',
    );
    _recordServiceQueueDebug(
      action: 'hydrateDone',
      locationId: resolvedLocationId,
      details: {
        'storageAliases': storageLocationIds,
        'elapsedMs': stopwatch?.elapsedMilliseconds,
      },
    );
  }

  Future<List<WorldChatroomMessage>> loadCachedMessages({
    required String worldId,
    required String locationId,
    String? ownerUid,
    Iterable<String> locationAliases = const <String>[],
    int limit = 20,
    bool updateState = true,
  }) async {
    _throwIfDisposed();
    final resolvedWorldId = worldId.trim();
    final resolvedLocationId = locationId.trim();
    if (resolvedWorldId.isEmpty || resolvedLocationId.isEmpty || limit <= 0) {
      return const <WorldChatroomMessage>[];
    }
    if (_worldId.isEmpty) _worldId = resolvedWorldId;
    final resolvedOwnerUid = ownerUid?.trim().isNotEmpty == true
        ? ownerUid!.trim()
        : _storageOwnerUid;
    if (resolvedOwnerUid.isEmpty) return const <WorldChatroomMessage>[];

    if (_historyRefreshes.containsKey(resolvedLocationId)) {
      return const <WorldChatroomMessage>[];
    }
    final ticket = _historyTicket(resolvedLocationId);
    final storageLocationIds = _orderedNonEmpty([
      ...locationAliases,
      resolvedLocationId,
    ]);
    var messages = const <WorldChatroomMessage>[];
    for (final storageLocationId in storageLocationIds) {
      final localMessages = await _messageStorage.loadLatestMessages(
        ownerUid: resolvedOwnerUid,
        worldId: resolvedWorldId,
        locationId: storageLocationId,
        limit: limit,
      );
      if (!_historyIsCurrent(resolvedLocationId, ticket)) {
        return const <WorldChatroomMessage>[];
      }
      for (final json in localMessages) {
        final message = WorldChatroomMessage.fromStorageJson(json);
        messages = _trimMessageList(
          _upsertIntoList(
            messages,
            message.locationId == resolvedLocationId
                ? message
                : message.copyWith(locationId: resolvedLocationId),
          ),
          limit,
        );
      }
    }
    if (updateState && messages.isNotEmpty) {
      _upsertMessages(messages, persist: false);
    }
    if (LocationChatDebugSlice.enabled) {
      LocationChatDebugSlice.recordEvent(
        source: 'service',
        action: 'loadCached',
        worldId: resolvedWorldId,
        locationId: resolvedLocationId,
        details: {
          'ownerUid': resolvedOwnerUid,
          'storageAliases': storageLocationIds,
          'limit': limit,
          'updateState': updateState,
          'loaded': messages.length,
          'messages': LocationChatDebugSlice.debugWorldMessageQueue(messages),
        },
      );
    }
    return messages;
  }

  /// Rebuild the bounded location cache after reconnect or a suspected missed broadcast.
  Future<void> refreshLocationHistory({required String locationId}) {
    _throwIfDisposed();
    return _requestHistoryReplacement(locationId: locationId);
  }

  /// Successful writes stay successful even if the subsequent range refresh fails.
  Future<ChatroomMessageMutationResult> batchMutateLlmMessages({
    required String locationId,
    required int conversationRoundId,
    required List<ChatroomLlmMessageOperation> operations,
  }) {
    _throwIfDisposed();
    return _mutateLlmReplies(
      locationId: locationId,
      conversationRoundId: conversationRoundId,
      operations: List.unmodifiable(operations),
    );
  }

  bool isMutatingLlmMessages({
    required String locationId,
    required int conversationRoundId,
  }) => _pendingMessageMutationKeys.contains(
    _messageMutationKey(locationId.trim(), conversationRoundId),
  );

  Future<List<WorldChatroomMessage>> refreshLatestMessages({
    required String locationId,
    int limit = 20,
    bool emitLatestFetched = true,
  }) async {
    _throwIfDisposed();
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty || limit <= 0) {
      return const <WorldChatroomMessage>[];
    }
    if (_worldId.isEmpty) return const <WorldChatroomMessage>[];
    final fetchKey =
        'location\u001F$_worldId\u001F$resolvedLocationId\u001F$limit\u001F$emitLatestFetched';
    final existingFetch = _latestMessageFetchFutures[fetchKey];
    if (existingFetch != null) {
      return existingFetch;
    }
    final fetch = _fetchLatestLocationMessagesWithFailure(
      locationId: resolvedLocationId,
      limit: limit,
      emitLatestFetched: emitLatestFetched,
    );
    LocationChatDebugSlice.recordEvent(
      source: 'service',
      action: 'refreshLatestStart',
      worldId: _worldId,
      locationId: resolvedLocationId,
      details: {'limit': limit, 'emitLatestFetched': emitLatestFetched},
    );
    _latestMessageFetchFutures[fetchKey] = fetch;
    try {
      return await fetch;
    } finally {
      if (identical(_latestMessageFetchFutures[fetchKey], fetch)) {
        _latestMessageFetchFutures.remove(fetchKey);
      }
    }
  }

  Future<void> initializeLeafLocationQueues({
    Iterable<String>? locationIds,
    int latestLimit = 20,
    int concurrency = _defaultLocationQueueInitConcurrency,
  }) async {
    _throwIfDisposed();
    if (_worldId.isEmpty || latestLimit <= 0) return;
    final ids = _orderedNonEmpty(
      locationIds ?? _leafLocationIdsForCurrentWorld(),
    );
    if (ids.isEmpty) return;
    final stopwatch = _chatroomHydrateMetricsEnabled
        ? (Stopwatch()..start())
        : null;
    _logChatroomHydrateMetric(
      'leaf queue init start world=$_worldId locations=${ids.length} '
      'limit=$latestLimit concurrency=$concurrency',
    );
    _recordServiceQueueDebug(
      action: 'leafQueueInitStart',
      locationId: '',
      details: {
        'locations': ids,
        'limit': latestLimit,
        'concurrency': concurrency,
      },
    );
    await _runLimited<String>(
      ids,
      math.max(1, concurrency),
      (locationId) => _initializeLeafLocationQueue(
        locationId: locationId,
        latestLimit: latestLimit,
      ),
    );
    _logChatroomHydrateMetric(
      'leaf queue init done world=$_worldId locations=${ids.length} '
      'elapsed=${stopwatch?.elapsedMilliseconds}ms',
    );
    _recordServiceQueueDebug(
      action: 'leafQueueInitDone',
      locationId: '',
      details: {'locations': ids, 'elapsedMs': stopwatch?.elapsedMilliseconds},
    );
  }

  Future<void> leave() async {
    _throwIfDisposed();
    _desiredLocationId = '';
    _lastUserEnterLocationCommandId = '';
    _pendingUserEnterLocationCommandId = '';
    final joinCompleter = _joinCompleter;
    _joinCompleter = null;
    if (joinCompleter != null && !joinCompleter.isCompleted) {
      joinCompleter.completeError(
        const ChatroomFailureEvent(
          code: 'join_cancelled',
          message: 'Something went wrong',
          sourceType: 'leave',
          requestType: 'join',
        ),
      );
    }
    final session = _session;
    _setState(_state.copyWith(joining: false, joinedLocationId: ''));
    if (session == null) return;
    try {
      await session.leave();
    } catch (e) {
      final failure = e is ChatroomFailureEvent
          ? e
          : ChatroomFailureEvent(
              code: 'leave_failed',
              message: 'Something went wrong',
              sourceType: 'leave',
              requestType: 'leave',
              cause: e,
            );
      _recordFailure(failure);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _suspendInspirations();
    _cancelHistoryRefreshes();
    _userDisconnected = true;
    _userLocationsRefreshGeneration += 1;
    _userLocationsRefreshPending = false;
    _latestWorldMessagesRefreshPending = false;
    _worldRefreshPending = false;
    _pendingMapContentDetection = false;
    _pendingCharacterContentDetection = false;
    _pendingWorldRefreshSocketCurrentTime = '';
    _desiredLocationId = '';
    _lastUserEnterLocationCommandId = '';
    _pendingUserEnterLocationCommandId = '';
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _clearAllConversationRounds();
    await _detachSession(disconnect: true);
    await _worldRefreshDrain;
    _queuedNotificationWorldRefreshes.clear();
    _setState(
      _state.copyWith(
        connected: false,
        joining: false,
        joinedLocationId: '',
        reconnecting: false,
      ),
    );
  }

  ChatroomSendHandle sendMessage(String text, {String? clientMsgId}) {
    final session = _session;
    if (session == null) {
      throw const ChatroomProtocolException('chatroom is not connected');
    }
    final requestedClientMsgId = clientMsgId?.trim() ?? '';
    final resolvedClientMsgId = requestedClientMsgId.isNotEmpty
        ? requestedClientMsgId
        : '${DateTime.now().microsecondsSinceEpoch}-${++_sendClientMessageSequence}';
    final roundLocationId = _state.joinedLocationId.trim();
    _startSubmittingConversationRound(
      locationId: roundLocationId,
      clientMsgId: resolvedClientMsgId,
    );
    final canonicalCompleter = _canonicalEchoCompleters.putIfAbsent(
      resolvedClientMsgId,
      Completer<WorldChatroomMessage>.new,
    );
    unawaited(
      canonicalCompleter.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      ),
    );
    late final Future<ChatroomAck> ackFuture;
    try {
      ackFuture = session.sendMessage(text, clientMsgId: resolvedClientMsgId);
    } catch (error, stackTrace) {
      _failSubmittingConversationRound(
        locationId: roundLocationId,
        clientMsgId: resolvedClientMsgId,
      );
      if (identical(
        _canonicalEchoCompleters[resolvedClientMsgId],
        canonicalCompleter,
      )) {
        _canonicalEchoCompleters.remove(resolvedClientMsgId);
      }
      if (!canonicalCompleter.isCompleted) {
        canonicalCompleter.completeError(error, stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final receipt = ackFuture
        .then((ack) {
          _markConversationRoundAccepted(
            locationId: roundLocationId,
            clientMsgId: resolvedClientMsgId,
          );
          return ChatroomSendReceipt.fromAck(
            ack,
            fallbackClientMsgId: resolvedClientMsgId,
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          _failSubmittingConversationRound(
            locationId: roundLocationId,
            clientMsgId: resolvedClientMsgId,
          );
          if (identical(
            _canonicalEchoCompleters[resolvedClientMsgId],
            canonicalCompleter,
          )) {
            _canonicalEchoCompleters.remove(resolvedClientMsgId);
          }
          if (!canonicalCompleter.isCompleted) {
            canonicalCompleter.completeError(error, stackTrace);
          }
          Error.throwWithStackTrace(error, stackTrace);
        });
    return ChatroomSendHandle(
      clientMsgId: resolvedClientMsgId,
      receipt: receipt,
      canonicalMessage: canonicalCompleter.future,
    );
  }

  /// Stops waiting for a canonical user echo without affecting message
  /// ingestion. A late echo will still be merged into the location queue.
  bool cancelCanonicalMessageWait(String clientMsgId, {Object? reason}) {
    final resolvedClientMsgId = clientMsgId.trim();
    if (resolvedClientMsgId.isEmpty) return false;
    final completer = _canonicalEchoCompleters.remove(resolvedClientMsgId);
    if (completer == null) return false;
    if (!completer.isCompleted) {
      completer.completeError(
        reason ??
            ChatroomFailureEvent(
              code: 'canonical_echo_cancelled',
              message: 'Stopped waiting for the canonical user message',
              clientMsgId: resolvedClientMsgId,
              sourceType: 'send_message',
              requestType: 'send_message',
            ),
      );
    }
    return true;
  }

  Future<WorldChatroomOlderMessagesPage> loadOlderMessages({
    required String locationId,
    required int beforeMessageId,
    int limit = 20,
  }) async {
    _throwIfDisposed();
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty ||
        _worldId.isEmpty ||
        beforeMessageId <= 0 ||
        limit <= 0) {
      return const WorldChatroomOlderMessagesPage(
        loadedCount: 0,
        hasMore: false,
      );
    }
    _requireHistoryAvailable(resolvedLocationId);
    final ticket = _historyTicket(resolvedLocationId);
    void checkCurrent() {
      if (!_historyIsCurrent(resolvedLocationId, ticket)) {
        throw const ChatroomProtocolException('History cursor invalidated');
      }
    }

    final loadedMessageKeys = <String>{};
    final currentLocationMessages =
        _state.messagesByLocation[resolvedLocationId] ??
        const <WorldChatroomMessage>[];
    final beforeWorldMessageId = _worldMessageBoundaryForLocationCursor(
      currentLocationMessages,
      beforeMessageId,
    );
    String loadedMessageKey({
      required String senderType,
      required int locationMessageId,
      required int messageId,
    }) {
      if (!isChatroomMessageIdOrderedSupplemental(
            senderType,
            locationMessageId: locationMessageId,
          ) &&
          locationMessageId > 0) {
        return 'location:$locationMessageId';
      }
      return messageId > 0 ? 'message:$messageId' : '';
    }

    final ownerUid = _storageOwnerUid;
    LocationChatDebugSlice.recordEvent(
      source: 'service',
      action: 'loadOlderStart',
      worldId: _worldId,
      locationId: resolvedLocationId,
      details: {
        'beforeMessageId': beforeMessageId,
        'beforeWorldMessageId': beforeWorldMessageId,
        'limit': limit,
      },
    );
    if (ownerUid.isNotEmpty && _worldId.isNotEmpty) {
      final localMessageJson = await _messageStorage.loadMessagesBefore(
        ownerUid: ownerUid,
        worldId: _worldId,
        locationId: resolvedLocationId,
        beforeMessageId: beforeMessageId,
        beforeWorldMessageId: beforeWorldMessageId,
        limit: limit,
      );
      checkCurrent();
      final localMessages = <WorldChatroomMessage>[];
      for (final json in localMessageJson) {
        final message = WorldChatroomMessage.fromStorageJson(json);
        final key = loadedMessageKey(
          senderType: message.senderType,
          locationMessageId: message.locationMessageId,
          messageId: message.messageId,
        );
        if (key.isNotEmpty) loadedMessageKeys.add(key);
        localMessages.add(message);
      }
      // A cached history page is one logical update. Publishing every row
      // separately makes the chat reconcile and rebuild the growing list up
      // to [limit] times during a single upward pagination request.
      _upsertMessages(localMessages, persist: false);
    }

    final response = await _api.chatroomHttp.getMessages(
      worldId: _worldId,
      locationId: resolvedLocationId,
      since: beforeMessageId,
      limit: limit,
    );
    await _mergeFetchedMessages(
      resolvedLocationId,
      response.messages,
      ticket: ticket,
    );
    checkCurrent();
    for (final message in response.messages) {
      final key = loadedMessageKey(
        senderType: message.senderType,
        locationMessageId: message.locationMessageId,
        messageId: message.messageId,
      );
      if (key.isNotEmpty) loadedMessageKeys.add(key);
    }
    final remoteLocationCursorAdvanced = response.messages.any(
      (message) =>
          message.locationMessageId > 0 &&
          message.locationMessageId < beforeMessageId,
    );
    final hasMore = response.hasMore && remoteLocationCursorAdvanced;
    if (response.hasMore && !remoteLocationCursorAdvanced) {
      _logChatroomSocketEvent(
        'older history pagination stopped because location cursor did not '
        'advance world=$_worldId location=$resolvedLocationId '
        'before=$beforeMessageId responseCount=${response.messages.length}',
      );
      _recordServiceQueueDebug(
        action: 'loadOlderCursorNotAdvanced',
        locationId: resolvedLocationId,
        details: {
          'beforeMessageId': beforeMessageId,
          'beforeWorldMessageId': beforeWorldMessageId,
          'responseCount': response.messages.length,
          'remoteHasMore': response.hasMore,
        },
      );
    }
    final page = WorldChatroomOlderMessagesPage(
      loadedCount: loadedMessageKeys.length,
      hasMore: hasMore,
    );
    _recordServiceQueueDebug(
      action: 'loadOlderDone',
      locationId: resolvedLocationId,
      details: {
        'beforeMessageId': beforeMessageId,
        'beforeWorldMessageId': beforeWorldMessageId,
        'limit': limit,
        'loadedCount': page.loadedCount,
        'hasMore': page.hasMore,
      },
    );
    return page;
  }

  Future<void> clearCachedMessages() async {
    _throwIfDisposed();
    final ownerUid = _storageOwnerUid;
    if (ownerUid.isEmpty) return;
    _cancelHistoryRefreshes();
    await Future.wait(_locationWrites.values.toList());
    await _messageStorage.clearCache(ownerUid);
    _deletedMessageIds.clear();
    _localMessageCacheGeneration += 1;
    _localHydratedMessageKeys.clear();
    _localHydratingMessageFutures.clear();
    _setState(
      _state.copyWith(
        worldMessages: const <WorldChatroomMessage>[],
        messagesByLocation: _leafLocationMessageQueues(
          _state.world,
          const <String, List<WorldChatroomMessage>>{},
        ),
        streamMessagesByKey: const <String, WorldChatroomMessage>{},
        lastMessageId: 0,
      ),
    );
    LocationChatDebugSlice.recordEvent(
      source: 'service',
      action: 'clearCachedMessages',
      worldId: _worldId,
      details: {'ownerUid': ownerUid},
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _clearAllConversationRounds();
    _disposed = true;
    _replyActionsController?.dispose();
    _replyActionsController = null;
    _inspirations?.dispose();
    _inspirations = null;
    final disposeFailure = const ChatroomFailureEvent(
      code: 'service_disposed',
      message: 'Chatroom service was disposed',
      sourceType: 'send_message',
      requestType: 'send_message',
    );
    for (final completer in _canonicalEchoCompleters.values) {
      if (!completer.isCompleted) completer.completeError(disposeFailure);
    }
    _canonicalEchoCompleters.clear();
    _userLocationsRefreshGeneration += 1;
    _userLocationsRefreshPending = false;
    _latestWorldMessagesRefreshPending = false;
    await disconnect();
    await _states.close();
    await _failures.close();
    await _balanceAlerts.close();
    await _latestFetchedMessages.close();
  }
}
