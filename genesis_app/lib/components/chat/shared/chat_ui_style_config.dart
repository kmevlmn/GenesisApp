import 'package:flutter/material.dart';

import '../../../ui/tokens/genesis_avatar_radii.dart';
import '../../../ui/tokens/genesis_colors.dart';

class ChatUiStyleConfig {
  const ChatUiStyleConfig({
    // Overall chat page background color.
    required this.conversationBackgroundColor,
    // Top chat header height, excluding the system safe area.
    required this.headerHeight,
    // Top chat header background color.
    required this.headerBackgroundColor,
    // Top chat header background gradient; when set, it takes precedence over the solid background color.
    this.headerBackgroundGradient,
    // Top chat header backdrop blur radius.
    this.headerBackdropBlurSigma = 0,
    // Top chat header title text style.
    required this.headerTitleTextStyle,
    // Top chat header subtitle text style.
    required this.headerSubtitleTextStyle,
    // Color of the location icon to the left of the header title.
    required this.headerTitleIconColor,
    // Size of the location icon to the left of the header title.
    required this.headerTitleIconSize,
    // Header subtitle status icon color.
    required this.headerStatusIconColor,
    // Header subtitle status icon size.
    required this.headerStatusIconSize,
    // Size of the More button icon on the right side of the header.
    required this.headerMoreIconSize,
    // Size of the Back button icon on the left side of the header.
    required this.headerBackIconSize,
    // Spacing between the header title icon and title text.
    required this.headerTitleIconGap,
    // Vertical spacing between the header title and subtitle.
    required this.headerSubtitleTopGap,
    // Spacing between the header status icon and subtitle text.
    required this.headerStatusIconGap,
    // Width reserved on the right when the More button is hidden, keeping the title centered.
    required this.headerTrailingPlaceholderWidth,
    // Bottom composer background color.
    required this.composerBackgroundColor,
    // Bottom composer background gradient; when set, it takes precedence over the solid background color.
    this.composerBackgroundGradient,
    // Bottom composer backdrop blur radius.
    this.composerBackdropBlurSigma = 0,
    // Bottom composer outer padding.
    required this.composerPadding,
    // Composer icon button hit-target size.
    required this.composerIconButtonSize,
    // Composer icon visual size.
    required this.composerIconSize,
    // Composer icon color.
    required this.composerIconColor,
    // Whether to show the voice button to the left of the input field.
    required this.showComposerVoiceButton,
    // Whether to show the sticker button to the right of the input field.
    required this.showComposerStickerButton,
    // Whether to show the Add button to the right of the input field.
    required this.showComposerAddButton,
    // Whether to show the Send button at the far right.
    required this.showComposerSendButton,
    // Send button width.
    required this.composerSendButtonWidth,
    // Send button height.
    required this.composerSendButtonHeight,
    // Send button border radius.
    required this.composerSendButtonBorderRadius,
    // Send button background color.
    required this.composerSendButtonColor,
    // Disabled send button background color.
    required this.composerSendButtonDisabledColor,
    // Backdrop blur used only by the send button surface.
    this.composerSendButtonBackdropBlurSigma = 0,
    // Send button icon color.
    required this.composerSendButtonIconColor,
    // Send button icon size.
    required this.composerSendButtonIconSize,
    // Send button loading indicator size.
    required this.composerSendButtonLoadingSize,
    // Send button loading indicator stroke width.
    required this.composerSendButtonLoadingStrokeWidth,
    // Spacing between the voice button and input field.
    required this.composerLeadingGap,
    // Spacing between action buttons to the right of the input field.
    required this.composerActionGap,
    // Minimum input field height.
    required this.inputMinHeight,
    // Minimum number of input field lines.
    required this.inputMinLines,
    // Maximum number of input field lines; additional content scrolls inside the field.
    required this.inputMaxLines,
    // Single-line input text height.
    required this.inputLineHeight,
    // Horizontal padding around input text.
    required this.inputHorizontalPadding,
    // Vertical padding around input text.
    required this.inputVerticalPadding,
    // Input field background color.
    required this.inputBackgroundColor,
    // Backdrop blur used only by the input field surface.
    this.inputBackdropBlurSigma = 0,
    // Input field border radius.
    required this.inputBorderRadius,
    // Input field text style.
    required this.inputTextStyle,
    this.inputHintStyle,
    // Message list padding.
    required this.messageListPadding,
    // Top space reserved when there is no top title.
    required this.topTitleEmptyHeight,
    // Bottom spacing below the top title.
    required this.topTitleBottomPadding,
    // Top title text style.
    required this.topTitleTextStyle,
    // Bottom spacing for each message row.
    required this.rowBottomPadding,
    // Maximum width of the current user's message bubble as a fraction of screen width.
    required this.selfBubbleMaxWidthFactor,
    // Maximum width of another user's message bubble as a fraction of screen width.
    required this.otherBubbleMaxWidthFactor,
    // Spacing between the loading or failure badge and the bubble.
    required this.badgeBubbleGap,
    // Spacing between the avatar and bubble.
    required this.avatarBubbleGap,
    // Space reserved between the far side of the bubble and the list edge.
    required this.avatarSideSpacerWidth,
    // Vertical spacing between the sender name and bubble.
    required this.senderNameBottomGap,
    // Vertical spacing between status text and the bubble.
    required this.statusTextTopGap,
    // Status text style for states other than sending and failed.
    required this.statusTextStyle,
    // Sender name style above another user's message.
    required this.senderNameTextStyle,
    // Whether to show the sender name above another user's bubble.
    required this.showSenderNameAboveOtherBubble,
    // Message bubble padding.
    required this.bubblePadding,
    // Message bubble border radius.
    required this.bubbleBorderRadius,
    // Current user's message bubble color.
    required this.selfBubbleColor,
    // Other user's message bubble color.
    required this.otherBubbleColor,
    // Message bubble text style.
    required this.bubbleTextStyle,
    // Whether messages use the Location Chat scene-plate geometry.
    this.useScenePlateBubbleGeometry = false,
    // Whether scene-plate narrator messages use the configured system colors.
    this.useConfiguredScenePlateSystemStyle = false,
    // Backdrop blur for Location Chat message plates.
    this.bubbleBackdropBlurSigma = 0,
    // Avatar size.
    required this.avatarSize,
    // Avatar border radius.
    required this.avatarBorderRadius,
    // Current user's avatar gradient colors.
    required this.selfAvatarColors,
    // Other user's avatar gradient colors.
    required this.otherAvatarColors,
    // Avatar text style.
    required this.avatarTextStyle,
    // AI badge size.
    required this.aiBadgeSize,
    // AI badge color.
    required this.aiBadgeColor,
    // Sending indicator badge size.
    required this.sendingBadgeSize,
    // Sending indicator badge padding.
    required this.sendingBadgePadding,
    // Sending indicator stroke width.
    required this.sendingBadgeStrokeWidth,
    // Sending indicator color.
    required this.sendingBadgeColor,
    // Failed red exclamation badge size.
    required this.failedBadgeSize,
    // Failed red exclamation badge background color.
    required this.failedBadgeColor,
    // Failed exclamation icon color.
    required this.failedBadgeIconColor,
    // Failed exclamation icon size.
    required this.failedBadgeIconSize,
    // Date divider bottom spacing.
    required this.dateDividerBottomPadding,
    // Date divider text style.
    required this.dateDividerTextStyle,
    // System message margin.
    required this.systemMessageMargin,
    // System message padding.
    required this.systemMessagePadding,
    // System message background color.
    required this.systemMessageBackgroundColor,
    // System message border radius.
    required this.systemMessageBorderRadius,
    // System message text style.
    required this.systemMessageTextStyle,
  });

