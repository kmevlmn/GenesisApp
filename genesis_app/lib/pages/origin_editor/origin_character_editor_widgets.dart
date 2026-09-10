part of 'origin_editor_pages.dart';

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.index,
    required this.form,
    required this.nextFocusNode,
    required this.onChanged,
    required this.onRecommendationChanged,
    required this.onDelete,
  });

  final int index;
  final OriginCharacterForm form;
  final FocusNode? nextFocusNode;
  final VoidCallback onChanged;
  final ValueChanged<bool> onRecommendationChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return CreateFormCard(
      title: 'Character $index',
      onDelete: onDelete,
      showBorder: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OriginCharacterFormFields(
            form: form,
            onChanged: onChanged,
            showFieldNotes: true,
            labelFontWeight: FontWeight.w600,
            nextFocusNode: nextFocusNode,
            nameSupportLeading: _BestRoleSelector(
              form: form,
              onChanged: onRecommendationChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _BestRoleSelector extends StatelessWidget {
  const _BestRoleSelector({required this.form, required this.onChanged});

  final OriginCharacterForm form;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('origin-character-best-role-hit-target-${form.charId}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!form.isRecommended),
      child: SizedBox(
        height: 32,
        child: Align(
          alignment: Alignment.topLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OriginRoleSelectionMark(
                key: ValueKey('origin-character-recommended-${form.charId}'),
                selected: form.isRecommended,
                semanticLabel: 'Creator suggests this role for the user',
                style: OriginRoleSelectionMarkStyle.star,
                starUnselectedColor: GenesisColors.darkTextTertiary,
              ),
              const SizedBox(width: 6),
              const Text(
                'Suggest',
                style: TextStyle(
                  color: GenesisColors.darkTextSecondary,
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
