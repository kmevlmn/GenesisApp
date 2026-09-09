part of 'create_form_library.dart';

typedef CreateKeyboardSafeFocusRegionBuilder =
    Widget Function(BuildContext context, FocusNode focusNode);

class CreateKeyboardSafeFocusRegion extends StatefulWidget {
  const CreateKeyboardSafeFocusRegion({
    super.key,
    required this.builder,
    this.focusNode,
    this.visibilityAxis,
  });

  final CreateKeyboardSafeFocusRegionBuilder builder;
  final FocusNode? focusNode;
  final Axis? visibilityAxis;

  @override
  State<CreateKeyboardSafeFocusRegion> createState() =>
      _CreateKeyboardSafeFocusRegionState();
}

class _CreateKeyboardSafeFocusRegionState
    extends State<CreateKeyboardSafeFocusRegion>
    with WidgetsBindingObserver {
  late final FocusNode _internalFocusNode;
  late FocusNode _observedFocusNode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _internalFocusNode = FocusNode();
    _observedFocusNode = _focusNode;
    _observedFocusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant CreateKeyboardSafeFocusRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _observedFocusNode.removeListener(_handleFocusChanged);
      _observedFocusNode = _focusNode;
      _observedFocusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _observedFocusNode.removeListener(_handleFocusChanged);
    _internalFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_observedFocusNode.hasFocus) _ensureRegionVisible();
  }

  @override
  void didChangeMetrics() {
    if (_observedFocusNode.hasFocus) _ensureRegionVisible();
  }

  void _ensureRegionVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_observedFocusNode.hasFocus) return;
      unawaited(_ensureRegionVisibleAboveKeyboard());
    });
  }

  Future<void> _ensureRegionVisibleAboveKeyboard() async {
    final visibilityAxis = widget.visibilityAxis;
    if (visibilityAxis == null) {
      await Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    } else {
      await _ensureVisibleAlongAxis(visibilityAxis);
    }
    if (!mounted || !_observedFocusNode.hasFocus) return;

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardInset <= 0) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final keyboardTop = MediaQuery.sizeOf(context).height - keyboardInset;
    final regionBottom = renderObject
        .localToGlobal(Offset(0, renderObject.size.height))
        .dy;
    final overlap = regionBottom - keyboardTop;
    if (overlap <= 0) return;

    if (visibilityAxis != null) {
      _shiftScrollableAncestors(visibilityAxis, overlap);
      return;
    }

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    final position = scrollable.position;
    if (!position.hasPixels || !position.hasContentDimensions) return;
    final target = (position.pixels + overlap)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() < 0.000001) return;
    position.jumpTo(target);
  }

  void _shiftScrollableAncestors(Axis axis, double distance) {
    var remaining = distance;
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null && remaining > 0.000001) {
      final position = scrollable.position;
      if (axisDirectionToAxis(scrollable.axisDirection) == axis &&
          position.hasPixels &&
          position.hasContentDimensions) {
        final reversed = axisDirectionIsReversed(scrollable.axisDirection);
        final requested = position.pixels + (reversed ? -remaining : remaining);
        final target = requested
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        final moved = (target - position.pixels).abs();
        if (moved > 0.000001) position.jumpTo(target);
        remaining -= moved;
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }

  Future<void> _ensureVisibleAlongAxis(Axis axis) async {
    final target = context.findRenderObject();
    if (target == null) return;
    final matchingScrollables = <ScrollableState>[];
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      if (axisDirectionToAxis(scrollable.axisDirection) == axis) {
        matchingScrollables.add(scrollable);
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    for (final matchingScrollable in matchingScrollables) {
      await matchingScrollable.position.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _focusNode);

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;
}

class CreateTextFieldBlock extends StatefulWidget {
  const CreateTextFieldBlock({
    super.key,
    required this.label,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.maxLength,
    this.showCounter = true,
    this.counterInside = false,
    this.note,
    this.supportLeading,
    this.minLines = 1,
    this.maxLines,
    this.prefix,
    this.labelSize = 14,
    this.labelFontWeight = FontWeight.w600,
    this.labelInputGap = 10,
    this.inputLineHeight,
    this.textInputAction,
    this.onEditingComplete,
    this.onSubmitted,
    this.scrollPadding,
    this.fillColor,
    this.textColor,
    this.hintColor,
    this.contentPadding,
    this.handoffVerticalDragToAncestor = false,
    this.visibilityBottomPadding = 0,
    this.inputFormatters = const [],
    this.focusNode,
    this.nextFocusNode,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final int? maxLength;
  final bool showCounter;
  final bool counterInside;
  final String? note;
  final Widget? supportLeading;
  final int minLines;
  final int? maxLines;
  final Widget? prefix;
  final double labelSize;
  final FontWeight labelFontWeight;
  final double labelInputGap;
  final double? inputLineHeight;
  final TextInputAction? textInputAction;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final EdgeInsets? scrollPadding;
  final Color? fillColor;
  final Color? textColor;
  final Color? hintColor;
  final EdgeInsets? contentPadding;
  final bool handoffVerticalDragToAncestor;
  final double visibilityBottomPadding;
  final List<TextInputFormatter> inputFormatters;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;

  @override
  State<CreateTextFieldBlock> createState() => _CreateTextFieldBlockState();
}

class _CreateTextFieldBlockState extends State<CreateTextFieldBlock> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_normalizeControllerText);
    _normalizeControllerText();
  }

  @override
  void didUpdateWidget(covariant CreateTextFieldBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_normalizeControllerText);
      widget.controller.addListener(_normalizeControllerText);
      _normalizeControllerText();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_normalizeControllerText);
    super.dispose();
  }

  void _normalizeControllerText() {
    if (_isSingleLine) return;
    final value = widget.controller.value;
    final sanitized = genesisConsecutiveNewlineLimitedTextEditingValue(value);
    if (sanitized == value) return;
    widget.controller.value = sanitized;
  }

  void _handleEditingComplete(FocusNode focusNode) {
    final customHandler = widget.onEditingComplete;
    if (customHandler != null) {
      customHandler();
      return;
    }

    final nextFocusNode = widget.nextFocusNode;
    if (nextFocusNode != null && nextFocusNode.canRequestFocus) {
      nextFocusNode.requestFocus();
      return;
    }

    if (!focusNode.nextFocus()) {
      focusNode.unfocus();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.handoffVerticalDragToAncestor || !event.down) return;
    final delta = event.delta.dy;
    if (delta == 0) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null || !scrollable.position.hasPixels) return;
    final position = scrollable.position;
    final nextPixels = (position.pixels - delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((nextPixels - position.pixels).abs() < 0.000001) return;
    position.jumpTo(nextPixels);
  }

  @override
  Widget build(BuildContext context) {
    return CreateKeyboardSafeFocusRegion(
      focusNode: widget.focusNode,
      builder: (context, focusNode) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label.isNotEmpty) ...[
            Text(
              widget.label,
              style: TextStyle(
                color: CreateFormTheme.colorOf(
                  context,
                  createFormText,
                  GenesisColors.darkTextPrimary,
                ),
                fontSize: widget.labelSize,
                fontWeight: widget.labelFontWeight,
                height: 1.2,
              ),
            ),
            // Field internal spacing: label -> input box.
            SizedBox(height: widget.labelInputGap),
          ],
          Container(
            constraints: CreateFormTheme.isDarkOf(context)
                ? const BoxConstraints(minHeight: 40)
                : null,
            decoration: BoxDecoration(
              color:
                  widget.fillColor ??
                  CreateFormTheme.colorOf(
                    context,
                    createFormFieldFill,
                    GenesisColors.darkFaintFill,
                  ),
              borderRadius: BorderRadius.circular(8),
            ),
            padding:
                widget.contentPadding ??
                EdgeInsets.symmetric(
                  horizontal: CreateFormTheme.isDarkOf(context) ? 14 : 10,
                  vertical: 10,
                ),
            alignment: _isSingleLine ? Alignment.center : Alignment.topCenter,
            child: Row(
              crossAxisAlignment: _isSingleLine
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                if (widget.prefix != null) ...[
                  widget.prefix!,
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerMove: widget.handoffVerticalDragToAncestor
                        ? _handlePointerMove
                        : null,
                    child: TextFieldTapRegion(
                      groupId: createFormTextFieldTapRegionGroup,
                      child: TextField(
                        controller: widget.controller,
                        focusNode: focusNode,
                        cursorColor:
                            widget.textColor ??
                            CreateFormTheme.colorOf(
                              context,
                              createFormText,
                              GenesisColors.darkTextPrimary,
                            ),
                        scrollPadding:
                            widget.scrollPadding ??
                            const EdgeInsets.fromLTRB(
                              20,
                              20,
                              20,
                              kMinInteractiveDimension,
                            ),
                        onChanged: widget.onChanged,
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        keyboardType: _resolvedKeyboardType,
                        textInputAction: _resolvedTextInputAction,
                        onEditingComplete: _shouldHandleEditingComplete
                            ? () => _handleEditingComplete(focusNode)
                            : null,
                        onSubmitted: widget.onSubmitted,
                        inputFormatters: [
                          if (!_isSingleLine)
                            const GenesisConsecutiveNewlineLimiter(),
                          ...widget.inputFormatters,
                        ],
                        maxLength: widget.maxLength,
                        minLines: widget.minLines,
                        maxLines: widget.maxLines,
                        style: GenesisTypography.withFallback(
                          TextStyle(
                            color:
                                widget.textColor ??
                                CreateFormTheme.colorOf(
                                  context,
                                  createFormText,
                                  GenesisColors.darkTextPrimary,
                                ),
                            fontSize: 14,
                            height:
                                widget.inputLineHeight ??
                                (CreateFormTheme.isDarkOf(context)
                                    ? 1.4
                                    : 1.42),
                          ),
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          hintText: widget.hintText,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintStyle: GenesisTypography.withFallback(
                            TextStyle(
                              color:
                                  widget.hintColor ??
                                  CreateFormTheme.colorOf(
                                    context,
                                    createFormHint,
                                    GenesisColors.darkInputPlaceholder,
                                  ),
                              fontSize: 14,
                              letterSpacing: 0,
                              height:
                                  widget.inputLineHeight ??
                                  (CreateFormTheme.isDarkOf(context)
                                      ? 1.4
                                      : 1.42),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_showsCounterInside) ...[
                  const SizedBox(width: 8),
                  _CreateFieldCounter(counter: _counterText),
                ],
              ],
            ),
          ),
          if (_hasSupportLine) ...[
            const SizedBox(height: 8),
            _CreateFieldSupportLine(
              note: widget.note,
              counter: _showsCounterOutside ? _counterText : null,
              leading: widget.supportLeading,
            ),
          ],
          if (widget.visibilityBottomPadding > 0)
            SizedBox(height: widget.visibilityBottomPadding),
        ],
      ),
    );
  }

  bool get _hasNote => widget.note?.trim().isNotEmpty == true;

  bool get _hasSupportLine =>
      widget.supportLeading != null || _hasNote || _showsCounterOutside;

  bool get _showsCounterInside =>
      widget.counterInside && widget.maxLength != null && widget.showCounter;

  bool get _showsCounterOutside =>
      !widget.counterInside && widget.maxLength != null && widget.showCounter;

  String get _counterText =>
      '${widget.controller.text.characters.length} / ${widget.maxLength}';

  bool get _isSingleLine =>
      (widget.maxLines ?? widget.minLines) == 1 && widget.minLines == 1;

  TextInputAction get _resolvedTextInputAction {
    final action = widget.textInputAction;
    if (action != null) return action;
    return _isSingleLine ? TextInputAction.done : TextInputAction.newline;
  }

  TextInputType get _resolvedKeyboardType {
    return _isSingleLine ? TextInputType.text : TextInputType.multiline;
  }

  bool get _shouldHandleEditingComplete {
    if (widget.onEditingComplete != null) return true;
    return _resolvedTextInputAction != TextInputAction.newline;
  }
}

