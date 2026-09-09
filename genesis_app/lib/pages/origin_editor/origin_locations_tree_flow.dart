part of 'origin_editor_pages.dart';

extension _OriginLocationsTreeFlow on _OriginLocationsEditorPageState {
  void _beginInlineNameEdit(WorldPoint point) {
    if (_mode != _LocationsEditorMode.edit || point.isLeafLocation) return;
    if (_blockForRequiredLocation(targetLocationId: point.id)) return;
    _inlineNameController.text =
        _inlineLocationNameController(point.id)?.text ?? '';
    _setLocationEditorState(() => _inlineEditingLocationId = point.id);
    _requestInlineNameFocus();
  }

  void _finishInlineNameEdit() {
    final editingId = _inlineEditingLocationId;
    if (editingId == null) return;
    final name = _inlineNameController.text.trim();
    if (name.isEmpty) {
      _showRequiredLocationMessage();
      _requestInlineNameFocus();
      return;
    }

    for (final l1 in _treeForms) {
      if (l1.locationId == editingId) {
        l1.name.text = name;
        if (_requiredInlineLocationId == editingId) {
          if (l1.children.isEmpty) {
            final l2 = _newL2Location(l1);
            l1.children.add(l2);
          }
          _L2LocationForm? requiredL2;
          for (final l2 in l1.children) {
            if (l2.name.text.trim().isEmpty) {
              requiredL2 = l2;
              break;
            }
          }
          if (requiredL2 == null) {
            _inlineNameFocusNode.unfocus();
          } else {
            _transferInlineNameInput(requiredL2.name.text);
          }
          _setLocationEditorState(() {
            _requiredInlineLocationId = requiredL2?.locationId;
            _inlineEditingLocationId = requiredL2?.locationId;
            if (requiredL2 == null) _requiredFlowL1Id = null;
          });
          if (requiredL2 == null) {
            _inlineNameFocusNode.unfocus();
          }
          return;
        }
        _inlineNameFocusNode.unfocus();
        _setLocationEditorState(() => _inlineEditingLocationId = null);
        return;
      }

      for (final l2 in l1.children) {
        if (l2.locationId != editingId) continue;
        l2.name.text = name;
        _inlineNameFocusNode.unfocus();
        _setLocationEditorState(() {
          _requiredInlineLocationId = null;
          _requiredFlowL1Id = null;
          _inlineEditingLocationId = null;
        });
        return;
      }
    }
  }

  void _cancelInlineEditForOutsideTap() {
    final retainRequiredL2 =
        _requiredFlowL1Id != null &&
        _requiredInlineLocationId != _requiredFlowL1Id;
    if (!_inlineNameFocusNode.hasFocus &&
        _requiredInlineLocationId != null &&
        (!_hasCompleteTree || retainRequiredL2)) {
      return;
    }
    _suppressRequiredActionForCurrentTap = true;

    final editingId = _inlineEditingLocationId;
    if (editingId == null) return;
    _inlineNameFocusNode.unfocus();

    final requiredId = _requiredInlineLocationId;
    if (requiredId == null) {
      _setLocationEditorState(() => _inlineEditingLocationId = null);
      return;
    }

    // Keep the only, guided L1/L2 input visible until the first tree exists.
    if (!_hasCompleteTree) return;

    for (final l1 in _treeForms) {
      if (l1.locationId == editingId) {
        _markRootAddL1ForReveal();
        _setLocationEditorState(() {
          _inlineEditingLocationId = null;
          _requiredInlineLocationId = null;
          _requiredFlowL1Id = null;
          _treeForms.remove(l1);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          l1.dispose();
        });
        return;
      }
      for (final l2 in l1.children) {
        if (l2.locationId != editingId) continue;
        final cancelWholeL1 = _requiredFlowL1Id == l1.locationId;
        if (cancelWholeL1) return;
        _setLocationEditorState(() {
          _inlineEditingLocationId = null;
          _requiredInlineLocationId = null;
          _requiredFlowL1Id = null;
          l1.children.remove(l2);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          l2.dispose();
        });
        return;
      }
    }
  }

