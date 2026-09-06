import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../components/chat/shared/chat_ui.dart';
import '../../icons/custom_icon_assets.dart';

/// Visual placeholders only. Reply actions deliberately have no callbacks.
class LocationChatReplyActions extends StatelessWidget {
  const LocationChatReplyActions({super.key, required this.style});

  final ChatUiStyleConfig style;

  static const double buttonSize = 32;
  static const double iconSize = 17;
  static const double centerSpacing = 50;
  // Account for the icon's inset inside its button when spacing the row.
  static const double contentBottomGap = 16 - (buttonSize - iconSize) / 2;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '<     1 / 2     >',
            key: ValueKey('location-chat-reply-page-indicator'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFF4F3F6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(
              left: style.avatarSize + style.avatarBubbleGap,
            ),
            child: Row(
              key: const ValueKey('location-chat-reply-actions-four-icons'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReplyActionIcon(
                  key: const ValueKey(_ReplyActionIconType.regenerate),
                  label: 'Regenerate',
                  icon: _ReplyActionIconType.regenerate,
                ),
                const SizedBox(width: centerSpacing - buttonSize),
                _ReplyActionIcon(
                  key: const ValueKey(_ReplyActionIconType.goOn),
                  label: 'Go on',
                  icon: _ReplyActionIconType.goOn,
                ),
                const SizedBox(width: centerSpacing - buttonSize),
                _ReplyActionIcon(
                  key: const ValueKey(_ReplyActionIconType.edit),
                  label: 'Edit',
                  icon: _ReplyActionIconType.edit,
                ),
                const SizedBox(width: centerSpacing - buttonSize),
                _ReplyActionIcon(
                  key: const ValueKey(_ReplyActionIconType.inspiration),
                  label: 'Inspiration',
                  icon: _ReplyActionIconType.inspiration,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ReplyActionIconType { regenerate, goOn, edit, inspiration }

class _ReplyActionIcon extends StatelessWidget {
  const _ReplyActionIcon({super.key, required this.label, required this.icon});

  final String label;
  final _ReplyActionIconType icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      enabled: false,
      child: SizedBox.square(
        dimension: LocationChatReplyActions.buttonSize,
        child: Center(
          child: SvgPicture.asset(
            switch (icon) {
              _ReplyActionIconType.regenerate => regenerateIconAsset,
              _ReplyActionIconType.goOn => goOnIconAsset,
              _ReplyActionIconType.edit => editSquareIconAsset,
              _ReplyActionIconType.inspiration => inspirationIconAsset,
            },
            width: LocationChatReplyActions.iconSize,
            height: LocationChatReplyActions.iconSize,
            colorFilter: const ColorFilter.mode(
              Color(0xFFF4F3F6),
              BlendMode.srcIn,
            ),
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
