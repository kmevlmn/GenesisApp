import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readWorldPageImplementationSource() {
  return [
    'lib/pages/world/world_page.dart',
    'lib/pages/world/world_page_tabs.dart',
    'lib/pages/world/world_page_chatroom_session.dart',
    'lib/pages/world/world_page_detail_sync.dart',
    'lib/pages/world/world_page_tick_flow.dart',
    'lib/pages/world/world_page_location_chat.dart',
    'lib/pages/world/world_page_sheets.dart',
    'lib/pages/world/world_page_layout.dart',
  ].map((path) => File(path).readAsStringSync()).join('\n');
}

void main() {
  test('world owner rebuilds chatroom authentication without timers', () {
    final worldPage = _readWorldPageImplementationSource();
    final locationChat = File(
      'lib/pages/world/world_location_chat_host.dart',
    ).readAsStringSync();
    final recovery = worldPage.substring(
      worldPage.indexOf(
        'Future<void> _performWorldChatroomAuthenticationRecovery()',
      ),
      worldPage.indexOf('void _handleWorldChatroomState('),
    );

    expect(worldPage, contains('onFailure: _handleWorldChatroomFailure'));
    expect(recovery, contains('await service.dispose()'));
    expect(recovery, contains('final loggedIn = await ensureGenesisLogin'));
    expect(recovery, contains('continueAfterLogin: true'));
    expect(recovery, contains('await replacement.connect('));
    expect(recovery, contains('await replacement.join('));
    expect(recovery, isNot(contains('Future<void>.delayed(')));
    expect(recovery, isNot(contains('Timer(')));
    expect(locationChat, contains('unauthorizedHandledByOwner: true'));
  });
}