class _CreateFieldSupportLine extends StatelessWidget {
  const _CreateFieldSupportLine({
    required this.note,
    required this.counter,
    required this.leading,
  });

  final String? note;
  final String? counter;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final normalizedNote = note?.trim() ?? '';
    final hasNote = normalizedNote.isNotEmpty;
    if (!hasNote && leading == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: _CreateFieldCounter(counter: counter ?? ''),
      );
    }
    if (!hasNote && leading != null) {
      return SizedBox(
        height: 32,
        child: Stack(
          children: [
            Align(alignment: Alignment.topLeft, child: leading),
            if (counter != null)
              Align(
                alignment: Alignment.topRight,
                child: _CreateFieldCounter(counter: counter!),
              ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) leading!,
        if (leading != null && hasNote) const SizedBox(width: 12),
        if (hasNote)
          Expanded(child: CreateFormNote(note: normalizedNote))
        else
          const Spacer(),
        if (counter != null) ...[
          const SizedBox(width: 12),
          _CreateFieldCounter(counter: counter!),
        ],
      ],
    );
  }
}

class CreateFormNote extends StatelessWidget {
  const CreateFormNote({super.key, required this.note, this.markdown = false});

  final String note;
  final bool markdown;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 0),
          child: SvgPicture.asset(
            createFormInfoIconAsset,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              CreateFormTheme.colorOf(
                context,
                createFormNote,
                GenesisColors.darkTextTertiary,
              ),
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _CreateFormNoteText(note: note, markdown: markdown),
        ),
      ],
    );
  }
}

