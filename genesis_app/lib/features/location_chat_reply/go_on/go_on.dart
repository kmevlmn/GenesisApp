import 'package:flutter/material.dart';

import '../../../icons/custom_icon_assets.dart';
import '../shared/reply_feature_button.dart';

/// Public invocation contract for continuing from the current reply round.
final class LocationChatGoOnFeature {
  const LocationChatGoOnFeature({
    required this.onInvoke,
    required this.enabled,
    required this.busy,
  });

  const LocationChatGoOnFeature.disabled()
    : onInvoke = null,
      enabled = false,
      busy = false;

  final VoidCallback? onInvoke;
  final bool enabled;
  final bool busy;

  VoidCallback? get invocation => enabled && !busy ? onInvoke : null;
}

class LocationChatGoOnButton extends StatelessWidget {
  const LocationChatGoOnButton({
    super.key,
    required this.feature,
    this.onBeforeInvoke,
  });

  final LocationChatGoOnFeature feature;
  final VoidCallback? onBeforeInvoke;

  @override
  Widget build(BuildContext context) => LocationChatReplyFeatureButton(
    label: 'Go on',
    iconAsset: goOnIconAsset,
    onTap: feature.invocation == null
        ? null
        : () {
            onBeforeInvoke?.call();
            feature.invocation!();
          },
  );
}
