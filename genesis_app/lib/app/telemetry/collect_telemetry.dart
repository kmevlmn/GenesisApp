import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../network/genesis_http_transport_pool.dart';
import '../../network/http_transport.dart';

const Duration defaultCollectUploadInterval = Duration(seconds: 5);
const int defaultCollectUploadBatchSize = 100;
const int defaultCollectUploadBatchBytes = 256 * 1024;
const int defaultCollectMemoryFallbackLimit = 300;
const Duration defaultCollectStoreTimeout = Duration(seconds: 2);
const Duration defaultCollectRequestTimeout = Duration(seconds: 8);

enum CollectStoreStatus { healthy, recovering, unavailable }

@immutable
class CollectTelemetryHealth {
  const CollectTelemetryHealth({
    required this.storeStatus,
    required this.memoryFallbackCount,
    required this.deadLetterCount,
    required this.droppedEventCount,
    required this.consecutiveUploadFailures,
    this.lastError = '',
    this.lastUploadSuccessAt,
    this.lastUploadFailureAt,
  });

  const CollectTelemetryHealth.initial()
    : storeStatus = CollectStoreStatus.healthy,
      memoryFallbackCount = 0,
      deadLetterCount = 0,
      droppedEventCount = 0,
      consecutiveUploadFailures = 0,
      lastError = '',
      lastUploadSuccessAt = null,
      lastUploadFailureAt = null;

  final CollectStoreStatus storeStatus;
  final int memoryFallbackCount;
  final int deadLetterCount;
  final int droppedEventCount;
  final int consecutiveUploadFailures;
  final String lastError;
  final DateTime? lastUploadSuccessAt;
  final DateTime? lastUploadFailureAt;
}

// `permanent` is retained as a compatibility name for batch rejection. It only
// permits splitting a request; even a rejected single event must stay queued.
enum CollectUploadFailureKind { transient, permanent, authorization }

class CollectUploadException implements Exception {
  const CollectUploadException({
    required this.message,
    required this.kind,
    this.statusCode,
    this.errNo,
  });

  final String message;
  final CollectUploadFailureKind kind;
  final int? statusCode;
  final int? errNo;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' status=$statusCode';
    final errorNumber = errNo == null ? '' : ' err_no=$errNo';
    return 'CollectUploadException($message$status$errorNumber)';
  }
}

class CollectEvent {
  const CollectEvent({
    required this.eventId,
    required this.actionType,
    required this.action,
    required this.appTimestamp,
    required this.object1,
    required this.object2,
    required this.object3,
    this.object4 = '',
    this.extData = '',
    this.appEnvironment = '',
    this.platform = '',
    this.appVersion = '',
    this.deviceId = '',
    this.userId = '',
    this.includeIdentityHeaders = true,
    this.contextCaptured = true,
  });

  final String eventId;
  final String actionType;
  final String action;
  final int appTimestamp;
  final String object1;
  final String object2;
  final String object3;
  final String object4;
  final String extData;
  final String appEnvironment;
  final String platform;
  final String appVersion;
  final String deviceId;
  final String userId;
  final bool includeIdentityHeaders;
  final bool contextCaptured;

  Map<String, Object> toWireMap() {
    return <String, Object>{
      'event_id': eventId,
      'action_type': actionType,
      'action': action,
      'app_timestamp': appTimestamp,
      'object1': object1,
      'object2': object2,
      'object3': object3,
      'object4': object4,
      'ext_data': extData,
    };
  }
}

class ClaimedCollectEventBatch {
  const ClaimedCollectEventBatch({required this.batchId, required this.events});

  final String batchId;
  final List<CollectEvent> events;
}

abstract interface class CollectEventStore {
  Future<void> enqueue(CollectEvent event);
  Future<void> recoverInFlight();
  Future<ClaimedCollectEventBatch?> claimPending({required int limit});
  Future<void> deleteClaimed(String batchId);
  Future<void> deleteEvents(List<String> eventIds);
  Future<void> releaseClaimed(
    String batchId, {
    List<String> excludingEventIds = const [],
  });
  Future<void> resetConnection();
}

class SqfliteCollectEventStore implements CollectEventStore {
  SqfliteCollectEventStore({
    this.databaseName = 'genesis_collect_events.db',
    DatabaseFactory? databaseFactoryOverride,
    this.databasePath,
  }) : _databaseFactory = databaseFactoryOverride;

