import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/telemetry/collect_telemetry.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/io_http_transport.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  for (final name in [
    'timeout',
    'network',
    'cancelled',
    'http500',
    'http401',
    'http403',
    'http408',
    'http429',
    'invalid_json',
    'non_object',
    'missing_err_no',
    'null_err_no',
    'nonzero_err_no',
    'http400',
    'http404',
    'http413',
    'http422',
  ]) {
    test(
      '$name retains the same event across retries and database reopen',
      () async {
        final store = await _sqliteStore();
        final endpoint = _Endpoint();
        switch (name) {
          case 'timeout':
            endpoint.error = TimeoutException('response not confirmed');
          case 'network':
            endpoint.error = const SocketException('connection closed');
          case 'cancelled':
            endpoint.error = const NetworkRequestCancelledException();
          case 'http500':
            endpoint.status = 500;
          case 'http401':
            endpoint.status = 401;
          case 'http403':
            endpoint.status = 403;
          case 'http408':
            endpoint.status = 408;
          case 'http429':
            endpoint.status = 429;
          case 'invalid_json':
            endpoint.body = 'not-json';
          case 'non_object':
            endpoint.body = '[]';
          case 'missing_err_no':
            endpoint.body = '{}';
          case 'null_err_no':
            endpoint.body = '{"err_no":null}';
          case 'nonzero_err_no':
            endpoint.body = '{"err_no":5000}';
          case 'http400':
            endpoint.status = 400;
          case 'http404':
            endpoint.status = 404;
          case 'http413':
            endpoint.status = 413;
          case 'http422':
            endpoint.status = 422;
        }
        final uploader = _uploader(store, endpoint);
        uploader.setContext(
          const CollectUploadContext(
            userId: 'captured-user',
            deviceId: 'captured-device',
            platform: 'android',
          ),
        );
        await uploader.enqueuePayload({
          'action_type': 'event',
          'action': 'delivery',
          'object1': 'original-content',
        });
        for (var attempt = 0; attempt < 2; attempt++) {
          await uploader.checkNow(force: true);
          final batch = await store.claimPending(limit: 100);
          expect(batch, isNotNull);
          expect(batch!.events.single.eventId, 'stable-id');
          expect(batch.events.single.object1, 'original-content');
          expect(batch.events.single.userId, 'captured-user');
          await store.releaseClaimed(batch.batchId);
          expect(uploader.health.deadLetterCount, 0);
          expect(uploader.health.droppedEventCount, 0);
        }
        uploader.dispose();
        await store.close();
        final reopened = SqfliteCollectEventStore(
          databaseFactoryOverride: databaseFactoryFfi,
          databasePath: store.databasePath,
        );
        addTearDown(reopened.close);
        endpoint.error = null;
        endpoint.status = 200;
        endpoint.body = '{"err_no":0}';
        final restarted = _uploader(reopened, endpoint);
        restarted.setUserId('different-current-user');
        await restarted.checkNow(force: true);
        await restarted.checkNow(force: true);
        expect(endpoint.requests, hasLength(3));
        expect(endpoint.ids, everyElement('stable-id'));
        expect(endpoint.requests.last.headers['X-UID'], 'captured-user');
        expect(await reopened.claimPending(limit: 100), isNull);
      },
    );
  }

  for (final mode in ['sqlite', 'memory_store', 'fallback']) {
    test(
      '$mode retries retained failures after untouched pending events',
      () async {
        final CollectEventStore store = mode == 'memory_store'
            ? MemoryCollectEventStore()
            : await _sqliteStore();
        final queue = mode == 'fallback'
            ? (_RecoveringStore(store)..failEnqueue = true)
            : store;
        final endpoint = _Endpoint();
        var reject = true;
        final accepted = <String>[];
        endpoint.respond = (events) {
          if (reject &&
              events.any(
                (event) => (event['action'] as String).startsWith('bad'),
              )) {
            return const TransportResponse(
              statusCode: 400,
              headers: {},
              body: '{"err_no":4004}',
            );
          }
          accepted.addAll(events.map((event) => event['event_id'] as String));
          return const TransportResponse(
            statusCode: 200,
            headers: {},
            body: '{"err_no":0}',
          );
        };
        var id = 0;
        final uploader =
            CollectTelemetryUploader(
              store: queue,
              batchSize: 2,
              idGenerator: () => 'fifo-${id++}',
            )..configure(
              enabled: true,
              client: SdkCollectTelemetryClient(
                endpoint: 'https://collect.invalid/api/v1/collect',
                transport: endpoint,
              ),
            );
        addTearDown(uploader.dispose);
        for (final action in ['bad-one', 'bad-two', 'good-one', 'good-two']) {
          await uploader.enqueuePayload({
            'action_type': 'event',
            'action': action,
          });
        }
        await uploader.checkNow(force: true);
        expect(accepted, isEmpty);
        await uploader.checkNow(force: true);
        expect(accepted, ['fifo-2', 'fifo-3']);
        // Also exercise a fresh insert after the queue's sequence IDs moved.
        await uploader.enqueuePayload({
          'action_type': 'event',
          'action': 'good-three',
        });
        await uploader.checkNow(force: true);
        await uploader.checkNow(force: true);
        expect(accepted, ['fifo-2', 'fifo-3', 'fifo-4']);
        reject = false;
        await uploader.checkNow(force: true);
        expect(accepted.take(3), ['fifo-2', 'fifo-3', 'fifo-4']);
        expect(accepted.skip(3), unorderedEquals(['fifo-0', 'fifo-1']));
        expect(uploader.health.memoryFallbackCount, 0);
        expect(uploader.health.droppedEventCount, 0);
        expect(await queue.claimPending(limit: 100), isNull);
      },
    );
  }

  test(
    'real HTTP rejection leaves SQLite data available for a later successful POST',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var reject = true;
      final ids = <String>[];
      server.listen((request) async {
        final payload =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        ids.add((payload['events'] as List).single['event_id'] as String);
        request.response.statusCode = reject ? 400 : 200;
        request.response.write(reject ? '{"err_no":4004}' : '{"err_no":0}');
        await request.response.close();
      });
      final native = HttpClient();
      addTearDown(() => native.close(force: true));
      final store = await _sqliteStore();
      final uploader =
          CollectTelemetryUploader(store: store, idGenerator: () => 'http-id')
            ..configure(
              enabled: true,
              client: SdkCollectTelemetryClient(
                endpoint: 'http://127.0.0.1:${server.port}/api/v1/collect',
                transport: IoHttpTransport(
                  client: native,
                  performanceMetricReady: () => false,
                ),
              ),
            );
      addTearDown(uploader.dispose);
      await uploader.enqueuePayload({
        'action_type': 'event',
        'action': 'real_http',
      });
      await uploader.checkNow(force: true);
      final pending = await store.claimPending(limit: 10);
      expect(pending!.events.single.eventId, 'http-id');
      await store.releaseClaimed(pending.batchId);
      reject = false;
      await uploader.checkNow(force: true);
      expect(ids, ['http-id', 'http-id']);
      expect(await store.claimPending(limit: 10), isNull);
    },
  );

  test(
    'SDK split rejection keeps the rejected event while acknowledging valid siblings',
    () async {
      final store = await _sqliteStore();
      final endpoint = _Endpoint();
      var rejectBad = true;
      final accepted = <String>[];
      endpoint.respond = (events) {
        if (rejectBad && events.any((event) => event['action'] == 'bad')) {
          return const TransportResponse(
            statusCode: 400,
            headers: {},
            body: '{"err_no":4004}',
          );
        }
        accepted.addAll(events.map((event) => event['event_id'] as String));
        return const TransportResponse(
          statusCode: 200,
          headers: {},
          body: '{"err_no":0}',
        );
      };
      var next = 0;
      final uploader = _uploader(
        store,
        endpoint,
        idGenerator: () => 'id-${next++}',
      );
      for (final action in ['good-before', 'bad', 'good-after']) {
        await uploader.enqueuePayload({
          'action_type': 'event',
          'action': action,
        });
      }
      await uploader.checkNow(force: true);
      expect(accepted, ['id-0', 'id-2']);
      final pending = await store.claimPending(limit: 100);
      expect(pending!.events.single.eventId, 'id-1');
      await store.releaseClaimed(pending.batchId);
      rejectBad = false;
      await uploader.checkNow(force: true);
      expect(accepted, ['id-0', 'id-2', 'id-1']);
      expect(await store.claimPending(limit: 100), isNull);
    },
  );

  test(
    'oversized single event survives reopen and does not discard valid siblings',
    () async {
      final store = await _sqliteStore();
      final endpoint = _Endpoint();
      var next = 0;
      final uploader = _uploader(
        store,
        endpoint,
        maxBatchBytes: 500,
        idGenerator: () => 'size-${next++}',
      );
      await uploader.enqueuePayload({
        'action_type': 'event',
        'action': 'large',
        'object1': 'x' * 1500,
      });
      await uploader.enqueuePayload({
        'action_type': 'event',
        'action': 'small',
      });
      await uploader.checkNow(force: true);
      expect(endpoint.ids, ['size-1']);
      expect(uploader.health.deadLetterCount, 0);
      uploader.dispose();
      await store.close();
      final reopened = SqfliteCollectEventStore(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: store.databasePath,
      );
      addTearDown(reopened.close);
      final pending = await reopened.claimPending(limit: 10);
      expect(pending!.events.single.eventId, 'size-0');
      expect(pending.events.single.object1, 'x' * 1500);
      await reopened.releaseClaimed(pending.batchId);
      // A later configuration that can carry the event can still deliver it.
      final restarted = _uploader(reopened, endpoint);
      await restarted.checkNow(force: true);
      expect(endpoint.ids, ['size-1', 'size-0']);
      expect(await reopened.claimPending(limit: 10), isNull);
    },
  );

  test(
    'recovered SQLite persists memory data even while uploads are in backoff',
    () async {
      final store = await _sqliteStore();
      final recovering = _RecoveringStore(store)..failEnqueue = true;
      final endpoint = _Endpoint()..status = 500;
      final uploader = _uploader(recovering, endpoint, memoryFallbackLimit: 1);
      await uploader.enqueuePayload({
        'action_type': 'event',
        'action': 'save_when_recovered',
      });
      await uploader.checkNow(force: true);
      expect(uploader.health.memoryFallbackCount, 1);
      expect(endpoint.requests, hasLength(1));
      recovering.failEnqueue = false;
      await uploader.checkNow();
      expect(
        endpoint.requests,
        hasLength(1),
        reason: 'network backoff is still in effect',
      );
      expect(uploader.health.memoryFallbackCount, 0);
      uploader.dispose();
      await store.close();
      final reopened = SqfliteCollectEventStore(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: store.databasePath,
      );
      addTearDown(reopened.close);
      endpoint.status = 200;
      final restarted = _uploader(reopened, endpoint);
      await restarted.checkNow(force: true);
      expect(endpoint.ids, ['stable-id', 'stable-id']);
      expect(await reopened.claimPending(limit: 10), isNull);
    },
  );

  for (final oldLimit in [0, 2]) {
    test(
      'failed memory uploads retain old and new events past limit $oldLimit',
      () async {
        final store = await _sqliteStore();
        final recovering = _RecoveringStore(store)..failEnqueue = true;
        final endpoint = _Endpoint()..status = 500;
        var nextId = 0;
        final uploader = _uploader(
          recovering,
          endpoint,
          memoryFallbackLimit: oldLimit,
          idGenerator: () => 'memory-${nextId++}',
        );
        for (var batch = 0; batch < 2; batch++) {
          for (var i = 0; i < 3; i++) {
            await uploader.enqueuePayload({
              'action_type': 'event',
              'action': 'retained',
            });
          }
          await uploader.checkNow(force: true);
        }
        expect(uploader.health.memoryFallbackCount, 6);
        expect(uploader.health.droppedEventCount, 0);
        recovering.failEnqueue = false;
        await uploader.checkNow();
        expect(endpoint.requests, hasLength(2));
        expect(uploader.health.memoryFallbackCount, 0);
        final persisted = await store.claimPending(limit: 100);
        expect(persisted!.events.map((event) => event.eventId), [
          for (var i = 0; i < 6; i++) 'memory-$i',
        ]);
        await store.releaseClaimed(persisted.batchId);
        endpoint.status = 200;
        await uploader.checkNow(force: true);
        expect(endpoint.requests, hasLength(3));
        expect(await store.claimPending(limit: 100), isNull);
      },
    );
  }

  test(
    'late backfill completion after memory upload cannot replay the accepted ID',
    () async {
      final store = await _sqliteStore();
      final recovering = _RecoveringStore(store)..failEnqueue = true;
      final endpoint = _Endpoint();
      final uploader = _uploader(
        recovering,
        endpoint,
        storeTimeout: const Duration(milliseconds: 20),
      );
      await uploader.enqueuePayload({
        'action_type': 'event',
        'action': 'late_backfill',
      });
      recovering.failEnqueue = false;
      recovering.delayWrite = Completer<void>();
      await uploader.checkNow(force: true);
      expect(endpoint.ids, ['stable-id']);
      recovering.delayWrite!.complete();
      await recovering.written.future;
      await uploader.checkNow(force: true);
      expect(endpoint.ids, ['stable-id']);
      expect(await store.claimPending(limit: 10), isNull);
    },
  );
}

