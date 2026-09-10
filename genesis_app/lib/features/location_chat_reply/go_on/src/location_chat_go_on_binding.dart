part of '../../../../pages/chat/location_chat_page.dart';

extension _LocationChatGoOnBinding on _LocationChatPanelState {
  LocationChatGoOnFeature _goOnFeature(
    bool replyBlocked,
    ChatroomReplyRoundState? replyState,
    bool goOnPending,
  ) => LocationChatGoOnFeature(
    enabled: !replyBlocked && (replyState?.canGoOn ?? false),
    busy: goOnPending,
    onInvoke: () => unawaited(
      _runReplyAction(
        (controller) => controller.goOn(widget.locationId),
        generating: true,
      ),
    ),
  );
}
