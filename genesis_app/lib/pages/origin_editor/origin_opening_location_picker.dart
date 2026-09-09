part of 'origin_editor_pages.dart';

class _OpeningLocationPickerSheet extends StatefulWidget {
  const _OpeningLocationPickerSheet({
    required this.options,
    required this.initialSelection,
  });

  final List<_OpeningLocationOption> options;
  final _OpeningLocationOption? initialSelection;

  @override
  State<_OpeningLocationPickerSheet> createState() =>
      _OpeningLocationPickerSheetState();
}

class _OpeningLocationPickerSheetState
    extends State<_OpeningLocationPickerSheet> {
  _OpeningLocationOption? _selection;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
  }

  @override
  Widget build(BuildContext context) {
    return GenesisBottomSheetPanel(
      title: 'Select Location',
      height: MediaQuery.sizeOf(context).height * 0.58,
      trailing: GenesisBottomSheetCloseButton(
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: Column(
        children: [
          Expanded(
            child: widget.options.isEmpty
                ? const Center(
                    child: Text(
                      'No saved locations',
                      style: TextStyle(
                        color: GenesisColors.darkTextTertiary,
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: widget.options.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 1,
                      color: GenesisColors.darkFaintFill,
                    ),
                    itemBuilder: (context, index) {
                      final option = widget.options[index];
                      final selected = _selection?.id == option.id;
                      return _OpeningLocationOptionRow(
                        option: option,
                        selected: selected,
                        onTap: () => setState(() => _selection = option),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GenesisPrimaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                  backgroundColor: GenesisColors.darkFaintFill,
                  foregroundColor: GenesisColors.darkTextPrimary,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: GenesisPrimaryButton(
                  label: 'Select',
                  onPressed: _selection == null
                      ? null
                      : () => Navigator.of(context).pop(_selection),
                  onDisabledPressed: () =>
                      showGenesisToast(context, 'Select a location first.'),
                  backgroundColor: GenesisColors.redPrimary,
                  disabledBackgroundColor: GenesisColors.redSecondary,
                  disabledForegroundColor: GenesisColors.darkTextPrimary,
                  foregroundColor: GenesisColors.darkTextPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpeningLocationOptionRow extends StatelessWidget {
  const _OpeningLocationOptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _OpeningLocationOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey<String>('opening-location-option-${option.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.place_outlined,
                size: 16,
                color: GenesisColors.darkTextPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.location.name.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GenesisColors.darkTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (option.characterNames.isNotEmpty) ...[
                        SvgPicture.asset(
                          characterStatIconAsset,
                          width: 14,
                          height: 14,
                          colorFilter: const ColorFilter.mode(
                            GenesisColors.darkTextSecondary,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          option.characterNames.isEmpty
                              ? 'No initial character'
                              : option.characterNames,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: option.characterNames.isEmpty
                                ? GenesisColors.darkTextTertiary
                                : GenesisColors.darkTextSecondary,
                            fontSize: 13,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? GenesisColors.darkTextPrimary
                    : GenesisColors.darkFaintFill,
                border: Border.all(
                  color: selected
                      ? GenesisColors.darkTextPrimary
                      : GenesisColors.darkFaintFill,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check,
                      size: 15,
                      color: GenesisColors.darkBackground,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningLocationOption {
  const _OpeningLocationOption({
    required this.location,
    required this.characters,
  });

  final LocationDraft location;
  final List<CharacterDraft> characters;

  String get id {
    final locationId = location.locationId.trim();
    return locationId.isEmpty ? location.name.trim() : locationId;
  }

  String get characterNames => characters
      .map((character) => character.name.trim())
      .where((name) => name.isNotEmpty)
      .join(', ');
}
