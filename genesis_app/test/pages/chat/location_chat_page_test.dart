import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genesis_flutter_android/components/ai_content_disclaimer.dart';
import 'package:genesis_flutter_android/app/bootstrap/app_services_scope.dart';
import 'package:genesis_flutter_android/app/bootstrap/service_registry.dart';
import 'package:genesis_flutter_android/app/config/app_config.dart';
import 'package:genesis_flutter_android/app/debug/location_chat_bubble_layout_settings.dart';
import 'package:genesis_flutter_android/app/debug/location_chat_header_effect_settings.dart';
import 'package:genesis_flutter_android/app/telemetry/firebase_analytics_monitoring.dart';
import 'package:genesis_flutter_android/components/chat/chatroom_failure_toast.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/icons/custom_icon_assets.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_client.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_connection_controller.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_http_models.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_message_storage.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_models.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_reply_action_storage.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_inspiration_storage.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/local_mock_genesis_transport.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_socket_transport.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_timeline_payload.dart';
import 'package:genesis_flutter_android/network/chatroom/world_chatroom_service.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_page.dart';
import 'package:genesis_flutter_android/pages/chat/message_parsers/location_chat_message_parsers.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_scroll_coordinator.dart';
import 'package:genesis_flutter_android/platform/channels/genesis_method_channels.dart';
import 'package:genesis_flutter_android/platform/device/android_sdk_version.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';
import 'package:genesis_flutter_android/ui/components/genesis_character_avatar.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_avatar_radii.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

String _readLocationChatImplementationSource() {
  return [
    'lib/pages/chat/location_chat_page.dart',
    'lib/pages/chat/location_chat_panel_connection.dart',
    'lib/pages/chat/location_chat_message_reconciler.dart',
    'lib/pages/chat/location_chat_send_actions.dart',
    'lib/pages/chat/location_chat_message_window.dart',
    'lib/pages/chat/location_chat_identity.dart',
    'lib/pages/chat/location_chat_panel_actions.dart',
    'lib/pages/chat/location_chat_layout.dart',
    'lib/pages/chat/location_chat_tick_progress.dart',
    'lib/pages/chat/location_chat_panel_widgets.dart',
    'lib/pages/chat/location_chat_shared.dart',
  ].map((path) => File(path).readAsStringSync()).join('\n');
}

bool _returnTrue() => true;

