import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../components/chat/shared/chat_ui.dart';
import '../../features/location_chat_reply/edit/edit.dart';
import '../../features/location_chat_reply/go_on/go_on.dart';
import '../../features/location_chat_reply/inspiration/inspiration.dart';
import '../../features/location_chat_reply/regenerate/regenerate.dart';
import '../../icons/custom_icon_assets.dart';
import '../../components/gems/gem_purchase_bottom_sheet.dart';
import 'location_chat_loading_bubble.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_typography.dart';

part '../../features/location_chat_reply/inspiration/src/location_chat_inspiration_replies.dart';

/// Reply actions with source-bound inspiration suggestions and host-owned messaging.
class LocationChatReplyActions extends StatefulWidget {
  const LocationChatReplyActions({
    super.key,
    required this.style,
    this.regenerateFeature = const LocationChatRegenerateFeature.disabled(),
    this.goOnFeature = const LocationChatGoOnFeature.disabled(),
    this.editFeature = const LocationChatEditFeature.disabled(),
    this.inspirationFeature = const LocationChatInspirationFeature.disabled(),
    this.selfMessageBubbleMaxWidthCap,
    this.inspirationExpanded,
    this.onInspirationExpandedChanged,
    this.inspirationPage,
    this.onInspirationPageChanged,
    this.isMember = true,
    this.cardIndex = 0,
    this.cardCount = 0,
    this.cardsConfirmed = false,
    this.onPreviousCard,
    this.onNextCard,
    this.editPromptExpanded,
    this.onEditPromptExpandedChanged,
  });

  final bool isMember;
  final LocationChatRegenerateFeature regenerateFeature;
  final LocationChatGoOnFeature goOnFeature;
  final LocationChatEditFeature editFeature;
  final LocationChatInspirationFeature inspirationFeature;

  /// Zero-based position in the full card list, including in-flight/failed cards.
  final int cardIndex;
  final int cardCount;
  final bool cardsConfirmed;
  final VoidCallback? onPreviousCard;
  final VoidCallback? onNextCard;
  final bool? editPromptExpanded;
  final ValueChanged<bool>? onEditPromptExpandedChanged;
  final ChatUiStyleConfig style;
  final double? selfMessageBubbleMaxWidthCap;
  final int? inspirationPage;
  final ValueChanged<int>? onInspirationPageChanged;
  final bool? inspirationExpanded;
  final ValueChanged<bool>? onInspirationExpandedChanged;

  static const double buttonSize = 32;
  static const double iconSize = 17;
  static const double centerSpacing = 50;
  // Account for the icon's inset inside its button when spacing the row.
  static const double contentBottomGap = 16 - (buttonSize - iconSize) / 2;

  @override
  State<LocationChatReplyActions> createState() =>
      _LocationChatReplyActionsState();
}

class _LocationChatReplyActionsState extends State<LocationChatReplyActions> {
  bool _localInspirationExpanded = false;
  int _localInspirationPage = 0;
  bool get _inspirationExpanded =>
      widget.inspirationExpanded ?? _localInspirationExpanded;

  void _setEditPromptExpanded(bool expanded) {
    if (widget.onEditPromptExpandedChanged case final onChanged?) {
      onChanged(expanded);
    }
  }

  void _toggleInspiration() {
    _setEditPromptExpanded(false);
    _setInspirationExpanded(!_inspirationExpanded);
  }

  void _setInspirationExpanded(bool next) {
    final onChanged =
        widget.onInspirationExpandedChanged ??
        widget.inspirationFeature.onExpandedChanged;
    if (onChanged != null) {
      onChanged(next);
    } else {
      setState(() => _localInspirationExpanded = next);
    }
  }

  ChatUiStyleConfig get style => widget.style;

