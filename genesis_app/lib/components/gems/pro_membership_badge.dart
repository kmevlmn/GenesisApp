import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../icons/custom_icon_assets.dart';

/// Membership mark for inline username labels — the 26a crown on its own,
/// as design 9k2 sets it beside the profile name. No plate, no wordmark.
class ProMembershipBadge extends StatelessWidget {
  const ProMembershipBadge({super.key, this.height = _nameHeight});

  /// Sizes the crown against the text it sits beside, keeping 9k2's ratio
  /// wherever the mark appears — a 20 name and a 12 meta row want very
  /// different crowns.
  const ProMembershipBadge.beside({super.key, required double fontSize})
    : height = fontSize * _heightPerTextSize;

  /// 9k2 sets a 17-high crown against a 24 name.
  static const double _nameHeight = 17;
  static const double _heightPerTextSize = _nameHeight / 24;

  /// The crown's own proportions; width follows from it.
  static const double _aspect = 96 / 68;

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Premium membership',
      image: true,
      excludeSemantics: true,
      child: SvgPicture.asset(
        proCrownGoldIconAsset,
        width: height * _aspect,
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}
