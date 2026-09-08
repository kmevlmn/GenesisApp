part of 'message_category_list_page.dart';

class _NotificationItem {
  const _NotificationItem({
    required this.id,
    required this.block,
    required this.type,
    required this.senderName,
    required this.senderUid,
    required this.senderAvatar,
    this.senderDeleted = false,
    required this.bizId,
    this.worldDeleted = false,
    this.originDeleted = false,
    required this.objId,
    required this.rootDiscussId,
    required this.content,
    required this.worldName,
    required this.originName,
    required this.commentText,
    required this.isFollowed,
    required this.isRead,
    required this.createdAt,
    required this.approvalStatus,
  });

  factory _NotificationItem.fromJson(Map<String, dynamic> json) {
    final sender = _optionalJsonMap(json['sender']);
    final user = _optionalJsonMap(json['user']);
    final relation = _optionalJsonMap(json['relation']);
    final comment = _optionalJsonMap(json['comment']);
    final reply = _optionalJsonMap(json['reply']);
    final target = _optionalJsonMap(json['target']);
    final type = asString(json['notice_type']);
    final block = asString(json['notice_block']);
    final content = asString(
      json['content'],
      fallback: asString(json['message'], fallback: 'New message'),
    );
    final bizId = asString(
      json['biz_id'],
      fallback: asString(json['world_id']),
    );
    final isWorldApply =
        block == 'world_apply' || type.startsWith('world_apply');
    final worldName = _firstNonEmpty([
      if (isWorldApply) asString(json['biz_name']),
      asString(json['world_name']),
      _mapString(json, 'world_title'),
      _mapString(json, 'target_world_name'),
      _mapString(_optionalJsonMap(json['world']), 'world_name'),
      _mapString(_optionalJsonMap(json['world']), 'name'),
      _mapString(_optionalJsonMap(json['target']), 'world_name'),
      _mapString(_optionalJsonMap(json['target']), 'name'),
      _extractWorldNameFromJoinContent(content),
    ]);
    final originName = _firstNonEmpty([
      asString(json['origin_name']),
      _mapString(json, 'biz_name'),
      _mapString(_optionalJsonMap(json['origin']), 'origin_name'),
      _mapString(_optionalJsonMap(json['origin']), 'name'),
      _mapString(_optionalJsonMap(json['target']), 'origin_name'),
      _mapString(_optionalJsonMap(json['target']), 'name'),
    ]);
    return _NotificationItem(
      id: asString(json['notification_id'], fallback: asString(json['id'])),
      block: block,
      type: type,
      senderName: _firstNonEmpty([
        _mapString(sender, 'name'),
        _mapString(sender, 'username'),
        _mapString(sender, 'nick_name'),
        _mapString(user, 'name'),
        _mapString(user, 'display_name'),
        _mapString(user, 'nickname'),
        asString(json['sender_name']),
      ]),
      senderUid: _firstNonEmpty([
        _mapString(sender, 'uid'),
        _mapString(sender, 'user_id'),
        _mapString(user, 'uid'),
        _mapString(user, 'target_user_id'),
        asString(json['sender_uid']),
        asString(json['applicant_uid']),
      ]),
      senderAvatar: asImageUrl(
        _firstNonNull([
          sender?['avatar'],
          sender?['avatar_url'],
          user?['avatar'],
          user?['avatar_url'],
          json['avatar'],
          json['avatar_url'],
        ]),
      ),
      senderDeleted: entityDeleted(
        sender?['deleted'],
        fallback:
            user?['deleted'] ?? json['sender_deleted'] ?? json['user_deleted'],
      ),
      bizId: bizId,
      worldDeleted: entityDeleted(
        json['world_deleted'],
        fallback:
            _optionalJsonMap(json['world'])?['world_deleted'] ??
            _optionalJsonMap(json['world'])?['deleted'],
      ),
      originDeleted: entityDeleted(
        json['origin_deleted'],
        fallback:
            _optionalJsonMap(json['origin'])?['origin_deleted'] ??
            _optionalJsonMap(json['origin'])?['deleted'] ??
            _optionalJsonMap(json['target'])?['origin_deleted'] ??
            _optionalJsonMap(json['target'])?['deleted'],
      ),
      objId: _firstNonEmpty([
        asString(json['obj_id']),
        asString(json['apply_id']),
        asString(json['discuss_id']),
        asString(json['root_discuss_id']),
      ]),
      rootDiscussId: _firstNonEmpty([
        asString(json['root_discuss_id']),
        _mapString(comment, 'root_discuss_id'),
        _mapString(reply, 'root_discuss_id'),
        _mapString(target, 'root_discuss_id'),
        asString(json['discuss_id']),
        asString(json['obj_id']),
      ]),
      content: content,
      worldName: worldName,
      originName: originName,
      commentText: _firstNonEmpty([
        asString(json['comment_content']),
        asString(json['comment_text']),
        asString(json['discuss_content']),
        asString(json['target_content']),
        asString(json['target_text']),
        _mapString(comment, 'content'),
        _mapString(reply, 'content'),
        _mapString(target, 'comment_content'),
        _mapString(target, 'content'),
        asString(json['text']),
        _extractCommentBodyFromContent(content),
        content,
      ]),
      isFollowed: json.containsKey('is_followed')
          ? asBool(json['is_followed'])
          : _relationIsFollowed(relation) ||
                _relationIsFollowed(user) ||
                _relationIsFollowed(json),
      isRead: asBool(json['is_read']),
      createdAt: asDateTime(json['created_at']),
      approvalStatus: _approvalStatusFromJson(json),
    );
  }

