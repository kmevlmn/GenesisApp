import 'package:flutter/material.dart';

import '../../utils/gem_amount.dart';

TextSpan gemBalanceTextSpan(int balanceCent, {required double fontSize}) {
  final amount = formatGemCent(balanceCent);
  final decimalIndex = amount.indexOf('.');
  return TextSpan(
    children: [
      TextSpan(text: amount.substring(0, decimalIndex)),
      TextSpan(
        text: amount.substring(decimalIndex),
        style: TextStyle(fontSize: fontSize * 0.7),
      ),
    ],
  );
}