bool _returnFalse() => false;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GenesisMethodChannels.device, (call) async {
          return switch (call.method) {
            GenesisMethodChannels.getAppVersion => <String, Object>{
              'versionName': '0.3.4',
              'versionCode': '1',
              'packageName': 'com.worldo.test',
            },
            GenesisMethodChannels.getSystemUserAgent => 'Flutter test',
            GenesisMethodChannels.getTimeZone => 'UTC',
            _ => null,
          };
        });
  });

  tearDown(() {
    FirebaseAnalyticsMonitoring.resetForTesting();
    debugDefaultTargetPlatformOverride = null;
    resetAndroidSdkIntForTesting();
    locationChatBubbleLayoutSettings.resetForTesting();
    locationChatHeaderEffectSettings.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GenesisMethodChannels.device, null);
  });

  test('location chat uses the symmetric ordinary bubble cap when crowded', () {
    final caps = locationChatOrdinaryMessageBubbleMaxWidthCapsForMetrics(
      logicalWidth: 390,
      textScaler: TextScaler.noScaling,
      bubbleFontSize: 14,
      crowdedEffectiveWidthThreshold: LocationChatBubbleLayoutSettings
          .defaultCrowdedEffectiveWidthThreshold,
      avatarSize: 40,
      avatarBubbleGap: 10,
      avatarSideSpacerWidth: 40 / 3,
      messageListHorizontalPadding: 20,
    );

    expect(caps.isCrowded, isTrue);
    expect(caps.selfMessage, closeTo(306.667, 0.001));
    expect(caps.otherMessage, closeTo(306.667, 0.001));
  });

  test('location chat uses the symmetric ordinary bubble cap when roomy', () {
    final caps = locationChatOrdinaryMessageBubbleMaxWidthCapsForMetrics(
      logicalWidth: 430,
      textScaler: TextScaler.noScaling,
      bubbleFontSize: 14,
      crowdedEffectiveWidthThreshold: LocationChatBubbleLayoutSettings
          .defaultCrowdedEffectiveWidthThreshold,
      avatarSize: 40,
      avatarBubbleGap: 10,
      avatarSideSpacerWidth: 40 / 3,
      messageListHorizontalPadding: 20,
    );

    expect(caps.isCrowded, isFalse);
    expect(caps.selfMessage, 320);
    expect(caps.otherMessage, 320);
  });

  test('ordinary bubble cap responds to text scaling', () {
    final caps = locationChatOrdinaryMessageBubbleMaxWidthCapsForMetrics(
      logicalWidth: 430,
      textScaler: const TextScaler.linear(2),
      bubbleFontSize: 14,
      crowdedEffectiveWidthThreshold: LocationChatBubbleLayoutSettings
          .defaultCrowdedEffectiveWidthThreshold,
      avatarSize: 40,
      avatarBubbleGap: 10,
      avatarSideSpacerWidth: 40 / 3,
      messageListHorizontalPadding: 20,
    );

    expect(caps.isCrowded, isTrue);
    expect(caps.selfMessage, closeTo(346.667, 0.001));
    expect(caps.otherMessage, closeTo(346.667, 0.001));
  });

  test(
    'location chat metadata updates contain asynchronous failures',
    () async {
      final unhandledErrors = <Object>[];

      await runZonedGuarded<Future<void>>(() async {
        final completed = Completer<void>();
        unawaited(
          runLocationChatMetadataUpdateBestEffort(
            () async => throw StateError('storage unavailable'),
          ).whenComplete(completed.complete),
        );
        await completed.future;
      }, (error, _) => unhandledErrors.add(error));

      expect(unhandledErrors, isEmpty);
    },
  );

  test('location chat keeps programmatic positioning in its coordinator', () {
    final pageSource = File(
      'lib/pages/chat/location_chat_page.dart',
    ).readAsStringSync();
    final coordinatorSource = File(
      'lib/pages/chat/location_chat_scroll_coordinator.dart',
    ).readAsStringSync();

    expect(pageSource, contains('MediaQuery.devicePixelRatioOf(context)'));
    expect(
      pageSource,
      isNot(contains('MediaQuery.maybeOf(context)?.devicePixelRatio')),
    );
    expect(
      pageSource,
      contains(
        'class _LocationChatPanelState extends State<LocationChatPanel> {',
      ),
    );
    expect(pageSource, contains('class _LocationChatKeyboardInsetLayoutState'));
    expect(
      RegExp(r'void didChangeMetrics\(\)').allMatches(pageSource),
      hasLength(1),
    );
    expect(
      coordinatorSource,
      contains('class LocationChatBottomAnchoringScrollPhysics'),
    );
    expect(coordinatorSource, contains('return newPosition.maxScrollExtent;'));
    expect(coordinatorSource, contains('controller.jumpTo(target)'));
    expect(coordinatorSource, contains('controller.animateTo('));
    final implementationSource = _readLocationChatImplementationSource();
    expect(implementationSource, isNot(contains('.jumpTo(')));
    expect(implementationSource, isNot(contains('.animateTo(')));
    expect(
      RegExp(
        r'_scrollCoordinator\.enter\(\);',
      ).allMatches(implementationSource),
      hasLength(2),
    );
  });

  test('location chat image widgets subscribe only to DPR changes', () {
    for (final path in [
      'lib/ui/components/genesis_static_network_image.dart',
      'lib/ui/components/genesis_avatar.dart',
      'lib/ui/components/genesis_list_image.dart',
      'lib/components/chat/shared/chat_ui_media.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('MediaQuery.devicePixelRatioOf(context)'),
        reason: path,
      );
      expect(
        source,
        isNot(contains('MediaQuery.maybeOf(context)?.devicePixelRatio')),
        reason: path,
      );
    }
  });

  test('manual keyboard inset starts at Android 11', () {
    expect(
      locationChatManagesKeyboardInsetForTesting(
        platform: TargetPlatform.iOS,
        androidSdkInt: null,
      ),
      isTrue,
    );
    expect(
      locationChatManagesKeyboardInsetForTesting(
        platform: TargetPlatform.android,
        androidSdkInt: 29,
      ),
      isFalse,
    );
    expect(
      locationChatManagesKeyboardInsetForTesting(
        platform: TargetPlatform.android,
        androidSdkInt: 30,
      ),
      isTrue,
    );
  });

  test('keyboard inset excludes the stable bottom safe area', () {
    expect(
      locationChatEffectiveKeyboardInsetForTesting(
        rawKeyboardInset: 0,
        bottomSafeAreaInset: 34,
      ),
      0,
    );
    expect(
      locationChatEffectiveKeyboardInsetForTesting(
        rawKeyboardInset: 34,
        bottomSafeAreaInset: 34,
      ),
      0,
    );
    expect(
      locationChatEffectiveKeyboardInsetForTesting(
        rawKeyboardInset: 300,
        bottomSafeAreaInset: 34,
      ),
      266,
    );
  });

  test('minimum surface effects make header and composer transparent', () {
    final style = resolveLocationChatHeaderEffectStyle(
      baseStyle: kLocationChatStyle,
      settings: const LocationChatHeaderEffectSettings(
        transparencyStrength: 0,
        blurSigma: 0,
      ),
    );

    expect(style.headerBackgroundGradient, isNull);
    expect(style.headerBackgroundColor.a, 0);
    expect(style.headerBackdropBlurSigma, 0);
    expect(style.composerBackgroundGradient, isNull);
    expect(style.composerBackgroundColor.a, 0);
    expect(style.composerBackdropBlurSigma, 0);
  });

  testWidgets('Android 11 uses the manual keyboard inset layout', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GenesisMethodChannels.device, (call) async {
          if (call.method == GenesisMethodChannels.getAndroidSdkInt) return 30;
          return null;
        });
    expect(await loadAndroidSdkInt(), 30);
    debugDefaultTargetPlatformOverride = null;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final harness = await _connectedLocationChatTestService();

    await tester.pumpWidget(
      AppServicesScope(
        services: harness.services,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            service: harness.service,
            leaveOnInactive: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final textField = find.byType(TextField);
    final restingBottom = tester.getBottomRight(textField).dy;
    expect(scaffold.resizeToAvoidBottomInset, isFalse);
    expect(
      tester.widget<ChatComposer>(find.byType(ChatComposer)).hintText,
      'Text...',
    );
    expect(
      tester
          .widget<ChatHeader>(find.byType(ChatHeader))
          .style
          ?.headerBackdropBlurSigma,
      4,
    );
    final composerWidget = tester.widget<ChatComposer>(
      find.byType(ChatComposer),
    );
    final headerWidget = tester.widget<ChatHeader>(find.byType(ChatHeader));
    expect(headerWidget.backdropGroupKey, isNotNull);
    expect(
      composerWidget.backdropGroupKey,
      same(headerWidget.backdropGroupKey),
    );
    expect(composerWidget.style?.composerBackdropBlurSigma, 4);
    expect(composerWidget.style?.composerSendButtonBackdropBlurSigma, 14);
    expect(composerWidget.style?.composerSendButtonBorderRadius, 8);
    expect(composerWidget.style?.inputBackdropBlurSigma, 4);
    final messageViewport = find.byKey(
      const ValueKey<String>('location-chat-message-viewport-clip'),
    );
    expect(find.byType(BackdropGroup), findsOneWidget);
    expect(
      tester.widget<ClipRect>(messageViewport).clipBehavior,
      Clip.hardEdge,
    );
    expect(
      find.ancestor(of: messageViewport, matching: find.byType(Expanded)),
      findsOneWidget,
    );
    final messageViewportRect = tester.getRect(messageViewport);
    expect(
      messageViewportRect.top,
      closeTo(tester.getRect(find.byType(ChatHeader)).bottom, 0.1),
    );
    expect(
      messageViewportRect.bottom,
      closeTo(tester.getRect(find.byType(ChatComposer)).top, 0.1),
    );
    expect(
      tester
          .widget<LocationChatAnchoredMessageList>(
            find.byKey(const ValueKey<String>('location-chat-message-list')),
          )
          .style
          ?.messageListPadding,
      kLocationChatStyle.messageListPadding,
    );

    expect(tester.widget<ChatHeader>(find.byType(ChatHeader)).style, isNotNull);
    locationChatHeaderEffectSettings.previewTransparencyStrength(0);
    locationChatHeaderEffectSettings.previewBlurSigma(0);
    await tester.pump();
    final disabledHeaderStyle = tester
        .widget<ChatHeader>(find.byType(ChatHeader))
        .style!;
    expect(disabledHeaderStyle.headerBackgroundGradient, isNull);
    expect(disabledHeaderStyle.headerBackgroundColor.a, 0);
    expect(disabledHeaderStyle.headerBackdropBlurSigma, 0);
    final disabledComposerStyle = tester
        .widget<ChatComposer>(find.byType(ChatComposer))
        .style!;
    expect(disabledComposerStyle.composerBackgroundGradient, isNull);
    expect(disabledComposerStyle.composerBackgroundColor.a, 0);
    expect(disabledComposerStyle.composerBackdropBlurSigma, 0);
    expect(
      find.descendant(
        of: find.byType(ChatComposer),
        matching: find.byType(BackdropFilter),
      ),
      findsNWidgets(2),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(
      tester.getBottomRight(textField).dy,
      closeTo(restingBottom - 300, 0.1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(harness.service.dispose());
  });

  test('chat scroll physics keeps a bottom-aligned viewport anchored', () {
    const physics = LocationChatBottomAnchoringScrollPhysics(
      shouldFollowLatest: _returnTrue,
    );
    final oldPosition = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 500,
      pixels: 200,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    final newPosition = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 800,
      pixels: 500,
      viewportDimension: 300,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(
      physics.adjustPositionForNewDimensions(
        oldPosition: oldPosition,
        newPosition: newPosition,
        isScrolling: false,
        velocity: 0,
      ),
      newPosition.maxScrollExtent,
    );
  });

  test('chat scroll physics does not pin when auto follow is disabled', () {
    const physics = LocationChatBottomAnchoringScrollPhysics(
      shouldFollowLatest: _returnFalse,
    );
    final oldPosition = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 500,
      pixels: 500,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    final newPosition = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 800,
      pixels: 320,
      viewportDimension: 300,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(
      physics.adjustPositionForNewDimensions(
        oldPosition: oldPosition,
        newPosition: newPosition,
        isScrolling: false,
        velocity: 0,
      ),
      newPosition.pixels,
    );
  });

  test('chat scroll physics preserves a detached viewport on head prepend', () {
    const physics = LocationChatBottomAnchoringScrollPhysics(
      shouldFollowLatest: _returnFalse,
      shouldPreservePrependAnchor: _returnTrue,
    );
    final oldPosition = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 500,
      pixels: 180,
      viewportDimension: 300,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    final newPosition = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 760,
      pixels: 180,
      viewportDimension: 300,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(
      physics.adjustPositionForNewDimensions(
        oldPosition: oldPosition,
        newPosition: newPosition,
        isScrolling: false,
        velocity: 0,
      ),
      440,
    );
  });

  test('older history waits until upward scrolling is idle', () {
    expect(
      locationChatShouldLoadOlderMessagesForTesting(
        active: true,
        isLeafLocation: true,
        loading: false,
        hasMore: true,
        detached: true,
        extentBefore: 120,
        isScrolling: true,
      ),
      isFalse,
    );
    expect(
      locationChatShouldLoadOlderMessagesForTesting(
        active: true,
        isLeafLocation: true,
        loading: false,
        hasMore: true,
        detached: true,
        extentBefore: 120,
        isScrolling: false,
      ),
      isTrue,
    );
  });

  test('AI disclaimer only enters the list after history is resolved', () {
    expect(
      locationChatShouldShowAiContentDisclaimerForTesting(
        initialContentReady: false,
        hasMoreOlderMessages: false,
        loadingOlderMessages: false,
      ),
      isFalse,
    );
    expect(
      locationChatShouldShowAiContentDisclaimerForTesting(
        initialContentReady: true,
        hasMoreOlderMessages: true,
        loadingOlderMessages: false,
      ),
      isFalse,
    );
    expect(
      locationChatShouldShowAiContentDisclaimerForTesting(
        initialContentReady: true,
        hasMoreOlderMessages: false,
        loadingOlderMessages: true,
      ),
      isFalse,
    );
    expect(
      locationChatShouldShowAiContentDisclaimerForTesting(
        initialContentReady: true,
        hasMoreOlderMessages: false,
        loadingOlderMessages: false,
      ),
      isTrue,
    );
  });

  testWidgets('streaming messages preserve an unfocused detached viewport', (
    tester,
  ) async {
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('user-1');
    await sessionStore.saveAuthToken('token-1');
    final services = ServiceRegistry.build(
      config: const AppConfig(useMock: true),
      sessionStoreOverride: sessionStore,
      chatroomMessagesOverride: MemoryChatroomMessageStorage(),
    );
    final socket = _LocationChatTestSocket();
    final client = ChatroomClient(
      wsBaseUrl: 'ws://localhost:8082/aitown-chat/ws',
      sessionStore: sessionStore,
      transport: _LocationChatTestTransport(socket),
      autoHeartbeat: false,
    );
    final service = WorldChatroomService(
      api: services.api,
      client: client,
      messageStorage: MemoryChatroomMessageStorage(),
      refreshInitialSnapshotOnConnect: false,
    );
    await service.connect(
      worldId: 'world-current',
      identity: const ChatroomConnectionIdentity(
        userId: 'user-1',
        senderId: 'user-1',
        senderName: 'Player One',
      ),
    );
    for (var id = 1; id <= 20; id += 1) {
      socket.serverUserMessage(messageId: id);
    }
    await _pumpUntilLocationChatTest(
      tester,
      () => service.state.messagesByLocation['location-current']?.length == 20,
    );

    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            service: service,
            leaveOnInactive: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isFalse,
    );

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('location-chat-message-list')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent - 300);
    await tester.pump();
    await tester.drag(scrollable, const Offset(0, 40));
    await tester.pump();
    expect(
      tester
          .widget<LocationChatAnchoredMessageList>(
            find.byKey(const ValueKey('location-chat-message-list')),
          )
          .coordinator
          .mode,
      LocationChatViewportMode.detached,
    );
    final viewportCoordinator = tester
        .widget<LocationChatAnchoredMessageList>(
          find.byKey(const ValueKey('location-chat-message-list')),
        )
        .coordinator;
    expect(viewportCoordinator.mode, LocationChatViewportMode.detached);
    expect(
      position.maxScrollExtent - position.pixels,
      greaterThan(LocationChatScrollCoordinator.bottomTolerance),
    );
    final pixelsBefore = position.pixels;
    final localIdsBeforeStream = tester
        .widget<LocationChatAnchoredMessageList>(
          find.byKey(const ValueKey('location-chat-message-list')),
        )
        .messages
        .map((message) => message.localId)
        .toList(growable: false);
    final observedOffsets = <double>[];
    void recordOffset() => observedOffsets.add(position.pixels);
    position.addListener(recordOffset);

    socket.serverLlmStreamStart(messageId: 21);
    await _pumpUntilLocationChatTest(
      tester,
      () =>
          service
              .state
              .streamMessagesByKey['world-current|location-current|21|char-1'] !=
          null,
    );
    expect(viewportCoordinator.mode, LocationChatViewportMode.detached);
    final localIdsAfterStreamStart = tester
        .widget<LocationChatAnchoredMessageList>(
          find.byKey(const ValueKey('location-chat-message-list')),
        )
        .messages
        .map((message) => message.localId)
        .toList(growable: false);
    expect(
      localIdsAfterStreamStart.take(localIdsBeforeStream.length),
      localIdsBeforeStream,
    );
    socket.serverLlmChunk(messageId: 21, content: 'streaming');
    await _pumpUntilLocationChatTest(
      tester,
      () =>
          service
              .state
              .streamMessagesByKey['world-current|location-current|21|char-1']
              ?.content ==
          'streaming',
    );
    expect(viewportCoordinator.mode, LocationChatViewportMode.detached);
    await tester.pump();
    position.removeListener(recordOffset);

    expect(position.pixels, closeTo(pixelsBefore, 0.1));
    expect(
      observedOffsets,
      everyElement(inInclusiveRange(pixelsBefore - 0.1, pixelsBefore + 0.1)),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(service.dispose());
  });

  testWidgets(
    'composer focus follows latest before keyboard resize then streaming stays detached after user drag',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('user-1');
      await sessionStore.saveAuthToken('token-1');
      final services = ServiceRegistry.build(
        config: const AppConfig(useMock: true),
        sessionStoreOverride: sessionStore,
        chatroomMessagesOverride: MemoryChatroomMessageStorage(),
      );
      final socket = _LocationChatTestSocket();
      final client = ChatroomClient(
        wsBaseUrl: 'ws://localhost:8082/aitown-chat/ws',
        sessionStore: sessionStore,
        transport: _LocationChatTestTransport(socket),
        autoHeartbeat: false,
      );
      final service = WorldChatroomService(
        api: services.api,
        client: client,
        messageStorage: MemoryChatroomMessageStorage(),
        replyActionStorage: MemoryChatroomReplyActionStorage(),
        inspirationStorage: MemoryChatroomInspirationStorage(),
        refreshInitialSnapshotOnConnect: false,
      );
      await service.connect(
        worldId: 'world-current',
        identity: const ChatroomConnectionIdentity(
          userId: 'user-1',
          senderId: 'user-1',
          senderName: 'Player One',
        ),
      );
      // Complete join history before seeding the live-message viewport.
      await service.join(locationId: 'location-current');
      await service.refreshLocationHistory(locationId: 'location-current');
      for (var id = 1; id <= 20; id += 1) {
        socket.serverUserMessage(messageId: id);
      }
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service.state.messagesByLocation['location-current']?.length == 20,
      );

      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(
            home: LocationChatPanel(
              worldId: 'world-current',
              locationId: 'location-current',
              service: service,
              leaveOnInactive: false,
              messageQueueInitializationCovered: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final textField = find.byType(TextField);
      expect(tester.widget<TextField>(textField).focusNode?.hasFocus, isFalse);
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('location-chat-message-list')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent - 300);
      await tester.pump();
      await tester.drag(scrollable, const Offset(0, 40));
      await tester.pump();

      final viewportCoordinator = tester
          .widget<LocationChatAnchoredMessageList>(
            find.byKey(const ValueKey('location-chat-message-list')),
          )
          .coordinator;
      expect(viewportCoordinator.mode, LocationChatViewportMode.detached);
      expect(
        position.maxScrollExtent - position.pixels,
        greaterThan(LocationChatScrollCoordinator.bottomTolerance),
      );

      await tester.tap(textField);
      await tester.pump();
      await tester.pump();

      expect(
        viewportCoordinator.mode,
        LocationChatViewportMode.followingLatest,
      );
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump();

      expect(
        viewportCoordinator.mode,
        LocationChatViewportMode.followingLatest,
      );
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));

      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pump();
      tester.view.resetViewInsets();
      await tester.pump();
      expect(viewportCoordinator.mode, LocationChatViewportMode.detached);
      expect(
        position.maxScrollExtent - position.pixels,
        greaterThan(LocationChatScrollCoordinator.bottomTolerance),
      );
      final pixelsBeforeStream = position.pixels;
      final observedOffsets = <double>[];
      void recordOffset() => observedOffsets.add(position.pixels);
      position.addListener(recordOffset);

      socket.serverUserMessage(messageId: 21);
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service.state.messagesByLocation['location-current']?.length == 21,
      );
      expect(viewportCoordinator.mode, LocationChatViewportMode.detached);
      expect(position.pixels, closeTo(pixelsBeforeStream, 0.1));

      socket.serverLlmStreamStart(messageId: 22);
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service
                .state
                .streamMessagesByKey['world-current|location-current|22|char-1'] !=
            null,
      );
      socket.serverLlmChunk(messageId: 22, content: 'focused streaming');
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service
                .state
                .streamMessagesByKey['world-current|location-current|22|char-1']
                ?.content ==
            'focused streaming',
      );
      await tester.pump();
      position.removeListener(recordOffset);

      expect(viewportCoordinator.mode, LocationChatViewportMode.detached);
      expect(position.pixels, closeTo(pixelsBeforeStream, 0.1));
      expect(
        observedOffsets,
        everyElement(
          inInclusiveRange(pixelsBeforeStream - 0.1, pixelsBeforeStream + 0.1),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(service.dispose());
    },
  );

  testWidgets(
    'consecutive canonical V2 ticks share one unread bubble count while detached',
    (tester) async {
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('user-1');
      await sessionStore.saveAuthToken('token-1');
      final services = ServiceRegistry.build(
        config: const AppConfig(useMock: true),
        sessionStoreOverride: sessionStore,
        chatroomMessagesOverride: MemoryChatroomMessageStorage(),
      );
      final socket = _LocationChatTestSocket();
      final client = ChatroomClient(
        wsBaseUrl: 'ws://localhost:8082/aitown-chat/ws',
        sessionStore: sessionStore,
        transport: _LocationChatTestTransport(socket),
        autoHeartbeat: false,
        handshakeHeaderSigner: (_, headers) async => <String, String>{
          ...headers,
          'X-App-Version': '0.3.4',
        },
      );
      final service = WorldChatroomService(
        api: services.api,
        client: client,
        messageStorage: MemoryChatroomMessageStorage(),
        replyActionStorage: MemoryChatroomReplyActionStorage(),
        inspirationStorage: MemoryChatroomInspirationStorage(),
        refreshInitialSnapshotOnConnect: false,
      );
      await service.connect(
        worldId: 'world-current',
        identity: const ChatroomConnectionIdentity(
          userId: 'user-1',
          senderId: 'user-1',
          senderName: 'Player One',
        ),
      );
      // Complete join history before seeding the live-message viewport.
      await service.join(locationId: 'location-current');
      await service.refreshLocationHistory(locationId: 'location-current');
      for (var id = 1; id <= 20; id += 1) {
        socket.serverV2UserMessage(messageId: id);
      }
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service.state.messagesByLocation['location-current']?.length == 20,
      );

      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(
            home: LocationChatPanel(
              worldId: 'world-current',
              locationId: 'location-current',
              service: service,
              leaveOnInactive: false,
              messageQueueInitializationCovered: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('location-chat-message-list')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent - 300);
      await tester.pump();
      await tester.drag(scrollable, const Offset(0, 40));
      await tester.pump();
      final viewportCoordinator = tester
          .widget<LocationChatAnchoredMessageList>(
            find.byKey(const ValueKey('location-chat-message-list')),
          )
          .coordinator;
      expect(viewportCoordinator.mode, LocationChatViewportMode.detached);
      final pixelsBeforeTick = position.pixels;

      socket.serverV2Tick(
        messageId: 21,
        locationMessageId: 21,
        globalText: 'Detached canonical tick',
      );
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service.state.messagesByLocation['location-current']?.any(
              (message) =>
                  message.locationMessageId == 21 && message.isV2LocationTick,
            ) ==
            true,
      );
      await tester.pump();

      expect(position.pixels, closeTo(pixelsBeforeTick, 0.1));
      expect(find.text('Detached canonical tick'), findsNothing);
      expect(
        tester
            .widget<LocationChatAnchoredMessageList>(
              find.byKey(const ValueKey('location-chat-message-list')),
            )
            .messages
            .where((message) => message.isTick)
            .single
            .text,
        'Detached canonical tick',
      );
      expect(find.text('1 new message'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('location-chat-new-message-notice')),
        findsOneWidget,
      );

      socket.serverV2Tick(
        messageId: 22,
        locationMessageId: 22,
        globalText: 'Latest detached canonical tick',
      );
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service.state.messagesByLocation['location-current']?.any(
              (message) =>
                  message.locationMessageId == 22 && message.isV2LocationTick,
            ) ==
            true,
      );
      await tester.pump();

      expect(position.pixels, closeTo(pixelsBeforeTick, 0.1));
      expect(find.text('Detached canonical tick'), findsNothing);
      expect(find.text('Latest detached canonical tick'), findsNothing);
      expect(
        tester
            .widget<LocationChatAnchoredMessageList>(
              find.byKey(const ValueKey('location-chat-message-list')),
            )
            .messages
            .where((message) => message.isTick),
        hasLength(1),
      );
      expect(
        tester
            .widget<LocationChatAnchoredMessageList>(
              find.byKey(const ValueKey('location-chat-message-list')),
            )
            .messages
            .where((message) => message.isTick)
            .single
            .text,
        'Latest detached canonical tick',
      );
      expect(find.text('1 new message'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('location-chat-new-message-notice')),
      );
      await tester.pump();
      await tester.pump();

      expect(
        viewportCoordinator.mode,
        LocationChatViewportMode.followingLatest,
      );
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
      expect(find.text('1 new message'), findsNothing);

      socket.serverV2Tick(
        messageId: 23,
        locationMessageId: 23,
        globalText: 'Bottom canonical tick',
      );
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service.state.messagesByLocation['location-current']?.any(
              (message) =>
                  message.locationMessageId == 23 && message.isV2LocationTick,
            ) ==
            true,
      );
      await tester.pump();

      expect(find.text('Bottom canonical tick'), findsOneWidget);
      expect(
        viewportCoordinator.mode,
        LocationChatViewportMode.followingLatest,
      );
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
      expect(find.text('1 new message'), findsNothing);
      expect(
        find.byKey(const ValueKey('location-chat-new-message-notice')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(service.dispose());
    },
  );

  testWidgets(
    'tick progress stays in the list until the canonical tick replaces its slot',
    (tester) async {
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('user-1');
      await sessionStore.saveAuthToken('token-1');
      final services = ServiceRegistry.build(
        config: const AppConfig(useMock: true),
        sessionStoreOverride: sessionStore,
        chatroomMessagesOverride: MemoryChatroomMessageStorage(),
      );
      final socket = _LocationChatTestSocket();
      final client = ChatroomClient(
        wsBaseUrl: 'ws://localhost:8082/aitown-chat/ws',
        sessionStore: sessionStore,
        transport: _LocationChatTestTransport(socket),
        autoHeartbeat: false,
        handshakeHeaderSigner: (_, headers) async => <String, String>{
          ...headers,
          'X-App-Version': '0.3.4',
        },
      );
      final service = WorldChatroomService(
        api: services.api,
        client: client,
        messageStorage: MemoryChatroomMessageStorage(),
        refreshInitialSnapshotOnConnect: false,
      );
      await service.connect(
        worldId: 'world-current',
        identity: const ChatroomConnectionIdentity(
          userId: 'user-1',
          senderId: 'user-1',
          senderName: 'Player One',
        ),
      );

      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(
            home: LocationChatPanel(
              worldId: 'world-current',
              locationId: 'location-current',
              service: service,
              leaveOnInactive: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      service.setInputBlocked(true);
      await _pumpUntilLocationChatTest(
        tester,
        () => find
            .byKey(const ValueKey<String>('chat-tick-progress-content'))
            .evaluate()
            .isNotEmpty,
      );

      final progressTitle = find.textContaining('Progressing the World');
      expect(progressTitle, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('chat-tick-progress-content')),
        findsOneWidget,
      );
      final progressList = tester.widget<LocationChatAnchoredMessageList>(
        find.byKey(const ValueKey<String>('location-chat-message-list')),
      );
      final progressSlotId = progressList.messages.last.localId;
      expect(progressSlotId, contains('location-chat-tick-progress'));

      service.setInputBlocked(false);
      await tester.pump();
      expect(progressTitle, findsOneWidget);

      socket.serverV2Tick(
        messageId: 1,
        locationMessageId: 1,
        globalText: 'The completed tick replaces progress.',
      );
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service.state.messagesByLocation['location-current']?.any(
              (message) => message.locationMessageId == 1,
            ) ==
            true,
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(progressTitle, findsNothing);
      expect(
        find.text('The completed tick replaces progress.'),
        findsOneWidget,
      );
      final completedList = tester.widget<LocationChatAnchoredMessageList>(
        find.byKey(const ValueKey<String>('location-chat-message-list')),
      );
      final completedTick = completedList.messages.last;
      expect(completedTick.isTick, isTrue);
      expect(completedList.messageLayoutId!(completedTick), progressSlotId);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(service.dispose());
    },
  );

  testWidgets(
    'world progress already running is shown when location chat opens',
    (WidgetTester tester) async {
      final harness = await _connectedLocationChatTestService();
      final services = harness.services;
      final service = harness.service;

      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(
            home: LocationChatPanel(
              worldId: 'world-current',
              locationId: 'location-current',
              service: service,
              worldTickInProgress: true,
              leaveOnInactive: false,
            ),
          ),
        ),
      );
      await _pumpUntilLocationChatTest(
        tester,
        () => find
            .byKey(const ValueKey<String>('chat-tick-progress-content'))
            .evaluate()
            .isNotEmpty,
      );

      expect(service.state.inputBlocked, isFalse);
      expect(
        find.byKey(const ValueKey<String>('chat-tick-progress-content')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(service.dispose());
    },
  );

  testWidgets(
    'historical ticks hydrated after opening do not dismiss world progress',
    (WidgetTester tester) async {
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('user-1');
      await sessionStore.saveAuthToken('token-1');
      final storage = MemoryChatroomMessageStorage();
      await storage.upsertMessage(
        ownerUid: 'user-1',
        worldId: 'world-current',
        locationId: 'location-current',
        message: <String, dynamic>{
          'global_message_id': 90001,
          'message_id': 1,
          'location_message_id': 1,
          'location_id': 'location-current',
          'conversation_round_id': 1,
          'sender_type': 'tick',
          'type': 'tick',
          'sender_id': 'tick',
          'sender_name': 'Time',
          'content': '',
          'payload': <String, dynamic>{
            'current_time': 'Day 1, 08:00',
            'tick_no': 1,
            'sub_tick_no': 0,
            'global': 'A completed historical tick.',
            'story_events': <Object?>[],
            'characters_moved': <Object?>[],
          },
          'created_at': '2026-08-01 08:00:00',
        },
      );
      final services = ServiceRegistry.build(
        config: const AppConfig(useMock: true),
        sessionStoreOverride: sessionStore,
        chatroomMessagesOverride: storage,
      );
      final service = WorldChatroomService(
        api: services.api,
        client: services.chatroom,
        messageStorage: storage,
        refreshInitialSnapshotOnConnect: false,
      );

      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(
            home: LocationChatPanel(
              worldId: 'world-current',
              locationId: 'location-current',
              service: service,
              worldTickInProgress: true,
              leaveOnInactive: false,
            ),
          ),
        ),
      );
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            service.state.messagesByLocation['location-current']?.isNotEmpty ==
            true,
      );
      await tester.pump();

      expect(find.text('A completed historical tick.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('chat-tick-progress-content')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(service.dispose());
    },
  );

  testWidgets('failed world progress removes the temporary tick card', (
    WidgetTester tester,
  ) async {
    final harness = await _connectedLocationChatTestService();
    final services = harness.services;
    final service = harness.service;

    Widget panel({required bool progressing, required int failureRevision}) {
      return AppServicesScope(
        services: services,
        child: MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            service: service,
            worldTickInProgress: progressing,
            worldTickProgressFailureRevision: failureRevision,
            leaveOnInactive: false,
          ),
        ),
      );
    }

    await tester.pumpWidget(panel(progressing: true, failureRevision: 0));
    await _pumpUntilLocationChatTest(
      tester,
      () => find
          .byKey(const ValueKey<String>('chat-tick-progress-content'))
          .evaluate()
          .isNotEmpty,
    );

    await tester.pumpWidget(panel(progressing: false, failureRevision: 1));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('chat-tick-progress-content')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(service.dispose());
  });

  testWidgets(
    'reactivating a cached location does not flash stale tick progress',
    (WidgetTester tester) async {
      final harness = await _connectedLocationChatTestService();
      final services = harness.services;
      final service = harness.service;

      Widget panel({required bool active, required bool progressing}) {
        return AppServicesScope(
          services: services,
          child: MaterialApp(
            home: LocationChatPanel(
              key: const ValueKey<String>('cached-location-panel'),
              worldId: 'world-current',
              locationId: 'location-current',
              service: service,
              active: active,
              worldTickInProgress: progressing,
              leaveOnInactive: false,
            ),
          ),
        );
      }

      await tester.pumpWidget(panel(active: true, progressing: true));
      await _pumpUntilLocationChatTest(
        tester,
        () => find
            .byKey(const ValueKey<String>('chat-tick-progress-content'))
            .evaluate()
            .isNotEmpty,
      );

      await tester.pumpWidget(panel(active: false, progressing: true));
      await tester.pump();
      await tester.pumpWidget(panel(active: false, progressing: false));
      await tester.pump();
      await tester.pumpWidget(panel(active: true, progressing: false));

      expect(
        find.byKey(const ValueKey<String>('chat-tick-progress-content')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(service.dispose());
    },
  );

  test('location chat panel hides the inactive more button by default', () {
    const panel = LocationChatPanel(worldId: 'world-1', locationId: 'loc-1');

    expect(panel.showMoreButton, isFalse);
    expect(panel.unauthorizedHandledByOwner, isFalse);
  });

  testWidgets(
    'location chat follows iOS keyboard inset and keeps unknown Android automatic',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final harness = await _connectedLocationChatTestService();

      Widget panel(TargetPlatform platform) => AppServicesScope(
        services: harness.services,
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            service: harness.service,
            leaveOnInactive: false,
          ),
        ),
      );

      await tester.pumpWidget(panel(TargetPlatform.iOS));
      await tester.pump();

      Scaffold scaffold() => tester.widget<Scaffold>(find.byType(Scaffold));
      final keyboardInset = find.byKey(
        const ValueKey<String>('location-chat-ios-keyboard-inset'),
      );
      final textField = find.byType(TextField);

      expect(scaffold().resizeToAvoidBottomInset, isFalse);
      expect(
        find.descendant(
          of: keyboardInset,
          matching: find.byType(AnimatedPadding),
        ),
        findsNothing,
      );
      final restingBottom = tester.getBottomRight(textField).dy;
      final restingMessageListSize = tester.getSize(
        find.byType(LocationChatAnchoredMessageList),
      );

      for (final inset in [100.0, 200.0, 300.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        expect(
          tester.getBottomRight(textField).dy,
          closeTo(restingBottom - inset, 0.1),
        );
        expect(
          tester.getSize(find.byType(LocationChatAnchoredMessageList)).height,
          closeTo(restingMessageListSize.height - inset, 0.1),
        );
      }

      tester.view.resetViewInsets();
      await tester.pump();
      expect(tester.getBottomRight(textField).dy, closeTo(restingBottom, 0.1));
      expect(
        tester.getSize(find.byType(LocationChatAnchoredMessageList)),
        restingMessageListSize,
      );

      await tester.pumpWidget(panel(TargetPlatform.android));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scaffold().resizeToAvoidBottomInset, isFalse);

      tester.widget<TextField>(textField).focusNode?.requestFocus();
      await tester.pump();
      expect(scaffold().resizeToAvoidBottomInset, isTrue);

      tester.widget<TextField>(textField).focusNode?.unfocus();
      await tester.pump();
      expect(scaffold().resizeToAvoidBottomInset, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(harness.service.dispose());
    },
  );

  testWidgets(
    'location chat composer follows keyboard frames with a bottom safe area',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetViewPadding);
      final harness = await _connectedLocationChatTestService();

      await tester.pumpWidget(
        AppServicesScope(
          services: harness.services,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: LocationChatPanel(
              worldId: 'world-current',
              locationId: 'location-current',
              service: harness.service,
              leaveOnInactive: false,
            ),
          ),
        ),
      );
      await tester.pump();

      final textField = find.byType(TextField);
      final messageList = find.byType(LocationChatAnchoredMessageList);
      final restingBottom = tester.getBottomRight(textField).dy;
      final restingMessageListSize = tester.getSize(messageList);

      for (final rawInset in [20.0, 34.0, 100.0, 220.0, 300.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: rawInset);
        await tester.pump();
        final effectiveInset = math.max(0.0, rawInset - 34);
        expect(
          tester.getBottomRight(textField).dy,
          closeTo(restingBottom - effectiveInset, 0.1),
        );
        expect(
          tester.getSize(messageList).height,
          closeTo(restingMessageListSize.height - effectiveInset, 0.1),
        );
      }

      for (final rawInset in [220.0, 100.0, 34.0, 20.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: rawInset);
        await tester.pump();
        final effectiveInset = math.max(0.0, rawInset - 34);
        expect(
          tester.getBottomRight(textField).dy,
          closeTo(restingBottom - effectiveInset, 0.1),
        );
        expect(
          tester.getSize(messageList).height,
          closeTo(restingMessageListSize.height - effectiveInset, 0.1),
        );
      }
      expect(tester.getSize(messageList), restingMessageListSize);

      // A stale opening commit must not run after a quick reversal.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tester.getBottomRight(textField).dy, closeTo(restingBottom, 0.1));
      expect(tester.getSize(messageList), restingMessageListSize);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(harness.service.dispose());
    },
  );

  test('selected model code reads the user info sibling field', () {
    expect(
      selectedModelCodeFromUserInfo({
        'selected_model_code': 'cc_4_5',
        'user': {'selected_model_code': 'legacy_model'},
      }),
      'cc_4_5',
    );
  });

  test('selected model title reads the title cached for its code', () {
    expect(
      selectedModelTitleFromUserInfo({
        'selected_model_titles': {'sedna': 'Sedna'},
      }, 'sedna'),
      'Sedna',
    );
  });

  testWidgets('location chat darkens the top and bottom of its background', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationChatPanel(
          worldId: 'background-world',
          locationId: 'background-location',
          active: false,
          renderBackgroundImage: false,
        ),
      ),
    );

    final overlay = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('location-chat-background-overlay')),
    );
    final decoration = overlay.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.stops, const <double>[0, 0.32, 0.64, 1]);
    expect(gradient.colors, const <Color>[
      Color(0xCC131215),
      Color(0x80131215),
      Color(0x80131215),
      Color(0xCC131215),
    ]);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('location-chat-background')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == const Color(0xFF151517),
        ),
      ),
      findsOneWidget,
    );
  });

  test('LLM stream and returned user UGC use their own display decoders', () {
    expect(
      locationChatMessageDisplayTextForTesting(
        _message(
          messageId: 1,
          locationMessageId: 1,
          content: r'Line\nTwo',
          isLlmStreamMessage: true,
        ),
      ),
      'Line\nTwo',
    );
    expect(
      locationChatMessageDisplayTextForTesting(
        _message(messageId: 2, locationMessageId: 2, content: r'Line\nTwo'),
      ),
      r'Line\nTwo',
    );
    expect(
      locationChatMessageDisplayTextForTesting(
        _message(messageId: 3, locationMessageId: 3, content: r'Line\\nTwo'),
      ),
      r'Line\\nTwo',
    );
    expect(
      locationChatMessageDisplayTextForTesting(
        _message(messageId: 4, locationMessageId: 4, content: 'Line\nTwo'),
      ),
      'Line\nTwo',
    );
  });

  test('selected model code accepts a nested compatibility fallback', () {
    expect(
      selectedModelCodeFromUserInfo({
        'user': {'selected_model_code': 'legacy_model'},
      }),
      'legacy_model',
    );
  });

  test('selected model code is empty when cache has no model field', () {
    expect(selectedModelCodeFromUserInfo({'uid': 'u_1'}), isEmpty);
  });

  testWidgets(
    'reply Edit persists through HTTP and refreshes canonical history from a nested navigator',
    (tester) async {
      final backend = _LocationChatReplyHttpTransport();
      final harness = await _connectedLocationChatTestService(
        replyTransport: backend,
      );
      await tester.pumpWidget(
        AppServicesScope(
          services: harness.services,
          child: MaterialApp(
            scrollBehavior: const GenesisScrollBehavior(),
            onGenerateRoute: AppRouter.onGenerateRoute,
            home: Navigator(
              requestFocus: false,
              pages: [
                MaterialPage<void>(
                  child: LocationChatPanel(
                    worldId: 'world-current',
                    locationId: 'location-current',
                    service: harness.service,
                    leaveOnInactive: false,
                    messageQueueInitializationCovered: true,
                  ),
                ),
              ],
              onDidRemovePage: (_) {},
            ),
          ),
        ),
      );
      await _pumpUntilLocationChatTest(
        tester,
        () => harness.service.state.joinedLocationId == 'location-current',
      );
      backend.seedReplyRound();
      harness.socket.serverV2UserMessage(messageId: 301);
      harness.socket.serverV2StreamFrame(
        streamType: 'llm_stream_end',
        roundId: 301,
        messageId: 302,
        content: 'Original reply.',
      );
      harness.socket.serverEndConversationRound(roundId: 301);
      await _pumpUntilLocationChatTest(
        tester,
        () => tester
            .widget<LocationChatAnchoredMessageList>(
              find.byType(LocationChatAnchoredMessageList),
            )
            .editEnabled,
      );
      await tester.pumpAndSettle();
      final originalHeaderHeight = tester
          .getSize(find.byType(ChatHeader))
          .height;
      await tester.tap(find.bySemanticsLabel('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(LocationChatEditPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('edit-subscription-prompt')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('edit-subscription-prompt'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(ChatHeader)).height,
        originalHeaderHeight,
      );
      expect(find.byType(ChatComposer), findsNothing);
      await tester.enterText(find.byType(TextField), 'Saved server reply.');
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.pumpAndSettle();
      expect(find.byType(LocationChatEditPage), findsNothing);
      expect(
        find.byKey(const ValueKey('edit-subscription-prompt')),
        findsNothing,
      );
      var list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(
        list.messages.any((message) => message.text == 'Saved server reply.'),
        isTrue,
      );
      expect(
        harness
            .service
            .state
            .messagesByLocation['location-current']!
            .last
            .content,
        'Saved server reply.',
      );
      expect(backend.batches, [
        {
          'conversation_round_id': 301,
          'operations': [
            {
              'action': 'edit',
              'global_message_id': 90302,
              'content': 'Saved server reply.',
            },
          ],
        },
      ]);
      expect(backend.rangeRequests, isNotEmpty);
      expect(
        backend.rangeRequests.every(
          (query) =>
              query['start_conversation_round_id'] == '301' &&
              query['end_conversation_round_id'] == '301',
        ),
        isTrue,
      );
      tester.widget<ChatComposer>(find.byType(ChatComposer)).controller.text =
          'Draft';
      await tester.pump();
      list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(
        list.messages.any((message) => message.text == 'Saved server reply.'),
        isTrue,
      );
      await tester.tap(find.bySemanticsLabel('Edit'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Saved server reply.',
      );
      await tester.enterText(find.byType(TextField), 'Discarded change');
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(
        list.messages.any((message) => message.text == 'Saved server reply.'),
        isTrue,
      );
      expect(
        backend.batches,
        hasLength(1),
        reason: 'Cancel does not issue a batch.',
      );
      await tester.tap(find.bySemanticsLabel('Edit'));
      await tester.pumpAndSettle();
      final messageId = list.messages
          .firstWhere((message) => message.text == 'Saved server reply.')
          .localId;
      final editorMessageId = tester
          .widget<ChatMessageRow>(find.byType(ChatMessageRow))
          .message
          .localId;
      await tester.tap(
        find.byKey(ValueKey('location-chat-edit-delete-$editorMessageId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('location-chat-edit-done')));
      await tester.pumpAndSettle();
      list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(
        list.messages.any((message) => message.localId == messageId),
        isFalse,
      );
      expect(
        harness.service.state.messagesByLocation['location-current']!.any(
          (message) => message.globalMessageId == 90302,
        ),
        isFalse,
      );
      expect(backend.batches.last, {
        'conversation_round_id': 301,
        'operations': [
          {'action': 'delete', 'global_message_id': 90302},
        ],
      });
      expect(backend.batches, hasLength(2));
      expect(
        list.messages.any((message) => message.isMe),
        isTrue,
        reason: 'The user message remains outside the edited AI block.',
      );
      expect(harness.socket.sendMessageCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(harness.service.dispose());
    },
  );

  for (final action in [
    ('Regenerate', 'regenerate_llm_card'),
    ('Go on', 'go_on'),
  ]) {
    testWidgets(
      '${action.$1} rejected ACK displays only centered server err_msg',
      (tester) async {
        final harness = await _mountCompletedReplyActionPanel(
          tester,
          backend: _LocationChatReplyHttpTransport(),
        );
        await tester.tap(find.bySemanticsLabel(action.$1));
        await _pumpUntilLocationChatTest(
          tester,
          () => harness.socket.replyActionFrames(action.$2).length == 1,
        );
        harness.socket.serverReplyActionAck(
          action.$2,
          roundId: 301,
          errNo: 2010,
          errMsg: '服务端频率限制提示',
        );
        await _pumpUntilLocationChatTest(
          tester,
          () => find.text('服务端频率限制提示').evaluate().isNotEmpty,
        );
        await tester.pump();
        expect(find.text('服务端频率限制提示'), findsOneWidget);
        expect(find.textContaining('ChatroomFailureEvent'), findsNothing);
        expect(
          find.text(
            'Too little time between posts. Ease up and try again shortly.',
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('location-chat-loading-bubble')),
          findsNothing,
        );
        final messages = tester
            .widget<LocationChatAnchoredMessageList>(
              find.byType(LocationChatAnchoredMessageList),
            )
            .messages;
        expect(messages.any((m) => m.text == 'Original reply.'), isTrue);
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('服务端频率限制提示'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        unawaited(harness.service.dispose());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'Regenerate button requests and displays a private candidate without replacing the user message',
    (tester) async {
      final backend = _LocationChatReplyHttpTransport();
      final harness = await _mountCompletedReplyActionPanel(
        tester,
        backend: backend,
      );
      await tester.tap(find.bySemanticsLabel('Regenerate'));
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            harness.socket.replyActionFrames('regenerate_llm_card').length == 1,
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('location-chat-loading-bubble')),
        findsOneWidget,
      );
      expect(find.text('Generating…'), findsNothing);
      expect(find.text('Waiting for the next reply…'), findsNothing);
      expect(find.text('Check status'), findsNothing);
      final request = harness.socket
          .replyActionFrames('regenerate_llm_card')
          .single;
      expect(request['world_id'], 'world-current');
      expect(request['conversation_round_id'], 301);
      expect(request['payload'], {'location_id': 'location-current'});
      expect(request['client_msg_id'], isNotEmpty);
      final canonicalBefore =
          harness.service.state.messagesByLocation['location-current']!;
      expect(canonicalBefore.map((message) => message.content), [
        'message 301',
        'Original reply.',
      ]);

      backend.beginCandidate();
      harness.socket.serverReplyActionAck(
        'regenerate_llm_card',
        roundId: 301,
        payload: {
          'regeneration': {
            'conversation_round_id': 301,
            'original_card_id': 501,
            'card_id': 502,
            'generation_state': 'generating',
            'billing': {'status': 'reserved'},
          },
        },
      );
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            harness.service.replyActions!
                .stateFor('location-current')!
                .viewedCardId ==
            502,
      );
      harness.socket.serverCandidateStream(streamType: 'start');
      harness.socket.serverCandidateStream(
        streamType: 'chunk',
        content: 'Private candidate.',
        seq: 1,
      );
      await _pumpUntilLocationChatTest(
        tester,
        () => tester
            .widget<LocationChatAnchoredMessageList>(
              find.byType(LocationChatAnchoredMessageList),
            )
            .messages
            .any((message) => message.text == 'Private candidate.'),
      );
      var list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(
        list.messages.where((message) => message.isMe).single.text,
        'message 301',
      );
      expect(
        list.messages.any((message) => message.text == 'Original reply.'),
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('location-chat-loading-bubble')),
        findsNothing,
      );
      expect(list.editEnabled, isFalse);
      expect(list.goOnEnabled, isFalse);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        harness.service.state.messagesByLocation['location-current']!.map(
          (message) => message.content,
        ),
        ['message 301', 'Original reply.'],
      );
      await tester.tap(
        find.byKey(const ValueKey('location-chat-reply-previous-card')),
      );
      await _pumpUntilLocationChatTest(
        tester,
        () => tester
            .widget<LocationChatAnchoredMessageList>(
              find.byType(LocationChatAnchoredMessageList),
            )
            .messages
            .any((message) => message.text == 'Original reply.'),
      );
      list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(
        list.messages.where((message) => message.isMe).single.text,
        'message 301',
      );
      expect(list.editEnabled, isTrue);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('location-chat-loading-bubble')),
        findsNothing,
      );
      expect(
        harness.socket.replyActionFrames('regenerate_llm_card'),
        hasLength(1),
      );
      expect(harness.socket.replyActionFrames('select_llm_card'), isEmpty);
      expect(
        backend.requests.any(
          (request) => request.uri.path.endsWith('/llm-messages/select'),
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(harness.service.dispose());
      await tester.pump();
    },
  );

  testWidgets(
    'Go on button sends once and receives a new formal round without a user bubble',
    (tester) async {
      final backend = _LocationChatReplyHttpTransport();
      final harness = await _mountCompletedReplyActionPanel(
        tester,
        backend: backend,
      );
      await tester.tap(find.bySemanticsLabel('Go on'));
      await _pumpUntilLocationChatTest(
        tester,
        () => harness.socket.replyActionFrames('go_on').length == 1,
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('location-chat-loading-bubble')),
        findsOneWidget,
      );
      expect(find.text('Generating…'), findsNothing);
      expect(find.text('Waiting for the next reply…'), findsNothing);
      expect(find.text('Check status'), findsNothing);
      final request = harness.socket.replyActionFrames('go_on').single;
      expect(request['world_id'], 'world-current');
      expect(request['payload'], {
        'location_id': 'location-current',
        'source_conversation_round_id': 301,
      });
      expect(request.containsKey('conversation_round_id'), isFalse);
      expect(request['client_msg_id'], isNotEmpty);
      await tester.tap(find.bySemanticsLabel('Go on'));
      await tester.pump();
      expect(harness.socket.replyActionFrames('go_on'), hasLength(1));
      var list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(list.messages.where((message) => message.isMe), hasLength(1));
      expect(harness.socket.sendMessageCount, 0);

      harness.socket.serverReplyActionAck('go_on', roundId: 401);
      harness.socket.serverWaitingConversationRound(roundId: 401);
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            harness.service.replyActions!
                .stateFor('location-current')!
                .roundId ==
            401,
      );
      harness.socket.serverV2StreamFrame(
        streamType: 'llm_stream_start',
        roundId: 401,
        messageId: 402,
        locationMessageId: 303,
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('location-chat-loading-bubble')),
        findsOneWidget,
      );
      harness.socket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        roundId: 401,
        messageId: 402,
        locationMessageId: 303,
        seq: 1,
        content: 'The story',
      );
      await _pumpUntilLocationChatTest(
        tester,
        () => tester
            .widget<LocationChatAnchoredMessageList>(
              find.byType(LocationChatAnchoredMessageList),
            )
            .messages
            .any((message) => message.text == 'The story'),
      );
      expect(
        find.byKey(const ValueKey('location-chat-loading-bubble')),
        findsNothing,
      );
      expect(
        harness.service.replyActions!
            .statesFor('location-current')
            .any((state) => state.goOnPending),
        isTrue,
      );
      backend.seedGoOnReply();
      harness.socket.serverV2StreamFrame(
        streamType: 'llm_stream_end',
        roundId: 401,
        messageId: 402,
        locationMessageId: 303,
        content: 'The story continues.',
      );
      harness.socket.serverEndConversationRound(roundId: 401);
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            backend.rangeRequests.any(
              (query) => query['start_conversation_round_id'] == '401',
            ) &&
            harness.service.state.messagesByLocation['location-current']!.any(
              (message) => message.content == 'The story continues.',
            ),
      );
      await tester.pumpAndSettle();
      list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(
        list.messages.where((message) => message.isMe).single.text,
        'message 301',
      );
      expect(
        list.messages.any((message) => message.text == 'Original reply.'),
        isTrue,
      );
      expect(
        list.messages.any((message) => message.text == 'The story continues.'),
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('location-chat-loading-bubble')),
        findsNothing,
      );
      expect(list.replyActionsIdentity, 'world-current/location-current/401');
      expect(harness.socket.replyActionFrames('go_on'), hasLength(1));
      expect(harness.socket.sendMessageCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(harness.service.dispose());
      await tester.pump();
    },
  );

  testWidgets(
    'send preserves a newer composer draft while finalizing the previous reply',
    (tester) async {
      final backend = _LocationChatReplyHttpTransport();
      final harness = await _mountCompletedReplyActionPanel(
        tester,
        backend: backend,
      );
      final controller = harness.service.replyActions!;
      final target = await controller.prepareEditor('location-current');
      await controller.setDraft(target, [
        const ChatroomLlmMessageOperation.edit(
          globalMessageId: 90302,
          content: 'Saved previous reply.',
        ),
      ]);
      final barrier = Completer<void>();
      backend.batchBarrier = barrier;
      final composerField = find.descendant(
        of: find.byType(ChatComposer),
        matching: find.byType(TextField),
      );
      await tester.enterText(composerField, 'The text captured by Send.');
      await tester.pump();
      expect(
        tester.widget<ChatComposer>(find.byType(ChatComposer)).sendEnabled,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send-button')));
      await _pumpUntilLocationChatTest(
        tester,
        () => backend.batches.length == 1,
      );
      expect(
        harness.socket.sendMessageCount,
        0,
        reason: 'The prior reply must finish saving first.',
      );
      await tester.enterText(composerField, 'A newer unsent draft.');
      barrier.complete();
      await _pumpUntilLocationChatTest(
        tester,
        () => harness.socket.sendMessageCount == 1,
      );
      final request = harness.socket.replyActionFrames('send_message').single;
      expect(request['payload']['content'], 'The text captured by Send.');
      expect(
        tester.widget<ChatComposer>(find.byType(ChatComposer)).controller.text,
        'A newer unsent draft.',
      );
      expect(
        harness
            .service
            .state
            .messagesByLocation['location-current']!
            .last
            .content,
        'Saved previous reply.',
      );
      harness.socket.serverV2AckForLatestSend(errNo: 0);
      harness.socket.serverV2UserMessage(
        messageId: 303,
        clientMsgId: request['client_msg_id'] as String,
        content: 'The text captured by Send.',
      );
      await _pumpUntilLocationChatTest(
        tester,
        () => harness.service.state.messagesByLocation['location-current']!.any(
          (message) => message.content == 'The text captured by Send.',
        ),
      );
      await tester.pump();
      expect(
        tester.widget<ChatComposer>(find.byType(ChatComposer)).controller.text,
        'A newer unsent draft.',
      );
      expect(harness.socket.sendMessageCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(harness.service.dispose());
      await tester.pump();
    },
  );

  testWidgets(
    'Go on toolbar remains after the final AI row while a later message is streaming',
    (tester) async {
      final backend = _LocationChatReplyHttpTransport();
      final harness = await _mountCompletedReplyActionPanel(
        tester,
        backend: backend,
      );
      await tester.tap(find.bySemanticsLabel('Go on'));
      await _pumpUntilLocationChatTest(
        tester,
        () => harness.socket.replyActionFrames('go_on').length == 1,
      );
      harness.socket.serverReplyActionAck('go_on', roundId: 401);
      harness.socket.serverWaitingConversationRound(roundId: 401);
      harness.socket.serverV2StreamFrame(
        streamType: 'llm_stream_end',
        roundId: 401,
        messageId: 402,
        locationMessageId: 303,
        content: 'The first reply is complete.',
      );
      harness.socket.serverV2StreamFrame(
        streamType: 'llm_stream_start',
        roundId: 401,
        messageId: 403,
        locationMessageId: 304,
      );
      harness.socket.serverV2StreamFrame(
        streamType: 'llm_chunk',
        roundId: 401,
        messageId: 403,
        locationMessageId: 304,
        seq: 1,
        content: 'The next reply is still arriving.',
      );
      await _pumpUntilLocationChatTest(
        tester,
        () => tester
            .widget<LocationChatAnchoredMessageList>(
              find.byType(LocationChatAnchoredMessageList),
            )
            .messages
            .any(
              (message) => message.text == 'The next reply is still arriving.',
            ),
      );
      final list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      final firstIndex = list.messages.indexWhere(
        (message) => message.text == 'The first reply is complete.',
      );
      final lastIndex = list.messages.indexWhere(
        (message) => message.text == 'The next reply is still arriving.',
      );
      expect(firstIndex, greaterThanOrEqualTo(0));
      expect(lastIndex, greaterThan(firstIndex));
      expect(list.messages[lastIndex].status, 'streaming');
      expect(list.replyActionsIdentity, 'world-current/location-current/401');
      expect(
        list.replyActionsAnchorIndex,
        lastIndex + 1,
        reason:
            'One completed message must not move the toolbar inside an unfinished round.',
      );
      expect(list.replyActionsAnchorIndex, list.messages.length);
      expect(list.goOnEnabled, isFalse);
      expect(list.messages.where((message) => message.isMe), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(harness.service.dispose());
      await tester.pump();
    },
  );

  testWidgets(
    'non-member inspiration loads API results without a subscription',
    (tester) async {
      final backend = _LocationChatReplyHttpTransport();
      final harness = await _mountCompletedReplyActionPanel(
        tester,
        backend: backend,
        isMember: false,
      );
      await tester.tap(find.bySemanticsLabel('Inspiration'));
      await _pumpUntilLocationChatTest(
        tester,
        () => tester
            .widget<LocationChatAnchoredMessageList>(
              find.byType(LocationChatAnchoredMessageList),
            )
            .inspirationMessages
            .isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inspiration-replies-carousel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('edit-subscription-prompt')),
        findsNothing,
      );
      expect(backend.inspirationRequests, hasLength(1));
      expect(backend.inspirationRequests.single, {
        'conversation_round_id': 301,
        'refresh': false,
      });
      expect(harness.socket.sendMessageCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(harness.service.dispose());
      await tester.pump();
    },
  );

  for (final outcome in ['success', 'failure', 'new-round']) {
    testWidgets('inspiration confirms its card before sending: $outcome', (
      tester,
    ) async {
      final backend = _LocationChatReplyHttpTransport();
      final harness = await _mountCompletedReplyActionPanel(
        tester,
        backend: backend,
        isMember: false,
      );
      backend.cards.addAll([
        backend._cardJson(501, 1, 'succeeded', 'Original reply.'),
        backend._cardJson(502, 2, 'succeeded', 'Candidate reply.'),
      ]);
      unawaited(
        harness.service.refreshLatestMessages(locationId: 'location-current'),
      );
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            harness.service.replyActions!
                .stateFor('location-current')!
                .cardCount ==
            2,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('location-chat-reply-next-card')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Inspiration'));
      await _pumpUntilLocationChatTest(
        tester,
        () => tester
            .widget<LocationChatAnchoredMessageList>(
              find.byType(LocationChatAnchoredMessageList),
            )
            .inspirationMessages
            .isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(backend.inspirationRequests.single['card_id'], 502);
      backend.selectionBarrier = Completer<void>();
      backend.selectionFails = outcome == 'failure';
      await tester.tap(
        find.byKey(const ValueKey('chat-message-bubble-inspiration-0')),
      );
      await tester.pump();
      await _pumpUntilLocationChatTest(
        tester,
        () => backend.selectionRequests.isNotEmpty,
      );
      expect(harness.socket.sendMessageCount, 0);
      expect(backend.selectionRequests.single['card_id'], 502);
      if (outcome == 'new-round') {
        harness.socket.serverWaitingConversationRound(roundId: 401);
        await tester.pump();
      }
      backend.selectionBarrier!.complete();
      if (outcome == 'success') {
        await _pumpUntilLocationChatTest(
          tester,
          () => harness.socket.sendMessageCount == 1,
        );
        final sent = harness.socket._sentFrames.lastWhere(
          (frame) => frame['type'] == 'send_message',
        );
        expect(sent['payload']['content'], 'Good job!');
        expect(backend.selectedCardId, 502);
        harness.socket.serverV2AckForLatestSend(errNo: 4001);
      }
      await tester.pump(const Duration(seconds: 4));
      expect(harness.socket.sendMessageCount, outcome == 'success' ? 1 : 0);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(harness.service.dispose());
      await tester.pump();
    });
  }

  testWidgets(
    'a new round removes inspiration and disables requests until complete',
    (tester) async {
      final backend = _LocationChatReplyHttpTransport();
      final harness = await _mountCompletedReplyActionPanel(
        tester,
        backend: backend,
      );
      await tester.tap(find.bySemanticsLabel('Inspiration'));
      await _pumpUntilLocationChatTest(
        tester,
        () => tester
            .widget<LocationChatAnchoredMessageList>(
              find.byType(LocationChatAnchoredMessageList),
            )
            .inspirationMessages
            .isNotEmpty,
      );
      harness.socket.serverWaitingConversationRound(roundId: 401);
      await tester.pump();
      await tester.pump();
      final list = tester.widget<LocationChatAnchoredMessageList>(
        find.byType(LocationChatAnchoredMessageList),
      );
      expect(list.inspirationEnabled, isFalse);
      expect(list.inspirationMessages, isEmpty);
      list.onInspirationExpanded!(true);
      await tester.pump();
      expect(backend.inspirationRequests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(harness.service.dispose());
      await tester.pump();
    },
  );

  testWidgets('inspiration uses the composer focus and existing send flow', (
    tester,
  ) async {
    final backend = _LocationChatReplyHttpTransport();
    final harness = await _mountCompletedReplyActionPanel(
      tester,
      backend: backend,
    );
    await tester.tap(find.bySemanticsLabel('Inspiration'));
    await _pumpUntilLocationChatTest(
      tester,
      () => tester
          .widget<LocationChatAnchoredMessageList>(
            find.byType(LocationChatAnchoredMessageList),
          )
          .inspirationMessages
          .isNotEmpty,
    );
    final list = tester.widget<LocationChatAnchoredMessageList>(
      find.byType(LocationChatAnchoredMessageList),
    );
    list.onInspirationEdit!('Good job!');
    await tester.pump();
    final composer = tester.widget<ChatComposer>(find.byType(ChatComposer));
    expect(composer.controller.text, 'Good job!');
    expect(composer.controller.selection.baseOffset, 'Good job!'.length);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(tester.testTextInput.isVisible, isTrue);
    expect(harness.socket.sendMessageCount, 0);

    tester.testTextInput.hide();
    list.onInspirationEdit!('Edit while still focused.');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(composer.controller.text, 'Edit while still focused.');

    list.onInspirationSend!('A different suggestion.');
    await _pumpUntilLocationChatTest(
      tester,
      () => harness.socket.sendMessageCount == 1,
    );
    final frame = harness.socket._sentFrames.lastWhere(
      (frame) => frame['type'] == 'send_message',
    );
    expect(frame['payload']['content'], 'A different suggestion.');
    expect(composer.controller.text, isEmpty);
    // Busy send guards also apply to inspiration taps.
    list.onInspirationSend!('Do not duplicate.');
    await tester.pump();
    expect(harness.socket.sendMessageCount, 1);
    harness.socket.serverV2AckForLatestSend(errNo: 4001);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(harness.service.dispose());
  });

  testWidgets(
    'location chat records one message_sent across transport retries',
    (WidgetTester tester) async {
      final analytics = _enableLocationChatAnalyticsForTesting(
        initialMessageSentCount: 9,
      );
      final harness = await _connectedLocationChatTestService(
        ackTimeout: const Duration(milliseconds: 10),
      );
      final service = harness.service;
      final socket = harness.socket;

      await tester.pumpWidget(
        AppServicesScope(
          services: harness.services,
          child: MaterialApp(
            home: LocationChatPanel(
              worldId: 'world-current',
              locationId: 'location-current',
              service: service,
              leaveOnInactive: false,
              messageQueueInitializationCovered: true,
            ),
          ),
        ),
      );
      await _pumpUntilLocationChatTest(
        tester,
        () => service.state.joinedLocationId == 'location-current',
      );

      final composerFinder = find.byType(ChatComposer);
      tester.widget<ChatComposer>(composerFinder).controller.text =
          'hello from location chat';
      await tester.pump();
      unawaited(tester.widget<ChatComposer>(composerFinder).onSend());
      await _pumpUntilLocationChatTest(
        tester,
        () =>
            socket.sendMessageCount == 1 &&
            analytics.events.any(
              (event) => event.name == 'message_sent_10_first',
            ),
      );

      expect(analytics.events, <_LocationChatAnalyticsEvent>[
        const _LocationChatAnalyticsEvent('message_sent', <String, Object>{
          'world_id': 'world-current',
          'location_id': 'location-current',
          'device_id': 'test-device-id',
        }),
        const _LocationChatAnalyticsEvent(
          'message_sent_first',
          <String, Object>{
            'world_id': 'world-current',
            'location_id': 'location-current',
            'device_id': 'test-device-id',
          },
        ),
        const _LocationChatAnalyticsEvent(
          'message_sent_10_first',
          <String, Object>{
            'world_id': 'world-current',
            'location_id': 'location-current',
            'device_id': 'test-device-id',
          },
        ),
      ]);

      // The chatroom client retries a missing ACK internally. Those transport
      // attempts must not create additional business-level Analytics events.
      await tester.pump(const Duration(milliseconds: 35));
      expect(socket.sendMessageCount, 3);
      expect(analytics.events, hasLength(3));
      await tester.pump(const Duration(seconds: 3));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(service.dispose());
    },
  );

  testWidgets('manual failed-message retry does not record message_sent', (
    WidgetTester tester,
  ) async {
    final analytics = _enableLocationChatAnalyticsForTesting();
    final harness = await _connectedLocationChatTestService();
    final service = harness.service;
    final socket = harness.socket;

    await tester.pumpWidget(
      AppServicesScope(
        services: harness.services,
        child: MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            service: service,
            leaveOnInactive: false,
            messageQueueInitializationCovered: true,
          ),
        ),
      ),
    );
    await _pumpUntilLocationChatTest(
      tester,
      () => service.state.joinedLocationId == 'location-current',
    );

    final composerFinder = find.byType(ChatComposer);
    tester.widget<ChatComposer>(composerFinder).controller.text =
        'retryable message';
    await tester.pump();
    unawaited(tester.widget<ChatComposer>(composerFinder).onSend());
    await _pumpUntilLocationChatTest(
      tester,
      () =>
          socket.sendMessageCount == 1 &&
          analytics.events.any((event) => event.name == 'message_sent'),
    );
    await tester.pump();
    final initialAnalyticsEvents = List<_LocationChatAnalyticsEvent>.of(
      analytics.events,
    );
    socket.serverV2AckForLatestSend(errNo: 9001);
    await _pumpUntilLocationChatTest(
      tester,
      () => find.byType(ChatFailedBadge).evaluate().isNotEmpty,
    );

    await tester.tap(find.byType(ChatFailedBadge));
    await _pumpUntilLocationChatTest(
      tester,
      () => socket.sendMessageCount == 2,
    );
    expect(analytics.events, initialAnalyticsEvents);

    socket.serverV2AckForLatestSend(errNo: 9001);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(service.dispose());
  });

  testWidgets('blank and blocked location chat sends are not recorded', (
    WidgetTester tester,
  ) async {
    final analytics = _enableLocationChatAnalyticsForTesting();
    final harness = await _connectedLocationChatTestService();
    final service = harness.service;
    final socket = harness.socket;

    await tester.pumpWidget(
      AppServicesScope(
        services: harness.services,
        child: MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            service: service,
            leaveOnInactive: false,
            messageQueueInitializationCovered: true,
          ),
        ),
      ),
    );
    await _pumpUntilLocationChatTest(
      tester,
      () => service.state.joinedLocationId == 'location-current',
    );

    final composerFinder = find.byType(ChatComposer);
    await tester.widget<ChatComposer>(composerFinder).onSend();
    await tester.pump();
    expect(socket.sendMessageCount, 0);
    expect(analytics.events, isEmpty);

    final composer = tester.widget<ChatComposer>(composerFinder);
    composer.controller.text = 'blocked draft';
    socket.serverWaitingConversationRound(roundId: 301);
    await _pumpUntilLocationChatTest(
      tester,
      () => service.state.waitingConversationRoundIdsByLocation.containsKey(
        'location-current',
      ),
    );
    await tester.pump();
    await tester.widget<ChatComposer>(composerFinder).onSend();
    await tester.pump();
    expect(socket.sendMessageCount, 0);
    expect(analytics.events, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(service.dispose());
  });

  testWidgets('a synchronous send failure is still recorded once', (
    WidgetTester tester,
  ) async {
    final analytics = _enableLocationChatAnalyticsForTesting();
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('user-1');
    final services = ServiceRegistry.build(
      config: const AppConfig(useMock: true),
      sessionStoreOverride: sessionStore,
      chatroomMessagesOverride: MemoryChatroomMessageStorage(),
    );
    final service = _ThrowingLocationChatService(services);

    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-sync-failure',
            locationId: 'location-sync-failure',
            service: service,
            leaveOnInactive: false,
            messageQueueInitializationCovered: true,
          ),
        ),
      ),
    );
    await tester.pump();

    final composerFinder = find.byType(ChatComposer);
    tester.widget<ChatComposer>(composerFinder).controller.text =
        'attempted message';
    await tester.pump();
    await tester.widget<ChatComposer>(composerFinder).onSend();
    await tester.pump();

    expect(service.sendAttempts, 1);
    expect(analytics.events, <_LocationChatAnalyticsEvent>[
      const _LocationChatAnalyticsEvent('message_sent', <String, Object>{
        'world_id': 'world-sync-failure',
        'location_id': 'location-sync-failure',
        'device_id': 'test-device-id',
      }),
      const _LocationChatAnalyticsEvent('message_sent_first', <String, Object>{
        'world_id': 'world-sync-failure',
        'location_id': 'location-sync-failure',
        'device_id': 'test-device-id',
      }),
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await service.dispose();
  });

  testWidgets('server waiting round disables send until matching end event', (
    WidgetTester tester,
  ) async {
    final harness = await _connectedLocationChatTestService();
    final services = harness.services;
    final service = harness.service;
    final socket = harness.socket;

    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            service: service,
            leaveOnInactive: false,
          ),
        ),
      ),
    );
    await _pumpUntilLocationChatTest(
      tester,
      () => service.state.joinedLocationId == 'location-current',
    );

    final composerFinder = find.byType(ChatComposer);
    final composer = tester.widget<ChatComposer>(composerFinder);
    composer.controller.text = 'draft while the server responds';
    await tester.pump();
    expect(tester.widget<ChatComposer>(composerFinder).sendEnabled, isTrue);

    socket.serverWaitingConversationRound(roundId: 301);
    await _pumpUntilLocationChatTest(
      tester,
      () =>
          service
              .state
              .waitingConversationRoundIdsByLocation['location-current'] ==
          '301',
    );
    await tester.pump();
    expect(tester.widget<ChatComposer>(composerFinder).sendEnabled, isFalse);
    expect(
      tester
          .widget<LocationChatAnchoredMessageList>(
            find.byType(LocationChatAnchoredMessageList),
          )
          .editEnabled,
      isFalse,
      reason: 'Reply editing stays disabled until the entire round finishes.',
    );

    await tester.widget<ChatComposer>(composerFinder).onSend();
    expect(socket.sendMessageCount, 0);
    expect(composer.controller.text, 'draft while the server responds');

    socket.serverV2StreamFrame(
      streamType: 'llm_stream_start',
      roundId: 301,
      messageId: 301,
    );
    socket.serverV2StreamFrame(
      streamType: 'llm_chunk',
      roundId: 301,
      messageId: 301,
      seq: 1,
      content: 'partial response',
    );
    await _pumpUntilLocationChatTest(
      tester,
      () => service.state.streamMessagesByKey.isNotEmpty,
    );
    expect(tester.widget<ChatComposer>(composerFinder).sendEnabled, isFalse);
    expect(
      tester
          .widget<LocationChatAnchoredMessageList>(
            find.byType(LocationChatAnchoredMessageList),
          )
          .editEnabled,
      isFalse,
      reason: 'Reply editing stays disabled until the entire round finishes.',
    );

    socket.serverV2StreamFrame(
      streamType: 'llm_stream_end',
      roundId: 301,
      messageId: 302,
      content: 'complete response',
    );
    await _pumpUntilLocationChatTest(
      tester,
      () => service.state.streamMessagesByKey.isEmpty,
    );
    await tester.pump();
    expect(tester.widget<ChatComposer>(composerFinder).sendEnabled, isFalse);
    expect(
      tester
          .widget<LocationChatAnchoredMessageList>(
            find.byType(LocationChatAnchoredMessageList),
          )
          .editEnabled,
      isFalse,
      reason: 'Reply editing stays disabled until the entire round finishes.',
    );

    socket.serverEndConversationRound(roundId: 301);
    await _pumpUntilLocationChatTest(
      tester,
      () => !service.state.waitingConversationRoundIdsByLocation.containsKey(
        'location-current',
      ),
    );
    await tester.pump();
    expect(tester.widget<ChatComposer>(composerFinder).sendEnabled, isTrue);
    expect(
      tester
          .widget<LocationChatAnchoredMessageList>(
            find.byType(LocationChatAnchoredMessageList),
          )
          .editEnabled,
      isTrue,
      reason:
          'Reply editing is available after the final content and round end.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(service.dispose());
  });

  test(
    'selected role aliases historical character messages to current user',
    () {
      const characters = <Map<String, dynamic>>[
        {'char_id': 'mateo', 'player_uid': 'u_me', 'name': 'Mateo Cruz'},
        {'char_id': 'marcus', 'player_uid': 'u_other', 'name': 'Marcus'},
      ];

      expect(
        locationChatMessageBelongsToCurrentRoleForTesting(
          messageUserId: '',
          messageSenderId: 'mateo',
          currentUserIds: const {'u_me'},
          currentSenderIds: const {'u_me'},
          characters: characters,
          characterPositions: const [],
        ),
        isTrue,
      );
      expect(
        locationChatMessageBelongsToCurrentRoleForTesting(
          messageUserId: 'u_me',
          messageSenderId: 'u_me',
          currentUserIds: const {'u_me'},
          currentSenderIds: const {'u_me'},
          characters: characters,
          characterPositions: const [],
        ),
        isTrue,
      );
      expect(
        locationChatMessageBelongsToCurrentRoleForTesting(
          messageUserId: '',
          messageSenderId: 'marcus',
          currentUserIds: const {'u_me'},
          currentSenderIds: const {'u_me'},
          characters: characters,
          characterPositions: const [],
        ),
        isFalse,
      );
    },
  );

  test(
    'edited AI history keeps other identity despite the initiating user ID',
    () {
      for (final type in ['character', 'narrator']) {
        for (final status in [0, 20]) {
          final message = WorldChatroomMessage.fromHttpMessage(
            ChatroomHttpMessage.fromV2Message(
              ChatroomV2Message.fromJson({
                'type': type,
                'global_message_id': 9007199254740993,
                'world_id': 'world',
                'location_id': 'location',
                'conversation_round_id': 42,
                'user_id': 'u_me',
                'sender_type': type,
                'sender_id': 'mateo',
                'payload': {
                  'content': status == 20 ? 'Edited reply' : 'Original reply',
                  'status': status,
                },
              }),
            ),
          );
          expect(
            locationChatMessageBelongsToCurrentRoleForTesting(
              messageBusinessType: locationChatBusinessType(message),
              messageUserId: message.userId,
              messageSenderId: message.senderId,
              currentUserIds: const {'u_me'},
              currentSenderIds: const {'u_me'},
              characters: const [
                {'char_id': 'mateo', 'player_uid': 'u_me'},
              ],
              characterPositions: const [],
            ),
            isFalse,
            reason:
                '$type with status=$status is a reply, not the initiating user',
          );
        }
      }
      for (final user in ['u_me', 'u_other']) {
        expect(
          locationChatMessageBelongsToCurrentRoleForTesting(
            messageBusinessType: 'user',
            messageUserId: user,
            messageSenderId: user,
            currentUserIds: const {'u_me'},
            currentSenderIds: const {'u_me'},
            characters: const [],
            characterPositions: const [],
          ),
          user == 'u_me',
        );
      }
    },
  );

  test('selected role alias resolves nested character position data', () {
    expect(
      locationChatMessageBelongsToCurrentRoleForTesting(
        messageUserId: '',
        messageSenderId: 'mateo',
        currentUserIds: const {'u_me'},
        currentSenderIds: const {'u_me'},
        characters: const [],
        characterPositions: const [
          {
            'location_id': 'loc-1',
            'character': {'id': 'mateo', 'player_uid': 'u_me'},
          },
        ],
      ),
      isTrue,
    );
  });

  test('story visibility uses every local character name', () {
    final roleNamesById = locationChatCurrentRoleNamesByIdForTesting(
      currentUserIds: const {'u_me'},
      currentSenderIds: const {'u_me'},
      characters: const [
        {'char_id': 'mateo', 'player_uid': 'u_me', 'name': 'Mateo Cruz'},
        {'char_id': 'iris', 'player_uid': 'u_me', 'name': 'Iris'},
        {'char_id': 'marcus', 'player_uid': 'u_other', 'name': 'Marcus'},
        {'char_id': 'oracle', 'player_uid': '', 'name': 'Oracle'},
      ],
      characterPositions: const [],
    );

    expect(roleNamesById, {
      'mateo': 'Mateo Cruz',
      'iris': 'Iris',
      'marcus': 'Marcus',
      'oracle': 'Oracle',
    });
    final roleIsAiById = locationChatRoleIsAiByIdForTesting(
      characters: const [
        {'char_id': 'mateo', 'player_uid': 'u_me'},
        {'char_id': 'oracle', 'player_uid': ''},
      ],
    );
    expect(roleIsAiById, {'mateo': false, 'oracle': true});
    expect(
      locationChatStoryEventParagraphVmForTesting(
        const ChatroomStoryEventParagraph(
          timestamp: 'Day 2, 10:15',
          visibility: 'public',
          visibleTo: [],
          text: 'Everyone can see this.',
          clue: '',
        ),
        roleNamesById: roleNamesById,
      )?.visibilityLabel,
      'public',
    );
    expect(
      locationChatStoryEventParagraphVmForTesting(
        const ChatroomStoryEventParagraph(
          timestamp: 'Day 2, 10:20',
          visibility: 'char_only',
          visibleTo: ['mateo', 'marcus', 'iris', 'mateo'],
          text: 'Only local roles can see this.',
          clue: '',
        ),
        roleNamesById: roleNamesById,
      )?.visibilityLabel,
      'Mateo Cruz, Marcus, Iris',
    );
    expect(
      locationChatStoryEventParagraphVmForTesting(
        const ChatroomStoryEventParagraph(
          timestamp: 'Day 2, 10:22',
          visibility: 'char_only',
          visibleTo: ['oracle', 'mateo'],
          text: 'AI and player roles see this.',
          clue: '',
        ),
        roleNamesById: roleNamesById,
        roleIsAiById: roleIsAiById,
      )?.visibleRoles,
      const [
        ChatStoryEventVisibleRoleVm(
          roleId: 'oracle',
          name: 'Oracle',
          isAi: true,
        ),
        ChatStoryEventVisibleRoleVm(
          roleId: 'mateo',
          name: 'Mateo Cruz',
          isAi: false,
        ),
      ],
    );
    expect(
      locationChatStoryEventParagraphVmForTesting(
        const ChatroomStoryEventParagraph(
          timestamp: 'Day 2, 10:25',
          visibility: 'char_only',
          visibleTo: ['marcus'],
          text: 'A different player sees this.',
          clue: '',
        ),
        roleNamesById: roleNamesById,
      )?.visibilityLabel,
      'Marcus',
    );
    expect(
      locationChatStoryEventParagraphVmForTesting(
        const ChatroomStoryEventParagraph(
          timestamp: 'Day 2, 10:30',
          visibility: 'char_only',
          visibleTo: ['missing'],
          text: 'The event remains visible without a matching label.',
          clue: '',
        ),
        roleNamesById: roleNamesById,
      )?.visibilityLabel,
      isEmpty,
    );
  });

  test('movement labels resolve known names and retain unknown ids', () {
    expect(
      resolveLocationChatTimelineCharacterNameForTesting(
        characterId: 'char-alice',
        characterPositions: const [
          {
            'location_id': 'loc-cafe',
            'character': {'id': 'char-alice', 'name': 'Alice'},
          },
        ],
      ),
      'Alice',
    );
    expect(
      resolveLocationChatTimelineCharacterNameForTesting(
        characterId: 'char-unknown',
      ),
      'char-unknown',
    );
    expect(
      resolveLocationChatTimelineLocationNameForTesting(
        locationId: 'loc-cafe',
        locations: const [
          {'location_id': 'loc-cafe', 'location_name': 'Cafe'},
        ],
      ),
      'Cafe',
    );
    expect(
      resolveLocationChatTimelineLocationNameForTesting(
        locationId: 'loc-unknown',
      ),
      'loc-unknown',
    );
  });

  test(
    'message reconciliation preserves local rows until canonical ids arrive',
    () {
      final accepted = ChatMessageVm(
        localId: 'local-accepted',
        clientMsgId: 'client-accepted',
        senderId: 'u_me',
        senderName: 'Me',
        avatarUrl: '',
        text: 'Accepted, awaiting echo',
        isMe: true,
        status: 'sent',
      );
      final canonical = ChatMessageVm(
        localId: 'server-message',
        clientMsgId: 'server-client-id',
        globalMessageId: 100,
        messageId: 10,
        locationMessageId: 1,
        senderId: 'u_me',
        senderName: 'Me',
        avatarUrl: '',
        text: 'Already canonical',
        isMe: true,
        status: 'sent',
      );
      final sending = ChatMessageVm(
        localId: 'local-sending',
        clientMsgId: 'client-sending',
        senderId: 'u_me',
        senderName: 'Me',
        avatarUrl: '',
        text: 'Sending',
        isMe: true,
        status: 'sending',
      );
      final failed = ChatMessageVm(
        localId: 'local-failed',
        clientMsgId: 'client-failed',
        senderId: 'u_me',
        senderName: 'Me',
        avatarUrl: '',
        text: 'Insufficient balance',
        isMe: true,
        status: 'failed',
      );
      final reconciled = <ChatMessageVm>[];

      preserveUnmatchedLocationChatLocalMessages(
        previous: [accepted, canonical, sending, failed],
        reconciled: reconciled,
        usedLocalIds: <String>{},
      );

      expect(reconciled, [accepted, sending, failed]);

      accepted.globalMessageId = 101;
      accepted.messageId = 11;
      accepted.locationMessageId = 2;
      final afterCanonical = <ChatMessageVm>[];
      preserveUnmatchedLocationChatLocalMessages(
        previous: [accepted],
        reconciled: afterCanonical,
        usedLocalIds: <String>{},
      );

      expect(afterCanonical, isEmpty);
    },
  );

  test('message reconciliation does not duplicate an already matched row', () {
    final sent = ChatMessageVm(
      localId: 'local-accepted',
      clientMsgId: 'client-accepted',
      senderId: 'u_me',
      senderName: 'Me',
      avatarUrl: '',
      text: 'Accepted, awaiting echo',
      isMe: true,
      status: 'sent',
    );
    final reconciled = <ChatMessageVm>[sent];

    preserveUnmatchedLocationChatLocalMessages(
      previous: [sent],
      reconciled: reconciled,
      usedLocalIds: {sent.localId},
    );

    expect(reconciled, [sent]);
  });

  test('ack 3001 removes the optimistic message and restores its draft', () {
    final localMessage = ChatMessageVm(
      localId: 'local-balance',
      clientMsgId: 'client-balance',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Try this again after top up',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: '3001',
        message: 'Insufficient balance',
      ),
      localMessage: localMessage,
      messages: messages,
    );

    expect(restoredDraft, 'Try this again after top up');
    expect(messages, isEmpty);
  });

  test('ack 2010 removes the optimistic message and restores its draft', () {
    final localMessage = ChatMessageVm(
      localId: 'local-rate-limited',
      clientMsgId: 'client-rate-limited',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Send this later',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: '2010',
        message: 'Rate limit exceeded',
      ),
      localMessage: localMessage,
      messages: messages,
    );

    expect(restoredDraft, 'Send this later');
    expect(messages, isEmpty);
  });

  test('ack 2006 removes the optimistic message and restores its draft', () {
    final localMessage = ChatMessageVm(
      localId: 'local-world-progressing',
      clientMsgId: 'client-world-progressing',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Send after world progress',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: '2006',
        message: 'World is progressing',
      ),
      localMessage: localMessage,
      messages: messages,
    );

    expect(restoredDraft, 'Send after world progress');
    expect(messages, isEmpty);
  });

  test('ack 5000 removes the optimistic message and restores its draft', () {
    final localMessage = ChatMessageVm(
      localId: 'local-server-error',
      clientMsgId: 'client-server-error',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Retry after server recovery',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: '5000',
        message: 'Service unavailable',
      ),
      localMessage: localMessage,
      messages: messages,
    );

    expect(restoredDraft, 'Retry after server recovery');
    expect(messages, isEmpty);
  });

  test('ack 1002 removes the optimistic message and restores its draft', () {
    final localMessage = ChatMessageVm(
      localId: 'local-format-error',
      clientMsgId: 'client-format-error',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Edit this message',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: '1002',
        message: 'Message format error',
      ),
      localMessage: localMessage,
      messages: messages,
    );

    expect(restoredDraft, 'Edit this message');
    expect(messages, isEmpty);
  });

  test('ack 1008 removes the optimistic message and restores its draft', () {
    final localMessage = ChatMessageVm(
      localId: 'local-send-format-error',
      clientMsgId: 'client-send-format-error',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Edit this send message',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: '1008',
        message: 'Send message format error',
      ),
      localMessage: localMessage,
      messages: messages,
    );

    expect(restoredDraft, 'Edit this send message');
    expect(messages, isEmpty);
  });

  test('ack 10001 removes the optimistic message and restores its draft', () {
    final localMessage = ChatMessageVm(
      localId: 'local-unauthorized',
      clientMsgId: 'client-unauthorized',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Retry this message',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: '10001',
        message: 'Unauthorized',
      ),
      localMessage: localMessage,
      messages: messages,
    );

    expect(restoredDraft, 'Retry this message');
    expect(messages, isEmpty);
  });

  test('active socket close send failure restores its draft', () {
    final localMessage = ChatMessageVm(
      localId: 'local-socket-closed',
      clientMsgId: 'client-socket-closed',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Put this back in the input',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: 'socket_closed',
        message: 'Something went wrong',
        sourceType: 'socket_closed',
      ),
      localMessage: localMessage,
      messages: messages,
      activeSendFailure: true,
    );

    expect(restoredDraft, 'Put this back in the input');
    expect(messages, isEmpty);
  });

  test('passive socket close does not restore a draft', () {
    final localMessage = ChatMessageVm(
      localId: 'local-passive-socket-closed',
      clientMsgId: 'client-passive-socket-closed',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Do not restore this',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: 'socket_closed',
        message: 'Something went wrong',
        sourceType: 'socket_closed',
      ),
      localMessage: localMessage,
      messages: messages,
    );

    expect(restoredDraft, isNull);
    expect(messages, [localMessage]);
  });

  test('only ack 10001 prompts chat login recovery', () {
    expect(
      isChatroomUnauthorizedFailure(
        const ChatroomFailureEvent(code: '10001', message: 'Unauthorized'),
      ),
      isTrue,
    );
    expect(
      isChatroomUnauthorizedFailure(
        const ChatroomFailureEvent(
          code: '5000',
          message: 'Service unavailable',
        ),
      ),
      isFalse,
    );
  });

  test('other send failures keep the optimistic message', () {
    final localMessage = ChatMessageVm(
      localId: 'local-failed',
      clientMsgId: 'client-failed',
      senderId: 'u_me',
      senderName: 'Me',
      text: 'Keep this failed message',
      isMe: true,
      status: 'sending',
    );
    final messages = <ChatMessageVm>[localMessage];

    final restoredDraft = recoverLocationChatDraftAfterRetriableAckFailure(
      failure: const ChatroomFailureEvent(
        code: 'send_failed',
        message: 'Send failed',
      ),
      localMessage: localMessage,
      messages: messages,
    );

    expect(restoredDraft, isNull);
    expect(messages, [localMessage]);
  });

  test('location chat model entry is server driven and world scoped', () {
    final source = _readLocationChatImplementationSource();

    expect(source, isNot(contains("modelLabel: 'CC4.5'")));
    expect(source, contains('sessionStore.readUserInfo()'));
    expect(source, contains('sessionStore.userInfoRevision'));
    expect(source, contains('_handleCachedUserInfoChanged'));
    expect(source, isNot(contains('api.v1.user.info()')));
    expect(source, contains('rootNavigator: true'));
    expect(source, contains('pushNamed<String>('));
    expect(source, contains("arguments: {'world_id': modelWorldId}"));
  });

  testWidgets('location chat model entry opens the current world model list', (
    tester,
  ) async {
    Object? routeArguments;
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name != RouteNames.memoryModel) return null;
          routeArguments = settings.arguments;
          return MaterialPageRoute<String>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('Model selection list')),
          );
        },
        home: Navigator(
          pages: const [
            MaterialPage<void>(
              child: LocationChatPanel(
                worldId: 'world-current',
                modelWorldId: 'world-current',
                locationId: 'location-current',
                active: true,
              ),
            ),
          ],
          onDidRemovePage: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('memory-model-entry')));
    await tester.pumpAndSettle();

    expect(find.text('Model selection list'), findsOneWidget);
    expect(routeArguments, {'world_id': 'world-current'});
  });

  testWidgets('location chat without a real world id hides the model entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationChatPanel(
          worldId: 'worldo-preview',
          locationId: 'location-current',
          active: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('memory-model-entry')), findsNothing);
  });

  testWidgets('exhausted location chat prepends one AI disclaimer bubble', (
    tester,
  ) async {
    final historyMessage = _message(
      messageId: 10,
      locationMessageId: 0,
      content: 'Only available history message',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocationChatPanel(
          worldId: 'world-current',
          locationId: 'loc-1',
          active: false,
          openingPreviewMessages: [historyMessage],
        ),
      ),
    );
    await tester.pump();

    final messageList = tester.widget<LocationChatAnchoredMessageList>(
      find.byKey(const ValueKey('location-chat-message-list')),
    );
    expect(messageList.oldestEdgeNotice, isNull);
    expect(messageList.oldestEdgeNoticeRequiresSecondScroll, isFalse);
    expect(messageList.messages.first.isAiContentDisclaimer, isTrue);
    expect(
      messageList.messages.where((message) => message.isAiContentDisclaimer),
      hasLength(1),
    );
    expect(messageList.messages.last.text, 'Only available history message');
    expect(find.byType(ChatAiContentDisclaimerMessageBubble), findsOneWidget);
    expect(find.text(kAiContentDisclaimerText), findsOneWidget);
  });

  testWidgets('resolved empty location chat shows the AI disclaimer bubble', (
    tester,
  ) async {
    final connected = await _connectedLocationChatTestService();
    final services = connected.services;
    final service = connected.service;
    await service.join(locationId: 'location-current');

    Widget build({required bool active}) {
      return AppServicesScope(
        services: services,
        child: MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            active: active,
            service: service,
            leaveOnInactive: false,
            messageQueueInitializationCovered: true,
          ),
        ),
      );
    }

    await tester.pumpWidget(build(active: false));
    await _pumpUntilLocationChatTest(
      tester,
      () => find
          .byType(ChatAiContentDisclaimerMessageBubble)
          .evaluate()
          .isNotEmpty,
    );

    final messageList = tester.widget<LocationChatAnchoredMessageList>(
      find.byKey(const ValueKey('location-chat-message-list')),
    );
    expect(messageList.messages, hasLength(1));
    expect(messageList.messages.single.isAiContentDisclaimer, isTrue);
    expect(find.text(kAiContentDisclaimerText), findsOneWidget);

    await tester.pumpWidget(build(active: true));
    await tester.pump();
    connected.socket.serverV2UserMessage(messageId: 1);
    await _pumpUntilLocationChatTest(tester, () {
      if (service.state.messagesByLocation['location-current']?.length != 1) {
        return false;
      }
      final listFinder = find.byKey(
        const ValueKey('location-chat-message-list'),
      );
      if (listFinder.evaluate().isEmpty) return false;
      return tester
              .widget<LocationChatAnchoredMessageList>(listFinder)
              .messages
              .length ==
          2;
    });

    final updatedMessageList = tester.widget<LocationChatAnchoredMessageList>(
      find.byKey(const ValueKey('location-chat-message-list')),
    );
    expect(
      updatedMessageList.messages.where(
        (message) => message.isAiContentDisclaimer,
      ),
      hasLength(1),
    );
    expect(updatedMessageList.messages.first.isAiContentDisclaimer, isTrue);
    expect(updatedMessageList.messages.last.text, 'message 1');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(service.dispose());
  });

  testWidgets(
    'location chat retains the model entry width while becoming inactive',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Widget panel({required bool active}) {
        return MaterialApp(
          home: LocationChatPanel(
            key: const ValueKey<String>('retained-model-entry-panel'),
            worldId: 'world-current',
            modelWorldId: 'world-current',
            locationId: 'location-current',
            locationName: 'The Wisteria Terrace With A Long Name',
            active: active,
            leaveOnInactive: false,
          ),
        );
      }

      await tester.pumpWidget(panel(active: true));
      await tester.pump();
      final title = find.text('The Wisteria Terrace With A Long Name');
      final count = find.text('1');
      final modelEntry = find.byKey(const ValueKey('memory-model-entry'));
      final activeTitleRect = tester.getRect(title);
      final activeCountRect = tester.getRect(count);
      final activeModelRect = tester.getRect(modelEntry);

      await tester.pumpWidget(panel(active: false));
      await tester.pump();

      expect(modelEntry, findsOneWidget);
      expect(tester.getRect(title), activeTitleRect);
      expect(tester.getRect(count), activeCountRect);
      expect(tester.getRect(modelEntry), activeModelRect);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'location chat adds self optimistically and retains the count on exit',
    (tester) async {
      final connected = await _connectedLocationChatTestService();

      Widget panel({required bool active}) {
        return AppServicesScope(
          services: connected.services,
          child: MaterialApp(
            home: LocationChatPanel(
              key: const ValueKey<String>('optimistic-occupant-panel'),
              worldId: 'world-current',
              locationId: 'location-current',
              locationName: 'Wisteria Terrace',
              active: active,
              service: connected.service,
              leaveOnInactive: false,
              messageQueueInitializationCovered: true,
            ),
          ),
        );
      }

      await tester.pumpWidget(panel(active: true));
      expect(find.text('1'), findsOneWidget);

      await _pumpUntilLocationChatTest(
        tester,
        () => connected.service.state.joinedLocationId == 'location-current',
      );
      expect(find.text('1'), findsOneWidget);

      unawaited(connected.service.leave());
      await tester.pumpWidget(panel(active: false));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(connected.service.dispose());
    },
  );

  testWidgets('opening the roster preserves scroll and dismisses outside', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocationChatPanel(
          worldId: 'roster-scroll',
          locationId: 'loc-1',
          active: false,
          openingPreviewMessages: <WorldChatroomMessage>[
            for (var index = 0; index < 24; index += 1)
              WorldChatroomMessage(
                messageId: 0,
                conversationRoundId: 'opening-preview-$index',
                roundOrder: index,
                locationId: 'loc-1',
                senderType: 'character',
                senderId: 'char-role',
                senderName: 'Preview Role',
                content: 'Opening line $index.',
                createdAt: null,
              ),
          ],
          openingPreviewEntities: const [
            WorldChatroomEntity(
              id: 'char-role',
              name: 'Preview Role',
              avatarUrl: '',
              type: WorldChatroomEntityType.character,
              locationId: 'loc-1',
              isAi: true,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('location-chat-message-list')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.pump();
    final scrolledOffset = position.pixels;
    final scrollableElement = tester.element(scrollable);
    expect(scrolledOffset, greaterThan(0));

    await tester.tap(
      find.byKey(const ValueKey<String>('location-chat-occupant-pill')),
    );
    await tester.pump();

    final roster = find.byKey(const ValueKey<String>('location-chat-roster'));
    expect(roster, findsOneWidget);
    final rosterBackdrop = tester.widget<BackdropFilter>(
      find.descendant(of: roster, matching: find.byType(BackdropFilter)),
    );
    expect(rosterBackdrop.filter, isNull);
    expect(
      rosterBackdrop.filterConfig,
      const ImageFilterConfig.blur(sigmaX: 14, sigmaY: 14, bounded: false),
    );
    expect(
      find.descendant(of: roster, matching: find.text('IN THE ROOM')),
      findsNothing,
    );
    expect(
      find.descendant(of: roster, matching: find.text('Preview Role')),
      findsOneWidget,
    );
    final rosterAvatar = tester.widget<GenesisCharacterAvatar>(
      find.descendant(
        of: roster,
        matching: find.byType(GenesisCharacterAvatar),
      ),
    );
    expect(rosterAvatar.borderRadius, GenesisAvatarRadii.character);
    expect(identical(tester.element(scrollable), scrollableElement), isTrue);
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      scrolledOffset,
    );

    await tester.tapAt(const Offset(8, 500));
    await tester.pump();
    expect(roster, findsNothing);
  });

  testWidgets('WebSocket and HTTP narrator nar_pic messages render as images', (
    tester,
  ) async {
    const imageUrl = 'assets/images/default_list_image.png';
    final websocketMessage = WorldChatroomMessage.fromNarratorMessage(
      ChatroomNarratorMessage.fromEnvelope(
        ChatroomEnvelope.fromJson({
          'type': 'nar_new_message',
          'world_id': 'world-current',
          'location_id': 'location-current',
          'global_msg_id': 1,
          'msg_id': 1,
          'location_msg_id': 1,
          'conversation_round_id': 1,
          'sender_id': 'nar_pic',
          'sender_name': 'Narrator',
          'payload': {'sender_type': 'narrator', 'content': imageUrl},
        }),
      ),
    );
    final httpMessage = WorldChatroomMessage.fromHttpMessage(
      ChatroomHttpMessage.fromJson({
        'global_message_id': 2,
        'message_id': 2,
        'location_msg_id': 2,
        'location_id': 'location-current',
        'conversation_round_id': 2,
        'sender_type': 'narrator',
        'sender_id': 'nar_pic',
        'sender_name': 'Narrator',
        'content': imageUrl,
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocationChatPanel(
          worldId: 'world-current',
          locationId: 'location-current',
          active: false,
          openingPreviewMessages: [websocketMessage, httpMessage],
        ),
      ),
    );
    await tester.pump();

    expect(websocketMessage.senderType, 'narrator');
    expect(httpMessage.senderType, 'narrator');
    expect(websocketMessage.messageType, 'image');
    expect(httpMessage.messageType, 'image');
    final renderedImageUrls = <String>{};
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('location-chat-message-list')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    for (final offset in <double>[0, position.maxScrollExtent]) {
      position.jumpTo(offset);
      await tester.pump();
      renderedImageUrls.addAll(
        tester
            .widgetList<ChatImageMessage>(find.byType(ChatImageMessage))
            .map((widget) => widget.message.imageUrl),
      );
    }
    expect(renderedImageUrls, contains(imageUrl));
    expect(
      tester
          .widget<LocationChatAnchoredMessageList>(
            find.byKey(const ValueKey('location-chat-message-list')),
          )
          .messages
          .where((message) => message.senderType == 'image'),
      hasLength(2),
    );
    expect(find.byType(ChatMessageBubble), findsNothing);
    final imageMessages = tester.widgetList<ChatImageMessage>(
      find.byType(ChatImageMessage),
    );
    expect(
      imageMessages.every(
        (widget) =>
            widget.message.senderType == 'image' &&
            widget.message.imageUrl == imageUrl,
      ),
      isTrue,
    );
    expect(find.text(imageUrl), findsNothing);
  });

  testWidgets(
    'location chat renders every narrator image and hides other image types',
    (tester) async {
      const narPicImage = 'assets/images/default_list_image.png';
      const narImage = 'assets/images/map_default/root_default.webp';
      final acceptedNarPicImage = WorldChatroomMessage.fromHttpMessage(
        ChatroomHttpMessage.fromJson({
          'type': 'narrator',
          'global_message_id': 1,
          'message_id': 1,
          'location_msg_id': 1,
          'location_id': 'location-current',
          'conversation_round_id': 1,
          'sender_type': 'narrator',
          'sender_id': 'nar_pic',
          'sender_name': 'Narrator',
          'content': narPicImage,
          'message_type': 'image',
        }),
      );
      final acceptedNarImage = WorldChatroomMessage.fromHttpMessage(
        ChatroomHttpMessage.fromJson({
          'type': 'narrator',
          'global_message_id': 2,
          'message_id': 2,
          'location_msg_id': 2,
          'location_id': 'location-current',
          'conversation_round_id': 2,
          'sender_type': 'narrator',
          'sender_id': 'nar',
          'sender_name': 'Narrator',
          'content': narImage,
          'message_type': 'image',
        }),
      );
      final blockedCharacterImage = WorldChatroomMessage.fromHttpMessage(
        ChatroomHttpMessage.fromJson({
          'type': 'character',
          'global_message_id': 3,
          'message_id': 3,
          'location_msg_id': 3,
          'location_id': 'location-current',
          'conversation_round_id': 3,
          'sender_type': 'character',
          'sender_id': 'char-1',
          'sender_name': 'Alice',
          'content': 'https://cdn.example.com/blocked.png',
          'message_type': 'image',
        }),
      );
      final unknown = WorldChatroomMessage.fromHttpMessage(
        ChatroomHttpMessage.fromJson({
          'type': 'narrator',
          'global_message_id': 4,
          'message_id': 4,
          'location_msg_id': 4,
          'location_id': 'location-current',
          'conversation_round_id': 4,
          'sender_type': 'narrator',
          'sender_id': 'nar_pic',
          'sender_name': 'Narrator',
          'content': 'https://cdn.example.com/future.bin',
          'message_type': 'future_format',
        }),
      );
      final explicitText = WorldChatroomMessage.fromHttpMessage(
        ChatroomHttpMessage.fromJson({
          'type': 'narrator',
          'global_message_id': 5,
          'message_id': 5,
          'location_msg_id': 5,
          'location_id': 'location-current',
          'conversation_round_id': 5,
          'sender_type': 'narrator',
          'sender_id': 'nar_pic',
          'sender_name': 'Narrator',
          'content': 'Visible narrator text',
          'message_type': 'text',
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            active: false,
            openingPreviewMessages: [
              acceptedNarPicImage,
              acceptedNarImage,
              blockedCharacterImage,
              unknown,
              explicitText,
            ],
          ),
        ),
      );
      await tester.pump();

      expect(acceptedNarPicImage.messageType, 'image');
      expect(acceptedNarImage.messageType, 'image');
      expect(blockedCharacterImage.messageType, 'image');
      expect(unknown.messageType, 'future_format');
      expect(explicitText.messageType, 'text');
      final imageMessages = tester
          .widget<LocationChatAnchoredMessageList>(
            find.byKey(const ValueKey('location-chat-message-list')),
          )
          .messages
          .where((message) => message.senderType == 'image');
      expect(imageMessages, hasLength(2));
      expect(
        imageMessages.map((message) => message.imageUrl),
        containsAll(<String>[narPicImage, narImage]),
      );
      final renderedImageUrls = <String>{};
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('location-chat-message-list')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      for (final offset in <double>[0, position.maxScrollExtent]) {
        position.jumpTo(offset);
        await tester.pump();
        renderedImageUrls.addAll(
          tester
              .widgetList<ChatImageMessage>(find.byType(ChatImageMessage))
              .map((widget) => widget.message.imageUrl),
        );
      }
      expect(renderedImageUrls, containsAll(<String>[narPicImage, narImage]));
      expect(find.text('Visible narrator text'), findsOneWidget);
      expect(find.text('https://cdn.example.com/blocked.png'), findsNothing);
      expect(find.text('https://cdn.example.com/future.bin'), findsNothing);
      expect(find.byType(ChatAvatar), findsNothing);
      expect(find.text('Narrator'), findsNothing);
    },
  );

  testWidgets(
    'location chat renders structured and plain enter timeline events',
    (tester) async {
      ChatCharacterMovementVm? openedMovement;
      final enter = _timelineMessage(
        messageId: 11,
        senderType: chatroomUserEnterLocationSenderType,
        payload: {
          'char_id': 'char-alice',
          'to_location_id': 'loc-cafe',
          'text': 'Alice entered the cafe.',
        },
      );
      final story = _timelineMessage(
        messageId: 12,
        senderType: chatroomStoryEventsSenderType,
        tickNo: 4,
        subTickNo: 1,
        currentTime: 'Day 2, 00:09:15',
        payload: {
          'location_id': 'location-current',
          'location_name': 'Old Station',
          'paragraphs': [
            {
              'timestamp': 'Day 2, 10:15',
              'visibility': 'public',
              'visible_to': <String>[],
              'text': 'Alice found a ticket.',
              'clue': 'The date is three years ago.',
            },
            {
              'timestamp': 'Day 2, 10:20',
              'visibility': 'public',
              'visible_to': <String>[],
              'text': 'The platform became quiet.',
              'clue': '',
            },
          ],
        },
      );
      final moved = _timelineMessage(
        messageId: 13,
        senderType: chatroomCharactersMovedSenderType,
        payload: [
          {
            'char_id': 'char-alice',
            'old_loc_id': 'loc-station',
            'to_loc_id': 'loc-cafe',
          },
          {
            'char_id': 'char-unknown',
            'old_loc_id': 'loc-cafe',
            'to_loc_id': 'loc-unknown',
          },
        ],
      );
      final invalid = _timelineMessage(
        messageId: 14,
        senderType: chatroomStoryEventsSenderType,
        payload: '{"broken":',
      );
      final plainTextEnter = _timelineMessage(
        messageId: 15,
        senderType: chatroomUserEnterLocationSenderType,
        payload: 'Dh来到了okkk。',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            active: false,
            openingPreviewMessages: [
              enter,
              story,
              moved,
              invalid,
              plainTextEnter,
            ],
            openingPreviewEntities: const [
              WorldChatroomEntity(
                id: 'char-alice',
                name: 'Alice',
                avatarUrl: '',
                type: WorldChatroomEntityType.character,
                locationId: 'loc-cafe',
                isAi: true,
              ),
            ],
            onCharactersMovedLocationTap: (movement) {
              openedMovement = movement;
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChatUserEnterLocationMessageBubble), findsNWidgets(2));
      expect(find.byType(ChatStoryEventsMessageBubble), findsOneWidget);
      expect(find.byType(ChatCharactersMovedMessageBubble), findsOneWidget);
      expect(
        find.text('Alice came to the cafe.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Dh来到了okkk。'), findsOneWidget);
      expect(find.text('Tick 4-1 · Day 2, 00:09:15'), findsNothing);
      expect(find.text('Old Station'), findsNothing);
      expect(find.text('Event'), findsNothing);
      expect(find.text('Day 2, 10:15'), findsOneWidget);
      expect(find.text('public'), findsNothing);
      expect(find.text('Alice found a ticket.'), findsOneWidget);
      expect(find.text('The date is three years ago.'), findsOneWidget);
      expect(find.text('Day 2, 10:20'), findsOneWidget);
      expect(find.text('The platform became quiet.'), findsOneWidget);
      expect(find.text('Character destinations'), findsNothing);
      expect(find.byIcon(Icons.directions_walk_rounded), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SvgPicture &&
              widget.bytesLoader.toString().contains(routeIconAsset),
        ),
        findsNWidgets(2),
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('char-unknown'), findsOneWidget);
      expect(find.text('has gone to'), findsNWidgets(2));
      expect(find.text('loc-cafe'), findsOneWidget);
      expect(find.text('loc-unknown'), findsOneWidget);
      await tester.tap(find.text('loc-unknown'));
      expect(openedMovement?.toLocationId, 'loc-unknown');
      expect(find.text('{"broken":'), findsNothing);
      expect(find.text('sub_tick'), findsNothing);
      expect(find.byType(ChatAvatar), findsNothing);
    },
  );

  testWidgets('location chat projects one V2 tick into one composite card', (
    tester,
  ) async {
    ChatCharacterMovementVm? openedMovement;
    const message = WorldChatroomMessage(
      globalMessageId: 8702,
      messageId: 101,
      locationMessageId: 29,
      conversationRoundId: '7359',
      roundOrder: 0,
      tickNo: 1,
      subTickNo: 2,
      locationId: 'location-current',
      senderType: 'tick',
      businessType: 'tick',
      senderId: 'tick',
      senderName: 'SubTick',
      content: '',
      currentTime: 'Day 1, 13:50',
      createdAt: null,
      v2TickPayload: ChatroomV2TickPayload(
        currentTime: 'Day 1, 13:50',
        tickNo: 1,
        subTickNo: 2,
        globalText: 'The promise-shaped key pulses.',
        storyEvents: [
          ChatroomV2StoryEvent(
            locationId: 'location-current',
            timestamp: 'Day 1, 13:30',
            visibility: 'public',
            visibleTo: null,
            text: 'Frost creeps toward Room 0.',
            clue: 'It spells Elara.',
          ),
        ],
        charactersMoved: [
          ChatroomV2CharacterMovement(
            characterId: 'char-2',
            oldLocationId: 'location-current',
            toLocationId: 'loc-room',
          ),
        ],
        fallbackContent: '',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocationChatPanel(
          worldId: 'world-current',
          locationId: 'location-current',
          active: false,
          openingPreviewMessages: [message],
          openingPreviewEntities: const [
            WorldChatroomEntity(
              id: 'char-2',
              name: 'Elara',
              avatarUrl: '',
              type: WorldChatroomEntityType.character,
              locationId: 'location-current',
              isAi: true,
            ),
          ],
          onCharactersMovedLocationTap: (movement) {
            openedMovement = movement;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ChatTickMessageBubble), findsOneWidget);
    expect(find.byType(ChatStoryEventsMessageBubble), findsNothing);
    expect(find.byType(ChatCharactersMovedMessageBubble), findsNothing);
    expect(find.text('Tick 1-2'), findsOneWidget);
    expect(find.text('Global'), findsNothing);
    expect(find.text('The promise-shaped key pulses.'), findsOneWidget);
    expect(find.text('Event'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ChatTickMessageBubble),
        matching: find.text('location-current'),
      ),
      findsNothing,
    );
    expect(find.text('public'), findsNothing);
    expect(find.text('Frost creeps toward Room 0.'), findsOneWidget);
    expect(find.text('Character destinations'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('chat-tick-message-bubble')),
        matching: find.text('Elara'),
      ),
      findsOneWidget,
    );
    expect(find.text('loc-room'), findsOneWidget);

    await tester.tap(find.text('loc-room'));
    expect(openedMovement?.toLocationId, 'loc-room');

    await tester.longPress(
      find.byKey(const ValueKey<String>('chat-tick-message-bubble')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
  });

  testWidgets(
    'location chat only displays the last tick in each consecutive run',
    (tester) async {
      WorldChatroomMessage tickMessage(int id, String text) {
        return _message(
          messageId: id,
          locationMessageId: id,
          content: text,
          senderType: 'tick',
          businessType: 'tick',
          tickNo: id,
          v2TickPayload: ChatroomV2TickPayload(
            currentTime: '',
            tickNo: id,
            subTickNo: 0,
            globalText: text,
            storyEvents: const [],
            charactersMoved: const [],
            fallbackContent: '',
          ),
        );
      }

      final source = [
        tickMessage(1, 'First tick in run one'),
        tickMessage(2, 'Last tick in run one'),
        _message(
          messageId: 3,
          locationMessageId: 3,
          content: 'Message between tick runs',
        ),
        tickMessage(4, 'First tick in run two'),
        tickMessage(5, 'Last tick in run two'),
      ];
      expect(
        visibleLocationChatMessagesForTesting(
          source,
        ).map((message) => message.messageId),
        [1, 2, 3, 4, 5],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'loc-1',
            active: false,
            openingPreviewMessages: source,
          ),
        ),
      );
      await tester.pump();

      final messageList = tester.widget<LocationChatAnchoredMessageList>(
        find.byKey(const ValueKey('location-chat-message-list')),
      );
      expect(messageList.messages.map((message) => message.messageId), [
        2,
        3,
        5,
      ]);
      expect(find.byType(ChatTickMessageBubble), findsNWidgets(2));
      expect(find.text('First tick in run one'), findsNothing);
      expect(find.text('Last tick in run one'), findsOneWidget);
      expect(find.text('Message between tick runs'), findsOneWidget);
      expect(find.text('First tick in run two'), findsNothing);
      expect(find.text('Last tick in run two'), findsOneWidget);
    },
  );

  testWidgets('location chat hides report for a zero-global-id V2 tick', (
    tester,
  ) async {
    const message = WorldChatroomMessage(
      messageId: 102,
      locationMessageId: 30,
      conversationRoundId: '7360',
      roundOrder: 0,
      locationId: 'location-current',
      senderType: 'tick',
      businessType: 'tick',
      senderId: 'tick',
      senderName: 'SubTick',
      content: 'Original content',
      createdAt: null,
      v2TickPayload: ChatroomV2TickPayload(
        currentTime: '',
        tickNo: 0,
        subTickNo: 0,
        globalText: '',
        storyEvents: [],
        charactersMoved: [],
        fallbackContent: 'Original content',
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: LocationChatPanel(
          worldId: 'world-current',
          locationId: 'location-current',
          active: false,
          openingPreviewMessages: [message],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Original content'), findsOneWidget);
    await tester.longPress(
      find.byKey(const ValueKey<String>('chat-tick-message-bubble')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
  });

  testWidgets(
    'location chat renders a positive-cursor tick without a typed payload',
    (tester) async {
      const message = WorldChatroomMessage(
        messageId: 103,
        locationMessageId: 31,
        conversationRoundId: '7361',
        roundOrder: 0,
        tickNo: 0,
        locationId: 'location-current',
        senderType: 'tick',
        businessType: 'tick',
        senderId: 'tick',
        senderName: 'SubTick',
        content: 'Recovered fallback Tick',
        createdAt: null,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            active: false,
            openingPreviewMessages: [message],
          ),
        ),
      );
      await tester.pump();

      expect(message.v2TickPayload, isNull);
      expect(message.isV2LocationTick, isTrue);
      expect(find.byType(ChatTickMessageBubble), findsOneWidget);
      expect(find.text('Tick 0 · Recovered fallback Tick'), findsOneWidget);
    },
  );

  testWidgets(
    'HTTP flat story_events 60 and 61 render the same event bubbles as WS',
    (tester) async {
      WorldChatroomMessage storyMessage({
        required int globalMessageId,
        required int messageId,
        required int locationMessageId,
        required String timestamp,
        required String text,
        required String clue,
      }) {
        return WorldChatroomMessage.fromHttpMessage(
          ChatroomHttpMessage.fromJson({
            'global_message_id': globalMessageId,
            'message_id': messageId,
            'location_message_id': locationMessageId,
            'location_id': 'loc_1_1_1',
            'conversation_round_id': 7003,
            'sender_type': 'story_events',
            'sender_id': 'tick',
            'sender_name': 'SubTick',
            'user_id': null,
            'content': jsonEncode({
              'location_id': 'loc_1_1_1',
              'timestamp': timestamp,
              'visibility': 'char_only',
              'visible_to': ['char_1'],
              'text': text,
              'clue': clue,
            }),
            'message_type': 'text',
            'current_time': 'Day 2, 00:09:15',
            'tick_no': 4,
            'sub_tick_no': 1,
            'created_at': '2026-08-06 20:57:54',
          }),
        );
      }

      final message60 = storyMessage(
        globalMessageId: 6140,
        messageId: 60,
        locationMessageId: 31,
        timestamp: 'Day 2, 00:08:30',
        text: '中年男人把录音带塞进桌角的旧录音机。',
        clue: '问他为什么不敢让你听完。',
      );
      final message61 = storyMessage(
        globalMessageId: 6141,
        messageId: 61,
        locationMessageId: 32,
        timestamp: 'Day 2, 00:09:00',
        text: '录音机开始播放，第三人的声音从磁带深处浮出来。',
        clue: '去辨认磁带里的耳语者。',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocationChatPanel(
            worldId: 'w_LV7MN3',
            locationId: 'loc_1_1_1',
            active: false,
            openingPreviewMessages: [message60, message61],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChatStoryEventsMessageBubble), findsNWidgets(2));
      expect(find.text('Tick 4-1 · Day 2, 00:09:15'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ChatStoryEventsMessageBubble),
          matching: find.text('loc_1_1_1'),
        ),
        findsNothing,
      );
      expect(find.text('Day 2, 00:08:30'), findsOneWidget);
      expect(find.text('中年男人把录音带塞进桌角的旧录音机。'), findsOneWidget);
      expect(find.text('问他为什么不敢让你听完。'), findsOneWidget);
      expect(find.text('Day 2, 00:09:00'), findsOneWidget);
      expect(find.text('录音机开始播放，第三人的声音从磁带深处浮出来。'), findsOneWidget);
      expect(find.text('去辨认磁带里的耳语者。'), findsOneWidget);
      expect(find.textContaining('"location_id"'), findsNothing);
    },
  );

  testWidgets('HTTP and WSS story_events share the same bubble layout', (
    tester,
  ) async {
    final httpMessage = _timelineMessage(
      messageId: 201,
      senderType: chatroomStoryEventsSenderType,
      tickNo: 5,
      subTickNo: 2,
      currentTime: 'Day 3, 08:30:00',
      payload: {
        'location_id': 'location-current',
        'timestamp': 'Day 3, 08:29:00',
        'visibility': 'public',
        'visible_to': <String>[],
        'text': 'HTTP event body.',
        'clue': 'HTTP event clue.',
      },
    );
    final websocketMessage = _wssStoryTimelineMessage(
      messageId: 202,
      locationMessageId: 202,
      tickNo: 5,
      subTickNo: 2,
      currentTime: 'Day 3, 08:30:00',
      payload: {
        'location_id': 'location-current',
        'timestamp': 'Day 3, 08:29:30',
        'visibility': 'public',
        'visible_to': <String>[],
        'text': 'WSS event body.',
        'clue': 'WSS event clue.',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocationChatPanel(
          worldId: 'world-current',
          locationId: 'location-current',
          active: false,
          openingPreviewMessages: [httpMessage, websocketMessage],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ChatStoryEventsMessageBubble), findsNWidgets(2));
    expect(find.text('Tick 5-2 · Day 3, 08:30:00'), findsNothing);
    expect(find.text('Event'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains(eventsIconAsset),
      ),
      findsNWidgets(2),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader.toString().contains(clueIconAsset),
      ),
      findsNWidgets(2),
    );
    expect(find.text('public'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ChatStoryEventsMessageBubble),
        matching: find.text('location-current'),
      ),
      findsNothing,
    );
    expect(find.text('Day 3, 08:29:00'), findsOneWidget);
    expect(find.text('HTTP event body.'), findsOneWidget);
    expect(find.text('HTTP event clue.'), findsOneWidget);
    expect(find.text('Day 3, 08:29:30'), findsOneWidget);
    expect(find.text('WSS event body.'), findsOneWidget);
    expect(find.text('WSS event clue.'), findsOneWidget);
  });

  testWidgets('location chat updates when cached selected model arrives', (
    tester,
  ) async {
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUserInfo({'uid': 'u_1'});
    final services = ServiceRegistry.build(
      config: const AppConfig(useMock: true),
      sessionStoreOverride: sessionStore,
    );

    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: const MaterialApp(
          home: LocationChatPanel(
            worldId: 'world-current',
            modelWorldId: 'world-current',
            locationId: 'location-current',
            active: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Model'), findsOneWidget);

    await sessionStore.saveUserInfo({
      'uid': 'u_1',
      'selected_model_code': 'luxury_selection_v4',
    });
    await tester.pump();

    await _pumpUntilLocationChatTest(
      tester,
      () => find.text('Luxury Selection V4.0').evaluate().isNotEmpty,
    );
    expect(find.text('Luxury Selection V4.0'), findsOneWidget);
    expect(find.text('Model'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'movement navigation is single-flight and preserves a shared service',
    (tester) async {
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('u_1');
      await sessionStore.saveAuthToken('token');
      final services = ServiceRegistry.build(
        config: const AppConfig(useMock: true),
        sessionStoreOverride: sessionStore,
      );
      final sharedService = WorldChatroomService(
        api: services.api,
        client: services.chatroom,
        messageStorage: services.chatroomMessages,
        refreshInitialSnapshotOnConnect: false,
      );
      var targetRouteBuilds = 0;
      Object? targetArguments;

      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(
            home: LocationChatPage(
              worldId: 'world-current',
              locationId: 'loc-current',
              service: sharedService,
            ),
            onGenerateRoute: (settings) {
              if (settings.name != RouteNames.locationChat) return null;
              targetRouteBuilds += 1;
              targetArguments = settings.arguments;
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const SizedBox.shrink(),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final panel = tester.widget<LocationChatPanel>(
        find.byType(LocationChatPanel),
      );
      expect(panel.leaveOnInactive, isFalse);
      const movement = ChatCharacterMovementVm(
        characterId: 'char-1',
        characterName: 'Alice',
        toLocationId: 'loc-target',
        toLocationName: 'Target',
      );
      panel.onCharactersMovedLocationTap!(movement);
      panel.onCharactersMovedLocationTap!(movement);
      await tester.pumpAndSettle();

      expect(targetRouteBuilds, 1);
      expect(
        (targetArguments as Map<String, Object?>)['world_chatroom_service'],
        same(sharedService),
      );
      expect(sharedService.isDisposed, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(sharedService.isDisposed, isFalse);
      await sharedService.dispose();
    },
  );

  test('location chat background uses no image when empty', () {
    expect(resolveLocationChatBackgroundUrlForTesting(imageUrl: ''), isEmpty);
  });

  test('location chat background suppresses the predata default image', () {
    expect(
      resolveLocationChatBackgroundUrlForTesting(
        imageUrl: 'https://cdn-001.worldo.ai/predata/location_default.webp',
      ),
      isEmpty,
    );
    expect(
      resolveLocationChatBackgroundUrlForTesting(
        imageUrl: 'assets/images/map_default/location_default.webp',
      ),
      isEmpty,
    );
  });

  test('message sender id matches only character char id', () {
    const characters = <Map<String, dynamic>>[
      {
        'char_id': 'char-role',
        'player_uid': 'user-role',
        'name': 'Character Name',
        'player_username': 'Player Username',
      },
    ];

    expect(
      resolveLocationChatMessageSenderNameForTesting(
        senderId: 'char-role',
        senderName: 'Pushed Name',
        characters: characters,
      ),
      'Character Name',
    );
    expect(
      resolveLocationChatMessageSenderNameForTesting(
        senderId: 'user-role',
        senderName: 'Pushed Name',
        characters: characters,
      ),
      'Pushed Name',
    );
  });

  test('matched character avatar resolves its image resource object', () {
    const xlUrl = 'https://example.test/character_800_600.webp';
    const smUrl = 'https://example.test/character_400_300.webp';
    const entityUrl = 'https://example.test/entity.webp';
    const characters = <Map<String, dynamic>>[
      {
        'char_id': 'char-role',
        'avatar': {
          'sm_url': smUrl,
          'xl_url': xlUrl,
          'object_key': 'uploads/character_800_600.webp',
        },
      },
    ];

    expect(
      resolveLocationChatMessageAvatarForTesting(
        senderId: 'char-role',
        characters: characters,
        entitiesById: const {
          'CHAR-ROLE': WorldChatroomEntity(
            id: 'char-role',
            name: 'Entity Role',
            avatarUrl: entityUrl,
            type: WorldChatroomEntityType.character,
            locationId: 'loc-1',
          ),
        },
      ),
      xlUrl,
    );
    expect(
      resolveLocationChatMessageAvatarForTesting(
        senderId: 'entity-role',
        characters: const <Map<String, dynamic>>[],
        entitiesById: const {
          'ENTITY-ROLE': WorldChatroomEntity(
            id: 'entity-role',
            name: 'Entity Role',
            avatarUrl: entityUrl,
            type: WorldChatroomEntityType.character,
            locationId: 'loc-1',
          ),
        },
      ),
      entityUrl,
    );
    expect(
      resolveLocationChatMessageAvatarForTesting(
        userId: 'user-role',
        senderId: 'unknown-sender',
        characters: const <Map<String, dynamic>>[],
        entitiesById: const {
          'user-role': WorldChatroomEntity(
            id: 'user-role',
            name: 'User Role',
            avatarUrl: entityUrl,
            type: WorldChatroomEntityType.player,
            locationId: 'loc-1',
          ),
        },
      ),
      entityUrl,
    );
    expect(
      resolveLocationChatMessageAvatarForTesting(
        senderId: 'missing-role',
        characters: characters,
      ),
      isEmpty,
    );
  });

  testWidgets('inactive opening preview uses entity avatar', (tester) async {
    const avatarAsset = 'assets/images/default_list_image.png';
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationChatPanel(
          worldId: 'origin-preview',
          locationId: 'loc-1',
          active: false,
          openingPreviewMessages: [
            WorldChatroomMessage(
              messageId: 0,
              conversationRoundId: 'opening-preview-0',
              roundOrder: 0,
              locationId: 'loc-1',
              senderType: 'character',
              senderId: 'char-role',
              senderName: 'Preview Role',
              content: 'Opening line.',
              createdAt: null,
            ),
          ],
          openingPreviewEntities: [
            WorldChatroomEntity(
              id: 'CHAR-ROLE',
              name: 'Preview Role',
              avatarUrl: avatarAsset,
              type: WorldChatroomEntityType.character,
              locationId: 'loc-1',
              isAi: true,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final avatar = tester.widget<ChatAvatar>(find.byType(ChatAvatar));
    expect(avatar.imageUrl, avatarAsset);
  });

  test('name list uses AI role names instead of real user names', () {
    const state = WorldChatroomState(
      entitiesByLocation: {
        'loc-1': [
          WorldChatroomEntity(
            id: 'ai-1',
            name: 'Alice',
            avatarUrl: '',
            type: WorldChatroomEntityType.character,
            locationId: 'loc-1',
            isAi: true,
          ),
          WorldChatroomEntity(
            id: 'user-1',
            name: 'Real User Role',
            avatarUrl: '',
            type: WorldChatroomEntityType.player,
            locationId: 'loc-1',
          ),
          WorldChatroomEntity(
            id: 'ai-2',
            name: 'Guide',
            avatarUrl: '',
            type: WorldChatroomEntityType.character,
            locationId: 'loc-1',
            isAi: true,
          ),
        ],
        'loc-alias': [
          WorldChatroomEntity(
            id: 'ai-1',
            name: 'Alice',
            avatarUrl: '',
            type: WorldChatroomEntityType.character,
            locationId: 'loc-alias',
            isAi: true,
          ),
        ],
      },
    );

    expect(
      resolveLocationChatAiRoleNamesForTesting(state, ['loc-1', 'loc-alias']),
      ['Alice', 'Guide'],
    );
  });

  test('message report target prefers global message id', () {
    expect(
      locationChatMessageReportTargetIdForTesting(
        ChatMessageVm(
          localId: 'local-fallback',
          clientMsgId: 'client-fallback',
          globalMessageId: 90001,
          messageId: 1001,
          locationMessageId: 101,
          senderId: 'u_peer',
          senderName: 'Peer',
          text: 'hello',
          isMe: false,
          status: 'sent',
        ),
      ),
      '90001',
    );
  });

  test('message report target is empty when global message id is absent', () {
    expect(
      locationChatMessageReportTargetIdForTesting(
        ChatMessageVm(
          localId: 'local-fallback',
          clientMsgId: 'client-fallback',
          messageId: 1001,
          locationMessageId: 101,
          senderId: 'u_peer',
          senderName: 'Peer',
          text: 'hello',
          isMe: false,
          status: 'sent',
        ),
      ),
      '',
    );

    expect(
      locationChatMessageReportTargetIdForTesting(
        ChatMessageVm(
          localId: 'local-fallback',
          clientMsgId: 'client-fallback',
          senderId: 'u_peer',
          senderName: 'Peer',
          text: 'pending',
          isMe: false,
          status: 'sending',
        ),
      ),
      '',
    );
  });

  test('report action requires a remote message with a positive global id', () {
    ChatMessageVm message({required bool isMe, required int globalId}) {
      return ChatMessageVm(
        localId: 'report-$isMe-$globalId',
        globalMessageId: globalId,
        senderId: isMe ? 'me' : 'peer',
        senderName: isMe ? 'Me' : 'Peer',
        text: 'message',
        isMe: isMe,
        status: 'sent',
      );
    }

    expect(
      locationChatMessageCanReportForTesting(
        message(isMe: false, globalId: 90001),
      ),
      isTrue,
    );
    expect(
      locationChatMessageCanReportForTesting(message(isMe: false, globalId: 0)),
      isFalse,
    );
    expect(
      locationChatMessageCanReportForTesting(
        message(isMe: true, globalId: 90001),
      ),
      isFalse,
    );
  });

  test('message local id uses location message id as queue key', () {
    final first = _message(
      messageId: 1080,
      locationMessageId: 80,
      senderType: 'narrator',
      senderId: 'nar',
      content: 'narrator 80',
    );
    final second = _message(
      messageId: 1083,
      locationMessageId: 83,
      senderType: 'narrator',
      senderId: 'nar',
      content: 'narrator 83',
    );

    expect(locationChatMessageLocalIdForTesting(first), 'location-loc-1-80');
    expect(locationChatMessageLocalIdForTesting(second), 'location-loc-1-83');
    expect(
      locationChatMessageLocalIdForTesting(first),
      isNot(locationChatMessageLocalIdForTesting(second)),
    );
  });

  test(
    'cursorless timeline uses message-id fallback while canonical uses location id',
    () {
      const first = WorldChatroomMessage(
        messageId: 1080,
        locationMessageId: 0,
        conversationRoundId: '80',
        roundOrder: 0,
        locationId: 'loc-1',
        senderType: 'story_events',
        senderId: 'sub_tick',
        senderName: 'sub_tick',
        content: '{}',
        createdAt: null,
      );
      const second = WorldChatroomMessage(
        messageId: 1083,
        locationMessageId: 83,
        conversationRoundId: '80',
        roundOrder: 0,
        locationId: 'loc-1',
        senderType: 'story_events',
        senderId: 'sub_tick',
        senderName: 'sub_tick',
        content: '{}',
        createdAt: null,
      );

      expect(locationChatMessageLocalIdForTesting(first), 'message-loc-1-1080');
      expect(locationChatMessageLocalIdForTesting(second), 'location-loc-1-83');
      expect(
        locationChatMessageLocalIdForTesting(first),
        isNot(locationChatMessageLocalIdForTesting(second)),
      );
    },
  );

  test('local hydrate ignores stale disposed provided chatroom services', () {
    final panelSource = _readLocationChatImplementationSource();
    final serviceSource = File(
      'lib/network/chatroom/world_chatroom_service.dart',
    ).readAsStringSync();

    expect(serviceSource, contains('bool get isDisposed => _disposed;'));
    expect(panelSource, contains('int _serviceGeneration = 0;'));
    expect(
      panelSource,
      contains('_startHydrateLocalMessages(provided, services);'),
    );
    expect(
      panelSource,
      isNot(contains('unawaited(_hydrateLocalMessages(provided, services))')),
    );
    expect(panelSource, contains('identical(_service, service)'));
    expect(panelSource, contains('!service.isDisposed'));
    expect(panelSource, contains('catch (error, stackTrace)'));
    expect(panelSource, contains('error is ChatroomProtocolException &&'));
    expect(
      panelSource,
      contains('_isDisposedServiceError(service, error, generation)'),
    );
    expect(panelSource, contains('hydrateLocalFailed'));
    expect(panelSource, contains('hydrateLocalStaleService'));
    expect(panelSource, contains('_serviceGeneration++;'));
  });

  test(
    'visible location chat messages keep latest continuous location id suffix',
    () {
      final visible = visibleLocationChatMessagesForTesting([
        _message(messageId: 10, locationMessageId: 1, content: 'old 1'),
        _message(messageId: 20, locationMessageId: 2, content: 'old 2'),
        _message(
          messageId: 30,
          locationMessageId: 0,
          senderType: 'tick',
          content: 'tick before gap',
        ),
        _message(messageId: 40, locationMessageId: 4, content: 'new 4'),
        _message(
          messageId: 45,
          locationMessageId: 0,
          senderType: 'tick',
          content: 'tick in visible range',
        ),
        _message(messageId: 50, locationMessageId: 5, content: 'new 5'),
      ]);

      expect(visible.map((message) => message.messageId), [40, 45, 50]);
      expect(
        locationChatMessageGapFillCursorForTesting([
          _message(messageId: 10, locationMessageId: 1, content: 'old 1'),
          _message(messageId: 40, locationMessageId: 4, content: 'new 4'),
          _message(messageId: 50, locationMessageId: 5, content: 'new 5'),
        ]),
        4,
      );
    },
  );

  test(
    'visible location chat messages render all continuous location messages',
    () {
      final source = [
        _message(messageId: 10, locationMessageId: 1, content: 'one'),
        _message(
          messageId: 15,
          locationMessageId: 0,
          senderType: 'tick',
          content: 'tick',
        ),
        _message(messageId: 20, locationMessageId: 2, content: 'two'),
        _message(messageId: 30, locationMessageId: 3, content: 'three'),
      ];

      expect(
        visibleLocationChatMessagesForTesting(
          source,
        ).map((message) => message.messageId),
        [10, 15, 20, 30],
      );
      expect(locationChatMessageGapFillCursorForTesting(source), 0);
    },
  );

  test(
    'cursorless non-tick timelines display without world-id interleaving',
    () {
      final source = [
        _message(messageId: 100, locationMessageId: 10, content: 'ten'),
        _message(
          messageId: 110,
          locationMessageId: 0,
          senderType: 'user_enter_location',
          content: 'enter',
        ),
        _message(messageId: 120, locationMessageId: 11, content: 'eleven'),
        _message(
          messageId: 130,
          locationMessageId: 0,
          senderType: 'story_events',
          content: 'story',
        ),
        _message(
          messageId: 135,
          locationMessageId: 0,
          senderType: 'characters_moved',
          content: 'moved',
        ),
        _message(messageId: 140, locationMessageId: 12, content: 'twelve'),
      ];

      expect(
        visibleLocationChatMessagesForTesting(
          source,
        ).map((message) => message.messageId),
        [110, 130, 135, 100, 120, 140],
      );
      expect(oldestLocationChatMessageIdForTesting(source), 10);
    },
  );

  test(
    'positive story_events location ids participate in the continuous window',
    () {
      final source = [
        _message(
          messageId: 58,
          locationMessageId: 30,
          senderType: 'narrator',
          content: 'Narrator before the events',
        ),
        _message(
          messageId: 60,
          locationMessageId: 31,
          senderType: 'story_events',
          content: 'First flat story event',
        ),
        _message(
          messageId: 61,
          locationMessageId: 32,
          senderType: 'story_events',
          content: 'Second flat story event',
        ),
        _message(
          messageId: 64,
          locationMessageId: 33,
          senderType: 'user_enter_location',
          content: 'Enter after the events',
        ),
      ];

      expect(
        visibleLocationChatMessagesForTesting(
          source,
        ).map((message) => message.messageId),
        [58, 60, 61, 64],
      );
      expect(locationChatMessageGapFillCursorForTesting(source), 0);
    },
  );

  test('only cursorless tick is assigned to a side of a location id gap', () {
    final source = [
      _message(messageId: 100, locationMessageId: 1, content: 'old one'),
      _message(
        messageId: 110,
        locationMessageId: 0,
        senderType: 'story_events',
        content: 'old-side event',
      ),
      _message(
        messageId: 120,
        locationMessageId: 0,
        senderType: 'tick',
        content: 'old-side tick',
      ),
      _message(messageId: 400, locationMessageId: 4, content: 'new four'),
      _message(
        messageId: 410,
        locationMessageId: 0,
        senderType: 'user_enter_location',
        content: 'new-side event',
      ),
      _message(messageId: 500, locationMessageId: 5, content: 'new five'),
    ];

    expect(
      visibleLocationChatMessagesForTesting(
        source,
      ).map((message) => message.messageId),
      [110, 410, 400, 500],
    );
    expect(locationChatMessageGapFillCursorForTesting(source), 4);
  });

  test('timeline-only queues retain every event without tick collapsing', () {
    final source = [
      _message(
        messageId: 100,
        locationMessageId: 0,
        senderType: 'story_events',
        content: 'story one',
      ),
      _message(
        messageId: 110,
        locationMessageId: 0,
        senderType: 'story_events',
        content: 'story two',
      ),
      _message(
        messageId: 120,
        locationMessageId: 0,
        senderType: 'characters_moved',
        content: 'moved',
      ),
    ];

    expect(
      visibleLocationChatMessagesForTesting(
        source,
      ).map((message) => message.messageId),
      [100, 110, 120],
    );
    expect(oldestLocationChatMessageIdForTesting(source), 0);
    expect(locationChatMessageGapFillCursorForTesting(source), 0);
  });

  test(
    'visible location chat messages include leading tick in visible window',
    () {
      final source = [
        _message(
          messageId: 0,
          locationMessageId: 0,
          senderType: 'tick',
          tickNo: 1,
          content: 'Day 1, 20:00',
        ),
        _message(messageId: 55, locationMessageId: 55, content: 'turn 19'),
        _message(messageId: 56, locationMessageId: 56, content: 'narrator'),
      ];

      expect(
        visibleLocationChatMessagesForTesting(
          source,
        ).map((message) => message.content),
        ['Day 1, 20:00', 'turn 19', 'narrator'],
      );
    },
  );

  test('visible location chat messages hide ticks without a number', () {
    final source = [
      _message(
        messageId: 1,
        locationMessageId: 0,
        senderType: 'tick',
        tickNo: 0,
        content: 'Day 1, 20:00',
      ),
      _message(messageId: 2, locationMessageId: 1, content: 'one'),
    ];

    expect(
      visibleLocationChatMessagesForTesting(
        source,
      ).map((message) => message.content),
      ['one'],
    );
  });

  test('visible location chat messages keep leading cursorless records', () {
    final source = [
      _message(
        messageId: 1,
        locationMessageId: 0,
        senderType: 'tick',
        content: 'Day 1, 20:00',
      ),
      _message(
        messageId: 5,
        locationMessageId: 0,
        senderType: 'character',
        content: 'dirty record without location id',
      ),
      _message(messageId: 45, locationMessageId: 12, content: 'first valid'),
      _message(messageId: 46, locationMessageId: 13, content: 'second valid'),
    ];

    expect(
      visibleLocationChatMessagesForTesting(
        source,
      ).map((message) => message.content),
      [
        'dirty record without location id',
        'Day 1, 20:00',
        'first valid',
        'second valid',
      ],
    );
  });

  test('visible location chat messages collapse consecutive ticks', () {
    final source = [
      _message(messageId: 1, locationMessageId: 1, content: 'one'),
      _message(
        messageId: 2,
        locationMessageId: 0,
        senderType: 'tick',
        content: 'older tick',
      ),
      _message(
        messageId: 3,
        locationMessageId: 0,
        senderType: 'tick',
        content: 'newer tick',
      ),
      _message(messageId: 4, locationMessageId: 2, content: 'two'),
    ];

    expect(
      visibleLocationChatMessagesForTesting(
        source,
      ).map((message) => message.content),
      ['one', 'newer tick', 'two'],
    );
  });

  test('visible location chat messages collapse consecutive leading ticks', () {
    final source = [
      _message(
        messageId: 1,
        locationMessageId: 0,
        senderType: 'tick',
        content: 'older leading tick',
      ),
      _message(
        messageId: 2,
        locationMessageId: 0,
        senderType: 'tick',
        content: 'newer leading tick',
      ),
      _message(messageId: 3, locationMessageId: 1, content: 'one'),
    ];

    expect(
      visibleLocationChatMessagesForTesting(
        source,
      ).map((message) => message.content),
      ['newer leading tick', 'one'],
    );
  });

  test('visible location chat messages collapse tick-only queues', () {
    final source = [
      _message(
        messageId: 1,
        locationMessageId: 0,
        senderType: 'tick',
        content: 'Tick 1',
      ),
      _message(
        messageId: 2,
        locationMessageId: 0,
        senderType: 'tick',
        content: 'Tick 2',
      ),
    ];

    expect(
      visibleLocationChatMessagesForTesting(
        source,
      ).map((message) => message.content),
      ['Tick 2'],
    );
  });

  test('canonical V2 ticks are neither filtered nor collapsed', () {
    const emptyTickPayload = ChatroomV2TickPayload(
      currentTime: '',
      tickNo: 0,
      subTickNo: 0,
      globalText: '',
      storyEvents: [],
      charactersMoved: [],
      fallbackContent: 'fallback',
    );
    final source = [
      _message(
        messageId: 10,
        locationMessageId: 1,
        content: 'first canonical tick',
        senderType: 'tick',
        businessType: 'tick',
        tickNo: 0,
        v2TickPayload: emptyTickPayload,
      ),
      _message(
        messageId: 20,
        locationMessageId: 2,
        content: 'second canonical tick',
        senderType: 'tick',
        businessType: 'tick',
        tickNo: 0,
        v2TickPayload: emptyTickPayload,
      ),
    ];

    expect(
      visibleLocationChatMessagesForTesting(
        source,
      ).map((message) => message.messageId),
      [10, 20],
    );
    expect(locationChatMessageGapFillCursorForTesting(source), 0);
    expect(source.map(locationChatMessageLocalIdForTesting), [
      'location-loc-1-1',
      'location-loc-1-2',
    ]);
  });

  test(
    'positive-cursor ticks without typed payloads are not filtered or collapsed',
    () {
      final source = [
        _message(
          messageId: 30,
          locationMessageId: 3,
          content: 'first fallback tick',
          senderType: 'tick',
          businessType: 'tick',
          tickNo: 0,
        ),
        _message(
          messageId: 40,
          locationMessageId: 4,
          content: 'second fallback tick',
          senderType: 'tick',
          businessType: 'tick',
          tickNo: 0,
        ),
      ];

      expect(source.every((message) => message.v2TickPayload == null), isTrue);
      expect(source.every((message) => message.isV2LocationTick), isTrue);
      expect(
        visibleLocationChatMessagesForTesting(
          source,
        ).map((message) => message.messageId),
        [30, 40],
      );
    },
  );

  test('cursorless active stream stays after canonical location history', () {
    final source = [
      _message(messageId: 10, locationMessageId: 1, content: 'history 1'),
      _message(messageId: 20, locationMessageId: 2, content: 'history 2'),
      _message(
        messageId: 0,
        locationMessageId: 0,
        content: 'direct stream',
        senderType: 'character',
        isLlmStreamMessage: true,
        streaming: true,
      ),
    ];

    expect(
      visibleLocationChatMessagesForTesting(
        source,
      ).map((message) => message.content),
      ['history 1', 'history 2', 'direct stream'],
    );
    expect(locationChatMessageGapFillCursorForTesting(source), 0);
  });

  test('business type selects tick and every V2 narrator image parser', () {
    const emptyTickPayload = ChatroomV2TickPayload(
      currentTime: '',
      tickNo: 0,
      subTickNo: 0,
      globalText: '',
      storyEvents: [],
      charactersMoved: [],
      fallbackContent: 'fallback',
    );
    final tick = _message(
      messageId: 10,
      locationMessageId: 1,
      content: 'fallback',
      senderType: 'character',
      businessType: 'tick',
      messageType: 'image',
      senderId: 'nar',
      v2TickPayload: emptyTickPayload,
    );
    final narratorImage = _message(
      messageId: 20,
      locationMessageId: 2,
      content: 'https://cdn.example.com/narrator.webp',
      senderType: 'narrator',
      businessType: 'narrator',
      messageType: 'image',
      senderId: 'nar',
    );
    final characterImage = _message(
      messageId: 30,
      locationMessageId: 3,
      content: 'https://cdn.example.com/character.webp',
      senderType: 'narrator',
      businessType: 'character',
      messageType: 'image',
      senderId: 'nar_pic',
    );

    expect(locationChatMessageParserForTesting(tick), isA<TickMessageParser>());
    expect(
      locationChatMessageParserForTesting(narratorImage),
      isA<ImageMessageParser>(),
    );
    expect(locationChatMessageParserForTesting(characterImage), isNull);
  });

  test('explicit V2 business envelopes never fall back to legacy senders', () {
    final unknownBusiness = _v2HttpWorldMessage(
      type: 'future_business',
      senderType: 'narrator',
      senderId: 'nar',
      messageType: 'text',
    );
    final legacyNarrator = WorldChatroomMessage.fromHttpMessage(
      ChatroomHttpMessage.fromJson({
        'global_message_id': 101,
        'message_id': 51,
        'location_message_id': 11,
        'location_id': 'loc-1',
        'conversation_round_id': 2,
        'sender_type': 'narrator',
        'sender_id': 'nar',
        'sender_name': 'Narrator',
        'content': 'Legacy narration',
        'message_type': 'text',
      }),
    );

    expect(unknownBusiness.hasExplicitBusinessType, isTrue);
    expect(unknownBusiness.businessType, 'future_business');
    expect(locationChatMessageParserForTesting(unknownBusiness), isNull);
    expect(
      locationChatMessageHasRenderableBusinessContent(unknownBusiness),
      isFalse,
    );
    expect(legacyNarrator.hasExplicitBusinessType, isFalse);
    expect(legacyNarrator.businessType, 'narrator');
    expect(
      locationChatMessageParserForTesting(legacyNarrator),
      isA<NarratorMessageParser>(),
    );
    expect(legacyNarrator.copyWith().hasExplicitBusinessType, isFalse);
  });

  test('known V2 business types reject unknown message types from HTTP', () {
    for (final businessType in const [
      'user',
      'character',
      'system',
      'narrator',
      'tick',
      chatroomUserEnterLocationSenderType,
      chatroomStoryEventsSenderType,
      chatroomCharactersMovedSenderType,
    ]) {
      final message = _v2HttpWorldMessage(
        type: businessType,
        senderType: businessType,
        senderId: businessType == 'narrator' ? 'nar' : 'sender',
        messageType: 'future_format',
      );

      expect(message.messageType, 'future_format', reason: businessType);
      expect(message.hasExplicitBusinessType, isTrue, reason: businessType);
      expect(
        locationChatMessageParserForTesting(message),
        isNull,
        reason: businessType,
      );
      expect(
        locationChatMessageHasRenderableBusinessContent(message),
        isFalse,
        reason: businessType,
      );
    }
  });

  test(
    'visible location chat messages keep rendered old data before new gaps',
    () {
      final source = [
        _message(messageId: 10, locationMessageId: 1, content: 'old 1'),
        _message(messageId: 20, locationMessageId: 2, content: 'old 2'),
        _message(messageId: 40, locationMessageId: 4, content: 'new 4'),
        _message(messageId: 50, locationMessageId: 5, content: 'new 5'),
      ];

      expect(
        visibleLocationChatMessagesWithRenderedIdsForTesting(
          source,
          renderedLocationMessageIds: const {1, 2},
        ).map((message) => message.messageId),
        [10, 20],
      );
    },
  );

  test('visible location chat messages fill holes inside rendered span', () {
    final source = [
      _message(messageId: 193, locationMessageId: 160, content: 'hi'),
      _message(
        messageId: 194,
        locationMessageId: 161,
        senderType: 'narrator',
        content: 'narrator inside rendered span',
      ),
      _message(
        messageId: 195,
        locationMessageId: 162,
        senderType: 'character',
        content: 'character',
      ),
      _message(messageId: 197, locationMessageId: 164, content: 'new gap'),
    ];

    expect(
      visibleLocationChatMessagesWithRenderedIdsForTesting(
        source,
        renderedLocationMessageIds: const {160, 162},
      ).map((message) => message.locationMessageId),
      [160, 161, 162],
    );
  });

  test('visible location chat messages release unrecoverable gaps', () {
    final source = [
      _message(messageId: 10, locationMessageId: 1, content: 'old 1'),
      _message(messageId: 20, locationMessageId: 2, content: 'old 2'),
      _message(messageId: 40, locationMessageId: 4, content: 'new 4'),
      _message(messageId: 50, locationMessageId: 5, content: 'new 5'),
    ];

    expect(
      visibleLocationChatMessagesWithRenderedIdsForTesting(
        source,
        renderedLocationMessageIds: const {1, 2},
        releasedGapKeys: const {'loc-1\u001F2\u001F4'},
      ).map((message) => message.messageId),
      [10, 20, 40, 50],
    );
  });

  testWidgets(
    'pending initial character mention stays rich while catalog loads',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      const pendingMessage = '@Ken Masters<char_ken>';
      final initialMentionCatalog = ChatMentionCatalog(
        characters: const <ChatMentionEntry>[
          ChatMentionEntry(
            id: 'char_ken',
            name: 'Ken Masters',
            type: ChatMentionType.character,
          ),
        ],
      );
      final harness = await _connectedLocationChatTestService();

      await tester.pumpWidget(
        AppServicesScope(
          services: harness.services,
          child: MaterialApp(
            home: LocationChatPanel(
              worldId: 'world-current',
              locationId: 'location-current',
              service: harness.service,
              active: false,
              leaveOnInactive: false,
              initialMessageToSend: pendingMessage,
              initialMentionCatalog: initialMentionCatalog,
            ),
          ),
        ),
      );
      await tester.pump();

      final composer = tester.widget<LocationChatComposerInput>(
        find.byType(LocationChatComposerInput),
      );
      expect(composer.controller.serializedText, pendingMessage);
      expect(composer.controller.text, isNot(pendingMessage));
      expect(composer.controller.text, isNot(contains('<')));
      expect(find.textContaining('<char_ken>'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      unawaited(harness.service.dispose());
    },
  );

  testWidgets('location chat * and @ shortcuts work at caret', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final harness = await _connectedLocationChatTestService();

    await tester.pumpWidget(
      AppServicesScope(
        services: harness.services,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: LocationChatPanel(
            worldId: 'world-current',
            locationId: 'location-current',
            service: harness.service,
            leaveOnInactive: false,
          ),
        ),
      ),
    );
    await _pumpUntilLocationChatTest(
      tester,
      () => harness.service.state.joinedLocationId == 'location-current',
    );

    final shortcut = find.byKey(
      const ValueKey<String>('chat-composer-leading-shortcut'),
    );
    final mentionShortcut = find.byKey(
      const ValueKey<String>('chat-composer-secondary-leading-shortcut'),
    );
    expect(shortcut, findsNothing);
    expect(mentionShortcut, findsNothing);

    final input = find.byKey(const ValueKey<String>('chat-composer-input'));
    final unfocusedInputWidth = tester.getSize(input).width;
    await tester.showKeyboard(input);
    await tester.pump();

    expect(shortcut, findsOneWidget);
    expect(mentionShortcut, findsOneWidget);
    expect(tester.getSize(input).width, closeTo(unfocusedInputWidth, 0.01));
    expect(tester.getSize(shortcut), const Size.square(26));
    expect(tester.getSize(mentionShortcut), const Size.square(26));
    final mentionLabelAlignment = tester.widget<Transform>(
      find.byKey(
        const ValueKey<String>(
          'chat-composer-mention-shortcut-label-alignment',
        ),
      ),
    );
    expect(mentionLabelAlignment.transform.getTranslation().y, -1);
    expect(
      tester.getTopLeft(mentionShortcut).dx,
      greaterThan(tester.getTopRight(shortcut).dx),
    );
    expect(
      tester.getTopLeft(shortcut).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(input).dy),
    );
    expect(
      find.descendant(
        of: shortcut,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.size == const Size.square(12),
        ),
      ),
      findsOneWidget,
    );

    final composer = tester.widget<ChatComposer>(find.byType(ChatComposer));
    composer.controller.value = const TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tester.tap(shortcut);
    await tester.pump();

    expect(composer.controller.text, 'he*llo');
    expect(
      composer.controller.selection,
      const TextSelection.collapsed(offset: 3),
    );
    expect(composer.focusNode?.hasFocus, isTrue);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final composerTopWithKeyboard = tester
        .getTopLeft(find.byType(ChatComposer))
        .dy;

    await tester.tap(mentionShortcut);
    await tester.pump();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('location-chat-mention-sheet')),
      findsOneWidget,
    );
    expect(composer.controller.text, 'he*@llo');
    expect(
      composer.controller.selection,
      const TextSelection.collapsed(offset: 4),
    );
    expect(
      tester.getTopLeft(find.byType(ChatComposer)).dy,
      closeTo(composerTopWithKeyboard, 0.1),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('location-chat-mention-collapse')),
    );
    await tester.pumpAndSettle();

    for (final keyboardInset in <double>[100, 200, 299]) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
      await tester.pump();
      expect(
        tester.getTopLeft(find.byType(ChatComposer)).dy,
        closeTo(composerTopWithKeyboard, 0.1),
      );
    }

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(ChatComposer)).dy,
      closeTo(composerTopWithKeyboard, 0.1),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(ChatComposer)).dy,
      greaterThan(composerTopWithKeyboard),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(harness.service.dispose());
  });
}

WorldChatroomMessage _message({
  required int messageId,
  required int locationMessageId,
  required String content,
  String senderType = 'user',
  String businessType = '',
  String locationId = 'loc-1',
  String? conversationRoundId,
  int? tickNo,
  String? senderId,
  String messageType = 'text',
  bool isLlmStreamMessage = false,
  bool streaming = false,
  ChatroomV2TickPayload? v2TickPayload,
}) {
  return WorldChatroomMessage(
    messageId: messageId,
    locationMessageId: locationMessageId,
    conversationRoundId: conversationRoundId ?? '$messageId',
    roundOrder: 0,
    tickNo: tickNo ?? (senderType == 'tick' ? messageId : 0),
    locationId: locationId,
    senderType: senderType,
    businessType: businessType,
    senderId: senderId ?? (senderType == 'tick' ? 'tick' : 'u_peer'),
    senderName: senderType == 'tick' ? 'Time' : 'Peer',
    content: content,
    messageType: messageType,
    createdAt: null,
    streaming: streaming,
    isLlmStreamMessage: isLlmStreamMessage,
    v2TickPayload: v2TickPayload,
  );
}

WorldChatroomMessage _v2HttpWorldMessage({
  required String type,
  required String senderType,
  required String senderId,
  required String messageType,
}) {
  return WorldChatroomMessage.fromHttpMessage(
    ChatroomHttpMessage.fromV2Json({
      'type': type,
      'stream_type': '',
      'ts': 1786340797000,
      'world_id': 'world-1',
      'session_id': 'session-1',
      'global_message_id': 100,
      'message_id': 50,
      'location_message_id': 10,
      'location_id': 'loc-1',
      'conversation_round_id': 1,
      'sender_type': senderType,
      'sender_id': senderId,
      'sender_name': 'Sender',
      'user_id': '',
      'client_msg_id': '',
      'message_type': messageType,
      'min_app_version': 0,
      'created_at': '2026-08-10 11:06:37',
      'payload': const <String, dynamic>{'content': 'Payload'},
      'err_no': 0,
      'err_msg': '',
    }),
  );
}

WorldChatroomMessage _timelineMessage({
  required int messageId,
  required String senderType,
  required Object payload,
  int tickNo = 0,
  int subTickNo = 0,
  String currentTime = '',
}) {
  return WorldChatroomMessage.fromHttpMessage(
    ChatroomHttpMessage.fromJson({
      'global_message_id': 90000 + messageId,
      'message_id': messageId,
      'location_msg_id': messageId,
      'location_id': 'location-current',
      'conversation_round_id': messageId,
      'sender_type': senderType,
      'sender_id': 'sub_tick',
      'sender_name': 'sub_tick',
      'tick_no': tickNo,
      'sub_tick_no': subTickNo,
      'content': payload is String ? payload : jsonEncode(payload),
      'current_time': currentTime,
    }),
  );
}

WorldChatroomMessage _wssStoryTimelineMessage({
  required int messageId,
  required int locationMessageId,
  required int tickNo,
  required int subTickNo,
  required String currentTime,
  required Map<String, dynamic> payload,
}) {
  final envelope = ChatroomEnvelope.fromJson({
    'type': chatroomStoryEventsSenderType,
    'schema_version': 1,
    'event_id': 'event-$messageId',
    'ts': 1786062600000,
    'world_id': 'world-current',
    'location_id': 'location-current',
    'global_msg_id': 90000 + messageId,
    'msg_id': messageId,
    'location_msg_id': locationMessageId,
    'conversation_round_id': messageId,
    'sender_id': 'sub_tick',
    'sender_name': 'sub_tick',
    'tick_no': tickNo,
    'sub_tick_no': subTickNo,
    'current_time': currentTime,
    'payload': payload,
  });
  return WorldChatroomMessage.fromStoryEventsMessage(
    ChatroomStoryEventsMessage.fromEnvelope(envelope),
  );
}

Future<void> _pumpUntilLocationChatTest(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await tester.pump();
  }
  fail('Timed out pumping location chat test state.');
}

Future<
  ({
    AppServices services,
    WorldChatroomService service,
    _LocationChatTestSocket socket,
  })
>
_mountCompletedReplyActionPanel(
  WidgetTester tester, {
  required _LocationChatReplyHttpTransport backend,
  bool isMember = true,
}) async {
  final harness = await _connectedLocationChatTestService(
    replyTransport: backend,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(harness.service.dispose());
  });
  await tester.pumpWidget(
    AppServicesScope(
      services: harness.services,
      child: MaterialApp(
        scrollBehavior: const GenesisScrollBehavior(),
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: LocationChatPanel(
          worldId: 'world-current',
          locationId: 'location-current',
          service: harness.service,
          isMember: isMember,
          leaveOnInactive: false,
          messageQueueInitializationCovered: true,
        ),
      ),
    ),
  );
  await _pumpUntilLocationChatTest(
    tester,
    () => harness.service.state.joinedLocationId == 'location-current',
  );
  backend.seedReplyRound();
  harness.socket.serverV2UserMessage(messageId: 301);
  harness.socket.serverV2StreamFrame(
    streamType: 'llm_stream_end',
    roundId: 301,
    messageId: 302,
    content: 'Original reply.',
  );
  harness.socket.serverEndConversationRound(roundId: 301);
  await _pumpUntilLocationChatTest(
    tester,
    () => tester
        .widget<LocationChatAnchoredMessageList>(
          find.byType(LocationChatAnchoredMessageList),
        )
        .editEnabled,
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<
  ({
    AppServices services,
    WorldChatroomService service,
    _LocationChatTestSocket socket,
  })
>
_connectedLocationChatTestService({
  Duration ackTimeout = const Duration(seconds: 12),
  HttpTransport? replyTransport,
}) async {
  final sessionStore = MemoryUserSessionStore();
  await sessionStore.saveUid('user-1');
  await sessionStore.saveAuthToken('token-1');
  final services = ServiceRegistry.build(
    config: const AppConfig(useMock: true),
    sessionStoreOverride: sessionStore,
    chatroomMessagesOverride: MemoryChatroomMessageStorage(),
  );
  final socket = _LocationChatTestSocket();
  final client = ChatroomClient(
    wsBaseUrl: 'ws://localhost:8082/aitown-chat/ws',
    sessionStore: sessionStore,
    transport: _LocationChatTestTransport(socket),
    ackTimeout: ackTimeout,
    autoHeartbeat: false,
    handshakeHeaderSigner: (_, headers) async => <String, String>{
      ...headers,
      'X-App-Version': '0.3.4',
    },
  );
  final service = WorldChatroomService(
    api: replyTransport == null
        ? services.api
        : GenesisApi(
            transport: replyTransport,
            useMock: false,
            sessionStore: sessionStore,
            appHeaderProvider: () async => const {},
          ),
    client: client,
    replyActionStorage: MemoryChatroomReplyActionStorage(),
    inspirationStorage: MemoryChatroomInspirationStorage(),
    messageStorage: MemoryChatroomMessageStorage(),
    refreshInitialSnapshotOnConnect: false,
  );
  await service.connect(
    worldId: 'world-current',
    identity: const ChatroomConnectionIdentity(
      userId: 'user-1',
      senderId: 'user-1',
      senderName: 'Player One',
    ),
  );
  return (services: services, service: service, socket: socket);
}

_LocationChatAnalyticsClient _enableLocationChatAnalyticsForTesting({
  int initialMessageSentCount = 0,
}) {
  final client = _LocationChatAnalyticsClient();
  var messageSentCount = initialMessageSentCount;
  FirebaseAnalyticsMonitoring.setClientForTesting(client);
  FirebaseAnalyticsMonitoring.setOnceEventStoreForTesting(
    _LocationChatOnceEventStore(),
  );
  FirebaseAnalyticsMonitoring.setEnabledForTesting(true);
  FirebaseAnalyticsMonitoring.setReadinessForTesting(Future<void>.value());
  FirebaseAnalyticsMonitoring.setDeviceIdReaderForTesting(
    () async => 'test-device-id',
  );
  FirebaseAnalyticsMonitoring.setMessageSentCountIncrementerForTesting(
    () async {
      messageSentCount += 1;
      return messageSentCount;
    },
  );
  return client;
}

class _LocationChatAnalyticsClient implements AppAnalyticsClient {
  final List<_LocationChatAnalyticsEvent> events =
      <_LocationChatAnalyticsEvent>[];

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    events.add(
      _LocationChatAnalyticsEvent(name, parameters ?? const <String, Object>{}),
    );
  }
}

class _LocationChatOnceEventStore implements FirebaseAnalyticsOnceEventStore {
  final Set<String> sentEvents = <String>{};

  @override
  Future<void> markSent(String eventName) async {
    sentEvents.add(eventName);
  }

  @override
  Future<bool> wasSent(String eventName) async {
    return sentEvents.contains(eventName);
  }
}

class _LocationChatAnalyticsEvent {
  const _LocationChatAnalyticsEvent(this.name, this.parameters);

  final String name;
  final Map<String, Object> parameters;

  @override
  bool operator ==(Object other) {
    return other is _LocationChatAnalyticsEvent &&
        other.name == name &&
        _mapsEqual(other.parameters, parameters);
  }

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAllUnordered(parameters.entries));
}

bool _mapsEqual(Map<String, Object> first, Map<String, Object> second) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    if (second[entry.key] != entry.value) return false;
  }
  return true;
}