  final String id;
  final String block;
  final String type;
  final String senderName;
  final String senderUid;
  final String senderAvatar;
  final bool senderDeleted;
  final String bizId;
  final bool worldDeleted;
  final bool originDeleted;
  final String objId;
  final String rootDiscussId;
  final String content;
  final String worldName;
  final String originName;
  final String commentText;
  final bool isFollowed;
  final bool isRead;
  final DateTime? createdAt;
  final _JoinRequestApprovalStatus? approvalStatus;

  _NotificationItem copyWith({
    bool? isRead,
    bool? worldDeleted,
    _JoinRequestApprovalStatus? approvalStatus,
  }) {
    return _NotificationItem(
      id: id,
      block: block,
      type: type,
      senderName: senderName,
      senderUid: senderUid,
      senderAvatar: senderAvatar,
      senderDeleted: senderDeleted,
      bizId: bizId,
      worldDeleted: worldDeleted ?? this.worldDeleted,
      originDeleted: originDeleted,
      objId: objId,
      rootDiscussId: rootDiscussId,
      content: content,
      worldName: worldName,
      originName: originName,
      commentText: commentText,
      isFollowed: isFollowed,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      approvalStatus: approvalStatus ?? this.approvalStatus,
    );
  }

  bool get isJoinRequestReview => type == 'world_apply_review';

  bool get isJoinRequest {
    if (isJoinRequestReview) return false;
    return type == 'world_apply' || block == 'world_apply';
  }

  bool get isFollowNotification => block == 'follow' || type == 'follow';

  bool get isDiscussNotification =>
      block == 'interaction' || type.startsWith('discuss_');

  String get applyId => objId;

  String get senderDisplayName {
    if (senderDeleted) return deletedEntityDisplayText;
    return senderName.isEmpty ? 'Someone' : formatUidForDisplay(senderName);
  }

  String get requesterName {
    if (senderDeleted) return deletedEntityDisplayText;
    if (senderName.isNotEmpty) return senderName;
    return _firstNonEmpty([
      _extractRequesterNameFromJoinContent(content),
      'Someone',
    ]);
  }

  String get requestWorldName {
    if (worldDeleted) return deletedEntityDisplayText;
    final cleanWorldName = worldName.trim();
    final cleanBizId = bizId.trim();
    if (cleanWorldName.isEmpty || cleanWorldName == cleanBizId) {
      return cleanBizId;
    }
    return cleanWorldName;
  }

  String get requestWorldSummaryName {
    if (worldDeleted) return deletedEntityDisplayText;
    final cleanWorldName = worldName.trim();
    final cleanBizId = bizId.trim();
    if (cleanWorldName.isEmpty || cleanWorldName == cleanBizId) {
      return cleanBizId.isEmpty ? 'this world' : cleanBizId;
    }
    return cleanWorldName;
  }

  String get requestWorldIdLabel {
    return deletedAwareIdLabel(bizId, deleted: worldDeleted);
  }

  bool get shouldShowRequestWorldId {
    if (worldDeleted) return true;
    final id = bizId.trim();
    return id.isNotEmpty && requestWorldSummaryName != id;
  }

  String get joinRequestSummary {
    final name = requesterName;
    final world = requestWorldSummaryName;
    final suffix = shouldShowRequestWorldId ? '($requestWorldIdLabel)' : '';
    return '$name request to join $world$suffix';
  }

  String get reviewTitleText {
    final world = requestWorldSummaryName;
    return 'request to $world${shouldShowRequestWorldId ? '($requestWorldIdLabel)' : ''}';
  }

  _JoinRequestApprovalStatus get joinRequestApprovalStatus {
    return approvalStatus ?? _JoinRequestApprovalStatus.pending;
  }

