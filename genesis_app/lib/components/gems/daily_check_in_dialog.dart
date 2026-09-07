import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../common/genesis_action_box.dart';
import 'gem_assets.dart';
import 'gem_colors.dart';
import '../../utils/gem_amount.dart';

const int dailyCheckInPreviewRewardCent = 5000;
const String dailyCheckInTaskCode = 'daily_checkin';
const Duration dailyCheckInSuccessDuration = Duration(seconds: 3);

enum DailyCheckInDialogStatus { checkIn, claim, claimed }

Future<bool> showDailyCheckInDialog(
  BuildContext context, {
  required DailyCheckInDialogStatus status,
  int rewardGemsCent = dailyCheckInPreviewRewardCent,
}) async {
  final claimed = status == DailyCheckInDialogStatus.claimed;
  final shouldCheckIn = await showGenesisActionBox<bool>(
    context: context,
    title: 'Daily Check-in',
    titleContent: _GemTaskReward(
      rewardGemsCent: rewardGemsCent,
      showWholeReward: true,
    ),
    titleContentSpacing: 10,
    actions: [
      GenesisActionBoxAction<bool>(
        label: switch (status) {
          DailyCheckInDialogStatus.checkIn => 'Check in',
          DailyCheckInDialogStatus.claim => 'Claim',
          DailyCheckInDialogStatus.claimed => 'Claimed',
        },
        value: true,
        color: claimed ? kGemTaskClaimedForegroundColor : kGemAccentColor,
        enabled: !claimed,
      ),
    ],
    cancelLabel: 'Cancel',
  );
  return shouldCheckIn == true;
}

Future<void> showDailyCheckInSuccessDialog(
  BuildContext context, {
  int rewardGemsCent = dailyCheckInPreviewRewardCent,
  Duration duration = dailyCheckInSuccessDuration,
}) async {
  return showGemTaskSuccessDialog(
    context,
    title: 'Check in successful!',
    rewardGemsCent: rewardGemsCent,
    duration: duration,
  );
}

Future<void> showGemTaskSuccessDialog(
  BuildContext context, {
  required String title,
  required int rewardGemsCent,
  Duration duration = dailyCheckInSuccessDuration,
  bool showWholeReward = true,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final timer = Timer(duration, () {
    if (navigator.mounted && navigator.canPop()) navigator.pop();
  });
  try {
    await showGenesisActionBox<void>(
      context: context,
      title: title,
      titleContent: _GemTaskReward(
        rewardGemsCent: rewardGemsCent,
        showWholeReward: showWholeReward,
      ),
      titleContentSpacing: 10,
      actions: const [],
      showCancel: false,
    );
  } finally {
    timer.cancel();
  }
}

class _GemTaskReward extends StatelessWidget {
  const _GemTaskReward({
    required this.rewardGemsCent,
    this.showWholeReward = false,
  });

  final int rewardGemsCent;
  final bool showWholeReward;

  @override
  Widget build(BuildContext context) {
    final rewardText = showWholeReward
        ? formatWholeGemCent(rewardGemsCent)
        : formatGemCent(rewardGemsCent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '+$rewardText',
          key: const ValueKey<String>('gem-task-reward-value'),
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 15,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        SvgPicture.asset(
          gemIconAsset,
          key: const ValueKey<String>('gem-task-reward-icon'),
          width: gemSmallIconSize,
          height: gemSmallIconSize,
        ),
      ],
    );
  }
}
