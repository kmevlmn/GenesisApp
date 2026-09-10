import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/components/genesis_refresh_indicator.dart';
import '../../app/bootstrap/app_services_scope.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/components/genesis_primary_button.dart';
import '../../components/page_header.dart';
import '../../network/models/gem_model.dart';
import '../../utils/gem_amount.dart';
import '../../ui/tokens/genesis_colors.dart';

typedef GemModelCatalogLoader =
    Future<GemModelCatalog> Function(String worldId);
typedef GemModelSelectionHandler =
    Future<GemModelSelection> Function(String worldId, String modelCode);
typedef SelectedModelCodeCacheWriter = Future<void> Function(String modelCode);

class MemoryModelPage extends StatefulWidget {
  const MemoryModelPage({
    super.key,
    required this.worldId,
    this.catalogLoader,
    this.selectionHandler,
    this.selectedModelCodeCacheWriter,
  });

  final String worldId;
  final GemModelCatalogLoader? catalogLoader;
  final GemModelSelectionHandler? selectionHandler;
  final SelectedModelCodeCacheWriter? selectedModelCodeCacheWriter;

  @override
  State<MemoryModelPage> createState() => _MemoryModelPageState();
}

class _MemoryModelPageState extends State<MemoryModelPage> {
  GemModelCatalog? _catalog;
  Object? _error;
  bool _loading = false;
  bool _saving = false;
  String _pendingModelCode = '';
  int _loadGeneration = 0;
  String _trackedPageWorldId = '';

