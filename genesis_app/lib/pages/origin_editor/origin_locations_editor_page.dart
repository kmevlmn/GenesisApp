part of 'origin_editor_pages.dart';

enum _LocationsEditorMode { preview, edit }

enum _L3EditorSheetAction { save, delete }

class OriginLocationsEditorPage extends StatefulWidget {
  const OriginLocationsEditorPage({
    super.key,
    required this.repository,
    this.useLocationTree = false,
    this.locationIdGenerator = const UuidLocationIdGenerator(),
  });

  final OriginDraftRepository repository;
  final bool useLocationTree;
  final LocationIdGenerator locationIdGenerator;

  @override
  State<OriginLocationsEditorPage> createState() =>
      _OriginLocationsEditorPageState();
}

class _OriginLocationsEditorPageState extends State<OriginLocationsEditorPage> {
  static const int _maxLocations = 15;
  static const String _statisticsNote =
      'Your world is built in 3 levels:\n'
      'L1 · Region     An area of your world — Downtown\n'
      "L2 · Building   A building inside it — Joe's Diner\n"
      'L3 · Room       A room inside that building — The Back Kitchen\n'
      'Every location needs all three levels. Up to 15 rooms in total.';
  static const String _l1NameNote =
      'An area of your world — a district, a town, a forest. '
      'Not a single building.';
  static const String _l2NameNote =
      'A building inside this region — a shop, a school, an apartment block.';
  static const String _l3NameNote =
      'A room inside the building. Rooftops, courtyards and entrances '
      'work too.';
  static const String _completeRequiredLocationMessage =
      'Please complete this location or delete it.';
  final List<_LocationForm> _forms = <_LocationForm>[];
  final List<_L1LocationForm> _treeForms = <_L1LocationForm>[];
  final Set<String> _reservedLocationIds = <String>{};
  String _openingLocationId = '';
  List<CharacterDraft> _finalCharacters = const <CharacterDraft>[];
  bool _isSaving = false;
  _LocationsEditorMode _mode = _LocationsEditorMode.edit;
  String? _inlineEditingLocationId;
  String? _requiredInlineLocationId;
  String? _requiredFlowL1Id;
  final GlobalKey _rootAddL1VisibilityKey = GlobalKey();
  bool _revealRootAddL1AfterKeyboard = false;
  bool _suppressRequiredActionForCurrentTap = false;
  late FocusNode _inlineNameFocusNode;
  late FocusNode _nextInlineNameFocusNode;
  late TextEditingController _inlineNameController;
  late TextEditingController _nextInlineNameController;

