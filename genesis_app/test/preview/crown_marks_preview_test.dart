import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/gems/pro_membership_badge.dart';
import 'package:genesis_flutter_android/icons/custom_icon_assets.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

/// The two crown marks in place: 27a as the Home entry, 26a beside a name.
void main() {
  testWidgets('render crown marks', (tester) async {
    tester.view.physicalSize = const Size(390, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      final font = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
      await font.load();
    });

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: GenesisTheme.dark(),
          home: Scaffold(
            backgroundColor: const Color(0xFF131215),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Home entry — 27e flat at 36',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: SvgPicture.asset(
                          proCrownFlatIconAsset,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Container(
                        width: 200,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF232228),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'Name mark — sized against its text',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Eve',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 6),
                      ProMembershipBadge.beside(fontSize: 20),
                      SizedBox(width: 34),
                      Text(
                        'Originator: u_A7BN1K',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          height: 1,
                        ),
                      ),
                      SizedBox(width: 4),
                      ProMembershipBadge.beside(fontSize: 12),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        'test/preview/crown_marks.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    });
  });
}
