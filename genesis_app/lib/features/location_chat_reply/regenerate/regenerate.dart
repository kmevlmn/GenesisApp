import 'package:flutter/material.dart';

import '../../../icons/custom_icon_assets.dart';
import '../shared/reply_feature_button.dart';

/// Public invocation contract for regenerating the current reply.
///
/// Consumers intentionally receive no controller, card, transport, or storage
/// implementation details.
final class LocationChatRegenerateFeature {
  const LocationChatRegenerateFeature({
    required this.onInvoke,
    required this.enabled,
    required this.busy,
  });

  const LocationChatRegenerateFeature.disabled()
    : onInvoke = null,
      enabled = false,
      busy = false;

  final VoidCallback? onInvoke;
  final bool enabled;
  final bool busy;

  VoidCallback? get invocation => enabled && !busy ? onInvoke : null;
}

class LocationChatRegenerateButton extends StatelessWidget {
  const LocationChatRegenerateButton({
    super.key,
    required this.feature,
    this.onBeforeInvoke,
  });

  final LocationChatRegenerateFeature feature;
  final VoidCallback? onBeforeInvoke;

  @override
  Widget build(BuildContext context) => LocationChatReplyFeatureButton(
    label: 'Regenerate',
    iconAsset: regenerateIconAsset,
    onTap: feature.invocation == null
        ? null
        : () {
            onBeforeInvoke?.call();
            feature.invocation!();
          },
  );
}
