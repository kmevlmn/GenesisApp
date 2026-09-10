import 'dart:async';

import '../../features/location_chat_reply/inspiration/inspiration.dart';

import 'package:flutter/foundation.dart';

import '../api_exception.dart';
import 'chatroom_client.dart';
import 'chatroom_http_api.dart';
import 'chatroom_http_models.dart';
import 'chatroom_models.dart';
import 'chatroom_reply_action_storage.dart';
import 'world_chatroom_service.dart' show WorldChatroomMessage;

part '../../features/location_chat_reply/regenerate/src/chatroom_regenerate_action.dart';
part '../../features/location_chat_reply/go_on/src/chatroom_go_on_action.dart';
part '../../features/location_chat_reply/edit/src/chatroom_edit_action.dart';

/// A stable editor identity; the messages are an authoritative, complete snapshot.
class ChatroomReplyEditorTarget {
  ChatroomReplyEditorTarget({
    required this.worldId,
    required this.locationId,
    required this.roundId,
    required this.cardId,
    required this.messages,
    required this.canEdit,
    required this.canDelete,
    required ChatroomReplyRoundState state,
  }) : _state = state,
       _openedRevision = state.completionRevision;

  final String worldId, locationId;
  final int roundId;
  final int? cardId;
  final List<WorldChatroomMessage> messages;
  final bool canEdit, canDelete;
  final ChatroomReplyRoundState _state;
  final int _openedRevision;
  bool get frozen => _state.frozen;
  bool get editorShouldClose =>
      _state.completionRevision > _openedRevision &&
      !_state.busy &&
      _state.error == null;
  List<ChatroomLlmMessageOperation> get draft =>
      List.unmodifiable(_state._drafts[cardId ?? 0] ?? const []);
  List<ChatroomLlmMessageOperation> get draftOperations => draft;
}

/// Mutable internally, read-only to widgets. Candidate bodies never enter history.
class ChatroomReplyRoundState {
  ChatroomReplyRoundState._(this._controller, this.locationId, this.roundId);

  final ChatroomReplyActionsController _controller;
  final String locationId;
  final int roundId;
  String _owner = '';
  bool _entryRound = false;
  bool _invalidated = false;
  bool _active = false;
  bool _ended = false;
  bool _roundFailed = false;
  bool _generating = false;
  bool _regenerateDispatching = false;
  bool _busy = false;
  bool _frozen = false;
  bool _confirmed = false;
  bool _canRegenerate = true;
  bool _canConfirm = false;
  int _viewedCardId = 0;
  int _lastCompleteCardId = 0;
  int _selectedCardId = 0;
  int _generation = 0;
  int _query = 0;
  int _presentationRevision = 0;
  int _completionRevision = 0;
  int? _fixedCardId;
  String? _selectionRequestId;
  String? _regenerationRequestId;
  Object? _error;
  ChatroomLlmCardsResponse? _cardsResponse;
  ChatroomLlmCardsResponse? _cachedCards;
  int? _cardsCachedAt;
  int _cardsCacheVersion = 0;
  Future<ChatroomLlmCardsResponse>? _cardsFetch;
  final _cards = <ChatroomLlmCard>[];
  List<WorldChatroomMessage> _formal = const [];
  final _drafts = <int, List<ChatroomLlmMessageOperation>>{};
  final _draftBaselines = <int, Map<int, String>>{};
  final _uncertainBatches = <int>{};
  final _openEditors = <int>{};
  final _streamMessages = <int, Map<int, _CandidateMessage>>{};
  final _authoritativeCards = <int>{};
  final _cardTerminals = <int, ChatroomLlmCardGenerationEnd>{};
  Timer? _regenerationStreamStartTimer;
  Timer? _regenerationStreamEndTimer;
  int? _watchedRegenerationCardId;
  bool _regenerationStreamStarted = false;
  Timer? _goOnStreamStartTimer;
  Timer? _goOnStreamEndTimer;
  bool _goOnStreamStarted = false;
  _PendingGoOn? _goOn;

  List<ChatroomLlmCard> get cards => List.unmodifiable(_cards);
  int get viewedCardId => _viewedCardId;
  int get lastCompleteCardId => _lastCompleteCardId;
  int get selectedCardId => _selectedCardId;
  int get presentationRevision => _presentationRevision;
  int get completionRevision => _completionRevision;
  bool get sourceOwnerKnown => _owner.isNotEmpty;
  bool get isOwnRound => _owner == _controller.ownerUid;
  bool get confirmed => _confirmed;
  bool get hasCardGroup => _cards.isNotEmpty;
  bool get provisional => _cards.any((card) => card.cardId <= 0);
  bool get showCandidates => hasCardGroup && !confirmed;
  bool get generating =>
      _regenerateDispatching ||
      _generating ||
      _cards.any((card) => !_terminal(card.generationState));
  bool get busy => _busy;
  bool get frozen => _frozen;
  Object? get error => _error;
  bool get complete => !_active && (_ended || _formal.any(_isReply));
  bool get isLatest => _controller._latest[locationId] == roundId;
  bool get goOnPending => _goOn != null && !_goOn!.finished;
  bool get goOnUnknown =>
      goOnPending && _goOn!.uncertain && _goOn!.roundId == null;
  int? get goOnRoundId => _goOn?.roundId;
  bool get canRegenerate =>
      _eligible &&
      !_entryRound &&
      !busy &&
      !frozen &&
      !generating &&
      _canRegenerate &&
      !confirmed &&
      _cards.length < 10;
  bool get canGoOn =>
      _eligible &&
      !busy &&
      !frozen &&
      !_controller._hasPendingGoOn(locationId) &&
      (!showCandidates || _completeCard(viewedCard));
  bool get canEdit =>
      isOwnRound &&
      complete &&
      !busy &&
      !frozen &&
      _controller._isReady(locationId) &&
      (!showCandidates || (_completeCard(viewedCard) && viewedCard!.canEdit));
  bool get _eligible =>
      isLatest &&
      !_invalidated &&
      isOwnRound &&
      complete &&
      _formal.any(_isReply) &&
      _controller._isReady(locationId) &&
      !_controller._isTickLocked();
  ChatroomLlmCard? get viewedCard => _card(_viewedCardId);

  int get inspirationTailMessageId => _formal.fold<int>(
    0,
    (tail, message) =>
        message.locationMessageId > tail ? message.locationMessageId : tail,
  );

  ChatroomInspirationSource? get inspirationSource {
    if (!isLatest ||
        _invalidated ||
        !complete ||
        _roundFailed ||
        !_controller._isReady(locationId) ||
        _controller._isTickLocked() ||
        !_formal.any(_isReply) ||
        busy ||
        frozen) {
      return null;
    }
    final card = confirmed ? _card(selectedCardId) : viewedCard;
    if (hasCardGroup &&
        (card == null || !_completeCard(card) || card.cardId <= 0)) {
      return null;
    }
    if (hasCardGroup && !confirmed && !isOwnRound) return null;
    return ChatroomInspirationSource(
      ownerUid: _controller.ownerUid,
      worldId: _controller.worldId,
      locationId: locationId,
      roundId: roundId,
      cardId: isOwnRound ? card?.cardId : null,
      sourceCardId: card == null || card.isOriginal ? 0 : card.cardId,
      tailMessageId: inspirationTailMessageId,
    );
  }

  int get cardPosition =>
      _cards.indexWhere((card) => card.cardId == _viewedCardId) + 1;
  int get cardCount => _cards.length;

  List<WorldChatroomMessage> get formalReplyMessages =>
      List.unmodifiable(_formal.where(_isReply));

  List<WorldChatroomMessage> get displayedMessages {
    if (!showCandidates || _viewedCardId == 0) {
      return formalReplyMessages;
    }
    return messagesForCard(_viewedCardId);
  }

  /// Read-only preview; browsing and persistence are deliberately separate.
  List<WorldChatroomMessage> messagesForCard(int cardId) {
    final card = _card(cardId);
    if (card == null ||
        card.generationState == ChatroomCardGenerationState.failed) {
      return const [];
    }
    final streams = _streamMessages[card.cardId];
    if (!_authoritativeCards.contains(card.cardId) && streams != null) {
      final sorted = streams.values.toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      return List.unmodifiable(
        sorted.map((message) => message.toMessage(locationId, roundId)),
      );
    }
    return List.unmodifiable(card.messages.map(_candidateToWorld));
  }

