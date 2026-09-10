part of 'gem_wallet_page.dart';

String _gemTaskTitle(GemTask task) {
  return task.taskCode.trim() == 'progress_world' ? 'Run a Tick' : task.title;
}

String _gemTaskDescription(GemTask task) {
  return task.taskCode.trim() == 'progress_world'
      ? 'Open one of your playing Worlds and tap Tick Now.'
      : task.description;
}

class _GemWalletContent extends StatelessWidget {
  const _GemWalletContent({
    required this.products,
    required this.taskGroups,
    required this.productsLoading,
    required this.tasksLoading,
    required this.productsError,
    required this.tasksError,
    required this.walletStateListenable,
    required this.billingStateListenable,
    required this.onPurchase,
    required this.onRetryProducts,
    required this.onRetryTasks,
    required this.taskStatusFor,
    required this.isTaskLoading,
    required this.onTaskTap,
    required this.onJoinUsTap,
  });

  final List<GemProduct>? products;
  final List<GemTaskGroup>? taskGroups;
  final bool productsLoading;
  final bool tasksLoading;
  final Object? productsError;
  final Object? tasksError;
  final ValueListenable<GemWalletState> walletStateListenable;
  final ValueListenable<BillingState> billingStateListenable;
  final ValueChanged<GemProduct> onPurchase;
  final VoidCallback onRetryProducts;
  final VoidCallback onRetryTasks;
  final String Function(GemTask task) taskStatusFor;
  final bool Function(String taskCode) isTaskLoading;
  final ValueChanged<GemTask> onTaskTap;
  final ValueChanged<GemTask> onJoinUsTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
      children: [
        ValueListenableBuilder<GemWalletState>(
          valueListenable: walletStateListenable,
          builder: (context, walletState, _) {
            return GemPurchaseCatalogSection(
              balanceCent: walletState.balanceCent ?? 0,
              catalog: products == null
                  ? productsLoading || productsError == null
                        ? const GemProductGridSkeleton()
                        : GemPurchaseState(
                            message: 'Unable to load gem packs.',
                            onRetry: onRetryProducts,
                          )
                  : products!.isEmpty
                  ? const GemPurchaseState(
                      message: 'No gem packs available.',
                      height: 96,
                    )
                  : GemProductGrid(
                      products: products!,
                      billingStateListenable: billingStateListenable,
                      onPurchase: onPurchase,
                    ),
            );
          },
        ),
        const SizedBox(height: 26),
        if (taskGroups == null)
          _GemSectionStatePanel(
            isLoading: tasksLoading,
            hasError: tasksError != null,
            errorMessage: 'Unable to load gem tasks.',
            onRetry: onRetryTasks,
          )
        else
          for (final group in taskGroups!)
            if (group.tasks.isNotEmpty) ...[
              _TaskGroupSection(
                group: group,
                taskStatusFor: taskStatusFor,
                isTaskLoading: isTaskLoading,
                onTaskTap: onTaskTap,
                onJoinUsTap: onJoinUsTap,
              ),
              const SizedBox(height: 20),
            ],
      ],
    );
  }
}

class _TaskGroupSection extends StatelessWidget {
  const _TaskGroupSection({
    required this.group,
    required this.taskStatusFor,
    required this.isTaskLoading,
    required this.onTaskTap,
    required this.onJoinUsTap,
  });

  final GemTaskGroup group;
  final String Function(GemTask task) taskStatusFor;
  final bool Function(String taskCode) isTaskLoading;
  final ValueChanged<GemTask> onTaskTap;
  final ValueChanged<GemTask> onJoinUsTap;

  @override
  Widget build(BuildContext context) {
    final isJoinUs =
        group.groupCode == 'join_us' ||
        group.groupTitle.trim().toLowerCase() == 'join us';
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
        const SizedBox(height: 10),
        for (final task in group.tasks) ...[
          if (isJoinUs)
            _JoinUsTaskRow(
              task: task,
              status: taskStatusFor(task),
              isLoading: isTaskLoading(task.taskCode),
              onRowTap: () => onJoinUsTap(task),
              onButtonTap: () => onTaskTap(task),
            )
          else
            _TaskRow(
              task: task,
              status: taskStatusFor(task),
              isLoading: isTaskLoading(task.taskCode),
              onTap: () => onTaskTap(task),
            ),
          SizedBox(height: isJoinUs ? 10 : 12),
        ],
      ],
    );
  }
}

class _JoinUsTaskRow extends StatelessWidget {
  const _JoinUsTaskRow({
    required this.task,
    required this.status,
    required this.isLoading,
    required this.onRowTap,
    required this.onButtonTap,
  });

  final GemTask task;
  final String status;
  final bool isLoading;
  final VoidCallback onRowTap;
  final VoidCallback onButtonTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey<String>('gem-join-us-row-${task.taskCode}'),
      behavior: HitTestBehavior.opaque,
      onTap: onRowTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/custom-icons/svg/discord-clyde-white.svg',
              width: 14,
              height: 14,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _gemTaskTitle(task),
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
            const SizedBox(width: 8),
            SizedBox(
              key: ValueKey<String>('gem-task-reward-${task.taskCode}'),
              width: 96,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '+${formatWholeGemCent(task.rewardGemsCent)}',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 16 / 14,
                      fontWeight: FontWeight.w600,
                      color: GenesisColors.darkTextPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SvgPicture.asset(
                    gemIconAsset,
                    key: ValueKey<String>(
                      'gem-task-reward-icon-${task.taskCode}',
                    ),
                    width: gemSmallIconSize,
                    height: gemSmallIconSize,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _TaskActionButton(
              task: task,
              status: status,
              isLoading: isLoading,
              onTap: onButtonTap,
              width: 64,
              height: 24,
              borderRadius: 10,
              textHeight: 14 / 12,
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.status,
    required this.isLoading,
    required this.onTap,
  });

  final GemTask task;
  final String status;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey<String>('gem-task-row-${task.taskCode}'),
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: GenesisColors.darkCardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GenesisColors.darkCardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _gemTaskTitle(task),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 16 / 14,
                    fontWeight: FontWeight.w600,
                    color: GenesisColors.darkTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _gemTaskDescription(task),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 14 / 12,
                    fontWeight: FontWeight.w400,
                    color: GenesisColors.darkTextTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            key: ValueKey<String>('gem-task-reward-${task.taskCode}'),
            width: 96,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '+${formatWholeGemCent(task.rewardGemsCent)}',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 16 / 14,
                        fontWeight: FontWeight.w600,
                        color: GenesisColors.darkTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    SvgPicture.asset(
                      gemIconAsset,
                      key: ValueKey<String>(
                        'gem-task-reward-icon-${task.taskCode}',
                      ),
                      width: gemSmallIconSize,
                      height: gemSmallIconSize,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                _TaskActionButton(
                  task: task,
                  status: status,
                  isLoading: isLoading,
                  onTap: onTap,
                  width: 64,
                  height: 24,
                  borderRadius: 10,
                  textHeight: 14 / 12,
                  alignment: Alignment.centerRight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
