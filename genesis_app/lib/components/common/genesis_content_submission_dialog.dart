import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';

import 'genesis_action_box.dart';
import 'genesis_center_toast.dart';
import 'genesis_modal_routes.dart';

typedef GenesisContentSubmitter = Future<void> Function(String content);

Future<bool> showGenesisContentSubmissionDialog({
  required BuildContext context,
  required String title,
  required Key contentInputKey,
  required GenesisContentSubmitter onSubmit,
  required String successMessage,
  required String failureMessage,
}) async {
  final submitted = await showGenesisDialog<bool>(
    context: context,
    barrierColor: const Color(0x52000000),
    builder: (dialogContext) {
      return _GenesisContentSubmissionDialog(
        title: title,
        contentInputKey: contentInputKey,
        onSubmit: onSubmit,
        successMessage: successMessage,
        failureMessage: failureMessage,
      );
    },
  );
  return submitted == true;
}

class _GenesisContentSubmissionDialog extends StatefulWidget {
  const _GenesisContentSubmissionDialog({
    required this.title,
    required this.contentInputKey,
    required this.onSubmit,
    required this.successMessage,
    required this.failureMessage,
  });

  final String title;
  final Key contentInputKey;
  final GenesisContentSubmitter onSubmit;
  final String successMessage;
  final String failureMessage;

  @override
  State<_GenesisContentSubmissionDialog> createState() =>
      _GenesisContentSubmissionDialogState();
}

class _GenesisContentSubmissionDialogState
    extends State<_GenesisContentSubmissionDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _submitting = false;

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(content);
      if (!mounted) return;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      Navigator.of(context).pop(true);
      if (overlay != null) {
        showGenesisToastInOverlay(overlay, widget.successMessage);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showGenesisToast(context, widget.failureMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GenesisActionBox<bool>(
      title: widget.title,
      titleHeight: 157,
      titleContentSpacing: 16,
      titleContent: TextField(
        key: widget.contentInputKey,
        controller: _controller,
        focusNode: _focusNode,
        cursorColor: GenesisColors.darkTextPrimary,
        style: const TextStyle(color: GenesisColors.darkTextPrimary),
        autofocus: true,
        minLines: 3,
        maxLines: 3,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: 'Describe the issue',
          hintStyle: const TextStyle(color: GenesisColors.darkInputPlaceholder),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: GenesisColors.darkFaintFill),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: GenesisColors.darkFaintFill),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: const [
        GenesisActionBoxAction<bool>(label: 'Submit', value: true),
      ],
      onActionSelected: (_) => unawaited(_submit()),
      onCancel: () => Navigator.of(context).pop(false),
    );
  }
}
