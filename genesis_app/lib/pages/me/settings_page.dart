import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/debug_floating_button_unlock.dart';
import '../../components/common/genesis_action_box.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/common/genesis_content_submission_dialog.dart';
import '../../components/login_provider_button.dart';
import '../../components/page_header.dart';
import '../../network/api_exception.dart';
import '../../platform/auth/auth_session.dart';
import '../../routers/app_router.dart';
import '../../network/genesis_api.dart';
import '../../network/json_utils.dart';
import '../../ui/genesis_ui.dart';
import '../../utils/display_name_formatter.dart';
import 'about_us_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const int _debugButtonUnlockTapCount = 10;
  static const double _logoutButtonWidthFactor = 0.7;
  static final Uri _discordUri = Uri.parse('https://discord.gg/wuKHk7cyX7');

  int _debugUnlockTapCount = 0;

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showGenesisActionBox<bool>(
      context: context,
      title: 'Log out of your account?',
      actions: const [
        GenesisActionBoxAction<bool>(label: 'Log out', value: true),
      ],
    );
    if (confirmed == true && context.mounted) {
      await _logout(context);
    }
  }

  Future<void> _openAccountPage(BuildContext context) async {
    final loggedOut = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AccountPage()));
    if (loggedOut == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openBlockedUsersPage(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const BlockedUsersPage()),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final services = AppServicesScope.read(context);
    await services.backendAuth.signOut();
    services.notifySessionChanged();
    if (!context.mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _showFeedbackDialog(BuildContext context) async {
    final api = AppServicesScope.read(context).api;
    await showGenesisContentSubmissionDialog(
      context: context,
      title: 'Feedback',
      contentInputKey: const ValueKey<String>('genesis-feedback-content-input'),
      successMessage: 'Feedback submitted',
      failureMessage: 'Feedback failed',
      onSubmit: (content) => api.v1.feedback.create(content: content),
    );
  }

  Future<void> _openDiscord() async {
    try {
      final launched = await launchUrl(
        _discordUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        showGenesisToast(context, 'Could not open Discord');
      }
    } catch (_) {
      if (mounted) {
        showGenesisToast(context, 'Could not open Discord');
      }
    }
  }

  void _handleDebugUnlockTap() {
    final nextCount = _debugUnlockTapCount + 1;
    if (nextCount < _debugButtonUnlockTapCount) {
      _debugUnlockTapCount = nextCount;
      return;
    }
    _debugUnlockTapCount = 0;
    unawaited(requestGenesisDebugFloatingButtonUnlock(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: GenesisBackAppBar(
        pageName: 'Settings',
        onBack: () => Navigator.of(context).maybePop(false),
        titleKey: const ValueKey<String>('settings-debug-title-unlock-area'),
        onTitleTap: _handleDebugUnlockTap,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutUsPage()),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'About us',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Color(0xFFB5B5B5),
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE7E7E7)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openAccountPage(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Account',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Color(0xFFB5B5B5),
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE7E7E7)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openBlockedUsersPage(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Blocked users',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Color(0xFFB5B5B5),
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE7E7E7)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showFeedbackDialog(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Feedback',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Color(0xFFB5B5B5),
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE7E7E7)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openDiscord,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Join Discord',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(width: 6),
                          SvgPicture.asset(
                            'assets/custom-icons/svg/discord-svgrepo-com.svg',
                            width: 28,
                            height: 28,
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        color: Color(0xFFB5B5B5),
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE7E7E7)),
              const Expanded(child: SizedBox.shrink()),
              GenesisPrimaryButton(
                label: 'Log out',
                width:
                    MediaQuery.sizeOf(context).width * _logoutButtonWidthFactor,
                onPressed: () => _confirmLogout(context),
                backgroundColor: const Color(0xFFE1E1E3),
                foregroundColor: Colors.black,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  late Future<List<_BlockedUserItem>> _future;
  final Set<String> _updatingUids = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _loadBlockedUsers();
  }

  Future<List<_BlockedUserItem>> _loadBlockedUsers() async {
    final response = await AppServicesScope.read(
      context,
    ).api.v1.user.blocks(pn: 1, rn: 100);
    final rawList = response['list'];
    final list = rawList is List ? rawList : const <Object?>[];
    return list
        .map(_BlockedUserItem.fromJson)
        .where((item) => item.uid.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final next = _loadBlockedUsers();
    setState(() => _future = next);
    await next;
  }

  Future<void> _toggleBlock(_BlockedUserItem item) async {
    if (item.uid.isEmpty || _updatingUids.contains(item.uid)) return;
    if (!item.isBlocked) {
      final confirmed = await _confirmBlockUser();
      if (!confirmed || !mounted) return;
    }
    setState(() => _updatingUids.add(item.uid));
    try {
      final api = AppServicesScope.read(context).api;
      if (item.isBlocked) {
        await api.v1.user.unblock(targetUid: item.uid);
      } else {
        await api.v1.user.block(targetUid: item.uid);
        await api.v1.report.create(
          targetType: 'user',
          targetId: item.uid,
          content: 'User blocked from blocked users settings.',
        );
      }
      if (!mounted) return;
      final wasBlocked = item.isBlocked;
      setState(() {
        item.isBlocked = !wasBlocked;
      });
      showGenesisToast(
        context,
        wasBlocked
            ? 'User unblocked'
            : 'User blocked. This content has been reported to Worldo team.',
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to update blocked user ${item.uid}: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      showGenesisToast(context, _blockedUserActionFailureMessage(error));
    } finally {
      if (mounted) {
        setState(() => _updatingUids.remove(item.uid));
      }
    }
  }

  Future<bool> _confirmBlockUser() async {
    final confirmed = await showGenesisActionBox<bool>(
      context: context,
      title: 'Block this user?',
      actions: const [
        GenesisActionBoxAction<bool>(
          label: 'Block',
          value: true,
          color: Color(0xFFFF2442),
        ),
      ],
    );
    return confirmed == true;
  }

  void _openProfile(_BlockedUserItem item) {
    if (item.uid.isEmpty) return;
    Navigator.of(
      context,
    ).pushNamed(RouteNames.userInfo, arguments: {'uid': item.uid});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GenesisBackAppBar(pageName: 'Blocked users'),
      body: SafeArea(
        child: FutureBuilder<List<_BlockedUserItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Load failed',
                        style: TextStyle(
                          color: Color(0xFF777777),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GenesisPrimaryButton(
                        label: 'Retry',
                        fullWidth: false,
                        width: 140,
                        onPressed: () {
                          setState(() => _future = _loadBlockedUsers());
                        },
                      ),
                    ],
                  ),
                ),
              );
            }

            final items = snapshot.data ?? const <_BlockedUserItem>[];
            if (items.isEmpty) {
              return GenesisRefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 120, 20, 24),
                  children: const [
                    Center(
                      child: Text(
                        'No blocked users yet.',
                        style: TextStyle(
                          color: Color(0xFF999999),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return GenesisRefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFE7E7E7)),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _BlockedUserTile(
                    item: item,
                    isUpdating: _updatingUids.contains(item.uid),
                    onTap: () => _openProfile(item),
                    onToggle: () => _toggleBlock(item),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BlockedUserItem {
  _BlockedUserItem({
    required this.uid,
    required this.displayName,
    required this.avatarUrl,
    required this.isBlocked,
  });

  factory _BlockedUserItem.fromJson(Object? value) {
    final map = asJsonMap(value);
    final user = asJsonMap(map['user']);
    final relation = map['relation'] == null
        ? const <String, dynamic>{}
        : asJsonMap(map['relation']);
    final uid = asString(user['uid']).trim();
    final name = asString(user['name'], fallback: uid).trim();
    return _BlockedUserItem(
      uid: uid,
      displayName: name.isEmpty
          ? formatUidForDisplay(uid, fallback: 'User')
          : name,
      avatarUrl: asResolvedImageUrl(user['avatar'], resolveAssetUrl),
      isBlocked: asBool(relation['is_blocked'], fallback: true),
    );
  }

  final String uid;
  final String displayName;
  final String avatarUrl;
  bool isBlocked;
}

class _BlockedUserTile extends StatelessWidget {
  const _BlockedUserTile({
    required this.item,
    required this.isUpdating,
    required this.onTap,
    required this.onToggle,
  });

  final _BlockedUserItem item;
  final bool isUpdating;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = item.isBlocked ? 'Unblock' : 'Block';
    final backgroundColor = item.isBlocked
        ? const Color(0xFFFF2442)
        : const Color(0xFFE5E5E5);
    final foregroundColor = item.isBlocked ? Colors.white : Colors.black;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            GenesisAvatar(
              name: item.displayName,
              url: item.avatarUrl,
              size: 54,
              borderRadius: 8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'UID: ${formatUidForDisplay(item.uid)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF777777),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GenesisPrimaryButton(
              label: label,
              width: 86,
              height: 28,
              fullWidth: false,
              padding: EdgeInsets.zero,
              fontSize: 12,
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              disabledBackgroundColor: backgroundColor,
              disabledForegroundColor: foregroundColor,
              isLoading: isUpdating,
              loadingSize: 15,
              minimumSize: const Size(86, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onPressed: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

String _blockedUserActionFailureMessage(Object error) {
  if (error is ApiException) {
    final message = error.message.trim().isEmpty
        ? 'Request failed'
        : error.message;
    return '$message[${error.code}]';
  }
  return 'Update failed';
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  static const double _deleteButtonWidthFactor = 0.7;

  IdentityProvider _provider = IdentityProvider.google;
  bool _hasReadAgreement = false;

  @override
  void initState() {
    super.initState();
    _loadProvider();
  }

  Future<void> _loadProvider() async {
    final userInfo = await AppServicesScope.read(
      context,
    ).sessionStore.readUserInfo();
    if (!mounted) return;
    final rawProvider = (userInfo?['login_provider'] ?? userInfo?['provider'])
        ?.toString()
        .trim()
        .toLowerCase();
    setState(() {
      _provider = rawProvider == IdentityProvider.apple.name
          ? IdentityProvider.apple
          : IdentityProvider.google;
    });
  }

  Future<void> _handleDeletePressed() async {
    if (!_hasReadAgreement) {
      showGenesisToast(context, 'Agree to our terms to continue.');
      return;
    }

    final confirmed = await showGenesisActionBox<bool>(
      context: context,
      title: 'Delete your account?',
      actions: const [
        GenesisActionBoxAction<bool>(label: 'Delete', value: true),
      ],
    );
    if (confirmed == true && mounted) {
      await _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    final services = AppServicesScope.read(context);
    await services.backendAuth.deleteAccount();
    services.notifySessionChanged();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(RouteNames.origin, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GenesisBackAppBar(pageName: 'Account'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                children: [
                  _CurrentLoginAccountCard(provider: _provider),
                  const SizedBox(height: 42),
                  const Text(
                    'Account Deletion Agreement',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'To ensure the security of your account, please read about '
                    'the consequences of account deletion.\n\n'
                    'Account deletion is not the same as logging out, and once '
                    'canceled, it cannot be undone. Your private data, including '
                    'created characters, search history, chat logs with any '
                    'characters, your favorites, your memories, interaction '
                    'data, and order records, will be irreversibly deleted and '
                    'cannot be recovered upon account deletion.',
                    style: TextStyle(
                      color: Color(0xFF777777),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'All unused Gems, including purchased and earned Gems, will '
                    'be permanently lost. By continuing, you voluntarily waive '
                    'them, and account deletion does not automatically entitle '
                    'you to a refund.',
                    style: TextStyle(
                      color: Color(0xFFFF2442),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => _hasReadAgreement = !_hasReadAgreement),
                    child: SizedBox(
                      width: double.infinity,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              value: _hasReadAgreement,
                              activeColor: const Color(0xFFFF4D4F),
                              checkColor: Colors.white,
                              onChanged: (value) => setState(
                                () => _hasReadAgreement = value ?? false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'I have read the Account Deletion Agreement',
                              style: TextStyle(
                                color: Color(0xFF777777),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GenesisPrimaryButton(
                    label: 'Delete',
                    width:
                        MediaQuery.sizeOf(context).width *
                        _deleteButtonWidthFactor,
                    onPressed: _handleDeletePressed,
                    backgroundColor: const Color(0xFFE1E1E3),
                    foregroundColor: _hasReadAgreement
                        ? Colors.black
                        : const Color(0xFF999999),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentLoginAccountCard extends StatelessWidget {
  const _CurrentLoginAccountCard({required this.provider});

  final IdentityProvider provider;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
        child: Column(
          children: [
            const Text(
              'Current login account:',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF777777),
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 18),
            LoginProviderIcon(provider: provider),
          ],
        ),
      ),
    );
  }
}
