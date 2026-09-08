import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/debug/location_chat_bubble_layout_settings.dart';
import '../../components/common/genesis_action_box.dart';
import '../../components/common/genesis_bottom_sheet_panel.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/common/genesis_modal_routes.dart';
import '../../components/chat/shared/chat_ui.dart';
import '../../components/origin/origin_character_form.dart';
import '../../components/origin/origin_role_recommendation.dart';
import '../../components/origin/origin_role_selection_mark.dart';
import '../../components/page_header.dart';
import '../../components/world_location_list.dart';
import '../../components/world_point.dart';
import '../../icons/custom_icon_assets.dart';
import '../../network/api_exception.dart';
import '../../ui/genesis_ui.dart';
import '../../ui/tokens/genesis_avatar_radii.dart';
import '../../utils/genesis_ugc_text.dart';
import '../create/create_form_widgets.dart';
import '../create/create_origin_draft_store.dart';
import '../create/create_origin_id_utils.dart';
import 'origin_debug_tools.dart';
import 'origin_draft_repository.dart';

part 'origin_basics_editor_page.dart';
part 'origin_characters_editor_page.dart';
part 'origin_character_editor_widgets.dart';
part 'origin_editor_section_widgets.dart';
part 'origin_editor_style.dart';
part 'origin_locations_editor_page.dart';
part 'origin_locations_shared.dart';
part 'origin_opening_editor_page.dart';
part 'origin_story_events_editor_page.dart';
part 'origin_locations_tree.dart';
part 'origin_locations_tree_flow.dart';
part 'origin_locations_editor_view.dart';
part 'origin_locations_preview.dart';
part 'origin_opening_location_field.dart';
part 'origin_opening_dialogue_editor.dart';
part 'origin_opening_location_picker.dart';
part 'origin_opening_models.dart';

bool _characterDraftHasContent(CharacterDraft item) {
  return item.isRecommended ||
      item.avatarUrl.trim().isNotEmpty ||
      item.name.trim().isNotEmpty ||
      item.identity.trim().isNotEmpty ||
      item.personality.trim().isNotEmpty ||
      item.bio.trim().isNotEmpty ||
      item.goal.trim().isNotEmpty;
}

bool _locationDraftHasContent(LocationDraft item) {
  return item.imageUrl.trim().isNotEmpty ||
      item.name.trim().isNotEmpty ||
      item.description.trim().isNotEmpty ||
      item.initialCharacterIds.isNotEmpty;
}

class OriginSubmitResult {
  const OriginSubmitResult({
    required this.message,
    this.draft,
    this.showMessage = true,
  });

  final String message;
  final CreateOriginDraft? draft;
  final bool showMessage;
}

typedef OriginSubmitHandler =
    Future<OriginSubmitResult> Function(
      BuildContext context,
      OriginDraftRepository repository,
      CreateOriginDraft draft,
    );

enum _DraftLeaveAction { submit, save, discard }

enum OriginDraftSubmitStatus { idle, checkingPending, processing }

const TextStyle _editSummaryLabelStyle = TextStyle(
  color: Colors.black,
  fontSize: 14,
  fontWeight: FontWeight.w600,
  height: 1.2,
);

double _primaryActionButtonWidth(BuildContext context) {
  return MediaQuery.sizeOf(context).width * 0.7;
}

bool _hasKeyboardViewInset() {
  // Scaffold removes viewInsets from body MediaQuery, so read view metrics.
  for (final view in WidgetsBinding.instance.platformDispatcher.views) {
    if (view.viewInsets.bottom > 0) return true;
  }
  return false;
}

class _KeyboardHiddenBottomAction extends StatefulWidget {
  const _KeyboardHiddenBottomAction({
    required this.child,
    this.minimum = const EdgeInsets.fromLTRB(24, 8, 24, 14),
    this.onShown,
  });

  final Widget child;
  final EdgeInsets minimum;
  final VoidCallback? onShown;

  @override
  State<_KeyboardHiddenBottomAction> createState() =>
      _KeyboardHiddenBottomActionState();
}

