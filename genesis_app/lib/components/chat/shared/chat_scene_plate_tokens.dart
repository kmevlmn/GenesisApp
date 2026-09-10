import '../../../ui/tokens/genesis_colors.dart';

import '../../../ui/tokens/genesis_blur.dart';

import 'package:flutter/material.dart';

const double kLocationChatOuterPadding = 10;
const double kChatScenePlateBubbleHorizontalPadding = 13;
const double kChatScenePlateBubbleVerticalPadding = 11;
const EdgeInsets kChatScenePlateBubblePadding = EdgeInsets.symmetric(
  horizontal: kChatScenePlateBubbleHorizontalPadding,
  vertical: kChatScenePlateBubbleVerticalPadding,
);
const Color kChatScenePlateAiBubbleColor = Color(0x993A3942);
const Color kChatScenePlatePlayerRoleBorderColor = GenesisColors.redPrimary;
const double kChatScenePlateBubbleBlurSigma = GenesisBlur.strong;
const TextStyle kChatScenePlateBubbleTextStyle = TextStyle(
  color: Color(0xFFF4F3F6),
  fontSize: 14,
  height: 1.4,
  fontWeight: FontWeight.w400,
);
const BorderRadius kChatScenePlateAiBubbleBorderRadius = BorderRadius.only(
  topLeft: Radius.circular(2),
  topRight: Radius.circular(14),
  bottomRight: Radius.circular(14),
  bottomLeft: Radius.circular(14),
);
const BorderRadius kChatScenePlateSelfBubbleBorderRadius = BorderRadius.only(
  topLeft: Radius.circular(14),
  topRight: Radius.circular(2),
  bottomRight: Radius.circular(14),
  bottomLeft: Radius.circular(14),
);