class _ThrowingLocationChatService extends WorldChatroomService {
  _ThrowingLocationChatService(AppServices services)
    : super(
        api: services.api,
        client: services.chatroom,
        messageStorage: services.chatroomMessages,
        refreshInitialSnapshotOnConnect: false,
      );

  int sendAttempts = 0;

  @override
  WorldChatroomState get state => const WorldChatroomState(
    connected: true,
    joinedLocationId: 'location-sync-failure',
  );

  @override
  ChatroomConnectionIdentity? get identity => const ChatroomConnectionIdentity(
    userId: 'user-1',
    senderId: 'user-1',
    senderName: 'Player One',
  );

  @override
  Future<void> hydrateLocalMessages({
    required String worldId,
    required String locationId,
    String? ownerUid,
    Iterable<String> locationAliases = const <String>[],
  }) async {}

  @override
  Future<List<WorldChatroomMessage>> refreshLatestMessages({
    required String locationId,
    int limit = 20,
    bool emitLatestFetched = true,
  }) async => const <WorldChatroomMessage>[];

  @override
  ChatroomSendHandle sendMessage(String text, {String? clientMsgId}) {
    sendAttempts += 1;
    throw StateError('synchronous send failure');
  }
}

/// Authoritative test backend: batch updates are only visible after history reload.
class _LocationChatReplyHttpTransport implements HttpTransport {
  final messages = <Map<String, Object?>>[];
  final batches = <Map<String, dynamic>>[];
  final rangeRequests = <Map<String, String>>[];
  final requests = <TransportRequest>[];
  final cards = <Map<String, Object?>>[];
  Completer<void>? batchBarrier;
  Completer<void>? selectionBarrier;
  bool selectionFails = false;
  int selectedCardId = 0;
  final inspirationRequests = <Map<String, dynamic>>[];
  final selectionRequests = <Map<String, dynamic>>[];