class _KeyboardHiddenBottomActionState
    extends State<_KeyboardHiddenBottomAction>
    with WidgetsBindingObserver {
  late bool _keyboardVisible = _hasKeyboardViewInset();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final nextKeyboardVisible = _hasKeyboardViewInset();
    if (_keyboardVisible == nextKeyboardVisible) return;
    setState(() => _keyboardVisible = nextKeyboardVisible);
    if (!nextKeyboardVisible && widget.onShown != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onShown?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible =
        _keyboardVisible || MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardVisible) return const SizedBox.shrink();
    return SafeArea(top: false, minimum: widget.minimum, child: widget.child);
  }
}

class OriginDraftFlowPage extends StatefulWidget {
  const OriginDraftFlowPage({
    super.key,
    required this.title,
    required this.repository,
    required this.basicsPageBuilder,
    required this.charactersPageBuilder,
    required this.locationsPageBuilder,
    required this.storyEventsPageBuilder,
    this.openingPageBuilder,
    required this.onSubmit,
    this.submitLabel = 'Save',
    this.submittingLabel = 'Saving...',
    this.failurePrefix = 'Save failed',
    this.leaveTitle = 'Save the draft before leaving?',
    this.leaveSubmitLabel,
    this.submitUnavailableMessage = 'No changes to save.',
    this.canSubmit,
    this.popOnSubmitSuccess = false,
    this.confirmLeaveWithDraftOptions = false,
    this.onDiscardDraft,
    this.showCurrentVersion = false,
    this.updateNotesController,
    this.submitStatus = OriginDraftSubmitStatus.idle,
    this.reloadSignal = 0,
    this.debugDraftGenerator,
  });

  final String title;
  final OriginDraftRepository repository;
  final Widget Function(OriginDraftRepository repository) basicsPageBuilder;
  final Widget Function(OriginDraftRepository repository) charactersPageBuilder;
  final Widget Function(OriginDraftRepository repository) locationsPageBuilder;
  final Widget Function(OriginDraftRepository repository)? openingPageBuilder;
  final Widget Function(OriginDraftRepository repository)
  storyEventsPageBuilder;
  final OriginSubmitHandler onSubmit;
  final String submitLabel;
  final String submittingLabel;
  final String failurePrefix;
  final String leaveTitle;
  final String? leaveSubmitLabel;
  final String submitUnavailableMessage;
  final bool Function(CreateOriginDraft draft)? canSubmit;
  final bool popOnSubmitSuccess;
  final bool confirmLeaveWithDraftOptions;
  final Future<void> Function(OriginDraftRepository repository)? onDiscardDraft;
  final bool showCurrentVersion;
  final TextEditingController? updateNotesController;
  final OriginDraftSubmitStatus submitStatus;
  final int reloadSignal;
  final OriginDebugDraftGenerator? debugDraftGenerator;

  @override
  State<OriginDraftFlowPage> createState() => _OriginDraftFlowPageState();
}

class _OriginDraftFlowPageState extends State<OriginDraftFlowPage> {
  CreateOriginDraft _draft = CreateOriginDraft.empty();
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isHandlingLeave = false;

  @override
  void initState() {
    super.initState();
    widget.updateNotesController?.addListener(_handleUpdateNotesChanged);
    _reloadDraft();
  }

