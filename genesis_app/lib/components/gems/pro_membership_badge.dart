import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../icons/custom_icon_assets.dart';
import 'pro_colors.dart';

/// Compact burgundy and gold membership badge for inline username labels.
class ProMembershipBadge extends StatelessWidget {
  const ProMembershipBadge({super.key, this.height = 20});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pro membership',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: height * 2.5,
        height: height,
        child: FittedBox(
          child: Container(
            width: 50,
            height: 20,
            padding: const EdgeInsets.all(0.65),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE0BE7C), Color(0xFFB98943)],
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3.35),
                border: Border.all(color: proLightGold, width: 0.6),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF841A32),
                    Color(0xFF590C20),
                    Color(0xFF3C0716),
                  ],
                  stops: [0, 0.55, 1],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    proCrownFilledIconAsset,
                    width: 18,
                    height: 18,
                  ),
                  const SizedBox(width: 2),
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFFFF2C6),
                        Color(0xFFF5DFA3),
                        Color(0xFFD8AF64),
                      ],
                      stops: [0, 0.45, 1],
                    ).createShader(bounds),
                    child: const Text(
                      'Pro',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
