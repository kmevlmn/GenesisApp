part of 'origin_editor_pages.dart';

extension _OriginLocationsEditorView on _OriginLocationsEditorPageState {
  List<Widget> _editorChildren() {
    return <Widget>[
      Align(
        alignment: Alignment.centerRight,
        child: Text(
          '${_forms.length}/'
          '${_OriginLocationsEditorPageState._maxLocations} (Added / Max)',
          style: const TextStyle(
            color: createFormText,
            fontSize: 14,
            height: 1.2,
          ),
        ),
      ),
      const SizedBox(height: 12),
      for (int i = 0; i < _forms.length; i++) ...[
        _LocationCard(
          index: i + 1,
          form: _forms[i],
          nextFocusNode: i + 1 < _forms.length
              ? _forms[i + 1].nameFocusNode
              : null,
          characters: _finalCharacters,
          onChanged: _onFormChanged,
          onPickCharacters: () => _openCharacterPicker(i),
          onRemoveCharacter: (charId) =>
              _removeCharacterFromLocation(i, charId),
          onDelete: () => _requestRemoveLocation(i),
        ),
        const SizedBox(height: 24),
      ],
      CreateAddButton(label: '+ Add Location', onTap: _addLocation),
      const SizedBox(height: 12),
    ];
  }
}

class _LocationsModeSwitch extends StatelessWidget {
  const _LocationsModeSwitch({required this.mode, required this.onChanged});

