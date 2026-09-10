part of 'chat_ui_library.dart';

class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.connected,
    required this.connecting,
    required this.onBack,
    this.titleSuffix,
    this.titleSuffixSemanticsLabel,
    this.titleOverline,
    this.titleOverlineStyle,
    this.showTitleIcon = true,
    this.showSubtitle = true,
    this.showMoreButton = true,
    this.alignContentLeft = false,
    this.trailingVerticallyCentered = false,
    this.subtitleIconAsset,
    this.trailing,
    this.style,
    this.backdropGroupKey,
  });

  final String title;
  final String subtitle;
  final bool connected;
  final bool connecting;
  final VoidCallback onBack;
  final Widget? titleSuffix;
  final String? titleSuffixSemanticsLabel;
  final String? titleOverline;
  final TextStyle? titleOverlineStyle;
  final bool showTitleIcon;
  final bool showSubtitle;
  final bool showMoreButton;
  final bool alignContentLeft;
  final bool trailingVerticallyCentered;
  final String? subtitleIconAsset;
  final Widget? trailing;
  final ChatUiStyleConfig? style;

  /// Groups this header blur with non-overlapping backdrop filters.
  final BackdropKey? backdropGroupKey;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? ChatUiStyleConfig.standard;
    final topInset = GenesisSafeAreaInsets.top(context);
    // Keep the back button in place; content starts 12px after its arrow.
    final alignedContentLeft =
        (kMinInteractiveDimension + style.headerBackIconSize) / 2 + 12;
    final headerSidePadding = trailing == null
        ? style.headerTrailingPlaceholderWidth
        : _chatHeaderTrailingWidth;
    final trailingInTitleRow =
        alignContentLeft && trailing != null && !trailingVerticallyCentered;
    final centeredTrailing =
        alignContentLeft && trailing != null && trailingVerticallyCentered;
    final titleText = _ChatHeaderTitleText(
      title: title,
      suffix: titleSuffix,
      suffixSemanticsLabel: titleSuffixSemanticsLabel,
      style: style.headerTitleTextStyle,
    );
    final overline = titleOverline?.trim() ?? '';
    final overlineStyle =
        titleOverlineStyle ??
        style.headerTitleTextStyle.copyWith(
          color: (style.headerTitleTextStyle.color ?? Colors.white).withValues(
            alpha: 0.45,
          ),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
        );
    final verticallyCenteredTitleIcon = alignContentLeft && showTitleIcon;
    final titleIconColor = overlineStyle.color ?? style.headerTitleIconColor;
    return ClipRect(
      child: _ChatHeaderBackdropFilter(
        sigma: style.headerBackdropBlurSigma,
        backdropGroupKey: backdropGroupKey,
        child: Container(
          height: topInset + style.headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 0),
          decoration: BoxDecoration(
            color: style.headerBackgroundGradient == null
                ? style.headerBackgroundColor
                : null,
            gradient: style.headerBackgroundGradient,
          ),
          child: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: onBack,
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      size: style.headerBackIconSize,
                      color: style.headerTitleTextStyle.color,
                    ),
                  ),
                ),
                if (verticallyCenteredTitleIcon)
                  Positioned(
                    left: alignedContentLeft,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        Icons.place_outlined,
                        size: style.headerTitleIconSize,
                        color: titleIconColor,
                      ),
                    ),
                  ),
                Positioned(
                  left: alignContentLeft ? alignedContentLeft : 0,
                  right:
                      alignContentLeft &&
                          !trailingInTitleRow &&
                          !centeredTrailing
                      ? headerSidePadding
                      : 0,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: alignContentLeft
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center,
                          children: [
                            if (overline.isNotEmpty) ...[
                              Padding(
                                padding: alignContentLeft
                                    ? EdgeInsets.only(
                                        left: showTitleIcon
                                            ? style.headerTitleIconSize +
                                                  style.headerTitleIconGap
                                            : 0,
                                      )
                                    : EdgeInsets.symmetric(
                                        horizontal: headerSidePadding,
                                      ),
                                child: Row(
                                  mainAxisAlignment: alignContentLeft
                                      ? MainAxisAlignment.start
                                      : MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        overline,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: overlineStyle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    _ChatHeaderOverlineChevron(
                                      color:
                                          overlineStyle.color ??
                                          style.headerTitleIconColor,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            Padding(
                              padding: alignContentLeft
                                  ? EdgeInsets.zero
                                  : EdgeInsets.symmetric(
                                      horizontal: headerSidePadding,
                                    ),
                              child: Row(
                                mainAxisAlignment: alignContentLeft
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.center,
                                mainAxisSize: alignContentLeft
                                    ? MainAxisSize.max
                                    : MainAxisSize.min,
                                children: [
                                  if (verticallyCenteredTitleIcon)
                                    SizedBox(
                                      width:
                                          style.headerTitleIconSize +
                                          style.headerTitleIconGap,
                                    )
                                  else if (showTitleIcon) ...[
                                    Icon(
                                      Icons.place_outlined,
                                      size: style.headerTitleIconSize,
                                      color: style.headerTitleIconColor,
                                    ),
                                    SizedBox(width: style.headerTitleIconGap),
                                  ],
                                  if (alignContentLeft)
                                    Expanded(child: titleText)
                                  else
                                    Flexible(child: titleText),
                                  if (trailingInTitleRow)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Transform.translate(
                                        offset: const Offset(0, 2),
                                        child: trailing,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (showSubtitle) ...[
                              SizedBox(height: style.headerSubtitleTopGap),
                              Padding(
                                padding: alignContentLeft
                                    ? EdgeInsets.zero
                                    : const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                child: Row(
                                  mainAxisAlignment: alignContentLeft
                                      ? MainAxisAlignment.start
                                      : MainAxisAlignment.center,
                                  children: [
                                    if (subtitleIconAsset != null)
                                      _ChatHeaderSubtitleAssetIcon(
                                        asset: subtitleIconAsset!,
                                        style: style,
                                      )
                                    else if (connected)
                                      _ChatHeaderSubtitleAssetIcon(
                                        asset: characterStatIconAsset,
                                        style: style,
                                      )
                                    else
                                      Icon(
                                        connecting
                                            ? Icons.sync
                                            : Icons.cloud_off,
                                        size: style.headerStatusIconSize,
                                        color: style.headerStatusIconColor,
                                      ),
                                    SizedBox(width: style.headerStatusIconGap),
                                    Flexible(
                                      child: Text(
                                        genesisDisplaySafeText(subtitle),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: alignContentLeft
                                            ? TextAlign.left
                                            : TextAlign.center,
                                        style: style.headerSubtitleTextStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (centeredTrailing) ...[
                        const SizedBox(width: 10),
                        trailing!,
                      ],
                    ],
                  ),
                ),
                if (trailing != null &&
                    !trailingInTitleRow &&
                    !centeredTrailing)
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: headerSidePadding,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing,
                      ),
                    ),
                  )
                else if (showMoreButton)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.more_horiz,
                        size: style.headerMoreIconSize,
                        color: style.headerTitleTextStyle.color,
                      ),
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: style.headerTrailingPlaceholderWidth,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatHeaderTitleText extends StatelessWidget {
  const _ChatHeaderTitleText({
    required this.title,
    required this.style,
    this.suffix,
    this.suffixSemanticsLabel,
  });

  final String title;
  final TextStyle style;
  final Widget? suffix;
  final String? suffixSemanticsLabel;

  @override
  Widget build(BuildContext context) {
    final visibleTitle = genesisDisplaySafeText(title);
    final spokenSuffix = suffixSemanticsLabel?.trim() ?? '';
    return Semantics(
      label: spokenSuffix.isEmpty
          ? visibleTitle
          : '$visibleTitle $spokenSuffix',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              visibleTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (suffix != null) ...[const SizedBox(width: 4), suffix!],
        ],
      ),
    );
  }
}

class _ChatHeaderOverlineChevron extends StatelessWidget {
  const _ChatHeaderOverlineChevron({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 7,
      child: CustomPaint(
        painter: _ChatHeaderOverlineChevronPainter(
          color: color.withValues(alpha: color.a * 0.5),
        ),
      ),
    );
  }
}

class _ChatHeaderOverlineChevronPainter extends CustomPainter {
  const _ChatHeaderOverlineChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.35, size.height * 0.18)
        ..lineTo(size.width * 0.68, size.height * 0.5)
        ..lineTo(size.width * 0.35, size.height * 0.82),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ChatHeaderOverlineChevronPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ChatHeaderBackdropFilter extends StatelessWidget {
  const _ChatHeaderBackdropFilter({
    required this.sigma,
    required this.backdropGroupKey,
    required this.child,
  });

  final double sigma;
  final BackdropKey? backdropGroupKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (sigma <= 0) return child;
    return BackdropFilter(
      backdropGroupKey: backdropGroupKey,
      filterConfig: ImageFilterConfig.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        bounded: false,
      ),
      child: child,
    );
  }
}

class _ChatHeaderSubtitleAssetIcon extends StatelessWidget {
  const _ChatHeaderSubtitleAssetIcon({
    required this.asset,
    required this.style,
  });

  final String asset;
  final ChatUiStyleConfig style;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: style.headerStatusIconSize,
      height: style.headerStatusIconSize,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(
        style.headerStatusIconColor,
        BlendMode.srcIn,
      ),
      excludeFromSemantics: true,
    );
  }
}