  bool hasNewCandidateChunk(Set<int> previousCardIds) =>
      _streamMessages.entries.any(
        (entry) =>
            !previousCardIds.contains(entry.key) &&
            entry.value.values.any((message) => message._receivedChunk),
      ) ||
      _cards.any(
        (card) =>
            card.cardId > 0 &&
            !card.isOriginal &&
            !previousCardIds.contains(card.cardId) &&
            card.messages.any((message) => message.content.trim().isNotEmpty),
      );

  bool hasCandidateChunk(int cardId) =>
      (_streamMessages[cardId]?.values.any(
            (message) => message._receivedChunk,
          ) ??
          false) ||
      (_authoritativeCards.contains(cardId) &&
          (_card(cardId)?.messages.isNotEmpty ?? false));

  ChatroomLlmCard? _card(int id) {
    for (final card in _cards) {
      if (card.cardId == id) return card;
    }
    return null;
  }
}

/// Owns one account/world lifetime. Recreate on account or world switches.
class ChatroomReplyActionsController extends ChangeNotifier {
  ChatroomReplyActionsController({
    required this.worldId,
    required this.ownerUid,
    required ChatroomHttpApi httpApi,
    required ChatroomSession? Function() session,
    required bool Function(String locationId) isReady,
    required bool Function() isTickLocked,
    required Future<void> Function(
      String locationId,
      int startRound,
      int endRound,
    )
    refreshFormalRange,
    Future<void> Function(String locationId, int roundId)?
    replaceCompletedRound,
    void Function(String locationId, int roundId)? onGoOnAccepted,
    void Function(String locationId, int roundId)? onGoOnFinished,
    Future<void> Function(String locationId)? refreshLatestHistory,
    Future<void> Function()? refreshWallet,
    ChatroomReplyActionStorage? storage,
    DateTime Function()? now,
    Duration regenerationStreamStartTimeout = const Duration(seconds: 30),
    Duration regenerationStreamEndTimeout = const Duration(seconds: 120),
    Duration goOnStreamStartTimeout = const Duration(seconds: 30),
    Duration goOnStreamEndTimeout = const Duration(seconds: 120),
  }) : _http = httpApi,
       _session = session,
       _isReady = isReady,
       _isTickLocked = isTickLocked,
       _refreshFormalRange = refreshFormalRange,
       _replaceCompletedRound = replaceCompletedRound,
       _onGoOnAccepted = onGoOnAccepted,
       _onGoOnFinished = onGoOnFinished,
       _refreshLatestHistory = refreshLatestHistory,
       _refreshWallet = refreshWallet,
       _storage = storage ?? SqfliteChatroomReplyActionStorage(),
       _now = now ?? DateTime.now,
       _regenerationStreamStartTimeout = regenerationStreamStartTimeout,
       _regenerationStreamEndTimeout = regenerationStreamEndTimeout,
       _goOnStreamStartTimeout = goOnStreamStartTimeout,
       _goOnStreamEndTimeout = goOnStreamEndTimeout;

  final DateTime Function() _now;
  final Duration _regenerationStreamStartTimeout;
  final Duration _regenerationStreamEndTimeout;
  final Duration _goOnStreamStartTimeout;
  final Duration _goOnStreamEndTimeout;
  static const cardsCacheMaxAge = Duration(hours: 24);

  final String worldId, ownerUid;
  final ChatroomHttpApi _http;
  final ChatroomSession? Function() _session;
  final bool Function(String) _isReady;
  final bool Function() _isTickLocked;
  final Future<void> Function(String, int, int) _refreshFormalRange;
  final Future<void> Function(String, int)? _replaceCompletedRound;
  final void Function(String, int)? _onGoOnAccepted;
  final void Function(String, int)? _onGoOnFinished;
  final Future<void> Function(String)? _refreshLatestHistory;
  final Future<void> Function()? _refreshWallet;
  final ChatroomReplyActionStorage _storage;
  final _states = <String, Map<int, ChatroomReplyRoundState>>{};
  final _latest = <String, int>{};
  final _restored = <String, Future<void>>{};
  final _seenEvents = <String>{};
  final _finalizations = <String, Future<void>>{};
  final _active = <String, Set<int>>{};
  final _ownerQueries = <String>{};
  int _latestTick = -1;
  int _latestSubTick = -1;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  int _requestCounter = 0;

  ChatroomReplyRoundState? stateFor(String locationId) =>
      _states[locationId]?[_latest[locationId]];
  Iterable<String> get locationIds => _states.keys;
  ChatroomReplyRoundState? stateForRound(String locationId, int roundId) =>
      _states[locationId]?[roundId];
  Iterable<ChatroomReplyRoundState> statesFor(String locationId) =>
      List.unmodifiable(
        _states[locationId]?.values ?? const <ChatroomReplyRoundState>[],
      );

  ChatroomReplyRoundState _state(String location, int round) =>
      (_states[location] ??= {})[round] ??= ChatroomReplyRoundState._(
        this,
        location,
        round,
      );

  void _notify() {
    if (_disposed) return;
    // Waiting/Go On can advance the latest round before formal history arrives.
    for (final location in locationIds.toList()) {
      for (final state in statesFor(location)) {
        if (!state.isLatest && state._cachedCards != null) {
          _invalidateCardsCache(state);
        }
      }
    }
    notifyListeners();
  }

  void _checkCurrent() {
    if (_disposed) throw StateError('Reply actions disposed');
  }

  String _request(String kind) =>
      '$kind-${DateTime.now().microsecondsSinceEpoch}-${++_requestCounter}';

  /// Hydration/refresh does not finalize candidates. Only deduplicated live
  /// events can do that, so paging or replaying old history is harmless.
  void observeMessages(
    String locationId,
    List<WorldChatroomMessage> messages, {
    Set<int> activeRoundIds = const {},
  }) {
    if (_disposed) return;
    _active[locationId] = {...activeRoundIds};
    final groups = <int, List<WorldChatroomMessage>>{};
    for (final message in messages) {
      final round = message.conversationRoundNumber;
      if (message.locationId != locationId || round <= 0) continue;
      groups.putIfAbsent(round, () => []).add(message);
      final id = message.globalMessageId > 0
          ? message.globalMessageId
          : message.locationMessageId;
      if (id > 0) _remember('message:$locationId:$id');
      if (message.businessType == 'tick') {
        _rememberTick(message.tickNo, message.subTickNo);
      }
    }
    for (final entry in groups.entries) {
      final state = _state(locationId, entry.key);
      state._formal = List.unmodifiable(entry.value);
      state._active =
          activeRoundIds.contains(entry.key) ||
          entry.value.any((m) => m.streaming);
      for (final message in entry.value) {
        if (message.userId.isNotEmpty) state._owner = message.userId;
        if (message.businessType == 'user_enter_location' ||
            message.senderType == 'user_enter_location') {
          state._entryRound = true;
        }
      }
    }
    for (final state in statesFor(locationId)) {
      if (!groups.containsKey(state.roundId)) {
        state._active = activeRoundIds.contains(state.roundId);
      }
    }
    for (final source in statesFor(locationId).toList()) {
      final pending = source._goOn;
      if (pending == null || pending.finished || pending.roundId == null) {
        continue;
      }
      final next = _states[locationId]?[pending.roundId!];
      if (next == null) continue;
      if (next._formal.any((message) => message.streaming)) {
        _noteGoOnStreamStarted(source);
      }
    }
    // Round IDs are positive monotonic server IDs. Include empty waiting rounds.
    final rounds = <int>[
      ...groups.keys,
      ...activeRoundIds,
      if (_latest[locationId] != null) _latest[locationId]!,
    ];
    if (rounds.isNotEmpty) {
      rounds.sort();
      _latest[locationId] = rounds.last;
      for (final state in statesFor(locationId)) {
        if (state.roundId < rounds.last &&
            (state._cachedCards != null || state._cardsFetch != null)) {
          _invalidateCardsCache(state);
        }
      }
    }
    final target = stateFor(locationId);
    if (target != null &&
        !target.sourceOwnerKnown &&
        _isReady(locationId) &&
        _ownerQueries.add('$locationId:${target.roundId}')) {
      _background(target, () async {
        final messages = await _loadRound(locationId, target.roundId);
        _checkCurrent();
        for (final message in messages) {
          if (message.userId.isNotEmpty) target._owner = message.userId;
        }
        _notify();
      });
    }
    _notify();
  }

