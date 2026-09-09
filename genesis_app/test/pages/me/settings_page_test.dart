import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genesis_flutter_android/app/bootstrap/app_services_scope.dart';
import 'package:genesis_flutter_android/app/bootstrap/service_registry.dart';
import 'package:genesis_flutter_android/app/config/app_config.dart';
import 'package:genesis_flutter_android/app/config/platform_config.dart';
import 'package:genesis_flutter_android/app/version/app_version_check_service.dart';
import 'package:genesis_flutter_android/components/common/genesis_action_box.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_client.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_message_storage.dart';
import 'package:genesis_flutter_android/network/direct_message_conversation_store.dart';
import 'package:genesis_flutter_android/network/direct_message_message_store.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/models/user.dart';
import 'package:genesis_flutter_android/pages/me/settings_page.dart';
import 'package:genesis_flutter_android/platform/platform_services.dart';
import 'package:genesis_flutter_android/ui/genesis_ui.dart';

void main() {
  testWidgets('settings feedback opens shared dialog and submits', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.viewInsets = FakeViewPadding.zero;
    });

    final transport = _RecordingFeedbackTransport();
    final services = _feedbackTestServices(transport);

    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('About us'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      GenesisColors.darkBackground,
    );
    final logout = tester.widget<GenesisPrimaryButton>(
      find.widgetWithText(GenesisPrimaryButton, 'Log out'),
    );
    expect(logout.backgroundColor, GenesisColors.darkFaintFill);
    expect(logout.foregroundColor, GenesisColors.darkTextTertiary);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Join Discord'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('Delete account'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Account')).dy,
      greaterThan(tester.getTopLeft(find.text('About us')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Feedback')).dy,
      greaterThan(tester.getTopLeft(find.text('Account')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Join Discord')).dy,
      greaterThan(tester.getTopLeft(find.text('Feedback')).dy),
    );

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Current login account:'), findsOneWidget);
    final currentLoginAccountText = tester.widget<Text>(
      find.text('Current login account:'),
    );
    expect(currentLoginAccountText.style?.fontSize, 16);
    final accountCard = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text('Current login account:'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (accountCard.decoration as BoxDecoration).color,
      GenesisColors.darkFaintFill,
    );
    expect(find.text('Account Deletion Agreement'), findsOneWidget);
    expect(
      find.text('I have read the Account Deletion Agreement'),
      findsOneWidget,
    );
    final agreementTextFinder = find.text(
      'I have read the Account Deletion Agreement',
    );
    final agreementText = tester.widget<Text>(agreementTextFinder);
    expect(agreementText.style?.fontSize, 14);
    expect(
      tester.getTopLeft(find.byType(Checkbox)).dx,
      closeTo(tester.getTopLeft(find.text('Account Deletion Agreement')).dx, 1),
    );
    expect(
      tester.getTopLeft(find.byType(Checkbox)).dx,
      lessThan(tester.getTopLeft(agreementTextFinder).dx),
    );
    final gemsWarningFinder = find.textContaining(
      'All unused Gems, including purchased and earned Gems',
    );
    await tester.scrollUntilVisible(
      gemsWarningFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(gemsWarningFinder, findsOneWidget);
    expect(find.textContaining('voluntarily waive them'), findsOneWidget);
    expect(
      find.textContaining('account deletion does not automatically entitle'),
      findsOneWidget,
    );
    final gemsWarning = tester.widget<Text>(gemsWarningFinder);
    expect(gemsWarning.style?.color, GenesisColors.redSecondary);
    await tester.tap(find.widgetWithText(GenesisPrimaryButton, 'Delete'));
    await tester.pump();
    expect(find.text('Agree to our terms to continue.'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final selectedCheckbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(selectedCheckbox.value, isTrue);
    expect(selectedCheckbox.activeColor, GenesisColors.redPrimary);
    await tester.tap(find.widgetWithText(GenesisPrimaryButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(GenesisActionBox<bool>), findsOneWidget);
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.text('Delete'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    final logoutButtonTopBeforeKeyboard = tester
        .getTopLeft(find.widgetWithText(GenesisPrimaryButton, 'Log out'))
        .dy;

    await tester.tap(find.text('Feedback'));
    await tester.pumpAndSettle();

    expect(find.byType(GenesisActionBox<bool>), findsOneWidget);
    expect(find.text('Feedback'), findsWidgets);
    final inputFinder = find.byKey(
      const ValueKey<String>('genesis-feedback-content-input'),
    );
    final input = tester.widget<TextField>(inputFinder);
    expect(input.minLines, 3);
    expect(input.maxLines, 3);
    expect(input.autofocus, isTrue);
    expect(input.focusNode?.hasFocus, isTrue);
    expect(input.decoration?.filled, isTrue);
    expect(input.decoration?.fillColor, GenesisColors.darkFaintFill);
    expect(input.decoration?.focusedBorder?.borderSide, BorderSide.none);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(
      tester
          .getTopLeft(find.widgetWithText(GenesisPrimaryButton, 'Log out'))
          .dy,
      logoutButtonTopBeforeKeyboard,
    );

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    await tester.enterText(inputFinder, '希望增加夜间模式');
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, 'Submit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Feedback submitted'), findsOneWidget);
    expect(transport.requestsFor('/api/v1/feedback/create'), hasLength(1));
    expect(
      transport.decodedBody(
        transport.requestsFor('/api/v1/feedback/create').single,
      ),
      {'content': '希望增加夜间模式'},
    );
    await tester.pumpAndSettle();
    expect(find.byType(GenesisActionBox<bool>), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });
}

AppServices _feedbackTestServices(_RecordingFeedbackTransport transport) {
  const config = AppConfig(useMock: false);
  final platformConfig = DefaultPlatformConfig(appConfig: config);
  final deviceId = const _FakeDeviceIdService();
  final sessionStore = MemoryUserSessionStore();
  final identityAuth = const _FakeIdentityAuthService();
  final api = GenesisApi(
    useMock: false,
    transport: transport,
    platformConfig: platformConfig,
    deviceIdService: deviceId,
    sessionStore: sessionStore,
    identityAuthService: identityAuth,
    appHeaderProvider: () async => const <String, String>{
      'app-id': 'test-app',
      'app-version': '1.0.0',
      'app-platform': 'test',
      'device-id': 'test-device-id',
    },
  );
  return AppServices(
    config: config,
    platformConfig: platformConfig,
    deviceId: deviceId,
    sessionStore: sessionStore,
    identityAuth: identityAuth,
    backendAuth: const _FakeBackendAuthCoordinator(),
    api: api,
    chatroom: ChatroomClient(
      wsBaseUrl: config.chatroomWsBaseUrl,
      sessionStore: sessionStore,
    ),
    chatroomMessages: MemoryChatroomMessageStorage(),
    directMessageConversations: DirectMessageConversationStore(
      api: api,
      sessionStore: sessionStore,
      storage: MemoryDirectMessageConversationStorage(),
    ),
    directMessageMessages: DirectMessageMessageStore(
      api: api,
      sessionStore: sessionStore,
      storage: MemoryDirectMessageMessageStorage(),
    ),
    appVersionCheck: const _NoUpgradeVersionCheckService(),
    externalUrlOpener: const _FakeExternalUrlOpener(),
  );
}

class _RecordingFeedbackTransport implements HttpTransport {
  final requests = <TransportRequest>[];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return const TransportResponse(
      statusCode: 200,
      headers: {'content-type': 'application/json'},
      body: '{"err_no":0,"err_msg":"succ","data":{"feedback_id":"fbk_test"}}',
    );
  }

  List<TransportRequest> requestsFor(String path) {
    return requests.where((request) => request.uri.path == path).toList();
  }

  Map<String, dynamic> decodedBody(TransportRequest request) {
    return jsonDecode(utf8.decode(request.bodyBytes ?? const <int>[]))
        as Map<String, dynamic>;
  }
}

class _NoUpgradeVersionCheckService implements AppVersionCheckService {
  const _NoUpgradeVersionCheckService();

  @override
  Future<AppVersionCheckResult> check() async {
    return const AppVersionCheckResult.noUpgrade();
  }
}

class _FakeDeviceIdService implements DeviceIdService {
  const _FakeDeviceIdService();

  @override
  Future<String> getDeviceId() async => 'test-device-id';
}

class _FakeIdentityAuthService implements IdentityAuthService {
  const _FakeIdentityAuthService();

  @override
  Future<AuthSession?> refreshSilently() async => null;

  @override
  Future<AuthSession> signIn(IdentityProvider provider) {
    throw UnsupportedError('Identity sign-in is not used in this test.');
  }

  @override
  Future<void> signOutIdentity() async {}
}

class _FakeBackendAuthCoordinator implements BackendAuthCoordinator {
  const _FakeBackendAuthCoordinator();

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<bool> hasAuthenticatedBackendSession({
    bool tryAutoRefresh = true,
  }) async {
    return false;
  }

  @override
  Future<User> loginWithIdentity(AuthSession session) {
    throw UnsupportedError('Backend login is not used in this test.');
  }

  @override
  Future<void> signOut() async {}
}

class _FakeExternalUrlOpener implements ExternalUrlOpener {
  const _FakeExternalUrlOpener();

  @override
  Future<bool> open(String url) async => true;
}
