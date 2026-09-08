import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../network/json_utils.dart';

typedef AppGlobalConfigLoader =
    Future<Map<String, dynamic>> Function({String? uid});

@immutable
class AppGlobalConfig {
  const AppGlobalConfig({
    this.showOpeningSheet = false,
    this.apiTraceSamplingRate = 0,
  });

  factory AppGlobalConfig.fromJson(Map<String, dynamic> json) {
    return AppGlobalConfig(
      showOpeningSheet: asBool(json['show_opening_sheet']),
      apiTraceSamplingRate: _samplingRate(
        json['apiTraceSamplingRate'] ?? json['api_trace_sampling_rate'],
      ),
    );
  }

  final bool showOpeningSheet;
  final double apiTraceSamplingRate;
}

double _samplingRate(Object? value) {
  final parsed = switch (value) {
    num value => value.toDouble(),
    String value => double.tryParse(value),
    _ => null,
  };
  if (parsed == null || !parsed.isFinite) return 0;
  return parsed.clamp(0.0, 1.0).toDouble();
}

@immutable
class AppGlobalConfigRequestState {
  const AppGlobalConfigRequestState({
    this.isLoading = false,
    this.data,
    this.error,
  });

  final bool isLoading;

  /// The last successful response's data, before applying client defaults.
  final Map<String, dynamic>? data;
  final Object? error;
}

class AppGlobalConfigStore extends ValueNotifier<AppGlobalConfig> {
  AppGlobalConfigStore({
    required AppGlobalConfigLoader loadConfig,
    AppGlobalConfig initialValue = const AppGlobalConfig(),
  }) : _loadConfig = loadConfig,
       super(initialValue);

  final AppGlobalConfigLoader _loadConfig;
  Future<void>? _refreshInFlight;
  final _requestState = ValueNotifier<AppGlobalConfigRequestState>(
    const AppGlobalConfigRequestState(),
  );
  bool _disposed = false;

  ValueListenable<AppGlobalConfigRequestState> get requestState =>
      _requestState;

  Future<void> refresh({String? uid}) {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final refresh = _refresh(uid: uid);
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
  }

  Future<void> _refresh({String? uid}) async {
    final previousData = _requestState.value.data;
    _requestState.value = AppGlobalConfigRequestState(
      isLoading: true,
      data: previousData,
    );
    try {
      final data = await _loadConfig(uid: uid);
      final config = AppGlobalConfig.fromJson(data);
      if (_disposed) return;
      _requestState.value = AppGlobalConfigRequestState(
        data: Map<String, dynamic>.unmodifiable(data),
      );
      value = config;
    } catch (error) {
      if (!_disposed) {
        _requestState.value = AppGlobalConfigRequestState(
          data: previousData,
          error: error,
        );
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestState.dispose();
    super.dispose();
  }
}
