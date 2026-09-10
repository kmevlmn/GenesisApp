import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/chat/shared/chat_ui.dart';
import 'package:genesis_flutter_android/components/ai_content_disclaimer.dart';
import 'package:genesis_flutter_android/network/models/origin.dart';
import 'package:genesis_flutter_android/pages/chat/location_chat_page.dart';
import 'package:genesis_flutter_android/pages/origin/origin_world_layout.dart';
import 'package:genesis_flutter_android/pages/origin/origin_world_page.dart';
import 'package:genesis_flutter_android/platform/keyboard/genesis_keyboard_animation.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_radii.dart';

void main() {
  final originWorldPageSource = File(
    'lib/pages/origin/origin_world_page.dart',
  ).readAsStringSync();
  final originWorldDetailSheetSource = File(
    'lib/pages/origin/origin_world_detail_sheet.dart',
  ).readAsStringSync();
  final originWorldSheetInteractionSource = File(
    'lib/pages/origin/origin_world_sheet_interaction.dart',
  ).readAsStringSync();
  final originWorldMapShellSource = File(
    'lib/pages/origin/origin_world_map_shell.dart',
  ).readAsStringSync();
  final originWorldLocationChatSource = File(
    'lib/pages/origin/origin_world_location_chat.dart',
  ).readAsStringSync();
  final originSectionsSource = [
    'lib/pages/origin/origin_world_sections.dart',
    'lib/pages/origin/origin_world_role_setup.dart',
    'lib/pages/origin/origin_world_launched_worlds.dart',
    'lib/pages/origin/origin_world_characters.dart',
  ].map((path) => File(path).readAsStringSync()).join('\n');

  test('origin detail sheet uses main ui horizontal padding', () {
    expect(originDetailSheetHorizontalPaddingForTesting, 12);
  });

  test('origin page and detail sheet share the base background', () {
    expect(originWorldDetailSheetBackgroundColor, const Color(0xFF151517));
    expect(GenesisColors.darkRaisedBackground, const Color(0xFF181C1F));
    expect(
      originWorldMapShellSource,
      contains('backgroundColor: originWorldDetailSheetBackgroundColor'),
    );
  });

  test('origin detail sheet uses the requested dark color tiers', () {
    expect(originWorldDetailSheetPrimaryTextColor, const Color(0xF2FFFFFF));
    expect(originWorldDetailSheetSecondaryTextColor, const Color(0xB8FFFFFF));
    expect(originWorldDetailSheetTertiaryTextColor, const Color(0x73FFFFFF));
    expect(originWorldDetailSheetSoftWhiteColor, const Color(0xFFF4F3F6));
    expect(GenesisColors.redSecondary, const Color(0xFFFF8A9A));
    expect(originWorldDetailSheetSubtleSurfaceColor, const Color(0x14FFFFFF));
    expect(originWorldDetailSheetSelectRoleArrowColor, const Color(0x8CFFFFFF));
  });

  test('origin role card paints its outline above the card content', () {
    expect(
      originSectionsSource,
      contains("'origin-setup-role-card-frame-\$stableId'"),
    );
    expect(
      originSectionsSource,
      contains('foregroundDecoration: BoxDecoration'),
    );
  });

  test('origin opening dialogue and composer reuse Location Chat styling', () {
    expect(
      originSectionsSource,
      contains('kLocationChatStyle.copyWith(bubbleBackdropBlurSigma: 0)'),
    );
    expect(
      originWorldLocationChatSource,
      contains('_originDetailSheetChatComposerStyle => kLocationChatStyle;'),
    );
    expect(
      originWorldDetailSheetSource,
      isNot(contains('inputDockBackgroundColor:')),
    );
    expect(
      originWorldLocationChatSource,
      isNot(contains('_originLocationChatRoleInputGap')),
    );
    expect(originWorldDetailSheetSource, contains('showShortcuts: false'));
    expect(originWorldDetailSheetSource, contains('enableMentionSheet: false'));
    expect(originWorldDetailSheetSource, contains('roleBorderRadius: 8'));
    expect(
      originWorldDetailSheetSource,
      contains('bottomNavigationBar: openingComposer != null'),
    );
    expect(originWorldDetailSheetSource, isNot(contains('composerLifted')));
    expect(
      originWorldDetailSheetSource,
      contains('origin-opening-docked-composer-bottom-spacer'),
    );
    expect(
      originWorldDetailSheetSource,
      isNot(contains('origin-opening-composer-layout-boundary')),
    );
    expect(
      originWorldDetailSheetSource,
      contains('resizeToAvoidBottomInset: false'),
    );
    expect(
      originWorldDetailSheetSource,
      isNot(contains('origin-opening-keyboard-message-overlay')),
    );
    expect(
      originWorldDetailSheetSource,
      isNot(contains('_openingKeyboardScrollController')),
    );
    expect(
      originWorldDetailSheetSource,
      contains('_OriginSliverPaintTranslation('),
    );
    expect(
      originWorldDetailSheetSource,
      isNot(contains('_expandedOpeningComposerTop')),
    );
    expect(
      originWorldDetailSheetSource,
      isNot(contains('_scheduleOpeningComposerPositionUpdate')),
    );
  });

  test('origin opening composer keeps one system dock during IME motion', () {
    expect(
      originWorldDetailSheetSource,
      contains('bottomNavigationBar: openingComposer != null'),
    );
    expect(
      originWorldDetailSheetSource,
      contains('_sheetInteraction.composerTranslation()'),
    );
    expect(originWorldDetailSheetSource, isNot(contains('composerLifted')));
  });

  test('origin sheet keeps hot interaction rebuilds locally scoped', () {
    expect(
      originWorldDetailSheetSource,
      isNot(
        contains(
          'animation: Listenable.merge([\n'
          '                            _sheetController,\n'
          '                            _pageController,\n'
          '                            _roleEditing,',
        ),
      ),
    );
    expect(
      originWorldDetailSheetSource,
      contains('animation: _sheetInteraction.keyboardFrameListenable'),
    );
    expect(
      originWorldSheetInteractionSource,
      contains('_notifyKeyboardFrameChanged();'),
    );
    expect(
      originWorldDetailSheetSource,
      contains(
        'actualKeyboardInset:\n'
        '                                _sheetInteraction.keyboardInset',
      ),
    );
    expect(
      originWorldDetailSheetSource,
      isNot(
        contains(
          'bottomSafeAreaInset: MediaQuery.viewInsetsOf(context).bottom',
        ),
      ),
    );
    expect(originSectionsSource, contains('SliverChildBuilderDelegate('));
    expect(originSectionsSource, contains('addAutomaticKeepAlives: false'));
    expect(originSectionsSource, contains('addRepaintBoundaries: true'));
    expect(originSectionsSource, contains('child: RepaintBoundary('));
    expect(originSectionsSource, isNot(contains('imageUrls.indexOf(')));
  });

  test('origin opening dialogue warms only while the sheet is stable', () {
    expect(
      originOpeningDialogueWarmupAllowedForTesting(
        hasMessages: true,
        autoExpansionPending: false,
        keyboardMode: false,
        roleEditing: false,
        openingPageSettled: true,
        sheetInteractionActive: false,
        extentAnimationActive: false,
      ),
      isTrue,
    );
    for (final blocked in <Map<String, bool>>[
      {'autoExpansionPending': true},
      {'keyboardMode': true},
      {'roleEditing': true},
      {'openingPageSettled': false},
      {'sheetInteractionActive': true},
      {'extentAnimationActive': true},
    ]) {
      expect(
        originOpeningDialogueWarmupAllowedForTesting(
          hasMessages: true,
          autoExpansionPending: blocked['autoExpansionPending'] ?? false,
          keyboardMode: blocked['keyboardMode'] ?? false,
          roleEditing: blocked['roleEditing'] ?? false,
          openingPageSettled: blocked['openingPageSettled'] ?? true,
          sheetInteractionActive: blocked['sheetInteractionActive'] ?? false,
          extentAnimationActive: blocked['extentAnimationActive'] ?? false,
        ),
        isFalse,
        reason: 'Warmup must wait while $blocked is active.',
      );
    }
    expect(
      originOpeningDialogueWarmupAllowedForTesting(
        hasMessages: false,
        autoExpansionPending: false,
        keyboardMode: false,
        roleEditing: false,
        openingPageSettled: true,
        sheetInteractionActive: false,
        extentAnimationActive: false,
      ),
      isFalse,
    );
  });

  test('origin opening dialogue fully caches after warmup or keyboard', () {
    expect(
      originOpeningDialogueShouldFullyCacheForTesting(
        keyboardMode: false,
        warmupCompleted: false,
      ),
      isFalse,
    );
    expect(
      originOpeningDialogueShouldFullyCacheForTesting(
        keyboardMode: false,
        warmupCompleted: true,
      ),
      isTrue,
    );
    expect(
      originOpeningDialogueShouldFullyCacheForTesting(
        keyboardMode: true,
        warmupCompleted: false,
      ),
      isTrue,
    );
    expect(
      originWorldDetailSheetSource,
      contains('_scheduleOpeningDialogueWarmupAfterPaint();'),
    );
  });

  test('origin sheet interaction is packaged outside the sheet UI', () {
    expect(
      originWorldPageSource,
      contains("part 'origin_world_sheet_interaction.dart';"),
    );
    expect(
      originWorldSheetInteractionSource,
      contains('class _OriginWorldSheetInteractionController'),
    );
    expect(
      originWorldSheetInteractionSource,
      contains('void handleComposerFocusChanged(bool hasFocus)'),
    );
    expect(
      originWorldSheetInteractionSource,
      contains('bool handlePageScrollEnd(ScrollEndNotification notification)'),
    );
    expect(
      originWorldSheetInteractionSource,
      contains('bool isCollapsedRoleActionVisible'),
    );
    expect(
      originWorldSheetInteractionSource,
      contains('class _OriginRoleEditorInteractionController'),
    );
    expect(
      originWorldSheetInteractionSource,
      contains('enum _OriginRoleEditorPhase'),
    );
    expect(originSectionsSource, isNot(contains('_positionEditingCard')));
    expect(
      originSectionsSource,
      isNot(contains('_keyboardSettlePositionTimer')),
    );
    expect(
      originWorldDetailSheetSource,
      isNot(contains('void _updateOpeningKeyboardInset(double rawInset)')),
    );
    expect(originWorldDetailSheetSource, contains('DraggableScrollableSheet('));
    expect(
      originWorldDetailSheetSource,
      contains('void _handleCollapsedRoleDragUpdate'),
    );
    expect(
      originWorldDetailSheetSource,
      contains('Future<void> _animateToRequestedExtent'),
    );
  });

  test('origin role editor targets a 30px keyboard gap', () {
    const sheetHeight = 800.0;
    const keyboardInset = 300.0;
    const cardBottom = 540.0;
    final target = originRoleEditorTargetScrollOffsetForTesting(
      startScrollOffset: 200,
      cardBottom: cardBottom,
      viewHeight: sheetHeight,
      keyboardInset: keyboardInset,
    );

    expect(target, 270);
    final translatedCardBottom = cardBottom - (target - 200);
    expect(sheetHeight - keyboardInset - translatedCardBottom, 30);
  });

  test('origin role editor uses the safe-area content coordinate', () {
    final target = originRoleEditorTargetScrollOffsetForTesting(
      startScrollOffset: 200,
      cardBottom: 540,
      viewHeight: 844,
      keyboardInset: 280,
      bottomSafeAreaInset: 34,
    );

    expect(target, 206);
    final translatedCardBottom = 540 - (target - 200);
    final usableViewBottom = 844 - 34;
    final effectiveKeyboardInset = 280 - 34;
    expect(
      usableViewBottom - effectiveKeyboardInset - translatedCardBottom,
      30,
    );
  });

  test('origin role editor keeps the keyboard gap on a short viewport', () {
    final target = originRoleEditorTargetScrollOffsetForTesting(
      startScrollOffset: 100,
      cardBottom: 400,
      viewHeight: 500,
      keyboardInset: 300,
    );

    expect(target, 330);
    expect(500 - 300 - (400 - (target - 100)), 30);
  });

  test('origin role editor preserves a negative target for short content', () {
    expect(
      originRoleEditorTargetScrollOffsetForTesting(
        startScrollOffset: 0,
        cardBottom: 200,
        viewHeight: 800,
        keyboardInset: 300,
      ),
      -270,
      reason:
          'A negative logical target is retained as paint translation when '
          'there is no leading scroll extent to commit.',
    );
  });

  test('origin role editor retains its temporary scroll extent at settle', () {
    final initialExtent = originRoleEditorAdditionalScrollExtentForTesting(
      targetScrollOffset: 300,
      minScrollExtent: 0,
      currentMaxScrollExtent: 200,
      retainedAdditionalExtent: 0,
    );
    expect(initialExtent, 100);

    expect(
      originRoleEditorAdditionalScrollExtentForTesting(
        targetScrollOffset: 300,
        minScrollExtent: 0,
        currentMaxScrollExtent: 300,
        retainedAdditionalExtent: initialExtent,
      ),
      100,
      reason:
          'The expanded max extent includes the temporary spacer and must not '
          'make the settle pass remove that spacer.',
    );
  });

  test('origin role editor spacer includes the bottom safe area', () {
    expect(
      originRoleEditorAdditionalScrollExtentForTesting(
        targetScrollOffset: 300,
        minScrollExtent: 0,
        currentMaxScrollExtent: 200,
        retainedAdditionalExtent: 0,
        bottomSafeAreaInset: 34,
      ),
      134,
    );
    expect(
      originRoleEditorAdditionalScrollExtentForTesting(
        targetScrollOffset: 180,
        minScrollExtent: 0,
        currentMaxScrollExtent: 200,
        retainedAdditionalExtent: 0,
        bottomSafeAreaInset: 34,
      ),
      0,
      reason: 'Do not add a spacer when the target is already reachable.',
    );
  });

  test('origin role editor close progress cannot reverse near zero inset', () {
    final progressAt24 = originRoleEditorClosingProgressForTesting(
      startInset: 280,
      currentInset: 24,
      previousProgress: 0,
    );
    expect(progressAt24, closeTo(256 / 280, 0.0001));
    expect(
      originRoleEditorClosingProgressForTesting(
        startInset: 280,
        currentInset: 30,
        previousProgress: progressAt24,
      ),
      progressAt24,
      reason:
          'A small IME/safe-area rebound must not move the role card back up.',
    );
    expect(
      originRoleEditorClosingProgressForTesting(
        startInset: 280,
        currentInset: 0,
        previousProgress: progressAt24,
      ),
      1,
    );
  });

  test('origin role editor falls with the closing keyboard', () {
    expect(
      originRoleEditorClosingVisualOffsetForTesting(
        startVisualOffset: 420,
        targetVisualOffset: 160,
        closingProgress: 0,
      ),
      420,
    );
    expect(
      originRoleEditorClosingVisualOffsetForTesting(
        startVisualOffset: 420,
        targetVisualOffset: 160,
        closingProgress: 0.5,
      ),
      290,
    );
    expect(
      originRoleEditorClosingVisualOffsetForTesting(
        startVisualOffset: 420,
        targetVisualOffset: 160,
        closingProgress: 1,
      ),
      160,
      reason:
          'The role card must move down by the full keyboard travel without '
          'scrolling the sheet to its bottom.',
    );
  });

  test('origin role editor paint translation reaches exact zero', () {
    expect(
      originRoleEditorClosingPaintTranslationForTesting(
        startTranslation: 48,
        closingProgress: 0,
      ),
      48,
    );
    expect(
      originRoleEditorClosingPaintTranslationForTesting(
        startTranslation: 48,
        closingProgress: 0.5,
      ),
      24,
    );
    expect(
      originRoleEditorClosingPaintTranslationForTesting(
        startTranslation: 48,
        closingProgress: 1,
      ),
      0,
      reason:
          'Translation removal must not depend on a visual scroll target '
          'remaining inside the final ScrollPosition range.',
    );
  });

  test('origin role editor spacer closes with the keyboard', () {
    expect(
      originRoleEditorClosingSpacerExtentForTesting(
        startExtent: 260,
        closingProgress: 0,
      ),
      260,
    );
    expect(
      originRoleEditorClosingSpacerExtentForTesting(
        startExtent: 260,
        closingProgress: 0.5,
      ),
      130,
    );
    expect(
      originRoleEditorClosingSpacerExtentForTesting(
        startExtent: 260,
        closingProgress: 1,
      ),
      0,
      reason:
          'The spacer must remain at close start and reach zero together with '
          'the keyboard.',
    );

    final metricsStart = originWorldSheetInteractionSource.indexOf(
      'void handleKeyboardMetrics(double rawInset)',
    );
    final reopenStart = originWorldSheetInteractionSource.indexOf(
      'void _prepareForReopenedKeyboard()',
      metricsStart,
    );
    expect(metricsStart, greaterThanOrEqualTo(0));
    expect(reopenStart, greaterThan(metricsStart));
    final metricsBody = originWorldSheetInteractionSource.substring(
      metricsStart,
      reopenStart,
    );
    expect(
      metricsBody,
      contains('originRoleEditorClosingSpacerExtentForTesting('),
      reason: 'The live keyboard metrics path must drive spacer removal.',
    );
  });

  test('origin role editor keyboard dismissal preserves bottom distance', () {
    expect(
      originRoleEditorRestingScrollOffsetForTesting(
        minScrollExtent: 0,
        maxScrollExtent: 420,
        distanceToBottom: 0,
      ),
      420,
      reason:
          'Hiding only the keyboard keeps an editor opened at the bottom at '
          'the bottom of the zero-keyboard layout.',
    );
    expect(
      originRoleEditorRestingScrollOffsetForTesting(
        minScrollExtent: 0,
        maxScrollExtent: 420,
        distanceToBottom: 35,
      ),
      385,
      reason:
          'When editing starts away from the bottom, preserve that distance '
          'instead of restoring a stale absolute scroll offset.',
    );
  });

  test('origin role editor finish does not jump after synchronized close', () {
    final finishStart = originWorldSheetInteractionSource.indexOf(
      'void _finishClosing()',
    );
    final keyboardDismissalStart = originWorldSheetInteractionSource.indexOf(
      'void _finishKeyboardDismissal()',
      finishStart,
    );
    expect(finishStart, greaterThanOrEqualTo(0));
    expect(keyboardDismissalStart, greaterThan(finishStart));

    final finishBody = originWorldSheetInteractionSource.substring(
      finishStart,
      keyboardDismissalStart,
    );
    expect(finishBody, isNot(contains('controller.jumpTo(')));
    expect(
      finishBody,
      contains('_terminalClosingPaintTranslation = 0'),
      reason:
          'The final closing frame must explicitly end at zero translation.',
    );
    expect(
      finishBody,
      isNot(contains('(controller.offset - _visualScrollOffset).abs()')),
      reason:
          'Closing must not wait forever for an unreachable visual scroll '
          'coordinate to equal the real ScrollPosition.',
    );
    expect(finishBody, isNot(contains('restoreSheetExtent(')));

    final closingStart = originWorldSheetInteractionSource.indexOf(
      'void _beginClosing(',
    );
    expect(closingStart, greaterThanOrEqualTo(0));
    final closingBody = originWorldSheetInteractionSource.substring(
      closingStart,
      finishStart,
    );
    expect(closingBody, contains('controller.animateTo('));
    expect(
      closingBody,
      contains('controller.jumpTo(reachableVisualOffset);'),
      reason:
          'Before the temporary spacer collapses, commit the reachable visual '
          'coordinate to the real ScrollPosition without changing its paint '
          'position.',
    );
    expect(
      closingBody.indexOf(
        '_alignRealScrollToVisualOffsetBeforeTerminalClose();',
      ),
      lessThan(closingBody.indexOf('_closingStartInset =')),
      reason: 'The real and visual coordinates must align before closing.',
    );
    expect(
      closingBody,
      contains('Only the frame built from the ordinary role card'),
      reason: 'Do not derive the final target from the outgoing editor layout.',
    );
    expect(
      closingBody,
      contains('_terminalClosingFallbackStartVisualOffset'),
      reason:
          'A missing native IME callback must animate from the current visual '
          'offset to the already resolved ordinary-layout target.',
    );
  });

  test('origin opening keyboard spacer only fills missing scroll extent', () {
    expect(
      originOpeningKeyboardLayoutSpacerExtentForTesting(
        additionalScrollExtent: 0,
      ),
      0,
      reason:
          'An existing role section that already makes the target reachable '
          'must not receive another keyboard-height spacer.',
    );
    expect(
      originOpeningKeyboardLayoutSpacerExtentForTesting(
        additionalScrollExtent: 42,
      ),
      42,
      reason: 'Only the exact missing scroll range should be appended.',
    );
    expect(
      originOpeningKeyboardLayoutSpacerExtentForTesting(
        additionalScrollExtent: 42,
      ),
      42,
      reason:
          'Closing keeps the missing range so the current content offset is '
          'not clamped to a different position.',
    );
  });

  test('origin opening keyboard geometry follows system inset progress', () {
    const startTop = 620.0;
    const sheetHeight = 760.0;
    const composerHeight = 100.0;
    const keyboardInset = 300.0;

    expect(
      originOpeningKeyboardProgressForTesting(
        currentInset: 0,
        startInset: 0,
        endInset: keyboardInset,
      ),
      0,
    );
    expect(
      originOpeningKeyboardProgressForTesting(
        currentInset: 150,
        startInset: 0,
        endInset: keyboardInset,
      ),
      0.5,
    );
    expect(
      originOpeningKeyboardProgressForTesting(
        currentInset: 150,
        startInset: keyboardInset,
        endInset: 0,
      ),
      0.5,
    );
    expect(
      originOpeningKeyboardComposerTopForTesting(
        startTop: startTop,
        sheetHeight: sheetHeight,
        composerHeight: composerHeight,
        keyboardInset: keyboardInset,
        progress: 0,
      ),
      startTop,
    );
    final finalTop = originOpeningKeyboardComposerTopForTesting(
      startTop: startTop,
      sheetHeight: sheetHeight,
      composerHeight: composerHeight,
      keyboardInset: keyboardInset,
      progress: 1,
    );
    expect(finalTop + composerHeight, sheetHeight - keyboardInset);
  });

  test('origin opening keyboard uses stable sliver coordinates', () {
    expect(
      originOpeningKeyboardLogicalCoordinateAtStartForTesting(
        logicalCoordinate: 340,
        startVisualOffset: 100,
      ),
      240,
      reason:
          'The logical sliver edge is converted to the coordinate space '
          'captured when focus began.',
    );
    expect(
      originOpeningKeyboardLogicalCoordinateAtStartForTesting(
        logicalCoordinate: 340,
        startVisualOffset: 100,
      ),
      240,
      reason: 'The result does not depend on a current paint offset.',
    );
  });

  test('origin opening keyboard removes only the safe-area overlap', () {
    expect(
      originOpeningEffectiveKeyboardInsetForTesting(
        rawKeyboardInset: 300,
        bottomSafeAreaInset: 24,
      ),
      276,
    );
    expect(
      originOpeningEffectiveKeyboardInsetForTesting(
        rawKeyboardInset: 12,
        bottomSafeAreaInset: 24,
      ),
      0,
    );
    expect(
      originWorldDetailSheetSource,
      contains('return view.viewPadding.bottom / view.devicePixelRatio;'),
      reason:
          'Keyboard geometry must use stable window padding even when the '
          'three-button system-bar boundary clears descendant MediaQuery '
          'padding.',
    );
  });

  test('origin opening keyboard progress stays linear across safe area', () {
    expect(
      originOpeningKeyboardRawProgressForTesting(
        currentRawInset: 0,
        targetLayoutInset: 252,
        bottomSafeAreaInset: 48,
      ),
      0,
    );
    expect(
      originOpeningKeyboardRawProgressForTesting(
        currentRawInset: 150,
        targetLayoutInset: 252,
        bottomSafeAreaInset: 48,
      ),
      0.5,
      reason:
          'Subtracting the safe area from every intermediate inset creates an '
          'initial dead zone and a device-dependent acceleration jump.',
    );
    expect(
      originOpeningKeyboardRawProgressForTesting(
        currentRawInset: 300,
        targetLayoutInset: 252,
        bottomSafeAreaInset: 48,
      ),
      1,
    );
  });

  test('origin opening composer never falls behind the actual keyboard', () {
    expect(
      originOpeningKeyboardVisibleComposerTopForTesting(
        animatedTop: 620,
        sheetHeight: 780,
        composerHeight: 100,
        actualKeyboardInset: 300,
      ),
      380,
      reason:
          'A stale animation frame is clamped so the composer bottom remains '
          'at the actual keyboard top.',
    );
    expect(
      originOpeningKeyboardVisibleComposerTopForTesting(
        animatedTop: 300,
        sheetHeight: 780,
        composerHeight: 100,
        actualKeyboardInset: 300,
      ),
      300,
      reason: 'A composer already above the keyboard must not be pushed down.',
    );
    expect(
      originOpeningKeyboardVisibleComposerTopForTesting(
        animatedTop: 620,
        sheetHeight: 780,
        composerHeight: 100,
        actualKeyboardInset: 0,
      ),
      620,
      reason: 'The keyboard bound is inactive after the keyboard is closed.',
    );
  });

  test('origin opening keyboard distinguishes short and scrolled content', () {
    expect(
      originOpeningKeyboardContentTargetOffsetForTesting(
        layoutOffset: 80,
        preservedOffset: 80,
        contentTop: 60,
        contentBottom: 300,
        composerTop: 500,
        gap: 24,
      ),
      80,
      reason: 'Short content keeps its original visual offset.',
    );
    expect(
      originOpeningKeyboardContentTargetOffsetForTesting(
        layoutOffset: 250,
        preservedOffset: 250,
        contentTop: -110,
        contentBottom: 130,
        composerTop: 500,
        gap: 24,
      ),
      140,
      reason:
          'Short content that was scrolled above the viewport returns its '
          'natural top edge to the sheet top.',
    );
    expect(
      originOpeningKeyboardContentTargetOffsetForTesting(
        layoutOffset: 80,
        preservedOffset: 80,
        contentTop: 60,
        contentBottom: 620,
        composerTop: 500,
        gap: 24,
      ),
      224,
      reason: 'Only the overflowing height is scrolled above the composer.',
    );
    expect(
      originOpeningKeyboardContentTargetOffsetForTesting(
        layoutOffset: 400,
        preservedOffset: 400,
        contentTop: -340,
        contentBottom: 220,
        composerTop: 500,
        gap: 24,
      ),
      144,
      reason:
          'A tall content block remains tall after scrolling; its on-screen '
          'top must not make it take the short-content path.',
    );
    expect(
      originOpeningKeyboardAdditionalScrollExtentForTesting(
        targetOffset: 140,
        maxScrollExtent: 112,
      ),
      28,
      reason:
          'The keyboard list must add the exact missing extent required to '
          'commit the short-content top alignment.',
    );
    expect(
      originOpeningKeyboardAdditionalScrollExtentForTesting(
        targetOffset: 140,
        maxScrollExtent: 180,
      ),
      0,
    );
    expect(
      originOpeningKeyboardSettledTargetInsetForTesting(
        nativeTargetInset: 304,
        actualInset: 300,
        stableFrameCount: 9,
      ),
      304,
      reason: 'The native target remains authoritative while IME is moving.',
    );
    expect(
      originOpeningKeyboardSettledTargetInsetForTesting(
        nativeTargetInset: 304,
        actualInset: 300,
        stableFrameCount: 10,
      ),
      300,
      reason:
          'The settled Flutter inset becomes the exact final keyboard edge.',
    );
  });

  test('origin opening keyboard rests at the inline composer boundary', () {
    expect(
      originOpeningKeyboardFlowRestingOffsetForTesting(
        layoutOffset: 80,
        contentBottom: 620,
        sheetHeight: 600,
        composerHeight: 100,
        gap: 24,
      ),
      224,
      reason:
          'Tall content leaves the inline composer exactly at the viewport '
          'bottom.',
    );
    expect(
      originOpeningKeyboardFlowRestingOffsetForTesting(
        layoutOffset: 80,
        contentBottom: 300,
        sheetHeight: 600,
        composerHeight: 100,
        gap: 24,
      ),
      0,
      reason:
          'Short content stays in natural flow when the boundary would require '
          'overscrolling above the list start.',
    );
  });

  test('origin opening keyboard close animates directly to zero', () {
    expect(
      originOpeningKeyboardClosingAnimationProgressForTesting(
        startProgress: 1,
        animationValue: 0,
      ),
      1,
    );
    expect(
      originOpeningKeyboardClosingAnimationProgressForTesting(
        startProgress: 1,
        animationValue: 0.5,
      ),
      0.5,
    );
    expect(
      originOpeningKeyboardClosingAnimationProgressForTesting(
        startProgress: 1,
        animationValue: 1,
      ),
      0,
      reason:
          'The sheet closing animation owns its progress and always ends at '
          'the zero-keyboard target.',
    );
  });

  test('origin opening keyboard close ignores late native reversals', () {
    expect(
      originOpeningKeyboardShouldIgnoreNativeTargetForTesting(
        closingOrRestoring: true,
        direction: GenesisKeyboardAnimationDirection.changing,
      ),
      isTrue,
    );
    expect(
      originOpeningKeyboardShouldIgnoreNativeTargetForTesting(
        closingOrRestoring: true,
        direction: GenesisKeyboardAnimationDirection.opening,
      ),
      isTrue,
    );
    expect(
      originOpeningKeyboardShouldIgnoreNativeTargetForTesting(
        closingOrRestoring: true,
        direction: GenesisKeyboardAnimationDirection.closing,
      ),
      isFalse,
      reason: 'Repeated native closing notifications remain harmless.',
    );
  });

  test('origin opening keyboard close freezes the current content offset', () {
    final closeStart = originWorldSheetInteractionSource.indexOf(
      'void _beginKeyboardClosing()',
    );
    final insetUpdateStart = originWorldSheetInteractionSource.indexOf(
      'void _updateKeyboardInset(double layoutInset)',
      closeStart,
    );
    final settleStart = originWorldSheetInteractionSource.indexOf(
      'void _scheduleKeyboardSettleCheck()',
      insetUpdateStart,
    );
    final finishStart = originWorldSheetInteractionSource.indexOf(
      'void _finishKeyboardTransitionIfNeeded()',
      settleStart,
    );
    final captureStart = originWorldSheetInteractionSource.indexOf(
      'void _captureKeyboardContentBounds(',
      finishStart,
    );

    expect(closeStart, greaterThanOrEqualTo(0));
    expect(insetUpdateStart, greaterThan(closeStart));
    expect(settleStart, greaterThan(insetUpdateStart));
    expect(finishStart, greaterThan(settleStart));
    expect(captureStart, greaterThan(finishStart));

    final closeBody = originWorldSheetInteractionSource.substring(
      closeStart,
      insetUpdateStart,
    );
    final insetUpdateBody = originWorldSheetInteractionSource.substring(
      insetUpdateStart,
      settleStart,
    );
    final finishBody = originWorldSheetInteractionSource.substring(
      finishStart,
      captureStart,
    );
    expect(
      closeBody,
      contains('_keyboardClosingVisualOffset = keyboardVisualScrollOffset();'),
      reason:
          'Focus loss snapshots the current content position instead of '
          'selecting a new zero-keyboard destination.',
    );
    expect(
      closeBody,
      isNot(contains('position.maxScrollExtent')),
      reason: 'Closing must not derive a new position from the list bottom.',
    );
    expect(
      insetUpdateBody + finishBody,
      isNot(contains('_keyboardClosingVisualOffset =')),
      reason: 'Keyboard frames must not change the frozen visual position.',
    );
    expect(
      originWorldDetailSheetSource,
      isNot(contains('_scheduleOpeningMessagePageBottomRestore')),
      reason:
          'Leaving keyboard mode must not schedule a second post-frame jump '
          'after the frozen closing target has already been committed.',
    );
  });

  test('origin keyboard animation target rejects malformed native events', () {
    expect(GenesisKeyboardAnimationTarget.tryParse(null), isNull);
    expect(
      GenesisKeyboardAnimationTarget.tryParse(const {
        'generation': 2,
        'phase': 'opening',
        'startInset': 0,
        'endInset': 301.5,
        'durationMillis': 250,
      }),
      isA<GenesisKeyboardAnimationTarget>()
          .having((event) => event.generation, 'generation', 2)
          .having(
            (event) => event.direction,
            'direction',
            GenesisKeyboardAnimationDirection.opening,
          )
          .having((event) => event.endInset, 'endInset', 301.5)
          .having(
            (event) => event.duration,
            'duration',
            const Duration(milliseconds: 250),
          ),
    );
  });

  test('origin keyboard consumers share one native event stream', () {
    expect(
      identical(
        GenesisKeyboardAnimationEvents.targets,
        GenesisKeyboardAnimationEvents.targets,
      ),
      isTrue,
      reason:
          'The message composer and role editor must not register competing '
          'EventChannel listeners.',
    );
  });

  test('origin collapsed sheet caps content height before safe area', () {
    expect(
      originWorldCollapsedSheetHeightFor(
        viewportHeight: 667,
        bottomSafeArea: 0,
      ),
      closeTo(233.45, 0.001),
    );
    expect(
      originWorldCollapsedSheetHeightFor(
        viewportHeight: 780,
        bottomSafeArea: 15,
      ),
      285,
    );
    expect(
      originWorldCollapsedSheetHeightFor(
        viewportHeight: 932,
        bottomSafeArea: 34,
      ),
      304,
    );
  });

  test('origin detail sheet header sizing matches design', () {
    expect(
      originDetailSheetHeaderHeightForTesting,
      GenesisRadii.sheetTopRadiusValue + 6,
    );
    expect(originDetailSheetHeaderBodyGapForTesting, 0);
    expect(originDetailSheetPageIndicatorTopOffsetForTesting, 4);
    expect(GenesisRadii.sheetTopRadiusValue, 18);
  });

  test('origin detail sections use main ui spacing', () {
    expect(originDetailSectionGapForTesting, 24);
    expect(originOpeningDialogueRoleGapForTesting, 36);
    expect(originOpeningKeyboardDialogueGapReductionForTesting, 10);
    expect(originDetailSectionTitleIconGapForTesting, 8);
  });

  test('origin launched world rows use compact character avatars', () {
    expect(originLaunchedWorldAvatarSizeForTesting, 44);
    expect(originLaunchedWorldSectionTopPaddingForTesting, 6);
    expect(originLaunchedWorldTitleListGapForTesting, 16);
    expect(originLaunchedWorldRowGapForTesting, 16);
    expect(originLaunchedWorldPreviewLimitForTesting, 5);
    expect(originSectionsSource, isNot(contains("'Your Launched Worlds'")));
    expect(originSectionsSource, isNot(contains("'Launched Before'")));
    expect(originSectionsSource, contains("'Playing World'"));
    expect(originSectionsSource, isNot(contains("'Launch another World'")));
    expect(originSectionsSource, isNot(contains('color: GenesisColors.brand')));
    expect(originSectionsSource, isNot(contains("'Enter'")));
    expect(originSectionsSource, contains('SizedBox(height: 6)'));
    expect(originSectionsSource, contains('formatMessageCountLabel'));
    expect(originSectionsSource, contains('formatGenesisTimestamp'));
    expect(originSectionsSource, isNot(contains('bLastActiveAt.compareTo')));
    expect(
      originSectionsSource,
      contains('.take(originLaunchedWorldPreviewLimitForTesting)'),
    );
    expect(originSectionsSource, isNot(contains('Divider(')));
    expect(
      originSectionsSource,
      isNot(contains('Icons.chevron_right_rounded')),
    );
    expect(
      originSectionsSource,
      contains('crossAxisAlignment: CrossAxisAlignment.start'),
    );
  });

  test('origin info section titles do not render leading icons', () {
    final titleWidget = originSectionsSource.substring(
      originSectionsSource.indexOf('class _SectionTitle'),
    );
    expect(titleWidget, isNot(contains('SvgPicture.asset')));
    expect(titleWidget, isNot(contains('Image.asset')));
    expect(titleWidget, isNot(contains('Icon(icon')));
    expect(originSectionsSource, contains("title: 'Worldo Brief'"));
    expect(originSectionsSource, contains("title: 'Launch Preview'"));
    expect(originSectionsSource, isNot(contains('Launched World Progress')));
    expect(originSectionsSource, contains("title: 'Characters ("));
  });

  test('origin opening brief and role titles do not render leading icons', () {
    expect(
      originSectionsSource,
      isNot(contains('origin-opening-worldo-brief-icon')),
    );
    expect(
      originSectionsSource,
      isNot(contains('origin-setup-role-title-launch-icon')),
    );
    expect(originSectionsSource, contains("'Worldo Brief'"));
    expect(originSectionsSource, contains("'Select Your Role'"));
  });

  test('origin detail discuss uses a title-row View all action', () {
    expect(
      originSectionsSource,
      contains('authorColor: originWorldDetailSheetSecondaryTextColor'),
    );
    expect(
      originSectionsSource,
      isNot(contains('authorColor: GenesisColors.redSecondary')),
    );
    expect(originSectionsSource, contains("'View all >'"));
    expect(originSectionsSource, contains('fontSize: 10'));
    expect(
      originSectionsSource,
      contains('originWorldDetailSheetTertiaryTextColor'),
    );
    expect(originSectionsSource, contains('enableViewMore: false'));
    expect(
      originSectionsSource,
      isNot(contains('onViewMoreTap: () => _openDiscussPage(context)')),
    );
  });

  test('origin detail does not load or render launched world progress', () {
    expect(originWorldPageSource, isNot(contains('getLatestWorldSummaries')));
    expect(
      originWorldDetailSheetSource,
      isNot(contains('CopyWorldProgressSection')),
    );
  });

  test('origin location opening preview keeps every initial dialogue line', () {
    final messages = originLocationOpeningPreviewMessagesForTesting(
      [
        {
          'tick_no': 1,
          'tick_result': {
            'current_time': 'Day 1, 08:30',
            'location_groups': [
              {
                'location_id': 'loc_1',
                'initial_dialogue': [
                  {
                    'char_id': 'nar',
                    'char_name': 'narrator',
                    'content': 'The diner lights hum as Sam unlocks the door.',
                  },
                  {
                    'char_id': 'char_1',
                    'char_name': 'Sam',
                    'content': 'Coffee is on. Keep the sign lit.',
                  },
                  {'char_id': 'char_2', 'char_name': 'Riley', 'content': ''},
                ],
              },
              {
                'location_id': 'loc_2',
                'initial_dialogue': [
                  {
                    'char_id': 'char_3',
                    'char_name': 'Wrong Location',
                    'content': 'This should not be shown.',
                  },
                ],
              },
            ],
          },
        },
      ],
      const ['loc_1'],
    );

    expect(messages.first.senderType, 'tick');
    expect(messages.first.content, 'Day 1, 08:30');
    expect(messages.skip(1).map((message) => message.content), [
      'The diner lights hum as Sam unlocks the door.',
      'Coffee is on. Keep the sign lit.',
    ]);
    expect(messages[1].senderType, 'narrator');
    expect(messages.last.senderType, 'character');
    expect(messages.skip(1).map((message) => message.currentTime), [
      'Day 1, 08:30',
      'Day 1, 08:30',
    ]);
  });

  test('origin location opening preview prefers tick one location group', () {
    final messages = originLocationOpeningPreviewMessagesForTesting(
      [
        {
          'tick_no': 2,
          'tick_result': {
            'current_time': 'Later time.',
            'location_groups': [
              {
                'location_id': 'loc_1',
                'initial_dialogue': [
                  {
                    'char_id': 'char_1',
                    'char_name': 'Sam',
                    'content': 'Later line.',
                  },
                ],
              },
            ],
          },
        },
        {
          'tick_no': 1,
          'tick_result': {
            'current_time': 'Opening time.',
            'location_groups': [
              {
                'location_id': 'loc_1',
                'initial_dialogue': [
                  {
                    'char_id': 'char_1',
                    'char_name': 'Sam',
                    'content': 'Opening line.',
                  },
                ],
              },
            ],
          },
        },
      ],
      const ['loc_1'],
    );

    expect(messages.first.content, 'Opening time.');
    expect(messages.last.content, 'Opening line.');
    expect(messages.last.currentTime, 'Opening time.');
  });

  test(
    'origin opening preview prefers top-level init group and keeps nar_pic',
    () {
      final origin = _originDetail(
        characters: const <OriginCharacter>[],
        locations: [
          OriginLocation.fromJson(const {
            'id': 12,
            'origin_id': 1,
            'location_id': 'loc_1',
            'location_name': 'Town Square',
          }),
        ],
        initLocationGroup: const OriginInitLocationGroup(
          locationId: 'loc_1',
          initialDialogue: [
            OriginDialogueLine(
              charId: 'nar',
              charName: 'Narrator',
              content: 'The square wakes.',
            ),
            OriginDialogueLine(
              charId: 'char_1',
              charName: 'Sam',
              content: 'We should go.',
            ),
            OriginDialogueLine(
              charId: 'nar_pic',
              charName: 'Narrator',
              content: 'https://cdn.example.com/opening.webp',
            ),
          ],
        ),
        ticks: const [
          {
            'tick_no': 1,
            'tick_result': {
              'location_groups': [
                {
                  'location_id': 'loc_1',
                  'initial_dialogue': [
                    {
                      'char_id': 'char_legacy',
                      'char_name': 'Legacy',
                      'content': 'Legacy tick line.',
                    },
                  ],
                },
              ],
            },
          },
        ],
      );

      final messages = originOpeningPreviewMessagesForTesting(origin, const [
        'loc_1',
      ]);

      expect(messages.map((message) => message.content), [
        'The square wakes.',
        'We should go.',
        'https://cdn.example.com/opening.webp',
      ]);
      expect(messages.map((message) => message.senderType), [
        'narrator',
        'character',
        'image',
      ]);
      expect(
        messages.map((message) => message.content),
        isNot(contains('Legacy tick line.')),
      );
    },
  );

  test('origin location opening preview resolves character avatars', () {
    final messages = originLocationOpeningPreviewMessagesForTesting(
      [
        {
          'tick_no': 1,
          'tick_result': {
            'location_groups': [
              {
                'location_id': 'loc_1',
                'initial_dialogue': [
                  {
                    'char_id': 'char_1',
                    'char_name': 'Sam',
                    'content': 'Opening line.',
                  },
                ],
              },
            ],
          },
        },
      ],
      const ['loc_1'],
    );

    final entities = originLocationOpeningPreviewEntitiesForTesting(
      [
        OriginCharacter(
          id: 7,
          characterId: 'char_1',
          originId: 1,
          name: 'Sam',
          avatar: 'https://example.com/sam.png',
          tags: '',
          currentLocationId: 0,
          initialLocationId: 0,
          createdAt: null,
          updatedAt: null,
        ),
      ],
      messages,
      'loc_1',
    );

    expect(entities.single.id, 'char_1');
    expect(entities.single.avatarUrl, 'https://example.com/sam.png');
    expect(entities.single.isAi, isTrue);
  });

  testWidgets(
    'origin opening preview passes character avatar to location chat',
    (tester) async {
      const avatarAsset = 'assets/images/default_list_image.png';
      final messages = originLocationOpeningPreviewMessagesForTesting(
        [
          {
            'tick_no': 1,
            'tick_result': {
              'location_groups': [
                {
                  'location_id': 'loc_1',
                  'initial_dialogue': [
                    {
                      'char_id': 'nar',
                      'char_name': 'Narrator',
                      'content': 'The location wakes.',
                    },
                    {
                      'char_id': 'nar_pic',
                      'char_name': 'Narrator',
                      'content': avatarAsset,
                    },
                    {
                      'char_id': 'char_1',
                      'char_name': 'Sam',
                      'content': 'Opening line.',
                    },
                  ],
                },
              ],
            },
          },
        ],
        const ['loc_1'],
      );
      final entities = originLocationOpeningPreviewEntitiesForTesting(
        [
          OriginCharacter(
            id: 7,
            characterId: 'char_1',
            originId: 1,
            name: 'Sam',
            avatar: avatarAsset,
            tags: '',
            currentLocationId: 0,
            initialLocationId: 0,
            createdAt: null,
            updatedAt: null,
          ),
        ],
        messages,
        'loc_1',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocationChatPanel(
            worldId: 'origin-preview',
            locationId: 'loc_1',
            active: false,
            openingPreviewMessages: messages,
            openingPreviewEntities: entities,
          ),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<ChatAvatar>(find.byType(ChatAvatar));
      expect(avatar.imageUrl, avatarAsset);
      expect(find.byType(ChatAvatar), findsOneWidget);
      expect(find.byType(ChatImageMessage), findsOneWidget);
    },
  );

  testWidgets('origin location chat renders its supplied empty state', (
    tester,
  ) async {
    const title = 'This location comes to life after launch.';
    const body = 'Launch this Worldo to explore and interact here.';

    await tester.pumpWidget(
      const MaterialApp(
        home: LocationChatPanel(
          worldId: 'origin-preview',
          locationId: 'loc_empty',
          locationName: 'Empty Location',
          active: false,
          showComposer: false,
          emptyState: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Text(title), Text(body)],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(title), findsOneWidget);
    expect(find.text(body), findsOneWidget);
  });

  testWidgets(
    'origin opening preview reveals AI notice above its first message',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messages = originLocationOpeningPreviewMessagesForTesting(
        [
          {
            'tick_no': 1,
            'tick_result': {
              'current_time': 'Day 1, 08:30',
              'location_groups': [
                {
                  'location_id': 'loc_1',
                  'initial_dialogue': [
                    {
                      'char_id': 'nar',
                      'char_name': 'Narrator',
                      'content': 'The location wakes.',
                    },
                    {
                      'char_id': 'char_1',
                      'char_name': 'Sam',
                      'content': 'Opening line.',
                    },
                  ],
                },
              ],
            },
          },
        ],
        const ['loc_1'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocationChatPanel(
            worldId: 'origin-preview',
            locationId: 'loc_1',
            active: false,
            openingPreviewMessages: messages,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byKey(const ValueKey<String>('location-chat-message-list')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(find.text(kAiContentDisclaimerText), findsOneWidget);
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
      expect(
        tester.getCenter(find.text(kAiContentDisclaimerText)).dy,
        lessThanOrEqualTo(tester.getBottomLeft(find.byType(ChatHeader)).dy),
      );

      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(position.pixels, 0);
      expect(
        tester.getCenter(find.text(kAiContentDisclaimerText)).dy,
        greaterThan(tester.getBottomLeft(find.byType(ChatHeader)).dy),
      );
    },
  );

  test('origin location parses dialogue lines', () {
    final location = OriginLocation.fromJson(const {
      'id': 12,
      'origin_id': 1,
      'location_id': 'loc_1',
      'location_name': 'Town Square',
      'dialogue': [
        {
          'char_id': 'char_1',
          'char_name': 'Casey',
          'content': 'Doors open at eight.',
        },
      ],
    });

    expect(location.dialogue, hasLength(1));
    expect(location.dialogue.single.charId, 'char_1');
    expect(location.dialogue.single.charName, 'Casey');
    expect(location.dialogue.single.content, 'Doors open at eight.');
  });

  test('origin map bubbles use location dialogue and character avatar ids', () {
    final origin = _originDetail(
      characters: [
        OriginCharacter(
          id: 7,
          characterId: 'char_1',
          originId: 1,
          name: 'Casey',
          avatar: '',
          tags: '',
          currentLocationId: 12,
          initialLocationId: 12,
          createdAt: null,
          updatedAt: null,
        ),
      ],
      locations: [
        OriginLocation.fromJson(const {
          'id': 12,
          'origin_id': 1,
          'location_id': 'loc_1',
          'location_name': 'Town Square',
          'dialogue': [
            {
              'char_id': 'char_1',
              'content': '*Casey flips the sign.* 「Open before sunrise.」',
            },
            {'char_id': 'nar', 'content': 'Narration should not show.'},
            {'char_id': 'missing', 'content': 'Missing character.'},
            {'char_id': 'char_1', 'content': ''},
          ],
        }),
      ],
    );

    final bubbles = originMapMessageBubblesForTesting(origin);

    expect(bubbles, hasLength(1));
    expect(bubbles.single.characterId, '7');
    expect(bubbles.single.content, 'Open before sunrise.');
  });

  test('origin map bubbles use init location dialogue first', () {
    final origin = _originDetail(
      characters: [
        OriginCharacter(
          id: 7,
          characterId: 'char_1',
          originId: 1,
          name: 'Casey',
          avatar: '',
          tags: '',
          currentLocationId: 12,
          initialLocationId: 12,
          createdAt: null,
          updatedAt: null,
        ),
      ],
      locations: [
        OriginLocation.fromJson(const {
          'id': 12,
          'origin_id': 1,
          'location_id': 'loc_1',
          'location_name': 'Town Square',
          'dialogue': <Object?>[
            <String, Object?>{
              'char_id': 'char_1',
              'content': 'Legacy location line.',
            },
          ],
        }),
      ],
      initLocationGroup: const OriginInitLocationGroup(
        locationId: 'loc_1',
        initialDialogue: [
          OriginDialogueLine(
            charId: 'char_1',
            charName: 'Casey',
            content: '*Casey checks the street.* 「The coast is clear.」',
          ),
          OriginDialogueLine(
            charId: 'nar',
            charName: 'Narrator',
            content: 'Narration should not show.',
          ),
        ],
      ),
    );

    final bubbles = originMapMessageBubblesForTesting(origin);

    expect(bubbles, hasLength(2));
    expect(bubbles.first.characterId, '7');
    expect(bubbles.map((bubble) => bubble.content), [
      'The coast is clear.',
      'Legacy location line.',
    ]);
  });

  test('origin map bubbles do not read tick opening dialogue', () {
    final origin = _originDetail(
      characters: [
        OriginCharacter(
          id: 7,
          characterId: 'char_1',
          originId: 1,
          name: 'Casey',
          avatar: '',
          tags: '',
          currentLocationId: 12,
          initialLocationId: 12,
          createdAt: null,
          updatedAt: null,
        ),
      ],
      locations: [
        OriginLocation.fromJson(const {
          'id': 12,
          'origin_id': 1,
          'location_id': 'loc_1',
          'location_name': 'Town Square',
        }),
      ],
      ticks: const [
        {
          'tick_no': 1,
          'tick_result': {
            'location_groups': [
              {
                'location_id': 'loc_1',
                'initial_dialogue': [
                  {
                    'char_id': 'char_1',
                    'char_name': 'Casey',
                    'content': 'The fallback line is visible.',
                  },
                ],
              },
            ],
          },
        },
      ],
    );

    final bubbles = originMapMessageBubblesForTesting(origin);

    expect(bubbles, isEmpty);
  });

  test('origin character resolves string current location ids', () {
    final character = OriginCharacter.fromJson(const {
      'id': 7,
      'character_id': 'char_1',
      'name': 'Casey',
      'current_location_id': 'loc_1',
    });
    final location = OriginLocation.fromJson(const {
      'location_id': 'loc_1',
      'location_name': 'Town Square',
    });

    expect(character.currentLocationBusinessId, 'loc_1');
    expect(character.currentLocationId, location.id);
  });

  test('origin map avatars have no AI star marker or white frame trigger', () {
    final avatar = originMapAvatarForTesting(
      OriginCharacter(
        id: 7,
        characterId: 'char_1',
        originId: 1,
        name: 'Casey',
        avatar: '',
        tags: '',
        currentLocationId: 12,
        initialLocationId: 12,
        createdAt: null,
        updatedAt: null,
      ),
    );

    expect(avatar.showStar, isFalse);
    expect(avatar.isPlayerControlledRole, isFalse);
  });

  test(
    'origin map bubbles ignore dialogue when character is at another location',
    () {
      final origin = _originDetail(
        characters: [
          OriginCharacter(
            id: 7,
            characterId: 'char_1',
            originId: 1,
            name: 'Casey',
            avatar: '',
            tags: '',
            currentLocationId: 13,
            initialLocationId: 13,
            createdAt: null,
            updatedAt: null,
          ),
        ],
        locations: [
          OriginLocation.fromJson(const {
            'id': 12,
            'origin_id': 1,
            'location_id': 'loc_1',
            'location_name': 'Town Square',
            'dialogue': [
              {'char_id': 'char_1', 'content': 'I am somewhere else.'},
            ],
          }),
          OriginLocation.fromJson(const {
            'id': 13,
            'origin_id': 1,
            'location_id': 'loc_2',
            'location_name': 'Harbor',
          }),
        ],
      );

      expect(originMapMessageBubblesForTesting(origin), isEmpty);
    },
  );

  test('origin character tagline reads brief directly', () {
    final character = OriginCharacter.fromJson(const {
      'character_id': 'char_1',
      'name': 'Sam',
      'identity': 'Archivist',
      'tagline': 'Old tagline should be ignored',
      'brief': 'Brief from API',
      'description': 'Description should be ignored',
      'goal': 'Protect the archive',
    });

    expect(character.tagline, 'Brief from API');
  });

  test(
    'origin character section omits description and uses unified body rhythm',
    () {
      final source = originSectionsSource;
      final characterRow = source.substring(
        source.indexOf('class _OriginCharacterRow'),
        source.indexOf('class _OriginCharacterPortrait'),
      );
      final bodyStyle = source.substring(
        source.indexOf('const _bodyTextStyle'),
        source.indexOf('const _mutedBodyTextStyle'),
      );

      expect(characterRow, isNot(contains('visibleDescription')));
      expect(characterRow, isNot(contains('character.description')));
      expect(characterRow, isNot(contains('_sameCharacterText')));
      expect(characterRow, isNot(contains('SizedBox(height: 9)')));
      expect(characterRow, contains("Text('Goal: \$goal'"));
      expect(bodyStyle, contains('height: 1.4'));
      expect(bodyStyle, isNot(contains('height: 1.45')));
      expect(bodyStyle, isNot(contains('height: 1.35')));
      expect(source, isNot(contains('bool _sameCharacterText')));
    },
  );

  test('origin info images use the requested DPR policies', () {
    final worldoBriefImage = originSectionsSource.substring(
      originSectionsSource.indexOf('class _OriginPreviewImage'),
      originSectionsSource.indexOf('class _LaunchPreviewSection'),
    );
    final characterPortrait = originSectionsSource.substring(
      originSectionsSource.indexOf('class _OriginCharacterPortrait'),
      originSectionsSource.indexOf('const _bodyTextStyle'),
    );

    expect(
      worldoBriefImage,
      contains('static const double _maxDevicePixelRatio = 2;'),
    );
    expect(
      worldoBriefImage,
      contains('maxDevicePixelRatio: _maxDevicePixelRatio'),
    );
    expect(
      characterPortrait,
      contains('maxDevicePixelRatio: devicePixelRatio'),
    );
    expect(
      characterPortrait,
      isNot(contains('_originRoleCardAvatarUrl(context, url)')),
    );
  });
}

OriginDetail _originDetail({
  required List<OriginCharacter> characters,
  required List<OriginLocation> locations,
  OriginInitLocationGroup? initLocationGroup,
  List<Map<String, dynamic>> ticks = const <Map<String, dynamic>>[],
}) {
  return OriginDetail(
    id: 1,
    oid: 'o_test',
    name: 'Origin',
    description: '',
    mapImage: '',
    worldMap: '',
    worldView: '',
    copyCount: 0,
    interactCount: 0,
    tags: const <String>[],
    createdAt: null,
    updatedAt: null,
    characters: characters,
    locations: locations,
    initLocationGroup: initLocationGroup,
    ticks: ticks,
  );
}
