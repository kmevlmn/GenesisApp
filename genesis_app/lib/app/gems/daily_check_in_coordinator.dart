import 'dart:async';

import 'package:flutter/material.dart';

import '../../components/common/genesis_center_toast.dart';
import '../../components/gems/daily_check_in_dialog.dart';
import '../../network/models/gem_task.dart';
import '../../network/models/gem_task_action.dart';
import '../../platform/session/user_session_store.dart';
import '../bootstrap/app_services_scope.dart';
import 'gem_task_analytics.dart';

typedef DailyCheckInTaskAction = Future<GemTaskActionResult> Function();
typedef DailyCheckInWalletRefresh = Future<void> Function();

Future<void> scheduleDailyCheckInAfterLogin(BuildContext context) async {
  if (!context.mounted) return;
  final services = AppServicesScope.read(context);
  final sessionRevision = services.sessionRevision.value;
  final uid = await services.sessionStore.readLoginUid();
  if (!context.mounted ||
      uid == null ||
      !identical(AppServicesScope.read(context), services) ||
      services.sessionRevision.value != sessionRevision) {
    return;
  }
  services.pendingLoginCheckInUid.value = uid;
}

/// Called by the main tabs only. Recheck visibility after the network request
/// so navigating to a detail page never brings the check-in prompt along with it.
Future<void> showPendingDailyCheckInAfterLogin(
  BuildContext context, {
  required bool Function() canShow,
}) async {
  if (!context.mounted || !canShow()) return;
  final services = AppServicesScope.read(context);
  final pending = services.pendingLoginCheckInUid;
  final uid = pending.value;
  if (uid == null) return;
  final sessionRevision = services.sessionRevision.value;
  bool isCurrentRequest() =>
      context.mounted &&
      identical(AppServicesScope.read(context), services) &&
      pending.value == uid &&
      services.sessionRevision.value == sessionRevision;

  final currentUid = await services.sessionStore.readLoginUid();
  if (!isCurrentRequest()) return;
  if (currentUid != uid) {
    pending.value = null;
    return;
  }
  if (!canShow()) return;
  late final GemTask? task;
  try {
    task = _findDailyCheckInTask((await services.api.v1.gem.tasks()).groups);
  } catch (_) {
    if (isCurrentRequest() && canShow()) pending.value = null;
    return;
  }
  if (!isCurrentRequest()) return;
  final latestUid = await services.sessionStore.readLoginUid();
  if (!isCurrentRequest()) return;
  if (latestUid != uid) {
    pending.value = null;
    return;
  }
  if (!context.mounted || !canShow()) return;
  pending.value = null;
  if (task == null) return;

  await runDailyCheckInFlow(
    context,
    task: task,
    reportTask: () => services.api.v1.gem.reportTask(dailyCheckInTaskCode),
    claimTask: () => services.api.v1.gem.claimTask(dailyCheckInTaskCode),
    refreshWallet: services.gemWallet.refresh,
  );
}

Future<void> runDailyCheckInFlow(
  BuildContext context, {
  required GemTask task,
  required DailyCheckInTaskAction reportTask,
  required DailyCheckInTaskAction claimTask,
  required DailyCheckInWalletRefresh refreshWallet,
}) async {
  var status = _dialogStatusForValue(task.status);
  if (status == DailyCheckInDialogStatus.claimed) return;
  while (context.mounted) {
    final shouldAct = await showDailyCheckInDialog(
      context,
      status: status,
      rewardGemsCent: task.rewardGemsCent,
    );
    if (!shouldAct || !context.mounted) return;

    try {
      final actionStatus = status;
      final action = switch (status) {
        DailyCheckInDialogStatus.checkIn => reportTask(),
        DailyCheckInDialogStatus.claim => claimTask(),
        DailyCheckInDialogStatus.claimed => null,
      };
      if (action == null) return;
      final result = await action;
      status = _dialogStatusForValue(result.status);
      if (actionStatus == DailyCheckInDialogStatus.claim) {
        trackGemTaskClaimedIfNeeded(
          taskCode: dailyCheckInTaskCode,
          status: result.status,
        );
      }
      if (actionStatus == DailyCheckInDialogStatus.checkIn &&
          status == DailyCheckInDialogStatus.claim) {
        final claimResult = await claimTask();
        status = _dialogStatusForValue(claimResult.status);
        trackGemTaskClaimedIfNeeded(
          taskCode: dailyCheckInTaskCode,
          status: claimResult.status,
        );
      }
      if (!context.mounted) return;
      if (status == DailyCheckInDialogStatus.claimed) {
        final successDialog = showDailyCheckInSuccessDialog(
          context,
          rewardGemsCent: task.rewardGemsCent,
        );
        unawaited(refreshWallet());
        await successDialog;
        return;
      }
    } catch (_) {
      if (!context.mounted) return;
      showGenesisToast(
        context,
        status == DailyCheckInDialogStatus.claim
            ? 'Claim failed.'
            : 'Check in failed.',
      );
      return;
    }
  }
}

GemTask? _findDailyCheckInTask(List<GemTaskGroup> groups) {
  for (final group in groups) {
    for (final task in group.tasks) {
      if (task.taskCode.trim() == dailyCheckInTaskCode) return task;
    }
  }
  return null;
}

DailyCheckInDialogStatus _dialogStatusForValue(String value) {
  return switch (value.trim().toLowerCase()) {
    'claimed' => DailyCheckInDialogStatus.claimed,
    'claimable' => DailyCheckInDialogStatus.claim,
    _ => DailyCheckInDialogStatus.checkIn,
  };
}
