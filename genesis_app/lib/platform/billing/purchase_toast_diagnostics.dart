import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../network/api_exception.dart';
import 'billing_models.dart';

/// Keep diagnostic data separate from the existing customer-facing message.
String purchaseToastMessage(String message, {required String debugInfo}) {
  if (!kDebugMode) return message;
  return 'debug：${_singleLine(debugInfo)}\n$message';
}

String purchaseDebugInfo(
  String stage, {
  String? status,
  String? reason,
  String? errorCode,
  String? errorMessage,
  Object? error,
}) {
  if (!kDebugMode) return '';
  final details = <String>[
    stage,
    if (status != null) 'status=$status',
    if (reason != null) 'reason=${reason.isEmpty ? '(empty)' : reason}',
    if (errorCode?.isNotEmpty == true) 'code=$errorCode',
    if (errorMessage?.isNotEmpty == true) 'message=$errorMessage',
    if (error != null) _errorInfo(error),
  ];
  return _singleLine(details.join('; '));
}

String _errorInfo(Object error) => switch (error) {
  ApiException() => [
    'ApiException',
    'kind=${error.kind.name}',
    if (error.code != null) 'code=${error.code}',
    if (error.statusCode != null) 'http=${error.statusCode}',
    if (error.clientFailureCode != null)
      'client_code=${error.clientFailureCode!.value}',
    if (error.uri != null) 'path=${error.uri!.path}',
    if (error.message.isNotEmpty) 'message=${error.message}',
  ].join('; '),
  BillingPlatformException() =>
    'BillingPlatformException; code=${error.code}; message=${error.message}',
  PlatformException() =>
    'PlatformException; code=${error.code}; message=${error.message ?? ''}',
  StateError() => 'StateError; ${error.message}',
  FormatException() => 'FormatException; ${error.message}',
  _ => error.runtimeType.toString(),
};

// Never include receipt bodies, exception sources, platform details or headers.
// Also remove credentials/identifiers if a server/SDK echoes them in a message.
String _singleLine(String value) {
  var result = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  result = result.replaceAll(
    RegExp(
      r'''["']?(?:purchase_?token|claim_?token|account_?uuid|authorization|receipt|signed_?transaction|original_?json)["']?\s*[=:]\s*(?:"[^"]*"|'[^']*'|[^\s;,]+)''',
      caseSensitive: false,
    ),
    '[redacted]',
  );
  result = result.replaceAll(
    RegExp(
      r'\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b',
      caseSensitive: false,
    ),
    '[redacted]',
  );
  result = result.replaceAll(
    RegExp(r'\bBearer\s+[^\s;,]+', caseSensitive: false),
    '[redacted]',
  );
  result = result.replaceAll(
    RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
    '[redacted]',
  );
  return result;
}