class _CreateFormNoteText extends StatelessWidget {
  const _CreateFormNoteText({required this.note, required this.markdown});

  final String note;
  final bool markdown;

  @override
  Widget build(BuildContext context) {
    final baseStyle = GenesisTypography.withFallback(
      createFormSupportTextStyle.copyWith(
        color: CreateFormTheme.colorOf(
          context,
          createFormNote,
          GenesisColors.darkTextTertiary,
        ),
      ),
    );
    if (!markdown) {
      return Text(note, softWrap: true, style: baseStyle);
    }

    final platform = Theme.of(context).platform;
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: _markdownSpans(note, platform, baseStyle),
      ),
    );
  }

  List<InlineSpan> _markdownSpans(
    String value,
    TargetPlatform platform,
    TextStyle baseStyle,
  ) {
    final spans = <InlineSpan>[];
    var index = 0;
    while (index < value.length) {
      final boldStart = value.indexOf('**', index);
      final italicStart = value.indexOf('*', index);
      final nextStart = _nextMarkdownStart(boldStart, italicStart);
      if (nextStart < 0) {
        spans.add(TextSpan(text: value.substring(index)));
        break;
      }
      if (nextStart > index) {
        spans.add(TextSpan(text: value.substring(index, nextStart)));
      }

      if (boldStart == nextStart) {
        final end = value.indexOf('**', nextStart + 2);
        if (end < 0) {
          spans.add(TextSpan(text: value.substring(nextStart)));
          break;
        }
        spans.add(
          TextSpan(
            text: value.substring(nextStart + 2, end),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
        index = end + 2;
      } else {
        final end = value.indexOf('*', nextStart + 1);
        if (end < 0) {
          spans.add(TextSpan(text: value.substring(nextStart)));
          break;
        }
        spans.addAll(
          _inlineEmphasisSpans(
            value.substring(nextStart + 1, end),
            platform,
            baseStyle,
          ),
        );
        index = end + 1;
      }
    }
    return spans;
  }

  int _nextMarkdownStart(int boldStart, int italicStart) {
    final normalizedItalicStart = italicStart == boldStart
        ? _valueNotFound
        : italicStart;
    if (boldStart < 0) return normalizedItalicStart;
    if (normalizedItalicStart < 0) return boldStart;
    return boldStart < normalizedItalicStart
        ? boldStart
        : normalizedItalicStart;
  }
}

List<InlineSpan> _inlineEmphasisSpans(
  String text,
  TargetPlatform platform,
  TextStyle baseStyle,
) {
  final style = GenesisTypography.inlineEmphasis(baseStyle, platform: platform);
  if (platform != TargetPlatform.iOS ||
      !GenesisTypography.useIosSoftItalicSkew) {
    return <InlineSpan>[TextSpan(text: text, style: style)];
  }

  return _emphasisTextPieces(text)
      .map(
        (piece) => piece.trim().isEmpty
            ? TextSpan(text: piece, style: style)
            : _skewedInlineEmphasisSpan(piece, style),
      )
      .toList(growable: false);
}

InlineSpan _skewedInlineEmphasisSpan(String text, TextStyle style) {
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Transform(
      alignment: Alignment.center,
      transform: Matrix4.skewX(GenesisTypography.iosInlineEmphasisSkew),
      transformHitTests: false,
      child: Text(text, style: style),
    ),
  );
}

List<String> _emphasisTextPieces(String text) {
  final pieces = <String>[];
  for (final match in RegExp(r'\s+|[^\s]+').allMatches(text)) {
    final piece = match.group(0)!;
    if (piece.trim().isEmpty || !_shouldSplitEmphasisPiece(piece)) {
      pieces.add(piece);
      continue;
    }
    pieces.addAll(piece.runes.map(String.fromCharCode));
  }
  return pieces;
}

bool _shouldSplitEmphasisPiece(String piece) {
  var runeCount = 0;
  for (final rune in piece.runes) {
    runeCount += 1;
    if (rune > 0x7F || runeCount > 16) return true;
  }
  return false;
}

const int _valueNotFound = -1;

class _CreateFieldCounter extends StatelessWidget {
  const _CreateFieldCounter({required this.counter});

  final String counter;

  @override
  Widget build(BuildContext context) {
    return Text(
      counter,
      textAlign: TextAlign.right,
      style: createFormSupportTextStyle.copyWith(
        color: CreateFormTheme.colorOf(
          context,
          createFormMuted,
          GenesisColors.darkTextTertiary,
        ),
      ),
    );
  }
}