  String get joinRequestListStatusText {
    switch (approvalStatus) {
      case _JoinRequestApprovalStatus.approved:
        return 'Approved';
      case _JoinRequestApprovalStatus.rejected:
        return 'Rejected';
      case _JoinRequestApprovalStatus.pending:
        return isJoinRequestReview
            ? 'Awaiting for approval'
            : 'Awaiting your approval';
      case null:
        return isJoinRequestReview ? 'Approved' : 'Awaiting your approval';
    }
  }

  String get joinRequestStatusText {
    switch (approvalStatus) {
      case _JoinRequestApprovalStatus.approved:
        return 'Approved';
      case _JoinRequestApprovalStatus.rejected:
        return 'Rejected';
      case _JoinRequestApprovalStatus.pending:
        return 'Awaiting your approval';
      case null:
        return isJoinRequestReview ? 'Approved' : 'Awaiting your approval';
    }
  }

  Color get joinRequestStatusColor {
    switch (approvalStatus) {
      case _JoinRequestApprovalStatus.approved:
        return GenesisColors.redSecondary;
      case _JoinRequestApprovalStatus.rejected:
        return GenesisColors.darkTextTertiary;
      case _JoinRequestApprovalStatus.pending:
        return GenesisColors.redSecondary;
      case null:
        return GenesisColors.redSecondary;
    }
  }

  String get discussTitleSuffix {
    final normalizedType = type.toLowerCase();
    final normalizedContent = content.toLowerCase();
    if (normalizedType == 'discuss_comment') {
      return ' comment your worldo';
    }
    if (normalizedType == 'discuss_reply') {
      return ' reply to you';
    }
    if (normalizedType == 'discuss_like') {
      return ' like your comment';
    }
    if (normalizedType.contains('like') ||
        normalizedContent.contains('liked your comment') ||
        normalizedContent.contains('like your comment')) {
      return ' like your comment';
    }
    if (normalizedType.contains('reply') ||
        normalizedContent.contains('replied to you') ||
        normalizedContent.contains('reply to you')) {
      return ' reply to you';
    }
    if (normalizedType.contains('comment') ||
        normalizedContent.contains('commented on your origin') ||
        normalizedContent.contains('comment your origin')) {
      return ' comment your worldo';
    }
    return content.isEmpty ? ' sent you a message' : ' $content';
  }

  String get titleText => '$senderDisplayName$discussTitleSuffix';

  String get followUserName {
    if (!isFollowNotification) return '';
    if (senderDeleted) return deletedEntityDisplayText;
    if (senderName.isNotEmpty) {
      return formatUidForDisplay(senderName, fallback: 'User');
    }
    final suffix = ' started following you.';
    if (content.endsWith(suffix)) {
      return formatUidForDisplay(
        content.substring(0, content.length - suffix.length).trim(),
        fallback: 'User',
      );
    }
    return 'User';
  }

  String get followUserUid {
    if (!isFollowNotification) return '';
    return _firstNonEmpty([senderUid, objId, bizId]);
  }

  String get bodyText {
    if (isDiscussNotification) {
      final trimmedComment = commentText.trim();
      if (trimmedComment.isEmpty) return '';
      final normalizedComment = trimmedComment.toLowerCase();
      final normalizedTitle = titleText.toLowerCase();
      if (normalizedComment == normalizedTitle) return '';
      return trimmedComment;
    }
    return content;
  }

  String get metaText {
    final source = isDiscussNotification || originDeleted || worldDeleted
        ? discussSourceLabel
        : _firstNonEmpty([
            originName.trim(),
            worldName.trim(),
            requestWorldIdLabel,
          ]);
    final time = createdAtText;
    if (source.isEmpty) return time;
    final displaySource = originName.trim().isEmpty
        ? source
        : originDisplayName(source);
    if (time.isEmpty) return displaySource;
    return '$displaySource · $time';
  }

  bool get discussSourceDeleted => originDeleted || worldDeleted;

  String get discussSourceLabel {
    if (discussSourceDeleted) return deletedEntityDisplayText;
    if (originName.trim().isNotEmpty) return originName.trim();
    if (worldName.trim().isNotEmpty) return worldName.trim();
    return bizId.trim();
  }

  String get createdAtText {
    return formatGenesisDateTime(createdAt);
  }

  OriginDiscussListItem toDiscussListItem() {
    return OriginDiscussListItem(
      discussId: objId,
      rootDiscussId: rootDiscussId,
      bizId: bizId,
      authorUid: senderUid,
      authorDeleted: senderDeleted,
      authorName: senderDisplayName,
      avatar: senderAvatar,
      content: commentText,
      replyCount: 0,
      createdAt: createdAt,
      seed: senderUid.isEmpty ? senderDisplayName : senderUid,
      latestReplies: const <Map<String, dynamic>>[],
    );
  }
}
