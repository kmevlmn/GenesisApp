part of 'developer_page.dart';

OverlayEntry? _worldUpdatePushPreviewEntry;
Timer? _worldUpdatePushPreviewTimer;

const List<WorldContentUpdateNotice> _singleWorldUpdatePushPreviewNotices = [
  WorldContentUpdateNotice(
    kind: WorldContentUpdateKind.location,
    entityId: 'developer-preview-location',
    name: 'New Harbor',
    targetLocationId: 'developer-preview-location',
    avatarUrl:
        'https://cdn-001.worldo.ai/app/uploads/20260705/'
        '2073569582257278976_800_1200.jpg?x-oss-process=image/format,webp',
    tickCount: 1,
    contextLabel: 'Azure Coast',
  ),
];

const List<WorldContentUpdateNotice> _multiWorldUpdatePushPreviewNotices = [
  WorldContentUpdateNotice(
    kind: WorldContentUpdateKind.location,
    entityId: 'developer-preview-location-1',
    name: 'New Harbor',
    targetLocationId: 'developer-preview-location-1',
    avatarUrl:
        'https://cdn-001.worldo.ai/app/uploads/20260705/'
        '2073569582257278976_800_1200.jpg?x-oss-process=image/format,webp',
    tickCount: 1,
    contextLabel: 'Azure Coast',
  ),
  WorldContentUpdateNotice(
    kind: WorldContentUpdateKind.location,
    entityId: 'developer-preview-location-2',
    name: 'Moonlit Market',
    targetLocationId: 'developer-preview-location-2',
    avatarUrl:
        'https://cdn-001.worldo.ai/app/uploads/20260705/'
        '2073569314962673664_800_1200.jpg?x-oss-process=image/format,webp',
    tickCount: 1,
    contextLabel: 'Old Quarter',
  ),
  WorldContentUpdateNotice(
    kind: WorldContentUpdateKind.character,
    entityId: 'developer-preview-character-1',
    name: 'New Wanderer',
    targetLocationId: 'developer-preview-location-1',
    avatarUrl:
        'https://cdn-001.worldo.ai/app/uploads/20260702/'
        '2072507310906806272_356_356.jpg?x-oss-process=image/format,webp',
    tickCount: 1,
    contextLabel: 'Heir to the Blackwood family and student council president.',
  ),
  WorldContentUpdateNotice(
    kind: WorldContentUpdateKind.character,
    entityId: 'developer-preview-character-2',
    name: 'Scarlet Keeper',
    targetLocationId: 'developer-preview-location-2',
    avatarUrl:
        'https://cdn-001.worldo.ai/app/uploads/20260702/'
        '2072508055576121344_356_356.jpg?x-oss-process=image/format,webp',
    tickCount: 1,
    contextLabel: 'Crimson guardian',
  ),
];

