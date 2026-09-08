import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/genesis_http_cache_manager.dart';
import 'package:genesis_flutter_android/network/genesis_http_transport_pool.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/network_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final warmUpFails in [false, true]) {
    test(
      'native business request does not wait for warm-up ($warmUpFails)',
      () async {
        final transport = _PendingWarmUpTransport();
        final pool = GenesisHttpTransportPool.platform(
          transportBuilder: () => transport,
        );
        final warmUp = pool.warmUp(
          Uri.parse('https://cdn-001.worldo.ai/robots.txt'),
        );
        final checkedWarmUp = warmUpFails
            ? expectLater(warmUp, throwsStateError)
            : warmUp;
        final response = await pool.send(
          TransportRequest(
            method: 'POST',
            uri: Uri.parse('https://cdn-001.worldo.ai/send'),
            headers: const {},
            bodyBytes: [1],
            timeoutMs: 100,
          ),
        );
        expect(response.statusCode, 200);
        expect(transport.methods, ['HEAD', 'POST']);
        if (warmUpFails) {
          transport.pending.completeError(StateError('warm-up failed'));
        } else {
          transport.pending.complete(response);
        }
        await checkedWarmUp;
        expect(
          (await pool.send(
            TransportRequest(
              method: 'POST',
              uri: Uri.parse('https://cdn-001.worldo.ai/send'),
              headers: const {},
              bodyBytes: [2],
              timeoutMs: 100,
            ),
          )).statusCode,
          200,
        );
        expect(transport.methods, ['HEAD', 'POST', 'POST']);
      },
    );
  }
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'global transport pool warms every connection once per origin',
    () async {
      const response = TransportResponse(
        statusCode: 200,
        headers: <String, String>{},
        body: '',
        httpProtocolVersion: '2.0',
      );
      final transports = List<_RecordingTransport>.generate(
        genesisHttp2ConnectionCount,
        (_) => _RecordingTransport(response),
      );
      final pool = GenesisHttpTransportPool(transports: transports);
      final warmUpUri = Uri.parse('https://cdn-001.worldo.ai/robots.txt');

      await Future.wait<void>([pool.warmUp(warmUpUri), pool.warmUp(warmUpUri)]);

      for (final transport in transports) {
        expect(transport.requests, hasLength(1));
        final request = transport.requests.single;
        expect(request.method, 'HEAD');
        expect(request.uri, warmUpUri);
        expect(request.headers, const <String, String>{'accept': '*/*'});
        expect(request.timeoutMs, 10000);
      }
    },
  );

  test(
    'global transport pool distributes requests over three connections',
    () async {
      const response = TransportResponse(
        statusCode: 200,
        headers: <String, String>{},
        body: '',
        httpProtocolVersion: '2.0',
      );
      final transports = List<_RecordingTransport>.generate(
        genesisHttp2ConnectionCount,
        (_) => _RecordingTransport(response),
      );
      final pool = GenesisHttpTransportPool(transports: transports);
      final urls = <Uri>[
        Uri.parse('https://api.worldo.ai/api/v1/world/map'),
        Uri.parse('https://cdn-001.worldo.ai/predata/tiles/tile-1.webp'),
        Uri.parse('https://collect.worldo.ai/api/v1/collect'),
        Uri.parse('https://api.worldo.ai/api/v1/origin/list'),
        Uri.parse('https://cdn-001.worldo.ai/predata/tiles/tile-4.webp'),
        Uri.parse('https://af.hushie.ai/html/index.html'),
        Uri.parse('https://dev.hushie.ai/api/v1/world/map'),
      ];

      await Future.wait([
        for (final url in urls)
          pool.send(
            TransportRequest(
              method: 'GET',
              uri: url,
              headers: const <String, String>{},
              bodyBytes: null,
              timeoutMs: 1000,
            ),
          ),
      ]);

      expect(
        transports.map(
          (transport) =>
              transport.requests.map((request) => request.uri.host).toList(),
        ),
        [
          ['api.worldo.ai', 'api.worldo.ai', 'dev.hushie.ai'],
          ['cdn-001.worldo.ai', 'cdn-001.worldo.ai'],
          ['collect.worldo.ai', 'af.hushie.ai'],
        ],
      );
    },
  );

  test('HTTP/3 platform pool creates one native connection manager', () {
    var nativeBuilds = 0;
    final pool = GenesisHttpTransportPool.platform(
      transportBuilder: () {
        nativeBuilds += 1;
        return _RecordingTransport(
          const TransportResponse(
            statusCode: 200,
            headers: <String, String>{},
            body: '',
            httpProtocolVersion: 'h3',
          ),
        );
      },
    );

    expect(nativeBuilds, genesisHttp3ConnectionCount);
    expect(pool.connectionCount, genesisHttp3ConnectionCount);
  });

  test('failed warm-up can be retried', () async {
    final transport = _FailOnceTransport(
      const TransportResponse(
        statusCode: 200,
        headers: <String, String>{},
        body: '',
        httpProtocolVersion: 'h3',
      ),
    );
    final pool = GenesisHttpTransportPool(
      transports: <HttpTransport>[transport],
    );
    final warmUpUri = Uri.parse('https://cdn-001.worldo.ai/robots.txt');

    await expectLater(pool.warmUp(warmUpUri), throwsStateError);
    await pool.warmUp(warmUpUri);

    expect(transport.requests, hasLength(2));
  });

  test(
    'native initialization failure creates three HTTP/2 fallbacks',
    () async {
      var fallbackBuilds = 0;
      final fallbackTransports = <_RecordingTransport>[];
      final pool = GenesisHttpTransportPool.platform(
        transportBuilder: () => throw StateError('Cronet unavailable'),
        fallbackBuilder: () {
          fallbackBuilds += 1;
          final transport = _RecordingTransport(
            const TransportResponse(
              statusCode: 200,
              headers: <String, String>{},
              body: 'fallback',
              httpProtocolVersion: 'h2',
            ),
          );
          fallbackTransports.add(transport);
          return transport;
        },
      );

      for (var index = 0; index < 3; index += 1) {
        await pool.send(
          TransportRequest(
            method: 'GET',
            uri: Uri.parse('https://api.worldo.ai/request-$index'),
            headers: const <String, String>{},
            bodyBytes: null,
            timeoutMs: 1000,
          ),
        );
      }

      expect(fallbackBuilds, 3);
      expect(fallbackTransports, hasLength(3));
      for (final transport in fallbackTransports) {
        expect(transport.requests, hasLength(1));
      }
    },
  );

  test('image file service sends downloads through shared transport', () async {
    final transport = _RecordingTransport(
      TransportResponse(
        statusCode: 200,
        headers: const <String, String>{
          'Cache-Control': 'public, max-age=60',
          'Content-Length': '5',
          'Content-Type': 'image/webp',
          'ETag': 'image-v1',
        },
        body: 'image',
        bodyBytes: utf8.encode('image'),
        responsePayloadSizeBytes: 5,
        httpProtocolVersion: '2.0',
      ),
    );
    final service = GenesisHttpFileService(
      transport: transport,
      timeoutMs: 4321,
    );
    expect(service.concurrentFetches, genesisHttpImageConcurrentFetches);
    final beforeRequest = DateTime.now();

    final response = await service.get(
      'https://cdn.example.com/image.webp',
      headers: const <String, String>{'if-none-match': 'image-v0'},
    );

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.uri, Uri.parse('https://cdn.example.com/image.webp'));
    expect(request.headers['if-none-match'], 'image-v0');
    expect(request.timeoutMs, 4321);
    expect(request.decodeResponseBody, false);
    expect(await response.content.expand((chunk) => chunk).toList(), [
      ...utf8.encode('image'),
    ]);
    expect(response.statusCode, 200);
    expect(response.contentLength, 5);
    expect(response.eTag, 'image-v1');
    expect(response.fileExtension, '.webp');
    final validTill = response.validTill;
    expect(
      validTill.isBefore(beforeRequest.add(const Duration(seconds: 60))),
      false,
    );
    expect(
      validTill.isBefore(DateTime.now().add(const Duration(seconds: 61))),
      true,
    );
  });

  test('image file service records actual CDN downloads only', () async {
    final imageBytes = List<int>.filled(84 * 1024, 1);
    final transport = _RecordingTransport(
      TransportResponse(
        statusCode: 200,
        headers: const <String, String>{'content-type': 'image/webp'},
        body: '',
        bodyBytes: imageBytes,
        responsePayloadSizeBytes: imageBytes.length,
        httpProtocolVersion: 'h3',
      ),
    );
    final captureController = NetworkCaptureController();
    await captureController.setEnabled(true);
    final service = GenesisHttpFileService(
      transport: transport,
      captureController: captureController,
      isDebugBuild: true,
    );
    const url =
        'https://cdn-001.worldo.ai/cover.webp'
        '?x-oss-process=image/resize,w_360,image/format,webp';

    await service.get(url);

    final record = captureController.records.single;
    expect(record.method, 'GET');
    expect(record.uri, Uri.parse(url));
    expect(record.status, NetworkCaptureStatus.success);
    expect(record.statusCode, 200);
    expect(record.httpProtocolVersion, 'h3');
    expect(record.responseBody?.binary, isTrue);
    expect(record.responseBody?.byteCount, 84 * 1024);
    expect(record.responseBody?.text, '[Binary body: 86016 bytes]');
  });

  test('no-cache image response expires immediately', () {
    final beforeResponse = DateTime.now();
    final response = GenesisHttpFileServiceResponse(
      const TransportResponse(
        statusCode: 200,
        headers: <String, String>{'cache-control': 'no-cache'},
        body: '',
      ),
    );

    final validTill = response.validTill;
    expect(validTill.isBefore(beforeResponse), false);
    expect(
      validTill.isAfter(DateTime.now().add(const Duration(seconds: 1))),
      false,
    );
  });
}

class _PendingWarmUpTransport implements HttpTransport {
  final pending = Completer<TransportResponse>();
  final methods = <String>[];
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    methods.add(request.method);
    if (request.method == 'HEAD') return pending.future;
    return const TransportResponse(statusCode: 200, headers: {}, body: 'ok');
  }
}

class _RecordingTransport implements HttpTransport {
  _RecordingTransport(this.response);

  final TransportResponse response;
  final List<TransportRequest> requests = <TransportRequest>[];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return response;
  }
}

class _FailOnceTransport extends _RecordingTransport {
  _FailOnceTransport(super.response);

  bool _failed = false;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    if (!_failed) {
      _failed = true;
      throw StateError('warm-up failed');
    }
    return response;
  }
}