  final _LocationsEditorMode mode;
  final ValueChanged<_LocationsEditorMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final nextMode = mode == _LocationsEditorMode.edit
        ? _LocationsEditorMode.preview
        : _LocationsEditorMode.edit;
    final label = nextMode == _LocationsEditorMode.preview ? 'Preview' : 'Edit';
    final switchingToPreview = nextMode == _LocationsEditorMode.preview;
    return Semantics(
      key: const ValueKey<String>('locations-mode-switch'),
      button: true,
      label: 'Switch to $label mode',
      child: GestureDetector(
        key: ValueKey<String>(
          nextMode == _LocationsEditorMode.preview
              ? 'locations-mode-preview'
              : 'locations-mode-edit',
        ),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => onChanged(nextMode),
        onLongPress: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (switchingToPreview)
                const Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: Color(0xFF4B6192),
                )
              else
                Transform.scale(
                  // Match the previous edit icon within its existing layout slot.
                  scale: 32 / 37.36,
                  child: SvgPicture.asset(
                    editSquareIconAsset,
                    width: 16,
                    height: 16,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF4B6192),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF4B6192),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineTreeLocationNameEditor extends StatelessWidget {
  const _InlineTreeLocationNameEditor({
    super.key,
    required this.testKey,
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.level,
    required this.hintText,
    required this.note,
    required this.onChanged,
    required this.onEditingComplete,
    required this.onTapOutside,
    required this.saveButtonKey,
    required this.onDelete,
    required this.deleteEnabled,
    required this.onDeleteDisabled,
  });

  final Key testKey;
  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int level;
  final String hintText;
  final String note;
  final VoidCallback onChanged;
  final VoidCallback onEditingComplete;
  final VoidCallback onTapOutside;
  final Key saveButtonKey;
  final VoidCallback onDelete;
  final bool deleteEnabled;
  final VoidCallback onDeleteDisabled;

  @override
  Widget build(BuildContext context) {
    final prefixStyle = _inlineLocationNameStyle(level);
    final inputVerticalOffset = level == 0 ? -2.0 : -5.0;
    return KeyedSubtree(
      key: testKey,
      child: Padding(
        padding: EdgeInsets.only(left: level * 15.0),
        child: TextFieldTapRegion(
          // Android renders the selection toolbar in the EditableText tap
          // region. Keep Paste/Copy/Select from cancelling inline editing.
          groupId: EditableText,
          consumeOutsideTaps: false,
          onTapOutside: (_) => onTapOutside(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    offset: const Offset(0, 5),
                    child: Text('- ', style: prefixStyle),
                  ),
                  Expanded(
                    child: Transform.translate(
                      offset: Offset(0, inputVerticalOffset),
                      child: CreateTextFieldBlock(
                        key: fieldKey,
                        controller: controller,
                        focusNode: focusNode,
                        label: '',
                        hintText: hintText,
                        maxLength: 25,
                        maxLines: 1,
                        counterInside: true,
                        inputLineHeight: 1.2,
                        textInputAction: TextInputAction.done,
                        onEditingComplete: onEditingComplete,
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Transform.translate(
                    offset: Offset(0, level == 0 ? 2.5 : 1.5),
                    child: _InlineLocationSaveButton(
                      key: saveButtonKey,
                      onPressed: onEditingComplete,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Transform.translate(
                    offset: Offset(0, level == 0 ? 2.5 : 1.5),
                    child: GenesisDeleteButton(
                      onPressed: onDelete,
                      enabled: deleteEnabled,
                      onDisabledPressed: onDeleteDisabled,
                    ),
                  ),
                ],
              ),
              if (note.trim().isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    left: 14,
                    top: 4,
                    bottom: 8 + inputVerticalOffset,
                  ),
                  child: Transform.translate(
                    offset: Offset(0, inputVerticalOffset),
                    child: CreateFormNote(note: note.trim()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationEditorNote extends StatelessWidget {
  const _LocationEditorNote({super.key, required this.text});

  static final RegExp _levelLine = RegExp(
    r'^(L\d)\s*\u00b7\s*(\S+)\s{2,}(.+)$',
  );

  final String text;

  @override
  Widget build(BuildContext context) {
    final value = text.trim();
    if (value.isEmpty) return const SizedBox.shrink();
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final levels = <_LocationEditorNoteLevel>[];
    final rest = <String>[];
    String heading = '';
    for (final line in lines) {
      final match = _levelLine.firstMatch(line);
      if (match != null) {
        levels.add(
          _LocationEditorNoteLevel(
            badge: match.group(1)!,
            name: match.group(2)!,
            description: match.group(3)!.trim(),
          ),
        );
      } else if (heading.isEmpty && levels.isEmpty) {
        heading = line;
      } else {
        rest.add(line);
      }
    }
    if (levels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: CreateFormNote(note: value),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading.isNotEmpty)
            Text(
              heading,
              style: TextStyle(
                color: const Color(0xCC131215),
                fontSize: 11,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          for (final (index, level) in levels.indexed) ...[
            SizedBox(height: index == 0 ? 11 : 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 26,
                      height: 19,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F3F6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        level.badge,
                        style: TextStyle(
                          color: const Color(0xFF131215),
                          fontSize: 9.5,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        level.name,
                        style: TextStyle(
                          color: const Color(0xFF131215),
                          fontSize: 11,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 33),
                  child: Text(
                    level.description,
                    style: TextStyle(
                      color: const Color(0x99131215),
                      fontSize: 11,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ],
          for (final line in rest) ...[
            const SizedBox(height: 8),
            Text(
              line,
              style: TextStyle(
                color: const Color(0x99131215),
                fontSize: 11,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationEditorNoteLevel {
  const _LocationEditorNoteLevel({
    required this.badge,
    required this.name,
    required this.description,
  });

  final String badge;
  final String name;
  final String description;
}

class _InlineTreeLocationPreviewHeader extends StatelessWidget {
  const _InlineTreeLocationPreviewHeader({
    super.key,
    required this.name,
    required this.level,
    required this.onTap,
  });

  final String name;
  final int level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _inlineLocationNameStyle(level);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(level * 15.0, 5, 0, 5),
        child: Row(
          children: [
            Text('- ', style: style),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                name,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _inlineLocationNameStyle(int level) {
  if (level <= 0) {
    return const TextStyle(
      color: Colors.black,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
  }
  return const TextStyle(
    color: Colors.black,
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );
}

class _InlineLocationSaveButton extends StatelessWidget {
  const _InlineLocationSaveButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xE6F4F4F6),
              border: Border.all(color: const Color(0xFF888888)),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          IconButton(
            tooltip: 'Save',
            onPressed: onPressed,
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            icon: SvgPicture.asset(
              checkLineIconAsset,
              width: 14,
              height: 14,
              colorFilter: const ColorFilter.mode(
                createFormMuted,
                BlendMode.srcIn,
              ),
            ),
            splashRadius: 12,
          ),
        ],
      ),
    );
  }
}

class _LocationTreeAddButton extends StatelessWidget {
  const _LocationTreeAddButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CreateInlineAddButton(
      label: label,
      onTap: onTap,
      verticalPadding: 5,
    );
  }
}

class _LocationTreeAddL3Button extends StatelessWidget {
  const _LocationTreeAddL3Button({
    required this.buttonKey,
    required this.isRequired,
    required this.onTap,
  });

  final Key buttonKey;
  final bool isRequired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        key: buttonKey,
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: CustomPaint(
            painter: CreateDashedRRectPainter(
              color: createFormBorder,
              radius: 4,
              strokeWidth: 1.2,
            ),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add,
                    color: GenesisColors.createAdd,
                    size: 22,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isRequired ? 'L3 *' : 'L3',
                    style: const TextStyle(
                      color: GenesisColors.createAdd,
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
