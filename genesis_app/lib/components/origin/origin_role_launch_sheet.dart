import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/genesis_center_toast.dart';
import '../common/genesis_bottom_sheet_panel.dart';
import '../common/genesis_modal_routes.dart';
import '../world_details_shell.dart';
import 'origin_character_form.dart';
import 'origin_role_recommendation.dart';
import 'origin_role_selection_mark.dart';
import '../../network/models/origin.dart';
import '../../ui/components/genesis_character_avatar.dart';
import '../../ui/components/genesis_edge_swipe_back.dart';
import '../../ui/components/genesis_primary_button.dart';
import '../../ui/tokens/genesis_avatar_radii.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../pages/create/create_form_widgets.dart';

typedef OriginRoleProfileLoader = Future<OriginCustomRoleDraft?> Function();
typedef OriginRoleAvatarResolver = String Function(String avatar);

enum OriginRoleLaunchHandlerResult { failed, closeSheet, navigationHandled }

typedef OriginRoleLaunchHandler =
    Future<OriginRoleLaunchHandlerResult> Function(
      OriginRoleLaunchSelection selection,
    );

@immutable
class OriginCustomRoleDraft {
  const OriginCustomRoleDraft({
    this.avatarUrl = '',
    this.name = '',
    this.identity = '',
    this.personality = '',
    this.bio = '',
  });

  final String avatarUrl;
  final String name;
  final String identity;
  final String personality;
  final String bio;

  Map<String, dynamic> toPayload() {
    final payload = <String, dynamic>{
      'name': name.trim(),
      'identity': identity.trim(),
    };
    final resolvedAvatar = avatarUrl.trim();
    final resolvedPersonality = personality.trim();
    final resolvedBio = bio.trim();
    if (resolvedAvatar.isNotEmpty) payload['avatar'] = resolvedAvatar;
    if (resolvedPersonality.isNotEmpty) {
      payload['personality'] = resolvedPersonality;
    }
    if (resolvedBio.isNotEmpty) payload['bio'] = resolvedBio;
    return payload;
  }
}

@immutable
class OriginRoleLaunchSelection {
  const OriginRoleLaunchSelection._({
    this.presetCharacterId,
    this.customRole,
    this.initialLocationId,
  });

  factory OriginRoleLaunchSelection.preset(
    String characterId, {
    String? initialLocationId,
  }) {
    return OriginRoleLaunchSelection._(
      presetCharacterId: characterId,
      initialLocationId: initialLocationId,
    );
  }

  factory OriginRoleLaunchSelection.custom(OriginCustomRoleDraft role) {
    return OriginRoleLaunchSelection._(customRole: role);
  }

  final String? presetCharacterId;
  final OriginCustomRoleDraft? customRole;
  final String? initialLocationId;
}

Future<OriginRoleLaunchSelection?> showOriginRoleLaunchSheet({
  required BuildContext context,
  required List<OriginCharacter> characters,
  bool initialCustomTab = false,
  bool fillProfileOnOpen = false,
  OriginRoleProfileLoader? onFillFromProfile,
  OriginRoleAvatarResolver? resolveAvatarUrl,
  OriginRoleLaunchHandler? onLaunch,
  SystemUiOverlayStyle systemUiOverlayStyle = kGenesisLightSystemUiOverlayStyle,
}) {
  return WorldDetailsStatusBarOverride.runWithStyle(
    systemUiOverlayStyle,
    () => Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<OriginRoleLaunchSelection>(
        opaque: false,
        barrierDismissible: false,
        barrierColor: kGenesisSubtleModalBarrierColor,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: systemUiOverlayStyle,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              resizeToAvoidBottomInset: true,
              body: OriginRoleLaunchSheet(
                characters: characters,
                initialCustomTab: initialCustomTab,
                fillProfileOnOpen: fillProfileOnOpen,
                onFillFromProfile: onFillFromProfile,
                resolveAvatarUrl: resolveAvatarUrl,
                onLaunch: onLaunch,
              ),
            ),
          );
        },
      ),
    ),
  );
}

class OriginRoleLaunchSheet extends StatefulWidget {
  const OriginRoleLaunchSheet({
    super.key,
    required this.characters,
    this.initialCustomTab = false,
    this.fillProfileOnOpen = false,
    this.onFillFromProfile,
    this.resolveAvatarUrl,
    this.onLaunch,
  });