  Future<void> restore(
    String locationId,
  ) => _restored.putIfAbsent(locationId, () async {
    final saved = await _storage.load(
      ownerUid: ownerUid,
      worldId: worldId,
      locationId: locationId,
    );
    _checkCurrent();
    for (final json in saved) {
      final round = json['round_id'];
      if (round is! int || round <= 0) continue;
      final state = _state(locationId, round);
      // A user action started during disk IO has newer state than this snapshot.
      if (state._generation != 0 ||
          state.busy ||
          state._cardsResponse != null) {
        continue;
      }
      state._owner = json['owner'] as String? ?? state._owner;
      state._entryRound = json['entry_round'] == true;
      state._invalidated = json['invalidated'] == true;
      final baselines = json['draft_baselines'];
      if (baselines is Map) {
        for (final entry in baselines.entries) {
          state._draftBaselines[int.parse(
            '${entry.key}',
          )] = (entry.value as Map).map(
            (id, content) => MapEntry(int.parse('$id'), content as String),
          );
        }
      }
      state._viewedCardId = json['viewed_card_id'] as int? ?? 0;
      state._lastCompleteCardId = json['last_complete_card_id'] as int? ?? 0;
      state._fixedCardId = json['fixed_card_id'] as int?;
      state._selectionRequestId = json['selection_request_id'] as String?;
      state._regenerationRequestId = json['regeneration_request_id'] as String?;
      state._frozen = json['frozen'] == true;
      state._confirmed = json['confirmed'] == true;
      final drafts = json['drafts'];
      if (drafts is Map) {
        for (final entry in drafts.entries) {
          final card = int.tryParse('${entry.key}');
          if (card == null || entry.value is! List) continue;
          state._drafts[card] = (entry.value as List)
              .map(_operationFromJson)
              .toList();
        }
      }
      state._uncertainBatches.addAll(
        (json['uncertain_batches'] as List? ?? []).whereType<int>(),
      );
      if (json['go_on'] is Map) {
        state._goOn = _PendingGoOn.fromJson(
          Map<String, dynamic>.from(json['go_on'] as Map),
        );
      }
      _latest[locationId] = (_latest[locationId] ?? 0) > round
          ? _latest[locationId]!
          : round;
      final cachedAt = json['cards_cached_at'];
      if (json['cards_cache'] != null) {
        if (state._cardsCacheVersion == 0 &&
            state.isLatest &&
            cachedAt is int &&
            _validCardsCacheTime(cachedAt)) {
          try {
            final cached = ChatroomLlmCardsResponse.fromJson(
              json['cards_cache'],
            );
            if (cached.conversationRoundId == round &&
                cached.list.every((card) => _terminal(card.generationState))) {
              state._cachedCards = cached;
              state._cardsCachedAt = cachedAt;
            }
          } on FormatException {
            // A malformed cache must not prevent recovery of operation metadata.
          }
        }
        if (state._cachedCards == null) await _persist(state);
      }
      final accepted = state._goOn;
      if (accepted?.roundId != null) {
        // The hidden Go On trigger is absent from history. Its receipt is
        // durable ownership evidence even after this request has completed.
        final next = _state(locationId, accepted!.roundId!);
        next._owner = ownerUid;
        next._ended = accepted.finished || accepted.ended;
        if (accepted.roundId! > (_latest[locationId] ?? 0)) {
          _latest[locationId] = accepted.roundId!;
        }
      }
      if (_isReady(locationId)) {
        final pending = state._goOn;
        if (pending != null &&
            !pending.finished &&
            pending.roundId != null &&
            !pending.ended) {
          final next = _state(locationId, pending.roundId!);
          next._owner = ownerUid;
          next._active = true;
          if (pending.roundId! > (_latest[locationId] ?? 0)) {
            _latest[locationId] = pending.roundId!;
          }
          _onGoOnAccepted?.call(locationId, pending.roundId!);
          _watchGoOn(state);
        }
      }
    }
    for (final state in statesFor(locationId)) {
      if (!state.isLatest && state._cachedCards != null) {
        _invalidateCardsCache(state);
      }
    }
    _notify();
  });

  /// Card bodies are part of remote history, including preloaded locations.
  /// This read path never finalizes drafts or starts recovery writes.
  Future<void> loadHistoryCards(
    String locationId, {
    required Set<int> roundIds,
    required bool Function() isCurrent,
  }) async {
    await restore(locationId);
    if (_disposed || !isCurrent()) return;
    final state = stateFor(locationId);
    if (state == null ||
        !roundIds.contains(state.roundId) ||
        !state.isOwnRound ||
        !state.complete ||
        state._entryRound ||
        state.busy ||
        state._openEditors.isNotEmpty ||
        state._regenerateDispatching) {
      return;
    }
    try {
      await _loadCards(state, isCurrent: isCurrent);
    } catch (error) {
      if (!_disposed && isCurrent()) {
        state._error = error;
        _notify();
        rethrow;
      }
    }
  }

  /// Called after entry history is loaded, even on a fresh installation with
  /// no saved reply-action metadata. Actions themselves use the local cards.
  Future<void> restoreLocationCards(
    String locationId, {
    bool reloadCards = true,
  }) async {
    await restore(locationId);
    _checkCurrent();
    if (!_isReady(locationId)) return;
    final latest = stateFor(locationId);
    for (final state in statesFor(locationId)) {
      if (!_isReady(locationId)) return;
      if (!state.isOwnRound) continue;
      try {
        if (reloadCards &&
            ((identical(state, latest) &&
                    state.complete &&
                    !state._entryRound) ||
                state.frozen ||
                state._regenerationRequestId != null)) {
          await _loadCards(
            state,
            force: state.frozen || state._regenerationRequestId != null,
          );
        }
        if (!_isReady(locationId)) return;
        if (state.frozen) await finalizeBeforeSend(locationId);
        await _recoverGoOn(state);
      } catch (error) {
        if (!_disposed) state._error = error;
      }
    }
    _notify();
  }

  Future<void> _persist(ChatroomReplyRoundState state) {
    _checkCurrent();
    final value = <String, dynamic>{
      'round_id': state.roundId,
      if (state._cachedCards != null) ...{
        'cards_cached_at': state._cardsCachedAt,
        'cards_cache': _cardsCacheJson(state._cachedCards!),
      },
      'owner': state._owner,
      'entry_round': state._entryRound,
      'invalidated': state._invalidated,
      'draft_baselines': state._draftBaselines.map(
        (card, messages) => MapEntry(
          '$card',
          messages.map((id, content) => MapEntry('$id', content)),
        ),
      ),
      'viewed_card_id': state._viewedCardId,
      'last_complete_card_id': state._lastCompleteCardId,
      'fixed_card_id': state._fixedCardId,
      'selection_request_id': state._selectionRequestId,
      'regeneration_request_id': state._regenerationRequestId,
      'frozen': state._frozen,
      'confirmed': state._confirmed,
      'drafts': state._drafts.map(
        (card, operations) =>
            MapEntry('$card', operations.map(_operationToDraftJson).toList()),
      ),
      'uncertain_batches': state._uncertainBatches.toList(),
      'go_on': state._goOn?.toJson(),
    };
    final write = _writes.then(
      (_) => _storage.save(
        ownerUid: ownerUid,
        worldId: worldId,
        locationId: state.locationId,
        roundId: state.roundId,
        value: value,
      ),
    );
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }

  bool _validCardsCacheTime(int timestamp) {
    final age = _now().millisecondsSinceEpoch - timestamp;
    return age >= 0 && age < cardsCacheMaxAge.inMilliseconds;
  }

  Map<String, dynamic> _cardsCacheJson(ChatroomLlmCardsResponse result) => {
    'conversation_round_id': result.conversationRoundId,
    'original_card_id': result.originalCardId,
    'selected_card_id': result.selectedCardId,
    'active_card_id': result.activeCardId,
    'confirmed': result.confirmed,
    'can_regenerate': result.canRegenerate,
    'can_confirm': result.canConfirm,
    'list': result.list.map((card) => card.rawJson).toList(),
    'total': result.total,
  };

