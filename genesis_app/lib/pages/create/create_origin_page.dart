import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/auth/login_guard.dart';
import '../../components/common/genesis_generation_wait_overlay.dart';
import '../../network/api_client.dart';
import '../../network/json_utils.dart';
import '../../utils/display_name_formatter.dart';
import '../origin_editor/origin_debug_tools.dart';
import '../origin_editor/origin_draft_repository.dart';
import '../origin_editor/origin_editor_pages.dart';
import '../origin_editor/origin_generation_wait_content.dart';
import '../origin_editor/origin_pending_submission_coordinator.dart';
import 'create_basics_page.dart';
import 'create_characters_page.dart';
import 'create_locations_page.dart';
import 'create_opening_page.dart';
import 'create_origin_draft_store.dart';
import 'create_story_events_page.dart';

class CreateOriginPage extends StatefulWidget {
  const CreateOriginPage({super.key});

  @override
  State<CreateOriginPage> createState() => _CreateOriginPageState();
}

class _CreateOriginPageState extends State<CreateOriginPage> {
  static const CreateOriginDraftRepository _repository =
      CreateOriginDraftRepository();

  final OriginPendingSubmissionCoordinator _pendingCoordinator =
      OriginPendingSubmissionCoordinator.instance;
  OriginDraftSubmitStatus _submitStatus = OriginDraftSubmitStatus.idle;
  int _reloadSignal = 0;
  late final VoidCallback _removeCreateOutcomeListener;
  bool _didResumePendingCreate = false;
  List<String> _generationWaitLines = const <String>[];

  @override
  void initState() {
    super.initState();
    GenesisTelemetry.collectLog(
      actionType: 'pageview',
      action: 'create_worldo',
    );
    _pendingCoordinator.creatingState.addListener(_syncSubmitStatus);
    _removeCreateOutcomeListener = _pendingCoordinator.addCreateOutcomeListener(
      _handleCreateOutcome,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didResumePendingCreate) return;
    _didResumePendingCreate = true;
    _resumePendingCreate();
  }

  @override
  void dispose() {
    _pendingCoordinator.creatingState.removeListener(_syncSubmitStatus);
    _removeCreateOutcomeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = OriginDraftFlowPage(
      title: 'Create Worldo',
      repository: _repository,
      basicsPageBuilder: (_) => const CreateBasicsPage(),
      charactersPageBuilder: (_) => const CreateCharactersPage(),
      locationsPageBuilder: (_) => const CreateLocationsPage(),
      openingPageBuilder: (_) => const CreateOpeningPage(),
      storyEventsPageBuilder: (_) => const CreateStoryEventsPage(),
      failurePrefix: 'Create failed',
      submitLabel: 'Create',
      submittingLabel: 'Creating...',
      onSubmit: _onCreate,
      submitStatus: _submitStatus,
      reloadSignal: _reloadSignal,
      debugDraftGenerator: createOriginDebugDraftGenerator(),
      confirmLeaveWithDraftOptions: true,
      onDiscardDraft: (_) => CreateOriginDraftStore.clear(),
    );
    if (_submitStatus == OriginDraftSubmitStatus.idle) return flow;
    return Stack(
      children: [
        flow,
        Positioned.fill(
          child: GenesisGenerationWaitOverlay(
            brightness: Brightness.dark,
            title: 'Creating your Worldo',
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

  Future<OriginSubmitResult> _onCreate(
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
      GenesisTelemetry.collectLog(
        actionType: 'event',
        action: 'create_worldo_submit_start',
      );
      final result = await api.createOriginV2(
        payload: draft.toCreateOriginPayload(),
      );
      final originId = result.oid.trim();
      if (originId.isEmpty) {
        throw StateError('origin_id is missing from create response');
      }
      GenesisTelemetry.collectLog(
        actionType: 'event',
        action: 'create_worldo_submit_success',
        object1: originId,
      );
      await _pendingCoordinator.startCreating(
        originId: originId,
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

  void _resumePendingCreate() {
    final api = AppServicesScope.read(context).api;
    unawaited(_loadPendingCreateWaitLines());
    unawaited(
      _pendingCoordinator.ensureCreatingPolling(
        loadOriginInfo: (originId) => api.v1.origin.info(
          originId: originId,
          tracePolicy: ApiRequestTracePolicy.excluded,
        ),
        context: context,
      ),
    );
    _syncSubmitStatus();
  }

  Future<void> _loadPendingCreateWaitLines() async {
    final originatorName = await _readOriginatorName(context);
    final draft = await CreateOriginDraftStore.loadFinal();
    if (!mounted) return;
    setState(() {
      _generationWaitLines = originDraftGenerationWaitLines(
        draft,
        originatorName: originatorName,
      );
    });
  }

  void _syncSubmitStatus() {
    if (!mounted) return;
    final state = _pendingCoordinator.creatingState.value;
    final nextStatus = switch (state?.phase) {
      OriginPendingSubmissionPhase.checkingPending =>
        OriginDraftSubmitStatus.checkingPending,
      OriginPendingSubmissionPhase.processing =>
        OriginDraftSubmitStatus.processing,
      null => OriginDraftSubmitStatus.idle,
    };
    if (_submitStatus == nextStatus) return;
    setState(() => _submitStatus = nextStatus);
  }

  void _handleCreateOutcome(OriginPendingSubmissionOutcome outcome) {
    if (!mounted) return;
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
