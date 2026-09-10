import 'package:flutter/material.dart';

import '../../network/models/app_version_check.dart';
import '../../ui/genesis_ui.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../components/page_header.dart';
import 'package:flutter/services.dart';
import '../bootstrap/app_services_scope.dart';
import '../startup/app_startup_coordinator.dart';
import 'app_version_check_service.dart';

class ForceUpgradeGate extends StatefulWidget {
  const ForceUpgradeGate({super.key, required this.child});

  final Widget child;

  @override
  State<ForceUpgradeGate> createState() => _ForceUpgradeGateState();
}

class _ForceUpgradeGateState extends State<ForceUpgradeGate>
    with WidgetsBindingObserver {
  AppVersionCheckService? _checker;
  ValueNotifier<int>? _sessionRevision;
  AppVersionCheckResponse? _upgrade;
  Object? _lastError;
  bool _checking = false;
  bool _pendingCheck = false;
  bool _openingUrl = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppStartupCoordinator.postLaunchWorkAllowedListenable.addListener(
      _handlePostLaunchWorkAllowed,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestCheck());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServicesScope.of(context);
    _checker = services.appVersionCheck;
    final sessionRevision = services.sessionRevision;
    if (!identical(_sessionRevision, sessionRevision)) {
      _sessionRevision?.removeListener(_requestCheck);
      _sessionRevision = sessionRevision;
      sessionRevision.addListener(_requestCheck);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _requestCheck();
  }

  @override
  void dispose() {
    _sessionRevision?.removeListener(_requestCheck);
    AppStartupCoordinator.postLaunchWorkAllowedListenable.removeListener(
      _handlePostLaunchWorkAllowed,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handlePostLaunchWorkAllowed() {
    if (AppStartupCoordinator.isPostLaunchWorkAllowed) _requestCheck();
  }

  void _requestCheck() {
    if (!mounted) return;
    if (!AppStartupCoordinator.isPostLaunchWorkAllowed) return;
    if (_checking) {
      _pendingCheck = true;
      return;
    }
    _checking = true;
    _runCheck();
  }

  Future<void> _runCheck() async {
    final checker = _checker ?? AppServicesScope.read(context).appVersionCheck;
    AppVersionCheckResult result;
    try {
      result = await checker.check();
    } catch (error) {
      result = AppVersionCheckResult.failed(error);
    }
    if (!mounted) return;

    setState(() {
      _lastError = result.error;
      if (result.isForceUpgrade) {
        _upgrade = result.response;
      } else if (!result.failed || _upgrade == null) {
        _upgrade = null;
      }
    });

    _checking = false;
    if (_pendingCheck) {
      _pendingCheck = false;
      _requestCheck();
    }
  }

  Future<void> _openUpgradeUrl() async {
    final upgrade = _upgrade;
    if (upgrade == null || upgrade.updateUrl.isEmpty || _openingUrl) return;
    setState(() => _openingUrl = true);
    try {
      await AppServicesScope.read(
        context,
      ).externalUrlOpener.open(upgrade.updateUrl);
    } finally {
      if (mounted) setState(() => _openingUrl = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final upgrade = _upgrade;
    if (upgrade == null) return widget.child;

    return ForceUpgradePage(
      response: upgrade,
      isOpeningUrl: _openingUrl,
      hasCheckError: _lastError != null,
      onUpdate: upgrade.updateUrl.isEmpty ? null : _openUpgradeUrl,
    );
  }
}

class ForceUpgradePage extends StatelessWidget {
  const ForceUpgradePage({
    super.key,
    required this.response,
    required this.onUpdate,
    this.isOpeningUrl = false,
    this.hasCheckError = false,
    this.preview = false,
  });

  final AppVersionCheckResponse response;
  final VoidCallback? onUpdate;
  final bool isOpeningUrl;
  final bool hasCheckError;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final title = response.title.isEmpty ? 'Update required' : response.title;
    final content = response.content.isEmpty
        ? 'Please update to the latest version to continue using Worldo.'
        : response.content;
    final latestVersionName = response.latestVersionName;

    return GenesisDarkTheme(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: PopScope(
          canPop: preview,
          child: Scaffold(
            backgroundColor: GenesisColors.darkBackground,
            appBar: preview
                ? GenesisBackAppBar(
                    backgroundColor: GenesisColors.darkBackground,
                    foregroundColor: GenesisColors.darkTextPrimary,
                    systemOverlayStyle: SystemUiOverlayStyle.light,
                    pageName: '',
                    onBack: () => Navigator.of(context).pop(),
                  )
                : null,
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GenesisSpacing.pageWide,
                    vertical: GenesisSpacing.section,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.system_update_alt_rounded,
                          size: 48,
                          color: GenesisColors.redSecondary,
                        ),
                        const SizedBox(height: GenesisSpacing.section),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: GenesisTypography.pageTitle.copyWith(
                            color: GenesisColors.darkTextPrimary,
                          ),
                        ),
                        if (latestVersionName.isNotEmpty) ...[
                          const SizedBox(height: GenesisSpacing.md),
                          Text(
                            'Version $latestVersionName',
                            textAlign: TextAlign.center,
                            style: GenesisTypography.supporting.copyWith(
                              color: GenesisColors.darkTextTertiary,
                            ),
                          ),
                        ],
                        const SizedBox(height: GenesisSpacing.page),
                        Text(
                          content,
                          textAlign: TextAlign.center,
                          style: GenesisTypography.body.copyWith(
                            height: 1.45,
                            color: GenesisColors.darkTextSecondary,
                          ),
                        ),
                        if (hasCheckError) ...[
                          const SizedBox(height: GenesisSpacing.xl),
                          Text(
                            'Unable to refresh update status. Please update to continue.',
                            textAlign: TextAlign.center,
                            style: GenesisTypography.supporting.copyWith(
                              color: GenesisColors.darkTextTertiary,
                            ),
                          ),
                        ],
                        const SizedBox(height: GenesisSpacing.section),
                        GenesisPrimaryButton(
                          label: 'Update now',
                          onPressed: onUpdate,
                          isLoading: isOpeningUrl,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