extension _DeveloperPreviews on _DeveloperPageContentState {
  Future<void> _showForceUpgradePreview() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (widget.dismissBeforePreview) {
      await widget.onDismissBeforePreview?.call();
    }
    if (!navigator.mounted) return;
    await navigator.push(
      GenesisDarkPageRoute<void>(
        builder: (previewContext) => ForceUpgradePage(
          preview: true,
          response: AppVersionCheckResponse.fromJson({
            'title': 'Update required',
            'content':
                'Please update to the latest version to continue using Worldo.',
            'latest_version_name': 'Preview',
          }),
          onUpdate: () => showGenesisToast(previewContext, 'Preview only'),
        ),
      ),
    );
  }

  Future<void> _showWorldUpdatePushPreview({required bool multiple}) async {
    final notices = multiple
        ? _multiWorldUpdatePushPreviewNotices
        : _singleWorldUpdatePushPreviewNotices;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (widget.dismissBeforePreview) {
      await widget.onDismissBeforePreview?.call();
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!navigator.mounted) return;
    final overlay = navigator.overlay;
    if (overlay == null) return;
    _removeWorldUpdatePushPreview();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => IgnorePointer(
        child: Stack(
          children: [
            WorldUpdatePushBannerQueue(
              top: MediaQuery.paddingOf(overlayContext).top + 8,
              revision: 1,
              notices: notices,
            ),
          ],
        ),
      ),
    );
    _worldUpdatePushPreviewEntry = entry;
    overlay.insert(entry);
    final queueDuration = Duration(
      milliseconds:
          (worldUpdatePushDisplayDuration.inMilliseconds +
              worldUpdatePushTransitionDuration.inMilliseconds) *
          notices.length,
    );
    final avatarPreloadBudget = Duration(
      milliseconds:
          worldUpdatePushAvatarPreloadTimeout.inMilliseconds *
          notices
              .where(
                (notice) =>
                    notice.kind == WorldContentUpdateKind.character &&
                    notice.avatarUrl.trim().isNotEmpty,
              )
              .length,
    );
    _worldUpdatePushPreviewTimer = Timer(
      queueDuration + avatarPreloadBudget + const Duration(seconds: 1),
      _removeWorldUpdatePushPreview,
    );
  }

  Future<void> _showCreatingWaitOverlayPreview() async {
    final api = AppServicesScope.read(context).api;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (widget.dismissBeforePreview) {
      await widget.onDismissBeforePreview?.call();
    }
    if (!navigator.mounted) return;
    final avatars = <GenesisGenerationWaitAvatar>[];
    try {
      final origins = await api.getOrigins(limit: 1);
      if (origins.data.isNotEmpty) {
        final origin = await api.getOrigin(origins.data.first.oid);
        avatars.addAll(
          origin.characters
              .where((c) => c.avatar.trim().isNotEmpty)
              .map(
                (c) => GenesisGenerationWaitAvatar(name: c.name, url: c.avatar),
              ),
        );
      }
    } catch (_) {
      if (navigator.mounted)
        showGenesisToast(
          navigator.context,
          'Could not load Worldo preview. Showing default preview.',
        );
    }
    if (!navigator.mounted) return;
    await showGeneralDialog<void>(
      context: navigator.context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return OriginGenerationWaitOverlay(
          avatars: avatars,
          onBarrierTap: () => Navigator.of(dialogContext).maybePop(),
          onBackPressed: () => Navigator.of(dialogContext).maybePop(),
        );
      },
    );
  }

  Future<void> _showGemPurchaseSheetPreview() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (widget.dismissBeforePreview) {
      await widget.onDismissBeforePreview?.call();
    }
    if (!navigator.mounted) return;
    final preview = _DeveloperGemPurchasePreview();
    try {
      await showGemPurchaseBottomSheet(
        navigator.context,
        alert: const GemBalanceAlert(
          kind: GemBalanceAlertKind.insufficient,
          balanceCent: 1200,
          message: 'Insufficient Gems',
        ),
        productsLoader: () async => preview.products,
        walletStore: preview.walletStore,
        billingService: preview.billing,
      );
    } finally {
      preview.dispose();
    }
  }

  Future<void> _showGemPurchaseOverlayPreview() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (widget.dismissBeforePreview) {
      await widget.onDismissBeforePreview?.call();
    }
    if (!navigator.mounted) return;
    await showGemBillingPurchaseOverlayPreview(navigator.context);
  }

  Future<void> _showDailyCheckInPreview() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (widget.dismissBeforePreview) {
      await widget.onDismissBeforePreview?.call();
    }
    if (!navigator.mounted) return;
    final checkedIn = await showDailyCheckInDialog(
      navigator.context,
      status: _dailyCheckInPreviewClaimed
          ? DailyCheckInDialogStatus.claimed
          : DailyCheckInDialogStatus.checkIn,
    );
    if (!checkedIn || !navigator.mounted) return;
    if (mounted) {
      _updateState(() => _dailyCheckInPreviewClaimed = true);
    }
    await showDailyCheckInSuccessDialog(navigator.context);
  }

  Widget _buildDeviceIdDiagnostics(DeviceIdDiagnostics? diagnostics) {
    final deviceId = _infoValue(diagnostics?.deviceId);
    if (diagnostics?.hasAndroidBreakdown != true) {
      return _DeveloperInfoSingleLineRow(title: 'Device ID', content: deviceId);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeveloperInfoSingleLineRow(
          title: 'ANDROID_ID',
          content: _infoValue(diagnostics?.androidId),
        ),
        const SizedBox(height: _DeveloperPageContentState._itemGap),
        _DeveloperInfoSingleLineRow(
          title: 'AAID',
          content: _infoValue(diagnostics?.aaid),
        ),
        const SizedBox(height: _DeveloperPageContentState._itemGap),
        _DeveloperInfoSingleLineRow(title: 'Device ID', content: deviceId),
      ],
    );
  }

  Future<_DeveloperAccountIdentity> _loadAccountIdentity() async {
    final services = AppServicesScope.read(context);
    final uid = (await services.sessionStore.readUid())?.trim() ?? '';
    final cachedUserInfo = await services.sessionStore.readUserInfo();
    return _DeveloperAccountIdentity(
      uid: uid,
      uuid: '${cachedUserInfo?['uuid'] ?? ''}'.trim(),
    );
  }

  Widget _buildAccountIdentityRows(
    AsyncSnapshot<_DeveloperAccountIdentity> snapshot,
  ) {
    final identity = snapshot.data;
    final loading = snapshot.connectionState != ConnectionState.done;
    final uuid = identity?.uuid ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeveloperInfoSingleLineRow(
          title: 'UID',
          content: loading ? 'Loading...' : _infoValue(identity?.uid),
        ),
        if (!loading && uuid.isNotEmpty) ...[
          const SizedBox(height: _DeveloperPageContentState._itemGap),
          _DeveloperInfoSingleLineRow(title: 'UUID', content: uuid),
        ],
      ],
    );
  }

  String _infoValue(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? 'unknown' : trimmed;
  }

  String _versionLabel(AppVersionInfo? versionInfo) {
    final versionName = versionInfo?.versionName.trim() ?? '';
    final versionCode = versionInfo?.versionCode.trim() ?? '';
    final base = AboutUsPage.versionLabel(
      versionName,
    ).replaceFirst(RegExp('^v'), '');
    return versionCode.isEmpty ? base : '$base/$versionCode';
  }

  String _formatAgentControlStatus(AgentControlStatus status) {
    final parts = <String>[status.label];
    final port = status.port;
    if (status.running && port != null) {
      parts.add('${status.host}:$port');
    }
    if (status.enabled) {
      parts.add(
        status.tokenConfigured ? 'token configured' : 'generated token',
      );
      final preview = status.tokenPreview;
      if (preview != null) parts.add(preview);
    }
    final error = status.lastError;
    if (error != null && error.trim().isNotEmpty) {
      parts.add(error);
    }
    return parts.join(' / ');
  }

  Widget _buildGemBalanceInfoRow() {
    final walletState = AppServicesScope.of(context).gemWallet.state;
    return ValueListenableBuilder<GemWalletState>(
      valueListenable: walletState,
      builder: (context, state, _) {
        final balanceCent = state.balanceCent;
        final content = balanceCent == null
            ? (state.isRefreshing ? 'Loading...' : '0.0')
            : formatGemCent(balanceCent);
        return _DeveloperInfoSingleLineRow(
          title: 'My Balance',
          content: content,
        );
      },
    );
  }
}

void _removeWorldUpdatePushPreview() {
  _worldUpdatePushPreviewTimer?.cancel();
  _worldUpdatePushPreviewTimer = null;
  final entry = _worldUpdatePushPreviewEntry;
  _worldUpdatePushPreviewEntry = null;
  if (entry?.mounted ?? false) entry!.remove();
}