  void seedGoOnReply() {
    messages.add(
      _messageJson(
        402,
        'character',
        'char-1',
        'The story continues.',
        roundId: 401,
        locationMessageId: 303,
      ),
    );
  }

  void beginCandidate() {
    cards.addAll([
      _cardJson(501, 1, 'succeeded', 'Original reply.'),
      _cardJson(502, 2, 'generating', ''),
    ]);
  }

  Map<String, Object?> _cardJson(
    int id,
    int index,
    String generation,
    String content,
  ) => {
    'card_id': id,
    'card_index': index,
    'is_original': index == 1,
    'generation_state': generation,
    'can_edit': generation == 'succeeded',
    'can_delete': generation == 'succeeded',
    'messages': generation != 'succeeded'
        ? []
        : [
            {
              'type': 'character',
              'stream_type': '',
              'world_id': 'world-current',
              'location_id': 'location-current',
              'conversation_round_id': 301,
              'global_message_id': id == 501 ? 90302 : 90502,
              'card_id': id,
              'card_message_index': 1,
              'user_id': 'user-1',
              'sender_type': 'character',
              'sender_id': 'char-1',
              'sender_name': 'Alice',
              'message_type': 'text',
              'payload': {'content': content},
            },
          ],
    'billing': {'status': index == 1 ? 'not_required' : 'reserved'},
    'created_at': '2026-09-08',
  };