CollectTelemetryUploader _uploader(
  CollectEventStore store,
  HttpTransport endpoint, {
  String Function()? idGenerator,
  int maxBatchBytes = defaultCollectUploadBatchBytes,
  int memoryFallbackLimit = defaultCollectMemoryFallbackLimit,
  Duration storeTimeout = defaultCollectStoreTimeout,
}) {
  final uploader =
      CollectTelemetryUploader(
        store: store,
        idGenerator: idGenerator ?? () => 'stable-id',
        maxBatchBytes: maxBatchBytes,
        memoryFallbackLimit: memoryFallbackLimit,
        storeTimeout: storeTimeout,
      )..configure(
        enabled: true,
        client: SdkCollectTelemetryClient(
          endpoint: 'https://collect.invalid/api/v1/collect',
          transport: endpoint,
        ),
      );
  addTearDown(uploader.dispose);
  return uploader;
}

Future<SqfliteCollectEventStore> _sqliteStore() async {
  sqfliteFfiInit();
  final directory = await Directory.systemTemp.createTemp('collect-retention-');
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

class _Endpoint extends HttpTransport {
  int status = 200;
  String body = '{"err_no":0}';
  Object? error;
  TransportResponse Function(List<Map<String, dynamic>>)? respond;
  final requests = <TransportRequest>[];
  final ids = <String>[];
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    final payload = jsonDecode(utf8.decode(request.bodyBytes!)) as Map;
    final events = (payload['events'] as List).cast<Map<String, dynamic>>();
    ids.addAll(events.map((event) => event['event_id'] as String));
    if (error != null) throw error!;
    return respond?.call(events) ??
        TransportResponse(statusCode: status, headers: const {}, body: body);
  }
}

class _RecoveringStore implements CollectEventStore {
  _RecoveringStore(this.delegate);
  final CollectEventStore delegate;
  bool failEnqueue = false;
  Completer<void>? delayWrite;
  final written = Completer<void>();
  @override
  Future<void> enqueue(CollectEvent event) async {
    if (failEnqueue) throw StateError('SQLite unavailable');
    await delayWrite?.future;
    await delegate.enqueue(event);
    if (!written.isCompleted) written.complete();
  }

  @override
  Future<void> recoverInFlight() => delegate.recoverInFlight();
  @override
  Future<ClaimedCollectEventBatch?> claimPending({required int limit}) =>
      delegate.claimPending(limit: limit);
  @override
  Future<void> deleteClaimed(String batchId) => delegate.deleteClaimed(batchId);
  @override
  Future<void> deleteEvents(List<String> ids) => delegate.deleteEvents(ids);
  @override
  Future<void> releaseClaimed(
    String batchId, {
    List<String> excludingEventIds = const [],
  }) => delegate.releaseClaimed(batchId, excludingEventIds: excludingEventIds);
  @override
  Future<void> resetConnection() => delegate.resetConnection();
}