  Future<void> _confirmAndRemoveLocationBranch({
    required int level,
    required String name,
    required VoidCallback remove,
  }) async {
    _inlineNameFocusNode.unfocus();
    final displayName = name.trim().isEmpty ? 'location' : name.trim();
    final subtitle = level == 1
        ? 'Every L2 and L3 locations inside it will be removed too.'
        : 'Every L3 locations inside it will be removed too.';
    final confirmed = await showGenesisActionBox<bool>(
      context: context,
      title: 'Delete "$displayName"',
      titleContent: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: GenesisColors.darkTextSecondary,
          fontSize: 13,
          height: 1.3,
          fontWeight: FontWeight.w400,
        ),
      ),
      titleHeight: 104,
      actions: const [
        GenesisActionBoxAction<bool>(label: 'Delete', value: true),
      ],
      cancelLabel: 'Cancel',
    );
    if (confirmed != true || !mounted) return;
    remove();
  }

  Future<bool> _confirmOpeningLocationDeletion({
    required String locationId,
    required String name,
  }) async {
    if (locationId.trim() != _openingLocationId) return true;
    final displayName = name.trim().isEmpty ? 'location' : name.trim();
    final confirmed = await showGenesisActionBox<bool>(
      context: context,
      title: 'Delete "$displayName"',
      titleContent: const Text(
        'This is the Opening location. Deleting it will also clear the Opening.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: GenesisColors.darkTextSecondary,
          fontSize: 13,
          height: 1.3,
          fontWeight: FontWeight.w400,
        ),
      ),
      titleHeight: 120,
      actions: const [
        GenesisActionBoxAction<bool>(label: 'Delete', value: true),
      ],
      cancelLabel: 'Cancel',
    );
    return confirmed == true;
  }

  void _removeLocationBranchFromEditor({
    required bool hasChildren,
    required int level,
    required String name,
    required VoidCallback remove,
  }) {
    if (!hasChildren) {
      remove();
      return;
    }
    unawaited(
      _confirmAndRemoveLocationBranch(level: level, name: name, remove: remove),
    );
  }

  void _releaseInlineOutsideTapSuppression() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressRequiredActionForCurrentTap = false;
    });
  }

  bool _blockForRequiredLocation({String? targetLocationId}) {
    if (_suppressRequiredActionForCurrentTap) {
      _suppressRequiredActionForCurrentTap = false;
      return true;
    }
    final requiredId = _requiredInlineLocationId;
    if (requiredId == null || requiredId == targetLocationId) return false;
    _showRequiredLocationMessage();
    _requestInlineNameFocus();
    return true;
  }

  void _showRequiredLocationMessage() {
    _showError(
      _OriginLocationsEditorPageState._completeRequiredLocationMessage,
    );
  }

  void _requestInlineNameFocus() {
    final editingId = _inlineEditingLocationId;
    if (editingId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _inlineEditingLocationId != editingId) return;
      _inlineNameFocusNode.requestFocus();
    });
  }

  void _transferInlineNameInput(String text) {
    final previousFocusNode = _inlineNameFocusNode;
    final nextFocusNode = _nextInlineNameFocusNode;
    final previousController = _inlineNameController;
    final nextController = _nextInlineNameController;
    nextController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    nextFocusNode.requestFocus();
    _inlineNameFocusNode = nextFocusNode;
    _nextInlineNameFocusNode = previousFocusNode;
    _inlineNameController = nextController;
    _nextInlineNameController = previousController;
  }

  Widget? _buildInlineNodeHeader(
    BuildContext context,
    WorldPoint point,
    int level,
  ) {
    if (point.isLeafLocation) return null;
    final displayLocationId = _displayLocationId(point.id);
    if (_inlineEditingLocationId != point.id) {
      return _InlineTreeLocationPreviewHeader(
        key: ValueKey<String>('world-location-node-header-$displayLocationId'),
        name: point.name,
        level: level,
        onTap: () => _beginInlineNameEdit(point),
      );
    }
    for (int l1Index = 0; l1Index < _treeForms.length; l1Index++) {
      final l1 = _treeForms[l1Index];
      if (l1.locationId == point.id) {
        return _InlineTreeLocationNameEditor(
          key: ValueKey<String>('locations-inline-name-$displayLocationId'),
          testKey: ValueKey<String>(
            'locations-inline-name-content-$displayLocationId',
          ),
          fieldKey: ValueKey<String>(
            'locations-inline-name-field-$displayLocationId',
          ),
          controller: _inlineNameController,
          focusNode: _inlineNameFocusNode,
          level: level,
          hintText: 'L1 Location · Region *',
          note: _OriginLocationsEditorPageState._l1NameNote,
          onChanged: _onFormChanged,
          onEditingComplete: _finishInlineNameEdit,
          onTapOutside: _cancelInlineEditForOutsideTap,
          saveButtonKey: ValueKey<String>(
            'locations-inline-save-$displayLocationId',
          ),
          onDelete: () => _removeLocationBranchFromEditor(
            hasChildren: l1.children.isNotEmpty,
            level: 1,
            name: _inlineNameController.text,
            remove: () => _removeL1Location(l1),
          ),
          deleteEnabled: _treeForms.length > 1,
          onDeleteDisabled: () =>
              _showError('At least one L1 location is required.'),
        );
      }
      for (int l2Index = 0; l2Index < l1.children.length; l2Index++) {
        final l2 = l1.children[l2Index];
        if (l2.locationId != point.id) continue;
        final deleteWholeL1 = l1.children.length == 1;
        return _InlineTreeLocationNameEditor(
          key: ValueKey<String>('locations-inline-name-$displayLocationId'),
          testKey: ValueKey<String>(
            'locations-inline-name-content-$displayLocationId',
          ),
          fieldKey: ValueKey<String>(
            'locations-inline-name-field-$displayLocationId',
          ),
          controller: _inlineNameController,
          focusNode: _inlineNameFocusNode,
          level: level,
          hintText: 'L2 Location · Building *',
          note: _OriginLocationsEditorPageState._l2NameNote,
          onChanged: _onFormChanged,
          onEditingComplete: _finishInlineNameEdit,
          onTapOutside: _cancelInlineEditForOutsideTap,
          saveButtonKey: ValueKey<String>(
            'locations-inline-save-$displayLocationId',
          ),
          onDelete: () => _removeLocationBranchFromEditor(
            hasChildren: l2.children.isNotEmpty,
            level: deleteWholeL1 ? 1 : 2,
            name: deleteWholeL1 ? l1.name.text : _inlineNameController.text,
            remove: () => deleteWholeL1
                ? _removeL1Location(l1)
                : _removeL2Location(l1, l2),
          ),
          deleteEnabled: !deleteWholeL1 || _treeForms.length > 1,
          onDeleteDisabled: () =>
              _showError('At least one L1 location is required.'),
        );
      }
    }
    return null;
  }

  Widget? _buildNodeFooter(BuildContext context, WorldPoint point, int level) {
    for (int l1Index = 0; l1Index < _treeForms.length; l1Index++) {
      final l1 = _treeForms[l1Index];
      if (l1.locationId == point.id) {
        final isAddingL2Here = l1.children.any(
          (l2) => l2.locationId == _requiredInlineLocationId,
        );
        if (isAddingL2Here ||
            l1.name.text.trim().isEmpty ||
            !_hasCompleteTree) {
          return null;
        }
        return Padding(
          padding: EdgeInsets.fromLTRB((level + 1) * 15.0, 0, 0, 12),
          child: _LocationTreeAddButton(
            key: ValueKey<String>(
              'create-add-l2-${_displayLocationId(l1.locationId)}',
            ),
            label: '+ L2',
            onTap: () => _addL2Location(l1),
          ),
        );
      }
      for (int l2Index = 0; l2Index < l1.children.length; l2Index++) {
        final l2 = l1.children[l2Index];
        if (l2.locationId != point.id) continue;
        if (l1.name.text.trim().isEmpty || l2.name.text.trim().isEmpty) {
          return null;
        }
        return Padding(
          padding: EdgeInsets.fromLTRB((level + 1) * 15.0, 5, 0, 8),
          child: _LocationTreeAddL3Button(
            buttonKey: ValueKey<String>(
              'create-add-l3-${_displayLocationId(l2.locationId)}',
            ),
            isRequired: !_l2HasSavedL3(l2),
            onTap: () => _addL3Location(l2),
          ),
        );
      }
    }
    return null;
  }

  Widget _buildTreeRootFooter() {
    if (_requiredFlowL1Id != null || !_hasCompleteTree) {
      return const SizedBox.shrink();
    }
    return Padding(
      key: _rootAddL1VisibilityKey,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
      child: _LocationTreeAddButton(
        key: const ValueKey<String>('create-add-l1-location'),
        label: '+ L1',
        onTap: _addL1Location,
      ),
    );
  }

  void _openLeafEditor(WorldPoint point) {
    if (_mode != _LocationsEditorMode.edit) return;
    if (_blockForRequiredLocation(targetLocationId: point.id)) return;
    for (int l1Index = 0; l1Index < _treeForms.length; l1Index++) {
      final l1 = _treeForms[l1Index];
      for (int l2Index = 0; l2Index < l1.children.length; l2Index++) {
        final l2 = l1.children[l2Index];
        for (int l3Index = 0; l3Index < l2.children.length; l3Index++) {
          final form = l2.children[l3Index];
          if (form.locationId != point.id) continue;
          unawaited(
            _showL3EditorSheet(
              _L3LocationTarget(
                parent: l2,
                form: form,
                l1Index: l1Index,
                l2Index: l2Index,
                l3Index: l3Index,
              ),
            ),
          );
          return;
        }
      }
    }
  }

  Future<void> _showL3EditorSheet(
    _L3LocationTarget target, {
    bool isNew = false,
  }) async {
    if (_inlineEditingLocationId != null) {
      _setLocationEditorState(() => _inlineEditingLocationId = null);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final draftForm = _LocationForm.copyOf(target.form);
    final sheetHeight =
        MediaQuery.sizeOf(context).height * 0.75 -
        MediaQuery.viewPaddingOf(context).bottom;
    var draftOwnedBySheet = false;
    try {
      final action = await showGenesisModalBottomSheet<_L3EditorSheetAction>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          draftOwnedBySheet = true;
          return _LocationFormOwner(
            form: draftForm,
            child: GenesisDarkTheme(
              child: CreateFormTheme(
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    void refreshSheet() => setSheetState(() {});

                    final deleteEnabled = target.parent.children.length > 1;
                    final selectedCharacterIds = draftForm.selectedCharacterIds
                        .toSet();
                    final blockedCharacterIds = _boundCharacterIdsExceptForm(
                      target.form,
                    );
                    final availableCharacters = _finalCharacters
                        .where((character) {
                          final characterId = character.charId.trim();
                          return characterId.isNotEmpty &&
                              character.name.trim().isNotEmpty &&
                              !selectedCharacterIds.contains(characterId) &&
                              !blockedCharacterIds.contains(characterId);
                        })
                        .toList(growable: false);
                    return GenesisBottomSheetPanel(
                      key: const ValueKey<String>('locations-l3-editor-sheet'),
                      title: isNew ? 'Add L3 Location' : 'Edit L3 Location',
                      height: sheetHeight,
                      maintainBottomViewPadding: true,
                      trailing: GenesisBottomSheetCloseButton(
                        buttonKey: const ValueKey<String>(
                          'locations-l3-editor-close',
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              child: _LocationCard(
                                key: ValueKey<String>(
                                  'locations-l3-sheet-${target.form.locationId}',
                                ),
                                index: target.l3Index + 1,
                                showHeader: false,
                                nameFieldLabel: 'Name *',
                                nameFieldHintText: '',
                                nameFieldNote:
                                    _OriginLocationsEditorPageState._l3NameNote,
                                fieldLabelFontWeight: FontWeight.w600,
                                form: draftForm,
                                nextFocusNode: null,
                                characters: _finalCharacters,
                                onChanged: refreshSheet,
                                onPickCharacters: () {
                                  // L3 sheets use the inline Available to select
                                  // list instead of opening a second sheet.
                                },
                                availableCharacters: availableCharacters,
                                onAddCharacter: (characterId) {
                                  if (draftForm.selectedCharacterIds.contains(
                                    characterId,
                                  )) {
                                    return;
                                  }
                                  draftForm.selectedCharacterIds = [
                                    ...draftForm.selectedCharacterIds,
                                    characterId,
                                  ];
                                  setSheetState(() {});
                                },
                                onRemoveCharacter: (charId) {
                                  draftForm.selectedCharacterIds = draftForm
                                      .selectedCharacterIds
                                      .where((item) => item != charId)
                                      .toList(growable: true);
                                  setSheetState(() {});
                                },
                                onDelete: () {},
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final preferredSaveWidth =
                                  _primaryActionButtonWidth(context);
                              final reservedActionWidth = isNew
                                  ? 0.0
                                  : GenesisPrimaryButton.defaultHeight + 12;
                              final availableSaveWidth =
                                  constraints.maxWidth - reservedActionWidth;
                              final saveWidth =
                                  preferredSaveWidth <= availableSaveWidth
                                  ? preferredSaveWidth
                                  : availableSaveWidth;
                              return Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isNew) ...[
                                      GenesisDeleteButton(
                                        buttonKey: const ValueKey<String>(
                                          'locations-l3-editor-delete',
                                        ),
                                        size:
                                            GenesisPrimaryButton.defaultHeight,
                                        iconSize: 20,
                                        onPressed: () async {
                                          final shouldDelete =
                                              await _confirmOpeningLocationDeletion(
                                                locationId:
                                                    target.form.locationId,
                                                name: draftForm.name.text,
                                              );
                                          if (!context.mounted ||
                                              !shouldDelete) {
                                            return;
                                          }
                                          Navigator.of(
                                            context,
                                          ).pop(_L3EditorSheetAction.delete);
                                        },
                                        enabled: deleteEnabled,
                                        onDisabledPressed: () => _showError(
                                          _l2NeedsL3Message(target.parent),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    GenesisPrimaryButton(
                                      key: const ValueKey<String>(
                                        'locations-l3-editor-save',
                                      ),
                                      label: 'Save',
                                      backgroundColor: GenesisColors.redPrimary,
                                      foregroundColor:
                                          GenesisColors.darkTextPrimary,
                                      disabledBackgroundColor:
                                          GenesisColors.redSecondary,
                                      disabledForegroundColor:
                                          GenesisColors.darkTextPrimary,
                                      width: saveWidth,
                                      onPressed:
                                          draftForm.name.text.trim().isEmpty
                                          ? null
                                          : () => Navigator.of(
                                              context,
                                            ).pop(_L3EditorSheetAction.save),
                                      onDisabledPressed: () => _showError(
                                        'L3 location name is required.',
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
      if (!mounted) return;
      if (action == _L3EditorSheetAction.delete) {
        _removeL3Location(target.parent, target.form);
        return;
      }
      if (action == _L3EditorSheetAction.save) {
        target.form.applyValuesFrom(draftForm);
        if (isNew) {
          _setLocationEditorState(() {
            target.parent.children.add(target.form);
          });
        } else {
          _onFormChanged();
        }
      }
    } finally {
      if (isNew && !target.parent.children.contains(target.form)) {
        target.form.dispose();
      }
      if (!draftOwnedBySheet) {
        draftForm.dispose();
      }
    }
  }
}

class _L3LocationTarget {
  const _L3LocationTarget({
    required this.parent,
    required this.form,
    required this.l1Index,
    required this.l2Index,
    required this.l3Index,
  });

  final _L2LocationForm parent;
  final _LocationForm form;
  final int l1Index;
  final int l2Index;
  final int l3Index;
}

class _LocationFormOwner extends StatefulWidget {
  const _LocationFormOwner({required this.form, required this.child});

  final _LocationForm form;
  final Widget child;

  @override
  State<_LocationFormOwner> createState() => _LocationFormOwnerState();
}

class _LocationFormOwnerState extends State<_LocationFormOwner> {
  @override
  void dispose() {
    widget.form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
