part of 'me_page.dart';

class _NickNameDialog extends StatefulWidget {
  const _NickNameDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_NickNameDialog> createState() => _NickNameDialogState();
}

class _NickNameDialogState extends State<_NickNameDialog> {
  static const int _maxLength = 30;

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: genesisDisplaySafeText(widget.initialValue),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GenesisActionBox<String>(
      title: 'Edit name',
      titleHeight: 126,
      titleContentSpacing: 24,
      titleContent: Transform.translate(
        offset: const Offset(0, 4),
        child: _NickNameInput(
          controller: _controller,
          maxLength: _maxLength,
          onChanged: () => setState(() {}),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ),
      actions: const [GenesisActionBoxAction<String>(label: 'OK', value: 'ok')],
      onActionSelected: (_) => Navigator.of(context).pop(_controller.text),
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}

class _NickNameInput extends StatelessWidget {
  const _NickNameInput({
    required this.controller,
    required this.maxLength,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final int maxLength;
  final VoidCallback onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    const border = UnderlineInputBorder(
      borderSide: BorderSide(color: GenesisColors.darkFaintFill),
    );
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            key: const ValueKey<String>('me-edit-nickname-input'),
            controller: controller,
            autofocus: true,
            cursorColor: GenesisColors.darkTextPrimary,
            maxLines: 1,
            maxLength: maxLength,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              isDense: true,
              counterText: '',
              enabledBorder: border,
              focusedBorder: border,
              contentPadding: EdgeInsets.only(bottom: 5),
            ),
            style: const TextStyle(
              color: GenesisColors.darkTextPrimary,
              fontSize: 14,
              height: 1.2,
            ),
            onChanged: (_) => onChanged(),
            onSubmitted: onSubmitted,
          ),
          const SizedBox(height: 3),
          Text(
            '${controller.text.characters.length}/$maxLength',
            style: const TextStyle(
              color: GenesisColors.darkTextTertiary,
              fontSize: 11,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

String _mapString(
  Map<dynamic, dynamic>? map,
  String key, {
  String fallback = '',
}) {
  final value = map == null ? null : map[key];
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _mapInt(Map<dynamic, dynamic>? map, String key) {
  return _mapIntOrNull(map, key) ?? 0;
}

int? _mapIntOrNull(Map<dynamic, dynamic>? map, String key) {
  final value = map == null ? null : map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
