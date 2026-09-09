part of 'origin_editor_pages.dart';

extension _OriginLocationsTree on _OriginLocationsEditorPageState {
  List<_L1LocationForm> _createLocationTrees(List<LocationDraft> source) {
    final populated = source
        .where(_locationDraftHasContent)
        .toList(growable: false);
    if (populated.isEmpty) return <_L1LocationForm>[_newL1Location()];

    final trees = <_L1LocationForm>[];
    final l1BySourceId = <String, _L1LocationForm>{};
    final l2BySourceId = <String, _L2LocationForm>{};
    _L1LocationForm? fallbackL1;
    _L2LocationForm? fallbackL2;

    _L1LocationForm ensureFallbackL1() {
      final existing = fallbackL1;
      if (existing != null) return existing;
      final created = _L1LocationForm(
        locationId: _generateUniqueLocationId(),
        name: TextEditingController(),
        children: <_L2LocationForm>[],
      );
      trees.add(created);
      fallbackL1 = created;
      return created;
    }

    _L2LocationForm ensureFallbackL2() {
      final existing = fallbackL2;
      if (existing != null) return existing;
      final parent = ensureFallbackL1();
      final created = _L2LocationForm(
        locationId: _generateUniqueLocationId(),
        name: TextEditingController(),
        children: <_LocationForm>[],
      );
      parent.children.add(created);
      fallbackL2 = created;
      return created;
    }

    final l1Drafts = populated.where((item) => item.level == 1);
    for (final l1Draft in l1Drafts) {
      final l1Id = l1Draft.locationId.trim().isEmpty
          ? _generateUniqueLocationId()
          : l1Draft.locationId.trim();
      final l1 = _L1LocationForm(
        locationId: l1Id,
        name: TextEditingController(text: l1Draft.name),
        children: <_L2LocationForm>[],
      );
      trees.add(l1);
      final sourceId = l1Draft.locationId.trim();
      if (sourceId.isNotEmpty) l1BySourceId.putIfAbsent(sourceId, () => l1);
    }

    final l2Drafts = populated.where((item) => item.level == 2);
    for (final l2Draft in l2Drafts) {
      final sourceParentId = l2Draft.parentLocationId.trim();
      final parent = l1BySourceId[sourceParentId] ?? ensureFallbackL1();
      final sourceId = l2Draft.locationId.trim();
      final l2 = _L2LocationForm(
        locationId: sourceId.isEmpty ? _generateUniqueLocationId() : sourceId,
        name: TextEditingController(text: l2Draft.name),
        children: <_LocationForm>[],
      );
      parent.children.add(l2);
      if (sourceId.isNotEmpty) l2BySourceId.putIfAbsent(sourceId, () => l2);
    }

    final leafDrafts = populated.where(
      (item) => item.level != 1 && item.level != 2,
    );
    for (final leafDraft in leafDrafts) {
      final sourceParentId = leafDraft.parentLocationId.trim();
      final parent = l2BySourceId[sourceParentId] ?? ensureFallbackL2();
      final sourceId = leafDraft.locationId.trim();
      parent.children.add(
        _LocationForm.treeLeaf(
          locationId: sourceId.isEmpty ? _generateUniqueLocationId() : sourceId,
          parentLocationId: parent.locationId,
          draft: leafDraft,
        ),
      );
    }

    if (trees.isEmpty) trees.add(_newL1Location());
    for (final l1 in trees) {
      if (l1.name.text.trim().isNotEmpty && l1.children.isEmpty) {
        l1.children.add(_newL2Location(l1));
      }
    }
    return trees;
  }

  _L1LocationForm _newL1Location() {
    final l1 = _L1LocationForm(
      locationId: _generateUniqueLocationId(),
      name: TextEditingController(),
      children: <_L2LocationForm>[],
    );
    return l1;
  }

  _L2LocationForm _newL2Location(_L1LocationForm parent) {
    final l2 = _L2LocationForm(
      locationId: _generateUniqueLocationId(),
      name: TextEditingController(),
      children: <_LocationForm>[],
    );
    return l2;
  }

