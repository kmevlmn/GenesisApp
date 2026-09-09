import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/auth/login_guard.dart';
import '../../components/common/genesis_generation_wait_overlay.dart';
import '../../components/page_header.dart';
import '../../ui/genesis_ui.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../network/api_client.dart';
import '../../network/api_exception.dart';
import '../../network/json_utils.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/genesis_ugc_text.dart';
import '../create/create_origin_draft_store.dart';
import '../origin_editor/origin_draft_repository.dart';
import '../origin_editor/origin_debug_tools.dart';
import '../origin_editor/origin_editor_pages.dart';
import '../origin_editor/origin_generation_wait_content.dart';
import '../origin_editor/origin_pending_submission_coordinator.dart';
import 'edit_basics_page.dart';
import 'edit_characters_page.dart';
import 'edit_locations_page.dart';
import 'edit_opening_page.dart';
import 'edit_story_events_page.dart';

class EditOriginPage extends StatefulWidget {
  const EditOriginPage({super.key, required this.originId});

  final String originId;

  @override
  State<EditOriginPage> createState() => _EditOriginPageState();
}

class _EditOriginPageState extends State<EditOriginPage> {
  final OriginPendingSubmissionCoordinator _pendingCoordinator =
      OriginPendingSubmissionCoordinator.instance;
  MemoryOriginDraftRepository? _repository;
  final TextEditingController _updateNotesController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  OriginDraftSubmitStatus _submitStatus = OriginDraftSubmitStatus.idle;
  int _reloadSignal = 0;
  late final VoidCallback _removePublishOutcomeListener;
  List<String> _generationWaitLines = const <String>[];
  bool _forEditIncludesSetting = false;
  bool _forEditIncludesEvents = false;
  Set<String> _forEditCharacterIds = const <String>{};
  Set<String> _forEditCharacterIdsWithBio = const <String>{};

  @override
  void initState() {
    super.initState();
    _pendingCoordinator.publishingState.addListener(_syncSubmitStatus);
    _removePublishOutcomeListener = _pendingCoordinator
        .addPublishOutcomeListener(_handlePublishOutcome);
    _loadOrigin();
  }

