part of 'user_profile_library.dart';

class _FollowStats extends StatelessWidget {
  const _FollowStats({
    required this.followingCount,
    required this.followerCount,
    required this.onFollowingTap,
    required this.onFollowersTap,
  });

  final int followingCount;
  final int followerCount;
  final VoidCallback onFollowingTap;
  final VoidCallback onFollowersTap;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 16,
      height: 1,
      color: Color(0xFF111111),
      fontWeight: FontWeight.w600,
    );
    const labelStyle = TextStyle(
      fontSize: 14,
      height: 1,
      color: Color(0xFF666666),
      fontWeight: FontWeight.w400,
    );

    return Row(
      children: [
        _FollowStatButton(
          onTap: onFollowingTap,
          count: formatStatCount(followingCount),
          label: 'Following',
          countStyle: style,
          labelStyle: labelStyle,
        ),
        const SizedBox(width: 16),
        _FollowStatButton(
          onTap: onFollowersTap,
          count: formatStatCount(followerCount),
          label: 'Followers',
          countStyle: style,
          labelStyle: labelStyle,
        ),
      ],
    );
  }
}

class _FollowStatButton extends StatelessWidget {
  const _FollowStatButton({
    required this.onTap,
    required this.count,
    required this.label,
    required this.countStyle,
    required this.labelStyle,
  });

  final VoidCallback onTap;
  final String count;
  final String label;
  final TextStyle countStyle;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(count, style: countStyle),
            const SizedBox(width: 4),
            Text(label, style: labelStyle),
          ],
        ),
      ),
    );
  }
}

class _ProfileActionButtons extends StatelessWidget {
  const _ProfileActionButtons({
    required this.isFollowed,
    required this.followLoading,
    required this.onFollowToggle,
    required this.onMessage,
  });

  final bool isFollowed;
  final bool followLoading;
  final VoidCallback onFollowToggle;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isFollowed
        ? const Color(0xFFE5E5E5)
        : const Color(0xFFFF2442);
    final foregroundColor = isFollowed ? Colors.black : Colors.white;
    final disabledBackgroundColor = isFollowed
        ? const Color(0xFFE5E5E5)
        : const Color(0xFFFF2442).withValues(alpha: 0.55);
    final disabledForegroundColor = isFollowed ? Colors.black54 : Colors.white;
    const actionTextStyle = TextStyle(fontWeight: FontWeight.w600);

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: FilledButton(
              key: const ValueKey('user-profile-follow-button'),
              onPressed: followLoading ? null : onFollowToggle,
              style: FilledButton.styleFrom(
                backgroundColor: backgroundColor,
                disabledBackgroundColor: disabledBackgroundColor,
                foregroundColor: foregroundColor,
                disabledForegroundColor: disabledForegroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: followLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: disabledForegroundColor,
                      ),
                    )
                  : Text(
                      isFollowed ? 'Following' : 'Follow',
                      style: actionTextStyle,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 36,
            child: FilledButton(
              key: const ValueKey('user-profile-message-button'),
              onPressed: onMessage,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE5E5E5),
                disabledBackgroundColor: const Color(0xFFE5E5E5),
                foregroundColor: Colors.black,
                disabledForegroundColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Message', style: actionTextStyle),
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.name,
    required this.urlListenable,
    required this.nameListenable,
    required this.isUpdating,
    required this.updatingListenable,
    required this.onEdit,
  });

  static const double _size = 80;
  static const double _radius = GenesisAvatarRadii.user;

  final String url;
  final String name;
  final ValueListenable<String>? urlListenable;
  final ValueListenable<String>? nameListenable;
  final bool isUpdating;
  final ValueListenable<bool>? updatingListenable;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final listenableName = nameListenable;
    if (listenableName != null) {
      return ValueListenableBuilder<String>(
        valueListenable: listenableName,
        builder: (context, displayName, _) =>
            _buildUrlLayer(displayName.trim().isEmpty ? name : displayName),
      );
    }
    return _buildUrlLayer(name);
  }

  Widget _buildUrlLayer(String displayName) {
    final avatarListenable = urlListenable;
    if (avatarListenable == null) {
      return _buildAvatar(url, displayName, isUpdating);
    }
    return ValueListenableBuilder<String>(
      valueListenable: avatarListenable,
      builder: (context, avatarUrl, _) {
        final loadingListenable = updatingListenable;
        if (loadingListenable == null) {
          return _buildAvatar(avatarUrl, displayName, isUpdating);
        }
        return ValueListenableBuilder<bool>(
          valueListenable: loadingListenable,
          builder: (context, updating, _) =>
              _buildAvatar(avatarUrl, displayName, updating),
        );
      },
    );
  }

  Widget _buildAvatar(String avatarUrl, String displayName, bool updating) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GenesisAvatar(
            url: avatarUrl,
            name: displayName,
            size: _size,
            borderRadius: _radius,
            imageKey: const ValueKey('user-profile-avatar-image'),
          ),
          if (onEdit != null)
            Positioned(
              right: 2,
              bottom: 2,
              child: Material(
                color: Colors.black.withValues(alpha: 0.4),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: updating ? null : onEdit,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      MyFlutterApp.editImage,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DisplayNameText extends StatelessWidget {
  const _DisplayNameText({
    required this.displayName,
    required this.displayNameListenable,
  });

  final String displayName;
  final ValueListenable<String>? displayNameListenable;

  @override
  Widget build(BuildContext context) {
    final listenable = displayNameListenable;
    if (listenable == null) {
      return _buildName(displayName);
    }
    return ValueListenableBuilder<String>(
      valueListenable: listenable,
      builder: (context, name, _) {
        final resolvedName = name.trim().isEmpty ? displayName : name;
        return _buildName(resolvedName);
      },
    );
  }

  Widget _buildName(String name) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 20,
        height: 1,
        fontWeight: FontWeight.w600,
        color: Colors.black,
      ),
    );
  }
}

class _ProfileEditButton extends StatelessWidget {
  const _ProfileEditButton({
    required this.isUpdating,
    required this.updatingListenable,
    required this.onTap,
  });

  final bool isUpdating;
  final ValueListenable<bool>? updatingListenable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final listenable = updatingListenable;
    if (listenable == null) {
      return _buildButton(isUpdating);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, updating, _) => _buildButton(updating),
    );
  }

  Widget _buildButton(bool updating) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: updating ? null : onTap,
      child: SizedBox(
        width: 28,
        height: 24,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Transform.scale(
            // Match the previous edit icon within its existing layout slot.
            scale: 32 / 37.36,
            child: SvgPicture.asset(
              editSquareIconAsset,
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(
                Colors.black,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
