import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../network/api_client.dart';
import '../../network/dio_http_transport.dart';
import '../../network/json_utils.dart';
import '../../utils/genesis_image_resource.dart';
import '../create/create_origin_draft_store.dart';
import 'origin_debug_draft_factory.dart';
import 'origin_debug_image_upload.dart';
import 'origin_draft_repository.dart';

import '../../ui/genesis_ui.dart';
import 'origin_debug_random_action.dart';

export 'origin_debug_random_action.dart';

OriginDebugDraftGenerator? createOriginDebugDraftGenerator() {
  if (!kDebugMode) return null;
  return (context, currentDraft) async {
    final generated = generateRandomCreateOriginDraft(currentDraft);
    return _uploadGeneratedImages(context, currentDraft, generated);
  };
}

OriginDebugDraftGenerator? editOriginDebugDraftGenerator(
  TextEditingController updateNotesController,
) {
  if (!kDebugMode) return null;
  return (context, currentDraft) async {
    final generated = await _uploadGeneratedImages(
      context,
      currentDraft,
      generateRandomEditOriginDraft(currentDraft),
    );
    if (!context.mounted) return generated;
    updateNotesController.text = 'Generated random test content in debug mode.';
    return generated;
  };
}

final Map<String, ApiClient> _debugImageDownloadClients = <String, ApiClient>{};

Future<CreateOriginDraft> _uploadGeneratedImages(
  BuildContext context,
  CreateOriginDraft current,
  CreateOriginDraft generated,
) {
  final services = AppServicesScope.read(context);
  final uploadApi = services.api.v1.upload;
  final debugProxy = services.config.debugProxy.trim();
  final downloadClient = _debugImageDownloadClients.putIfAbsent(
    debugProxy,
    () => ApiClient(
      baseUrl: 'https://localhost.invalid/',
      defaultHeaders: const <String, String>{'accept': 'image/*'},
      transport: DioHttpTransport(proxy: debugProxy),
      timeoutMs: 120000,
      retryPolicy: ApiRetryPolicy.safe,
    ),
  );
  return uploadGeneratedOriginDebugImages(
    current: current,
    generated: generated,
    downloadImage: (sourceUrl) async {
      if (!context.mounted) {
        throw StateError('Debug image generation was cancelled.');
      }
      final bytes = await downloadClient.downloadBytes(sourceUrl.toString());
      return Uint8List.fromList(bytes);
    },
    uploadImage: (image) async {
      if (!context.mounted) {
        throw StateError('Debug image generation was cancelled.');
      }
      final uploaded = await uploadApi.image(
        bytes: image.bytes,
        filename: image.filename,
        contentType: image.contentType,
      );
      final uploadedUrl = GenesisImageResourceRegistry.resolve(
        uploaded,
      ).displayUrl;
      if (uploadedUrl.trim().isEmpty) {
        throw StateError(
          'Upload returned an empty URL: ${asString(uploaded['object_key'])}',
        );
      }
      return uploadedUrl;
    },
  );
}

final _randomActions = <_RegisteredRandomAction>[];

VoidCallback registerOriginDebugRandomAction({
  required BuildContext context,
  required String Function() label,
  required OriginDraftRepository Function() repository,
  required OriginDebugDraftGenerator? Function() generator,
  required bool Function() enabled,
  required Future<void> Function() onGenerated,
}) {
  if (!kDebugMode) return () {};
  final action = _RegisteredRandomAction(
    context: context,
    labelProvider: label,
    repository: repository,
    generator: generator,
    enabled: enabled,
    onGenerated: onGenerated,
  );
  _randomActions.add(action);
  return () {
    action.active = false;
    _randomActions.remove(action);
  };
}

OriginDebugRandomAction? captureOriginDebugRandomAction() {
  if (!kDebugMode) return null;
  for (final action in _randomActions.reversed) {
    if (action.active &&
        action.context.mounted &&
        ModalRoute.of(action.context)?.isCurrent == true &&
        action.generator() != null) {
      return action;
    }
  }
  return null;
}

class _RegisteredRandomAction implements OriginDebugRandomAction {
  _RegisteredRandomAction({
    required this.context,
    required this.labelProvider,
    required this.repository,
    required this.generator,
    required this.enabled,
    required this.onGenerated,
  });

