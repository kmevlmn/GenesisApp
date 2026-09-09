import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../components/chat/shared/chat_ui.dart';
import '../../icons/custom_icon_assets.dart';
import '../../components/gems/gem_purchase_bottom_sheet.dart';
import 'location_chat_loading_bubble.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_typography.dart';

/// Reply actions with source-bound inspiration suggestions and host-owned messaging.
class LocationChatReplyActions extends StatefulWidget {
  const LocationChatReplyActions({
    super.key,
    required this.style,
    this.selfMessageBubbleMaxWidthCap,
    this.inspirationExpanded,
    this.onInspirationExpandedChanged,
    this.inspirationMessages = const [],
    this.inspirationLoading = false,
    this.inspirationEnabled = true,
    this.inspirationPage,
    this.onInspirationPageChanged,
    this.onInspirationSend,
    this.onInspirationEdit,
    this.onEditReply,
    this.onRegenerate,
    this.onGoOn,
    this.isMember = true,
    this.regenerateEnabled = true,
    this.goOnEnabled = true,
    this.editEnabled = true,
    this.regenerateBusy = false,
    this.goOnBusy = false,
    this.editBusy = false,
    this.cardIndex = 0,
    this.cardCount = 0,
    this.cardsConfirmed = false,
    this.onPreviousCard,
    this.onNextCard,
    this.editPromptExpanded,
    this.onEditPromptExpandedChanged,
  });

