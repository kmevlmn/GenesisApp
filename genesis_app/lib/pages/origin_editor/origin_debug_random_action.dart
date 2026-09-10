import 'dart:async';

import 'package:flutter/widgets.dart';

import '../create/create_origin_draft_store.dart';

typedef OriginDebugDraftGenerator =
    FutureOr<CreateOriginDraft> Function(
      BuildContext context,
      CreateOriginDraft currentDraft,
    );

/// A Developer action bound to the editor from which Developer was opened.
abstract interface class OriginDebugRandomAction {
  String get label;
  bool get isEnabled;
  Future<void> generate();
}
