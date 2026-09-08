import 'package:genesis_flutter_android/network/chatroom/chatroom_http_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/common/genesis_center_toast.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';

class _FakeTransport implements HttpTransport {
  _FakeTransport({required this.handler});
  final TransportResponse Function(TransportRequest) handler;
  @override
  Future<TransportResponse> send(TransportRequest request) async =>
      handler(request);
}

void main() {
  testWidgets('message mutation err_msg displays in the global toast', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
    );
    final api = GenesisApi(
      transport: _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"err_no":2012,"err_msg":"Only the original sender can edit this reply","data":false}',
        ),
      ),
      useMock: false,
      sessionStore: MemoryUserSessionStore(),
      appHeaderProvider: () async => {},
      onChatroomMessageMutationError: (message) => showGenesisToastInOverlay(
        navigatorKey.currentState!.overlay!,
        message,
      ),
    );
    await expectLater(
      api.chatroomHttp.batchMutateLlmMessages(
        worldId: 'w',
        locationId: 'l',
        conversationRoundId: 1,
        operations: [
          ChatroomLlmMessageOperation.edit(globalMessageId: 1, content: 'edit'),
        ],
      ),
      throwsA(isA<ApiException>()),
    );
    await tester.pump();
    expect(
      find.text('Only the original sender can edit this reply'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.text('Only the original sender can edit this reply'),
      findsNothing,
    );
  });
}
