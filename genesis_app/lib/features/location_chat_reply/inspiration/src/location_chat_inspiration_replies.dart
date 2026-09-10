part of '../../../../pages/chat/location_chat_reply_actions.dart';

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