  @override
  void initState() {
    super.initState();
    _inlineNameFocusNode = FocusNode();
    _nextInlineNameFocusNode = FocusNode();
    _inlineNameController = TextEditingController();
    _nextInlineNameController = TextEditingController();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final draft = await widget.repository.loadDraft();
    _finalCharacters = await widget.repository.loadSavedCharacters();
    _openingLocationId = draft.openingSaved
        ? draft.opening.locationId.trim()
        : '';
    final source = draft.locations.isEmpty
        ? const <LocationDraft>[LocationDraft()]
        : draft.locations;
    _reservedLocationIds.addAll(
      source
          .map((item) => item.locationId.trim())
          .where((item) => item.isNotEmpty),
    );
    if (widget.useLocationTree) {
      _treeForms.addAll(_createLocationTrees(source));
      _requiredInlineLocationId = _firstIncompleteParentLocationId();
      _inlineEditingLocationId = _requiredInlineLocationId;
      _inlineNameController.text =
          _inlineLocationNameController(_inlineEditingLocationId)?.text ?? '';
    } else {
      for (final item in source) {
        _forms.add(
          _LocationForm.fromDraft(
            item,
            createLocationId: _generateUniqueLocationId,
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {});
    if (_requiredInlineLocationId != null) {
      _requestInlineNameFocus();
    }
  }

  String _generateUniqueLocationId() {
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final candidate = widget.locationIdGenerator.generate().trim();
      if (!compactLocationIdPattern.hasMatch(candidate)) {
        throw StateError(
          'Generated location ID must be $compactLocationIdLength lowercase '
          'hex characters.',
        );
      }
      if (_reservedLocationIds.add(candidate)) return candidate;
    }
    throw StateError('Unable to generate a unique location ID.');
  }

  Future<void> _saveLocations() async {
    if (_blockForRequiredLocation()) return;
    if (widget.useLocationTree) {
      for (int l1Index = 0; l1Index < _treeForms.length; l1Index++) {
        final l1 = _treeForms[l1Index];
        if (l1.name.text.trim().isEmpty) {
          _showError('L1 location name is required.');
          return;
        }
        for (int l2Index = 0; l2Index < l1.children.length; l2Index++) {
          final l2 = l1.children[l2Index];
          if (l2.name.text.trim().isEmpty) {
            _showError(
              '${_locationNameLabel(l1.name, fallback: 'This L1 location')} '
              'has an L2 location that needs a name.',
            );
            return;
          }
          for (int l3Index = 0; l3Index < l2.children.length; l3Index++) {
            if (l2.children[l3Index].name.text.trim().isEmpty) {
              _showError(
                '${_locationNameLabel(l2.name, fallback: 'This L2 location')} '
                'has an L3 location that needs a name.',
              );
              return;
            }
          }
        }
      }
    } else {
      for (int i = 0; i < _forms.length; i++) {
        final form = _forms[i];
        if (!form.hasContent) continue;
        if (form.name.text.trim().isEmpty) {
          _showError('Location name is required.');
          return;
        }
      }
    }

    final currentLocations = _snapshotLocations()
        .where(_locationDraftHasContent)
        .toList(growable: false);
    if (currentLocations.isEmpty) {
      _showError('Please create at least one location.');
      return;
    }
    final identityError = _locationIdentityError(currentLocations);
    if (identityError != null) {
      _showError(identityError);
      return;
    }

    setState(() => _isSaving = true);
    final draft = await widget.repository.loadDraft();
    _finalCharacters = await widget.repository.loadSavedCharacters();
    final locations = _snapshotLocations()
        .where(_locationDraftHasContent)
        .toList(growable: false);
    final openingLocationId = draft.opening.locationId.trim();
    final shouldClearOpening =
        draft.openingSaved &&
        openingLocationId.isNotEmpty &&
        !locations.any(
          (location) =>
              (location.level == 0 || location.level == 3) &&
              location.locationId.trim() == openingLocationId,
        );

    await widget.repository.saveFinalDraft(
      draft.copyWith(
        locations: locations,
        locationsSaved: locations.isNotEmpty,
        opening: shouldClearOpening ? const OpeningDraft() : draft.opening,
        openingSaved: shouldClearOpening ? false : draft.openingSaved,
      ),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.of(context).pop(true);
  }

  String? _locationIdentityError(List<LocationDraft> locations) {
    final locationsById = <String, LocationDraft>{};
    for (final location in locations) {
      final locationId = location.locationId.trim();
      if (locationId.isEmpty) return 'Every location must have an ID.';
      if (locationsById.containsKey(locationId)) {
        return 'Every location must have a unique ID.';
      }
      locationsById[locationId] = location;
    }
    for (final location in locations) {
      final expectedParentLevel = switch (location.level) {
        2 => 1,
        3 => 2,
        _ => null,
      };
      if (expectedParentLevel == null) continue;
      final parent = locationsById[location.parentLocationId.trim()];
      if (parent == null || parent.level != expectedParentLevel) {
        return 'Every location must have a valid parent.';
      }
    }
    return null;
  }

  bool get _canSaveCurrentLocations {
    if (widget.useLocationTree) {
      if (_treeForms.isEmpty || _l3LocationCount == 0) return false;
      for (final l1 in _treeForms) {
        if (l1.name.text.trim().isEmpty || l1.children.isEmpty) return false;
        for (final l2 in l1.children) {
          if (l2.name.text.trim().isEmpty || l2.children.isEmpty) return false;
          if (l2.children.any((item) => item.name.text.trim().isEmpty)) {
            return false;
          }
        }
      }
      return true;
    }
    var hasCompleteLocation = false;
    for (final form in _forms) {
      if (!form.hasContent) continue;
      if (form.name.text.trim().isEmpty) return false;
      hasCompleteLocation = true;
    }
    return hasCompleteLocation;
  }

  bool get _canUseSaveButton {
    if (_isSaving) return false;
    return _canSaveCurrentLocations;
  }

  String get _saveDisabledReason {
    if (_isSaving) return 'Saving is already in progress.';
    if (widget.useLocationTree) {
      if (_treeForms.isEmpty) return 'Add at least one L1 location.';
      for (int l1Index = 0; l1Index < _treeForms.length; l1Index++) {
        final l1 = _treeForms[l1Index];
        if (l1.name.text.trim().isEmpty) {
          return 'L1 location name is required.';
        }
        if (l1.children.isEmpty) {
          return _l1NeedsL2Message(l1);
        }
        for (int l2Index = 0; l2Index < l1.children.length; l2Index++) {
          final l2 = l1.children[l2Index];
          if (l2.name.text.trim().isEmpty) {
            return '${_locationNameLabel(l1.name, fallback: 'This L1 location')} '
                'has an L2 location that needs a name.';
          }
          if (l2.children.isEmpty) {
            return _l2NeedsL3Message(l2);
          }
          for (int l3Index = 0; l3Index < l2.children.length; l3Index++) {
            if (l2.children[l3Index].name.text.trim().isEmpty) {
              return '${_locationNameLabel(l2.name, fallback: 'This L2 location')} '
                  'has an L3 location that needs a name.';
            }
          }
        }
      }
    } else {
      for (int index = 0; index < _forms.length; index++) {
        final form = _forms[index];
        if (!form.hasContent) continue;
        if (form.name.text.trim().isEmpty) {
          return 'Location name is required.';
        }
      }
      if (!_forms.any((form) => form.hasContent)) {
        return 'Please create at least one location.';
      }
    }
    return 'Complete all required location fields before saving.';
  }

  void _showError(String message) {
    showGenesisToast(context, message, brightness: Brightness.dark);
  }

  void _setLocationEditorState(VoidCallback callback) {
    setState(callback);
  }

  Widget _buildBottomSaveAction({VoidCallback? onShown}) {
    return _KeyboardHiddenBottomAction(
      onShown: onShown,
      minimum: const EdgeInsets.fromLTRB(28, 8, 28, 14),
      child: GenesisPrimaryButton(
        label: _isSaving ? 'Saving...' : 'Save',
        backgroundColor: GenesisColors.redPrimary,
        foregroundColor: GenesisColors.darkTextPrimary,
        disabledBackgroundColor: GenesisColors.redSecondary,
        disabledForegroundColor: GenesisColors.darkTextPrimary,
        width: _primaryActionButtonWidth(context),
        onPressed: _canUseSaveButton ? _saveLocations : null,
        onDisabledPressed: () => _showError(_saveDisabledReason),
      ),
    );
  }

  @override
  void dispose() {
    _inlineNameController.dispose();
    _nextInlineNameController.dispose();
    _inlineNameFocusNode.dispose();
    _nextInlineNameFocusNode.dispose();
    for (final form in _forms) {
      form.dispose();
    }
    for (final form in _treeForms) {
      form.dispose();
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
    return Listener(
      onPointerUp: (_) => _releaseInlineOutsideTapSuppression(),
      onPointerCancel: (_) => _releaseInlineOutsideTapSuppression(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: GenesisColors.darkBackground,
        appBar: GenesisBackAppBar(
          pageName: 'Locations',
          backgroundColor: GenesisColors.darkBackground,
          foregroundColor: GenesisColors.darkTextPrimary,
          systemOverlayStyle: kGenesisLightSystemUiOverlayStyle,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Transform.translate(
                offset: const Offset(0, 1.2),
                child: _LocationsModeSwitch(mode: _mode, onChanged: _setMode),
              ),
            ),
          ],
        ),
        body: _mode == _LocationsEditorMode.preview
            ? _buildPreviewBody()
            : _buildEditBody(),
      ),
    );
  }
}
