import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final featureRoot = Directory('$root/lib/features/location_chat_reply');
  const features = ['regenerate', 'go_on', 'edit', 'inspiration'];

  test(
    'each reply feature has one public entry and private implementation',
    () {
      for (final feature in features) {
        expect(
          File('${featureRoot.path}/$feature/$feature.dart').existsSync(),
          isTrue,
          reason: '$feature must expose one public entry file',
        );
        expect(
          Directory('${featureRoot.path}/$feature/src').existsSync(),
          isTrue,
          reason: '$feature implementation must stay under src/',
        );
      }
    },
  );

  test('other libraries do not import feature src files', () {
    final violations = <String>[];
    for (final entity in Directory('$root/lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.startsWith(featureRoot.path)) continue;
      final contents = entity.readAsStringSync();
      for (final line in contents.split('\n')) {
        final isImportOrExport =
            line.trimLeft().startsWith('import ') ||
            line.trimLeft().startsWith('export ');
        if (isImportOrExport &&
            line.contains('features/location_chat_reply/') &&
            line.contains('/src/')) {
          violations.add('${entity.path}: $line');
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('shared hosts contain no feature action implementation', () {
    final page = File(
      '$root/lib/pages/chat/location_chat_page.dart',
    ).readAsStringSync();
    final controller = File(
      '$root/lib/network/chatroom/chatroom_reply_actions_controller.dart',
    ).readAsStringSync();
    final actionHost = File(
      '$root/lib/pages/chat/location_chat_reply_actions.dart',
    ).readAsStringSync();
    final listHost = File(
      '$root/lib/pages/chat/location_chat_scroll_coordinator.dart',
    ).readAsStringSync();

    expect(page, contains('regenerateFeature:'));
    expect(page, contains('goOnFeature:'));
    expect(page, contains('editFeature:'));
    expect(page, contains('inspirationFeature:'));
    expect(page, isNot(contains('controller.regenerate(')));
    expect(page, isNot(contains('controller.goOn(')));

    expect(controller, isNot(contains('Future<void> regenerate(')));
    expect(controller, isNot(contains('Future<ChatroomGoOnReceipt> goOn(')));
    expect(
      controller,
      isNot(contains('Future<ChatroomReplyEditorTarget> prepareEditor(')),
    );
    for (final legacyParameter in [
      'final VoidCallback? onRegenerate',
      'final VoidCallback? onGoOn',
      'final VoidCallback? onEditReply',
      'final List<String> inspirationMessages',
    ]) {
      expect(actionHost, isNot(contains(legacyParameter)));
      expect(listHost, isNot(contains(legacyParameter)));
    }
  });
}