  void seedReplyRound() {
    messages.addAll([
      _messageJson(301, 'user', 'user-1', 'message 301'),
      _messageJson(302, 'character', 'char-1', 'Original reply.'),
    ]);
  }

  Map<String, Object?> _messageJson(
    int id,
    String type,
    String sender,
    String text, {
    int roundId = 301,
    int? locationMessageId,
  }) => {
    'type': type,
    'stream_type': '',
    'world_id': 'world-current',
    'location_id': 'location-current',
    'conversation_round_id': roundId,
    'global_message_id': 90000 + id,
    'message_id': id,
    'location_message_id': locationMessageId ?? id,
    if (type == 'user') 'user_id': 'user-1',
    'sender_type': type,
    'sender_id': sender,
    'sender_name': type == 'user' ? 'Player One' : 'Alice',
    'message_type': 'text',
    'created_at': '2026-09-08 10:00:00',
    'payload': {'content': text},
  };

  TransportResponse _ok(Object data) => TransportResponse(
    statusCode: 200,
    headers: const {},
    body: jsonEncode({'err_no': 0, 'err_msg': '', 'data': data}),
  );

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    if (request.uri.path.endsWith('/inspiration')) {
      final body =
          jsonDecode(utf8.decode(request.bodyBytes!)) as Map<String, dynamic>;
      inspirationRequests.add(body);
      final card = body['card_id'] as int? ?? selectedCardId;
      return _ok({
        'conversation_round_id': body['conversation_round_id'],
        'card_id': card,
        'source_card_id': card == 501 ? 0 : card,
        'messages': [
          'Good job!',
          'A different suggestion.',
          'Try another path.',
          'One more idea.',
        ],
        'gateway_request_id': '',
      });
    }
    if (request.uri.path.endsWith('/llm-messages/select')) {
      final body =
          jsonDecode(utf8.decode(request.bodyBytes!)) as Map<String, dynamic>;
      selectionRequests.add(body);
      await selectionBarrier?.future;
      if (selectionFails) {
        return TransportResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({
            'err_no': 5002,
            'err_msg': 'Selection failed',
            'data': {},
          }),
        );
      }
      selectedCardId = body['card_id'] as int;
      return _ok({
        'conversation_round_id': body['conversation_round_id'],
        'selected_card_id': selectedCardId,
        'confirmed': true,
        'start_conversation_round_id': 301,
        'end_conversation_round_id': 301,
        'newest_message_id': 302,
      });
    }

    if (request.uri.path.endsWith('/llm-messages/cards')) {
      final round = int.parse(
        request.uri.queryParameters['conversation_round_id']!,
      );
      if (round != 301) {
        return _ok({
          'conversation_round_id': round,
          'original_card_id': 0,
          'selected_card_id': 0,
          'active_card_id': 0,
          'confirmed': false,
          'can_regenerate': true,
          'can_confirm': false,
          'list': [],
          'total': 0,
        });
      }
      return _ok({
        'conversation_round_id': 301,
        'original_card_id': cards.isEmpty ? 0 : 501,
        'selected_card_id': selectedCardId,
        'active_card_id': selectedCardId > 0
            ? selectedCardId
            : cards.isEmpty
            ? 0
            : 502,
        'confirmed': selectedCardId > 0,
        'can_regenerate': true,
        'can_confirm': cards.isNotEmpty,
        'list': cards,
        'total': cards.length,
      });
    }
    if (request.uri.path.endsWith('/llm-messages/batch')) {
      final body =
          jsonDecode(utf8.decode(request.bodyBytes!)) as Map<String, dynamic>;
      batches.add(body);
      if (batchBarrier case final barrier?) await barrier.future;
      for (final raw in body['operations'] as List) {
        final operation = raw as Map<String, dynamic>;
        if (operation['action'] == 'delete') {
          messages.removeWhere(
            (message) =>
                message['global_message_id'] == operation['global_message_id'],
          );
        } else {
          final message = messages.singleWhere(
            (message) =>
                message['global_message_id'] == operation['global_message_id'],
          );
          message['payload'] = {'content': operation['content']};
        }
      }
      return _ok({
        'start_conversation_round_id': 301,
        'end_conversation_round_id': 301,
        'newest_message_id': messages.isEmpty
            ? 0
            : messages.last['location_message_id'],
      });
    }
    if (request.uri.path.endsWith('/api/v2/messages')) {
      if (request.uri.queryParameters.containsKey(
        'start_conversation_round_id',
      )) {
        rangeRequests.add(request.uri.queryParameters);
      }
      final start = int.tryParse(
        request.uri.queryParameters['start_conversation_round_id'] ?? '',
      );
      final end = int.tryParse(
        request.uri.queryParameters['end_conversation_round_id'] ?? '',
      );
      return _ok({
        'messages': messages.where((message) {
          final round = message['conversation_round_id'] as int;
          return (start == null || round >= start) &&
              (end == null || round <= end);
        }).toList(),
        'has_more': false,
        'newest_message_id': messages.isEmpty
            ? 0
            : messages.last['location_message_id'],
      });
    }
    return LocalMockGenesisTransport.instance.send(request);
  }
}

