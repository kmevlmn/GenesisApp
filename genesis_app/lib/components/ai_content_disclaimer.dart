import 'package:flutter/material.dart';

const String kAiContentDisclaimerText =
    'All content is AI-generated and fictional. Any resemblance to real people, events, or places is coincidental.';

const TextStyle kAiContentDisclaimerTextStyle = TextStyle(
  fontSize: 12,
  height: 1.4,
  fontWeight: FontWeight.w400,
  color: Color(0xFF888888),
);

class AiContentDisclaimer extends StatelessWidget {
  const AiContentDisclaimer({
    super.key,
    this.text = kAiContentDisclaimerText,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 16),
    this.textAlign = TextAlign.center,
    this.textColor,
  });

  final String text;
  final EdgeInsetsGeometry padding;
  final TextAlign textAlign;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text,
        textAlign: textAlign,
        style: textColor == null
            ? kAiContentDisclaimerTextStyle
            : kAiContentDisclaimerTextStyle.copyWith(color: textColor),
      ),
    );
  }
}