  static const standard = ChatUiStyleConfig(
    conversationBackgroundColor: Color(
      0xFFEDEDED,
    ), // Overall chat page background color.
    headerHeight: 50, // Top chat header height, excluding the system safe area.
    headerBackgroundColor: Color(
      0xF5F2EFF2,
    ), // Top chat header background color.
    headerBackgroundGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xF2111111), Color(0x00111111)],
    ), // Top chat header background gradient.
    headerTitleTextStyle: TextStyle(
      fontSize: 16, // Header title font size.
      fontWeight: FontWeight.w600, // Header title font weight.
      color: Colors.black, // Header title color.
    ),
    headerSubtitleTextStyle: TextStyle(
      fontSize: 16, // Header subtitle font size.
      fontWeight: FontWeight.w400, // Header subtitle font weight.
      color: Colors.black87, // Header subtitle color.
    ),
    headerTitleIconColor: Color(0xFF526A9F), // Header location icon color.
    headerTitleIconSize: 16, // Header location icon size.
    headerStatusIconColor: Colors.black87, // Header subtitle status icon color.
    headerStatusIconSize: 17, // Header subtitle status icon size.
    headerMoreIconSize:
        17, // Size of the More button icon on the right side of the header.
    headerBackIconSize:
        17, // Size of the Back button icon on the left side of the header.
    headerTitleIconGap: 4, // Spacing between the header title icon and text.
    headerSubtitleTopGap:
        4, // Vertical spacing between the header title and subtitle.
    headerStatusIconGap: 5, // Spacing between the header status icon and text.
    headerTrailingPlaceholderWidth:
        48, // Width reserved on the right when the More button is hidden.
    composerBackgroundColor: Color(
      0xFAF1EFF1,
    ), // Bottom composer background color.
    composerBackgroundGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00111111), Color(0xF2111111)],
    ), // Bottom composer background gradient.
    composerPadding: EdgeInsets.fromLTRB(
      10,
      8,
      10,
      16,
    ), // Bottom composer inner padding.
    composerIconButtonSize: 32, // Composer icon button hit-target size.
    composerIconSize: 30, // Composer icon visual size.
    composerIconColor: Colors.black, // Composer icon color.
    showComposerVoiceButton:
        false, // Whether to show the voice button to the left of the input field.
    showComposerStickerButton:
        false, // Whether to show the sticker button to the right of the input field.
    showComposerAddButton:
        false, // Whether to show the Add button to the right of the input field.
    showComposerSendButton:
        true, // Whether to show the Send button at the far right.
    composerSendButtonWidth: 64, // Send button width.
    composerSendButtonHeight: 36, // Send button height.
    composerSendButtonBorderRadius: 8, // Send button border radius.
    composerSendButtonColor:
        GenesisColors.brand, // Send button background color.
    composerSendButtonDisabledColor:
        GenesisColors.brandSoft, // Disabled send button background color.
    composerSendButtonIconColor: Colors.white, // Send button icon color.
    composerSendButtonIconSize: 18, // Send button icon size.
    composerSendButtonLoadingSize: 18, // Send button loading indicator size.
    composerSendButtonLoadingStrokeWidth:
        2, // Send button loading indicator stroke width.
    composerLeadingGap: 12, // Spacing between the voice button and input field.
    composerActionGap:
        10, // Spacing between buttons to the right of the input field.
    inputMinHeight: 40, // Minimum input field height.
    inputMinLines: 1, // Minimum number of input field lines.
    inputMaxLines:
        10, // Maximum number of input field lines; additional content scrolls internally.
    inputLineHeight: 20, // Single-line input text height.
    inputHorizontalPadding: 14, // Horizontal padding around input text.
    inputVerticalPadding: 10, // Vertical padding around input text.
    inputBackgroundColor: Colors.white, // Input field background color.
    inputBorderRadius: 8, // Input field border radius.
    inputTextStyle: TextStyle(
      color: Colors.black, // Input field text color.
      fontSize: 14, // Input field font size.
      height: 20 / 14, // Input field text line height.
    ),
    messageListPadding: EdgeInsets.fromLTRB(
      18,
      18,
      18,
      12,
    ), // Message list padding.
    topTitleEmptyHeight: 16, // Top space reserved when there is no top title.
    topTitleBottomPadding: 16, // Bottom spacing below the top title.
    topTitleTextStyle: TextStyle(
      fontSize: 14, // Top title font size.
      height: 1.2, // Top title line height.
      fontWeight: FontWeight.w600, // Top title font weight.
      color: Colors.black87, // Top title color.
    ),
    rowBottomPadding: 24, // Bottom spacing for each message row.
    selfBubbleMaxWidthFactor:
        0.68, // Maximum width factor for the current user's message bubble.
    otherBubbleMaxWidthFactor:
        0.72, // Maximum width factor for another user's message bubble.
    badgeBubbleGap:
        8, // Spacing between the loading or failure badge and the bubble.
    avatarBubbleGap: 10, // Spacing between the avatar and bubble.
    avatarSideSpacerWidth:
        50, // Space reserved between the far side of the bubble and the list edge.
    senderNameBottomGap:
        4, // Vertical spacing between the other user's name and bubble.
    statusTextTopGap: 4, // Vertical spacing between status text and the bubble.
    statusTextStyle: TextStyle(
      color: Colors.white70,
      fontSize: 11,
    ), // Status text style.
    senderNameTextStyle: TextStyle(
      color: Colors.white, // Other user's name text color.
      fontSize: 12, // Other user's name font size.
      fontWeight: FontWeight.w400, // Other user's name font weight.
    ),
    showSenderNameAboveOtherBubble:
        true, // Whether to show the sender name above another user's bubble.
    bubblePadding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 10,
    ), // Bubble padding.
    bubbleBorderRadius: 8, // Bubble border radius.
    selfBubbleColor: Color(0xFF95EC69), // Current user's message bubble color.
    otherBubbleColor: Colors.white, // Other user's message bubble color.
    bubbleTextStyle: TextStyle(
      color: Colors.black, // Bubble text color.
      fontSize: 14, // Bubble font size.
      height: 20 / 14, // Bubble text line height.
      fontWeight: FontWeight.w400, // Bubble font weight.
    ),
    avatarSize: 40, // Avatar size.
    avatarBorderRadius: GenesisAvatarRadii.user, // Avatar border radius.
    selfAvatarColors: [
      Color(0xFFFFE7B0),
      Color(0xFF9ED7FF),
    ], // Current user's avatar gradient colors.
    otherAvatarColors: [
      Color(0xFFBFD7F2),
      Color(0xFF4F6D94),
    ], // Other user's avatar gradient colors.
    avatarTextStyle: TextStyle(
      color: Colors.white, // Avatar text color.
      fontSize: 13, // Avatar font size.
      fontWeight: FontWeight.w400, // Avatar font weight.
    ),
    aiBadgeSize: 16, // AI badge size.
    aiBadgeColor: GenesisColors.redPrimary, // AI badge color.
    sendingBadgeSize: 22, // Sending indicator badge size.
    sendingBadgePadding: 2, // Sending indicator badge padding.
    sendingBadgeStrokeWidth: 2, // Sending indicator stroke width.
    sendingBadgeColor: Color(0xFF777777), // Sending indicator color.
    failedBadgeSize: 22, // Failed red exclamation badge size.
    failedBadgeColor: GenesisColors
        .redPrimary, // Failed red exclamation badge background color.
    failedBadgeIconColor: Colors.white, // Failed exclamation icon color.
    failedBadgeIconSize: 17, // Failed exclamation icon size.
    dateDividerBottomPadding: 12, // Date divider bottom spacing.
    dateDividerTextStyle: TextStyle(
      color: Color(0xFF777777), // Date divider text color.
      fontSize: 10, // Date divider font size.
      fontWeight: FontWeight.w400, // Date divider font weight.
    ),
    systemMessageMargin: EdgeInsets.only(bottom: 18), // System message margin.
    systemMessagePadding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 6,
    ), // System message padding.
    systemMessageBackgroundColor: Color(
      0xE6111111,
    ), // System message background color.
    systemMessageBorderRadius: 8, // System message border radius.
    systemMessageTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 13,
    ), // System message text style.
  );

  // Overall chat page background color.
  final Color conversationBackgroundColor;
  // Top chat header height, excluding the system safe area.
  final double headerHeight;
  // Top chat header background color.
  final Color headerBackgroundColor;
  // Top chat header background gradient; when set, it takes precedence over the solid background color.
  final Gradient? headerBackgroundGradient;
  // Top chat header backdrop blur radius.
  final double headerBackdropBlurSigma;
  // Top chat header title text style.
  final TextStyle headerTitleTextStyle;
  // Top chat header subtitle text style.
  final TextStyle headerSubtitleTextStyle;
  // Color of the location icon to the left of the header title.
  final Color headerTitleIconColor;
  // Size of the location icon to the left of the header title.
  final double headerTitleIconSize;
  // Header subtitle status icon color.
  final Color headerStatusIconColor;
  // Header subtitle status icon size.
  final double headerStatusIconSize;
  // Size of the More button icon on the right side of the header.
  final double headerMoreIconSize;
  // Size of the Back button icon on the left side of the header.
  final double headerBackIconSize;
  // Spacing between the header title icon and title text.
  final double headerTitleIconGap;
  // Vertical spacing between the header title and subtitle.
  final double headerSubtitleTopGap;
  // Spacing between the header status icon and subtitle text.
  final double headerStatusIconGap;
  // Width reserved on the right when the More button is hidden, keeping the title centered.
  final double headerTrailingPlaceholderWidth;
  // Bottom composer background color.
  final Color composerBackgroundColor;
  // Bottom composer background gradient; when set, it takes precedence over the solid background color.
  final Gradient? composerBackgroundGradient;
  // Bottom composer backdrop blur radius.
  final double composerBackdropBlurSigma;
  // Bottom composer outer padding.
  final EdgeInsets composerPadding;
  // Composer icon button hit-target size.
  final double composerIconButtonSize;
  // Composer icon visual size.
  final double composerIconSize;
  // Composer icon color.
  final Color composerIconColor;
  // Whether to show the voice button to the left of the input field.
  final bool showComposerVoiceButton;
  // Whether to show the sticker button to the right of the input field.
  final bool showComposerStickerButton;
  // Whether to show the Add button to the right of the input field.
  final bool showComposerAddButton;
  // Whether to show the Send button at the far right.
  final bool showComposerSendButton;
  // Send button width.
  final double composerSendButtonWidth;
  // Send button height.
  final double composerSendButtonHeight;
  // Send button border radius.
  final double composerSendButtonBorderRadius;
  // Send button background color.
  final Color composerSendButtonColor;
  // Disabled send button background color.
  final Color composerSendButtonDisabledColor;
  // Backdrop blur used only by the send button surface.
  final double composerSendButtonBackdropBlurSigma;
  // Send button icon color.
  final Color composerSendButtonIconColor;
  // Send button icon size.
  final double composerSendButtonIconSize;
  // Send button loading indicator size.
  final double composerSendButtonLoadingSize;
  // Send button loading indicator stroke width.
  final double composerSendButtonLoadingStrokeWidth;
  // Spacing between the voice button and input field.
  final double composerLeadingGap;
  // Spacing between action buttons to the right of the input field.
  final double composerActionGap;
  // Minimum input field height.
  final double inputMinHeight;
  // Minimum number of input field lines.
  final int inputMinLines;
  // Maximum number of input field lines; additional content scrolls inside the field.
  final int inputMaxLines;
  // Single-line input text height.
  final double inputLineHeight;
  // Horizontal padding around input text.
  final double inputHorizontalPadding;
  // Vertical padding around input text.
  final double inputVerticalPadding;
  // Input field background color.
  final Color inputBackgroundColor;
  // Backdrop blur used only by the input field surface.
  final double inputBackdropBlurSigma;
  // Input field border radius.
  final double inputBorderRadius;
  // Input field text style.
  final TextStyle inputTextStyle;
  final TextStyle? inputHintStyle;
  // Message list padding.
  final EdgeInsets messageListPadding;
  // Top space reserved when there is no top title.
  final double topTitleEmptyHeight;
  // Bottom spacing below the top title.
  final double topTitleBottomPadding;
  // Top title text style.
  final TextStyle topTitleTextStyle;
  // Bottom spacing for each message row.
  final double rowBottomPadding;
  // Maximum width of the current user's message bubble as a fraction of screen width.
  final double selfBubbleMaxWidthFactor;
  // Maximum width of another user's message bubble as a fraction of screen width.
  final double otherBubbleMaxWidthFactor;
  // Spacing between the loading or failure badge and the bubble.
  final double badgeBubbleGap;
  // Spacing between the avatar and bubble.
  final double avatarBubbleGap;
  // Space reserved between the far side of the bubble and the list edge.
  final double avatarSideSpacerWidth;
  // Vertical spacing between the sender name and bubble.
  final double senderNameBottomGap;
  // Vertical spacing between status text and the bubble.
  final double statusTextTopGap;
  // Status text style for states other than sending and failed.
  final TextStyle statusTextStyle;
  // Sender name style above another user's message.
  final TextStyle senderNameTextStyle;
  // Whether to show the sender name above another user's bubble.
  final bool showSenderNameAboveOtherBubble;
  // Message bubble padding.
  final EdgeInsets bubblePadding;
  // Message bubble border radius.
  final double bubbleBorderRadius;
  // Current user's message bubble color.
  final Color selfBubbleColor;
  // Other user's message bubble color.
  final Color otherBubbleColor;
  // Message bubble text style.
  final TextStyle bubbleTextStyle;
  // Whether messages use the Location Chat scene-plate geometry.
  final bool useScenePlateBubbleGeometry;
  // Whether scene-plate narrator messages use the configured system colors.
  final bool useConfiguredScenePlateSystemStyle;
  // Backdrop blur for Location Chat message plates.
  final double bubbleBackdropBlurSigma;
  // Avatar size.
  final double avatarSize;
  // Avatar border radius.
  final double avatarBorderRadius;
  // Current user's avatar gradient colors.
  final List<Color> selfAvatarColors;
  // Other user's avatar gradient colors.
  final List<Color> otherAvatarColors;
  // Avatar text style.
  final TextStyle avatarTextStyle;
  // AI badge size.
  final double aiBadgeSize;
  // AI badge color.
  final Color aiBadgeColor;
  // Sending indicator badge size.
  final double sendingBadgeSize;
  // Sending indicator badge padding.
  final double sendingBadgePadding;
  // Sending indicator stroke width.
  final double sendingBadgeStrokeWidth;
  // Sending indicator color.
  final Color sendingBadgeColor;
  // Failed red exclamation badge size.
  final double failedBadgeSize;
  // Failed red exclamation badge background color.
  final Color failedBadgeColor;
  // Failed exclamation icon color.
  final Color failedBadgeIconColor;
  // Failed exclamation icon size.
  final double failedBadgeIconSize;
  // Date divider bottom spacing.
  final double dateDividerBottomPadding;
  // Date divider text style.
  final TextStyle dateDividerTextStyle;
  // System message margin.
  final EdgeInsets systemMessageMargin;
  // System message padding.
  final EdgeInsets systemMessagePadding;
  // System message background color.
  final Color systemMessageBackgroundColor;
  // System message border radius.
  final double systemMessageBorderRadius;
  // System message text style.
  final TextStyle systemMessageTextStyle;

  ChatUiStyleConfig copyWith({
    TextStyle? statusTextStyle,
    TextStyle? dateDividerTextStyle,
    Color? sendingBadgeColor,
    Color? failedBadgeIconColor,
    Color? conversationBackgroundColor,
    double? headerHeight,
    Color? headerBackgroundColor,
    Gradient? headerBackgroundGradient,
    bool clearHeaderBackgroundGradient = false,
    double? headerBackdropBlurSigma,
    Color? composerBackgroundColor,
    Gradient? composerBackgroundGradient,
    bool clearComposerBackgroundGradient = false,
    double? composerBackdropBlurSigma,
    EdgeInsets? composerPadding,
    TextStyle? headerTitleTextStyle,
    TextStyle? headerSubtitleTextStyle,
    Color? headerTitleIconColor,
    Color? headerStatusIconColor,
    double? headerStatusIconSize,
    double? headerSubtitleTopGap,
    EdgeInsets? messageListPadding,
    double? rowBottomPadding,
    double? avatarSize,
    double? avatarBorderRadius,
    double? avatarSideSpacerWidth,
    TextStyle? senderNameTextStyle,
    double? senderNameBottomGap,
    bool? showSenderNameAboveOtherBubble,
    EdgeInsets? bubblePadding,
    double? bubbleBorderRadius,
    Color? selfBubbleColor,
    Color? otherBubbleColor,
    TextStyle? bubbleTextStyle,
    bool? useScenePlateBubbleGeometry,
    bool? useConfiguredScenePlateSystemStyle,
    double? bubbleBackdropBlurSigma,
    TextStyle? avatarTextStyle,
    EdgeInsets? systemMessageMargin,
    EdgeInsets? systemMessagePadding,
    Color? systemMessageBackgroundColor,
    double? systemMessageBorderRadius,
    TextStyle? systemMessageTextStyle,
    bool? showComposerSendButton,
    double? composerSendButtonWidth,
    double? composerSendButtonHeight,
    double? composerSendButtonBorderRadius,
    Color? composerSendButtonColor,
    Color? composerSendButtonDisabledColor,
    Color? composerSendButtonIconColor,
    double? composerSendButtonBackdropBlurSigma,
    double? composerSendButtonIconSize,
    double? composerActionGap,
    Color? inputBackgroundColor,
    double? inputBackdropBlurSigma,
    double? inputBorderRadius,
    TextStyle? inputTextStyle,
    TextStyle? inputHintStyle,
  }) {
    return ChatUiStyleConfig(
      conversationBackgroundColor:
          conversationBackgroundColor ?? this.conversationBackgroundColor,
      headerHeight: headerHeight ?? this.headerHeight,
      headerBackgroundColor:
          headerBackgroundColor ?? this.headerBackgroundColor,
      headerBackgroundGradient: clearHeaderBackgroundGradient
          ? null
          : headerBackgroundGradient ?? this.headerBackgroundGradient,
      headerBackdropBlurSigma:
          headerBackdropBlurSigma ?? this.headerBackdropBlurSigma,
      composerBackgroundGradient: clearComposerBackgroundGradient
          ? null
          : composerBackgroundGradient ?? this.composerBackgroundGradient,
      composerBackdropBlurSigma:
          composerBackdropBlurSigma ?? this.composerBackdropBlurSigma,
      headerTitleTextStyle: headerTitleTextStyle ?? this.headerTitleTextStyle,
      headerSubtitleTextStyle:
          headerSubtitleTextStyle ?? this.headerSubtitleTextStyle,
      headerTitleIconColor: headerTitleIconColor ?? this.headerTitleIconColor,
      headerTitleIconSize: headerTitleIconSize,
      headerStatusIconColor:
          headerStatusIconColor ?? this.headerStatusIconColor,
      headerStatusIconSize: headerStatusIconSize ?? this.headerStatusIconSize,
      headerMoreIconSize: headerMoreIconSize,
      headerBackIconSize: headerBackIconSize,
      headerTitleIconGap: headerTitleIconGap,
      headerSubtitleTopGap: headerSubtitleTopGap ?? this.headerSubtitleTopGap,
      headerStatusIconGap: headerStatusIconGap,
      headerTrailingPlaceholderWidth: headerTrailingPlaceholderWidth,
      composerBackgroundColor:
          composerBackgroundColor ?? this.composerBackgroundColor,
      composerPadding: composerPadding ?? this.composerPadding,
      composerIconButtonSize: composerIconButtonSize,
      composerIconSize: composerIconSize,
      composerIconColor: composerIconColor,
      showComposerVoiceButton: showComposerVoiceButton,
      showComposerStickerButton: showComposerStickerButton,
      showComposerAddButton: showComposerAddButton,
      showComposerSendButton:
          showComposerSendButton ?? this.showComposerSendButton,
      composerSendButtonWidth:
          composerSendButtonWidth ?? this.composerSendButtonWidth,
      composerSendButtonHeight:
          composerSendButtonHeight ?? this.composerSendButtonHeight,
      composerSendButtonBorderRadius:
          composerSendButtonBorderRadius ?? this.composerSendButtonBorderRadius,
      composerSendButtonColor:
          composerSendButtonColor ?? this.composerSendButtonColor,
      composerSendButtonDisabledColor:
          composerSendButtonDisabledColor ??
          this.composerSendButtonDisabledColor,
      composerSendButtonBackdropBlurSigma:
          composerSendButtonBackdropBlurSigma ??
          this.composerSendButtonBackdropBlurSigma,
      composerSendButtonIconColor:
          composerSendButtonIconColor ?? this.composerSendButtonIconColor,
      composerSendButtonIconSize:
          composerSendButtonIconSize ?? this.composerSendButtonIconSize,
      composerSendButtonLoadingSize: composerSendButtonLoadingSize,
      composerSendButtonLoadingStrokeWidth:
          composerSendButtonLoadingStrokeWidth,
      composerLeadingGap: composerLeadingGap,
      composerActionGap: composerActionGap ?? this.composerActionGap,
      inputMinHeight: inputMinHeight,
      inputMinLines: inputMinLines,
      inputMaxLines: inputMaxLines,
      inputLineHeight: inputLineHeight,
      inputHorizontalPadding: inputHorizontalPadding,
      inputVerticalPadding: inputVerticalPadding,
      inputBackgroundColor: inputBackgroundColor ?? this.inputBackgroundColor,
      inputBackdropBlurSigma:
          inputBackdropBlurSigma ?? this.inputBackdropBlurSigma,
      inputBorderRadius: inputBorderRadius ?? this.inputBorderRadius,
      inputTextStyle: inputTextStyle ?? this.inputTextStyle,
      inputHintStyle: inputHintStyle ?? this.inputHintStyle,
      messageListPadding: messageListPadding ?? this.messageListPadding,
      topTitleEmptyHeight: topTitleEmptyHeight,
      topTitleBottomPadding: topTitleBottomPadding,
      topTitleTextStyle: topTitleTextStyle,
      rowBottomPadding: rowBottomPadding ?? this.rowBottomPadding,
      selfBubbleMaxWidthFactor: selfBubbleMaxWidthFactor,
      otherBubbleMaxWidthFactor: otherBubbleMaxWidthFactor,
      badgeBubbleGap: badgeBubbleGap,
      avatarBubbleGap: avatarBubbleGap,
      avatarSideSpacerWidth:
          avatarSideSpacerWidth ?? this.avatarSideSpacerWidth,
      senderNameBottomGap: senderNameBottomGap ?? this.senderNameBottomGap,
      statusTextTopGap: statusTextTopGap,
      statusTextStyle: statusTextStyle ?? this.statusTextStyle,
      senderNameTextStyle: senderNameTextStyle ?? this.senderNameTextStyle,
      showSenderNameAboveOtherBubble:
          showSenderNameAboveOtherBubble ?? this.showSenderNameAboveOtherBubble,
      bubblePadding: bubblePadding ?? this.bubblePadding,
      bubbleBorderRadius: bubbleBorderRadius ?? this.bubbleBorderRadius,
      selfBubbleColor: selfBubbleColor ?? this.selfBubbleColor,
      otherBubbleColor: otherBubbleColor ?? this.otherBubbleColor,
      bubbleTextStyle: bubbleTextStyle ?? this.bubbleTextStyle,
      useScenePlateBubbleGeometry:
          useScenePlateBubbleGeometry ?? this.useScenePlateBubbleGeometry,
      useConfiguredScenePlateSystemStyle:
          useConfiguredScenePlateSystemStyle ??
          this.useConfiguredScenePlateSystemStyle,
      bubbleBackdropBlurSigma:
          bubbleBackdropBlurSigma ?? this.bubbleBackdropBlurSigma,
      avatarSize: avatarSize ?? this.avatarSize,
      avatarBorderRadius: avatarBorderRadius ?? this.avatarBorderRadius,
      selfAvatarColors: selfAvatarColors,
      otherAvatarColors: otherAvatarColors,
      avatarTextStyle: avatarTextStyle ?? this.avatarTextStyle,
      aiBadgeSize: aiBadgeSize,
      aiBadgeColor: aiBadgeColor,
      sendingBadgeSize: sendingBadgeSize,
      sendingBadgePadding: sendingBadgePadding,
      sendingBadgeStrokeWidth: sendingBadgeStrokeWidth,
      sendingBadgeColor: sendingBadgeColor ?? this.sendingBadgeColor,
      failedBadgeSize: failedBadgeSize,
      failedBadgeColor: failedBadgeColor,
      failedBadgeIconColor: failedBadgeIconColor ?? this.failedBadgeIconColor,
      failedBadgeIconSize: failedBadgeIconSize,
      dateDividerBottomPadding: dateDividerBottomPadding,
      dateDividerTextStyle: dateDividerTextStyle ?? this.dateDividerTextStyle,
      systemMessageMargin: systemMessageMargin ?? this.systemMessageMargin,
      systemMessagePadding: systemMessagePadding ?? this.systemMessagePadding,
      systemMessageBackgroundColor:
          systemMessageBackgroundColor ?? this.systemMessageBackgroundColor,
      systemMessageBorderRadius:
          systemMessageBorderRadius ?? this.systemMessageBorderRadius,
      systemMessageTextStyle:
          systemMessageTextStyle ?? this.systemMessageTextStyle,
    );
  }

  // Maximum input field height, calculated from the maximum lines, line height, and vertical padding.
  double get inputMaxHeight {
    return inputLineHeight * inputMaxLines + inputVerticalPadding * 2;
  }

  // Single-line bubble text height, calculated from the font size and TextStyle.height.
  double get bubbleLineHeight {
    return (bubbleTextStyle.fontSize ?? 14) * (bubbleTextStyle.height ?? 1);
  }
}
