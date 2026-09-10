import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/config/app_global_config.dart';

void main() {
  test('AppGlobalConfig defaults opening sheet to false', () {
    expect(const AppGlobalConfig().showOpeningSheet, isFalse);
    expect(const AppGlobalConfig().apiTraceSamplingRate, 0);
    expect(AppGlobalConfig.fromJson(const {}).showOpeningSheet, isFalse);
    expect(AppGlobalConfig.fromJson(const {}).apiTraceSamplingRate, 0);
  });

  test('AppGlobalConfig parses and clamps API trace sampling rate', () {
    expect(
      AppGlobalConfig.fromJson(const {
        'apiTraceSamplingRate': 0.25,
      }).apiTraceSamplingRate,
      0.25,
    );
    expect(
      AppGlobalConfig.fromJson(const {
        'api_trace_sampling_rate': 0.75,
      }).apiTraceSamplingRate,
      0.75,
    );
    expect(
      AppGlobalConfig.fromJson(const {
        'apiTraceSamplingRate': 2,
      }).apiTraceSamplingRate,
      1,
    );
    expect(
      AppGlobalConfig.fromJson(const {
        'apiTraceSamplingRate': -1,
      }).apiTraceSamplingRate,
      0,
    );
    expect(
      AppGlobalConfig.fromJson(const {
        'apiTraceSamplingRate': 'invalid',
      }).apiTraceSamplingRate,
      0,
    );
  });

  test('AppGlobalConfigStore loads and publishes app config', () async {
    final store = AppGlobalConfigStore(
      loadConfig: ({String? uid}) async => {
        'show_opening_sheet': true,
        'apiTraceSamplingRate': 0.5,
      },
    );
    addTearDown(store.dispose);

    await store.refresh();

    expect(store.value.showOpeningSheet, isTrue);
    expect(store.value.apiTraceSamplingRate, 0.5);
  });

  test('AppGlobalConfigStore deduplicates concurrent refreshes', () async {
    final response = Completer<Map<String, dynamic>>();
    var requestCount = 0;
    final store = AppGlobalConfigStore(
      loadConfig: ({String? uid}) {
        requestCount += 1;
        return response.future;
      },
    );
    addTearDown(store.dispose);

    final first = store.refresh();
    final second = store.refresh();
    response.complete({'show_opening_sheet': true});
    await Future.wait([first, second]);

    expect(requestCount, 1);
    expect(store.value.showOpeningSheet, isTrue);
  });

  test('AppGlobalConfigStore forwards the startup uid', () async {
    String? requestedUid;
    final store = AppGlobalConfigStore(
      loadConfig: ({String? uid}) async {
        requestedUid = uid;
        return const <String, dynamic>{};
      },
    );
    addTearDown(store.dispose);

    await store.refresh(uid: 'u_startup');

    expect(requestedUid, 'u_startup');
  });

  test(
    'request state preserves raw fields instead of client defaults',
    () async {
      final response = Completer<Map<String, dynamic>>();
      final store = AppGlobalConfigStore(
        loadConfig: ({String? uid}) => response.future,
      );
      addTearDown(store.dispose);
      expect(store.requestState.value.data, isNull);

      final refresh = store.refresh();
      expect(store.requestState.value.isLoading, isTrue);
      final data = <String, dynamic>{
        'apiTraceSamplingRate': 2,
        'future_config': {
          'enabled': true,
          'values': [1, '中文', null],
        },
      };
      response.complete(data);
      await refresh;

      expect(store.value.apiTraceSamplingRate, 1);
      expect(store.value.showOpeningSheet, isFalse);
      expect(store.requestState.value.data, data);
      expect(
        store.requestState.value.data!.containsKey('show_opening_sheet'),
        isFalse,
      );
      expect(store.requestState.value.isLoading, isFalse);
      expect(store.requestState.value.error, isNull);
    },
  );

  test(
    'failed refresh exposes its error and retains the last response',
    () async {
      var shouldFail = true;
      final error = StateError('config unavailable');
      final store = AppGlobalConfigStore(
        loadConfig: ({String? uid}) async {
          if (shouldFail) throw error;
          return {'show_opening_sheet': true};
        },
      );
      addTearDown(store.dispose);

      await expectLater(store.refresh(), throwsA(same(error)));
      expect(store.requestState.value.data, isNull);
      expect(store.requestState.value.error, same(error));
      expect(store.requestState.value.isLoading, isFalse);

      shouldFail = false;
      await store.refresh();
      expect(store.requestState.value.error, isNull);

      shouldFail = true;
      await expectLater(store.refresh(), throwsA(same(error)));
      expect(store.requestState.value.data, {'show_opening_sheet': true});
      expect(store.requestState.value.error, same(error));
      expect(store.value.showOpeningSheet, isTrue);
    },
  );

  test(
    'a late response does not publish after the store is disposed',
    () async {
      final response = Completer<Map<String, dynamic>>();
      final store = AppGlobalConfigStore(
        loadConfig: ({String? uid}) => response.future,
      );
      final refresh = store.refresh();
      store.dispose();
      response.complete({'show_opening_sheet': true});
      await refresh;
    },
  );
}
