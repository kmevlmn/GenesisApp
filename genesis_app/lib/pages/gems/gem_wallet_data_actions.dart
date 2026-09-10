part of 'gem_wallet_page.dart';

extension _GemWalletDataActions on _GemWalletPageState {
  Future<void> _refreshAll({bool silent = false}) async {
    if (!silent) {
      _updateState(() => _primaryLoading = true);
    }
    final tasksFuture = _refreshTasks(silent: silent);
    await Future.wait<void>([
      _walletStore.refresh(),
      _refreshProducts(silent: silent),
    ]);
    if (!mounted) return;
    if (!silent) {
      _updateState(() => _primaryLoading = false);
    }
    await tasksFuture;
  }

  Future<void> _refreshTasksAndWallet() async {
    unawaited(_walletStore.refresh());
    await _refreshTasks(silent: true);
  }

  Future<void> _refreshProducts({bool silent = false}) async {
    final generation = ++_productsRequestGeneration;
    final future = _loadProducts();
    _updateState(() {
      _productsLoading = true;
      _productsError = null;
      if (!silent) _products = null;
    });
    try {
      final products = await future;
      if (!mounted || generation != _productsRequestGeneration) return;
      _updateState(() {
        _products = products;
        _productsError = null;
        _productsLoading = false;
      });
      _startStoreRecovery(products);
    } catch (error) {
      if (!mounted || generation != _productsRequestGeneration) return;
      _updateState(() {
        _productsError = error;
        _productsLoading = false;
      });
    }
  }

  Future<void> _refreshTasks({bool silent = false}) async {
    final generation = ++_tasksRequestGeneration;
    final future = _loadTasks();
    _updateState(() {
      _tasksLoading = true;
      _tasksError = null;
      if (!silent) _taskGroups = null;
    });
    try {
      final groups = await future;
      if (!mounted || generation != _tasksRequestGeneration) return;
      _updateState(() {
        _taskGroups = groups;
        _tasksError = null;
        _tasksLoading = false;
        _taskStatusOverrides.clear();
      });
    } catch (error) {
      if (!mounted || generation != _tasksRequestGeneration) return;
      _updateState(() {
        _tasksError = error;
        _tasksLoading = false;
      });
    }
  }

  Future<List<GemProduct>> _loadProducts() async {
    final loader = widget.productsLoader;
    if (loader != null) return loader(context);
    return (await AppServicesScope.read(
      context,
    ).api.v1.gem.products()).products;
  }

  Future<List<GemTaskGroup>> _loadTasks() async {
    final loader = widget.tasksLoader;
    if (loader != null) return loader(context);
    return (await AppServicesScope.read(context).api.v1.gem.tasks()).groups;
  }

  String _taskStatus(GemTask task) {
    return _taskStatusOverrides[task.taskCode] ?? task.status;
  }

  Future<GemTaskActionResult> _reportTask(String taskCode) {
    final reporter = widget.taskReporter;
    if (reporter != null) return reporter(taskCode);
    return AppServicesScope.read(context).api.v1.gem.reportTask(taskCode);
  }

  Future<GemTaskActionResult> _claimTask(String taskCode) {
    final claimer = widget.taskClaimer;
    if (claimer != null) return claimer(taskCode);
    return AppServicesScope.read(context).api.v1.gem.claimTask(taskCode);
  }

  Future<void> _handleTaskTap(GemTask task) async {
    final taskCode = task.taskCode.trim();
    if (taskCode.isEmpty || _loadingTaskCodes.contains(taskCode)) return;

    final status = _taskStatus(task);
    if (status == 'claimed') return;
    if (taskCode == dailyCheckInTaskCode) {
      if (status == 'in_progress' || status == 'claimable') {
        await _openDailyCheckInTask(task);
      }
      return;
    }

    if (status == 'claimable') {
      await _claimTaskReward(taskCode, rewardGemsCent: task.rewardGemsCent);
      return;
    }
    if (status != 'in_progress') return;

    switch (taskCode) {
      case 'create_first_worldo':
        await _openCreateWorld(taskCode);
        return;
      case 'launch_first_world':
        showGenesisToast(
          context,
          'Open a Worldo you like, then Launch your own world.',
        );
        return;
      case 'invite_friend':
        showGenesisToast(
          context,
          'Open a World, then tap Invite in the detail panel.',
        );
        return;
      case 'write_comment':
        showGenesisToast(
          context,
          'Open a Worldo you liked, then write a post in Discuss.',
        );
        return;
      case 'request_join_world':
        showGenesisToast(
          context,
          'Open a World you haven’t joined, then request to join it.',
        );
        return;
      case 'send_message':
        showGenesisToast(context, 'Send messages in your world.');
        return;
      case 'progress_world':
        showGenesisToast(
          context,
          'Open your playing World, then tap Tick Now.',
        );
        return;
      case 'discord_follow':
        await Future.wait<void>([_openDiscord(), _reportTaskAction(taskCode)]);
        return;
    }
  }

