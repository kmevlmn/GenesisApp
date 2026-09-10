import 'dart:async';
import 'dart:convert';

import 'package:genesis_flutter_android/components/discuss/discuss_dark_style.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/bootstrap/app_services_scope.dart';
import 'package:genesis_flutter_android/app/bootstrap/service_registry.dart';
import 'package:genesis_flutter_android/app/config/app_config.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/chatroom/chatroom_message_storage.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/pages/discuss/discuss_page.dart';
import 'package:genesis_flutter_android/pages/discuss/post_detail_page.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';
import 'package:genesis_flutter_android/components/discuss/origin_discuss_list.dart';
import 'package:genesis_flutter_android/components/discuss/story_badge.dart';

void main() {
  testWidgets('hides attached images on discuss and post detail pages', (
    tester,
  ) async {
    const attachedImage = 'assets/images/map_default/root_default.webp';
    final transport = _DiscussPageTransport(
      includeReplies: true,
      includeImages: true,
    );

    await tester.pumpWidget(
      AppServicesScope(
        services: _servicesWithTransport(transport),
        child: _discussTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.image(const AssetImage(attachedImage)), findsNothing);

    await tester.tap(find.text('Reply User: Reply target'));
    await tester.pumpAndSettle();

    expect(find.text('Post Detail'), findsOneWidget);
    expect(find.text('Reply target'), findsOneWidget);
    expect(find.image(const AssetImage(attachedImage)), findsNothing);
  });

  testWidgets('shows skeleton instead of progress indicator while loading', (
    tester,
  ) async {
    final originGate = Completer<void>();
    final transport = _DiscussPageTransport(originGate: originGate.future);

    await tester.pumpWidget(
      AppServicesScope(
        services: _servicesWithTransport(transport),
        child: _discussTestApp(),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('discuss-page-loading-skeleton')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Loading stays static even while the network response remains pending.
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    final bones = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('discuss-page-loading-skeleton')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).borderRadius != null,
        ),
      ),
    );
    expect(bones, isNotEmpty);
    for (final bone in bones) {
      final decoration = bone.decoration as BoxDecoration;
      expect(decoration.color, const Color(0x1FFFFFFF));
      expect(decoration.gradient, isNull);
    }

    originGate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('discuss-page-loading-skeleton')),
      findsNothing,
    );
    expect(find.text('Discuss item 1'), findsOneWidget);
  });

  testWidgets('loads more discuss items on scroll without View More', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);
    addTearDown(tester.view.reset);

    final transport = _DiscussPageTransport();
    await tester.pumpWidget(
      AppServicesScope(
        services: _servicesWithTransport(transport),
        child: _discussTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('View More >'), findsNothing);
    expect(find.text('Discuss item 1'), findsOneWidget);
    expect(find.text('Discuss item 20'), findsOneWidget);
    expect(
      transport.discussRequests.map((request) => request.uri.queryParameters),
      contains(
        allOf(
          containsPair('pn', '1'),
          containsPair('rn', '20'),
          containsPair('biz_id', 'o_auto'),
        ),
      ),
    );

    // Pagination requires a user drag near the end, not programmatic scrolling.
    await tester.ensureVisible(find.text('Discuss item 20'));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView).first);
    final scrollController = list.controller!;
    scrollController.jumpTo(scrollController.position.maxScrollExtent - 300);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(find.text('View More >'), findsNothing);
    expect(find.text('Discuss item 21'), findsOneWidget);
    expect(
      transport.discussRequests.map((request) => request.uri.queryParameters),
      contains(
        allOf(
          containsPair('pn', '2'),
          containsPair('rn', '20'),
          containsPair('biz_id', 'o_auto'),
        ),
      ),
    );
  });

  testWidgets('post input floats at the bottom of the page', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);

    final transport = _DiscussPageTransport();
    await tester.pumpWidget(
      AppServicesScope(
        services: _servicesWithTransport(transport),
        child: _discussTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.bottomNavigationBar, isNull);

    final bar = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(
              const ValueKey<String>('discuss-page-post-input-bar'),
            ),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(bar.color, DiscussDarkColors.background);
    expect(scaffold.backgroundColor, DiscussDarkColors.background);
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
      DiscussDarkColors.background,
    );
    expect(
      tester.widget<Text>(find.text('Discuss item 1')).style?.color,
      DiscussDarkColors.primary,
    );

    final barRect = tester.getRect(
      find.byKey(const ValueKey<String>('discuss-page-post-input-bar')),
    );
    final inputRect = tester.getRect(find.text('Write a post'));
    expect(barRect.bottom, 760);
    expect(inputRect.bottom, greaterThan(660));
    expect(inputRect.bottom, lessThanOrEqualTo(760 - 34));
  });

  testWidgets('reply preview opens post detail before showing composer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);
    addTearDown(tester.view.reset);

    final transport = _DiscussPageTransport(includeReplies: true);
    await tester.pumpWidget(
      AppServicesScope(
        services: _servicesWithTransport(transport),
        child: _discussTestApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DiscussStoryBadge), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('discuss-page-reply-preview-dis_1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Post Detail'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('post-detail-comment-input-bar')),
      findsOneWidget,
    );
    expect(find.text('Write a reply'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      DiscussDarkColors.background,
    );
    expect(
      tester.widget<Text>(find.text('Reply target')).style?.color,
      DiscussDarkColors.primary,
    );
  });

  testWidgets('comment action row shows report menu', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);
    addTearDown(tester.view.reset);

    final transport = _DiscussPageTransport();
    await tester.pumpWidget(
      AppServicesScope(
        services: _servicesWithTransport(transport),
        child: _discussTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('discuss-page-report-dis_1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Report'), findsOneWidget);
  });

  testWidgets('post detail bottom input opens composer for its root discuss', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);
    addTearDown(tester.view.reset);

    final transport = _DiscussPageTransport(includeReplies: true);
    await tester.pumpWidget(
      AppServicesScope(
        services: _servicesWithTransport(transport),
        child: _discussTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DiscussStoryBadge), findsNothing);

    await tester.tap(find.text('Reply User: Reply target'));
    await tester.pumpAndSettle();

    expect(find.text('Post Detail'), findsOneWidget);
    expect(find.text('All Replies 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('post-detail-reply-like-reply_1')),
      findsOneWidget,
    );
    expect(find.text('Reply User: Reply target'), findsNothing);
    expect(find.text('Reply target'), findsOneWidget);
    expect(find.byType(DiscussStoryBadge), findsNothing);
    expect(find.text('Write a reply'), findsOneWidget);

    await tester.tap(find.text('Write a reply'));
    await tester.pumpAndSettle();

    final composerInputFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Write a reply' &&
          widget.minLines == 3 &&
          widget.maxLines == 6,
    );
    expect(composerInputFinder, findsOneWidget);
    final replyInput = tester.widget<TextField>(composerInputFinder);
    expect(replyInput.minLines, 3);
    expect(replyInput.maxLines, 6);
    expect(replyInput.expands, isFalse);

    await tester.enterText(composerInputFinder, 'reply from list item');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    final postRequest = transport.postRequests.single;
    final postBody =
        jsonDecode(utf8.decode(postRequest.bodyBytes ?? const <int>[]))
            as Map<String, dynamic>;
    expect(postBody['root_discuss_id'], 'dis_1');
    expect(postBody['parent_discuss_id'], 'dis_1');
    expect(postBody['parent_discuss_id'], isNot('reply_1'));
    expect(postBody['content'], 'reply from list item');
  });

  testWidgets('post detail reply action row shows report menu', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);
    addTearDown(tester.view.reset);

    final transport = _DiscussPageTransport(includeReplies: true);
    await tester.pumpWidget(
      AppServicesScope(
        services: _servicesWithTransport(transport),
        child: _postDetailTestApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DiscussStoryBadge), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('post-detail-reply-report-reply_1')),
    );
    await tester.pump();

    expect(find.text('Report'), findsOneWidget);
  });

  testWidgets('post detail hides WID in root and reply discuss meta', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);
    addTearDown(tester.view.reset);

    final transport = _DiscussPageTransport(includeReplies: true);
    await tester.pumpWidget(
      AppServicesScope(
        services: _servicesWithTransport(transport),
        child: _discussTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reply User: Reply target'));
    await tester.pumpAndSettle();

    expect(find.text('Post Detail'), findsOneWidget);
    expect(find.text('Discuss item 1'), findsOneWidget);
    expect(find.text('Reply target'), findsOneWidget);
    expect(find.text('WID: w_auto'), findsNothing);
    expect(find.text('WID: w_reply'), findsNothing);
  });
}

