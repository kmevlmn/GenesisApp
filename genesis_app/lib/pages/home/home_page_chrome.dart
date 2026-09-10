part of 'home_page.dart';

class _HomeScaffold extends StatelessWidget {
  const _HomeScaffold({
    required this.activationListenable,
    required this.reselectionListenable,
    required this.isActiveListenable,
    required this.isFirstPageViewReported,
    required this.onFirstPageViewReady,
    required this.onOpenWorldo,
    required this.networkRequestsAllowed,
    required this.keepInitialNetworkFailureLoading,
    required this.initialRequestMetricWindow,
    required this.localRestoreTimeout,
    required this.initialMyWorldsRenderOperation,
    required this.initialMyWorldsRequestAttempt,
    this.initialMyWorldsData,
    this.myWorldsCacheLoader,
  });

  final ValueListenable<int>? activationListenable;
  final ValueListenable<int>? reselectionListenable;
  final ValueListenable<bool>? isActiveListenable;
  final bool Function(String action)? isFirstPageViewReported;
  final void Function(String action)? onFirstPageViewReady;
  final VoidCallback? onOpenWorldo;
  final ValueListenable<bool> networkRequestsAllowed;
  final bool keepInitialNetworkFailureLoading;
  final Duration initialRequestMetricWindow;
  final Duration localRestoreTimeout;
  final FirebasePerformanceOperation? initialMyWorldsRenderOperation;
  final int initialMyWorldsRequestAttempt;
  final Map<String, dynamic>? initialMyWorldsData;
  final HomeMyWorldsCacheLoader? myWorldsCacheLoader;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: [
          const _HomeHeader(),
          Expanded(
            child: _MyWorldFeed(
              index: 0,
              activationListenable: activationListenable,
              reselectionListenable: reselectionListenable,
              isActiveListenable: isActiveListenable,
              isFirstPageViewReported: isFirstPageViewReported,
              onFirstPageViewReady: onFirstPageViewReady,
              onOpenWorldo: onOpenWorldo,
              networkRequestsAllowed: networkRequestsAllowed,
              keepInitialNetworkFailureLoading:
                  keepInitialNetworkFailureLoading,
              initialRequestMetricWindow: initialRequestMetricWindow,
              localRestoreTimeout: localRestoreTimeout,
              myWorldsCacheLoader: myWorldsCacheLoader,
              initialPageData: initialMyWorldsData,
              initialPageRenderOperation: initialMyWorldsRenderOperation,
              initialPageRequestAttempt: initialMyWorldsRequestAttempt,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return GenesisTopSafeArea(
      backgroundColor: GenesisColors.darkBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: kGenesisTopBarHeight + 4,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: kGenesisTopBarHeight,
              child: Transform.translate(
                offset: const Offset(0, 5),
                child: Row(
                  children: [
                    const _HomeGemWalletEntry(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SearchBarPlaceholder(
                        backgroundColor: GenesisColors.darkFaintFill,
                        borderColor: null,
                        iconColor: GenesisColors.darkTextSecondary,
                        onTap: () {
                          Navigator.of(context).pushNamed(RouteNames.search);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeGemWalletEntry extends StatelessWidget {
  const _HomeGemWalletEntry();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Membership',
      child: GestureDetector(
        key: const ValueKey<String>('home-gem-wallet-entry'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final navigator = Navigator.of(context);
          navigator.pushNamed(RouteNames.gemWallet, arguments: 'subscription');
        },
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: SizedBox(
              key: const ValueKey<String>('home-gem-wallet-icon'),
              width: 36,
              height: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: proGold, width: 0.8),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF841A32),
                      Color(0xFF590C20),
                      Color(0xFF3C0716),
                    ],
                    stops: [0, 0.55, 1],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SvgPicture.asset(
                    proCrownFilledIconAsset,
                    key: const ValueKey<String>('home-gem-wallet-artwork'),
                    fit: BoxFit.contain,
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
