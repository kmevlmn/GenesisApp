import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_loading_bubble.dart';

void main() {
  testWidgets(
    'loading bubble matches other-role surface and has three black looping dots',
    (tester) async {
      final style = kLocationChatStyle.copyWith(
        selfBubbleColor: const Color(0x99C41F2E),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BackdropGroup(
              child: Column(
                children: [
                  ChatMessageBubble(
                    message: ChatMessageVm(
                      localId: 'other',
                      senderId: 'character',
                      senderName: 'Other',
                      text: 'Hello',
                      isMe: false,
                      senderType: 'character',
                      status: 'sent',
                    ),
                    style: style,
                  ),
                  LocationChatLoadingBubble(style: style),
                ],
              ),
            ),
          ),
        ),
      );
      final bubble = tester.widget<Container>(
        find.byKey(const ValueKey('location-chat-loading-bubble')),
      );
      final decoration = bubble.decoration! as BoxDecoration;
      final otherBubble = tester.widget<Container>(
        find.byKey(const ValueKey('chat-message-bubble-other')),
      );
      expect(
        decoration.color,
        (otherBubble.decoration! as BoxDecoration).color,
      );
      final surfaces = tester
          .widgetList<ChatStableBackdropSurface>(
            find.byType(ChatStableBackdropSurface),
          )
          .toList();
      expect(surfaces, hasLength(2));
      expect(surfaces[1].sigma, surfaces[0].sigma);
      for (var i = 0; i < 3; i++) {
        final dot = tester.widget<Container>(
          find.descendant(
            of: find.byKey(ValueKey('location-chat-loading-dot-$i')),
            matching: find.byType(Container),
          ),
        );
        expect((dot.decoration! as BoxDecoration).color, Colors.black);
      }
      expect(decoration.borderRadius, BorderRadius.circular(14));
      expect(
        find.descendant(
          of: find.byType(LocationChatLoadingBubble),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      double scale(int i) => tester
          .widget<Transform>(
            find.byKey(ValueKey('location-chat-loading-dot-$i')),
          )
          .transform
          .storage[0];
      final initial = [for (var i = 0; i < 3; i++) scale(i)];
      expect(initial.toSet().length, 3);
      await tester.pump(const Duration(milliseconds: 300));
      expect(scale(0), greaterThan(initial[0]));
      await tester.pump(const Duration(milliseconds: 900));
      for (var i = 0; i < 3; i++) {
        expect(scale(i), closeTo(initial[i], 0.001));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
