part of 'chat_ui_library.dart';

/// Enables inline editing while preserving the normal message row geometry.
class ChatMessageEditorScope extends InheritedWidget {
  const ChatMessageEditorScope({
    super.key,
    required this.controllers,
    this.onEditorActivated,
    this.onEditorDeactivated,
    required super.child,
  });

  final Map<String, TextEditingController> controllers;
  final ValueChanged<String>? onEditorActivated;
  final ValueChanged<String>? onEditorDeactivated;

  static TextEditingController? controllerOf(BuildContext context, String id) =>
      context
          .dependOnInheritedWidgetOfExactType<ChatMessageEditorScope>()
          ?.controllers[id];

  @override
  bool updateShouldNotify(ChatMessageEditorScope oldWidget) =>
      controllers != oldWidget.controllers ||
      onEditorActivated != oldWidget.onEditorActivated ||
      onEditorDeactivated != oldWidget.onEditorDeactivated;
}

class _ChatMessageTextEditor extends StatefulWidget {
  const _ChatMessageTextEditor({
    required this.messageId,
    required this.controller,
    required this.style,
  });

  final String messageId;
  final TextEditingController controller;
  final TextStyle style;

  @override
  State<_ChatMessageTextEditor> createState() => _ChatMessageTextEditorState();
}

class _ChatMessageTextEditorState extends State<_ChatMessageTextEditor> {
  final _focusNode = FocusNode();
  bool _placeCaretAtEnd = true;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _activate() {
    context
        .getInheritedWidgetOfExactType<ChatMessageEditorScope>()
        ?.onEditorActivated
        ?.call(widget.messageId);
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _activate();
    } else {
      context
          .getInheritedWidgetOfExactType<ChatMessageEditorScope>()
          ?.onEditorDeactivated
          ?.call(widget.messageId);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      _placeCaretAtEnd =
          !_focusNode.hasFocus || View.of(context).viewInsets.bottom == 0;
    },
    child: TextField(
      key: ValueKey('chat-message-editor-${widget.messageId}'),
      controller: widget.controller,
      focusNode: _focusNode,
      style: GenesisTypography.resolve(context, widget.style),
      cursorColor: widget.style.color,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      minLines: 1,
      maxLines: null,
      scrollPadding: const EdgeInsets.all(24),
      onTap: () {
        if (_placeCaretAtEnd) {
          widget.controller.selection = TextSelection.collapsed(
            offset: widget.controller.text.length,
          );
          _activate();
        }
      },
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    ),
  );
}
