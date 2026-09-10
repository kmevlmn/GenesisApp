part of 'developer_page.dart';

const Color _worldHistoryGetColor = Color(0xFF1565C0);
const Color _worldHistoryUpdateColor = Color(0xFF2E7D32);
const Color _worldHistoryDeleteColor = Color(0xFFB3261E);

class _DeveloperTestSectionPanel extends StatelessWidget {
  const _DeveloperTestSectionPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border.all(color: const Color(0xFFE1E1E3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _DeveloperWorldHistoryWatermarkPanel extends StatelessWidget {
  const _DeveloperWorldHistoryWatermarkPanel({
    required this.highWatermarkController,
    required this.lowWatermarkController,
    required this.busyAction,
    required this.settings,
    required this.onFetch,
    required this.onUpdate,
    required this.onDelete,
  });

  final TextEditingController highWatermarkController;
  final TextEditingController lowWatermarkController;
  final String? busyAction;
  final WorldHistorySettings? settings;
  final VoidCallback onFetch;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final enabled = busyAction == null;
    return _DeveloperTestSectionPanel(
      key: const ValueKey<String>('developer-world-history-watermark-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DeveloperSectionTitle('World History watermarks'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DeveloperWorldHistoryWatermarkInput(
                  fieldKey: const ValueKey<String>(
                    'developer-world-history-high-watermark-input',
                  ),
                  label: 'high_watermark · 20–30',
                  controller: highWatermarkController,
                  enabled: enabled,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DeveloperWorldHistoryWatermarkInput(
                  fieldKey: const ValueKey<String>(
                    'developer-world-history-low-watermark-input',
                  ),
                  label: 'low_watermark · 10–20',
                  controller: lowWatermarkController,
                  enabled: enabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DeveloperWorldHistoryReadOnlyValue(
            field: 'stored_high_watermark',
            value: settings == null ? '—' : '${settings!.storedHighWatermark}',
          ),
          const SizedBox(height: 6),
          _DeveloperWorldHistoryReadOnlyValue(
            field: 'stored_low_watermark',
            value: settings == null ? '—' : '${settings!.storedLowWatermark}',
          ),
          const SizedBox(height: 6),
          _DeveloperWorldHistoryReadOnlyValue(
            field: 'source',
            value: settings?.source.isNotEmpty == true ? settings!.source : '—',
          ),
          const SizedBox(height: 6),
          _DeveloperWorldHistoryReadOnlyValue(
            field: 'degraded',
            value: settings == null ? '—' : '${settings!.degraded}',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('developer-world-history-fetch'),
                  onPressed: enabled ? onFetch : null,
                  style: _worldHistoryActionButtonStyle(_worldHistoryGetColor),
                  child: _worldHistoryActionButtonContent(
                    label: 'Get',
                    loading: busyAction == 'fetch',
                    color: _worldHistoryGetColor,
                    loadingKey: const ValueKey<String>(
                      'developer-world-history-fetch-loading',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('developer-world-history-update'),
                  onPressed: enabled ? onUpdate : null,
                  style: _worldHistoryActionButtonStyle(
                    _worldHistoryUpdateColor,
                  ),
                  child: _worldHistoryActionButtonContent(
                    label: 'Update',
                    loading: busyAction == 'update',
                    color: _worldHistoryUpdateColor,
                    loadingKey: const ValueKey<String>(
                      'developer-world-history-update-loading',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('developer-world-history-delete'),
                  onPressed: enabled ? onDelete : null,
                  style: _worldHistoryActionButtonStyle(
                    _worldHistoryDeleteColor,
                  ),
                  child: _worldHistoryActionButtonContent(
                    label: 'Delete',
                    loading: busyAction == 'delete',
                    color: _worldHistoryDeleteColor,
                    loadingKey: const ValueKey<String>(
                      'developer-world-history-delete-loading',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _worldHistoryActionButtonContent({
  required String label,
  required bool loading,
  required Color color,
  required Key loadingKey,
}) {
  if (!loading) {
    return Text(label, maxLines: 1, softWrap: false);
  }
  return SizedBox.square(
    key: loadingKey,
    dimension: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}

ButtonStyle _worldHistoryActionButtonStyle(Color foregroundColor) {
  return OutlinedButton.styleFrom(
    foregroundColor: foregroundColor,
    backgroundColor: Colors.transparent,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    side: const BorderSide(color: Color(0xFFD0D0D4)),
  );
}

class _DeveloperWorldHistoryWatermarkInput extends StatelessWidget {
  const _DeveloperWorldHistoryWatermarkInput({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.enabled,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      cursorColor:
          Theme.of(context).textTheme.bodyLarge?.color ??
          const Color(0xFF111111),
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        floatingLabelStyle: const TextStyle(
          fontSize: 12,
          color: Color(0xFF555555),
          fontWeight: FontWeight.w600,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _DeveloperWorldHistoryReadOnlyValue extends StatelessWidget {
  const _DeveloperWorldHistoryReadOnlyValue({
    required this.field,
    required this.value,
  });

  final String field;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            field,
            style: const TextStyle(fontSize: 12, color: Color(0xFF555555)),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          key: ValueKey<String>('developer-world-history-$field-value'),
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DeveloperTelemetryUploadPanel extends StatelessWidget {
  const _DeveloperTelemetryUploadPanel({
    required this.state,
    required this.savingChannels,
    required this.onChanged,
  });

  final TelemetryUploadState state;
  final Set<TelemetryChannel> savingChannels;
  final void Function(TelemetryChannel channel, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    return _DeveloperTestSectionPanel(
      key: const ValueKey<String>('developer-telemetry-upload-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Telemetry Upload',
            style: TextStyle(
              fontSize: 15,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Automatic channels stay on. Others are for debugging.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF777777),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _telemetryStatusLabel(state),
            key: const ValueKey<String>('developer-telemetry-status'),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF777777),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE5E5E5)),
          _DeveloperTelemetryChannelSwitch(
            label: 'Collect',
            value: state.collectEnabled,
            automatic: state.automaticEnabled,
            enabled: !savingChannels.contains(TelemetryChannel.collect),
            switchKey: const ValueKey<String>(
              'developer-telemetry-collect-switch',
            ),
            onChanged: (value) => onChanged(TelemetryChannel.collect, value),
          ),
          _DeveloperTelemetryChannelSwitch(
            label: 'Firebase Analytics',
            value: state.analyticsEnabled,
            automatic: state.automaticEnabled,
            enabled: !savingChannels.contains(TelemetryChannel.analytics),
            switchKey: const ValueKey<String>(
              'developer-telemetry-analytics-switch',
            ),
            onChanged: (value) => onChanged(TelemetryChannel.analytics, value),
          ),
          _DeveloperTelemetryChannelSwitch(
            label: 'Firebase Performance',
            value: state.performanceEnabled,
            automatic: state.isReleaseBuild && state.isProductionFlavor,
            enabled: !savingChannels.contains(TelemetryChannel.performance),
            switchKey: const ValueKey<String>(
              'developer-telemetry-performance-switch',
            ),
            onChanged: (value) =>
                onChanged(TelemetryChannel.performance, value),
          ),
          _DeveloperTelemetryChannelSwitch(
            label: 'Firebase Crashlytics',
            value: state.crashlyticsEnabled,
            automatic: state.automaticEnabled,
            enabled: !savingChannels.contains(TelemetryChannel.crashlytics),
            switchKey: const ValueKey<String>(
              'developer-telemetry-crashlytics-switch',
            ),
            showDivider: false,
            onChanged: (value) =>
                onChanged(TelemetryChannel.crashlytics, value),
          ),
        ],
      ),
    );
  }
}

class _DeveloperTelemetryChannelSwitch extends StatelessWidget {
  const _DeveloperTelemetryChannelSwitch({
    required this.label,
    required this.value,
    required this.automatic,
    required this.enabled,
    required this.switchKey,
    required this.onChanged,
    this.showDivider = true,
  });

  final String label;
  final bool value;
  final bool automatic;
  final bool enabled;
  final Key switchKey;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: automatic ? 60 : 46,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (automatic)
                      const Text(
                        'On automatically',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777777),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                height: 32,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Switch(
                    key: switchKey,
                    value: value,
                    onChanged: enabled && !automatic ? onChanged : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, color: Color(0xFFEDEDED)),
      ],
    );
  }
}

class _DeveloperToggleRow extends StatelessWidget {
  const _DeveloperToggleRow({
    required this.sectionTitle,
    required this.label,
    required this.value,
    required this.enabled,
    required this.switchKey,
    required this.onChanged,
  });

  final String sectionTitle;
  final String label;
  final bool value;
  final bool enabled;
  final Key switchKey;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DeveloperSectionTitle(sectionTitle),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          height: 32,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Switch(
              key: switchKey,
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeveloperSliderControl extends StatelessWidget {
  const _DeveloperSliderControl({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.sliderKey,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Key sliderKey;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              valueLabel,
              style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
            ),
          ],
        ),
        Slider(
          key: sliderKey,
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _DeveloperGemPurchasePreview {
  _DeveloperGemPurchasePreview()
    : walletStore = GemWalletStore(
        loadWallet: () async => const GemWallet(balanceCent: 1200),
        readUid: () async => 'developer_preview_user',
      );

  final GemWalletStore walletStore;
  final _DeveloperPreviewBillingService billing =
      _DeveloperPreviewBillingService();

  List<GemProduct> get products => const <GemProduct>[
    GemProduct(
      productId: 'gem_pack_500',
      appleProductId: 'worldo.gems.500',
      googleProductId: 'worldo.gems.500',
      baseGemsCent: 50000,
      bonusGemsCent: 0,
      priceCurrencyCode: 'USD',
      priceAmount: 149,
      canPurchase: true,
      activityType: 'new_user',
      activityText: 'New User',
      activityColor: '#E85C39',
    ),
    GemProduct(
      productId: 'gem_pack_1100',
      appleProductId: 'worldo.gems.1100',
      googleProductId: 'worldo.gems.1100',
      baseGemsCent: 100000,
      bonusGemsCent: 10000,
      priceCurrencyCode: 'USD',
      priceAmount: 590,
      canPurchase: true,
      activityType: 'first_top_up',
      activityText: 'First Top-up',
      activityColor: '#B53B52',
    ),
    GemProduct(
      productId: 'gem_pack_4400',
      appleProductId: 'worldo.gems.4400',
      googleProductId: 'worldo.gems.4400',
      baseGemsCent: 400000,
      bonusGemsCent: 40000,
      priceCurrencyCode: 'USD',
      priceAmount: 1990,
      canPurchase: true,
      activityType: 'first_top_up',
      activityText: 'First Top-up',
      activityColor: '#B53B52',
    ),
    GemProduct(
      productId: 'gem_pack_8800',
      appleProductId: 'worldo.gems.8800',
      googleProductId: 'worldo.gems.8800',
      baseGemsCent: 800000,
      bonusGemsCent: 80000,
      priceCurrencyCode: 'USD',
      priceAmount: 3890,
      canPurchase: true,
      activityType: 'first_top_up',
      activityText: 'First Top-up',
      activityColor: '#B53B52',
    ),
    GemProduct(
      productId: 'gem_pack_16500',
      appleProductId: 'worldo.gems.16500',
      googleProductId: 'worldo.gems.16500',
      baseGemsCent: 1500000,
      bonusGemsCent: 150000,
      priceCurrencyCode: 'USD',
      priceAmount: 6990,
      canPurchase: true,
      activityType: 'first_top_up',
      activityText: 'First Top-up',
      activityColor: '#B53B52',
    ),
    GemProduct(
      productId: 'gem_pack_55000',
      appleProductId: 'worldo.gems.55000',
      googleProductId: 'worldo.gems.55000',
      baseGemsCent: 5000000,
      bonusGemsCent: 500000,
      priceCurrencyCode: 'USD',
      priceAmount: 19990,
      canPurchase: true,
      activityType: 'first_top_up',
      activityText: 'First Top-up',
      activityColor: '#B53B52',
    ),
  ];

  void dispose() {
    walletStore.dispose();
    billing.dispose();
  }
}

class _DeveloperPreviewBillingService implements BillingService {
  final ValueNotifier<BillingState> _state = ValueNotifier<BillingState>(
    BillingState(storeAvailable: true),
  );
  final StreamController<BillingUiEvent> _events =
      StreamController<BillingUiEvent>.broadcast();
  bool _disposed = false;

  @override
  Stream<BillingUiEvent> get events => _events.stream;

  @override
  ValueListenable<BillingState> get state => _state;

  @override
  Future<void> start() async {}

  @override
  Future<void> purchaseGem(
    GemProduct product, {
    BillingPurchaseSource source = BillingPurchaseSource.buyGemsPage,
    String payTrackId = '',
  }) async {
    if (_disposed) return;
    if (_state.value.hasBusyPurchase) return;
    _state.value = BillingState(
      storeAvailable: true,
      busyProductIds: <String>{product.productId},
    );
    _events.add(
      BillingUiEvent(
        kind: BillingUiEventKind.processing,
        productId: product.productId,
        attemptId: 'developer_preview',
        message: 'Purchasing Gems',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (_disposed) return;
    _state.value = BillingState(storeAvailable: true);
    _events.add(
      BillingUiEvent(
        kind: BillingUiEventKind.success,
        productId: product.productId,
        attemptId: 'developer_preview',
        message: 'Purchase successful!',
        grantedGemsCent: product.totalGemsCent,
      ),
    );
  }

  @override
  Future<void> recover(BillingRecoverySource source) async {}

  @override
  Future<bool> recoverStorePurchases({
    List<GemProduct>? productCatalog,
  }) async => true;

  @override
  void resetForSession() {}

  @override
  void dispose() {
    _disposed = true;
    _state.dispose();
    _events.close();
  }
}

class _DeveloperAccountIdentity {
  const _DeveloperAccountIdentity({required this.uid, required this.uuid});

  final String uid;
  final String uuid;
}

class _DeveloperSectionTitle extends StatelessWidget {
  const _DeveloperSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        color: Colors.black,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );
  }
}

class _DeveloperVersionField extends StatelessWidget {
  const _DeveloperVersionField({
    super.key,
    required this.label,
    required this.controller,
    required this.enabled,
    this.digitsOnly = false,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool digitsOnly;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      cursorColor: Colors.black,
      keyboardType: digitsOnly ? TextInputType.number : TextInputType.text,
      inputFormatters: digitsOnly
          ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
          : null,
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontSize: 14, color: Colors.black),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _DeveloperEndpointHeader extends StatelessWidget {
  const _DeveloperEndpointHeader({
    required this.isTestEnvironment,
    required this.enabled,
    required this.onPressed,
  });

  final bool isTestEnvironment;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final actionText = isTestEnvironment
        ? 'Switch to production'
        : 'Switch to test';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(child: _DeveloperSectionTitle('Endpoint overrides')),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                actionText,
                textAlign: TextAlign.right,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? Colors.black : const Color(0xFFA8A8AD),
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DeveloperEndpointField extends StatelessWidget {
  const _DeveloperEndpointField({
    super.key,
    required this.label,
    required this.scheme,
    required this.hintText,
    required this.controller,
  });

  final String label;
  final String scheme;
  final String hintText;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final host = controller.text.trim().isEmpty
        ? hintText
        : controller.text.trim();
    final displayText = '$scheme$host';
    return _DeveloperInfoSingleLineRow(title: label, content: displayText);
  }
}

class _DeveloperInfoSingleLineRow extends StatelessWidget {
  const _DeveloperInfoSingleLineRow({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  static const double _titleWidth = 104;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _titleWidth,
          child: Text(
            '$title:',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _copyContent(context),
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                content,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyContent(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;
    showGenesisToast(context, 'Copied');
  }
}

class _DeveloperInfoRow extends StatelessWidget {
  const _DeveloperInfoRow({required this.title, required this.content});

  final String title;
  final String content;

  static const double _titleWidth = 104;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _titleWidth,
          child: Text(
            '$title:',
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _copyContent(context),
            child: Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyContent(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;
    showGenesisToast(context, 'Copied');
  }
}

class _DeveloperInfoBlock extends StatelessWidget {
  const _DeveloperInfoBlock({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _copyContent(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$title:',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF666666),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyContent(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;
    showGenesisToast(context, 'Copied');
  }
}
