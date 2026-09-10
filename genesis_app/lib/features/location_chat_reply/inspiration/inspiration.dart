import 'package:flutter/material.dart';

import '../../../icons/custom_icon_assets.dart';
import '../shared/reply_feature_button.dart';

export 'src/chatroom_inspiration_controller.dart'
    show ChatroomInspirationController;
export 'src/chatroom_inspiration_models.dart'
    show ChatroomInspirationResponse, ChatroomInspirationSource;
export 'src/chatroom_inspiration_storage.dart'
    show
        ChatroomInspirationStorage,
        MemoryChatroomInspirationStorage,
        SqfliteChatroomInspirationStorage;

/// Public invocation and presentation contract for inspiration replies.
///
/// Request generations, cache epochs, HTTP details, and source validation stay
/// inside the inspiration feature.
final class LocationChatInspirationFeature {
  const LocationChatInspirationFeature({
    required this.messages,
    required this.loading,
    required this.enabled,
    this.onExpandedChanged,
    this.onSend,
    this.onEdit,
  });

  const LocationChatInspirationFeature.disabled()
    : messages = const [],
      loading = false,
      enabled = false,
      onExpandedChanged = null,
      onSend = null,
      onEdit = null;

  final List<String> messages;
  final bool loading;
  final bool enabled;
  final ValueChanged<bool>? onExpandedChanged;
  final ValueChanged<String>? onSend;
  final ValueChanged<String>? onEdit;
}

class LocationChatInspirationButton extends StatelessWidget {
  const LocationChatInspirationButton({
    super.key,
    required this.feature,
    required this.expanded,
    required this.onToggle,
    this.onBeforeInvoke,
  });

  final LocationChatInspirationFeature feature;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onBeforeInvoke;

  @override
  Widget build(BuildContext context) => LocationChatReplyFeatureButton(
    label: 'Inspiration',
    iconAsset: inspirationIconAsset,
    expanded: expanded,
    onTap: !feature.enabled || feature.loading
        ? null
        : () {
            onBeforeInvoke?.call();
            onToggle();
          },
  );
}