  void _invalidateCardsCache(ChatroomReplyRoundState state) {
    state._cardsCacheVersion++;
    state._query++;
    state._cardsFetch = null;
    final hadCache = state._cachedCards != null;
    state._cachedCards = null;
    state._cardsCachedAt = null;
    if (hadCache) _background(state, () => _persist(state));
  }

  void invalidateCardsOnDisconnect() {
    for (final location in locationIds.toList()) {
      for (final state in statesFor(location)) {
        _cancelRegenerationWatchdog(state);
        _invalidateCardsCache(state);
      }
    }
  }

  /// Clears only cached server snapshots, preserving drafts and recovery receipts.
  Future<void> clearCardsCache(
    String locationId, {
    int? start,
    int? end,
  }) async {
    // Mark current states immediately so pending disk/network reads cannot revive them.
    for (final state in statesFor(locationId)) {
      if ((start == null || state.roundId >= start) &&
          (end == null || state.roundId <= end)) {
        _invalidateCardsCache(state);
      }
    }
    await restore(locationId);
    _checkCurrent();
    for (final state in statesFor(locationId)) {
      if ((start == null || state.roundId >= start) &&
          (end == null || state.roundId <= end)) {
        _invalidateCardsCache(state);
        await _persist(state);
      }
    }
  }

  Future<void> _loadCards(
    ChatroomReplyRoundState state, {
    bool Function()? isCurrent,
    bool force = false,
  }) async {
    if (force ||
        (state._cardsCachedAt != null &&
            !_validCardsCacheTime(state._cardsCachedAt!))) {
      // An authoritative recovery read must never fall back to stale data on error.
      if (state._cachedCards != null) _invalidateCardsCache(state);
    }
    final generation = state._generation;
    final cacheVersion = state._cardsCacheVersion;
    final query = ++state._query;
    var fetched = force ? null : state._cachedCards;
    if (fetched == null) {
      final fetch = state._cardsFetch ??= _http.getLlmCards(
        worldId: worldId,
        locationId: state.locationId,
        conversationRoundId: state.roundId,
      );
      try {
        fetched = await fetch;
      } finally {
        if (identical(state._cardsFetch, fetch)) state._cardsFetch = null;
      }
    }
    final result = fetched;
    _checkCurrent();
    if (generation != state._generation ||
        cacheVersion != state._cardsCacheVersion ||
        query != state._query ||
        (isCurrent != null && !isCurrent())) {
      return;
    }
    if (state.isLatest &&
        result.list.every((card) => _terminal(card.generationState))) {
      state._cardsCachedAt ??= _now().millisecondsSinceEpoch;
      state._cachedCards = result;
    }
    state._cardsResponse = result;
    state._canRegenerate = result.canRegenerate;
    state._canConfirm = result.canConfirm;
    state._selectedCardId = result.selectedCardId;
    state._confirmed = result.confirmed;
    final unresolved = state._card(-1);
    if (unresolved != null &&
        result.activeCardId > 0 &&
        result.list.any(
          (card) =>
              card.cardId == result.activeCardId &&
              card.cardIndex >= unresolved.cardIndex,
        )) {
      if (state._viewedCardId == -1) state._viewedCardId = result.activeCardId;
      state._cards.removeWhere((card) => card.cardId == -1);
    }
    final pending = state._cards
        .where(
          (card) =>
              !result.list.any((item) => item.cardId == card.cardId) &&
              (card.cardId < 0 ||
                  (card.cardId == 0 && result.list.isEmpty) ||
                  !_terminal(card.generationState)),
        )
        .toList();
    state._cards
      ..clear()
      ..addAll(result.list)
      ..addAll(pending);
    state._cards.sort((a, b) => a.cardIndex.compareTo(b.cardIndex));
    for (final card in result.list) {
      if (_terminal(card.generationState)) {
        state._streamMessages.remove(card.cardId);
        state._cardTerminals.remove(card.cardId);
        state._authoritativeCards.add(card.cardId);
      }
    }
    if (state._card(state._viewedCardId) == null) {
      final nextView = result.selectedCardId > 0
          ? result.selectedCardId
          : result.originalCardId;
      if (nextView != state._viewedCardId) {
        state._viewedCardId = nextView;
        state._presentationRevision++;
      }
    }
    if (_completeCard(state.viewedCard)) {
      state._lastCompleteCardId = state._viewedCardId;
    }
    state._generating = state._cards.any(
      (card) => !_terminal(card.generationState),
    );
    if (!state._generating) {
      state._regenerationRequestId = null;
      _cancelRegenerationWatchdog(state);
    } else if (state._regenerationRequestId != null) {
      final activeCardId = result.activeCardId > 0
          ? result.activeCardId
          : state._watchedRegenerationCardId;
      if (activeCardId != null && activeCardId > 0) {
        _watchRegeneration(state, activeCardId);
      }
    }
    await _persist(state);
    _notify();
  }

  Future<void> browse(String locationId, int delta) async {
    final state = stateFor(locationId);
    if (state == null ||
        !state.showCandidates ||
        state.busy ||
        state.frozen ||
        delta == 0) {
      return;
    }
    final index = state._cards.indexWhere(
      (card) => card.cardId == state.viewedCardId,
    );
    final next = index + delta;
    if (next < 0 || next >= state._cards.length) return;
    state._viewedCardId = state._cards[next].cardId;
    if (_completeCard(state.viewedCard)) {
      state._lastCompleteCardId = state.viewedCardId;
    }
    state._presentationRevision++;
    _notify();
    await _persist(state);
  }

  Future<ChatroomReplyRoundState> _target(String locationId) async {
    _checkCurrent();
    final state = stateFor(locationId);
    if (state == null) throw StateError('No identified conversation round');
    if (!state.sourceOwnerKnown) {
      state._formal = await _loadRound(locationId, state.roundId);
      _checkCurrent();
      for (final message in state._formal) {
        if (message.userId.isNotEmpty) state._owner = message.userId;
      }
    }
    if (!state.isOwnRound) {
      throw StateError('This round is not owned by the current user');
    }
    return state;
  }

  Future<void> finalizeBeforeSend(
    String locationId, {
    ChatroomInspirationSource? expectedSource,
  }) async {
    void verify() {
      if (expectedSource != null &&
          !expectedSource.sameOrigin(stateFor(locationId)?.inspirationSource)) {
        throw StateError('The reply changed. Please select inspiration again.');
      }
    }

    verify();
    final existing = _finalizations[locationId];
    if (existing != null) {
      await existing;
      verify();
      return;
    }
    if (expectedSource != null) {
      final sourceState = stateFor(locationId)!;
      if (sourceState.hasCardGroup && !sourceState.confirmed) {
        sourceState._fixedCardId = sourceState.viewedCardId;
        sourceState._frozen = true;
      }
    }
    final task = _finalizeLocation(locationId);
    _finalizations[locationId] = task;
    await task.whenComplete(() {
      if (identical(_finalizations[locationId], task)) {
        _finalizations.remove(locationId);
      }
    });
    verify();
  }

