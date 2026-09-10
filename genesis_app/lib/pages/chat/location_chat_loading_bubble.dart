import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../components/chat/shared/chat_ui.dart';

/// A transient reply placeholder; never added to the persisted message queue.
class LocationChatLoadingBubble extends StatefulWidget {
  const LocationChatLoadingBubble({super.key, required this.style});

  final ChatUiStyleConfig style;

  @override
  State<LocationChatLoadingBubble> createState() =>
      _LocationChatLoadingBubbleState();
}

class _LocationChatLoadingBubbleState extends State<LocationChatLoadingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Generating reply',
    child: Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Align(
        alignment: Alignment.center,
        child: RepaintBoundary(
          child: _surface(
            Container(
              key: const ValueKey('location-chat-loading-bubble'),
              width: 76,
              height: 42,
              decoration: BoxDecoration(
                color: widget.style.otherBubbleColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Transform.scale(
                          key: ValueKey('location-chat-loading-dot-$i'),
                          scale:
                              0.6 +
                              0.6 *
                                  (0.5 +
                                      0.5 *
                                          math.sin(
                                            2 *
                                                math.pi *
                                                (_animation.value - i / 3),
                                          )),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
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
      ),
    ),
  );

  Widget _surface(Widget child) {
    final style = widget.style;
    return style.useScenePlateBubbleGeometry &&
            style.bubbleBackdropBlurSigma > 0
        ? ChatStableBackdropSurface(
            borderRadius: BorderRadius.circular(14),
            sigma: style.bubbleBackdropBlurSigma,
            child: child,
          )
        : child;
  }
}
