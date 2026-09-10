import 'package:flutter/material.dart';

import 'origin_draft_repository.dart';
import 'origin_debug_random_action.dart';

export 'origin_debug_random_action.dart';

OriginDebugDraftGenerator? createOriginDebugDraftGenerator() => null;

OriginDebugDraftGenerator? editOriginDebugDraftGenerator(
  TextEditingController updateNotesController,
) => null;

VoidCallback registerOriginDebugRandomAction({
  required BuildContext context,
  required String Function() label,
  required OriginDraftRepository Function() repository,
  required OriginDebugDraftGenerator? Function() generator,
  required bool Function() enabled,
  required Future<void> Function() onGenerated,
}) => () {};

OriginDebugRandomAction? captureOriginDebugRandomAction() => null;

Widget? buildOriginDebugRandomContentButton({
  required OriginDebugRandomAction? action,
}) => null;
