part of 'origin_editor_pages.dart';

class OriginBasicsEditorPage extends StatefulWidget {
  const OriginBasicsEditorPage({super.key, required this.repository});

  final OriginDraftRepository repository;

  @override
  State<OriginBasicsEditorPage> createState() => _OriginBasicsEditorPageState();
}

class _OriginBasicsEditorPageState extends State<OriginBasicsEditorPage> {
  final TextEditingController _originNameController = TextEditingController();
  final TextEditingController _worldViewController = TextEditingController();
  final TextEditingController _worldLogicController = TextEditingController();
  final TextEditingController _metricController = TextEditingController();
  final TextEditingController _coverImageController = TextEditingController();
  final TextEditingController _worldStartTimeController =
      TextEditingController();
  final TextEditingController _timeProgressCustomController =
      TextEditingController();
  final TextEditingController _progressMetricController =
      TextEditingController();
  final TextEditingController _labelNoteController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();
  final TextEditingController _startingValueController =
      TextEditingController();
  final TextEditingController _minValueController = TextEditingController();
  final TextEditingController _maxValueController = TextEditingController();
  final FocusNode _originNameFocusNode = FocusNode();
  final FocusNode _worldViewFocusNode = FocusNode();
  final FocusNode _worldLogicFocusNode = FocusNode();
  final FocusNode _worldStartTimeFocusNode = FocusNode();
  final FocusNode _timeProgressCustomFocusNode = FocusNode();
  final FocusNode _progressMetricFocusNode = FocusNode();
  final FocusNode _labelNoteFocusNode = FocusNode();
  final FocusNode _unitFocusNode = FocusNode();
  final FocusNode _startingValueFocusNode = FocusNode();
  final FocusNode _minValueFocusNode = FocusNode();
  final FocusNode _maxValueFocusNode = FocusNode();