  final ValueChanged<String>? onInspirationSend;
  final ValueChanged<String>? onInspirationEdit;
  final VoidCallback? onEditReply;
  final VoidCallback? onRegenerate;
  final VoidCallback? onGoOn;
  final bool isMember;
  final bool regenerateEnabled;
  final bool goOnEnabled;
  final bool editEnabled;
  final bool regenerateBusy;
  final bool goOnBusy;
  final bool editBusy;

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
  final List<String> inspirationMessages;
  final bool inspirationLoading;
  final bool inspirationEnabled;
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
    if (widget.onInspirationExpandedChanged case final onChanged?) {
      onChanged(next);
    } else {
      setState(() => _localInspirationExpanded = next);
    }
  }

  VoidCallback? _memberAction(VoidCallback? action, {bool enabled = true}) {
    if (!enabled || action == null) return null;
    return () {
      _setEditPromptExpanded(false);
      action();
    };
  }

  ChatUiStyleConfig get style => widget.style;

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
              _ReplyActionIcon(
                key: const ValueKey(_ReplyActionIconType.regenerate),
                label: 'Regenerate',
                icon: _ReplyActionIconType.regenerate,
                onTap: _memberAction(
                  widget.onRegenerate,
                  enabled: widget.regenerateEnabled && !widget.regenerateBusy,
                ),
              ),
              const SizedBox(
                width:
                    LocationChatReplyActions.centerSpacing -
                    LocationChatReplyActions.buttonSize,
              ),
              _ReplyActionIcon(
                key: const ValueKey(_ReplyActionIconType.goOn),
                label: 'Go on',
                icon: _ReplyActionIconType.goOn,
                onTap: _memberAction(
                  widget.onGoOn,
                  enabled: widget.goOnEnabled && !widget.goOnBusy,
                ),
              ),
              const SizedBox(
                width:
                    LocationChatReplyActions.centerSpacing -
                    LocationChatReplyActions.buttonSize,
              ),
              _ReplyActionIcon(
                key: const ValueKey(_ReplyActionIconType.edit),
                label: 'Edit',
                icon: _ReplyActionIconType.edit,
                onTap: _memberAction(
                  widget.onEditReply == null
                      ? null
                      : () {
                          _setInspirationExpanded(false);
                          widget.onEditReply!();
                        },
                  enabled: widget.editEnabled && !widget.editBusy,
                ),
              ),
              const SizedBox(
                width:
                    LocationChatReplyActions.centerSpacing -
                    LocationChatReplyActions.buttonSize,
              ),
              _ReplyActionIcon(
                key: const ValueKey(_ReplyActionIconType.inspiration),
                label: 'Inspiration',
                icon: _ReplyActionIconType.inspiration,
                expanded: _inspirationExpanded,
                onTap: _memberAction(
                  _toggleInspiration,
                  enabled:
                      widget.inspirationEnabled && !widget.inspirationLoading,
                ),
              ),
            ],
          ),
        ),
        if (_inspirationExpanded) ...[
          const SizedBox(height: 12),
          if (widget.inspirationLoading)
            LocationChatLoadingBubble(style: style)
          else if (widget.inspirationMessages.isNotEmpty)
            _InspirationReplies(
              replies: widget.inspirationMessages,
              onSend: (text) {
                _setInspirationExpanded(false);
                widget.onInspirationSend?.call(text);
              },
              onEdit: (text) {
                _setInspirationExpanded(false);
                widget.onInspirationEdit?.call(text);
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

class _InspirationReplies extends StatefulWidget {
  const _InspirationReplies({
    required this.style,
    required this.maxWidthCap,
    required this.replies,
    required this.initialPage,
    required this.onPageChanged,
    required this.onSend,
    required this.onEdit,
  });

  final ChatUiStyleConfig style;
  final double? maxWidthCap;
  final List<String> replies;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<String> onSend;
  final ValueChanged<String> onEdit;

  @override
  State<_InspirationReplies> createState() => _InspirationRepliesState();
}

class _InspirationRepliesState extends State<_InspirationReplies> {
  PageController? _pageController;
  double _viewportFraction = 1;
  late int _currentPage = widget.initialPage.clamp(
    0,
    widget.replies.length - 1,
  );

  static const double _editStripWidth = 27;

  void _handleCardTap(int index, {bool edit = false}) {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final page = controller.page ?? _currentPage.toDouble();
    if (index != _currentPage || (page - index).abs() > 0.001) {
      controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (edit) {
      widget.onEdit(replies[index]);
    } else {
      widget.onSend(replies[index]);
    }
  }

  void _configureCarousel(double viewportWidth, double cardWidth) {
    final fraction = viewportWidth <= 0
        ? 1.0
        : ((cardWidth + 12) / viewportWidth).clamp(0.0, 1.0);
    if (_pageController != null &&
        (_viewportFraction - fraction).abs() < 0.0001) {
      return;
    }
    _pageController?.dispose();
    _viewportFraction = fraction;
    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: fraction,
    );
  }

  ChatUiStyleConfig get style => widget.style;
  double? get maxWidthCap => widget.maxWidthCap;

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  List<String> get replies => widget.replies;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = chatNarratorMessageBackgroundColor(
      style,
    ).withValues(alpha: style.selfBubbleColor.a);
    final bubbleStyle = style.copyWith(
      bubblePadding: style.bubblePadding.copyWith(right: 8 + _editStripWidth),
      selfBubbleColor: backgroundColor,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth -
              style.avatarSize -
              style.avatarBubbleGap -
              style.avatarSideSpacerWidth,
        );
        final width = math.min(
          availableWidth,
          math.min(
            chatNormalBubbleMaxWidth(context, style),
            maxWidthCap ?? double.infinity,
          ),
        );
        // Match text scaling and padding while giving the horizontal viewport
        // enough height for every suggestion, without clipping long replies.
        var contentHeight = 0.0;
        for (final reply in replies) {
          final painter =
              TextPainter(
                text: TextSpan(
                  text: reply,
                  style: GenesisTypography.resolve(
                    context,
                    style.bubbleTextStyle,
                  ),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(
                maxWidth: math.max(
                  1,
                  width - bubbleStyle.bubblePadding.horizontal,
                ),
              );
          contentHeight = math.max(contentHeight, painter.height);
          painter.dispose();
        }
        final carouselHeight = contentHeight + style.bubblePadding.vertical + 2;
        // Expand the paging viewport asymmetrically so the active card keeps
        // the original user-bubble position while its neighbors remain visible.
        final rightInset = style.avatarSize + style.avatarBubbleGap;
        final cardCenter = constraints.maxWidth - rightInset - width / 2;
        final centerOffset = cardCenter - constraints.maxWidth / 2;
        final viewportWidth = constraints.maxWidth + 2 * centerOffset.abs();
        final viewportLeft = math.min(0.0, 2 * centerOffset);
        _configureCarousel(viewportWidth, width);
        return Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                key: const ValueKey('inspiration-replies-carousel'),
                width: constraints.maxWidth,
                height: carouselHeight,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: viewportLeft,
                      top: 0,
                      bottom: 0,
                      width: viewportWidth,
                      child: PageView.builder(
                        controller: _pageController,
                        physics: const ClampingScrollPhysics(),
                        itemCount: replies.length,
                        padEnds: true,
                        onPageChanged: (page) {
                          _currentPage = page;
                          widget.onPageChanged(page);
                        },
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: SizedBox.expand(
                            key: ValueKey('inspiration-reply-card-$index'),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ChatMessageBubble(
                                  onTap: () => _handleCardTap(index),
                                  borderRadius: BorderRadius.circular(
                                    style.bubbleBorderRadius,
                                  ),
                                  message: ChatMessageVm(
                                    localId: 'inspiration-$index',
                                    senderId: 'inspiration',
                                    senderName: '',
                                    text: replies[index],
                                    isMe: true,
                                    status: 'sent',
                                  ),
                                  style: bubbleStyle,
                                ),
                                Positioned(
                                  top: 0,
                                  bottom: 0,
                                  right: 0,
                                  width: _editStripWidth,
                                  child: Semantics(
                                    button: true,
                                    label: 'Edit inspiration ${index + 1}',
                                    child: GestureDetector(
                                      key: ValueKey('inspiration-edit-$index'),
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () =>
                                          _handleCardTap(index, edit: true),
                                      child: Center(
                                        child: SvgPicture.asset(
                                          editSquareIconAsset,
                                          width:
                                              LocationChatReplyActions.iconSize,
                                          height:
                                              LocationChatReplyActions.iconSize,
                                          colorFilter: const ColorFilter.mode(
                                            Color(0xFFF4F3F6),
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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

enum _ReplyActionIconType { regenerate, goOn, edit, inspiration }

class _ReplyActionIcon extends StatelessWidget {
  const _ReplyActionIcon({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.expanded,
  });

  final String label;
  final _ReplyActionIconType icon;
  final VoidCallback? onTap;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      enabled: onTap != null,
      button: true,
      expanded: expanded,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
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
                colorFilter: ColorFilter.mode(
                  onTap == null
                      ? const Color(0x73FFFFFF)
                      : const Color(0xF2FFFFFF),
                  BlendMode.srcIn,
                ),
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