class _LocationChatTestTransport implements ChatroomSocketTransport {
  const _LocationChatTestTransport(this.socket);

  final _LocationChatTestSocket socket;

  @override
  Future<ChatroomSocket> connect(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    return socket;
  }
}

class _LocationChatTestSocket implements ChatroomSocket {
  final _messages = StreamController<String>.broadcast();
  final List<Map<String, dynamic>> _sentFrames = <Map<String, dynamic>>[];

  int get sendMessageCount =>
      _sentFrames.where((frame) => frame['type'] == 'send_message').length;

  List<Map<String, dynamic>> replyActionFrames(String type) =>
      _sentFrames.where((frame) => frame['type'] == type).toList();

  void serverReplyActionAck(
    String requestType, {
    required int roundId,
    int errNo = 0,
    String errMsg = '',
    Map<String, Object?> payload = const {},
  }) {
    final request = replyActionFrames(requestType).last;
    _serverFrame('ack', {
      'world_id': 'world-current',
      'location_id': 'location-current',
      'session_id': 'session-1',
      'conversation_round_id': roundId,
      'user_id': 'user-1',
      'client_msg_id': request['client_msg_id'],
      'payload': payload,
      'err_no': errNo,
      'err_msg': errMsg,
    });
  }

  void serverCandidateStream({
    required String streamType,
    String content = '',
    int? seq,
  }) {
    _serverFrame('llm_card_stream', {
      'stream_type': streamType,
      'world_id': 'world-current',
      'location_id': 'location-current',
      'user_id': 'user-1',
      'conversation_round_id': 301,
      'global_message_id': 90502,
      'sender_type': 'character',
      'sender_id': 'char-1',
      'sender_name': 'Alice',
      'payload': {
        'card_id': 502,
        'card_message_index': 1,
        if (seq != null) 'seq': seq,
        'content': content,
      },
      'err_no': 0,
      'err_msg': '',
    });
  }

