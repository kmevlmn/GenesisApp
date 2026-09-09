import '../../components/chat/shared/chat_ui.dart';

/// Replaces only canonical AI replies in the selected round. UI flags such as
/// isSystem (which includes narrators) and isMe do not define card membership.
({List<ChatMessageVm> messages, int anchorIndex})
buildLocationChatReplyPresentation({
  required List<ChatMessageVm> source,
  required String roundId,
  required Set<int> replyMessageIds,
  List<ChatMessageVm>? candidates,
}) {
  final output = <ChatMessageVm>[];
  int? anchor;
  var inserted = false;
  for (final message in source) {
    if (message.roundId == roundId &&
        message.globalMessageId > 0 &&
        replyMessageIds.contains(message.globalMessageId)) {
      if (candidates != null) {
        if (!inserted) output.addAll(candidates);
        inserted = true;
      } else {
        output.add(message);
      }
      anchor = output.length;
    } else {
      output.add(message);
    }
  }
  if (candidates != null && !inserted) {
    output.addAll(candidates);
    anchor = output.length;
  }
  return (messages: output, anchorIndex: anchor ?? output.length);
}
