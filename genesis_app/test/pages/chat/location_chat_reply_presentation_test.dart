import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_reply_presentation.dart';

void main() {
  const round = '9007199254740993';
  ChatMessageVm message(
    int id,
    String type, {
    bool mine = false,
    String? inRound,
  }) => ChatMessageVm(
    localId: '$id',
    globalMessageId: id,
    roundId: inRound ?? round,
    senderId: type,
    senderName: type,
    text: '$type-$id',
    senderType: type,
    isMe: mine,
    status: 'sent',
  );
  final older = message(1, 'narrator', inRound: '9007199254740992');
  final mine = message(2, 'user', mine: true);
  final otherUser = message(3, 'user');
  final character = message(4, 'character', mine: true);
  final narrator = message(5, 'narrator');
  final image = message(6, 'image');
  final tick = message(7, 'tick');
  final system = message(8, 'system');
  final source = [
    older,
    mine,
    otherUser,
    character,
    narrator,
    image,
    tick,
    system,
  ];
  const ids = {4, 5, 6};

  test(
    'switching cards replaces all AI replies while preserving users and events',
    () {
      expect(narrator.isSystem, isTrue);
      final candidate = [message(11, 'narrator'), message(12, 'character')];
      final next = buildLocationChatReplyPresentation(
        source: source,
        roundId: round,
        replyMessageIds: ids,
        candidates: candidate,
      );
      expect(next.messages, [
        older,
        mine,
        otherUser,
        ...candidate,
        tick,
        system,
      ]);
      expect(next.anchorIndex, 5);
      final original = buildLocationChatReplyPresentation(
        source: source,
        roundId: round,
        replyMessageIds: ids,
        candidates: [character, narrator, image],
      );
      expect(original.messages, source);
      expect(original.anchorIndex, 6);
      expect(source, containsAll([character, narrator, image]));
    },
  );

  test(
    'loading card hides only the AI group and retains its action anchor',
    () {
      final result = buildLocationChatReplyPresentation(
        source: source,
        roundId: round,
        replyMessageIds: ids,
        candidates: [],
      );
      expect(result.messages, [older, mine, otherUser, tick, system]);
      expect(result.anchorIndex, 3);
    },
  );

  test(
    'without candidates original content and narrator action anchor remain',
    () {
      final result = buildLocationChatReplyPresentation(
        source: source,
        roundId: round,
        replyMessageIds: ids,
      );
      expect(result.messages, source);
      expect(result.anchorIndex, 6);
    },
  );
}