  void serverV2AckForLatestSend({required int errNo}) {
    final frame = _sentFrames.lastWhere(
      (candidate) => candidate['type'] == 'send_message',
    );
    final clientMsgId = '${frame['client_msg_id'] ?? ''}';
    _serverFrame('ack', <String, Object?>{
      'stream_type': '',
      'ts': 1786327200000,
      'world_id': 'world-current',
      'location_id': 'location-current',
      'session_id': 'session-1',
      'sender_type': '',
      'sender_id': '',
      'sender_name': '',
      'user_id': 'user-1',
      'client_msg_id': clientMsgId,
      'message_type': '',
      'min_app_version': 0,
      'created_at': '',
      'payload': const <String, Object?>{},
      'err_no': errNo,
      'err_msg': errNo == 0 ? '' : 'rejected',
    });
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> send(String message) async {
    final frame = jsonDecode(message) as Map<String, dynamic>;
    _sentFrames.add(frame);
    if (frame['type'] != 'join') return;
    final clientMsgId = '${frame['client_msg_id'] ?? ''}';
    scheduleMicrotask(() {
      _serverFrame('ack', {
        'stream_type': '',
        'world_id': 'world-current',
        'session_id': 'session-1',
        'location_id': frame['location_id'],
        'user_id': 'user-1',
        'client_msg_id': clientMsgId,
        'payload': {'client_msg_id': clientMsgId},
        'err_no': 0,
        'err_msg': '',
      });
    });
  }

  @override
  Future<void> close([int? code, String? reason]) {
    unawaited(_messages.close());
    return Future<void>.value();
  }

  void serverUserMessage({required int messageId}) {
    _serverFrame('user_message', {
      'world_id': 'world-current',
      'session_id': 'session-1',
      'location_id': 'location-current',
      'global_msg_id': 90000 + messageId,
      'msg_id': messageId,
      'location_msg_id': messageId,
      'conversation_round_id': messageId,
      'payload': {
        'round_order': 1,
        'sender_type': 'user',
        'sender_id': 'user-1',
        'sender_name': 'Player One',
        'content': 'message $messageId',
        'created_at': 1717300000000 + messageId,
      },
    });
  }

  void serverV2UserMessage({
    required int messageId,
    String clientMsgId = '',
    String? content,
  }) {
    _serverFrame('user', {
      'stream_type': '',
      'ts': 1786327200000 + messageId,
      'world_id': 'world-current',
      'session_id': 'session-1',
      'location_id': 'location-current',
      'global_message_id': 90000 + messageId,
      'message_id': messageId,
      'location_message_id': messageId,
      'conversation_round_id': messageId,
      'sender_type': 'user',
      'sender_id': 'user-1',
      'sender_name': 'Player One',
      'user_id': 'user-1',
      'client_msg_id': clientMsgId,
      'message_type': 'text',
      'min_app_version': 0,
      'created_at': '2026-08-10 10:00:00',
      'payload': <String, Object?>{'content': content ?? 'message $messageId'},
      'err_no': 0,
      'err_msg': '',
    });
  }

  void serverV2Tick({
    required int messageId,
    required int locationMessageId,
    required String globalText,
  }) {
    _serverFrame('tick', {
      'stream_type': '',
      'ts': 1786327200000 + messageId,
      'world_id': 'world-current',
      'session_id': 'session-1',
      'location_id': 'location-current',
      'global_message_id': 90000 + messageId,
      'message_id': messageId,
      'location_message_id': locationMessageId,
      'conversation_round_id': messageId,
      'sender_type': 'tick',
      'sender_id': 'tick',
      'sender_name': 'Time',
      'user_id': '',
      'client_msg_id': '',
      'message_type': 'text',
      'min_app_version': 0,
      'created_at': '2026-08-10 10:00:00',
      'payload': <String, Object?>{
        'current_time': 'Day 8, 10:00',
        'tick_no': 0,
        'sub_tick_no': 0,
        'global': globalText,
        'story_events': <Object?>[],
        'characters_moved': <Object?>[],
      },
      'err_no': 0,
      'err_msg': '',
    });
  }

  void serverWaitingConversationRound({required int roundId}) {
    _serverFrame('waiting_conversation_round', {
      'stream_type': '',
      'ts': 1785890000000,
      'world_id': 'world-current',
      'session_id': 'session-1',
      'location_id': 'location-current',
      'conversation_round_id': roundId,
      'user_id': 'user-1',
      'payload': <String, Object?>{},
      'err_no': 0,
      'err_msg': '',
    });
  }

  void serverEndConversationRound({required int roundId}) {
    _serverFrame('end_conversation_round', {
      'stream_type': '',
      'ts': 1785890001000,
      'world_id': 'world-current',
      'session_id': 'session-1',
      'location_id': 'location-current',
      'conversation_round_id': roundId,
      'user_id': 'user-1',
      'payload': <String, Object?>{},
      'err_no': 0,
      'err_msg': '',
    });
  }

  void serverV2StreamFrame({
    required String streamType,
    required int roundId,
    required int messageId,
    int? locationMessageId,
    int? seq,
    String content = '',
  }) {
    _serverFrame('character', {
      'stream_type': streamType,
      'ts': 1785890000000 + messageId,
      'world_id': 'world-current',
      'session_id': 'session-1',
      'location_id': 'location-current',
      'global_message_id': 90000 + messageId,
      'message_id': messageId,
      'location_message_id': locationMessageId ?? messageId,
      'conversation_round_id': roundId,
      'sender_type': 'character',
      'sender_id': 'char-1',
      'sender_name': 'Alice',
      'user_id': '',
      'client_msg_id': '',
      'message_type': 'text',
      'min_app_version': 0,
      'created_at': '2026-08-12 10:00:00',
      'payload': <String, Object?>{
        if (seq != null) 'seq': seq,
        'content': content,
      },
      'err_no': 0,
      'err_msg': '',
    });
  }

  void serverLlmStreamStart({required int messageId}) {
    _serverFrame('llm_stream_start', {
      'world_id': 'world-current',
      'session_id': 'session-1',
      'location_id': 'location-current',
      'global_msg_id': 90000 + messageId,
      'msg_id': messageId,
      'location_msg_id': messageId,
      'conversation_round_id': messageId,
      'payload': {
        'sender_id': 'char-1',
        'sender_name': 'Alice',
        'round_order': 1,
      },
    });
  }

  void serverLlmChunk({required int messageId, required String content}) {
    _serverFrame('llm_chunk', {
      'world_id': 'world-current',
      'session_id': 'session-1',
      'location_id': 'location-current',
      'global_msg_id': 90000 + messageId,
      'msg_id': messageId,
      'location_msg_id': messageId,
      'conversation_round_id': messageId,
      'payload': {'sender_id': 'char-1', 'seq': 1, 'content': content},
    });
  }

  void _serverFrame(String type, Map<String, Object?> fields) {
    _messages.add(jsonEncode(<String, Object?>{'type': type, ...fields}));
  }
}