  final List<OriginCharacter> characters;
  final bool initialCustomTab;
  final bool fillProfileOnOpen;
  final OriginRoleProfileLoader? onFillFromProfile;
  final OriginRoleAvatarResolver? resolveAvatarUrl;
  final OriginRoleLaunchHandler? onLaunch;

  @override
  State<OriginRoleLaunchSheet> createState() => _OriginRoleLaunchSheetState();
}

class _OriginRoleLaunchSheetState extends State<OriginRoleLaunchSheet> {
  final OriginCharacterForm _customForm = OriginCharacterForm.empty(
    charId: 'custom_role',
  );
  int _tabIndex = 0;
  String _selectedPresetId = '';
  bool _fillingProfile = false;
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCustomTab) {
      _tabIndex = 1;
    }
    _customForm.addListener(_handleTextChanged);
    if (widget.initialCustomTab && widget.fillProfileOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fillFromProfile();
      });
    }
  }

  @override
  void didUpdateWidget(covariant OriginRoleLaunchSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.characters != widget.characters &&
        !_hasCharacterId(widget.characters, _selectedPresetId)) {
      _selectedPresetId = '';
    }
  }

  @override
  void dispose() {
    _customForm
      ..removeListener(_handleTextChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (mounted) setState(() {});
  }

  bool get _customReady {
    return _customForm.name.text.trim().isNotEmpty &&
        _customForm.identity.text.trim().isNotEmpty &&
        !_fillingProfile;
  }

  bool get _canLaunch {
    if (_tabIndex == 0) return _selectedPresetId.trim().isNotEmpty;
    return _customReady;
  }

  void _selectTab(int index) {
    if (_launching || _tabIndex == index) return;
    FocusScope.of(context).unfocus();
    setState(() => _tabIndex = index);
  }

  Future<void> _fillFromProfile() async {
    final loader = widget.onFillFromProfile;
    if (loader == null || _fillingProfile) return;
    FocusScope.of(context).unfocus();
    setState(() => _fillingProfile = true);
    try {
      final draft = await loader();
      if (!mounted || draft == null) return;
      final name = draft.name.trim();
      final identity = draft.identity.trim();
      final bio = draft.bio.trim();
      final avatar = draft.avatarUrl.trim();
      if (name.isNotEmpty) {
        _customForm.name.text = _limitProfileFill(
          name,
          originCharacterNameMaxLength,
        );
      }
      if (identity.isNotEmpty) {
        _customForm.identity.text = _limitProfileFill(
          identity,
          originCharacterIdentityMaxLength,
        );
      }
      if (bio.isNotEmpty) {
        _customForm.bio.text = _limitProfileFill(
          bio,
          originCharacterBioMaxLength,
        );
      }
      _customForm.avatarUrl.text = avatar;
    } finally {
      if (mounted) setState(() => _fillingProfile = false);
    }
  }

  Future<void> _submit() async {
    if (_launching) return;
    if (!_canLaunch) {
      showGenesisToast(
        context,
        _launchValidationMessage,
        brightness: Brightness.dark,
      );
      return;
    }
    final OriginRoleLaunchSelection selection;
    if (_tabIndex == 0) {
      selection = OriginRoleLaunchSelection.preset(_selectedPresetId.trim());
    } else {
      selection = OriginRoleLaunchSelection.custom(
        OriginCustomRoleDraft(
          avatarUrl: _customForm.avatarUrl.text,
          name: _customForm.name.text,
          identity: _customForm.identity.text,
          bio: _customForm.bio.text,
        ),
      );
    }

    final launch = widget.onLaunch;
    if (launch == null) {
      Navigator.of(context).pop(selection);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _launching = true);
    var result = OriginRoleLaunchHandlerResult.failed;
    try {
      result = await launch(selection);
    } catch (_) {
      result = OriginRoleLaunchHandlerResult.failed;
    }
    if (!mounted) return;
    switch (result) {
      case OriginRoleLaunchHandlerResult.failed:
        setState(() => _launching = false);
        return;
      case OriginRoleLaunchHandlerResult.closeSheet:
        Navigator.of(context).pop(selection);
        return;
      case OriginRoleLaunchHandlerResult.navigationHandled:
        return;
    }
  }

  String get _launchValidationMessage {
    if (_tabIndex == 0) return 'Please select a preset role';
    if (_customForm.name.text.trim().isEmpty) return 'Please enter a name';
    if (_customForm.identity.text.trim().isEmpty) {
      return 'Please enter an identity';
    }
    return 'Please wait for the profile to finish loading.';
  }

  void _dismiss() {
    if (_launching) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => GenesisDarkTheme(
    child: GenesisBottomSystemBarStyleScope(
      style: const GenesisBottomSystemBarStyle(
        color: GenesisColors.darkRaisedBackground,
      ),
      child: CreateFormTheme(child: Builder(builder: _buildContent)),
    ),
  );

  Widget _buildContent(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = math.max(
          0.0,
          constraints.maxHeight - media.padding.top - 18,
        );
        final targetHeight = math.min(media.size.height * 0.78, maxHeight);

        return GenesisEdgeSwipeBack(
          onBack: _dismiss,
          child: SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('origin-role-scrim-dismiss'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _launching ? null : _dismiss,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: GenesisBottomSheetPanel(
                      key: const ValueKey('origin-role-sheet'),
                      title: 'Setup Your Role',
                      height: targetHeight,
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                      trailing: GenesisBottomSheetCloseButton(
                        buttonKey: const ValueKey('origin-role-sheet-close'),
                        onPressed: _launching ? null : _dismiss,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RoleSegmentedControl(
                            index: _tabIndex,
                            onChanged: _selectTab,
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: AbsorbPointer(
                              absorbing: _launching,
                              child: _tabIndex == 0
                                  ? _PresetRoleGrid(
                                      key: const ValueKey(
                                        'origin-role-preset-tab',
                                      ),
                                      characters: widget.characters,
                                      selectedId: _selectedPresetId,
                                      resolveAvatarUrl: widget.resolveAvatarUrl,
                                      onSelected: (id) {
                                        if (_launching) return;
                                        setState(() => _selectedPresetId = id);
                                      },
                                    )
                                  : OriginCustomRoleForm(
                                      key: const ValueKey(
                                        'origin-role-custom-tab',
                                      ),
                                      form: _customForm,
                                      fillingProfile: _fillingProfile,
                                      canFillProfile:
                                          widget.onFillFromProfile != null,
                                      onChanged: _handleTextChanged,
                                      onFillFromProfile: _fillFromProfile,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _SheetActions(
                            canLaunch: _canLaunch,
                            launching: _launching,
                            onCancel: _launching ? null : _dismiss,
                            onLaunch: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoleSegmentedControl extends StatelessWidget {
  const _RoleSegmentedControl({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: GenesisColors.darkFaintFill,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: index == 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: GenesisColors.darkTextPrimary,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _SegmentButton(
                label: 'Preset',
                selected: index == 0,
                onTap: () => onChanged(0),
              ),
              _SegmentButton(
                label: 'Custom',
                selected: index == 1,
                onTap: () => onChanged(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          highlightColor: Colors.transparent,
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                height: 1,
                fontWeight: FontWeight.w600,
                color: selected
                    ? GenesisColors.darkBackground
                    : GenesisColors.darkTextSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetRoleGrid extends StatelessWidget {
  const _PresetRoleGrid({
    super.key,
    required this.characters,
    required this.selectedId,
    required this.onSelected,
    this.resolveAvatarUrl,
  });

  final List<OriginCharacter> characters;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final OriginRoleAvatarResolver? resolveAvatarUrl;

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return const Center(
        child: Text(
          'No preset role',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: GenesisColors.darkTextTertiary,
          ),
        ),
      );
    }

    final sortedCharacters = originCharactersRecommendedFirst(characters);

    return GridView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: sortedCharacters.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 116,
        crossAxisSpacing: 8,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        final character = sortedCharacters[index];
        final id = _characterRoleId(character);
        final avatar =
            resolveAvatarUrl?.call(character.avatar) ?? character.avatar.trim();
        return _PresetRoleTile(
          character: character,
          avatarUrl: avatar,
          selected: id == selectedId,
          onTap: () => onSelected(id),
        );
      },
    );
  }
}

class _PresetRoleTile extends StatelessWidget {
  const _PresetRoleTile({
    required this.character,
    required this.avatarUrl,
    required this.selected,
    required this.onTap,
  });

  final OriginCharacter character;
  final String avatarUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('origin-role-preset-${_characterRoleId(character)}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 82,
              height: 82,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GenesisCharacterAvatar(
                    url: avatarUrl,
                    name: character.name,
                    size: 82,
                    borderRadius: GenesisAvatarRadii.character,
                    showFallbackWhileLoading: false,
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: OriginRoleSelectionMark(selected: selected),
                  ),
                  if (character.isRecommended)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: OriginRecommendedRoleMark(
                        badgeKey: ValueKey(
                          'origin-role-preset-recommended-${_characterRoleId(character)}',
                        ),
                        showBackground: true,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              character.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                height: 1.1,
                fontWeight: FontWeight.w400,
                color: GenesisColors.darkTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OriginCustomRoleForm extends StatelessWidget {
  const OriginCustomRoleForm({
    super.key,
    required this.form,
    required this.fillingProfile,
    required this.canFillProfile,
    required this.onChanged,
    required this.onFillFromProfile,
    this.scrollable = true,
    this.textFieldFillColor,
    this.textFieldScrollPadding,
    this.handoffTextFieldVerticalDragToAncestor = false,
  });

  final OriginCharacterForm form;
  final bool fillingProfile;
  final bool canFillProfile;
  final VoidCallback onChanged;
  final VoidCallback onFillFromProfile;
  final bool scrollable;
  final Color? textFieldFillColor;
  final EdgeInsets? textFieldScrollPadding;
  final bool handoffTextFieldVerticalDragToAncestor;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: GenesisColors.darkFaintFill, width: 1.2),
          ),
          child: OriginCharacterFormFields(
            form: form,
            onChanged: onChanged,
            showPersonality: false,
            showGoal: false,
            showAvatarRemoveLink: true,
            labelFontWeight: FontWeight.w600,
            avatarEmptyLabelFontWeight: FontWeight.w600,
            avatarRemoveLinkFontWeight: FontWeight.w600,
            avatarEmptyIconLabelGap: 6,
            identityBelowAvatarRow: true,
            showPlaceholders: false,
            textFieldScrollPadding:
                textFieldScrollPadding ??
                const EdgeInsets.fromLTRB(20, 20, 20, 8),
            textFieldFillColor: textFieldFillColor,
            handoffTextFieldVerticalDragToAncestor:
                handoffTextFieldVerticalDragToAncestor,
            topSpacing: 0,
            bioMaxLines: 3,
          ),
        ),
        if (canFillProfile) ...[
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('origin-role-fill-profile'),
              onTap: fillingProfile ? null : onFillFromProfile,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                child: Text(
                  fillingProfile ? 'Filling...' : 'Fill from my profile',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: GenesisColors.redSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    if (!scrollable) {
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: content);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: content,
    );
  }
}

class _SheetActions extends StatelessWidget {
  const _SheetActions({
    required this.canLaunch,
    required this.launching,
    required this.onCancel,
    required this.onLaunch,
  });

  final bool canLaunch;
  final bool launching;
  final VoidCallback? onCancel;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GenesisPrimaryButton(
            key: const ValueKey('origin-role-cancel'),
            label: 'Cancel',
            backgroundColor: GenesisColors.darkFaintFill,
            foregroundColor: GenesisColors.darkTextPrimary,
            disabledBackgroundColor: GenesisColors.darkFaintFill,
            disabledForegroundColor: GenesisColors.darkTextTertiary,
            onPressed: onCancel,
            height: 35,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GenesisPrimaryButton(
            key: const ValueKey('origin-role-launch'),
            label: 'Launch',
            onPressed: canLaunch ? onLaunch : null,
            onDisabledPressed: launching ? null : onLaunch,
            isLoading: launching,
            height: 35,
            backgroundColor: GenesisColors.brand,
            disabledBackgroundColor: GenesisColors.darkButtonDisabledBackground,
            disabledForegroundColor: GenesisColors.darkButtonDisabledForeground,
            foregroundColor: GenesisColors.darkTextPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

bool _hasCharacterId(List<OriginCharacter> characters, String id) {
  if (id.trim().isEmpty) return false;
  return characters.any((character) => _characterRoleId(character) == id);
}

String _characterRoleId(OriginCharacter character) {
  final explicitId = character.characterId.trim();
  if (explicitId.isNotEmpty) return explicitId;
  if (character.id > 0) return '${character.id}';
  return character.name.trim();
}

String _limitProfileFill(String value, int maxLength) {
  final characters = value.characters;
  if (characters.length <= maxLength) return value;
  return characters.take(maxLength).toString();
}