  Future<void> _finalizeLocation(String locationId) async {
    _checkCurrent();
    final targets =
        statesFor(locationId)
            .where(
              (state) =>
                  state.showCandidates ||
                  (state.frozen) ||
                  state._drafts.isNotEmpty ||
                  state._openEditors.isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.roundId.compareTo(b.roundId));
    for (final state in targets) {
      if (!state.isOwnRound) continue;
      if (state.busy) throw StateError('A reply is currently being saved');
      state._fixedCardId ??= _completeCard(state.viewedCard)
          ? state.viewedCardId
          : state.lastCompleteCardId;
      state._frozen = true;
      state._busy = true;
      state._error = null;
      _notify();
      try {
        await _persist(state);
        await _loadCards(state, force: true);
        if (state.confirmed &&
            state._selectionRequestId != null &&
            state.selectedCardId == state._fixedCardId) {
          // GET can recover our successful selection after its ACK was lost.
          // Only retire alternatives; a remaining selected-card draft still
          // needs the conflict path below and must never be silently dropped.
          _retireAlternativeDrafts(state, state.selectedCardId);
        }
        if ((!state.hasCardGroup || state.confirmed) &&
            state._drafts[0]?.isNotEmpty == true) {
          state._formal = await _loadRound(locationId, state.roundId);
        }
        if (!state.confirmed && state.hasCardGroup) {
          final id = state._fixedCardId!;
          final card = state._card(id);
          if (!_completeCard(card)) {
            throw StateError('No complete candidate is available to confirm');
          }
          await _saveDraft(state, _editor(state, cardId: id));
          if (!state._canConfirm) {
            throw StateError('This card group cannot be confirmed');
          }
          _invalidateCardsCache(state);
          state._selectionRequestId ??= _request('select');
          await _persist(state);
          final result = await _http.selectLlmCard(
            worldId: worldId,
            locationId: locationId,
            conversationRoundId: state.roundId,
            cardId: id,
            clientMsgId: state._selectionRequestId!,
          );
          _checkCurrent();
          await _refreshFormalRange(
            locationId,
            result.startConversationRoundId,
            result.endConversationRoundId,
          );
          _checkCurrent();
          state._selectedCardId = result.selectedCardId;
          state._confirmed = true;
          state._viewedCardId = result.selectedCardId;
          _retireAlternativeDrafts(state, result.selectedCardId);
        } else if (!state.hasCardGroup &&
            state._drafts[0]?.isNotEmpty == true) {
          await _saveDraft(state, _editor(state));
        } else if (state.confirmed) {
          if (state._drafts.entries.any(
            (entry) => entry.key > 0 && entry.value.isNotEmpty,
          )) {
            throw StateError(
              'This card was confirmed before its draft could be saved',
            );
          }
          if (state._drafts[0]?.isNotEmpty == true) {
            await _saveDraft(state, _editor(state));
          }
          // A select ACK may have been lost; GET confirmed proves selection,
          // then authoritative formal refresh is still required.
          await _refreshFormalRange(locationId, state.roundId, state.roundId);
        }
        state._openEditors.clear();
        state._frozen = false;
        state._completionRevision++;
        state._presentationRevision++;
        await _persist(state);
      } catch (error) {
        if (!_disposed) {
          state._error = error;
          await _persist(state);
        }
        rethrow;
      } finally {
        state._busy = false;
        _notify();
      }
    }
  }

  void _retireAlternativeDrafts(
    ChatroomReplyRoundState state,
    int selectedCardId,
  ) {
    bool isAlternative(int cardId) => cardId > 0 && cardId != selectedCardId;
    state._drafts.removeWhere((cardId, _) => isAlternative(cardId));
    state._draftBaselines.removeWhere((cardId, _) => isAlternative(cardId));
    state._uncertainBatches.removeWhere(isAlternative);
  }

  bool _hasPendingGoOn(String location) =>
      statesFor(location).any((state) => state.goOnPending);
  ChatroomSession _requireSession() =>
      _session() ?? (throw StateError('Chatroom is disconnected'));

  Future<List<WorldChatroomMessage>> _loadRound(
    String location,
    int round,
  ) async {
    final messages = <int, WorldChatroomMessage>{};
    int? since;
    while (true) {
      final page = await _http.getMessages(
        worldId: worldId,
        locationId: location,
        startConversationRoundId: round,
        endConversationRoundId: round,
        since: since,
        limit: 100,
      );
      _checkCurrent();
      var oldest = since ?? 0;
      for (final message in page.messages) {
        if (message.conversationRoundId != round ||
            message.locationId != location ||
            message.locationMessageId <= 0) {
          throw const FormatException(
            'Authoritative round history has a mismatched identity',
          );
        }
        messages[message.locationMessageId] =
            WorldChatroomMessage.fromHttpMessage(message);
        if (oldest == 0 || message.locationMessageId < oldest) {
          oldest = message.locationMessageId;
        }
      }
      if (!page.hasMore) break;
      if (oldest <= 0 || (since != null && oldest >= since)) {
        throw const FormatException(
          'Round history pagination made no progress',
        );
      }
      since = oldest;
    }
    final sorted = messages.values.toList()
      ..sort((a, b) => a.locationMessageId.compareTo(b.locationMessageId));
    return sorted;
  }

  void receiveEvent(ChatroomEvent event) {
    if (_disposed) return;
    if (event is ChatroomLlmMessageUpdated) {
      if (event.worldId == worldId && event.errNo == 0) {
        unawaited(clearCardsCache(event.locationId).catchError((Object _) {}));
      }
      return;
    }
    if (event is ChatroomLlmCardStream) {
      if (event.worldId != worldId || event.userId != ownerUid) return;
      final state = _state(event.locationId, event.conversationRoundId);
      state._owner = event.userId;
      if (state.confirmed || state._authoritativeCards.contains(event.cardId)) {
        return;
      }
      if (state._viewedCardId == -1) state._viewedCardId = event.cardId;
      state._cards.removeWhere((card) => card.cardId == -1);
      if (state._card(event.cardId) == null) {
        final index =
            state._cards.fold<int>(
              0,
              (v, c) => c.cardIndex > v ? c.cardIndex : v,
            ) +
            1;
        state._cards.add(_placeholder(event.cardId, index));
      }
      final streams = state._streamMessages.putIfAbsent(event.cardId, () => {});
      final message = streams.putIfAbsent(
        event.globalMessageId,
        () => _CandidateMessage(event),
      );
      message.apply(event);
      _noteRegenerationStream(state, event.cardId);
      _invalidateCardsCache(state);
      ++state._generation;
      final terminal = state._cardTerminals[event.cardId];
      if (terminal != null) {
        _completeLocalCard(state, terminal);
        _background(state, () => _persist(state));
      }
      _notify();
    } else if (event is ChatroomLlmCardGenerationEnd) {
      if (event.worldId != worldId || event.userId != ownerUid) return;
      final state = _state(event.locationId, event.conversationRoundId);
      if (state.confirmed ||
          state._authoritativeCards.contains(event.cardId) ||
          state._cardTerminals.containsKey(event.cardId)) {
        return;
      }
      _invalidateCardsCache(state);
      ++state._generation;
      state._cardTerminals[event.cardId] = event;
      _completeLocalCard(state, event);
      if (state._generating && state._regenerationRequestId != null) {
        _watchRegeneration(state, event.cardId, streamStarted: true);
      }
      _notify();
      _background(state, () async {
        await _persist(state);
        if (!_disposed && _refreshWallet != null) {
          try {
            await _refreshWallet();
          } catch (_) {}
        }
      });
    } else if (event is ChatroomWaitingConversationRound) {
      if (event.worldId != worldId) return;
      final round = int.tryParse(event.conversationRoundId);
      if (round == null || round <= 0) return;
      final state = _state(event.locationId, round);
      if (event.userId.isNotEmpty) state._owner = event.userId;
      if (!state._ended) state._active = true;
      if (round > (_latest[event.locationId] ?? 0)) {
        _latest[event.locationId] = round;
      }
      _notify();
    } else if (event is ChatroomEndConversationRound) {
      if (event.worldId != worldId) return;
      final round = int.tryParse(event.conversationRoundId);
      if (round == null || round <= 0) return;
      final state = _state(event.locationId, round);
      state._active = false;
      state._ended = true;
      state._roundFailed = !event.ok;
      if (event.userId.isNotEmpty) state._owner = event.userId;
      for (final source in statesFor(event.locationId)) {
        if (source.goOnPending && source.goOnRoundId == round) {
          source._goOn!.ended = true;
          _background(source, () async {
            await _persist(source);
            await _recoverGoOn(source);
          });
        }
      }
      _notify();
    } else if (event is ChatroomErrorEvent) {
      if (event.worldId != worldId) return;
      for (final state in statesFor(event.locationId)) {
        final pending = state._goOn;
        final eventRound = int.tryParse(event.conversationRoundId);
        if (pending != null &&
            ((event.clientMsgId.isNotEmpty &&
                    event.clientMsgId == pending.clientMsgId) ||
                (eventRound != null && eventRound == pending.roundId))) {
          state._error = event;
          if (!pending.finished) {
            pending.finished = true;
            _cancelGoOnWatchdog(state);
            _rollbackGoOnRound(state);
            final round = pending.roundId;
            if (round != null) _onGoOnFinished?.call(state.locationId, round);
            _background(state, () => _persist(state));
          }
          _notify();
        }
      }
    } else if (event is ChatroomTickAdvanceMessage) {
      if (event.worldId != worldId ||
          !_rememberTick(event.tickNo, event.subTickNo)) {
        return;
      }
      for (final location in _states.keys.toList()) {
        for (final state in statesFor(location)) {
          state._invalidated = true;
        }
        _freezeFromExternal(location, null);
      }
    } else if (event is ChatroomAiStreamStart) {
      if (event.worldId != worldId) return;
      final round = int.tryParse(event.conversationRoundId);
      if (round == null ||
          round <= 0 ||
          event.globalMessageId <= 0 ||
          !_remember('message:${event.locationId}:${event.globalMessageId}')) {
        return;
      }
      for (final source in statesFor(event.locationId)) {
        if (source.goOnPending && source.goOnRoundId == round) {
          _noteGoOnStreamStarted(source);
        }
      }
      _freezeFromExternal(event.locationId, round);
    } else if (event is ChatroomUserEnterLocationMessage) {
      if (event.worldId != worldId) return;
      final round = int.tryParse(event.conversationRoundId);
      if (round == null ||
          round <= 0 ||
          event.globalMessageId <= 0 ||
          !_remember('message:${event.locationId}:${event.globalMessageId}')) {
        return;
      }
      final state = _state(event.locationId, round);
      state._entryRound = true;
      if (event.userId.isNotEmpty) state._owner = event.userId;
      _freezeFromExternal(event.locationId, round);
    } else if (event is ChatroomUserMessage) {
      if (event.worldId != worldId) return;
      final round = int.tryParse(event.conversationRoundId);
      if (round == null || round <= 0) return;
      final state = _state(event.locationId, round);
      if (event.userId.isNotEmpty) state._owner = event.userId;
      final id = event.globalMessageId > 0
          ? event.globalMessageId
          : event.locationMessageId;
      if (id <= 0 || !_remember('message:${event.locationId}:$id')) return;
      _freezeFromExternal(event.locationId, round);
    } else if (event is ChatroomNarratorMessage) {
      if (event.worldId != worldId) return;
      final round = int.tryParse(event.conversationRoundId);
      if (round == null || round <= 0) return;
      final id = event.globalMessageId > 0
          ? event.globalMessageId
          : event.locationMessageId;
      if (id > 0 && _remember('message:${event.locationId}:$id')) {
        _freezeFromExternal(event.locationId, round);
      }
    }
  }

