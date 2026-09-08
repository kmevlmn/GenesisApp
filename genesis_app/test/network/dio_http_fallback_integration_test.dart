import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/dio_http_transport.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:http2/http2.dart';

void main() {
  test(
    'default Dio validates TLS and falls back before sending one POST',
    () async {
      // Generate a short-lived loopback certificate to respect macOS lifetime
      // limits and avoid a checked-in certificate eventually expiring in CI.
      final fixture = await _createTlsFixture();
      addTearDown(() => fixture.delete(recursive: true));
      final certificate = File('${fixture.path}/cert.pem').readAsBytesSync();
      final context = SecurityContext()
        ..useCertificateChainBytes(certificate)
        ..usePrivateKey('${fixture.path}/key.pem');
      // Dart's HTTP server speaks HTTP/1.1 and this endpoint offers no h2 ALPN.
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => server.close(force: true));
      final bodies = <String>[];
      server.listen((request) async {
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"err_no":0}');
        await request.response.close();
      }, onError: (Object _) {});
      final transport = DioHttpTransport(performanceMetricReady: () => false);
      final request = TransportRequest(
        method: 'POST',
        uri: Uri.parse('https://localhost:${server.port}/api/v1/collect'),
        headers: const {'content-type': 'application/json'},
        bodyBytes: utf8.encode('{"events":[{"event_id":"same-id"}]}'),
        timeoutMs: 5000,
      );
      await expectLater(
        transport.send(request),
        throwsA(
          isA<DioException>().having(
            (error) => error.error,
            'cause',
            isA<HandshakeException>(),
          ),
        ),
      );
      expect(
        bodies,
        isEmpty,
        reason: 'An untrusted certificate must prevent the business POST.',
      );

      // Both adapters validate against this explicit test-only CA trust store.
      final trustedContext = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(certificate);
      final trustedTransport = DioHttpTransport(
        securityContext: trustedContext,
        performanceMetricReady: () => false,
      );
      final response = await trustedTransport.send(request);
      expect(response.statusCode, 200);
      expect(response.body, '{"err_no":0}');
      expect(bodies, ['{"events":[{"event_id":"same-id"}]}']);
    },
  );

  test('repeated HTTP/1.1 fallback releases every unused TLS socket', () async {
    final fixture = await _createTlsFixture();
    addTearDown(() => fixture.delete(recursive: true));
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain('${fixture.path}/cert.pem')
        ..usePrivateKey('${fixture.path}/key.pem'),
    );
    addTearDown(() => server.close(force: true));
    var posts = 0;
    server.listen((request) async {
      await request.drain<void>();
      posts++;
      request.response.persistentConnection = false;
      request.response.write('{"err_no":0}');
      await request.response.close();
    }, onError: (Object _) {});
    final transport = DioHttpTransport(
      securityContext: SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('${fixture.path}/cert.pem'),
      performanceMetricReady: () => false,
    );
    for (var i = 0; i < 4; i++) {
      await transport.send(
        TransportRequest(
          method: 'POST',
          uri: Uri.parse('https://localhost:${server.port}/api/v1/collect'),
          headers: const {},
          bodyBytes: utf8.encode('{}'),
          timeoutMs: 5000,
        ),
      );
      // Socket close propagation is asynchronous. Bound the wait by a deadline.
      final watch = Stopwatch()..start();
      while (server.connectionsInfo().total > 0 &&
          watch.elapsedMilliseconds < 1000) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(
        server.connectionsInfo().total,
        0,
        reason: 'fallback iteration $i',
      );
      expect(posts, i + 1);
    }
  });

  test('successful HTTP/2 requests still share a TLS connection', () async {
    final fixture = await _createTlsFixture();
    addTearDown(() => fixture.delete(recursive: true));
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain('${fixture.path}/cert.pem')
        ..usePrivateKey('${fixture.path}/key.pem')
        ..setAlpnProtocols(['h2'], true),
      supportedProtocols: ['h2'],
    );
    final sockets = <SecureSocket>[];
    final bodies = <String>[];
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
    });
    server.listen((socket) {
      sockets.add(socket);
      expect(socket.selectedProtocol, 'h2');
      final connection = ServerTransportConnection.viaSocket(socket);
      connection.incomingStreams.listen((stream) async {
        final bytes = <int>[];
        await for (final message in stream.incomingMessages) {
          if (message is DataStreamMessage) bytes.addAll(message.bytes);
        }
        bodies.add(utf8.decode(bytes));
        stream.sendHeaders([Header.ascii(':status', '200')]);
        stream.sendData(utf8.encode('{"err_no":0}'), endStream: true);
      });
    });
    final transport = DioHttpTransport(
      securityContext: SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('${fixture.path}/cert.pem'),
      performanceMetricReady: () => false,
    );
    Future<TransportResponse> send(int id) => transport.send(
      TransportRequest(
        method: 'POST',
        uri: Uri.parse('https://localhost:${server.port}/send'),
        headers: const {},
        bodyBytes: utf8.encode('event-$id'),
        timeoutMs: 5000,
      ),
    );
    final responses = [
      ...await Future.wait([send(1), send(2)]),
      await send(3),
    ];
    expect(responses.map((r) => r.httpProtocolVersion), everyElement('h2'));
    expect(bodies, unorderedEquals(['event-1', 'event-2', 'event-3']));
    expect(sockets, hasLength(1));
  });

  for (final notSupported in [false, true]) {
    test(
      'cancellation during H2 connect prevents late stream or fallback ($notSupported)',
      () async {
        final delegate = _DelayedConnectionManager();
        final guarded = CancellationAwareHttp2ConnectionManager(delegate);
        final token = CancelToken();
        final options = RequestOptions(
          path: 'https://example.invalid/send',
          cancelToken: token,
        );
        final future = guarded.getConnection(options, []);
        final checked = expectLater(
          future,
          throwsA(
            isA<DioException>().having(
              (error) => error.type,
              'type',
              DioExceptionType.cancel,
            ),
          ),
        );
        token.cancel();
        if (notSupported) {
          delegate.connection.completeError(
            DioH2NotSupportedException(Uri.parse(options.path), null),
          );
        } else {
          delegate.connection.complete(_UnusedConnection());
        }
        await checked;
        expect(
          delegate.closed,
          isFalse,
          reason: 'Other requests may share the connection.',
        );
      },
    );
  }
}

Future<Directory> _createTlsFixture() async {
  final directory = await Directory.systemTemp.createTemp('worldo-http-tls-');
  try {
    final config = File('${directory.path}/openssl.cnf');
    await config.writeAsString('''
[req]
prompt=no
distinguished_name=dn
x509_extensions=v3
[dn]
CN=localhost
[v3]
subjectAltName=DNS:localhost,IP:127.0.0.1
basicConstraints=critical,CA:TRUE
keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign
extendedKeyUsage=serverAuth
''');
    final result = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-sha256',
      '-days',
      '2',
      '-config',
      config.path,
      '-keyout',
      '${directory.path}/key.pem',
      '-out',
      '${directory.path}/cert.pem',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Test certificate generation failed: ${result.stderr}');
    }
    return directory;
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
}

class _DelayedConnectionManager implements ConnectionManager {
  final connection = Completer<ClientTransportConnection>();
  bool closed = false;
  @override
  Future<ClientTransportConnection> getConnection(
    RequestOptions options,
    List<RedirectRecord> redirects,
  ) => connection.future;
  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  void removeConnection(ClientTransportConnection transport) {}
  @override
  int get cachedConnectionsCount => 0;
}

class _UnusedConnection implements ClientTransportConnection {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
