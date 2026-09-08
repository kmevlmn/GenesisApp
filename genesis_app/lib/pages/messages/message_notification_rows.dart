part of 'message_category_list_page.dart';

class _NotificationListItem extends StatelessWidget {
  const _NotificationListItem({
    super.key,
    required this.item,
    required this.showUnreadDot,
    required this.followIsLoading,
    required this.followStateOverride,
    required this.onTap,
    required this.onToggleFollow,
  });

  final _NotificationItem item;
  final bool showUnreadDot;
  final bool followIsLoading;
  final bool? followStateOverride;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleFollow;

  @override
  Widget build(BuildContext context) {
    if (item.isFollowNotification) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            key: ValueKey('message-follow-row-${item.followUserUid}'),
            height: GenesisFollowUserListTile.itemExtent,
            child: GenesisFollowUserListTile(
              uid: item.followUserUid,
              displayName: item.followUserName,
              avatarUrl: item.senderAvatar,
              deleted: item.senderDeleted,
              isFollowed: followStateOverride ?? item.isFollowed,
              isLoading: followIsLoading,
              keyPrefix: 'message-follow',
              onToggleFollow: () =>
                  onToggleFollow(followStateOverride ?? item.isFollowed),
            ),
          ),
          if (showUnreadDot)
            const Positioned(
              right: -13,
              top: (GenesisFollowUserListTile.itemExtent - 7) / 2,
              child: _UnreadDot(),
            ),
        ],
      );
    }

    final content = InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: item.isJoinRequest || item.isJoinRequestReview
          ? _JoinRequestListItem(item: item)
          : _CommentNotificationListItem(item: item),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: content),
        const SizedBox(width: 10),
        SizedBox(
          width: 8,
          height: item.isFollowNotification
              ? GenesisFollowUserListTile.itemExtent
              : null,
          child: Align(
            alignment: item.isFollowNotification
                ? Alignment.center
                : Alignment.topCenter,
            child: showUnreadDot ? const _UnreadDot() : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('message-category-unread-dot'),
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: GenesisColors.redPrimary,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _CommentNotificationRow extends StatelessWidget {
  const _CommentNotificationRow({
    super.key,
    required this.item,
    required this.showUnreadDot,
    required this.onTap,
  });

  final _NotificationItem item;
  final bool showUnreadDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(right: showUnreadDot ? 18 : 0),
            child: _CommentNotificationListItem(item: item, isComments: true),
          ),
          if (showUnreadDot)
            const Positioned(right: 0, top: 5, child: _UnreadDot()),
        ],
      ),
    );
  }
}

class _JoinRequestListItem extends StatelessWidget {
  const _JoinRequestListItem({required this.item});

  final _NotificationItem item;

  @override
  Widget build(BuildContext context) {
    final isReview = item.isJoinRequestReview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Join request',
          style: TextStyle(
            color: GenesisColors.darkTextPrimary,
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        isReview
            ? _JoinRequestReviewSummaryText(item: item)
            : _JoinRequestSummaryText(item: item),
        const SizedBox(height: 8),
        _JoinRequestListStatusText(item: item),
      ],
    );
  }
}

class _JoinRequestReviewSummaryText extends StatelessWidget {
  const _JoinRequestReviewSummaryText({required this.item});

  final _NotificationItem item;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          color: GenesisColors.darkTextSecondary,
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w400,
        ),
        children: [
          const TextSpan(text: 'You request to join '),
          TextSpan(
            text: item.requestWorldSummaryName,
            style: _notificationNameStyle,
          ),
          if (item.requestWorldIdLabel.trim().isNotEmpty)
            TextSpan(text: ' (${item.requestWorldIdLabel})'),
        ],
      ),
    );
  }
}

class _JoinRequestSummaryText extends StatelessWidget {
  const _JoinRequestSummaryText({required this.item});

  final _NotificationItem item;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          color: GenesisColors.darkTextSecondary,
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w400,
        ),
        children: [
          TextSpan(text: item.requesterName, style: _notificationNameStyle),
          const TextSpan(text: ' request to join '),
          TextSpan(text: item.requestWorldName, style: _notificationNameStyle),
          if (item.requestWorldIdLabel.trim().isNotEmpty)
            TextSpan(text: ' (${item.requestWorldIdLabel})'),
        ],
      ),
    );
  }
}

class _JoinRequestListStatusText extends StatelessWidget {
  const _JoinRequestListStatusText({required this.item});

  final _NotificationItem item;

  @override
  Widget build(BuildContext context) {
    return Text(
      item.joinRequestListStatusText,
      style: TextStyle(
        color: item.joinRequestStatusColor,
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.item});

  final _NotificationItem item;

  @override
  Widget build(BuildContext context) {
    return Text(
      item.joinRequestStatusText,
      style: TextStyle(
        color: item.joinRequestStatusColor,
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _CommentNotificationListItem extends StatelessWidget {
  const _CommentNotificationListItem({
    required this.item,
    this.isComments = false,
  });

  final _NotificationItem item;
  final bool isComments;

  @override
  Widget build(BuildContext context) {
    final titleStyle = isComments
        ? _commentNotificationTitleStyle
        : _notificationTitleStyle;
    final bodyStyle = isComments
        ? _commentNotificationBodyStyle
        : _notificationBodyStyle;
    final metaStyle = isComments
        ? _commentNotificationMetaStyle
        : _notificationMetaStyle;
    final verticalGap = 8.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.titleText, style: titleStyle),
        if (item.bodyText.isNotEmpty) ...[
          SizedBox(height: verticalGap),
          Text(item.bodyText, style: bodyStyle),
        ],
        if (item.metaText.isNotEmpty) ...[
          SizedBox(height: verticalGap),
          Text(item.metaText, style: metaStyle),
        ],
      ],
    );
  }
}

const _notificationTitleStyle = TextStyle(
  color: GenesisColors.darkTextPrimary,
  fontSize: 14,
  height: 1.18,
  fontWeight: FontWeight.w600,
);

const _notificationBodyStyle = TextStyle(
  color: GenesisColors.darkTextSecondary,
  fontSize: 12,
  height: 1.25,
  fontWeight: FontWeight.w400,
);

const _notificationMetaStyle = TextStyle(
  color: GenesisColors.darkTextTertiary,
  fontSize: 12,
  height: 1.2,
  fontWeight: FontWeight.w400,
);

const _commentNotificationTitleStyle = TextStyle(
  color: GenesisColors.darkTextPrimary,
  fontSize: 14,
  height: 1.18,
  fontWeight: FontWeight.w600,
);

const _commentNotificationBodyStyle = TextStyle(
  color: GenesisColors.darkTextSecondary,
  fontSize: 12,
  height: 1.25,
  fontWeight: FontWeight.w400,
);

const _commentNotificationMetaStyle = TextStyle(
  color: GenesisColors.darkTextTertiary,
  fontSize: 12,
  height: 1.2,
  fontWeight: FontWeight.w400,
);

const _notificationNameStyle = TextStyle(color: GenesisColors.darkTextPrimary);
