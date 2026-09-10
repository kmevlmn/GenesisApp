import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/network/models/gem_records.dart';
import 'package:genesis_flutter_android/pages/gems/gem_records_page.dart';

void main() {
  test('formats record time with the full date and time', () {
    expect(
      formatGemRecordTimestamp(_epochSeconds(DateTime(2026, 6, 3, 9, 2))),
      '2026-06-03 09:02',
    );
  });

  testWidgets('ends the list directly after the last record', (tester) async {
    var clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final data = Map<String, dynamic>.from(call.arguments as Map);
              clipboardText = '${data['text'] ?? ''}';
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: GemRecordsPage(
          recordsLoader: ({required scene, required pn, required rn}) async =>
              GemRecordList(
                items: const [
                  GemRecordItem(
                    ledgerId: 'ledger-1',
                    orderId: 'order-1',
                    amountCent: 5000,
                    scene: 'task',
                    reasonCode: 'daily_checkin',
                    title: 'Daily check-in',
                    subtitle: 'Daily task',
                    createdAt: 1,
                    expiresAt: 1893456000,
                    worldId: 'w_daily',
                  ),
                  GemRecordItem(
                    ledgerId: 'ledger-2',
                    amountCent: -400,
                    scene: 'world_tick',
                    reasonCode: 'location_message',
                    title: 'Message',
                    subtitle: 'Moonlit Market',
                    createdAt: 1,
                    expiresAt: 0,
                    worldName: 'Should not be used in title',
                    worldId: 'w_moonlit',
                    orderId: 'order-2',
                  ),
                ],
                total: 2,
                page: 1,
                pageSize: rn,
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gem-records-footer')), findsNothing);
    expect(find.byKey(const ValueKey('gem-record-primary-icon')), findsNothing);
    expect(find.byKey(const ValueKey('gem-record-amount-icon')), findsNothing);
    expect(find.textContaining('Expires'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Daily check-in')).dy -
          tester.getBottomLeft(find.byType(TabBar)).dy,
      closeTo(24, 0.1),
    );
    expect(
      tester.getTopLeft(find.text('Daily check-in')).dy -
          tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('gem-record-item-ledger-1')),
              )
              .dy,
      closeTo(12, 0.1),
    );
    final textBlockCenter =
        (tester.getTopLeft(find.text('Daily check-in')).dy +
            tester.getBottomLeft(find.text('w_daily')).dy) /
        2;
    final recordTime = find.text(formatGemRecordTimestamp(1)).first;
    expect(
      tester.getTopLeft(recordTime).dy -
          tester.getBottomLeft(find.text('Daily check-in')).dy,
      closeTo(8, 0.1),
    );
    expect(
      tester.getTopLeft(find.text('w_daily')).dy -
          tester.getBottomLeft(recordTime).dy,
      closeTo(8, 0.1),
    );
    expect(
      tester.getCenter(find.text('+50.0')).dy,
      closeTo(textBlockCenter, 0.1),
    );
    expect(
      tester.getTopLeft(find.text('Message')).dy -
          tester.getTopLeft(find.text('Daily check-in')).dy,
      closeTo(85, 0.1),
    );
    final messageWorldId = tester.widget<Text>(find.text('w_moonlit'));
    expect(messageWorldId.style?.color, GenesisColors.darkTextTertiary);
    expect(find.text('Daily task'), findsNothing);
    expect(find.text('Moonlit Market'), findsNothing);
    expect(find.text('ID: order-1'), findsNothing);
    expect(find.text('ID: ledger-1'), findsNothing);
    expect(find.text('ID: order-2'), findsNothing);
    await tester.tap(find.text('w_moonlit'));
    var copied = await Clipboard.getData('text/plain');
    expect(copied?.text, 'w_moonlit');
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('w_daily'));
    copied = await Clipboard.getData('text/plain');
    expect(copied?.text, 'w_daily');
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('gem-record-item-ledger-1')),
          )
          .height,
      closeTo(85, 0.1),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('gem-record-item-ledger-2')),
          )
          .height,
      closeTo(85, 0.1),
    );
  });

  testWidgets('does not show the footer while another page is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GemRecordsPage(
          recordsLoader: ({required scene, required pn, required rn}) async =>
              const GemRecordList(
                items: [
                  GemRecordItem(
                    ledgerId: 'ledger-1',
                    amountCent: -400,
                    scene: 'world_tick',
                    reasonCode: 'message',
                    title: 'Message',
                    subtitle: 'Location chat',
                    createdAt: 1,
                    expiresAt: 0,
                  ),
                ],
                total: 2,
                page: 1,
                pageSize: 1,
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gem-records-footer')), findsNothing);
  });
}

int _epochSeconds(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;
