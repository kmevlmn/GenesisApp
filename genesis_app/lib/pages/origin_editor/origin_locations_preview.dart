part of 'origin_editor_pages.dart';

extension _OriginLocationsPreview on _OriginLocationsEditorPageState {
  void _markRootAddL1ForReveal() {
    _revealRootAddL1AfterKeyboard = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealRootAddL1IfReady();
    });
  }

  void _revealRootAddL1IfReady() {
    if (!mounted || !_revealRootAddL1AfterKeyboard || _hasKeyboardViewInset()) {
      return;
    }
    final targetContext = _rootAddL1VisibilityKey.currentContext;
    if (targetContext == null) return;
    _revealRootAddL1AfterKeyboard = false;
    unawaited(
      Scrollable.ensureVisible(
        targetContext,
        duration: Duration.zero,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ),
    );
  }

  List<WorldMapLocationNode> _previewLocationNodes() {
    if (!widget.useLocationTree) return const <WorldMapLocationNode>[];
    final charactersById = <String, CharacterDraft>{
      for (final character in _finalCharacters)
        if (character.charId.trim().isNotEmpty)
          character.charId.trim(): character,
    };
    return <WorldMapLocationNode>[
      for (final l1 in _treeForms)
        WorldMapLocationNode(
          id: l1.locationId,
          point: _previewPoint(
            id: l1.locationId,
            name: _previewName(l1.name, 'L1 Location'),
            depth: 0,
            isLeaf: false,
          ),
          children: <WorldMapLocationNode>[
            for (final l2 in l1.children)
              WorldMapLocationNode(
                id: l2.locationId,
                point: _previewPoint(
                  id: l2.locationId,
                  name: _previewName(l2.name, 'L2 Location'),
                  depth: 1,
                  isLeaf: false,
                ),
                children: <WorldMapLocationNode>[
                  for (final l3 in l2.children)
                    WorldMapLocationNode(
                      id: l3.locationId,
                      point: _previewPoint(
                        id: l3.locationId,
                        name: _previewName(l3.name, 'L3 Location'),
                        depth: 2,
                        imageUrl: l3.imageUrl.text.trim(),
                        imageBytes: l3.previewImageBytes,
                        description: l3.description.text.trim(),
                        users: _previewUsers(l3, charactersById),
                      ),
                    ),
                ],
              ),
          ],
        ),
    ];
  }

  List<WorldPoint> _previewFlatPoints() {
    if (widget.useLocationTree) return const <WorldPoint>[];
    final charactersById = <String, CharacterDraft>{
      for (final character in _finalCharacters)
        if (character.charId.trim().isNotEmpty)
          character.charId.trim(): character,
    };
    return <WorldPoint>[
      for (final form in _forms)
        _previewPoint(
          id: form.locationId,
          name: _previewName(form.name, 'Location'),
          depth: form.level > 0 ? form.level - 1 : 0,
          imageUrl: form.imageUrl.text.trim(),
          imageBytes: form.previewImageBytes,
          description: form.description.text.trim(),
          users: _previewUsers(form, charactersById),
        ),
    ];
  }

  WorldPoint _previewPoint({
    required String id,
    required String name,
    required int depth,
    String imageUrl = '',
    Uint8List? imageBytes,
    String description = '',
    List<UserAvatar> users = const <UserAvatar>[],
    bool isLeaf = true,
  }) {
    return WorldPoint(
      id: id,
      sceneId: id,
      pointId: id,
      name: name,
      type: WorldPointType.portal,
      position: Offset.zero,
      users: users,
      iconUrl: imageUrl,
      iconBytes: imageBytes,
      description: description,
      locationDescription: description,
      depth: depth,
      isLeafLocation: isLeaf,
    );
  }

  List<UserAvatar> _previewUsers(
    _LocationForm form,
    Map<String, CharacterDraft> charactersById,
  ) {
    return form.selectedCharacterIds
        .map((id) => charactersById[id.trim()])
        .whereType<CharacterDraft>()
        .map((character) {
          final name = character.name.trim();
          return UserAvatar(
            name,
            id: character.charId.trim(),
            name: name,
            avatarUrl: character.avatarUrl.trim(),
          );
        })
        .toList(growable: false);
  }

  String _previewName(TextEditingController controller, String fallback) {
    final name = controller.text.trim();
    return name.isEmpty ? fallback : name;
  }

  Widget _buildLocationsList({required bool editable}) {
    final list = WorldLocationList(
      key: ValueKey<String>(
        editable ? 'locations-edit-list' : 'locations-preview-list',
      ),
      points: _previewFlatPoints(),
      locationNodes: _previewLocationNodes(),
      enableOuterScrollHandoff: false,
      physics: const ClampingScrollPhysics(),
      padding: editable
          ? const EdgeInsets.fromLTRB(12, 8, 12, 32)
          : const EdgeInsets.fromLTRB(12, 14, 12, 32),
      onNodeHeaderTap: editable ? _beginInlineNameEdit : null,
      nodeHeaderBuilder: editable ? _buildInlineNodeHeader : null,
      nodeFooterBuilder: editable ? _buildNodeFooter : null,
      onPointTap: editable ? _openLeafEditor : null,
      header: editable ? _buildEditTreeHeader() : null,
      footer: editable ? _buildTreeRootFooter() : null,
    );
    if (!editable) return list;
    return Builder(
      builder: (context) => Theme(
        key: const ValueKey<String>('locations-edit-no-tap-effects'),
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
        ),
        child: list,
      ),
    );
  }

  Widget _buildEditTreeHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LocationEditorNote(
          key: const ValueKey<String>('locations-statistics-note'),
          text: _OriginLocationsEditorPageState._statisticsNote,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPreviewBody() {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(child: _buildLocationsList(editable: false)),
          _buildBottomSaveAction(),
        ],
      ),
    );
  }

  Widget _buildEditBody() {
    if (!widget.useLocationTree) {
      return CreateKeyboardDismissArea(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _editorChildren(),
                  ),
                ),
              ),
              _buildBottomSaveAction(),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(child: _buildLocationsList(editable: true)),
          _buildBottomSaveAction(onShown: _revealRootAddL1IfReady),
        ],
      ),
    );
  }
}