  _LocationForm _newL3Location(_L2LocationForm parent) {
    return _LocationForm.treeLeaf(
      locationId: _generateUniqueLocationId(),
      parentLocationId: parent.locationId,
    );
  }

  int get _l1LocationCount => _treeForms.length;

  int get _l2LocationCount =>
      _treeForms.fold<int>(0, (count, l1) => count + l1.children.length);

  int get _l3LocationCount => _allL3Forms.length;

  String _displayLocationId(String locationId) {
    for (var l1Index = 0; l1Index < _treeForms.length; l1Index += 1) {
      final l1 = _treeForms[l1Index];
      if (l1.locationId == locationId) return 'Loc_${l1Index + 1}';
      for (var l2Index = 0; l2Index < l1.children.length; l2Index += 1) {
        final l2 = l1.children[l2Index];
        if (l2.locationId == locationId) {
          return 'Loc_${l1Index + 1}_${l2Index + 1}';
        }
        for (var l3Index = 0; l3Index < l2.children.length; l3Index += 1) {
          if (l2.children[l3Index].locationId == locationId) {
            return 'Loc_${l1Index + 1}_${l2Index + 1}_${l3Index + 1}';
          }
        }
      }
    }
    return locationId;
  }

  String? _firstIncompleteParentLocationId() {
    for (final l1 in _treeForms) {
      if (l1.name.text.trim().isEmpty) return l1.locationId;
      for (final l2 in l1.children) {
        if (l2.name.text.trim().isEmpty) return l2.locationId;
      }
    }
    return null;
  }

  TextEditingController? _inlineLocationNameController(String? locationId) {
    if (locationId == null) return null;
    for (final l1 in _treeForms) {
      if (l1.locationId == locationId) return l1.name;
      for (final l2 in l1.children) {
        if (l2.locationId == locationId) return l2.name;
      }
    }
    return null;
  }

  bool _l2HasSavedL3(_L2LocationForm l2) {
    return l2.children.any((form) => form.name.text.trim().isNotEmpty);
  }

  bool _l1HasCompletePath(_L1LocationForm l1) {
    if (l1.name.text.trim().isEmpty) return false;
    return l1.children.any(
      (l2) => l2.name.text.trim().isNotEmpty && _l2HasSavedL3(l2),
    );
  }

  bool get _hasCompleteTree => _treeForms.any(_l1HasCompletePath);

  String _locationNameLabel(
    TextEditingController controller, {
    required String fallback,
  }) {
    final name = controller.text.trim();
    return name.isEmpty ? fallback : '"$name"';
  }

  String _l1NeedsL2Message(_L1LocationForm l1) {
    return '${_locationNameLabel(l1.name, fallback: 'This L1 location')} '
        'must contain at least one L2 location.';
  }

  String _l2NeedsL3Message(_L2LocationForm l2) {
    return '${_locationNameLabel(l2.name, fallback: 'This L2 location')} '
        'must contain at least one L3 location.';
  }

  void _addL1Location() {
    if (_blockForRequiredLocation()) return;
    if (_l3LocationCount >= _OriginLocationsEditorPageState._maxLocations) {
      _showError(
        'You can add up to '
        '${_OriginLocationsEditorPageState._maxLocations} L3 locations.',
      );
      return;
    }
    final form = _newL1Location();
    _inlineNameController.clear();
    _setLocationEditorState(() {
      _treeForms.add(form);
      _requiredFlowL1Id = form.locationId;
      _requiredInlineLocationId = form.locationId;
      _inlineEditingLocationId = form.locationId;
    });
    _requestInlineNameFocus();
  }

  void _addL2Location(_L1LocationForm parent) {
    if (_blockForRequiredLocation()) return;
    if (_l3LocationCount >= _OriginLocationsEditorPageState._maxLocations) {
      _showError(
        'You can add up to '
        '${_OriginLocationsEditorPageState._maxLocations} L3 locations.',
      );
      return;
    }
    final form = _newL2Location(parent);
    _inlineNameController.clear();
    _setLocationEditorState(() {
      parent.children.add(form);
      _requiredFlowL1Id = null;
      _requiredInlineLocationId = form.locationId;
      _inlineEditingLocationId = form.locationId;
    });
    _requestInlineNameFocus();
  }