  @override
  void dispose() {
    _pendingCoordinator.publishingState.removeListener(_syncSubmitStatus);
    _removePublishOutcomeListener();
    _updateNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadOrigin() async {
    final originId = widget.originId.trim();
    if (originId.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'origin_id is required.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = AppServicesScope.read(context).api;
      final editData = await api.v2.origin.forEdit(originId: originId);
      final editInfo = editData['info'] is Map
          ? asJsonMap(editData['info'])
          : editData;
      final editCharacters = editData['characters'] is List
          ? asJsonList(
              editData['characters'],
            ).whereType<Map>().map(asJsonMap).toList(growable: false)
          : const <Map<String, dynamic>>[];
      final initialDraft = originDraftFromV2ForEdit(editData);
      if (!mounted) return;
      setState(() {
        _forEditIncludesSetting =
            editInfo.containsKey('setting') ||
            editInfo.containsKey('world_setting');
        _forEditIncludesEvents =
            editInfo.containsKey('events') ||
            editData.containsKey('events') ||
            editData.containsKey('event_list');
        _forEditCharacterIds = editCharacters
            .map((item) => asString(item['char_id']).trim())
            .where((item) => item.isNotEmpty)
            .toSet();
        _forEditCharacterIdsWithBio = editCharacters
            .where(
              (item) =>
                  item.containsKey('bio') || item.containsKey('description'),
            )
            .map((item) => asString(item['char_id']).trim())
            .where((item) => item.isNotEmpty)
            .toSet();
        _repository = MemoryOriginDraftRepository(initialDraft: initialDraft);
        _updateNotesController.clear();
        _submitStatus = OriginDraftSubmitStatus.idle;
        _isLoading = false;
      });
      final originatorName = await _readOriginatorName(context);
      if (!mounted) return;
      setState(() {
        _generationWaitLines = originDraftGenerationWaitLines(
          initialDraft,
          originatorName: originatorName,
        );
      });
      await _pendingCoordinator.ensurePublishingPolling(
        loadOriginInfo: (originId) => api.v1.origin.info(
          originId: originId,
          tracePolicy: ApiRequestTracePolicy.excluded,
        ),
        context: context,
      );
      _syncSubmitStatus();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Load failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GenesisDarkTheme(
      child: GenesisBottomSystemBarStyleScope(
        style: const GenesisBottomSystemBarStyle(
          color: GenesisColors.darkBackground,
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: kGenesisLightSystemUiOverlayStyle,
          child: _buildPage(context),
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: GenesisColors.darkBackground,
        appBar: GenesisBackAppBar(
          pageName: 'Edit Worldo',
          backgroundColor: GenesisColors.darkBackground,
          foregroundColor: GenesisColors.darkTextPrimary,
          systemOverlayStyle: kGenesisLightSystemUiOverlayStyle,
        ),
        body: Center(child: GenesisLoadingIndicator()),
      );
    }

    final repository = _repository;
    if (_error != null || repository == null) {
      return Scaffold(
        backgroundColor: GenesisColors.darkBackground,
        appBar: const GenesisBackAppBar(
          pageName: 'Edit Worldo',
          backgroundColor: GenesisColors.darkBackground,
          foregroundColor: GenesisColors.darkTextPrimary,
          systemOverlayStyle: kGenesisLightSystemUiOverlayStyle,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? 'Worldo detail is unavailable.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: GenesisColors.darkTextSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loadOrigin,
                  style: FilledButton.styleFrom(
                    backgroundColor: GenesisColors.darkFaintFill,
                    foregroundColor: GenesisColors.darkTextPrimary,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final flow = OriginDraftFlowPage(
      key: ValueKey('edit-origin-${widget.originId}'),
      title: 'Edit Worldo',
      repository: repository,
      basicsPageBuilder: (repository) => EditBasicsPage(repository: repository),
      charactersPageBuilder: (repository) =>
          EditCharactersPage(repository: repository),
      locationsPageBuilder: (repository) =>
          EditLocationsPage(repository: repository),
      openingPageBuilder: (repository) =>
          EditOpeningPage(repository: repository),
      storyEventsPageBuilder: (repository) =>
          EditStoryEventsPage(repository: repository),
      canSubmit: repository.hasSubmitChanges,
      submitLabel: 'Publish',
      submittingLabel: 'Publishing...',
      disabledSubmitBackgroundColor: GenesisColors.redSecondary,
      failurePrefix: 'Publish failed',
      leaveTitle: 'Publish changes before leaving?',
      leaveSubmitLabel: 'Publish',
      submitUnavailableMessage: 'No changes to publish.',
      showCurrentVersion: true,
      updateNotesController: _updateNotesController,
      submitStatus: _submitStatus,
      reloadSignal: _reloadSignal,
      debugDraftGenerator: editOriginDebugDraftGenerator(
        _updateNotesController,
      ),
      onSubmit: _onSave,
    );
    if (_submitStatus == OriginDraftSubmitStatus.idle) return flow;
    return Stack(
      children: [
        flow,
        Positioned.fill(
          child: GenesisGenerationWaitOverlay(
            brightness: Brightness.dark,
            title: 'Publishing your Worldo',
            illustration: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 88,
                  height: 88,
                ),
              ),
            ),
            perspectiveLines: _generationWaitLines,
            centeredPerspectiveLineCount: 2,
            onBackPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    );
  }

  Future<OriginSubmitResult> _onSave(
    BuildContext context,
    OriginDraftRepository repository,
    CreateOriginDraft draft,
  ) async {
    if (!await ensureGenesisLogin(context)) {
      return const OriginSubmitResult(message: '', showMessage: false);
    }
    if (!context.mounted) {
      return const OriginSubmitResult(message: '', showMessage: false);
    }
    final originId = draft.basics.originId.trim();
    final api = AppServicesScope.read(context).api;
    setState(() {
      _submitStatus = OriginDraftSubmitStatus.checkingPending;
      _generationWaitLines = originDraftGenerationWaitLines(draft);
    });
    try {
      final originatorName = await _readOriginatorName(context);
      if (!context.mounted) {
        return const OriginSubmitResult(message: '', showMessage: false);
      }
      setState(
        () => _generationWaitLines = originDraftGenerationWaitLines(
          draft,
          originatorName: originatorName,
        ),
      );
      final payload = draft.toCreateOriginPayload();
      if (payload['init_location_group'] is! Map) {
        throw StateError('A complete Opening is required to publish');
      }
      if (repository is MemoryOriginDraftRepository) {
        payload['deleted_char_ids'] = repository.deletedCharacterIds(draft);
        payload['deleted_location_ids'] = repository.deletedLocationIds(draft);
        if (!_forEditIncludesSetting && !repository.worldLogicChanged(draft)) {
          payload.remove('world_setting');
        }
        if (!_forEditIncludesEvents && !repository.storyEventsChanged(draft)) {
          payload.remove('event_list');
        }
        final characters = payload['character_list'];
        if (characters is List) {
          for (final item in characters.whereType<Map>()) {
            final character = asJsonMap(item);
            final charId = asString(character['char_id']).trim();
            if (_forEditCharacterIds.contains(charId) &&
                !_forEditCharacterIdsWithBio.contains(charId) &&
                asString(character['description']).trim().isEmpty) {
              item.remove('description');
            }
          }
        }
      }
      payload['update_notes'] = normalizeGenesisUgcTextForSubmission(
        _updateNotesController.text,
      );
      GenesisTelemetry.collectLog(
        actionType: 'event',
        action: 'edit_worldo_submit_start',
        object1: originId,
      );
      final result = await api.updateOriginV2(oid: originId, payload: payload);
      final updatedOriginId = result.oid.trim();
      if (updatedOriginId.isEmpty) {
        throw StateError('origin_id is missing from publish response');
      }
      GenesisTelemetry.collectLog(
        actionType: 'event',
        action: 'edit_worldo_submit_success',
        object1: updatedOriginId,
      );
      await _pendingCoordinator.startPublishing(
        originId: updatedOriginId,
        originName: draft.basics.originName,
        loadOriginInfo: (originId) => api.v1.origin.info(
          originId: originId,
          tracePolicy: ApiRequestTracePolicy.excluded,
        ),
      );
      return const OriginSubmitResult(message: '', showMessage: false);
    } catch (_) {
      if (mounted) setState(() => _submitStatus = OriginDraftSubmitStatus.idle);
      rethrow;
    }
  }

  void _syncSubmitStatus() {
    if (!mounted) return;
    final state = _pendingCoordinator.publishingState.value;
    final nextStatus = switch (state?.originId == widget.originId
        ? state?.phase
        : null) {
      OriginPendingSubmissionPhase.checkingPending =>
        OriginDraftSubmitStatus.checkingPending,
      OriginPendingSubmissionPhase.processing =>
        OriginDraftSubmitStatus.processing,
      null => OriginDraftSubmitStatus.idle,
    };
    if (_submitStatus == nextStatus) return;
    setState(() => _submitStatus = nextStatus);
  }

  void _handlePublishOutcome(OriginPendingSubmissionOutcome outcome) {
    if (!mounted || outcome.originId != widget.originId) return;
    if (outcome.completed) {
      _repository?.markCurrentAsOriginal();
    }
    setState(() {
      _submitStatus = OriginDraftSubmitStatus.idle;
      _reloadSignal++;
    });
  }

  Future<String> _readOriginatorName(BuildContext context) async {
    final services = AppServicesScope.read(context);
    final userInfo = await services.sessionStore.readUserInfo();
    final uid = (await services.sessionStore.readUid())?.trim() ?? '';
    final rawName = userInfo == null
        ? ''
        : asString(
            userInfo['name'] ??
                userInfo['user_name'] ??
                userInfo['username'] ??
                userInfo['display_name'] ??
                userInfo['nickname'],
          );
    return formatUidForDisplay(rawName, fallback: uid.isEmpty ? 'You' : uid);
  }
}