  @override
  void initState() {
    super.initState();
    _trackSwitchModelPage();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant MemoryModelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.worldId != widget.worldId) {
      _trackSwitchModelPage();
      unawaited(_refresh());
    }
  }

  void _trackSwitchModelPage() {
    final worldId = widget.worldId.trim();
    if (worldId.isEmpty || worldId == _trackedPageWorldId) return;
    _trackedPageWorldId = worldId;
    GenesisTelemetry.collectLog(
      actionType: 'pay_event',
      action: 'switch_model_page',
      object1: worldId,
    );
  }

  Future<GemModelCatalog> _loadCatalog() {
    final loader = widget.catalogLoader;
    if (loader != null) return loader(widget.worldId);
    return AppServicesScope.read(
      context,
    ).api.v1.gem.models(worldId: widget.worldId);
  }

  Future<GemModelSelection> _saveSelection(String modelCode) {
    final handler = widget.selectionHandler;
    if (handler != null) return handler(widget.worldId, modelCode);
    return AppServicesScope.read(
      context,
    ).api.v1.gem.selectModel(worldId: widget.worldId, modelCode: modelCode);
  }

  SelectedModelCodeCacheWriter? _resolveSelectedModelCodeCacheWriter() {
    final writer = widget.selectedModelCodeCacheWriter;
    if (writer != null) return writer;
    if (widget.selectionHandler != null) return null;
    final sessionStore = AppServicesScope.read(context).sessionStore;
    return (modelCode) async {
      final current = await sessionStore.readUserInfo();
      final title = _catalog?.titlesByCode()[modelCode] ?? '';
      await sessionStore.saveUserInfo(
        userInfoWithSelectedGemModel(
          current,
          selectedModelCode: modelCode,
          titlesByCode: title.isEmpty
              ? const <String, String>{}
              : <String, String>{modelCode: title},
        ),
      );
    };
  }

  Future<void> _refresh({bool preserveContent = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      if (!preserveContent) _catalog = null;
    });
    try {
      final catalog = await _loadCatalog();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _catalog = catalog;
        _pendingModelCode = catalog.selectedModelCode;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _selectModel(GemModel model) {
    final modelCode = model.modelCode.trim();
    if (modelCode.isEmpty || _saving || modelCode == _pendingModelCode) return;
    setState(() => _pendingModelCode = modelCode);
  }

  Future<void> _submitSelection() async {
    final modelCode = _pendingModelCode.trim();
    if (modelCode.isEmpty || _saving) return;
    final worldId = widget.worldId.trim();
    if (worldId.isNotEmpty) {
      GenesisTelemetry.collectLog(
        actionType: 'pay_event',
        action: 'switch_model_save',
        object1: worldId,
        object2: modelCode,
      );
    }
    final cacheWriter = _resolveSelectedModelCodeCacheWriter();
    setState(() => _saving = true);
    try {
      final result = await _saveSelection(modelCode);
      final responseModelCode = result.selectedModelCode.trim();
      final selectedModelCode = responseModelCode.isEmpty
          ? modelCode
          : responseModelCode;
      try {
        await cacheWriter?.call(selectedModelCode);
      } catch (error) {
        debugPrint('[GemModel] cache selected model failed: $error');
      }
      if (!mounted) return;
      setState(() {
        _catalog = _catalog?.copyWith(selectedModelCode: selectedModelCode);
        _pendingModelCode = selectedModelCode;
      });
      showGenesisToast(
        context,
        'Switched successfully',
        brightness: Brightness.dark,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pendingModelCode = _catalog?.selectedModelCode ?? '';
      });
      showGenesisToast(context, 'Switched failed', brightness: Brightness.dark);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _closePage() {
    Navigator.of(context).pop(_catalog?.selectedModelCode ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return GenesisDarkTheme(
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: GenesisColors.darkBackground,
          appBar: GenesisBackAppBar(
            backgroundColor: GenesisColors.darkBackground,
            foregroundColor: GenesisColors.darkTextPrimary,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            pageName: 'Model',
            titleStyle: const TextStyle(color: GenesisColors.darkTextPrimary),
            onBack: _closePage,
            actions: [
              _ModelSaveAction(
                saving: _saving,
                enabled:
                    !_loading &&
                    _pendingModelCode.trim().isNotEmpty &&
                    _pendingModelCode.trim() !=
                        (_catalog?.selectedModelCode.trim() ?? ''),
                onPressed: _submitSelection,
              ),
            ],
          ),
          body: SafeArea(child: _buildBody()),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final catalog = _catalog;
    if (catalog == null && _loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: GenesisLoadingIndicator(
            key: ValueKey('gem-model-page-loading'),
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (catalog == null && _error != null) {
      return _ModelLoadError(onRetry: () => unawaited(_refresh()));
    }
    if (catalog == null || catalog.groups.isEmpty) {
      return GenesisRefreshIndicator(
        onRefresh: () => _refresh(preserveContent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Center(
              child: Text(
                'No models available',
                style: TextStyle(
                  fontSize: 14,
                  color: GenesisColors.darkTextTertiary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GenesisRefreshIndicator(
      onRefresh: () => _refresh(preserveContent: true),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: catalog.groups.length,
        itemBuilder: (context, index) {
          final group = catalog.groups[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == catalog.groups.length - 1 ? 0 : 24,
            ),
            child: _GemModelGroupSection(
              group: group,
              selectedModelCode: _pendingModelCode,
              currentModelCode: catalog.selectedModelCode,
              enabled: !_saving,
              onModelTap: _selectModel,
            ),
          );
        },
      ),
    );
  }
}

class _ModelSaveAction extends StatelessWidget {
  const _ModelSaveAction({
    required this.saving,
    required this.enabled,
    required this.onPressed,
  });

  final bool saving;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Center(
        child: GenesisPrimaryButton(
          key: const ValueKey('gem-model-save'),
          label: 'Save',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          width: 64,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: GenesisColors.redPrimary,
          foregroundColor: GenesisColors.darkTextPrimary,
          isLoading: saving,
          onPressed: enabled && !saving ? onPressed : null,
        ),
      ),
    );
  }
}

class _GemModelGroupSection extends StatelessWidget {
  const _GemModelGroupSection({
    required this.group,
    required this.selectedModelCode,
    required this.currentModelCode,
    required this.enabled,
    required this.onModelTap,
  });

  final GemModelGroup group;
  final String selectedModelCode;
  final String currentModelCode;
  final bool enabled;
  final ValueChanged<GemModel> onModelTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.groupTitle,
          style: const TextStyle(
            fontSize: 16,
            height: 20 / 16,
            fontWeight: FontWeight.w600,
            color: GenesisColors.darkTextPrimary,
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < group.models.length; index += 1) ...[
          _GemModelTile(
            model: group.models[index],
            selected: group.models[index].modelCode == selectedModelCode,
            isCurrentModel:
                group.models[index].modelCode == currentModelCode.trim(),
            enabled: enabled,
            onTap: () => onModelTap(group.models[index]),
          ),
          if (index != group.models.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _GemModelTile extends StatelessWidget {
  const _GemModelTile({
    required this.model,
    required this.selected,
    required this.isCurrentModel,
    required this.enabled,
    required this.onTap,
  });

  final GemModel model;
  final bool selected;
  final bool isCurrentModel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? GenesisColors.redPrimary
        : GenesisColors.darkFaintFill;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        key: ValueKey<String>('gem-model-${model.modelCode}'),
        color: GenesisColors.darkRaisedBackground,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor, width: selected ? 1.2 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _GemModelTileContent(
                    model: model,
                    isCurrentModel: isCurrentModel,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _GemModelSelectionIndicator(selected: selected),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GemModelTileContent extends StatelessWidget {
  const _GemModelTileContent({
    required this.model,
    required this.isCurrentModel,
  });

  final GemModel model;
  final bool isCurrentModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isCurrentModel) ...[
              Container(
                key: ValueKey<String>('gem-model-current-${model.modelCode}'),
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: GenesisColors.brand,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                model.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 16 / 14,
                  fontWeight: FontWeight.w600,
                  color: GenesisColors.darkTextPrimary,
                ),
              ),
            ),
            for (final tag in model.tags) ...[
              const SizedBox(width: 5),
              _GemModelTag(label: tag),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              text: 'Estimated next message: ',
              children: [
                TextSpan(
                  text:
                      '${formatGemCent(model.estimatedNextMessageGemsCent)} gems',
                  style: const TextStyle(color: GenesisColors.redSecondary),
                ),
              ],
            ),
            key: ValueKey<String>('gem-model-estimate-${model.modelCode}'),
            style: const TextStyle(
              fontSize: 12,
              height: 12 / 12,
              fontWeight: FontWeight.w400,
              color: GenesisColors.darkTextSecondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          model.description,
          style: const TextStyle(
            fontSize: 12,
            height: 14 / 12,
            fontWeight: FontWeight.w400,
            color: GenesisColors.darkTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _GemModelTag extends StatelessWidget {
  const _GemModelTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final normalizedLabel = label.trim().toLowerCase();
    final displayLabel = normalizedLabel.isEmpty
        ? ''
        : '${normalizedLabel[0].toUpperCase()}${normalizedLabel.substring(1)}';
    final backgroundColor = normalizedLabel == 'hot'
        ? const Color(0xFFFF7A1A)
        : GenesisColors.redPrimary;
    return Container(
      key: ValueKey<String>('gem-model-tag-$normalizedLabel'),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        displayLabel,
        style: const TextStyle(
          fontSize: 10,
          height: 14 / 10,
          fontWeight: FontWeight.w600,
          color: GenesisColors.darkTextPrimary,
        ),
      ),
    );
  }
}

class _GemModelSelectionIndicator extends StatelessWidget {
  const _GemModelSelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? GenesisColors.redPrimary : Colors.transparent,
        border: Border.all(
          color: selected
              ? GenesisColors.redPrimary
              : GenesisColors.darkFaintFill,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? const Icon(
              Icons.check_rounded,
              size: 12,
              color: GenesisColors.darkTextPrimary,
            )
          : null,
    );
  }
}

class _ModelLoadError extends StatelessWidget {
  const _ModelLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Load failed',
            style: TextStyle(
              fontSize: 14,
              color: GenesisColors.darkTextTertiary,
            ),
          ),
          const SizedBox(height: 14),
          GenesisPrimaryButton(onPressed: onRetry, label: 'Retry'),
        ],
      ),
    );
  }
}
