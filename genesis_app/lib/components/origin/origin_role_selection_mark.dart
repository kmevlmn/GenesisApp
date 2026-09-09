import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';

enum OriginRoleSelectionMarkStyle { checkbox, star }

class OriginRoleSelectionMark extends StatelessWidget {
  const OriginRoleSelectionMark({
    super.key,
    required this.selected,
    this.semanticLabel,
    this.style = OriginRoleSelectionMarkStyle.checkbox,
    this.starUnselectedColor = const Color(0xFF999999),
  });

  final bool selected;
  final String? semanticLabel;
  final OriginRoleSelectionMarkStyle style;
  final Color starUnselectedColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: style == OriginRoleSelectionMarkStyle.star,
      label: semanticLabel,
      child: style == OriginRoleSelectionMarkStyle.star
          ? _OriginRoleStarMark(
              selected: selected,
              unselectedColor: starUnselectedColor,
            )
          : _OriginRoleCheckboxMark(selected: selected),
    );
  }
}

class _OriginRoleStarMark extends StatelessWidget {
  const _OriginRoleStarMark({
    required this.selected,
    required this.unselectedColor,
  });

  final Color unselectedColor;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 16,
      child: Transform.scale(
        scale: 1.2,
        child: Icon(
          selected ? Icons.star_rounded : Icons.star_border_rounded,
          size: 16,
          color: selected ? GenesisColors.redPrimary : unselectedColor,
        ),
      ),
    );
  }
}

class _OriginRoleCheckboxMark extends StatelessWidget {
  const _OriginRoleCheckboxMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: selected ? GenesisColors.brand : Colors.white10,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: selected
          ? const Icon(Icons.check, size: 18, color: Colors.white)
          : null,
    );
  }
}
