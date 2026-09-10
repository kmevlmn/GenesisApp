import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../components/common/genesis_center_toast.dart';
import '../ui/tokens/genesis_typography.dart';
import '../ui/theme/genesis_theme.dart';
import 'debug_floating_button_visibility.dart';

const String _debugFloatingButtonPassword = '6688';

Future<void> requestGenesisDebugFloatingButtonUnlock(
  BuildContext context, {
  bool isDebugBuild = kDebugMode,
}) async {
  if (isDebugBuild) {
    showGenesisDebugFloatingButton();
    showGenesisToast(context, 'Debug button shown');
    return;
  }

  final unlocked = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const GenesisLightTheme(child: _DebugPasswordDialog()),
  );
  if (!context.mounted || unlocked != true) return;
  showGenesisDebugFloatingButton();
  showGenesisToast(context, 'Debug button shown');
}

class _DebugPasswordDialog extends StatefulWidget {
  const _DebugPasswordDialog();

  @override
  State<_DebugPasswordDialog> createState() => _DebugPasswordDialogState();
}

class _DebugPasswordDialogState extends State<_DebugPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  var _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim() == _debugFloatingButtonPassword) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _error = true);
  }

  @override
  Widget build(BuildContext context) {
    final inputBorderColor = _error
        ? const Color(0xFFFF2442)
        : const Color(0xFF777777);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE7B85E), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(38, 30, 38, 30),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: TextField(
                    key: const ValueKey<String>('debug-password-input'),
                    controller: _controller,
                    focusNode: _focusNode,
                    cursorColor:
                        Theme.of(context).textTheme.bodyLarge?.color ??
                        const Color(0xFF111111),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Enter password',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: inputBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: inputBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _error
                              ? const Color(0xFFFF2442)
                              : const Color(0xFF008D68),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 106,
                height: 52,
                child: OutlinedButton(
                  key: const ValueKey<String>('debug-password-confirm'),
                  onPressed: _submit,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFFCF2),
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Color(0xFFBEB7A7)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: GenesisTypography.fontFamily,
                      fontFamilyFallback: GenesisTypography.fontFamilyFallback,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