  bool _isSaving = false;
  String _metricMode = 'qualitative';
  String _selectedTimeProgress = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final draft = await widget.repository.loadDraft();
    if (!mounted) return;
    _originNameController.text = draft.basics.originName;
    _worldViewController.text = draft.basics.worldView;
    _worldLogicController.text = draft.basics.worldLogic;
    _metricController.text = draft.basics.metricJson;
    _coverImageController.text = draft.basics.coverImageUrl;
    _loadSimulationSettings(
      metricJson: draft.basics.metricJson,
      startedAt: draft.basics.startedAt,
      tickDurationTime: draft.basics.tickDurationTime,
      tickDurationDays: draft.basics.tickDurationDays,
    );
    setState(() {});
  }

  void _onFormChanged() {
    setState(() {});
  }

  Future<CreateOriginDraft> _draftWithCurrentBasics({
    required bool basicsSaved,
    String? originId,
  }) async {
    final draft = await widget.repository.loadDraft();
    return draft.copyWith(
      basics: draft.basics.copyWith(
        originId: originId ?? draft.basics.originId,
        originName: normalizeGenesisUgcTextForDisplay(
          _originNameController.text,
        ),
        worldView: normalizeGenesisUgcTextForDisplay(_worldViewController.text),
        worldLogic: normalizeGenesisUgcTextForDisplay(
          _worldLogicController.text,
        ),
        metricJson: _simulationSettingsJson(),
        startedAt: _worldStartTimeController.text.trim(),
        tickDurationTime: _tickDurationTime(),
        tickDurationDays: _tickDurationDays(),
        coverImageUrl: _coverImageController.text.trim(),
      ),
      basicsSaved: basicsSaved,
    );
  }

  Future<void> _onSave() async {
    final originName = _originNameController.text.trim();
    final worldView = _worldViewController.text.trim();
    final metricJson = _simulationSettingsJson();
    final coverImage = _coverImageController.text.trim();

    if (originName.isEmpty) {
      _showError('Worldo Name is required.');
      return;
    }
    if (worldView.isEmpty) {
      _showError('Worldo Brief is required.');
      return;
    }
    if (coverImage.isEmpty) {
      _showError('Cover Image is required.');
      return;
    }
    if (metricJson.isNotEmpty) {
      try {
        jsonDecode(metricJson);
      } catch (_) {
        _showError('Metric must be valid JSON.');
        return;
      }
    }

    setState(() => _isSaving = true);
    final uidFuture = readCreateOriginUid(context);
    final draft = await widget.repository.loadDraft();
    final uid = await uidFuture;
    final originId = draft.basics.originId.trim().isEmpty
        ? createUidTimestampHashId(uid: uid, prefix: 'origin')
        : draft.basics.originId.trim();
    final updatedDraft = await _draftWithCurrentBasics(
      basicsSaved: true,
      originId: originId,
    );
    await widget.repository.saveFinalDraft(updatedDraft);
    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.of(context).pop(true);
  }

  bool get _canSaveCurrentBasics {
    if (_originNameController.text.trim().isEmpty ||
        _worldViewController.text.trim().isEmpty ||
        _coverImageController.text.trim().isEmpty) {
      return false;
    }
    final metricJson = _simulationSettingsJson();
    if (metricJson.trim().isEmpty) return true;
    try {
      jsonDecode(metricJson);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _canUseSaveButton {
    if (_isSaving) return false;
    return _canSaveCurrentBasics;
  }

  String get _saveDisabledReason {
    if (_isSaving) return 'Saving is already in progress.';
    if (_originNameController.text.trim().isEmpty) {
      return 'Worldo Name is required.';
    }
    if (_worldViewController.text.trim().isEmpty) {
      return 'Worldo Brief is required.';
    }
    if (_coverImageController.text.trim().isEmpty) {
      return 'Cover Image is required.';
    }
    final metricJson = _simulationSettingsJson();
    if (metricJson.trim().isNotEmpty) {
      try {
        jsonDecode(metricJson);
      } catch (_) {
        return 'Metric must be valid JSON.';
      }
    }
    return 'Complete all required fields before saving.';
  }

  void _showError(String message) {
    showGenesisToast(context, message, brightness: Brightness.dark);
  }

  void _loadSimulationSettings({
    required String metricJson,
    required String startedAt,
    required String tickDurationTime,
    required int? tickDurationDays,
  }) {
    _worldStartTimeController.text = startedAt.trim();
    final durationText = tickDurationTime.trim();
    if (durationText.isNotEmpty) {
      _selectedTimeProgress = _timeProgressOptionForValue(durationText);
      if (_selectedTimeProgress.isEmpty) {
        _timeProgressCustomController.text = durationText;
      }
    } else if (tickDurationDays != null) {
      final legacyValue = tickDurationDays == 1
          ? '1 day'
          : '$tickDurationDays days';
      _selectedTimeProgress = _timeProgressOptionForValue(legacyValue);
      if (_selectedTimeProgress.isEmpty) {
        _timeProgressCustomController.text = legacyValue;
      }
    }

    final raw = metricJson.trim();
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _worldStartTimeController.text = _worldStartTimeController.text.isNotEmpty
          ? _worldStartTimeController.text
          : decoded['start_time']?.toString() ?? '';
      _metricMode = decoded['mode']?.toString().trim().isNotEmpty == true
          ? decoded['mode'].toString().trim()
          : _metricMode;
      if (durationText.isEmpty && tickDurationDays == null) {
        _selectedTimeProgress = decoded['time_per_progress']?.toString() ?? '';
        _timeProgressCustomController.text =
            decoded['time_per_progress_custom']?.toString() ?? '';
      }
      _progressMetricController.text =
          decoded['label']?.toString() ??
          decoded['progress_metric']?.toString() ??
          '';
      _labelNoteController.text = decoded['label_note']?.toString() ?? '';
      _unitController.text = decoded['unit']?.toString() ?? '';
      final range = decoded['range'];
      if (range is List) {
        if (range.isNotEmpty) _minValueController.text = '${range.first}';
        if (range.length > 1) _maxValueController.text = '${range[1]}';
      }
      _startingValueController.text =
          decoded['default']?.toString() ??
          decoded['starting_value']?.toString() ??
          '';
    } catch (_) {
      return;
    }
  }

  String _simulationSettingsJson() {
    final values = <String, String>{
      'label': normalizeGenesisUgcTextForDisplay(
        _progressMetricController.text,
      ),
      'label_note': normalizeGenesisUgcTextForDisplay(
        _labelNoteController.text,
      ),
      'unit': normalizeGenesisUgcTextForDisplay(_unitController.text),
    }..removeWhere((_, value) => value.isEmpty);

    if (values.isEmpty) return _worldMetricFallbackJson();

    final payload = <String, dynamic>{
      'mode': _metricMode.trim().isEmpty ? 'qualitative' : _metricMode.trim(),
      ...values,
      if (_minValueController.text.trim().isNotEmpty &&
          _maxValueController.text.trim().isNotEmpty)
        'range': [
          _numericSetting(_minValueController.text.trim()),
          _numericSetting(_maxValueController.text.trim()),
        ],
      if (_startingValueController.text.trim().isNotEmpty)
        'default': _numericSetting(_startingValueController.text.trim()),
    };
    return jsonEncode(payload);
  }

  String _worldMetricFallbackJson() {
    final raw = _metricController.text.trim();
    if (raw.isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return raw;
      final payload = <String, dynamic>{
        for (final key in const [
          'mode',
          'label',
          'label_note',
          'unit',
          'range',
          'default',
        ])
          if (decoded[key] != null && decoded[key].toString().trim().isNotEmpty)
            key: decoded[key],
      };
      return payload.isEmpty ? '' : jsonEncode(payload);
    } catch (_) {
      return raw;
    }
  }

  int? _tickDurationDays() {
    final value = _tickDurationTime();
    if (value == null) return null;
    return _daysForTimeProgressValue(value);
  }

  String? _tickDurationTime() {
    final selected = _selectedTimeProgress.trim();
    if (selected.isNotEmpty) return selected;
    final custom = _timeProgressCustomController.text.trim();
    return custom.isEmpty ? null : custom;
  }

  int? _daysForTimeProgressValue(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      '1 day' => 1,
      '1 week' => 7,
      _ =>
        normalized.endsWith('days') || normalized.endsWith('day')
            ? int.tryParse(
                RegExp(r'\d+').firstMatch(normalized)?.group(0) ?? '',
              )
            : int.tryParse(normalized),
    };
  }

  String _timeProgressOptionForValue(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      '6 hours' => '6 hours',
      '12 hours' => '12 hours',
      '1 day' => '1 day',
      '1 week' => '1 week',
      _ => '',
    };
  }

  void _selectTimeProgress(String value) {
    setState(() {
      if (_selectedTimeProgress == value) {
        _selectedTimeProgress = '';
      } else {
        _selectedTimeProgress = value;
        _timeProgressCustomController.clear();
      }
    });
  }

  void _handleTimeProgressCustomChanged(String value) {
    setState(() {
      if (value.trim().isNotEmpty) {
        _selectedTimeProgress = '';
      }
    });
  }

  Object _numericSetting(String text) {
    final intValue = int.tryParse(text);
    if (intValue != null) return intValue;
    return double.tryParse(text) ?? text;
  }

  @override
  void dispose() {
    _originNameController.dispose();
    _worldViewController.dispose();
    _worldLogicController.dispose();
    _metricController.dispose();
    _coverImageController.dispose();
    _worldStartTimeController.dispose();
    _timeProgressCustomController.dispose();
    _progressMetricController.dispose();
    _labelNoteController.dispose();
    _unitController.dispose();
    _startingValueController.dispose();
    _minValueController.dispose();
    _maxValueController.dispose();
    _originNameFocusNode.dispose();
    _worldViewFocusNode.dispose();
    _worldLogicFocusNode.dispose();
    _worldStartTimeFocusNode.dispose();
    _timeProgressCustomFocusNode.dispose();
    _progressMetricFocusNode.dispose();
    _labelNoteFocusNode.dispose();
    _unitFocusNode.dispose();
    _startingValueFocusNode.dispose();
    _minValueFocusNode.dispose();
    _maxValueFocusNode.dispose();
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
        pageName: 'Basics',
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
                      CreateTextFieldBlock(
                        label: 'Worldo Name *',
                        controller: _originNameController,
                        hintText: 'eg. Main Street',
                        maxLength: 30,
                        maxLines: 1,
                        labelInputGap: _fieldLabelInputGap,
                        focusNode: _originNameFocusNode,
                        nextFocusNode: _worldViewFocusNode,
                        prefix: const Text(
                          '#',
                          style: TextStyle(
                            color: GenesisColors.darkTextPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onChanged: (_) => _onFormChanged(),
                      ),
                      const SizedBox(height: _fieldGroupGap),
                      CreateTextFieldBlock(
                        label: 'Worldo Brief *',
                        controller: _worldViewController,
                        hintText:
                            'eg. Half the shops on Main Street are boarded up. By Labor Day, the richest storefront owns the town.',
                        maxLength: 300,
                        note:
                            'The public hook players see first — the setting, the core conflict, and what makes it intriguing.',
                        minLines: 4,
                        maxLines: 8,
                        labelInputGap: _fieldLabelInputGap,
                        focusNode: _worldViewFocusNode,
                        nextFocusNode: _worldLogicFocusNode,
                        onChanged: (_) => _onFormChanged(),
                      ),
                      const SizedBox(height: _fieldGroupGap),
                      const Text(
                        'Cover Image *',
                        style: TextStyle(
                          color: GenesisColors.darkTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: _fieldLabelInputGap),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CreateUploadBox(
                            controller: _coverImageController,
                            label: 'Upload',
                            emptyBackgroundColor: GenesisColors.darkFaintFill,
                            emptyBorderColor: GenesisColors.darkTextTertiary,
                            emptyIconColor: GenesisColors.createAdd,
                            emptyLabelColor: GenesisColors.darkTextSecondary,
                            width: 170,
                            height: 230,
                            borderRadius: 8,
                            iconSize: 42,
                            cropSize: const Size(800, 1200),
                            emptyLabelFontSize: 14,
                            onChanged: _onFormChanged,
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: CreateFormNote(
                              note:
                                  'Used for cards and detail pages. Recommend ~768×1024 px. Supported formats: JPG, PNG, WEBP.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      const _AdvancedSettingsDivider(),
                      const SizedBox(height: 26),
                      CreateTextFieldBlock(
                        label: 'Worldo Settings - Hidden (Optional)',
                        controller: _worldLogicController,
                        hintText:
                            'eg. The banker secretly controls who gets loans; whoever overextends can be squeezed out.',
                        maxLength: 1000,
                        note:
                            'The hidden rules and backstory that drive the story — agendas, mechanics, and secret limits.',
                        minLines: 5,
                        maxLines: 12,
                        labelInputGap: _fieldLabelInputGap,
                        focusNode: _worldLogicFocusNode,
                        nextFocusNode: _worldStartTimeFocusNode,
                        onChanged: (_) => _onFormChanged(),
                      ),
                      const SizedBox(height: _fieldGroupGap),
                      const Text(
                        'Worldo Time (Optional)',
                        style: TextStyle(
                          color: GenesisColors.darkTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const CreateFormNote(
                        note:
                            'This worldo starts at {Start Time}; each time the user taps *progress*, the timeline moves forward by {Time per Progress}.',
                        markdown: true,
                      ),
                      const SizedBox(height: 14),
                      const _SimulationFieldLabel('Start Time'),
                      const SizedBox(height: _fieldLabelInputGap),
                      CreateTextFieldBlock(
                        label: '',
                        controller: _worldStartTimeController,
                        hintText: 'eg. Day 1, 09:00 / 2026-01-01',
                        maxLength: 30,
                        showCounter: false,
                        maxLines: 1,
                        focusNode: _worldStartTimeFocusNode,
                        nextFocusNode: _timeProgressCustomFocusNode,
                        onChanged: (_) => _onFormChanged(),
                      ),
                      const SizedBox(height: _fieldGroupGap),
                      const _SimulationFieldLabel('Time per Progress'),
                      const SizedBox(height: _fieldLabelInputGap),
                      _TimeProgressPicker(
                        selected: _selectedTimeProgress,
                        onSelected: _selectTimeProgress,
                      ),
                      const SizedBox(height: _fieldLabelInputGap),
                      CreateTextFieldBlock(
                        label: '',
                        controller: _timeProgressCustomController,
                        hintText: 'eg. 8 hours / 3 days',
                        maxLength: 10,
                        showCounter: false,
                        maxLines: 1,
                        focusNode: _timeProgressCustomFocusNode,
                        nextFocusNode: _progressMetricFocusNode,
                        prefix: const Text(
                          'Custom',
                          style: TextStyle(
                            color: GenesisColors.darkTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        onChanged: _handleTimeProgressCustomChanged,
                      ),
                      const SizedBox(height: _fieldGroupGap),
                      const Text(
                        'Worldo Metric (Optional)',
                        style: TextStyle(
                          color: GenesisColors.darkTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const CreateFormNote(
                        note:
                            "This worldo updates each character's {Metric Label} every progress, shown in {Unit}. Each character starts at {Starting}, and the value can move within {Delta Min}–{Delta Max}.",
                      ),
                      const SizedBox(height: 14),
                      const _SimulationFieldLabel('Metric Label'),
                      const SizedBox(height: _fieldLabelInputGap),
                      CreateTextFieldBlock(
                        label: '',
                        controller: _progressMetricController,
                        hintText: 'eg. Wealth / Goal Progress',
                        maxLength: 20,
                        showCounter: false,
                        maxLines: 1,
                        focusNode: _progressMetricFocusNode,
                        nextFocusNode: _labelNoteFocusNode,
                        onChanged: (_) => _onFormChanged(),
                      ),
                      const SizedBox(height: _fieldGroupGap),
                      const _SimulationFieldLabel('Label note'),
                      const SizedBox(height: _fieldLabelInputGap),
                      CreateTextFieldBlock(
                        label: '',
                        controller: _labelNoteController,
                        hintText: 'Describe what this metric measures',
                        maxLength: 50,
                        showCounter: false,
                        maxLines: 1,
                        focusNode: _labelNoteFocusNode,
                        nextFocusNode: _unitFocusNode,
                        onChanged: (_) => _onFormChanged(),
                      ),
                      const SizedBox(height: _fieldGroupGap),
                      const _SimulationFieldLabel('Unit'),
                      const SizedBox(height: _fieldLabelInputGap),
                      CreateTextFieldBlock(
                        label: '',
                        controller: _unitController,
                        hintText: 'eg. coins / %',
                        maxLength: 10,
                        showCounter: false,
                        maxLines: 1,
                        focusNode: _unitFocusNode,
                        nextFocusNode: _startingValueFocusNode,
                        onChanged: (_) => _onFormChanged(),
                      ),
                      const SizedBox(height: _fieldGroupGap),
                      const _SimulationFieldLabel('Value Range'),
                      const SizedBox(height: _fieldLabelInputGap),
                      Row(
                        children: [
                          Expanded(
                            child: CreateTextFieldBlock(
                              label: '',
                              controller: _startingValueController,
                              hintText: 'Starting',
                              maxLength: 10,
                              showCounter: false,
                              maxLines: 1,
                              focusNode: _startingValueFocusNode,
                              nextFocusNode: _minValueFocusNode,
                              onChanged: (_) => _onFormChanged(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CreateTextFieldBlock(
                              label: '',
                              controller: _minValueController,
                              hintText: 'Delta Min',
                              maxLength: 10,
                              showCounter: false,
                              maxLines: 1,
                              focusNode: _minValueFocusNode,
                              nextFocusNode: _maxValueFocusNode,
                              onChanged: (_) => _onFormChanged(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CreateTextFieldBlock(
                              label: '',
                              controller: _maxValueController,
                              hintText: 'Delta Max',
                              maxLength: 10,
                              showCounter: false,
                              maxLines: 1,
                              focusNode: _maxValueFocusNode,
                              onChanged: (_) => _onFormChanged(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _KeyboardHiddenBottomAction(
                child: GenesisPrimaryButton(
                  label: _isSaving ? 'Saving...' : 'Save',
                  backgroundColor: GenesisColors.redPrimary,
                  foregroundColor: GenesisColors.darkTextPrimary,
                  width: _primaryActionButtonWidth(context),
                  onPressed: _canUseSaveButton ? _onSave : null,
                  onDisabledPressed: () => _showError(_saveDisabledReason),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdvancedSettingsDivider extends StatelessWidget {
  const _AdvancedSettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(height: 1, color: GenesisColors.darkFaintFill)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Advanced Settings (Optional)',
            style: TextStyle(
              color: GenesisColors.darkTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
        Expanded(child: Divider(height: 1, color: GenesisColors.darkFaintFill)),
      ],
    );
  }
}

class _SimulationFieldLabel extends StatelessWidget {
  const _SimulationFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: GenesisColors.darkTextSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );
  }
}

class _TimeProgressPicker extends StatelessWidget {
  const _TimeProgressPicker({required this.selected, required this.onSelected});

  static const List<String> _options = <String>[
    '6 hours',
    '12 hours',
    '1 day',
    '1 week',
  ];

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 4.8,
      children: [
        for (final option in _options)
          _TimeProgressOption(
            label: option,
            selected: option == selected,
            onTap: () => onSelected(option == selected ? '' : option),
          ),
      ],
    );
  }
}

class _TimeProgressOption extends StatelessWidget {
  const _TimeProgressOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('time-progress-option-$label'),
      color: selected
          ? GenesisColors.darkTextPrimary
          : GenesisColors.darkFaintFill,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? GenesisColors.darkBackground
                  : GenesisColors.darkTextSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
