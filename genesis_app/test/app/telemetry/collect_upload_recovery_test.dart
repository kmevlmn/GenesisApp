import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/telemetry/collect_telemetry.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  for (final mode in ['memory_store', 'sqlite', 'fallback']) {
    for (final poison in [false, true]) {
      test(
        '$mode checkpoints partial ${poison ? 'poison' : 'size'} split success',
        () async {
          final store = await _store(mode);
          final accepted = <String>[];
          var failedB = false;
          var rejectPoison = true;
          var nextId = 0;
          final client = _Client((events) async {
            if (rejectPoison && events.any((e) => e.action == 'poison')) {
              throw const CollectUploadException(
                message: 'poison',
                kind: CollectUploadFailureKind.permanent,
              );
            }
            if (events.any((e) => e.action == 'b') && !failedB) {
              failedB = true;
              throw TimeoutException('transient b');
            }
            accepted.addAll(events.map((e) => e.action));
          });
          const sample = CollectEvent(
            eventId: 'split-0',
            actionType: 'event',
            action: 'a',
            appTimestamp: 0,
            object1: '',
            object2: '',
            object3: '',
            object4: '',
            extData: '',
          );
          final oneSize =
              utf8
                  .encode(
                    jsonEncode({
                      'events': [sample.toWireMap()],
                    }),
                  )
                  .length +
              30;
          final uploader = CollectTelemetryUploader(
            store: store,
            idGenerator: () => 'split-${nextId++}',
            maxBatchBytes: poison ? defaultCollectUploadBatchBytes : oneSize,
          )..configure(enabled: true, client: client);
          addTearDown(uploader.dispose);
          for (final action in ['a', if (poison) 'poison', 'b']) {
            await uploader.enqueuePayload({
              'action_type': 'event',
              'action': action,
            });
          }
          await uploader.checkNow();
          expect(accepted, ['a']);
          if (mode == 'fallback') {
            expect(uploader.health.memoryFallbackCount, poison ? 2 : 1);
          }
          await uploader.checkNow(force: true);
          expect(accepted, ['a', 'b']);
          expect(uploader.health.deadLetterCount, 0);
          rejectPoison = false;
          await uploader.checkNow(force: true);
          expect(accepted, ['a', 'b', if (poison) 'poison']);
          expect(uploader.health.memoryFallbackCount, 0);
          expect(await store.claimPending(limit: 100), isNull);
        },
      );
    }
  }

  for (final timing in [
    'before_upload',
    'during_upload',
    'after_upload',
    'committed_future_pending',
  ]) {
    test('late insert $timing uploads each ID once', () async {
      final store = _DelayedStore();
      final accepted = <String>[];
      final started = Completer<void>();
      final finishUpload = Completer<void>();
      final uploader =
          CollectTelemetryUploader(
            store: store,
            storeTimeout: const Duration(milliseconds: 20),
            idGenerator: () => 'late-id',
          )..configure(
            enabled: true,
            client: _Client((events) async {
              if (!started.isCompleted) started.complete();
              if (timing == 'during_upload') await finishUpload.future;
              accepted.addAll(events.map((e) => e.eventId));
            }),
          );
      addTearDown(uploader.dispose);
      await uploader.enqueuePayload({'action_type': 'event', 'action': 'late'});
      expect(uploader.health.memoryFallbackCount, 1);
      if (timing == 'before_upload' || timing == 'committed_future_pending') {
        store.insert.complete();
        await store.inserted.future;
        if (timing == 'before_upload') store.finish.complete();
      }
      final uploading = uploader.checkNow(force: true);
      if (timing == 'during_upload') {
        await started.future;
        store.insert.complete();
        await store.inserted.future;
        store.finish.complete();
        finishUpload.complete();
      }
      await uploading;
      if (timing == 'after_upload') {
        store.insert.complete();
        await store.inserted.future;
        store.finish.complete();
      } else if (timing == 'committed_future_pending') {
        store.finish.complete();
      }
      await store.finished.future;
      await uploader.checkNow(force: true);
      expect(accepted, ['late-id']);
      expect(store.delegate.eventsForTesting, isEmpty);
      expect(uploader.health.memoryFallbackCount, 0);
    });
  }

  test(
    'partial local deletion failure does not replay success or strand failed siblings',
    () async {
      final store = _DelayedStore();
      store.insert.complete();
      store.finish.complete();
      final accepted = <String>[];
      var failedB = false;
      var id = 0;
      final uploader =
          CollectTelemetryUploader(
            store: store,
            idGenerator: () => 'delete-${id++}',
            maxBatchBytes: 400,
          )..configure(
            enabled: true,
            client: _Client((events) async {
              if (events.any((e) => e.action == 'b') && !failedB) {
                failedB = true;
                throw TimeoutException('b failed');
              }
              accepted.addAll(events.map((e) => e.action));
            }),
          );
      addTearDown(uploader.dispose);
      for (final action in ['a', 'b']) {
        await uploader.enqueuePayload({
          'action_type': 'event',
          'action': action,
          'object1': 'x' * 150,
        });
      }
      store.failDelete = true;
      await uploader.checkNow(force: true);
      expect(accepted, ['a']);
      expect(store.delegate.pendingCountForTesting, 1);
      expect(store.delegate.inFlightCountForTesting, 1);
      store.failDelete = false;
      await uploader.checkNow(force: true);
      expect(accepted, ['a', 'b']);
      expect(store.delegate.pendingCountForTesting, 0);
      expect(store.delegate.inFlightCountForTesting, 1);
    },
  );

  test(
    'acknowledgement survives cleanup while a claimed batch is returning',
    () async {
      final store = _DelayedStore()..holdClaim = true;
      final accepted = <String>[];
      final uploader =
          CollectTelemetryUploader(
            store: store,
            storeTimeout: const Duration(milliseconds: 50),
            idGenerator: () => 'claim-race',
          )..configure(
            enabled: true,
            client: _Client(
              (events) async => accepted.addAll(events.map((e) => e.eventId)),
            ),
          );
      addTearDown(uploader.dispose);
      await uploader.enqueuePayload({'action_type': 'event', 'action': 'race'});
      store.insert.complete();
      await store.inserted.future;
      final checking = uploader.checkNow(force: true);
      await store.claimed.future;
      // The memory copy is accepted; the claim still holds the old row snapshot.
      store.finish.complete();
      await store.deleted.future;
      store.returnClaim.complete();
      await checking;
      expect(accepted, ['claim-race']);
      expect(store.delegate.eventsForTesting, isEmpty);
    },
  );

  test(
    'late-write cleanup failure retains acknowledgement until store recovers',
    () async {
      final store = _DelayedStore();
      final accepted = <String>[];
      final uploader =
          CollectTelemetryUploader(
            store: store,
            storeTimeout: const Duration(milliseconds: 20),
            idGenerator: () => 'cleanup-id',
          )..configure(
            enabled: true,
            client: _Client(
              (events) async => accepted.addAll(events.map((e) => e.eventId)),
            ),
          );
      addTearDown(uploader.dispose);
      await uploader.enqueuePayload({
        'action_type': 'event',
        'action': 'cleanup',
      });
      await uploader.checkNow(force: true);
      store.failDelete = true;
      store.insert.complete();
      store.finish.complete();
      await store.finished.future;
      await uploader.checkNow(force: true);
      expect(accepted, ['cleanup-id']);
      store.failDelete = false;
      await uploader.checkNow(force: true);
      expect(accepted, ['cleanup-id']);
      expect(store.delegate.eventsForTesting, isEmpty);
    },
  );

  test(
    'claiming a later fallback batch transfers ownership without replay',
    () async {
      final store = _DelayedStore();
      var id = 0;
      final accepted = <String>[];
      final uploader =
          CollectTelemetryUploader(
            store: store,
            storeTimeout: const Duration(milliseconds: 20),
            batchSize: 1,
            idGenerator: () => 'id-${id++}',
          )..configure(
            enabled: true,
            client: _Client(
              (events) async => accepted.addAll(events.map((e) => e.eventId)),
            ),
          );
      addTearDown(uploader.dispose);
      for (var i = 0; i < 2; i++) {
        await uploader.enqueuePayload({
          'action_type': 'event',
          'action': 'later',
        });
      }
      store.insert.complete();
      store.finish.complete();
      await store.finished.future;
      await uploader.checkNow(force: true);
      await uploader.checkNow(force: true);
      await uploader.checkNow(force: true);
      expect(accepted, ['id-0', 'id-1']);
      expect(uploader.health.memoryFallbackCount, 0);
      expect(store.delegate.eventsForTesting, isEmpty);
    },
  );

  test(
    'hung writes stay bounded without discarding unconfirmed events',
    () async {
      final store = _DelayedStore();
      var id = 0;
      final accepted = <String>[];
      final uploader =
          CollectTelemetryUploader(
            store: store,
            storeTimeout: const Duration(milliseconds: 10),
            memoryFallbackLimit: 2,
            idGenerator: () => 'id-${id++}',
          )..configure(
            enabled: true,
            client: _Client(
              (events) async => accepted.addAll(events.map((e) => e.eventId)),
            ),
          );
      addTearDown(uploader.dispose);
      for (var i = 0; i < 10; i++) {
        await uploader.enqueuePayload({
          'action_type': 'event',
          'action': 'bounded',
        });
      }
      expect(store.enqueueCount, 2);
      expect(uploader.health.memoryFallbackCount, 10);
      expect(uploader.health.droppedEventCount, 0);
      await uploader.checkNow(force: true);
      store.insert.complete();
      store.finish.complete();
      await store.finished.future;
      await uploader.checkNow(force: true);
      expect(accepted.toSet(), {for (var i = 0; i < 10; i++) 'id-$i'});
      expect(accepted, hasLength(10));
    },
  );
}

