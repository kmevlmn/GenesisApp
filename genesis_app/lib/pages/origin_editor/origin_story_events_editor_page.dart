part of 'origin_editor_pages.dart';

class OriginStoryEventsEditorPage extends StatefulWidget {
  const OriginStoryEventsEditorPage({super.key, required this.repository});

  final OriginDraftRepository repository;

  @override
  State<OriginStoryEventsEditorPage> createState() =>
      _OriginStoryEventsEditorPageState();
}

class _OriginStoryEventsEditorPageState
    extends State<OriginStoryEventsEditorPage> {
  static const int _maxEvents = 10;
  final List<TextEditingController> _eventControllers =
      <TextEditingController>[];
  final List<FocusNode> _eventFocusNodes = <FocusNode>[];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final draft = await widget.repository.loadDraft();
    final source = draft.storyEvents.isEmpty
        ? const <StoryEventDraft>[StoryEventDraft()]
        : draft.storyEvents;
    for (final event in source) {
      _eventControllers.add(TextEditingController(text: event.event));
      _eventFocusNodes.add(FocusNode());
    }
    if (!mounted) return;
    setState(() {});
  }

  void _addEvent() {
    if (_eventControllers.length >= _maxEvents) {
      _showError('You can add up to $_maxEvents events.');
      return;
    }
    setState(() {
      _eventControllers.add(TextEditingController());
      _eventFocusNodes.add(FocusNode());
    });
    _onFormChanged();
  }

  void _requestRemoveEvent(int index) {
    _removeEvent(index);
  }

  void _removeEvent(int index) {
    if (_eventControllers.length <= 1) {
      _eventControllers[index].clear();
    } else {
      final controller = _eventControllers.removeAt(index);
      final focusNode = _eventFocusNodes.removeAt(index);
      controller.dispose();
      focusNode.dispose();
    }
    _onFormChanged();
  }

  void _onFormChanged() {
    setState(() {});
  }

  List<StoryEventDraft> _snapshotEvents() {
    return _eventControllers
        .map(
          (controller) => StoryEventDraft(
            event: normalizeGenesisUgcTextForDisplay(controller.text),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _saveEvents() async {
    setState(() => _isSaving = true);
    final draft = await widget.repository.loadDraft();
    final events = _snapshotEvents()
        .where((item) => item.event.trim().isNotEmpty)
        .toList(growable: false);

    await widget.repository.saveFinalDraft(
      draft.copyWith(storyEvents: events, storyEventsSaved: events.isNotEmpty),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.of(context).pop(true);
  }

  bool get _canUseSaveButton {
    return !_isSaving;
  }

  void _showError(String message) {
    showGenesisToast(context, message, brightness: Brightness.dark);
  }

  @override
  void dispose() {
    for (final controller in _eventControllers) {
      controller.dispose();
    }
    for (final focusNode in _eventFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GenesisDarkTheme(
      child: GenesisBottomSystemBarStyleScope(
        style: const GenesisBottomSystemBarStyle(
          color: GenesisColors.darkBackground,
        ),
        child: CreateFormTheme(child: _buildPage(context)),
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: GenesisColors.darkBackground,
      appBar: const GenesisBackAppBar(
        pageName: 'Story Events',
        backgroundColor: GenesisColors.darkBackground,
        foregroundColor: GenesisColors.darkTextPrimary,
        systemOverlayStyle: kGenesisLightSystemUiOverlayStyle,
      ),
      body: CreateKeyboardDismissArea(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_eventControllers.length}/$_maxEvents (Added / Max)',
                          style: const TextStyle(
                            color: GenesisColors.darkTextTertiary,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (int i = 0; i < _eventControllers.length; i++) ...[
                        _StoryEventCard(
                          index: i + 1,
                          controller: _eventControllers[i],
                          focusNode: _eventFocusNodes[i],
                          nextFocusNode: i + 1 < _eventFocusNodes.length
                              ? _eventFocusNodes[i + 1]
                              : null,
                          onChanged: _onFormChanged,
                          onDelete: () {
                            _requestRemoveEvent(i);
                          },
                        ),
                        if (i + 1 < _eventControllers.length)
                          const SizedBox(height: 12),
                      ],
                      if (_eventControllers.isNotEmpty)
                        const SizedBox(height: 12),
                      CreateInlineAddButton(
                        label: '+ Add Event',
                        onTap: _addEvent,
                        fontSize: 16,
                        centered: true,
                        contentPadding: const EdgeInsets.fromLTRB(0, 11, 0, 5),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              _KeyboardHiddenBottomAction(
                minimum: const EdgeInsets.fromLTRB(28, 8, 28, 14),
                child: GenesisPrimaryButton(
                  label: _isSaving ? 'Saving...' : 'Save',
                  backgroundColor: GenesisColors.redPrimary,
                  foregroundColor: GenesisColors.darkTextPrimary,
                  width: _primaryActionButtonWidth(context),
                  onPressed: _canUseSaveButton ? _saveEvents : null,
                  onDisabledPressed: () =>
                      _showError('Saving is already in progress.'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryEventCard extends StatelessWidget {
  const _StoryEventCard({
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.nextFocusNode,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? nextFocusNode;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return CreateFormCard(
      title: 'Event $index',
      onDelete: onDelete,
      showBorder: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          CreateTextFieldBlock(
            label: '',
            controller: controller,
            hintText:
                'eg. A national chain scouts a vacant lot, threatening to undercut every local on price.',
            maxLength: 100,
            note: 'A key story beat the AI uses to steer the storyline.',
            minLines: 5,
            maxLines: 5,
            labelSize: 0,
            focusNode: focusNode,
            nextFocusNode: nextFocusNode,
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}