Widget _discussTestApp() {
  return MaterialApp(
    onGenerateRoute: AppRouter.onGenerateRoute,
    home: const DiscussPage(oid: 'o_auto'),
  );
}

Widget _postDetailTestApp() {
  return MaterialApp(
    onGenerateRoute: AppRouter.onGenerateRoute,
    home: PostDetailPage(item: _postDetailRootItem()),
  );
}

OriginDiscussListItem _postDetailRootItem() {
  return OriginDiscussListItem.fromJson({
    'discuss_id': 'dis_1',
    'biz_type': 1,
    'biz_id': 'o_auto',
    'world_id': 'w_auto',
    'author': {'uid': 'u_1', 'name': 'User 1'},
    'content': 'Discuss item 1',
    'reply_cnt': 1,
    'like_cnt': 0,
    'is_liked': false,
    'created_at': '2026-02-09T00:00:00Z',
  });
}

AppServices _servicesWithTransport(_DiscussPageTransport transport) {
  final base = ServiceRegistry.build(config: const AppConfig(useMock: true));
  final apiClient = ApiClient(
    baseUrl: 'http://localhost:8080/api/',
    defaultHeaders: const {
      'content-type': 'application/json',
      'accept': 'application/json',
    },
    transport: transport,
    responseProcessor: (response) =>
        ApiClient.defaultResponseProcessor(response),
  );
  final healthClient = ApiClient(
    baseUrl: 'http://localhost:8080/',
    defaultHeaders: const {'accept': 'application/json'},
    transport: transport,
    responseProcessor: (response) =>
        ApiClient.defaultResponseProcessor(response),
  );
  final sessionStore = MemoryUserSessionStore();
  unawaited(sessionStore.saveUid('u_test'));
  unawaited(sessionStore.saveAuthToken('test-token'));
  return AppServices(
    config: base.config,
    platformConfig: base.platformConfig,
    deviceId: base.deviceId,
    sessionStore: sessionStore,
    identityAuth: base.identityAuth,
    backendAuth: base.backendAuth,
    api: GenesisApi(
      apiClient: apiClient,
      healthClient: healthClient,
      sessionStore: sessionStore,
    ),
    chatroom: base.chatroom,
    chatroomMessages: MemoryChatroomMessageStorage(),
    directMessageConversations: base.directMessageConversations,
    directMessageMessages: base.directMessageMessages,
    appVersionCheck: base.appVersionCheck,
    externalUrlOpener: base.externalUrlOpener,
  );
}