Future<CollectEventStore> _store(String mode) async {
  if (mode == 'fallback') return _UnavailableStore();
  if (mode != 'sqlite') return MemoryCollectEventStore();
  sqfliteFfiInit();
  final directory = await Directory.systemTemp.createTemp('collect-recovery-');
  final store = SqfliteCollectEventStore(
    databaseFactoryOverride: databaseFactoryFfi,
    databasePath: '${directory.path}/events.db',
  );
  addTearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  return store;
}

class _Client implements CollectTelemetryClient {
  _Client(this.action);
  final Future<void> Function(List<CollectEvent>) action;
  @override
  Future<void> collectBatch(
    List<CollectEvent> events, {
    Map<String, String> headers = const {},
    NetworkCancellationToken? cancellationToken,
  }) => action(events);
}

class _UnavailableStore extends MemoryCollectEventStore {
  @override
  Future<void> enqueue(CollectEvent event) async =>
      throw StateError('store unavailable');
}

class _DelayedStore implements CollectEventStore {
  final delegate = MemoryCollectEventStore();
  final insert = Completer<void>();
  final inserted = Completer<void>();
  final finish = Completer<void>();
  final finished = Completer<void>();
  bool failDelete = false;
  bool holdClaim = false;
  final claimed = Completer<void>();
  final returnClaim = Completer<void>();
  final deleted = Completer<void>();
  int enqueueCount = 0;
  int completedCount = 0;
  @override
  Future<void> enqueue(CollectEvent event) async {
    enqueueCount++;
    await insert.future;
    await delegate.enqueue(event);
    if (!inserted.isCompleted) inserted.complete();
    await finish.future;
    completedCount++;
    if (completedCount == enqueueCount && !finished.isCompleted) {
      finished.complete();
    }
  }

  @override
  Future<void> recoverInFlight() => delegate.recoverInFlight();
  @override
  Future<ClaimedCollectEventBatch?> claimPending({required int limit}) async {
    final result = await delegate.claimPending(limit: limit);
    if (holdClaim) {
      if (!claimed.isCompleted) claimed.complete();
      await returnClaim.future;
    }
    return result;
  }

  @override
  Future<void> deleteClaimed(String batchId) => delegate.deleteClaimed(batchId);
  @override
  Future<void> deleteEvents(List<String> ids) async {
    if (ids.isEmpty) return;
    if (failDelete) throw StateError('delete unavailable');
    await delegate.deleteEvents(ids);
    if (!deleted.isCompleted) deleted.complete();
  }

  @override
  Future<void> releaseClaimed(
    String batchId, {
    List<String> excludingEventIds = const [],
  }) => delegate.releaseClaimed(batchId, excludingEventIds: excludingEventIds);
  @override
  Future<void> resetConnection() async {}
}