  final String databaseName;
  final String? databasePath;
  final DatabaseFactory? _databaseFactory;
  Database? _database;
  Future<Database>? _openingDatabase;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;
    _database = null;
    final opening = _openingDatabase;
    if (opening != null) return opening;
    final nextOpening = _openDatabase();
    _openingDatabase = nextOpening;
    try {
      final database = await nextOpening;
      if (!identical(_openingDatabase, nextOpening)) {
        await database.close();
        throw StateError('Collect database open was superseded');
      }
      _database = database;
      return database;
    } finally {
      if (identical(_openingDatabase, nextOpening)) {
        _openingDatabase = null;
      }
    }
  }

  Future<Database> _openDatabase() async {
    final factory = _databaseFactory ?? databaseFactory;
    final path =
        databasePath ?? '${await factory.getDatabasesPath()}/$databaseName';
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await db.execute(_createCollectEventsSql);
          await db.execute(_createCollectEventsStateIndexSql);
          await db.execute(_createCollectEventsUploadContextIndexSql);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute(_addCollectAppEnvironmentSql);
          }
          if (oldVersion < 3) {
            await db.execute(_addCollectPlatformSql);
            await db.execute(_addCollectAppVersionSql);
            await db.execute(_addCollectDeviceIdSql);
            await db.execute(_addCollectUserIdSql);
            await db.execute(_addCollectContextCapturedSql);
            await db.execute(_createCollectEventsUploadContextIndexSql);
          }
          if (oldVersion < 4) {
            await db.execute(_addCollectObject4Sql);
          }
          if (oldVersion < 5) {
            await db.execute(_addCollectExtDataSql);
          }
        },
      ),
    );
  }

  @override
  Future<void> enqueue(CollectEvent event) async {
    await (await _db).insert(
      'collect_events',
      _eventToRow(event),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> recoverInFlight() async {
    await (await _db).update(
      'collect_events',
      <String, Object?>{'state': _pendingState, 'batch_id': null},
      where: 'state = ?',
      whereArgs: <Object>[_inFlightState],
    );
  }

  @override
  Future<ClaimedCollectEventBatch?> claimPending({required int limit}) async {
    if (limit <= 0) return null;
    return (await _db).transaction((txn) async {
      final oldestRows = await txn.query(
        'collect_events',
        where: 'state = ?',
        whereArgs: <Object>[_pendingState],
        orderBy: 'sequence_id ASC',
        limit: 1,
      );
      if (oldestRows.isEmpty) return null;
      final oldest = _eventFromRow(oldestRows.single);
      final where = <String>[
        'state = ?',
        'app_environment = ?',
        'include_identity_headers = ?',
        'context_captured = ?',
      ];
      final whereArgs = <Object>[
        _pendingState,
        oldest.appEnvironment,
        oldest.includeIdentityHeaders ? 1 : 0,
        oldest.contextCaptured ? 1 : 0,
      ];
      if (oldest.contextCaptured) {
        where.addAll(<String>['platform = ?', 'app_version = ?']);
        whereArgs.addAll(<Object>[oldest.platform, oldest.appVersion]);
        if (oldest.includeIdentityHeaders) {
          where.addAll(<String>['device_id = ?', 'user_id = ?']);
          whereArgs.addAll(<Object>[oldest.deviceId, oldest.userId]);
        }
      }
      final rows = await txn.query(
        'collect_events',
        where: where.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'sequence_id ASC',
        limit: limit,
      );

      final batchId = newCollectEventId();
      final eventIds = rows
          .map((row) => '${row['event_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      final placeholders = List.filled(eventIds.length, '?').join(',');
      await txn.update(
        'collect_events',
        <String, Object?>{'state': _inFlightState, 'batch_id': batchId},
        where: 'state = ? AND event_id IN ($placeholders)',
        whereArgs: <Object>[_pendingState, ...eventIds],
      );
      return ClaimedCollectEventBatch(
        batchId: batchId,
        events: rows.map(_eventFromRow).toList(growable: false),
      );
    });
  }

  @override
  Future<void> deleteEvents(List<String> eventIds) async {
    if (eventIds.isEmpty) return;
    await (await _db).delete(
      'collect_events',
      where: 'event_id IN (${List.filled(eventIds.length, '?').join(',')})',
      whereArgs: eventIds,
    );
  }

  @override
  Future<void> deleteClaimed(String batchId) async {
    await (await _db).delete(
      'collect_events',
      where: 'state = ? AND batch_id = ?',
      whereArgs: <Object>[_inFlightState, batchId],
    );
  }

  @override
  Future<void> releaseClaimed(
    String batchId, {
    List<String> excludingEventIds = const [],
  }) async {
    await (await _db).transaction((txn) async {
      final rows = await txn.query(
        'collect_events',
        columns: ['event_id'],
        where:
            'state = ? AND batch_id = ?'
            '${excludingEventIds.isEmpty ? '' : ' AND event_id NOT IN (${List.filled(excludingEventIds.length, '?').join(',')})'}',
        whereArgs: <Object>[_inFlightState, batchId, ...excludingEventIds],
        orderBy: 'sequence_id ASC',
      );
      if (rows.isEmpty) return;
      final maximum = await txn.rawQuery(
        'SELECT COALESCE(MAX(sequence_id), 0) AS last_sequence FROM collect_events',
      );
      var sequence = (maximum.single['last_sequence'] as num).toInt();
      for (final row in rows) {
        // Move failed rows behind untouched pending events without deleting or
        // changing their event ID, captured timestamp, identity or payload.
        await txn.update(
          'collect_events',
          <String, Object?>{
            'state': _pendingState,
            'batch_id': null,
            'sequence_id': ++sequence,
          },
          where: 'state = ? AND batch_id = ? AND event_id = ?',
          whereArgs: <Object>[_inFlightState, batchId, row['event_id']!],
        );
      }
    });
  }

  Future<void> close() async {
    final database = _database;
    final opening = _openingDatabase;
    _database = null;
    _openingDatabase = null;
    await database?.close();
    if (database == null && opening != null) {
      try {
        final openedDatabase = await opening;
        await openedDatabase.close();
      } catch (_) {
        // The failed open is the reason the connection is being reset.
      }
    }
  }

  @override
  Future<void> resetConnection() => close();
}

class MemoryCollectEventStore implements CollectEventStore {
  final List<_MemoryCollectEventRow> _rows = <_MemoryCollectEventRow>[];
  var _nextSequence = 1;

  List<CollectEvent> get eventsForTesting =>
      _rows.map((row) => row.event).toList(growable: false);

  int get pendingCountForTesting =>
      _rows.where((row) => row.state == _pendingState).length;

  int get inFlightCountForTesting =>
      _rows.where((row) => row.state == _inFlightState).length;

  @override
  Future<void> enqueue(CollectEvent event) async {
    if (_rows.any((row) => row.event.eventId == event.eventId)) return;
    _rows.add(_MemoryCollectEventRow(_nextSequence++, event));
  }

  @override
  Future<void> recoverInFlight() async {
    for (final row in _rows) {
      if (row.state != _inFlightState) continue;
      row
        ..state = _pendingState
        ..batchId = null;
    }
  }

  @override
  Future<ClaimedCollectEventBatch?> claimPending({required int limit}) async {
    if (limit <= 0) return null;
    final pending =
        _rows.where((row) => row.state == _pendingState).toList(growable: false)
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
    if (pending.isEmpty) return null;
    final oldest = pending.first.event;
    final selected = pending
        .where((row) => _hasSameUploadContext(row.event, oldest))
        .take(limit)
        .toList(growable: false);
    final batchId = newCollectEventId();
    for (final row in selected) {
      row
        ..state = _inFlightState
        ..batchId = batchId;
    }
    return ClaimedCollectEventBatch(
      batchId: batchId,
      events: selected.map((row) => row.event).toList(growable: false),
    );
  }

  @override
  Future<void> deleteEvents(List<String> eventIds) async {
    final ids = eventIds.toSet();
    _rows.removeWhere((row) => ids.contains(row.event.eventId));
  }

  @override
  Future<void> deleteClaimed(String batchId) async {
    _rows.removeWhere(
      (row) => row.state == _inFlightState && row.batchId == batchId,
    );
  }

  @override
  Future<void> releaseClaimed(
    String batchId, {
    List<String> excludingEventIds = const [],
  }) async {
    for (final row in _rows) {
      if (row.state != _inFlightState ||
          row.batchId != batchId ||
          excludingEventIds.contains(row.event.eventId)) {
        continue;
      }
      row
        ..sequence = _nextSequence++
        ..state = _pendingState
        ..batchId = null;
    }
  }

  @override
  Future<void> resetConnection() async {}
}

class CollectUploadContext {
  const CollectUploadContext({
    this.platform = '',
    this.appVersion = '',
    this.appEnvironment = 'production',
    this.deviceId = '',
    this.userId = '',
  });

  final String platform;
  final String appVersion;
  final String appEnvironment;
  final String deviceId;
  final String userId;

  CollectUploadContext copyWith({
    String? platform,
    String? appVersion,
    String? appEnvironment,
    String? deviceId,
    String? userId,
  }) {
    return CollectUploadContext(
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      appEnvironment: appEnvironment ?? this.appEnvironment,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
    );
  }
}

abstract interface class CollectTelemetryClient {
  Future<void> collectBatch(
    List<CollectEvent> events, {
    Map<String, String> headers = const <String, String>{},
    NetworkCancellationToken? cancellationToken,
  });
}

class SdkCollectTelemetryClient implements CollectTelemetryClient {
  SdkCollectTelemetryClient({
    required String endpoint,
    HttpTransport? transport,
    String? debugProxy,
    this.timeoutMs = 5000,
  }) : _endpoint = Uri.parse(endpoint),
       _transport =
           transport ??
           ((debugProxy?.trim().isNotEmpty ?? false)
               ? GenesisHttpTransportRegistry.configure(debugProxy: debugProxy)
               : GenesisHttpTransportRegistry.current);

  final Uri _endpoint;
  final HttpTransport _transport;
  final int timeoutMs;

  @override
  Future<void> collectBatch(
    List<CollectEvent> events, {
    Map<String, String> headers = const <String, String>{},
    NetworkCancellationToken? cancellationToken,
  }) async {
    final response = await _transport.send(
      TransportRequest(
        method: 'POST',
        uri: _endpoint,
        headers: <String, String>{
          'content-type': 'application/json',
          'accept': 'application/json',
          ...headers,
        },
        bodyBytes: utf8.encode(
          jsonEncode(<String, Object>{
            'events': events.map((event) => event.toWireMap()).toList(),
          }),
        ),
        timeoutMs: timeoutMs,
        cancellationToken: cancellationToken,
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final statusCode = response.statusCode;
      final kind = statusCode == 401 || statusCode == 403
          ? CollectUploadFailureKind.authorization
          : statusCode == 400 || statusCode == 413 || statusCode == 422
          ? CollectUploadFailureKind.permanent
          : CollectUploadFailureKind.transient;
      throw CollectUploadException(
        message: 'Collect request failed',
        kind: kind,
        statusCode: statusCode,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const CollectUploadException(
        message: 'Collect response is not valid JSON',
        kind: CollectUploadFailureKind.transient,
      );
    }
    if (decoded is! Map) {
      throw const CollectUploadException(
        message: 'Collect response is not a JSON object',
        kind: CollectUploadFailureKind.transient,
      );
    }
    final errNo = decoded['err_no'];
    if (errNo != 0 && errNo?.toString() != '0') {
      throw CollectUploadException(
        message: 'Collect response err_no is not zero',
        // The response does not establish that the event itself is invalid.
        kind: CollectUploadFailureKind.transient,
        errNo: _asInt(errNo),
      );
    }
  }
}

// Retained only while a timed-out write and its memory copy need reconciling.
class _CollectStoreWrite {
  _CollectStoreWrite(this.eventId);

  final String eventId;
  bool settled = false;
  bool failed = false;
  bool fallback = false;
  bool acknowledged = false;
  bool databaseOwned = false;
  Future<void>? cleanup;
}

class CollectTelemetryUploader {
  CollectTelemetryUploader({
    required CollectEventStore store,
    Duration interval = defaultCollectUploadInterval,
    int batchSize = defaultCollectUploadBatchSize,
    int maxBatchBytes = defaultCollectUploadBatchBytes,
    int memoryFallbackLimit = defaultCollectMemoryFallbackLimit,
    Duration storeTimeout = defaultCollectStoreTimeout,
    Duration requestTimeout = defaultCollectRequestTimeout,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _store = store,
       _interval = interval,
       _batchSize = batchSize,
       _maxBatchBytes = maxBatchBytes,
       _memoryFallbackLimit = memoryFallbackLimit,
       _storeTimeout = storeTimeout,
       _requestTimeout = requestTimeout,
       _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? newCollectEventId;

  final CollectEventStore _store;
  final Duration _interval;
  final int _batchSize;
  final int _maxBatchBytes;
  // Compatibility setting: caps concurrent unresolved writes, never retention.
  final int _memoryFallbackLimit;
  final Duration _storeTimeout;
  final Duration _requestTimeout;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  CollectTelemetryClient? _client;
  CollectUploadContext _context = const CollectUploadContext();
  Future<void> _pendingWrites = Future<void>.value();
  final List<CollectEvent> _memoryFallback = <CollectEvent>[];
  final Map<String, _CollectStoreWrite> _storeWrites = {};
  Timer? _timer;
  Timer? _immediateCheckTimer;
  Timer? _storeRecoveryTimer;
  Future<void>? _storeRecovery;
  bool _enabled = false;
  bool _started = false;
  bool _checking = false;
  bool _disposed = false;
  bool _contextCaptured = false;
  CollectStoreStatus _storeStatus = CollectStoreStatus.healthy;
  int _droppedEventCount = 0;
  int _consecutiveUploadFailures = 0;
  String _lastError = '';
  DateTime? _lastUploadSuccessAt;
  DateTime? _lastUploadFailureAt;
  DateTime? _nextUploadAt;

  bool get isStartedForTesting => _started;
  bool get hasTimerForTesting => _timer != null;
  bool get isCheckingForTesting => _checking;
  List<CollectEvent> get deadLettersForTesting => const <CollectEvent>[];

  CollectTelemetryHealth get health => CollectTelemetryHealth(
    storeStatus: _storeStatus,
    memoryFallbackCount: _memoryFallback.length,
    deadLetterCount: 0,
    droppedEventCount: _droppedEventCount,
    consecutiveUploadFailures: _consecutiveUploadFailures,
    lastError: _lastError,
    lastUploadSuccessAt: _lastUploadSuccessAt,
    lastUploadFailureAt: _lastUploadFailureAt,
  );

  void configure({required bool enabled, CollectTelemetryClient? client}) {
    _enabled = enabled;
    _client = client;
  }

  void setContext(CollectUploadContext context) {
    _context = context;
    _contextCaptured = true;
  }

  void updateMetadataContext({
    required String platform,
    required String appVersion,
    required String deviceId,
  }) {
    _context = _context.copyWith(
      platform: platform,
      appVersion: appVersion,
      deviceId: deviceId,
    );
    _contextCaptured = true;
  }

  void setAppEnvironment(String value) {
    _context = _context.copyWith(appEnvironment: value.trim());
  }

  void setUserId(String? uid) {
    _context = _context.copyWith(userId: uid?.trim() ?? '');
  }

  Future<void> enqueuePayload(
    Map<String, Object?> payload, {
    bool includeIdentityHeaders = true,
  }) async {
    await enqueuePayloadWithResult(
      payload,
      includeIdentityHeaders: includeIdentityHeaders,
    );
  }

  Future<bool> enqueuePayloadWithResult(
    Map<String, Object?> payload, {
    bool includeIdentityHeaders = true,
  }) {
    if (!_enabled) return Future<bool>.value(false);
    if (_disposed) {
      _droppedEventCount += 1;
      return Future<bool>.value(false);
    }
    final actionType = _boundedString(payload['action_type'], 64).trim();
    final action = _boundedString(payload['action'], 128).trim();
    if (actionType.isEmpty || action.isEmpty) {
      return Future<bool>.value(false);
    }
    final CollectEvent event;
    try {
      event = CollectEvent(
        eventId: _idGenerator(),
        actionType: actionType,
        action: action,
        appTimestamp: _clock().millisecondsSinceEpoch,
        object1: _boundedString(payload['object1'], 2048),
        object2: _boundedString(payload['object2'], 2048),
        object3: _boundedString(payload['object3'], 2048),
        object4: _boundedString(payload['object4'], 2048),
        extData: _boundedString(payload['ext_data'], 4096),
        appEnvironment: _context.appEnvironment.trim(),
        platform: _context.platform.trim(),
        appVersion: _context.appVersion.trim(),
        deviceId: _context.deviceId.trim(),
        userId: _context.userId.trim(),
        includeIdentityHeaders: includeIdentityHeaders,
        contextCaptured: _contextCaptured,
      );
    } catch (error) {
      _droppedEventCount += 1;
      _recordError('event_build', error);
      return Future<bool>.value(false);
    }
    final previousWrite = _pendingWrites;
    final write = _writeAfter(previousWrite, event);
    _pendingWrites = write.catchError((_) {});
    return write.then((_) => true);
  }

  Future<void> _writeAfter(
    Future<void> previousWrite,
    CollectEvent event,
  ) async {
    try {
      await previousWrite.timeout(_storeTimeout);
    } catch (error) {
      _recordStoreFailure('write_chain', error);
    }
    try {
      await _writeToStore(event);
    } finally {
      _scheduleImmediateCheck();
    }
  }

  Future<bool> _writeToStore(
    CollectEvent event, {
    bool fromMemory = false,
  }) async {
    // A hung store must not create an unbounded set of outstanding writes.
    if (_storeWrites.length >= max(1, _memoryFallbackLimit)) {
      _addMemoryFallback(event);
      return false;
    }
    final state = _CollectStoreWrite(event.eventId);
    _storeWrites[event.eventId] = state;
    final write = Future<void>.sync(() => _store.enqueue(event)).then(
      (_) {
        state.settled = true;
        if (state.fallback) unawaited(_reconcileStoreWrite(state));
      },
      onError: (Object error, StackTrace stack) {
        state.settled = true;
        state.failed = true;
        _storeWrites.remove(state.eventId);
        Error.throwWithStackTrace(error, stack);
      },
    );
    try {
      await write.timeout(_storeTimeout);
      _storeWrites.remove(event.eventId);
      if (fromMemory) {
        _memoryFallback.removeWhere((item) => item.eventId == event.eventId);
      }
      _markStoreHealthy();
      return true;
    } catch (error) {
      state.fallback = true;
      if (!state.acknowledged && !state.databaseOwned) {
        _addMemoryFallback(event);
      }
      _recordStoreFailure('enqueue', error);
      await _reconcileStoreWrite(state);
      return false;
    }
  }

  Future<bool> _persistMemoryFallback() async {
    // checkNow owns the upload lock, so a successful write can transfer this
    // memory copy to SQLite before another upload starts. Keep timed-out writes
    // tracked until they settle, using the same late-write reconciliation.
    var persisted = false;
    final batch = _memoryFallback.take(_batchSize).toList(growable: false);
    for (final event in batch) {
      final state = _storeWrites[event.eventId];
      if (state != null) {
        if (state.settled && !state.failed && !state.acknowledged) {
          _memoryFallback.removeWhere((item) => item.eventId == event.eventId);
          _storeWrites.remove(event.eventId);
          persisted = true;
        }
        continue;
      }
      if (!await _writeToStore(event, fromMemory: true)) break;
      persisted = true;
    }
    return persisted;
  }

  Future<void> _reconcileStoreWrite(_CollectStoreWrite state) async {
    if (!state.settled || state.failed) return;
    if (!state.acknowledged) {
      if (!_memoryFallback.any((event) => event.eventId == state.eventId)) {
        _storeWrites.remove(state.eventId);
      }
      return;
    }
    final cleanup = state.cleanup;
    if (cleanup != null) return cleanup;
    final operation = _deleteAcknowledgedWrite(state);
    state.cleanup = operation;
    try {
      await operation;
    } finally {
      state.cleanup = null;
    }
  }

  Future<void> _deleteAcknowledgedWrite(_CollectStoreWrite state) async {
    try {
      await _store.deleteEvents([state.eventId]).timeout(_storeTimeout);
      _storeWrites.remove(state.eventId);
    } catch (error) {
      // Keep the acknowledgement so a later claim cannot upload this ID again.
      _recordStoreFailure('late_write_cleanup', error);
    }
  }

  void _markAcknowledged(List<CollectEvent> events) {
    for (final event in events) {
      _storeWrites[event.eventId]?.acknowledged = true;
    }
  }

  Future<void> _reconcileStoreWrites() async {
    await Future.wait(
      _storeWrites.values.toList(growable: false).map(_reconcileStoreWrite),
    );
  }

  void start() {
    if (!_enabled || _client == null || _started || _disposed) return;
    _started = true;
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _pendingWrites.timeout(_storeTimeout);
      await _store.recoverInFlight().timeout(_storeTimeout);
      _markStoreHealthy();
    } catch (error) {
      _recordStoreFailure('startup_recovery', error);
    }
    try {
      await checkNow(force: true);
    } finally {
      _startTimer();
    }
  }

  Future<void> checkNow({bool force = false}) async {
    if (!_enabled || _client == null || _checking || _disposed) return;
    _checking = true;
    ClaimedCollectEventBatch? batch;
    try {
      try {
        await _pendingWrites.timeout(_storeTimeout);
      } catch (error) {
        _recordStoreFailure('pending_writes', error);
      }

      // Network backoff must not prevent recovered storage from preserving
      // events that previously existed only in memory.
      final persistedFallback = await _persistMemoryFallback();
      final nextUploadAt = _nextUploadAt;
      if (!force && nextUploadAt != null && _clock().isBefore(nextUploadAt)) {
        return;
      }
      // Newly persisted older events keep priority over the memory tail.
      final fallbackCompleted =
          persistedFallback || await _uploadMemoryFallback();
      if (!fallbackCompleted) return;
      await _reconcileStoreWrites();
      // Cleanup can finish while claimPending is awaiting SQLite. Preserve the
      // known acknowledgements even if the corresponding write tracker retires.
      final acknowledgedIds = _storeWrites.values
          .where((state) => state.acknowledged)
          .map((state) => state.eventId)
          .toSet();

      try {
        batch = await _store
            .claimPending(limit: _batchSize)
            .timeout(_storeTimeout);
        _markStoreHealthy();
      } catch (error) {
        _recordStoreFailure('claim', error);
        return;
      }
      if (batch == null || batch.events.isEmpty) return;

      // A timed-out insert may have committed while its Future is still pending.
      // Remove acknowledged copies before allowing any claimed event to upload.
      final acknowledged = batch.events
          .where(
            (event) =>
                acknowledgedIds.contains(event.eventId) ||
                _storeWrites[event.eventId]?.acknowledged == true,
          )
          .map((event) => event.eventId)
          .toList(growable: false);
      final events = batch.events
          .where((event) => !acknowledged.contains(event.eventId))
          .toList(growable: false);
      final acceptedIds = acknowledged.toSet();
      var acknowledgementFailed = false;
      Future<void> acknowledge(List<String> ids) async {
        acceptedIds.addAll(ids);
        try {
          await _store.deleteEvents(ids).timeout(_storeTimeout);
        } catch (error) {
          acknowledgementFailed = true;
          _recordStoreFailure('delete_after_upload', error);
        }
      }

      try {
        await acknowledge(acknowledged);
        // The claimed row now owns any unacknowledged memory copy.
        final claimedIds = events.map((event) => event.eventId).toSet();
        for (final id in claimedIds) {
          _storeWrites[id]?.databaseOwned = true;
        }
        _memoryFallback.removeWhere(
          (event) => claimedIds.contains(event.eventId),
        );
        final completed = await _uploadWithIsolation(events, (accepted) async {
          _markAcknowledged(accepted);
          await acknowledge(accepted.map((event) => event.eventId).toList());
        });
        if (completed) {
          if (events.isNotEmpty) _recordUploadSuccess();
        } else {
          // Preserve accepted rows whose local deletion failed, but let the
          // unaccepted remainder retry without waiting for an app restart.
          await _store
              .releaseClaimed(
                batch.batchId,
                excludingEventIds: acceptedIds.toList(),
              )
              .timeout(_storeTimeout);
        }
        if (!acknowledgementFailed) _markStoreHealthy();
      } catch (error) {
        _recordStoreFailure('release_after_failure', error);
      }
      await _reconcileStoreWrites();
    } finally {
      _checking = false;
    }
  }

  Future<bool> _uploadMemoryFallback() async {
    if (_memoryFallback.isEmpty) return true;
    final oldest = _memoryFallback.first;
    final batch = _memoryFallback
        .where((event) => _hasSameUploadContext(event, oldest))
        .take(_batchSize)
        .toList(growable: false);
    final completed = await _uploadWithIsolation(batch, (accepted) async {
      _markAcknowledged(accepted);
      final ids = accepted.map((event) => event.eventId).toSet();
      _memoryFallback.removeWhere((event) => ids.contains(event.eventId));
      await _reconcileStoreWrites();
    });
    if (completed) {
      _recordUploadSuccess();
    } else {
      // Failed memory-only entries stay queued, behind events not tried yet.
      final batchIds = batch.map((event) => event.eventId).toSet();
      final retry = _memoryFallback
          .where((event) => batchIds.contains(event.eventId))
          .toList(growable: false);
      _memoryFallback.removeWhere((event) => batchIds.contains(event.eventId));
      _memoryFallback.addAll(retry);
    }
    return completed;
  }

  Future<bool> _uploadWithIsolation(
    List<CollectEvent> events,
    Future<void> Function(List<CollectEvent>) acknowledge,
  ) async {
    if (events.isEmpty) return true;
    Future<bool> split() async {
      final middle = events.length ~/ 2;
      final left = await _uploadWithIsolation(
        events.sublist(0, middle),
        acknowledge,
      );
      final right = await _uploadWithIsolation(
        events.sublist(middle),
        acknowledge,
      );
      return left && right;
    }

    if (_encodedBatchSize(events) > _maxBatchBytes) {
      if (events.length > 1) return split();
      _recordUploadFailure(
        const CollectUploadException(
          message:
              'Collect event exceeds the request size limit; retained for retry',
          kind: CollectUploadFailureKind.permanent,
        ),
      );
      return false;
    }

    try {
      await runWithNetworkDeadline(
        timeout: _requestTimeout,
        action: (token) => _client!.collectBatch(
          events,
          headers: _headers(events.first),
          cancellationToken: token,
        ),
      );
    } catch (error) {
      final kind = _uploadFailureKind(error);
      if (kind == CollectUploadFailureKind.permanent && events.length > 1) {
        return split();
      }
      _recordUploadFailure(error);
      return false;
    }
    // Only the normal SDK success path can acknowledge and delete event IDs.
    // Keep local storage errors outside the network failure/isolation catch.
    await acknowledge(events);
    return true;
  }

  void handleAppResumed() {
    if (!_started || _disposed) return;
    _timer?.cancel();
    _timer = null;
    unawaited(_checkAfterResume());
  }

  Future<void> _checkAfterResume() async {
    await checkNow(force: true);
    _startTimer();
  }

  void handleAppBackgrounded() {
    if (!_started || _disposed) return;
    unawaited(checkNow(force: true));
  }

  Future<void> waitForPendingWrites() async {
    try {
      await _pendingWrites.timeout(_storeTimeout);
    } catch (_) {
      // The event has already fallen back to memory, or will do so when its
      // timed operation completes. Tests and shutdown paths must not hang.
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _immediateCheckTimer?.cancel();
    _immediateCheckTimer = null;
    _storeRecoveryTimer?.cancel();
    _storeRecoveryTimer = null;
  }

  void _startTimer() {
    if (!_started || _disposed || _timer != null) return;
    _timer = Timer.periodic(_interval, (_) {
      unawaited(checkNow());
    });
  }

  void _scheduleImmediateCheck() {
    if (!_started || _disposed || _immediateCheckTimer != null) return;
    _immediateCheckTimer = Timer(Duration.zero, () {
      _immediateCheckTimer = null;
      unawaited(checkNow());
    });
  }

  void _addMemoryFallback(CollectEvent event) {
    if (_memoryFallback.any((item) => item.eventId == event.eventId)) return;
    // Storage is unavailable. Retain the event until upload acknowledgement or
    // successful persistence; a capacity threshold cannot authorize data loss.
    _memoryFallback.add(event);
  }

  void _recordUploadSuccess() {
    _lastUploadSuccessAt = _clock();
    _consecutiveUploadFailures = 0;
    _nextUploadAt = null;
  }

  void _recordUploadFailure(Object error) {
    _lastUploadFailureAt = _clock();
    _consecutiveUploadFailures += 1;
    _lastError = 'upload:${_safeError(error)}';
    _nextUploadAt = _clock().add(_retryDelay(_consecutiveUploadFailures));
    debugPrint('[Collect] upload failed: $error');
  }

  void _recordStoreFailure(String operation, Object error) {
    _storeStatus = CollectStoreStatus.unavailable;
    _recordError('sqlite_$operation', error);
    _scheduleStoreRecovery();
  }

  void _recordError(String operation, Object error) {
    _lastError = '$operation:${_safeError(error)}';
    debugPrint('[Collect] $operation failed: $error');
  }

  void _markStoreHealthy() {
    _storeStatus = CollectStoreStatus.healthy;
  }

  void _scheduleStoreRecovery() {
    if (_disposed || _storeRecovery != null || _storeRecoveryTimer != null) {
      return;
    }
    _storeRecoveryTimer = Timer(const Duration(seconds: 1), () {
      _storeRecoveryTimer = null;
      if (_checking) {
        _scheduleStoreRecovery();
        return;
      }
      final recovery = _recoverStore();
      _storeRecovery = recovery;
      unawaited(
        recovery.whenComplete(() {
          if (identical(_storeRecovery, recovery)) _storeRecovery = null;
        }),
      );
    });
  }

  Future<void> _recoverStore() async {
    if (_disposed) return;
    _storeStatus = CollectStoreStatus.recovering;
    try {
      await _store.resetConnection().timeout(_storeTimeout);
      _markStoreHealthy();
      _scheduleImmediateCheck();
    } catch (error) {
      _recordStoreFailure('reopen', error);
    }
  }

  Map<String, String> _headers(CollectEvent event) {
    final platform = event.contextCaptured ? event.platform : _context.platform;
    final appVersion = _resolvedAppVersion(event, _context.appVersion);
    final deviceId = event.contextCaptured ? event.deviceId : _context.deviceId;
    final userId = event.contextCaptured ? event.userId : _context.userId;
    return <String, String>{
      for (final entry in <String, String?>{
        'X-Platform': _collectPlatformHeaderValue(platform),
        'X-App-Version': appVersion,
        'x-app-environment': event.appEnvironment.trim().isEmpty
            ? _context.appEnvironment
            : event.appEnvironment,
        if (event.includeIdentityHeaders) 'X-Device-ID': deviceId,
        if (event.includeIdentityHeaders) 'X-UID': userId,
      }.entries)
        if ((entry.value ?? '').trim().isNotEmpty)
          entry.key: entry.value!.trim(),
    };
  }
}

String _resolvedAppVersion(CollectEvent event, String currentAppVersion) {
  final current = currentAppVersion.trim();
  if (!event.contextCaptured) return current;
  final captured = event.appVersion.trim();
  if (_hasKnownCollectAppVersion(captured) ||
      !_hasKnownCollectAppVersion(current)) {
    return captured;
  }
  // Version metadata can recover after an early event captured `unknown`.
  // Late-bind only this header; device and user identity remain event snapshots.
  return current;
}

bool _hasKnownCollectAppVersion(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isNotEmpty && normalized != 'unknown';
}

class _MemoryCollectEventRow {
  _MemoryCollectEventRow(this.sequence, this.event);

  int sequence;
  final CollectEvent event;
  String state = _pendingState;
  String? batchId;
}

Map<String, Object?> _eventToRow(CollectEvent event) {
  return <String, Object?>{
    'event_id': event.eventId,
    'action_type': event.actionType,
    'action': event.action,
    'app_timestamp': event.appTimestamp,
    'object1': event.object1,
    'object2': event.object2,
    'object3': event.object3,
    'object4': event.object4,
    'ext_data': event.extData,
    'app_environment': event.appEnvironment,
    'platform': event.platform,
    'app_version': event.appVersion,
    'device_id': event.deviceId,
    'user_id': event.userId,
    'include_identity_headers': event.includeIdentityHeaders ? 1 : 0,
    'context_captured': event.contextCaptured ? 1 : 0,
    'state': _pendingState,
    'batch_id': null,
  };
}

CollectEvent _eventFromRow(Map<String, Object?> row) {
  return CollectEvent(
    eventId: '${row['event_id'] ?? ''}',
    actionType: '${row['action_type'] ?? ''}',
    action: '${row['action'] ?? ''}',
    appTimestamp: row['app_timestamp'] as int? ?? 0,
    object1: '${row['object1'] ?? ''}',
    object2: '${row['object2'] ?? ''}',
    object3: '${row['object3'] ?? ''}',
    object4: '${row['object4'] ?? ''}',
    extData: '${row['ext_data'] ?? ''}',
    appEnvironment: '${row['app_environment'] ?? ''}',
    platform: '${row['platform'] ?? ''}',
    appVersion: '${row['app_version'] ?? ''}',
    deviceId: '${row['device_id'] ?? ''}',
    userId: '${row['user_id'] ?? ''}',
    includeIdentityHeaders: (row['include_identity_headers'] as int? ?? 1) != 0,
    contextCaptured: (row['context_captured'] as int? ?? 0) != 0,
  );
}

bool _hasSameUploadContext(CollectEvent left, CollectEvent right) {
  if (left.appEnvironment != right.appEnvironment ||
      left.includeIdentityHeaders != right.includeIdentityHeaders ||
      left.contextCaptured != right.contextCaptured) {
    return false;
  }
  if (!left.contextCaptured) return true;
  if (left.platform != right.platform || left.appVersion != right.appVersion) {
    return false;
  }
  if (!left.includeIdentityHeaders) return true;
  return left.deviceId == right.deviceId && left.userId == right.userId;
}

String _stringValue(Object? value) {
  if (value == null) return '';
  return value.toString();
}

String _boundedString(Object? value, int maxLength) {
  final text = _stringValue(value);
  if (text.length <= maxLength) return text;
  return text.substring(0, maxLength);
}

int _encodedBatchSize(List<CollectEvent> events) {
  return utf8
      .encode(
        jsonEncode(<String, Object>{
          'events': events.map((event) => event.toWireMap()).toList(),
        }),
      )
      .length;
}

CollectUploadFailureKind _uploadFailureKind(Object error) {
  if (error is CollectUploadException) return error.kind;
  return CollectUploadFailureKind.transient;
}

Duration _retryDelay(int failureCount) {
  return switch (failureCount) {
    <= 1 => const Duration(seconds: 5),
    2 => const Duration(seconds: 15),
    3 => const Duration(seconds: 30),
    4 => const Duration(minutes: 1),
    _ => const Duration(minutes: 5),
  };
}

String _safeError(Object error) {
  if (error is CollectUploadException) return error.toString();
  return error.runtimeType.toString();
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _collectPlatformHeaderValue(String platform) {
  final normalized = platform.trim().toLowerCase();
  if (normalized == 'ios') return 'ios';
  if (normalized == 'android') return 'android';
  return platform.trim();
}

String newCollectEventId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

const _pendingState = 'pending';
const _inFlightState = 'inflight';

const _createCollectEventsSql = '''
  CREATE TABLE collect_events (
    sequence_id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    action_type TEXT NOT NULL,
    action TEXT NOT NULL,
    app_timestamp INTEGER NOT NULL,
    object1 TEXT NOT NULL,
    object2 TEXT NOT NULL,
    object3 TEXT NOT NULL,
    object4 TEXT NOT NULL DEFAULT '',
    ext_data TEXT NOT NULL DEFAULT '',
    app_environment TEXT NOT NULL DEFAULT '',
    platform TEXT NOT NULL DEFAULT '',
    app_version TEXT NOT NULL DEFAULT '',
    device_id TEXT NOT NULL DEFAULT '',
    user_id TEXT NOT NULL DEFAULT '',
    include_identity_headers INTEGER NOT NULL,
    context_captured INTEGER NOT NULL DEFAULT 0,
    state TEXT NOT NULL,
    batch_id TEXT
  )
''';

const _createCollectEventsStateIndexSql = '''
  CREATE INDEX idx_collect_events_state_sequence
  ON collect_events(state, sequence_id)
''';

const _createCollectEventsUploadContextIndexSql = '''
  CREATE INDEX idx_collect_events_upload_context
  ON collect_events(
    state,
    app_environment,
    include_identity_headers,
    context_captured,
    platform,
    app_version,
    device_id,
    user_id,
    sequence_id
  )
''';

const _addCollectAppEnvironmentSql = '''
  ALTER TABLE collect_events
  ADD COLUMN app_environment TEXT NOT NULL DEFAULT ''
''';

const _addCollectPlatformSql = '''
  ALTER TABLE collect_events
  ADD COLUMN platform TEXT NOT NULL DEFAULT ''
''';

const _addCollectAppVersionSql = '''
  ALTER TABLE collect_events
  ADD COLUMN app_version TEXT NOT NULL DEFAULT ''
''';

const _addCollectDeviceIdSql = '''
  ALTER TABLE collect_events
  ADD COLUMN device_id TEXT NOT NULL DEFAULT ''
''';

const _addCollectUserIdSql = '''
  ALTER TABLE collect_events
  ADD COLUMN user_id TEXT NOT NULL DEFAULT ''
''';

const _addCollectContextCapturedSql = '''
  ALTER TABLE collect_events
  ADD COLUMN context_captured INTEGER NOT NULL DEFAULT 0
''';

const _addCollectObject4Sql = '''
  ALTER TABLE collect_events
  ADD COLUMN object4 TEXT NOT NULL DEFAULT ''
''';

const _addCollectExtDataSql = '''
  ALTER TABLE collect_events
  ADD COLUMN ext_data TEXT NOT NULL DEFAULT ''
''';