  void _completeLocalCard(
    ChatroomReplyRoundState state,
    ChatroomLlmCardGenerationEnd event,
  ) {
    final old = state._card(event.cardId);
    final streams = state._streamMessages[event.cardId]?.values.toList()
      ?..sort((a, b) => a.index.compareTo(b.index));
    final failed = event.generationState == ChatroomCardGenerationState.failed;
    final complete =
        !failed &&
        streams != null &&
        streams.isNotEmpty &&
        streams.every((m) => m._ended);
    state._cards.removeWhere(
      (card) => card.cardId == event.cardId || card.cardId == -1,
    );
    state._cards.add(
      _assembledCard(
        state,
        event.cardId,
        old?.cardIndex ?? state._cards.length + 1,
        failed
            ? const []
            : (streams ?? [])
                  .map((m) => m.toMessage(state.locationId, state.roundId))
                  .toList(),
        billing: event.billing,
        generation: !failed && !complete
            ? ChatroomCardGenerationState.generating
            : event.generationState,
        editable: complete,
        error: event.error,
      ),
    );
    state._cards.sort((a, b) => a.cardIndex.compareTo(b.cardIndex));
    if (state._viewedCardId == -1) state._viewedCardId = event.cardId;
    if (failed || complete) {
      state._authoritativeCards.add(event.cardId);
      state._streamMessages.remove(event.cardId);
    }
    state._generating = state._cards.any(
      (card) => !_terminal(card.generationState),
    );
    if (!state._generating) {
      state._regenerationRequestId = null;
      _cancelRegenerationWatchdog(state);
    }
    state._canConfirm = true;
    state._canRegenerate = !state.confirmed && state._cards.length < 10;
    state._error = failed
        ? event.errNo != 0
              ? event
              : event.errMsg.isNotEmpty
              ? event.errMsg
              : event.error ?? 'Generation failed'
        : complete
        ? null
        : StateError('Candidate content is incomplete; reload to recover');
    if (complete && state._viewedCardId == event.cardId) {
      state._lastCompleteCardId = event.cardId;
    }
  }

  ChatroomLlmCard _assembledCard(
    ChatroomReplyRoundState state,
    int id,
    int index,
    List<WorldChatroomMessage> messages, {
    required ChatroomCardBilling billing,
    bool isOriginal = false,
    bool editable = true,
    ChatroomCardGenerationState generation =
        ChatroomCardGenerationState.succeeded,
    Object? error,
  }) => ChatroomLlmCard(
    cardId: id,
    cardIndex: index,
    isOriginal: isOriginal,
    generationState: generation,
    canEdit: editable,
    canDelete: editable,
    messages: [
      for (final (position, message) in messages.indexed)
        ChatroomLlmCardMessage(
          cardId: id,
          cardMessageIndex: isOriginal ? position + 1 : message.roundOrder,
          isLlmStreamMessage: message.isLlmStreamMessage,
          message: ChatroomV2Message(
            type: message.businessType,
            worldId: worldId,
            locationId: state.locationId,
            conversationRoundId: state.roundId,
            globalMessageId: message.globalMessageId,
            userId: message.userId,
            senderId: message.senderId,
            senderName: message.senderName,
            senderType: message.senderType,
            messageType: message.messageType,
            currentTime: message.currentTime,
            ts: message.createdAt?.millisecondsSinceEpoch,
            payload: {
              ...message.rawPayload,
              'content': message.content,
              'current_time': message.currentTime,
            },
          ),
          rawJson: const {},
        ),
    ],
    billing: billing,
    createdAt: '',
    rawJson: const {},
    error: error,
  );

  bool _rememberTick(int tick, int subTick) {
    if (tick < _latestTick ||
        (tick == _latestTick && subTick <= _latestSubTick)) {
      return false;
    }
    _latestTick = tick;
    _latestSubTick = subTick;
    return true;
  }

  bool _remember(String key) {
    if (!_seenEvents.add(key)) return false;
    if (_seenEvents.length > 1000) _seenEvents.remove(_seenEvents.first);
    return true;
  }

  void _freezeFromExternal(String location, int? incomingRound) {
    final targets = statesFor(location)
        .where(
          (state) =>
              state.isOwnRound &&
              (state.showCandidates ||
                  state._drafts.isNotEmpty ||
                  state._openEditors.isNotEmpty) &&
              (incomingRound == null || incomingRound > state.roundId),
        )
        .toList();
    if (targets.isEmpty) return;
    for (final state in targets) {
      state._fixedCardId ??= _completeCard(state.viewedCard)
          ? state.viewedCardId
          : state.lastCompleteCardId;
      state._frozen = true;
    }
    _notify();
    if (targets.any((state) => state.busy || state._regenerateDispatching)) {
      for (final state in targets) {
        _background(state, () => _persist(state));
      }
      return;
    }
    _background(targets.first, () => finalizeBeforeSend(location));
  }

  void _background(
    ChatroomReplyRoundState state,
    Future<void> Function() work,
  ) {
    unawaited(
      Future.sync(work).catchError((Object error) {
        if (!_disposed) {
          state._error = error;
          _notify();
        }
      }),
    );
  }

  void _watchRegeneration(
    ChatroomReplyRoundState state,
    int cardId, {
    bool streamStarted = false,
  }) {
    _cancelRegenerationWatchdog(state);
    final card = state._card(cardId);
    if (_disposed || card == null || _terminal(card.generationState)) return;
    state._watchedRegenerationCardId = cardId;
    state._regenerationStreamStarted =
        streamStarted || (state._streamMessages[cardId]?.isNotEmpty ?? false);
    if (state._regenerationStreamStarted) {
      state._regenerationStreamEndTimer = Timer(
        _regenerationStreamEndTimeout,
        () => _recoverTimedOutRegeneration(state, cardId),
      );
    } else {
      state._regenerationStreamStartTimer = Timer(
        _regenerationStreamStartTimeout,
        () => _recoverTimedOutRegeneration(state, cardId),
      );
    }
  }

