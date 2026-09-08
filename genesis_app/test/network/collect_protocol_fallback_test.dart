import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/telemetry/collect_telemetry.dart';
import 'package:genesis_flutter_android/network/platform_http3_transport.dart';
import 'package:genesis_flutter_android/network/io_http_transport.dart';
import 'package:http/http.dart' as http;

class _AcceptingEndpoint extends http.BaseClient {
  final requests = <Map<String, dynamic>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/collect');
    requests.add(
      jsonDecode(utf8.decode(await request.finalize().toBytes()))
          as Map<String, dynamic>,
    );
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"err_no":0}')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  test(
    'uploader deadline cancels SDK preparation and preserves the queued event',
    () async {
      final endpoint = _AcceptingEndpoint();
      final metric = _BlockedMetric();
      final store = MemoryCollectEventStore();
      final uploader =
          CollectTelemetryUploader(
            store: store,
            requestTimeout: const Duration(milliseconds: 50),
            idGenerator: () => 'stable-event',
          )..configure(
            enabled: true,
            client: SdkCollectTelemetryClient(
              endpoint: 'https://collect.invalid/api/v1/collect',
              timeoutMs: 5000,
              transport: PlatformHttp3Transport(
                client: endpoint,
                performanceMetricReady: () => true,
                performanceMetricFactory: (_, __) => metric,
              ),
            ),
          );
      addTearDown(uploader.dispose);
      await uploader.enqueuePayload({'action_type': 'event', 'action': 'send'});
      await uploader.checkNow();
      expect(endpoint.requests, isEmpty);
      expect(store.pendingCountForTesting, 1);
      expect(store.inFlightCountForTesting, 0);
      metric.release.complete();
      await metric.stopped.future;
      expect(
        endpoint.requests,
        isEmpty,
        reason: 'Late metric completion must not dispatch POST.',
      );
      await uploader.checkNow(force: true);
      expect(endpoint.requests, hasLength(1));
      expect(
        (endpoint.requests.single['events'] as List).single['event_id'],
        'stable-event',
      );
      expect(store.eventsForTesting, isEmpty);
    },
  );
  for (final firstProtocol in ['http/1.1', 'h2', 'h3', null]) {
    test(
      'Collect POST accepted with $firstProtocol is acknowledged without retry',
      () async {
        final endpoint = _AcceptingEndpoint();
        final transport = PlatformHttp3Transport(
          client: endpoint,
          protocolResolver: (_) => firstProtocol,
          performanceMetricReady: () => false,
        );
        final store = MemoryCollectEventStore();
        var now = DateTime.utc(2026, 9, 7);
        var generatedIds = 0;
        final uploader =
            CollectTelemetryUploader(
              store: store,
              clock: () => now,
              idGenerator: () => 'diagnostic-event-${++generatedIds}',
            )..configure(
              enabled: true,
              client: SdkCollectTelemetryClient(
                endpoint: 'https://collect.invalid/api/v1/collect',
                transport: transport,
              ),
            );
        addTearDown(uploader.dispose);
        addTearDown(endpoint.close);
        for (final actionType in ['monitor', 'event', 'pageview']) {
          await uploader.enqueuePayload({
            'action_type': actionType,
            'action': 'diagnostic_$actionType',
          });
        }

        await uploader.checkNow();
        expect(endpoint.requests, hasLength(1));
        expect(store.pendingCountForTesting, 0);
        expect(store.inFlightCountForTesting, 0);
        expect(uploader.health.consecutiveUploadFailures, 0);

        // Acknowledged events must stay removed even after a retry interval.
        await uploader.checkNow();
        expect(endpoint.requests, hasLength(1));
        now = now.add(const Duration(seconds: 5));
        await uploader.checkNow();
        expect(endpoint.requests, hasLength(1));
        expect(generatedIds, 3);
        expect(store.eventsForTesting, isEmpty);
        expect(uploader.health.consecutiveUploadFailures, 0);
      },
    );
  }
}

class _BlockedMetric implements HttpRequestPerformanceMetric {
  final release = Completer<void>();
  final stopped = Completer<void>();
  @override
  Future<void> start() => release.future;
  @override
  Future<void> stop() async {
    if (!stopped.isCompleted) stopped.complete();
  }

  @override
  void putAttribute(String name, String value) {}
  @override
  set httpResponseCode(int? value) {}
  @override
  set requestPayloadSize(int? value) {}
  @override
  set responseContentType(String? value) {}
  @override
  set responsePayloadSize(int? value) {}
}