  LocationChatRegenerateFeature get _regenerate => widget.regenerateFeature;
  LocationChatGoOnFeature get _goOn => widget.goOnFeature;
  LocationChatEditFeature get _edit => widget.editFeature;
  LocationChatInspirationFeature get _inspiration => widget.inspirationFeature;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.cardCount > 1 && !widget.cardsConfirmed) ...[
          Row(
            key: const ValueKey('location-chat-reply-pagination'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('location-chat-reply-previous-card'),
                tooltip: 'Previous reply',
                onPressed: widget.cardIndex > 0 ? widget.onPreviousCard : null,
                icon: const Icon(Icons.chevron_left, size: 20),
                color: const Color(0xF2FFFFFF),
                disabledColor: const Color(0x73FFFFFF),
              ),
              Text(
                '${widget.cardIndex + 1} / ${widget.cardCount}',
                key: const ValueKey('location-chat-reply-page-indicator'),
                semanticsLabel:
                    'Reply ${widget.cardIndex + 1} of ${widget.cardCount}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xF2FFFFFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              IconButton(
                key: const ValueKey('location-chat-reply-next-card'),
                tooltip: 'Next reply',
                onPressed: widget.cardIndex < widget.cardCount - 1
                    ? widget.onNextCard
                    : null,
                icon: const Icon(Icons.chevron_right, size: 20),
                color: const Color(0xF2FFFFFF),
                disabledColor: const Color(0x73FFFFFF),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: EdgeInsets.only(
            left: style.avatarSize + style.avatarBubbleGap,
          ),
          child: Row(
            key: const ValueKey('location-chat-reply-actions-four-icons'),
            mainAxisSize: MainAxisSize.min,
            children: [
              LocationChatRegenerateButton(
                key: const ValueKey('location-chat-regenerate'),
                feature: _regenerate,
                onBeforeInvoke: () => _setEditPromptExpanded(false),
              ),
              const SizedBox(
                width:
                    LocationChatReplyActions.centerSpacing -
                    LocationChatReplyActions.buttonSize,
              ),
              LocationChatGoOnButton(
                key: const ValueKey('location-chat-go-on'),
                feature: _goOn,
                onBeforeInvoke: () => _setEditPromptExpanded(false),
              ),
              const SizedBox(
                width:
                    LocationChatReplyActions.centerSpacing -
                    LocationChatReplyActions.buttonSize,
              ),
              LocationChatEditButton(
                key: const ValueKey('location-chat-edit'),
                feature: _edit,
                onBeforeInvoke: () {
                  _setEditPromptExpanded(false);
                  _setInspirationExpanded(false);
                },
              ),
              const SizedBox(
                width:
                    LocationChatReplyActions.centerSpacing -
                    LocationChatReplyActions.buttonSize,
              ),
              LocationChatInspirationButton(
                key: const ValueKey('location-chat-inspiration'),
                feature: _inspiration,
                expanded: _inspirationExpanded,
                onBeforeInvoke: () => _setEditPromptExpanded(false),
                onToggle: _toggleInspiration,
              ),
            ],
          ),
        ),
        if (_inspirationExpanded) ...[
          const SizedBox(height: 12),
          if (_inspiration.loading)
            LocationChatLoadingBubble(style: style)
          else if (_inspiration.messages.isNotEmpty)
            _InspirationReplies(
              replies: _inspiration.messages,
              onSend: (text) {
                _setInspirationExpanded(false);
                _inspiration.onSend?.call(text);
              },
              onEdit: (text) {
                _setInspirationExpanded(false);
                _inspiration.onEdit?.call(text);
              },
              style: style,
              maxWidthCap: widget.selfMessageBubbleMaxWidthCap,
              initialPage: widget.inspirationPage ?? _localInspirationPage,
              onPageChanged: (page) {
                _localInspirationPage = page;
                widget.onInspirationPageChanged?.call(page);
              },
            ),
        ],
      ],
    );
  }
}

/// Shared appearance for inline subscription prompts below reply actions.
class LocationChatSubscriptionPrompt extends StatelessWidget {
  const LocationChatSubscriptionPrompt({
    super.key,
    required this.style,
    required this.promptKey,
    required this.semanticsLabel,
    required this.message,
    required this.actionLabel,
    this.singleLine = false,
  });

  final ChatUiStyleConfig style;
  final Key promptKey;
  final String semanticsLabel;
  final InlineSpan message;
  final String actionLabel;
  final bool singleLine;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    child: GestureDetector(
      key: promptKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => showSubscriptionPurchaseBottomSheet(context),
      child: ChatStableBackdropSurface(
        borderRadius: BorderRadius.circular(style.bubbleBorderRadius),
        sigma: style.bubbleBackdropBlurSigma,
        child: Container(
          padding: style.bubblePadding,
          decoration: BoxDecoration(
            color: chatNarratorMessageBackgroundColor(
              style,
            ).withValues(alpha: style.selfBubbleColor.a),
            borderRadius: BorderRadius.circular(style.bubbleBorderRadius),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                message,
                TextSpan(
                  text: '${singleLine ? ' ' : '\n'}$actionLabel',
                  style: const TextStyle(color: GenesisColors.brand),
                ),
              ],
            ),
            maxLines: singleLine ? 1 : null,
            softWrap: !singleLine,
            textWidthBasis: TextWidthBasis.longestLine,
            textAlign: TextAlign.center,
            style: GenesisTypography.resolve(
              context,
              style.bubbleTextStyle,
            ).copyWith(fontSize: 13),
          ),
        ),
      ),
    ),
  );
}