class _DiscussPageTransport implements HttpTransport {
  _DiscussPageTransport({
    this.originGate,
    this.includeReplies = false,
    this.includeImages = false,
  });

  final Future<void>? originGate;
  final bool includeReplies;
  final bool includeImages;
  final List<TransportRequest> requests = <TransportRequest>[];

  List<TransportRequest> get discussRequests => requests
      .where((request) => request.uri.path.endsWith('/discuss/list'))
      .toList(growable: false);

  List<TransportRequest> get postRequests => requests
      .where((request) => request.uri.path.endsWith('/discuss/post'))
      .toList(growable: false);

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    if (request.uri.path.endsWith('/origin/detail')) {
      await originGate;
      return _jsonResponse({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {
          'info': {
            'origin_id': 'o_auto',
            'origin_name': 'Auto Load Origin',
            'cover': '',
            'map_url': '',
            'world_setting': 'A test origin for discuss page paging.',
            'world_view': 'A test origin for discuss page paging.',
            'owner_name': 'Tester',
            'origin_version': 1,
            'updated_at': '2026-02-09T00:00:00Z',
            'tags': <String>[],
          },
          'stats': {'discuss_cnt': 40},
          'characters': <Object?>[],
          'locations': <Object?>[],
        },
      });
    }
    if (request.uri.path.endsWith('/discuss/list')) {
      final bizId = request.uri.queryParameters['biz_id'] ?? 'o_auto';
      final page = int.tryParse(request.uri.queryParameters['pn'] ?? '') ?? 1;
      final rn = int.tryParse(request.uri.queryParameters['rn'] ?? '') ?? 20;
      final start = (page - 1) * rn;
      final end = (start + rn).clamp(0, 40);
      return _jsonResponse({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {
          'list': [
            for (var index = start; index < end; index += 1)
              {
                'comment': {
                  'discuss_id': 'dis_${index + 1}',
                  'biz_type': 1,
                  'biz_id': bizId,
                  'world_id': 'w_auto',
                  'author': {
                    'uid': 'u_${index + 1}',
                    'name': 'User ${index + 1}',
                  },
                  'content': 'Discuss item ${index + 1}',
                  'images': includeImages && index == 0
                      ? <String>['assets/images/map_default/root_default.webp']
                      : <String>[],
                  'reply_cnt': includeReplies && index == 0 ? 1 : index,
                  'like_cnt': index,
                  'is_liked': false,
                  'created_at': '2026-02-09T00:00:00Z',
                },
                'latest_replies': includeReplies && index == 0
                    ? [
                        {
                          'discuss_id': 'reply_1',
                          'author': {'uid': 'u_reply_1', 'name': 'Reply User'},
                          'content': 'Reply target',
                          'images': includeImages
                              ? <String>[
                                  'assets/images/map_default/root_default.webp',
                                ]
                              : <String>[],
                          'root_discuss_id': 'dis_1',
                          'parent_discuss_id': 'dis_1',
                          'level': 2,
                          'reply_cnt': 0,
                          'like_cnt': 0,
                          'is_liked': false,
                          'created_at': '2026-02-09T00:00:00Z',
                        },
                      ]
                    : <Object?>[],
              },
          ],
          'top_total': 40,
          'total_all': 40,
          'pn': page,
          'rn': rn,
        },
      });
    }
    if (request.uri.path.endsWith('/discuss/replies')) {
      return _jsonResponse({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {
          'comment': {
            'discuss_id': 'dis_1',
            'biz_type': 1,
            'biz_id': 'o_auto',
            'world_id': 'w_auto',
            'author': {'uid': 'u_1', 'name': 'User 1'},
            'content': 'Discuss item 1',
            'images': includeImages
                ? <String>['assets/images/map_default/root_default.webp']
                : <String>[],
            'reply_cnt': 1,
            'like_cnt': 0,
            'is_liked': false,
            'created_at': '2026-02-09T00:00:00Z',
          },
          'list': [
            {
              'discuss_id': 'reply_1',
              'biz_id': 'o_auto',
              'world_id': 'w_reply',
              'author': {'uid': 'u_reply_1', 'name': 'Reply User'},
              'content': 'Reply target',
              'images': includeImages
                  ? <String>['assets/images/map_default/root_default.webp']
                  : <String>[],
              'root_discuss_id': 'dis_1',
              'parent_discuss_id': 'dis_1',
              'level': 2,
              'reply_cnt': 0,
              'like_cnt': 0,
              'is_liked': false,
              'created_at': '2026-02-09T00:00:00Z',
            },
          ],
          'total': 1,
          'pn': 1,
          'rn': 20,
        },
      });
    }
    if (request.uri.path.endsWith('/discuss/post')) {
      return _jsonResponse({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {
          'discuss_id': 'dis_reply_new',
          'root_discuss_id': 'dis_1',
          'level': 2,
        },
      });
    }
    return _jsonResponse({
      'err_no': 0,
      'err_msg': 'succ',
      'data': <String, dynamic>{},
    });
  }
}

TransportResponse _jsonResponse(Map<String, dynamic> body) {
  return TransportResponse(
    statusCode: 200,
    headers: const {'content-type': 'application/json'},
    body: jsonEncode(body),
  );
}