  void _noteRegenerationStream(ChatroomReplyRoundState state, int cardId) {
    if (state._regenerationRequestId == null ||
        (state._watchedRegenerationCardId != null &&
            state._watchedRegenerationCardId != cardId)) {
      return;
    }
    if (state._regenerationStreamStarted &&
        state._watchedRegenerationCardId == cardId) {
      return;
    }
    state._regenerationStreamStartTimer?.cancel();
    state._regenerationStreamStartTimer = null;
    state._watchedRegenerationCardId = cardId;
    state._regenerationStreamStarted = true;
    state._regenerationStreamEndTimer?.cancel();
    state._regenerationStreamEndTimer = Timer(
      _regenerationStreamEndTimeout,
      () => _recoverTimedOutRegeneration(state, cardId),
    );
  }

  void _recoverTimedOutRegeneration(ChatroomReplyRoundState state, int cardId) {
    final card = state._card(cardId);
    if (_disposed ||
        state._regenerationRequestId == null ||
        state._watchedRegenerationCardId != cardId ||
        card == null ||
        _terminal(card.generationState)) {
      _cancelRegenerationWatchdog(state);
      return;
    }
    state._regenerationStreamStartTimer = null;
    state._regenerationStreamEndTimer = null;
    // A stream event racing the recovery GET must be able to arm a fresh
    // end watchdog even if the stale HTTP response is discarded.
    state._regenerationStreamStarted = false;
    final requestId = state._regenerationRequestId!;
    unawaited(_recoverTimedOutRegenerationFromCards(state, cardId, requestId));
  }

  Future<void> _recoverTimedOutRegenerationFromCards(
    ChatroomReplyRoundState state,
    int cardId,
    String requestId,
  ) async {
    try {
      await _loadCards(state, force: true);
    } catch (error) {
      if (_disposed || state._regenerationRequestId != requestId) return;
      await _failRegenerationLocally(state, cardId, error);
    }
  }

  Future<void> _failRegenerationLocally(
    ChatroomReplyRoundState state,
    int cardId,
    Object error,
  ) async {
    _cancelRegenerationWatchdog(state);
    final card = state._card(cardId);
    if (cardId <= 0) {
      state._cards.removeWhere((item) => item.cardId <= 0);
      state._viewedCardId = state._lastCompleteCardId;
    } else if (card != null && !_terminal(card.generationState)) {
      state._cards.remove(card);
      state._cards.add(
        _assembledCard(
          state,
          card.cardId,
          card.cardIndex,
          const [],
          billing: card.billing,
          editable: false,
          generation: ChatroomCardGenerationState.failed,
          error: error,
        ),
      );
      state._cards.sort((a, b) => a.cardIndex.compareTo(b.cardIndex));
    }
    state._regenerationRequestId = null;
    state._regenerateDispatching = false;
    state._generating = state._cards.any(
      (item) => !_terminal(item.generationState),
    );
    state._canConfirm = state._cards.isNotEmpty;
    state._canRegenerate = !state.confirmed && state._cards.length < 10;
    state._error = error;
    try {
      await _persist(state);
    } catch (_) {
      // A local terminal state must still release the action controls.
    }
    _notify();
  }

  void _cancelRegenerationWatchdog(ChatroomReplyRoundState state) {
    state._regenerationStreamStartTimer?.cancel();
    state._regenerationStreamEndTimer?.cancel();
    state._regenerationStreamStartTimer = null;
    state._regenerationStreamEndTimer = null;
    state._watchedRegenerationCardId = null;
    state._regenerationStreamStarted = false;
  }

  void _watchGoOn(
    ChatroomReplyRoundState source, {
    bool streamStarted = false,
  }) {
    _cancelGoOnWatchdog(source);
    final pending = source._goOn;
    if (_disposed ||
        pending == null ||
        pending.finished ||
        pending.roundId == null) {
      return;
    }
    source._goOnStreamStarted = streamStarted;
    if (streamStarted) {
      source._goOnStreamEndTimer = Timer(
        _goOnStreamEndTimeout,
        () => _recoverTimedOutGoOn(source, pending),
      );
    } else {
      source._goOnStreamStartTimer = Timer(
        _goOnStreamStartTimeout,
        () => _recoverTimedOutGoOn(source, pending),
      );
    }
  }

  void _noteGoOnStreamStarted(ChatroomReplyRoundState source) {
    final pending = source._goOn;
    if (pending == null || pending.finished || pending.roundId == null) return;
    if (source._goOnStreamStarted && source._goOnStreamEndTimer != null) {
      return;
    }
    _watchGoOn(source, streamStarted: true);
  }

  void _recoverTimedOutGoOn(
    ChatroomReplyRoundState source,
    _PendingGoOn pending,
  ) {
    if (_disposed || !identical(source._goOn, pending) || pending.finished) {
      _cancelGoOnWatchdog(source);
      return;
    }
    final message = source._goOnStreamStarted
        ? 'Go on did not finish. Please try again.'
        : 'Go on did not start. Please try again.';
    _cancelGoOnWatchdog(source);
    unawaited(_recoverOrFinishTimedOutGoOn(source, pending, message));
  }

  Future<void> _recoverOrFinishTimedOutGoOn(
    ChatroomReplyRoundState source,
    _PendingGoOn pending,
    String message,
  ) async {
    try {
      await _recoverGoOn(
        source,
        finishIfIncomplete: true,
        incompleteError: StateError(message),
      );
    } catch (_) {
      if (_disposed || !identical(source._goOn, pending) || pending.finished) {
        return;
      }
      pending.finished = true;
      source._error = StateError(message);
      _rollbackGoOnRound(source);
      final round = pending.roundId;
      if (round != null) _onGoOnFinished?.call(source.locationId, round);
      try {
        await _persist(source);
      } catch (_) {
        // The in-memory terminal state must still unlock the UI.
      }
      _notify();
    }
  }

  void _cancelGoOnWatchdog(ChatroomReplyRoundState source) {
    source._goOnStreamStartTimer?.cancel();
    source._goOnStreamEndTimer?.cancel();
    source._goOnStreamStartTimer = null;
    source._goOnStreamEndTimer = null;
    source._goOnStreamStarted = false;
  }

  void _rollbackGoOnRound(ChatroomReplyRoundState source) {
    final round = source._goOn?.roundId;
    if (round == null) return;
    final states = _states[source.locationId];
    final next = states?[round];
    if (next != null) next._active = false;
    if (round != source.roundId) states?.remove(round);
    final remaining = states?.keys.toList() ?? const <int>[];
    _latest[source.locationId] = remaining.isEmpty
        ? source.roundId
        : remaining.reduce((a, b) => a > b ? a : b);
  }

  Future<void> _recoverGoOn(
    ChatroomReplyRoundState source, {
    bool finishIfIncomplete = false,
    Object? incompleteError,
  }) async {
    final pending = source._goOn;
    if (pending == null || pending.finished) return;
    if (pending.roundId == null) {
      // There is no query-by-client-id API. Refresh once, then release the
      // local lock without ever automatically resending this non-idempotent
      // request. A manual retry remains an explicit user decision.
      await _refreshLatestHistory?.call(source.locationId);
      pending.finished = true;
      source._error ??= StateError(
        'Could not confirm Go on. Please try again.',
      );
      await _persist(source);
      _notify();
      return;
    }
    final round = pending.roundId!;
    final next = _state(source.locationId, round);
    final messages = await _loadRound(source.locationId, round);
    _checkCurrent();
    if (!next._ended && !pending.ended && !messages.any(_isReply)) {
      // The contract commits a successful round atomically. Persisted AI
      // replies prove success even when end was lost; an empty/non-AI result
      // does not prove that an accepted request failed.
      if (!finishIfIncomplete) return;
      pending.finished = true;
      source._error =
          incompleteError ??
          StateError('Go on did not finish. Please try again.');
      _rollbackGoOnRound(source);
      _onGoOnFinished?.call(source.locationId, round);
      await _persist(source);
      _notify();
      return;
    }
    if (_replaceCompletedRound != null) {
      await _replaceCompletedRound(source.locationId, round);
    } else {
      await _refreshFormalRange(source.locationId, round, round);
    }
    _checkCurrent();
    next._formal = messages;
    next._active = false;
    next._ended = true;
    pending.finished = true;
    _cancelGoOnWatchdog(source);
    source._error = messages.any(_isReply)
        ? null
        : StateError('No usable reply was persisted');
    next._error = source._error;
    if (!messages.any(_isReply)) _rollbackGoOnRound(source);
    _onGoOnFinished?.call(source.locationId, round);
    await _persist(source);
    _notify();
    if (_refreshWallet != null) {
      try {
        await _refreshWallet();
      } catch (_) {
        // Wallet availability must not undo a recovered, persisted round.
      }
    }
  }