  @override
  void didUpdateWidget(covariant OriginDraftFlowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updateNotesController != widget.updateNotesController) {
      oldWidget.updateNotesController?.removeListener(
        _handleUpdateNotesChanged,
      );
      widget.updateNotesController?.addListener(_handleUpdateNotesChanged);
    }
    if (widget.reloadSignal != oldWidget.reloadSignal ||
        widget.repository != oldWidget.repository) {
      unawaited(_reloadDraft());
    }
  }

  @override
  void dispose() {
    widget.updateNotesController?.removeListener(_handleUpdateNotesChanged);
    super.dispose();
  }

  void _handleUpdateNotesChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _reloadDraft() async {
    final draft = await widget.repository.loadSummaryDraft();
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _isLoading = false;
    });
  }

  Future<void> _openSection(Widget page) async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => page));
    if (!mounted) return;
    _clearInputFocus();
    await _reloadDraft();
  }

  void _clearInputFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<bool> _submit() async {
    final latest = await widget.repository.loadSummaryDraft();
    if (!mounted) return false;
    final blockReason = _submitBlockReason(latest);
    if (blockReason != null) {
      _showError(blockReason);
      setState(() => _draft = latest);
      return false;
    }

    setState(() {
      _isSubmitting = true;
      _draft = latest;
    });

    try {
      final result = await widget.onSubmit(context, widget.repository, latest);
      if (!mounted) return false;
      if (result.showMessage && result.message.trim().isNotEmpty) {
        showGenesisToast(context, result.message);
      }
      if (result.draft != null) {
        setState(() {
          _draft = result.draft!;
          _isSubmitting = false;
        });
      } else {
        setState(() => _isSubmitting = false);
        await _reloadDraft();
      }
      if (widget.popOnSubmitSuccess && mounted) {
        Navigator.of(context).maybePop();
      }
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() => _isSubmitting = false);
      _showError(e.message);
      return false;
    } catch (e, stackTrace) {
      debugPrint('[OriginEditor] submit failed: $e');
      debugPrint('[OriginEditor] stacktrace:\n$stackTrace');
      if (!mounted) return false;
      setState(() => _isSubmitting = false);
      _showError(widget.failurePrefix);
      return false;
    }
  }

  void _showError(String message) {
    showGenesisToast(context, message);
  }

  String? _submitBlockReason(CreateOriginDraft draft) {
    final errors = draft.validateForSubmit();
    if (errors.isNotEmpty) return errors.first;
    if (!(widget.canSubmit?.call(draft) ?? true)) {
      return widget.submitUnavailableMessage;
    }
    if (widget.updateNotesController != null &&
        widget.updateNotesController!.text.trim().isEmpty) {
      return 'Update notes are required to publish.';
    }
    return null;
  }

  void _showSubmitDisabledReason() {
    if (_isSubmitting || widget.submitStatus != OriginDraftSubmitStatus.idle) {
      _showError('This action is already in progress.');
      return;
    }
    _showError(_submitBlockReason(_draft) ?? widget.submitUnavailableMessage);
  }

  Future<void> _handleLeaveRequest() async {
    if (_isHandlingLeave) return;
    _isHandlingLeave = true;
    final navigator = Navigator.of(context);
    final pageRoute = ModalRoute.of(context);

    bool pageCanInteract() {
      return mounted &&
          navigator.mounted &&
          (pageRoute == null || pageRoute.isCurrent);
    }

    try {
      final latest = await widget.repository.loadSummaryDraft();
      if (!pageCanInteract()) return;
      if (widget.submitStatus != OriginDraftSubmitStatus.idle) {
        navigator.pop();
        return;
      }
      if (!widget.confirmLeaveWithDraftOptions ||
          !_shouldConfirmLeave(latest)) {
        navigator.pop();
        return;
      }

      final dialogContext = navigator.context;
      if (!dialogContext.mounted) return;
      final action = await showGenesisActionBox<_DraftLeaveAction>(
        context: dialogContext,
        title: widget.leaveTitle,
        actions: [
          GenesisActionBoxAction<_DraftLeaveAction>(
            label: widget.leaveSubmitLabel ?? 'Save',
            value: widget.leaveSubmitLabel == null
                ? _DraftLeaveAction.save
                : _DraftLeaveAction.submit,
          ),
          const GenesisActionBoxAction<_DraftLeaveAction>(
            label: 'Discard',
            value: _DraftLeaveAction.discard,
          ),
        ],
      );
      if (!pageCanInteract() || action == null) return;
      if (action == _DraftLeaveAction.save) {
        await widget.repository.saveFinalDraft(latest);
      } else if (action == _DraftLeaveAction.submit) {
        final submitted = await _submit();
        if (!submitted || !pageCanInteract()) return;
      } else {
        await widget.onDiscardDraft?.call(widget.repository);
      }
      if (!pageCanInteract()) return;
      navigator.pop();
    } finally {
      _isHandlingLeave = false;
    }
  }

  bool _shouldConfirmLeave(CreateOriginDraft draft) {
    if (widget.leaveSubmitLabel != null) {
      return widget.repository.hasSubmitChanges(draft);
    }
    return _hasDraftContent(draft);
  }

  bool _hasDraftContent(CreateOriginDraft draft) {
    return draft.basicsSaved ||
        draft.charactersSaved ||
        draft.locationsSaved ||
        draft.storyEventsSaved ||
        draft.basics.originName.trim().isNotEmpty ||
        draft.basics.worldView.trim().isNotEmpty ||
        draft.basics.worldLogic.trim().isNotEmpty ||
        draft.basics.metricJson.trim().isNotEmpty ||
        draft.basics.coverImageUrl.trim().isNotEmpty ||
        draft.characters.any(_characterHasContent) ||
        draft.locations.any(_locationHasContent) ||
        draft.storyEvents.any((item) => item.event.trim().isNotEmpty);
  }

  bool _characterHasContent(CharacterDraft item) {
    return item.charId.trim().isNotEmpty ||
        item.avatarUrl.trim().isNotEmpty ||
        item.name.trim().isNotEmpty ||
        item.identity.trim().isNotEmpty ||
        item.personality.trim().isNotEmpty ||
        item.bio.trim().isNotEmpty ||
        item.goal.trim().isNotEmpty;
  }

  bool _locationHasContent(LocationDraft item) {
    return item.locationId.trim().isNotEmpty ||
        item.imageUrl.trim().isNotEmpty ||
        item.name.trim().isNotEmpty ||
        item.description.trim().isNotEmpty ||
        item.initialCharacterIds.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    const disabledSubmitColor = GenesisColors.brandSoft;
    final canUseSubmitButton =
        !_isSubmitting &&
        widget.submitStatus == OriginDraftSubmitStatus.idle &&
        _submitBlockReason(_draft) == null;
    final submitLabel = _submitButtonLabel();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_handleLeaveRequest());
      },
      child: GenesisEdgeSwipeBack(
        onBack: () => unawaited(_handleLeaveRequest()),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: GenesisBackAppBar(
            pageName: widget.title,
            onBack: () => unawaited(_handleLeaveRequest()),
          ),
          floatingActionButton: buildOriginDebugRandomContentButton(
            repository: widget.repository,
            generator: widget.debugDraftGenerator,
            enabled:
                !_isSubmitting &&
                widget.submitStatus == OriginDraftSubmitStatus.idle,
            onGenerated: _reloadDraft,
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _clearInputFocus,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          const SizedBox(height: 14),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.only(
                                bottom: widget.updateNotesController == null
                                    ? 10
                                    : 0,
                              ),
                              children: [
                                if (widget.showCurrentVersion) ...[
                                  Text(
                                    'Current Version: ${_versionLabel(_draft.basics.originVersion)}',
                                    style: _editSummaryLabelStyle,
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                _SectionRow(
                                  icon: createOriginBasicsIconAsset,
                                  title: 'Basics',
                                  summary: _basicsSummary(_draft),
                                  modified: _basicsModified(_draft),
                                  onTap: () => _openSection(
                                    widget.basicsPageBuilder(widget.repository),
                                  ),
                                ),
                                _SectionRow(
                                  icon: createOriginCharactersIconAsset,
                                  title: 'Characters (>=1)',
                                  summary: _charactersSummary(_draft),
                                  modified: _charactersModified(_draft),
                                  wrapFirstSummaryLine: true,
                                  onTap: () => _openSection(
                                    widget.charactersPageBuilder(
                                      widget.repository,
                                    ),
                                  ),
                                ),
                                _SectionRow(
                                  icon: createOriginLocationsIconAsset,
                                  title: 'Locations (>=1)',
                                  summary: _locationsSummary(_draft),
                                  modified: _locationsModified(_draft),
                                  onTap: () => _openSection(
                                    widget.locationsPageBuilder(
                                      widget.repository,
                                    ),
                                  ),
                                ),
                                if (widget.openingPageBuilder != null)
                                  _SectionRow(
                                    key: ValueKey<String>(
                                      'create-opening-section',
                                    ),
                                    icon: createOriginOpeningIconAsset,
                                    title: 'Opening',
                                    summary: _openingSummary(_draft),
                                    modified: _openingModified(_draft),
                                    onTap: () => _openSection(
                                      widget.openingPageBuilder!(
                                        widget.repository,
                                      ),
                                    ),
                                  ),
                                _SectionRow(
                                  icon: createOriginStoryEventsIconAsset,
                                  title: 'Story Events (Optional)',
                                  summary: _storyEventsSummary(_draft),
                                  modified: _storyEventsModified(_draft),
                                  showDivider: false,
                                  onTap: () => _openSection(
                                    widget.storyEventsPageBuilder(
                                      widget.repository,
                                    ),
                                  ),
                                ),
                                if (widget.updateNotesController != null) ...[
                                  const SizedBox(height: 20),
                                  const _UpdateNotesFieldLabel(),
                                  const SizedBox(height: 8),
                                  _UpdateNotesField(
                                    controller: widget.updateNotesController!,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _KeyboardHiddenBottomAction(
                    child: GenesisPrimaryButton(
                      label: submitLabel,
                      width: _primaryActionButtonWidth(context),
                      onPressed: canUseSubmitButton
                          ? () => unawaited(_submit())
                          : null,
                      onDisabledPressed: _showSubmitDisabledReason,
                      backgroundColor: createFormGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: disabledSubmitColor,
                      disabledForegroundColor: Colors.white,
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

  String _submitButtonLabel() {
    if (_isSubmitting) return widget.submittingLabel;
    return switch (widget.submitStatus) {
      OriginDraftSubmitStatus.idle => widget.submitLabel,
      OriginDraftSubmitStatus.checkingPending => 'Checking...',
      OriginDraftSubmitStatus.processing => widget.submittingLabel,
    };
  }

  String _basicsSummary(CreateOriginDraft draft) {
    if (!draft.basicsSaved) return 'Not started yet';
    final basics = draft.basics;
    return [
      'Worldo Name: ${_originNameSummaryValue(basics.originName)}',
      'Worldo Brief: ${_summaryValue(basics.worldView)}',
      'Cover Image: ${basics.coverImageUrl.trim().isEmpty ? 'Not uploaded' : 'Uploaded'}',
      'Worldo Settings: ${_summaryValue(basics.worldLogic)}',
      'Worldo Time: ${_summaryValue(_worldTimeSummary(basics))}',
      'Worldo Metric: ${_summaryValue(_progressMetricSummary(basics))}',
    ].join('\n');
  }

  String _worldTimeSummary(BasicsDraft basics) {
    final parts = <String>[
      if (_singleLineSummaryText(basics.startedAt).isNotEmpty)
        _singleLineSummaryText(basics.startedAt),
      if (_singleLineSummaryText(basics.tickDurationTime).isNotEmpty)
        _singleLineSummaryText(basics.tickDurationTime)
      else if (basics.tickDurationDays != null)
        basics.tickDurationDays == 1
            ? '1 day'
            : '${basics.tickDurationDays} days',
    ];
    return parts.join(', ');
  }

  String _progressMetricSummary(BasicsDraft basics) {
    final raw = basics.metricJson.trim();
    if (raw.isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return raw;
      final parts = <String>[
        _summaryMetricValue(decoded['label']),
        _summaryMetricValue(decoded['label_note']),
        _summaryMetricValue(decoded['unit']),
        _summaryMetricValue(decoded['default']),
        _summaryMetricValue(decoded['range']),
      ];
      return parts.where((item) => item.isNotEmpty).join(', ');
    } catch (_) {
      return raw;
    }
  }

  String _summaryMetricValue(Object? value) {
    if (value == null) return '';
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .join(' - ');
    }
    return _singleLineSummaryText(value.toString());
  }

  String _charactersSummary(CreateOriginDraft draft) {
    if (!draft.charactersSaved) return 'Not started yet';
    final characters = draft.characters
        .where(_characterDraftHasContent)
        .toList(growable: false);
    final names = characters
        .map((item) => _singleLineSummaryText(item.name))
        .where((name) => name.isNotEmpty)
        .join(', ');
    final bestRoleName = characters
        .where((item) => item.isRecommended)
        .map((item) => _singleLineSummaryText(item.name))
        .where((name) => name.isNotEmpty)
        .firstOrNull;
    final characterSummary = characters.isEmpty
        ? '0 characters'
        : '${characters.length} characters: $names';
    if (bestRoleName == null) return characterSummary;
    return '$characterSummary\nSuggested: $bestRoleName';
  }

  String _locationsSummary(CreateOriginDraft draft) {
    if (!draft.locationsSaved) return 'Not started yet';
    final locations = draft.locations
        .where(_locationDraftHasContent)
        .toList(growable: false);
    final l1Count = locations.where((item) => item.level == 1).length;
    final l2Count = locations.where((item) => item.level == 2).length;
    final l3Count = locations
        .where((item) => item.level != 1 && item.level != 2)
        .length;
    return 'L1 · Region : $l1Count\n'
        'L2 · Building : $l2Count\n'
        'L3 · Room : $l3Count';
  }

  String _storyEventsSummary(CreateOriginDraft draft) {
    if (!draft.storyEventsSaved) return 'Not started yet';
    final count = draft.storyEvents
        .map((item) => item.event.trim())
        .where((item) => item.isNotEmpty)
        .length;
    return '$count events';
  }

  String _openingSummary(CreateOriginDraft draft) {
    if (!draft.openingSaved) return 'Not started yet';
    final opening = draft.opening;
    final locationName = _singleLineSummaryText(opening.locationName);
    var characterDialogueCount = 0;
    var narratorCount = 0;
    var imageCount = 0;
    for (final item in opening.dialogue) {
      switch (item.type.trim()) {
        case OpeningDialogueDraft.characterType:
          characterDialogueCount += 1;
        case OpeningDialogueDraft.narratorType:
          narratorCount += 1;
        case OpeningDialogueDraft.imageType:
          imageCount += 1;
      }
    }
    return <String>[
      locationName.isEmpty ? '-' : locationName,
      'Character dialogue : $characterDialogueCount',
      'Narrator : $narratorCount',
      'Image : $imageCount',
    ].join('\n');
  }

  String _summaryValue(String value, {int maxLength = 48}) {
    final trimmed = _singleLineSummaryText(value);
    if (trimmed.isEmpty) return '-';
    if (trimmed.length <= maxLength) return trimmed;
    return '${trimmed.substring(0, maxLength)}...';
  }

  String _originNameSummaryValue(String value) {
    final trimmed = _singleLineSummaryText(value);
    if (trimmed.isEmpty) return '-';
    return _summaryValue('#$trimmed');
  }

  String _singleLineSummaryText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _versionLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '-';
    if (trimmed.toUpperCase().startsWith('V')) return trimmed;
    return 'V$trimmed';
  }

  bool _basicsModified(CreateOriginDraft draft) {
    final repository = widget.repository;
    return repository is MemoryOriginDraftRepository &&
        repository.basicsChanged(draft);
  }

  bool _charactersModified(CreateOriginDraft draft) {
    final repository = widget.repository;
    return repository is MemoryOriginDraftRepository &&
        repository.charactersChanged(draft);
  }

  bool _locationsModified(CreateOriginDraft draft) {
    final repository = widget.repository;
    return repository is MemoryOriginDraftRepository &&
        repository.locationsChanged(draft);
  }

  bool _openingModified(CreateOriginDraft draft) {
    final repository = widget.repository;
    return repository is MemoryOriginDraftRepository &&
        repository.openingChanged(draft);
  }

  bool _storyEventsModified(CreateOriginDraft draft) {
    final repository = widget.repository;
    return repository is MemoryOriginDraftRepository &&
        repository.storyEventsChanged(draft);
  }
}

class _UpdateNotesFieldLabel extends StatelessWidget {
  const _UpdateNotesFieldLabel();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Update notes (required to publish)',
      style: _editSummaryLabelStyle,
    );
  }
}

class _UpdateNotesField extends StatelessWidget {
  const _UpdateNotesField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return CreateTextFieldBlock(
      label: '',
      controller: controller,
      hintText: 'What changed in this version?',
      minLines: 4,
      maxLines: 4,
      visibilityBottomPadding: 10,
      textInputAction: TextInputAction.done,
      onChanged: (_) {},
      onEditingComplete: () => FocusManager.instance.primaryFocus?.unfocus(),
      onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    );
  }
}
