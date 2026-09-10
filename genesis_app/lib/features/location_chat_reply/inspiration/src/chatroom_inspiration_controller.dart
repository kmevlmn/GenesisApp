import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../../network/http_transport.dart';

import '../../../../network/chatroom/chatroom_http_api.dart';
import 'chatroom_inspiration_models.dart';
import 'chatroom_inspiration_storage.dart';

class ChatroomInspirationController extends ChangeNotifier {
  ChatroomInspirationController({
    required this.ownerUid,
    required this.worldId,
    required ChatroomHttpApi httpApi,
    ChatroomInspirationStorage? storage,
  }) : _http = httpApi,
       _storage = storage ?? SqfliteChatroomInspirationStorage();

  final String ownerUid, worldId;
  final ChatroomHttpApi _http;
  final ChatroomInspirationStorage _storage;
  final _contexts = <String, (int, int)>{};
  final _epochs = <String, int>{};
  final _views = <String, String>{};
  final _viewEpochs = <String, int>{};
  final _locationsByKey = <String, String>{};
  final _memory = <String, ChatroomInspirationResponse>{};
  final _requests = <String, Future<ChatroomInspirationResponse?>>{};
  final _tokens = <String, NetworkCancellationToken>{};
  Future<void> _writes = Future.value();
  bool _disposed = false;

  int revision(String location) => _epochs[location] ?? 0;

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _writes.then((_) => work());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Observe verified history and live progress, never a partial older page.
  void observe(
    String location, {
    required int roundId,
    required int tailMessageId,
    bool replacing = false,
  }) {
    if (_disposed || roundId <= 0) return;
    final old = _contexts[location];
    if (old != null && roundId < old.$1) return;
    _contexts[location] = (
      roundId,
      old != null && roundId == old.$1
          ? (tailMessageId > old.$2 ? tailMessageId : old.$2)
          : tailMessageId,
    );
    if (old == null ||
        roundId > old.$1 ||
        (!replacing && tailMessageId > old.$2)) {
      _invalidate(location);
      unawaited(
        _serial(
          () => _storage.clearLocation(
            ownerUid,
            worldId,
            location,
            keepRound: old == null || roundId > old.$1 ? roundId : null,
            minTailMessageId: tailMessageId,
          ),
        ).catchError((Object _) {}),
      );
    }
  }

  void _invalidate(String location) {
    _epochs[location] = revision(location) + 1;
    cancelView(location);
    _memory.removeWhere((key, _) => _locationsByKey[key] == location);
    // In-flight results check their epoch before entering the write queue.
    _requests.removeWhere((key, _) => _locationsByKey[key] == location);
    _locationsByKey.removeWhere((_, value) => value == location);
    if (!_disposed) notifyListeners();
  }

  void cancelView(String location) {
    if (_disposed) return;
    _views.remove(location);
    _viewEpochs[location] = (_viewEpochs[location] ?? 0) + 1;
    for (final entry in _tokens.entries.toList()) {
      if (_locationsByKey[entry.key] == location) {
        entry.value.cancel();
        _tokens.remove(entry.key);
      }
    }
    _requests.removeWhere((key, _) => _locationsByKey[key] == location);
  }

  void activate(ChatroomInspirationSource source) {
    if (_views[source.locationId] == source.key) return;
    cancelView(source.locationId);
    _views[source.locationId] = source.key;
    _locationsByKey[source.key] = source.locationId;
  }

  bool isCurrent(ChatroomInspirationSource source, int epoch) =>
      !_disposed &&
      source.ownerUid == ownerUid &&
      source.worldId == worldId &&
      _contexts[source.locationId]?.$1 == source.roundId &&
      revision(source.locationId) == epoch;

  Future<ChatroomInspirationResponse?> load(ChatroomInspirationSource source) {
    final epoch = revision(source.locationId);
    if (!isCurrent(source, epoch)) return Future.value(null);
    activate(source);
    final pending = _requests[source.key];
    if (pending != null) return pending;
    late final Future<ChatroomInspirationResponse?> task;
    task = _load(source, epoch, _viewEpochs[source.locationId] ?? 0)
        .whenComplete(() {
          if (identical(_requests[source.key], task)) {
            _requests.remove(source.key);
          }
        });
    _requests[source.key] = task;
    return task;
  }

  Future<ChatroomInspirationResponse?> _load(
    ChatroomInspirationSource source,
    int epoch,
    int viewEpoch,
  ) async {
    bool current() =>
        isCurrent(source, epoch) &&
        _views[source.locationId] == source.key &&
        _viewEpochs[source.locationId] == viewEpoch;
    final cached =
        _memory[source.key] ?? await _serial(() => _storage.load(source));
    if (!current()) return null;
    if (cached != null &&
        cached.conversationRoundId == source.roundId &&
        (cached.sourceCardId == source.sourceCardId ||
            (source.cardId == null && source.sourceCardId == 0))) {
      _memory[source.key] = cached;
      return cached;
    }
    final token = NetworkCancellationToken();
    _tokens[source.key] = token;
    late final ChatroomInspirationResponse response;
    try {
      response = await _http.getInspirations(
        worldId: worldId,
        locationId: source.locationId,
        conversationRoundId: source.roundId,
        cardId: source.cardId,
        cancellationToken: token,
      );
    } catch (_) {
      if (!current()) return null;
      rethrow;
    } finally {
      if (identical(_tokens[source.key], token)) _tokens.remove(source.key);
    }
    if (!current()) return null;
    // A formal reply owned by another user may already be a selected candidate.
    // Its card group is private; the endpoint resolves the authoritative source.
    if (response.sourceCardId != source.sourceCardId &&
        !(source.cardId == null && source.sourceCardId == 0)) {
      throw StateError(
        'The inspiration source changed. Please reopen inspiration.',
      );
    }
    await _serial(() async {
      if (!current()) return;
      await _storage.save(source.resolved(response.sourceCardId), response);
      if (current()) _memory[source.key] = response;
    });
    return current() ? response : null;
  }

  void suspend() {
    for (final location in _contexts.keys.toList()) {
      _invalidate(location);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    _views.clear();
    _memory.clear();
    unawaited(_serial(_storage.close).catchError((Object _) {}));
    super.dispose();
  }
}