  Future<void> reconnect() async {
    for (final location in _states.keys.toList()) {
      if (!_isReady(location)) continue;
      for (final state in statesFor(location)) {
        try {
          if (state.hasCardGroup ||
              state._regenerationRequestId != null ||
              state.frozen) {
            await _loadCards(state, force: true);
          }
          if (state.frozen) {
            await finalizeBeforeSend(location);
          }
          await _recoverGoOn(state);
        } catch (error) {
          if (!_disposed) state._error = error;
        }
      }
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final location in _states.keys.toList()) {
      for (final state in statesFor(location)) {
        _cancelRegenerationWatchdog(state);
        _cancelGoOnWatchdog(state);
      }
    }
    unawaited(_writes.then((_) => _storage.close()).catchError((Object _) {}));
    super.dispose();
  }
}

class _PendingGoOn {
  _PendingGoOn(
    this.clientMsgId, {
    this.roundId,
    this.finished = false,
    this.uncertain = false,
    this.ended = false,
  });
  final String clientMsgId;
  int? roundId;
  bool finished;
  bool uncertain;
  bool ended;
  Map<String, dynamic> toJson() => {
    'client_msg_id': clientMsgId,
    'round_id': roundId,
    'finished': finished,
    'uncertain': uncertain,
    'ended': ended,
  };
  factory _PendingGoOn.fromJson(Map<String, dynamic> json) => _PendingGoOn(
    json['client_msg_id'] as String,
    roundId: json['round_id'] as int?,
    finished: json['finished'] == true,
    uncertain: json['round_id'] == null && json['finished'] != true,
    ended: json['ended'] == true,
  );
}

class _CandidateMessage {
  _CandidateMessage(ChatroomLlmCardStream event)
    : id = event.globalMessageId,
      index = event.cardMessageIndex,
      senderType = event.senderType,
      senderId = event.senderId,
      senderName = event.senderName,
      userId = event.userId,
      currentTime = event.currentTime,
      ts = event.ts;
  final int id, index;
  final String senderType, senderId, senderName, userId, currentTime;
  final int? ts;
  final _chunks = <int, String>{};
  String _content = '';
  bool _ended = false;
  bool _receivedChunk = false;
  void apply(ChatroomLlmCardStream event) {
    if (_ended || event.cardMessageIndex != index) return;
    if (event.streamType == 'chunk') {
      _receivedChunk = true;
      _chunks.putIfAbsent(event.seq!, () => event.content);
      final seq = _chunks.keys.toList()..sort();
      _content = seq.map((key) => _chunks[key]).join();
    } else if (event.streamType == 'end') {
      _content = event.content;
      _ended = true;
    }
  }

  WorldChatroomMessage toMessage(String location, int round) =>
      WorldChatroomMessage(
        globalMessageId: id,
        messageId: 0,
        locationMessageId: 0,
        conversationRoundId: '$round',
        roundOrder: index,
        locationId: location,
        senderType: senderType,
        businessType: senderType,
        senderId: senderId,
        senderName: senderName,
        userId: userId,
        content: _content,
        currentTime: currentTime,
        messageType: senderId == 'nar_pic' ? 'image' : 'text',
        createdAt: ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts!),
        streaming: !_ended,
        isLlmStreamMessage: true,
      );
}

bool _isReply(WorldChatroomMessage message) =>
    !const {
      'user',
      'tick',
      'user_enter_location',
      'characters_moved',
      'story_events',
      'world_notification',
    }.contains(message.businessType) &&
    (const {'character', 'narrator', 'llm'}.contains(message.businessType) ||
        const {'character', 'narrator', 'ai'}.contains(message.senderType));
bool _terminal(ChatroomCardGenerationState state) =>
    state == ChatroomCardGenerationState.succeeded ||
    state == ChatroomCardGenerationState.failed;
bool _completeCard(ChatroomLlmCard? card) =>
    card != null &&
    card.generationState == ChatroomCardGenerationState.succeeded &&
    card.messages.isNotEmpty;
WorldChatroomMessage _candidateToWorld(ChatroomLlmCardMessage message) =>
    WorldChatroomMessage.fromHttpMessage(
      ChatroomHttpMessage.fromV2Message(message.message),
    ).copyWith(isLlmStreamMessage: message.isLlmStreamMessage);
ChatroomLlmCard _placeholder(
  int id,
  int index, {
  ChatroomCardGenerationState generationState =
      ChatroomCardGenerationState.generating,
}) => ChatroomLlmCard(
  cardId: id,
  cardIndex: index,
  isOriginal: false,
  generationState: generationState,
  canEdit: false,
  canDelete: false,
  messages: const [],
  billing: const ChatroomCardBilling(
    status: ChatroomCardBillingStatus.notStarted,
  ),
  createdAt: '',
  rawJson: const {},
);
ChatroomLlmMessageOperation _operationFromJson(Object? value) {
  final json = Map<String, dynamic>.from(value as Map);
  final id = json['global_message_id'] as int;
  return json['action'] == 'delete'
      ? ChatroomLlmMessageOperation.delete(globalMessageId: id)
      : ChatroomLlmMessageOperation.edit(
          globalMessageId: id,
          content: json['content'] as String,
        );
}

bool _operationsApplied(
  List<ChatroomLlmMessageOperation> operations,
  List<WorldChatroomMessage> current,
) {
  final messages = {
    for (final message in current) message.globalMessageId: message,
  };
  return operations.every(
    (operation) => operation.action == ChatroomLlmMessageAction.delete
        ? !messages.containsKey(operation.globalMessageId)
        : messages[operation.globalMessageId]?.content == operation.content,
  );
}

bool _unchangedTargets(
  List<ChatroomLlmMessageOperation> operations,
  Map<int, String> before,
  List<WorldChatroomMessage> current,
) {
  final after = {
    for (final message in current) message.globalMessageId: message.content,
  };
  return operations.every(
    (operation) =>
        before.containsKey(operation.globalMessageId) &&
        after.containsKey(operation.globalMessageId) &&
        before[operation.globalMessageId] == after[operation.globalMessageId],
  );
}

bool _definiteRejection(Object error) =>
    error is ArgumentError ||
    error is ChatroomErrorEvent && error.errNo != null ||
    error is ChatroomFailureEvent && int.tryParse(error.code) != null ||
    error is ApiException && error.kind == ApiExceptionKind.business;

Map<String, Object?> _operationToDraftJson(ChatroomLlmMessageOperation op) => {
  'action': op.action.name,
  'global_message_id': op.globalMessageId,
  if (op.action == ChatroomLlmMessageAction.edit) 'content': op.content,
};

bool _sameOperations(
  List<ChatroomLlmMessageOperation> a,
  List<ChatroomLlmMessageOperation> b,
) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every(
      (i) =>
          a[i].action == b[i].action &&
          a[i].globalMessageId == b[i].globalMessageId &&
          a[i].content == b[i].content,
    );

int? _errorCode(Object error) => switch (error) {
  ChatroomFailureEvent failure => int.tryParse(failure.code),
  ChatroomErrorEvent event => event.errNo ?? int.tryParse(event.code),
  ApiException exception => exception.code,
  _ => null,
};

// Only documented pre-queue rejections permit a fresh request. ID allocation,
// storage and infrastructure failures (including unknown future codes) retain
// the non-idempotent operation until its outcome can be established.
bool _goOnDefiniteRejection(Object error) =>
    error is ArgumentError ||
    const {
      10001,
      1001,
      1002,
      1003,
      1005,
      2012,
      2015,
      2006,
      2010,
      3001,
      2005,
    }.contains(_errorCode(error));
