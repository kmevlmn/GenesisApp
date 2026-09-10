part of 'message_category_list_page.dart';

enum _JoinRequestAction {
  approve,
  reject;

  String get apiValue {
    switch (this) {
      case _JoinRequestAction.approve:
        return 'approve';
      case _JoinRequestAction.reject:
        return 'reject';
    }
  }

  _JoinRequestApprovalStatus get approvalStatus {
    switch (this) {
      case _JoinRequestAction.approve:
        return _JoinRequestApprovalStatus.approved;
      case _JoinRequestAction.reject:
        return _JoinRequestApprovalStatus.rejected;
    }
  }

  String get successText {
    switch (this) {
      case _JoinRequestAction.approve:
        return 'Approved';
      case _JoinRequestAction.reject:
        return 'Rejected';
    }
  }
}

enum _JoinRequestApprovalStatus { pending, approved, rejected }

class _JoinRequestDialogContent extends StatelessWidget {
  const _JoinRequestDialogContent({
    required this.item,
    required this.statusOnly,
    required this.onOpenUser,
    required this.onOpenWorld,
  });

  final _NotificationItem item;
  final bool statusOnly;
  final VoidCallback? onOpenUser;
  final VoidCallback? onOpenWorld;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _JoinRequestDialogInfoRow(
            title: item.requesterName,
            subtitle: deletedAwareIdLabel(
              item.senderUid,
              deleted: item.senderDeleted,
            ),
            onTap: onOpenUser,
          ),
          const SizedBox(height: 4),
          _JoinRequestDialogInfoRow(
            title: item.requestWorldName.isEmpty
                ? 'this world'
                : item.requestWorldName,
            subtitle: deletedAwareIdLabel(
              item.bizId,
              deleted: item.worldDeleted,
            ),
            onTap: onOpenWorld,
          ),
          if (statusOnly) ...[
            const SizedBox(height: 12),
            _StatusText(item: item),
          ],
        ],
      ),
    );
  }
}

class _JoinRequestDialogInfoRow extends StatelessWidget {
  const _JoinRequestDialogInfoRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: title, style: _notificationNameStyle),
                    if (subtitle.trim().isNotEmpty)
                      TextSpan(
                        text: ' $subtitle',
                        style: const TextStyle(
                          color: GenesisColors.darkTextTertiary,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GenesisColors.darkTextSecondary,
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Text(
                '>',
                style: TextStyle(
                  color: GenesisColors.darkTextTertiary,
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic>? _optionalJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

String _mapString(Map<String, dynamic>? map, String key) {
  if (map == null) return '';
  return asString(map[key]);
}

bool _relationIsFollowed(Map<String, dynamic>? map) {
  if (map == null) return false;
  final state = _firstNonEmpty([
    asString(map['follow_button_state']),
    asString(map['relation_status']),
  ]).toLowerCase();
  if (state == 'following' || state == 'friend' || state == 'friends') {
    return true;
  }
  if (state == 'follow' || state == 'follow_back' || state == 'self') {
    return false;
  }
  return asBool(map['i_followed']) ||
      asBool(map['is_followed']) ||
      asBool(map['followed']) ||
      asBool(map['is_friend']);
}

String _firstNonEmpty(Iterable<String> values, {String fallback = ''}) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return fallback;
}

Object? _firstNonNull(Iterable<Object?> values) {
  for (final value in values) {
    if (value != null) return value;
  }
  return null;
}

_JoinRequestApprovalStatus? _approvalStatusFromJson(Map<String, dynamic> json) {
  final raw = _firstNonEmpty([
    asString(json['apply_status']),
    asString(json['status']),
    asString(json['review_status']),
  ]).toLowerCase();
  if (raw == '20' || raw == '40' || raw == 'approved' || raw == 'approve') {
    return _JoinRequestApprovalStatus.approved;
  }
  if (raw == '30' || raw == 'rejected' || raw == 'reject') {
    return _JoinRequestApprovalStatus.rejected;
  }
  if (raw == '10' || raw == 'pending') {
    return _JoinRequestApprovalStatus.pending;
  }
  return null;
}

String _extractRequesterNameFromJoinContent(String content) {
  final match = RegExp(
    r'^(.+?)\s+(?:request|requests|wants|want)\s+to\s+join\b',
    caseSensitive: false,
  ).firstMatch(content.trim());
  return match?.group(1)?.trim() ?? '';
}

String _extractCommentBodyFromContent(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return '';
  final quoted = RegExp(r'["“](.+?)["”]').firstMatch(trimmed);
  if (quoted != null) return quoted.group(1)?.trim() ?? '';
  final colonIndex = trimmed.indexOf(':');
  if (colonIndex == -1 || colonIndex == trimmed.length - 1) return '';
  return trimmed.substring(colonIndex + 1).trim();
}

String _extractWorldNameFromJoinContent(String content) {
  final match = RegExp(
    r'\bjoin\s+(.+?)(?:\.|$)',
    caseSensitive: false,
  ).firstMatch(content.trim());
  return match?.group(1)?.trim() ?? '';
}
