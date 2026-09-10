// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';

/// Correlates native StoreKit preparation with one Dart checkout.
class StoreKitPurchaseHandoff {
  static const channel = MethodChannel('worldo/storekit_purchase_handoff');
  static final _callbacks = <String, bool Function()>{};
  static final _epoch = DateTime.now().microsecondsSinceEpoch;
  static int _sequence = 0;
  static bool _listening = false;

  static Future<T> run<T>(
    bool Function() onHandoff,
    Future<T> Function(String id) purchase,
  ) async {
    if (!_listening) {
      channel.setMethodCallHandler((call) async {
        if (call.method != 'ready') return false;
        final callback = _callbacks.remove(call.arguments);
        // Unknown/stale calls must never authorize a new platform payment.
        if (callback == null) return false;
        try {
          return callback();
        } catch (_) {
          return false;
        }
      });
      _listening = true;
    }
    final id = '$_epoch-${++_sequence}';
    _callbacks[id] = onHandoff;
    try {
      return await purchase(id);
    } finally {
      _callbacks.remove(id);
    }
  }
}
