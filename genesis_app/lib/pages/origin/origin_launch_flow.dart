import 'package:flutter/material.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/origin/origin_role_launch_sheet.dart';
import '../../network/models/origin.dart';

enum OriginLaunchSource {
  openingMessage(
    telemetryValue: 'opening_message',
    startAction: 'worldo_launch_message',
  );

  const OriginLaunchSource({
    required this.telemetryValue,
    required this.startAction,
  });

  final String telemetryValue;
  final String startAction;
}

Future<String?> startOriginLaunch({
  required BuildContext context,
  required OriginDetail origin,
  required OriginRoleLaunchSelection roleSelection,
  required OriginLaunchSource launchSource,
}) async {
  try {
    final services = AppServicesScope.of(context);
    final api = services.api;
    final result = await api.v1.origin.launch(
      oid: origin.oid,
      presetCharacterId: roleSelection.presetCharacterId,
      customRole: roleSelection.customRole?.toPayload(),
    );
    if (!context.mounted) return null;

    final wid = '${result['world_id'] ?? result['wid'] ?? ''}'.trim();
    if (wid.isEmpty) {
      showGenesisToast(context, 'Launch failed', brightness: Brightness.dark);
      return null;
    }
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'worldo_launch_submit_success',
      object1: origin.oid,
      object2: wid,
      object3: launchSource.telemetryValue,
    );
    return wid;
  } catch (_) {
    if (context.mounted) {
      showGenesisToast(context, 'Launch failed', brightness: Brightness.dark);
    }
    return null;
  }
}
