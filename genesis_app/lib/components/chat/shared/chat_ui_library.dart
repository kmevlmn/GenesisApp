import 'dart:async';
import 'dart:math' as math;

import '../../../ui/tokens/genesis_blur.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/config/genesis_image_config.dart';
import '../../../components/common/genesis_image_viewer_overlay.dart';
import '../../../components/common/genesis_generation_wait_overlay.dart';
import '../../../components/common/genesis_timestamp_text.dart';
import '../../../components/ai_content_disclaimer.dart';
import '../../../icons/custom_icon_assets.dart';
import '../../../icons/my_flutter_app_icons.dart';
import '../../../ui/components/genesis_avatar.dart';
import '../../../ui/components/genesis_asterisk_icon.dart';
import '../../../ui/components/genesis_safe_area.dart';
import '../../../ui/components/genesis_soft_italic_text.dart';
import '../../../ui/components/genesis_static_network_image.dart';
import '../../../ui/system/genesis_system_ui.dart';
import '../../../ui/tokens/genesis_colors.dart';
import '../../../ui/tokens/genesis_typography.dart';
import '../../../ui/text/genesis_text_input_formatters.dart';
import '../../../utils/genesis_message_image.dart';
import 'chat_scene_plate_tokens.dart';
import 'chat_mention.dart';
import 'chat_ui_style_config.dart';

export 'chat_mention.dart';
export 'chat_ui_style_config.dart';

part 'chat_ui_message_model.dart';
part 'chat_ui_message_editor.dart';
part 'chat_ui_header.dart';
part 'chat_ui_composer.dart';
part 'chat_ui_message_lists.dart';
part 'chat_ui_message_row.dart';
part 'chat_ui_self_message_bubble.dart';
part 'chat_ui_other_message_bubble.dart';
part 'chat_ui_system_message_bubble.dart';
part 'chat_ui_narrator_message_bubble.dart';
part 'chat_ui_tick_message_bubble.dart';
part 'chat_ui_image_message_bubble.dart';
part 'chat_ui_user_enter_location_message_bubble.dart';
part 'chat_ui_story_events_message_bubble.dart';
part 'chat_ui_characters_moved_message_bubble.dart';
part 'chat_ui_ai_content_disclaimer_message_bubble.dart';
part 'chat_ui_media.dart';
part 'chat_ui_bubbles.dart';
part 'chat_ui_system_markdown.dart';

const SystemUiOverlayStyle kChatTransparentLightSystemUiOverlayStyle =
    kGenesisDefaultSystemUiOverlayStyle;

const SystemUiOverlayStyle kChatDarkHeaderSystemUiOverlayStyle =
    kGenesisLightStatusIconsSystemUiOverlayStyle;

@immutable
class LocationChatOrdinaryMessageBubbleMaxWidthCaps {
  const LocationChatOrdinaryMessageBubbleMaxWidthCaps({
    required this.isCrowded,
    required this.selfMessage,
    required this.otherMessage,
  });

  final bool isCrowded;
  final double selfMessage;
  final double otherMessage;
}

LocationChatOrdinaryMessageBubbleMaxWidthCaps
locationChatOrdinaryMessageBubbleMaxWidthCapsForMetrics({
  required double logicalWidth,
  required TextScaler textScaler,
  required double bubbleFontSize,
  required double crowdedEffectiveWidthThreshold,
  required double avatarSize,
  required double avatarBubbleGap,
  required double avatarSideSpacerWidth,
  required double messageListHorizontalPadding,
}) {
  if (logicalWidth <= 0 || bubbleFontSize <= 0) {
    return const LocationChatOrdinaryMessageBubbleMaxWidthCaps(
      isCrowded: true,
      selfMessage: 0,
      otherMessage: 0,
    );
  }
  final scaledFontSize = textScaler.scale(bubbleFontSize);
  if (scaledFontSize <= 0) {
    return const LocationChatOrdinaryMessageBubbleMaxWidthCaps(
      isCrowded: true,
      selfMessage: 0,
      otherMessage: 0,
    );
  }
  final effectiveWidth = logicalWidth / (scaledFontSize / bubbleFontSize);
  final isCrowded = effectiveWidth < crowdedEffectiveWidthThreshold;
  if (isCrowded) {
    final crowdedMaxWidth = math.max(
      0.0,
      logicalWidth -
          avatarSize -
          avatarBubbleGap -
          avatarSideSpacerWidth -
          messageListHorizontalPadding,
    );
    return LocationChatOrdinaryMessageBubbleMaxWidthCaps(
      isCrowded: true,
      selfMessage: crowdedMaxWidth,
      otherMessage: crowdedMaxWidth,
    );
  }
  final roomyMaxWidth = math.max(
    0.0,
    logicalWidth -
        avatarSize * 2 -
        avatarBubbleGap -
        messageListHorizontalPadding,
  );
  return LocationChatOrdinaryMessageBubbleMaxWidthCaps(
    isCrowded: false,
    selfMessage: roomyMaxWidth,
    otherMessage: roomyMaxWidth,
  );
}

final ChatUiStyleConfig kChatWhiteHeaderStyle = ChatUiStyleConfig.standard
    .copyWith(headerBackgroundColor: Colors.white);