  void _addL3Location(_L2LocationForm parent) {
    if (_blockForRequiredLocation()) return;
    if (_l3LocationCount >= _OriginLocationsEditorPageState._maxLocations) {
      _showError(
        "You've used all "
        '${_OriginLocationsEditorPageState._maxLocations} rooms. '
        'Delete one to add another.',
      );
      return;
    }
    for (int l1Index = 0; l1Index < _treeForms.length; l1Index++) {
      final l1 = _treeForms[l1Index];
      final l2Index = l1.children.indexOf(parent);
      if (l2Index < 0) continue;
      final form = _newL3Location(parent);
      unawaited(
        _showL3EditorSheet(
          _L3LocationTarget(
            parent: parent,
            form: form,
            l1Index: l1Index,
            l2Index: l2Index,
            l3Index: parent.children.length,
          ),
          isNew: true,
        ),
      );
      return;
    }
  }

  void _removeL1Location(_L1LocationForm form) {
    if (_treeForms.length == 1) {
      _showError('At least one L1 location is required.');
      return;
    }
    final restoresRootAdd =
        _requiredFlowL1Id == form.locationId ||
        _requiredInlineLocationId == form.locationId;
    if (restoresRootAdd) _markRootAddL1ForReveal();
    _inlineNameFocusNode.unfocus();
    _setLocationEditorState(() {
      if (_requiredInlineLocationId == form.locationId ||
          _requiredFlowL1Id == form.locationId) {
        _requiredInlineLocationId = null;
        _requiredFlowL1Id = null;
        _inlineEditingLocationId = null;
      }
      _treeForms.remove(form);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => form.dispose());
  }

  void _removeL2Location(_L1LocationForm parent, _L2LocationForm form) {
    if (parent.children.length == 1) {
      _showError(_l1NeedsL2Message(parent));
      return;
    }
    _inlineNameFocusNode.unfocus();
    _setLocationEditorState(() {
      if (_requiredInlineLocationId == form.locationId) {
        _requiredInlineLocationId = null;
        _requiredFlowL1Id = null;
        _inlineEditingLocationId = null;
      }
      parent.children.remove(form);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => form.dispose());
  }

  void _removeL3Location(_L2LocationForm parent, _LocationForm form) {
    if (parent.children.length == 1) {
      _showError(_l2NeedsL3Message(parent));
      return;
    }
    _setLocationEditorState(() {
      parent.children.remove(form);
      form.dispose();
    });
    _onFormChanged();
  }

  void _addLocation() {
    if (_forms.length >= _OriginLocationsEditorPageState._maxLocations) {
      _showError(
        'You can add up to '
        '${_OriginLocationsEditorPageState._maxLocations} locations.',
      );
      return;
    }
    _setLocationEditorState(() {
      _forms.add(_LocationForm.empty(locationId: _generateUniqueLocationId()));
    });
    _onFormChanged();
  }

  void _requestRemoveLocation(int index) {
    _removeLocation(index);
  }

  void _removeLocation(int index) {
    if (_forms.length <= 1) {
      _forms[index].clear();
    } else {
      final form = _forms.removeAt(index);
      form.dispose();
    }
    _onFormChanged();
  }

  void _onFormChanged() {
    _setLocationEditorState(() {});
  }

  void _setMode(_LocationsEditorMode mode) {
    if (_mode == mode) return;
    if (mode == _LocationsEditorMode.preview && _blockForRequiredLocation()) {
      return;
    }
    _inlineEditingLocationId = null;
    FocusManager.instance.primaryFocus?.unfocus();
    _setLocationEditorState(() => _mode = mode);
  }

  Iterable<_LocationForm> get _allL3Forms sync* {
    if (!widget.useLocationTree) {
      yield* _forms;
      return;
    }
    for (final l1 in _treeForms) {
      for (final l2 in l1.children) {
        yield* l2.children;
      }
    }
  }

  void _removeCharacterFromLocation(int locationIndex, String charId) {
    _removeCharacterFromForm(_forms[locationIndex], charId);
  }

  void _removeCharacterFromForm(_LocationForm form, String charId) {
    _setLocationEditorState(() {
      form.selectedCharacterIds = form.selectedCharacterIds
          .where((item) => item != charId)
          .toList(growable: true);
    });
    _onFormChanged();
  }

  List<LocationDraft> _snapshotLocations() {
    final validCharacterIds = _finalCharacters
        .map((item) => item.charId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (widget.useLocationTree) {
      return [
        for (final l1 in _treeForms) ...[
          LocationDraft(
            locationId: l1.locationId,
            level: 1,
            name: l1.name.text.trim(),
          ),
          for (final l2 in l1.children) ...[
            LocationDraft(
              locationId: l2.locationId,
              parentLocationId: l1.locationId,
              level: 2,
              name: l2.name.text.trim(),
            ),
            for (final form in l2.children)
              LocationDraft(
                locationId: form.locationId,
                parentLocationId: l2.locationId,
                level: 3,
                imageUrl: form.imageUrl.text.trim(),
                name: form.name.text.trim(),
                description: form.description.text.trim(),
                initialCharacterIds: form.selectedCharacterIds
                    .where(validCharacterIds.contains)
                    .toList(growable: false),
              ),
          ],
        ],
      ];
    }
    return _forms
        .map(
          (form) => LocationDraft(
            locationId: form.locationId,
            parentLocationId: form.parentLocationId,
            level: form.level,
            imageUrl: form.imageUrl.text.trim(),
            name: normalizeGenesisUgcTextForDisplay(form.name.text),
            description: normalizeGenesisUgcTextForDisplay(
              form.description.text,
            ),
            initialCharacterIds: form.selectedCharacterIds
                .where(validCharacterIds.contains)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _openCharacterPicker(int locationIndex) async {
    await _openCharacterPickerForForm(_forms[locationIndex]);
  }

  Future<void> _openCharacterPickerForForm(
    _LocationForm form, {
    bool notifyFormChanged = true,
  }) async {
    final characters = await widget.repository.loadSavedCharacters();
    if (!mounted) return;
    _setLocationEditorState(() => _finalCharacters = characters);
    if (characters.isEmpty) {
      _showError('There are no characters yet.');
      return;
    }

    final blockedIds = _boundCharacterIdsExceptForm(form);
    final currentIds = form.selectedCharacterIds.toSet();
    final availableCharacters = characters
        .where((item) {
          final charId = item.charId.trim();
          if (charId.isEmpty) return false;
          return currentIds.contains(charId) || !blockedIds.contains(charId);
        })
        .toList(growable: false);

    if (availableCharacters.isEmpty) {
      _showError('There are no available characters.');
      return;
    }

    final selectedIds = await showGenesisModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GenesisDarkTheme(
          child: CreateFormTheme(
            child: _CharacterPickerSheet(
              characters: availableCharacters,
              initialSelectedIds: currentIds,
            ),
          ),
        );
      },
    );
    if (selectedIds == null || !mounted) return;
    _setLocationEditorState(() {
      form.selectedCharacterIds = selectedIds;
    });
    if (notifyFormChanged) _onFormChanged();
  }

  Set<String> _boundCharacterIdsExceptForm(_LocationForm excludedForm) {
    final ids = <String>{};
    for (final form in _allL3Forms) {
      if (identical(form, excludedForm)) continue;
      ids.addAll(form.selectedCharacterIds);
    }
    return ids;
  }
}

class _L1LocationForm {
  _L1LocationForm({
    required this.locationId,
    required this.name,
    required this.children,
  });

  final String locationId;
  final TextEditingController name;
  final List<_L2LocationForm> children;

  void dispose() {
    name.dispose();
    for (final child in children) {
      child.dispose();
    }
  }
}

class _L2LocationForm {
  _L2LocationForm({
    required this.locationId,
    required this.name,
    required this.children,
  });

  final String locationId;
  final TextEditingController name;
  final List<_LocationForm> children;

  void dispose() {
    name.dispose();
    for (final child in children) {
      child.dispose();
    }
  }
}