  final BuildContext context;
  final String Function() labelProvider;
  final OriginDraftRepository Function() repository;
  final OriginDebugDraftGenerator? Function() generator;
  final bool Function() enabled;
  final Future<void> Function() onGenerated;
  bool active = true;
  bool generating = false;

  @override
  String get label => labelProvider();
  @override
  bool get isEnabled =>
      active &&
      context.mounted &&
      !generating &&
      enabled() &&
      generator() != null;

  @override
  Future<void> generate() async {
    if (!isEnabled) throw StateError('No active editor available.');
    final targetRepository = repository();
    final targetGenerator = generator()!;
    generating = true;
    try {
      final current = await targetRepository.loadSummaryDraft();
      if (!active || !context.mounted) throw StateError('Editor closed.');
      final generated = await targetGenerator(context, current);
      if (!active ||
          !context.mounted ||
          !enabled() ||
          repository() != targetRepository) {
        throw StateError('Editor changed during generation.');
      }
      await targetRepository.saveFinalDraft(
        _markChangedDebugSectionsSaved(current, generated),
      );
      if (active && context.mounted) await onGenerated();
    } finally {
      generating = false;
    }
  }
}

Widget? buildOriginDebugRandomContentButton({
  required OriginDebugRandomAction? action,
}) {
  if (!kDebugMode) return null;
  return _DeveloperRandomContentButton(action: action);
}

class _DeveloperRandomContentButton extends StatefulWidget {
  const _DeveloperRandomContentButton({required this.action});
  final OriginDebugRandomAction? action;
  @override
  State<_DeveloperRandomContentButton> createState() =>
      _DeveloperRandomContentButtonState();
}

class _DeveloperRandomContentButtonState
    extends State<_DeveloperRandomContentButton> {
  bool _generating = false;

  Future<void> _generate() async {
    final action = widget.action;
    if (_generating || action == null || !action.isEnabled) return;
    setState(() => _generating = true);
    try {
      await action.generate();
      if (mounted) showGenesisToast(context, 'Random test content generated.');
    } catch (error, stackTrace) {
      debugPrint(
        '[OriginEditor] debug draft generation failed: $error\n$stackTrace',
      );
      if (mounted) {
        showGenesisToast(context, 'Unable to generate random test content.');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GenesisPrimaryButton(
          key: const ValueKey<String>('origin-debug-random-content-button'),
          label: _generating ? 'Generating...' : 'Random',
          onPressed: !_generating && (widget.action?.isEnabled ?? false)
              ? () => unawaited(_generate())
              : null,
          backgroundColor: const Color(0xFFE1E1E3),
          foregroundColor: Colors.black,
        ),
        const SizedBox(height: 6),
        Text(
          widget.action == null
              ? 'Open Create or Edit home before opening Developer to use Random.'
              : 'Generate random content for ${widget.action!.label}.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
        ),
      ],
    );
  }
}

CreateOriginDraft _markChangedDebugSectionsSaved(
  CreateOriginDraft current,
  CreateOriginDraft generated,
) {
  final currentDraft = current.normalized();
  final generatedDraft = generated.normalized();
  bool changed(Object currentValue, Object generatedValue) {
    return jsonEncode(currentValue) != jsonEncode(generatedValue);
  }

  return generatedDraft.copyWith(
    basicsSaved:
        generatedDraft.basicsSaved ||
        changed(currentDraft.basics.toJson(), generatedDraft.basics.toJson()),
    charactersSaved:
        generatedDraft.charactersSaved ||
        changed(
          currentDraft.characters.map((item) => item.toJson()).toList(),
          generatedDraft.characters.map((item) => item.toJson()).toList(),
        ),
    locationsSaved:
        generatedDraft.locationsSaved ||
        changed(
          currentDraft.locations.map((item) => item.toJson()).toList(),
          generatedDraft.locations.map((item) => item.toJson()).toList(),
        ),
    openingSaved:
        generatedDraft.openingSaved ||
        changed(currentDraft.opening.toJson(), generatedDraft.opening.toJson()),
    storyEventsSaved:
        generatedDraft.storyEventsSaved ||
        changed(
          currentDraft.storyEvents.map((item) => item.toJson()).toList(),
          generatedDraft.storyEvents.map((item) => item.toJson()).toList(),
        ),
  );
}
