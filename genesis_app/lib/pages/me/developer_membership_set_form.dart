import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../network/models/membership_manual_set.dart';

class DeveloperMembershipSetForm extends StatefulWidget {
  const DeveloperMembershipSetForm({
    super.key,
    required this.loadUid,
    required this.onSubmit,
    required this.onSaved,
  });

  final Future<String?> Function() loadUid;
  final Future<MembershipManualSetResult> Function(MembershipManualSetRequest)
  onSubmit;
  final Future<void> Function(MembershipManualSetResult) onSaved;

  @override
  State<DeveloperMembershipSetForm> createState() =>
      _DeveloperMembershipSetFormState();
}

class _DeveloperMembershipSetFormState
    extends State<DeveloperMembershipSetForm> {
  final _formKey = GlobalKey<FormState>();
  final _uid = TextEditingController();
  final _expiresAt = TextEditingController();
  final _reason = TextEditingController();
  String _planCode = 'pro_monthly';
  bool _uidEdited = false;
  bool _submitting = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) unawaited(_prefillUid());
  }

  Future<void> _prefillUid() async {
    try {
      final uid = await widget.loadUid();
      if (mounted && !_uidEdited && !_submitting && _uid.text.isEmpty) {
        _uid.text = uid?.trim() ?? '';
      }
    } catch (_) {
      // A target UID can still be entered without a local login session.
    }
  }

  @override
  void dispose() {
    _uid.dispose();
    _expiresAt.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!kDebugMode || _submitting || !_formKey.currentState!.validate()) {
      return;
    }
    final request = MembershipManualSetRequest(
      uid: _uid.text.trim(),
      planCode: _planCode,
      expiresAt: int.parse(_expiresAt.text.trim()),
      reason: _reason.text.trim(),
    );
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _result = null;
    });
    try {
      final result = await widget.onSubmit(request);
      var message =
          'VIP updated\nuid: ${result.uid}\nplan_code: ${result.planCode}\n'
          'expires_at: ${result.expiresAt}\n'
          'membership_status: ${result.membershipStatus}';
      try {
        await widget.onSaved(result);
      } catch (error) {
        // A failed refresh must not turn a successful mutation into a retry.
        message += '\nWallet refresh failed: $error';
      }
      if (mounted) setState(() => _result = message);
    } catch (error) {
      if (mounted) setState(() => _result = 'VIP request failed: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration(String label, {String? helperText}) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelStyle: const TextStyle(
        fontSize: 12,
        color: Color(0xFF555555),
        fontWeight: FontWeight.w600,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Set manual membership'),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('developer-membership-set-uid'),
            controller: _uid,
            enabled: !_submitting,
            autocorrect: false,
            decoration: _decoration('uid'),
            onChanged: (_) => _uidEdited = true,
            validator: (value) {
              final uid = value?.trim() ?? '';
              return uid.isEmpty || uid.length > 32
                  ? 'Enter a uid with 1–32 characters'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('developer-membership-set-plan'),
            initialValue: _planCode,
            isExpanded: true,
            decoration: _decoration('plan_code'),
            items: [
              for (final code in MembershipManualSetRequest.planCodes)
                DropdownMenuItem(value: code, child: Text(code)),
            ],
            onChanged: _submitting
                ? null
                : (value) {
                    if (value != null) setState(() => _planCode = value);
                  },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('developer-membership-set-expires-at'),
            controller: _expiresAt,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _decoration(
              'expires_at',
              helperText: 'Unix timestamp in seconds',
            ),
            validator: (value) {
              final seconds = int.tryParse(value?.trim() ?? '');
              return seconds == null || seconds < 1
                  ? 'Enter positive Unix seconds'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('developer-membership-set-reason'),
            controller: _reason,
            enabled: !_submitting,
            minLines: 1,
            maxLines: 3,
            decoration: _decoration('reason (optional)'),
            validator: (value) => (value?.trim().length ?? 0) > 512
                ? 'Use at most 512 characters'
                : null,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const ValueKey('developer-membership-set-submit'),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              _result!,
              key: const ValueKey('developer-membership-set-result'),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
