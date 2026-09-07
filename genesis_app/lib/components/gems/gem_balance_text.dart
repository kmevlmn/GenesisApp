import 'package:flutter/painting.dart';

import '../../utils/gem_amount.dart';

TextSpan buildGemBalanceSpan(int balanceCent, {required double fontSize}) {
  final amount = formatGemCent(balanceCent);
  final decimalIndex = amount.indexOf('.');
  return TextSpan(
    text: amount.substring(0, decimalIndex),
    children: [
      TextSpan(
        text: amount.substring(decimalIndex),
        style: TextStyle(fontSize: fontSize * 0.7),
      ),
    ],
  );
}
