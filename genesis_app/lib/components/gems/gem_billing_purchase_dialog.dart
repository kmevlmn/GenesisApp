import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../common/genesis_action_box.dart';
import 'gem_assets.dart';
import 'gem_colors.dart';

enum GemBillingPurchaseDialogPhase { processing, success }

class GemBillingPurchaseDialogState {
  const GemBillingPurchaseDialogState({
    required this.phase,
    required this.attemptId,
    this.grantedText = '',
  });

  factory GemBillingPurchaseDialogState.processing({
    required String attemptId,
  }) {
    return GemBillingPurchaseDialogState(
      phase: GemBillingPurchaseDialogPhase.processing,
      attemptId: attemptId,
    );
  }

  factory GemBillingPurchaseDialogState.success({
    required String attemptId,
    required String grantedText,
  }) {
    return GemBillingPurchaseDialogState(
      phase: GemBillingPurchaseDialogPhase.success,
      attemptId: attemptId,
      grantedText: grantedText,
    );
  }

  final GemBillingPurchaseDialogPhase phase;
  final String attemptId;
  final String grantedText;
}

class GemBillingPurchaseDialog extends StatelessWidget {
  const GemBillingPurchaseDialog({
    super.key,
    required this.state,
    required this.onConfirm,
    this.processingLabel = 'Purchasing Gems',
    this.successTitle = 'Purchase successful!',
    this.successMessage,
    this.successIconAsset = gemStackIconAsset,
  });

  final ValueListenable<GemBillingPurchaseDialogState> state;
  final VoidCallback onConfirm;
  final String processingLabel;
  final String successTitle;
  final String? successMessage;
  final String successIconAsset;
  static const double _processingHeight = 202;
  static const double _successContentHeight = 150;
  static const double _titleHorizontalPadding = 24;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GemBillingPurchaseDialogState>(
      valueListenable: state,
      builder: (context, value, _) {
        final isSuccess = value.phase == GemBillingPurchaseDialogPhase.success;
        return PopScope(
          // The purchase result must be acknowledged explicitly with OK.
          canPop: false,
          child: GenesisActionBox<bool>(
            title: '',
            titleHeight: isSuccess ? _successContentHeight : _processingHeight,
            titleHorizontalPadding: _titleHorizontalPadding,
            titleWidget: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSuccess) ...[
                  SvgPicture.asset(
                    successIconAsset,
                    width: gemStackIconWidth,
                    height: gemStackIconHeight,
                  ),
                  const SizedBox(height: 18),
                ] else ...[
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: kGemAccentColor,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (isSuccess)
                  _GemBillingPurchaseGrantedMessage(
                    grantedText: value.grantedText,
                    title: successTitle,
                    message: successMessage,
                  )
                else
                  _ProcessingPaymentText(label: processingLabel),
              ],
            ),
            actions: isSuccess
                ? const [GenesisActionBoxAction<bool>(label: 'OK', value: true)]
                : const [],
            showCancel: false,
            onActionSelected: (_) => onConfirm(),
            onCancel: onConfirm,
          ),
        );
      },
    );
  }
}

class _GemBillingPurchaseGrantedMessage extends StatelessWidget {
  const _GemBillingPurchaseGrantedMessage({
    required this.grantedText,
    required this.title,
    this.message,
  });

  final String grantedText;
  final String title;
  final String? message;

  static const _grantedTextStyle = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: Color(0xFF111111),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          key: const ValueKey<String>('billing-purchase-success-title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            height: 20 / 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(
          key: ValueKey<String>('billing-purchase-success-line-gap'),
          height: 12,
        ),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            key: const ValueKey<String>('billing-purchase-granted-fit'),
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text.rich(
              key: const ValueKey<String>('billing-purchase-granted-line'),
              TextSpan(
                children: message != null
                    ? [TextSpan(text: message)]
                    : [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: SvgPicture.asset(
                              gemIconAsset,
                              key: const ValueKey<String>(
                                'billing-purchase-granted-icon',
                              ),
                              width: 12,
                              height: 12,
                            ),
                          ),
                        ),
                        TextSpan(
                          text: grantedText,
                          style: const TextStyle(color: kGemAccentColor),
                        ),
                        const TextSpan(text: ' Gems have been granted.'),
                      ],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: _grantedTextStyle,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProcessingPaymentText extends StatefulWidget {
  const _ProcessingPaymentText({required this.label});
  final String label;

  @override
  State<_ProcessingPaymentText> createState() => _ProcessingPaymentTextState();
}

class _ProcessingPaymentTextState extends State<_ProcessingPaymentText> {
  late final Timer _timer;
  int _dotCount = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() => _dotCount = _dotCount == 3 ? 1 : _dotCount + 1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 15,
      height: 20 / 15,
      letterSpacing: 0,
      fontWeight: FontWeight.w400,
      color: Color(0xFF111111),
    );
    return SizedBox(
      width: double.infinity,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.label, textAlign: TextAlign.center, style: style),
              SizedBox(
                width: 18,
                child: Text(
                  '.' * _dotCount,
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  softWrap: false,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