  Future<void> _openDailyCheckInTask(GemTask task) async {
    final taskCode = task.taskCode.trim();
    if (!_beginTaskAction(taskCode)) return;
    bool confirmed;
    try {
      confirmed = await showDailyCheckInDialog(
        context,
        status: _taskStatus(task) == 'claimable'
            ? DailyCheckInDialogStatus.claim
            : DailyCheckInDialogStatus.checkIn,
        rewardGemsCent: task.rewardGemsCent,
      );
    } finally {
      _endTaskAction(taskCode);
    }
    if (!mounted || !confirmed) return;
    // Read current status after the dialog; opening it must not claim a reward.
    switch (_taskStatus(task)) {
      case 'claimable':
        await _claimTaskReward(taskCode, rewardGemsCent: task.rewardGemsCent);
      case 'in_progress':
        await _reportTaskAction(taskCode, rewardGemsCent: task.rewardGemsCent);
    }
  }

  Future<void> _handleJoinUsRowTap(GemTask task) async {
    final taskCode = task.taskCode.trim();
    final shouldReport =
        taskCode.isNotEmpty &&
        _taskStatus(task) == 'in_progress' &&
        !_loadingTaskCodes.contains(taskCode);
    if (!shouldReport) {
      await _openDiscord();
      return;
    }
    await Future.wait<void>([_openDiscord(), _reportTaskAction(taskCode)]);
  }

  Future<void> _openDiscord() async {
    try {
      final launcher = widget.discordLauncher;
      final launched = launcher != null
          ? await launcher(_GemWalletPageState._discordUri)
          : await launchUrl(
              _GemWalletPageState._discordUri,
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

  Future<void> _openCreateWorld(String taskCode) async {
    if (!_beginTaskAction(taskCode)) return;
    try {
      await Navigator.of(context).pushNamed(RouteNames.create);
    } finally {
      _endTaskAction(taskCode);
    }
  }

  Future<void> _reportTaskAction(
    String taskCode, {
    int rewardGemsCent = dailyCheckInPreviewRewardCent,
  }) async {
    if (!_beginTaskAction(taskCode)) return;
    final isDailyCheckIn = taskCode == dailyCheckInTaskCode;
    var claimingDailyReward = false;
    try {
      var result = await _reportTask(taskCode);
      if (isDailyCheckIn && result.status == 'claimable') {
        claimingDailyReward = true;
        result = await _claimTask(taskCode);
      }
      if (!mounted) return;
      if (isDailyCheckIn && result.status != 'claimed') {
        _updateState(() => _taskStatusOverrides[taskCode] = result.status);
        showGenesisToast(
          context,
          claimingDailyReward ? 'Claim failed.' : 'Check in failed.',
        );
        return;
      }
      if (isDailyCheckIn && claimingDailyReward) {
        trackGemTaskClaimedIfNeeded(taskCode: taskCode, status: result.status);
      }
      _updateState(() => _taskStatusOverrides[taskCode] = result.status);
      if (isDailyCheckIn && mounted) {
        final successDialog = showDailyCheckInSuccessDialog(
          context,
          rewardGemsCent: rewardGemsCent,
        );
        unawaited(_refreshTasksAndWallet());
        await successDialog;
      } else {
        await _refreshTasksAndWallet();
      }
    } catch (_) {
      if (!mounted) return;
      final message = switch (taskCode) {
        'daily_checkin' =>
          claimingDailyReward ? 'Claim failed.' : 'Check in failed.',
        'discord_follow' => 'Follow failed.',
        _ => 'Task update failed.',
      };
      showGenesisToast(context, message);
    } finally {
      _endTaskAction(taskCode);
    }
  }

  Future<void> _claimTaskReward(
    String taskCode, {
    int rewardGemsCent = dailyCheckInPreviewRewardCent,
  }) async {
    if (!_beginTaskAction(taskCode)) return;
    try {
      final result = await _claimTask(taskCode);
      if (!mounted) return;
      if (result.status != 'claimed') {
        showGenesisToast(context, 'Claim failed.');
        return;
      }
      trackGemTaskClaimedIfNeeded(taskCode: taskCode, status: result.status);
      _updateState(() => _taskStatusOverrides[taskCode] = result.status);
      final successDialog = taskCode == dailyCheckInTaskCode
          ? showDailyCheckInSuccessDialog(
              context,
              rewardGemsCent: rewardGemsCent,
            )
          : showGemTaskSuccessDialog(
              context,
              title: 'Claim successful!',
              rewardGemsCent: rewardGemsCent,
            );
      unawaited(_refreshTasksAndWallet());
      await successDialog;
    } catch (_) {
      if (mounted) showGenesisToast(context, 'Claim failed.');
    } finally {
      _endTaskAction(taskCode);
    }
  }

  bool _beginTaskAction(String taskCode) {
    if (_loadingTaskCodes.contains(taskCode)) return false;
    _updateState(() => _loadingTaskCodes.add(taskCode));
    return true;
  }

  void _endTaskAction(String taskCode) {
    if (!mounted || !_loadingTaskCodes.contains(taskCode)) return;
    _updateState(() => _loadingTaskCodes.remove(taskCode));
  }

  GemWalletStore get _walletStore =>
      widget.walletStore ?? AppServicesScope.read(context).gemWallet;

  ValueListenable<GemWalletState> get _walletStateListenable =>
      widget.walletStore?.state ?? AppServicesScope.of(context).gemWallet.state;

  ValueListenable<BillingState> get _billingStateListenable =>
      _billingService?.state ?? _idleBillingState;
}