final ChatUiStyleConfig kPrivateChatStyle = ChatUiStyleConfig.standard.copyWith(
  conversationBackgroundColor: GenesisColors.darkBackground,
  headerBackgroundColor: GenesisColors.darkBackground,
  headerTitleTextStyle: GenesisTypography.pageTitle.copyWith(
    color: GenesisColors.darkTextPrimary,
  ),
  clearHeaderBackgroundGradient: true,
  headerBackdropBlurSigma: 0,
  composerBackgroundColor: GenesisColors.darkBackground,
  clearComposerBackgroundGradient: true,
  composerBackdropBlurSigma: 0,
  composerSendButtonColor: GenesisColors.redPrimary,
  composerSendButtonDisabledColor: GenesisColors.darkFaintFill,
  composerSendButtonIconColor: GenesisColors.darkTextPrimary,
  inputBackgroundColor: GenesisColors.darkFaintFill,
  inputHintStyle: const TextStyle(color: GenesisColors.darkInputPlaceholder),
  inputTextStyle: ChatUiStyleConfig.standard.inputTextStyle.copyWith(
    color: GenesisColors.darkTextPrimary,
    height: 1.4,
  ),
  selfBubbleColor: GenesisColors.redPrimary.withValues(alpha: 0.4),
  otherBubbleColor: GenesisColors.darkFaintFill,
  bubbleTextStyle: ChatUiStyleConfig.standard.bubbleTextStyle.copyWith(
    color: GenesisColors.darkTextPrimary,
  ),
  senderNameTextStyle: ChatUiStyleConfig.standard.senderNameTextStyle.copyWith(
    color: GenesisColors.darkTextSecondary,
  ),
  statusTextStyle: ChatUiStyleConfig.standard.statusTextStyle.copyWith(
    color: GenesisColors.darkTextTertiary,
  ),
  dateDividerTextStyle: ChatUiStyleConfig.standard.dateDividerTextStyle
      .copyWith(color: GenesisColors.darkTextTertiary),
  sendingBadgeColor: GenesisColors.darkTextSecondary,
  failedBadgeIconColor: GenesisColors.darkTextPrimary,
  showSenderNameAboveOtherBubble: false,
);

const double _locationChatAvatarOneThird = 40 / 3;
const double _npcChatAvatarSize = 40;
const Color _npcChatAvatarBackgroundColor = Color(0xFF4A5F7A);
const Color _locationChatBackgroundColor = GenesisColors.darkBackground;
const Color _locationChatSurfaceColor = Colors.transparent;
const double _locationChatSurfaceBlurSigma = GenesisBlur.light;
const double _chatHeaderTrailingWidth = 96;

ChatUiStyleConfig get kLocationChatStyle => ChatUiStyleConfig.standard.copyWith(
  conversationBackgroundColor: _locationChatBackgroundColor,
  headerHeight: 50,
  headerBackgroundColor: _locationChatSurfaceColor,
  clearHeaderBackgroundGradient: true,
  headerTitleTextStyle: ChatUiStyleConfig.standard.headerTitleTextStyle
      .copyWith(color: Colors.white),
  headerSubtitleTextStyle: ChatUiStyleConfig.standard.headerSubtitleTextStyle
      .copyWith(color: Colors.white),
  headerTitleIconColor: Colors.white,
  headerStatusIconColor: Colors.white,
  headerBackdropBlurSigma: _locationChatSurfaceBlurSigma,
  composerBackgroundColor: _locationChatSurfaceColor,
  clearComposerBackgroundGradient: true,
  composerBackdropBlurSigma: _locationChatSurfaceBlurSigma,
  composerSendButtonWidth: 40,
  composerSendButtonHeight: 40,
  composerSendButtonBorderRadius: 8,
  composerSendButtonColor: GenesisColors.redPrimary,
  composerSendButtonDisabledColor: const Color(0x21FFFFFF),
  composerSendButtonBackdropBlurSigma: GenesisBlur.strong,
  composerSendButtonIconSize: 17,
  composerActionGap: 9,
  inputBackgroundColor: GenesisColors.darkFaintFill,
  inputBackdropBlurSigma: GenesisBlur.light,
  inputBorderRadius: 8,
  inputHintStyle: const TextStyle(color: GenesisColors.darkInputPlaceholder),
  inputTextStyle: ChatUiStyleConfig.standard.inputTextStyle.copyWith(
    color: GenesisColors.darkTextPrimary,
    fontSize: 14,
    height: 1.4,
  ),
  messageListPadding: ChatUiStyleConfig.standard.messageListPadding.copyWith(
    left: kLocationChatOuterPadding,
    right: kLocationChatOuterPadding,
  ),
  rowBottomPadding: 14,
  avatarSideSpacerWidth: _locationChatAvatarOneThird,
  senderNameBottomGap: 6,
  senderNameTextStyle: const TextStyle(
    color: Color(0xFFF4F3F6),
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1,
  ),
  bubblePadding: kChatScenePlateBubblePadding,
  bubbleBorderRadius: 14,
  selfBubbleColor: const Color(0x99C41F2E),
  otherBubbleColor: kChatScenePlateAiBubbleColor,
  bubbleTextStyle: kChatScenePlateBubbleTextStyle,
  useScenePlateBubbleGeometry: true,
  bubbleBackdropBlurSigma: kChatScenePlateBubbleBlurSigma,
  systemMessageMargin: const EdgeInsets.only(bottom: 14),
  systemMessagePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  systemMessageBackgroundColor: const Color(0x14FFFFFF),
  systemMessageBorderRadius: 8,
  systemMessageTextStyle: const TextStyle(
    color: Color(0x99FFFFFF),
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w400,
  ),
);

// Opening uses the chat palette on a flat surface, so no backdrop blur is needed.
ChatUiStyleConfig get kOpeningDialogueStyle =>
    kLocationChatStyle.copyWith(bubbleBackdropBlurSigma: 0);
