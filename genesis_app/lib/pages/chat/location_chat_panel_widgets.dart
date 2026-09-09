part of 'location_chat_page.dart';

const LinearGradient _locationChatBackgroundOverlayGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: <double>[0, 0.32, 0.64, 1],
  colors: <Color>[
    Color(0xCC131215),
    Color(0x80131215),
    Color(0x80131215),
    Color(0xCC131215),
  ],
);

class _LocationChatBackground extends StatelessWidget {
  const _LocationChatBackground({
    required this.imageUrl,
    required this.previewImageUrl,
    required this.color,
    required this.enabled,
  });

  final String? imageUrl;
  final String? previewImageUrl;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final imageLayer = enabled
        ? LayoutBuilder(
            builder: (context, constraints) {
              final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
              final fullUrl = _resolveLocationChatBackgroundUrl(
                imageUrl,
                previewImageUrl: previewImageUrl,
                logicalWidth: constraints.maxWidth,
                logicalHeight: constraints.maxHeight,
                devicePixelRatio: devicePixelRatio,
              );
              final previewUrl = resolveLocationChatBackgroundPreviewUrl(
                imageUrl,
                previewImageUrl: previewImageUrl,
              );
              return _LocationChatBackgroundImage(
                previewUrl: previewUrl,
                fullUrl: fullUrl,
              );
            },
          )
        : const SizedBox.expand(
            key: ValueKey<String>('location-chat-background-disabled'),
          );
    return RepaintBoundary(
      key: const ValueKey<String>('location-chat-background'),
      child: ColoredBox(
        color: color,
        child: Stack(
          key: const ValueKey<String>('location-chat-background-layers'),
          fit: StackFit.expand,
          children: [
            imageLayer,
            const IgnorePointer(
              child: DecoratedBox(
                key: ValueKey<String>('location-chat-background-overlay'),
                decoration: BoxDecoration(
                  gradient: _locationChatBackgroundOverlayGradient,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _resolveLocationChatBackgroundUrl(
  Object? imageUrl, {
  Object? previewImageUrl,
  required double? logicalWidth,
  required double? logicalHeight,
  required double devicePixelRatio,
}) {
  return _resolveLocationChatBackgroundImageUrl(
    imageUrl,
    fallback: previewImageUrl,
    logicalWidth: logicalWidth,
    logicalHeight: logicalHeight,
    devicePixelRatio: devicePixelRatio,
  );
}

String resolveLocationChatBackgroundPreviewUrl(
  Object? imageUrl, {
  Object? previewImageUrl,
}) {
  return _resolveLocationChatBackgroundImageUrl(
    imageUrl,
    fallback: previewImageUrl,
    logicalWidth: _locationChatBackgroundPreviewLogicalWidth,
    logicalHeight: null,
    devicePixelRatio: 1,
  );
}

String _resolveLocationChatBackgroundImageUrl(
  Object? source, {
  Object? fallback,
  required double? logicalWidth,
  required double? logicalHeight,
  required double devicePixelRatio,
}) {
  final selected = selectGenesisImageUrl(
    source,
    fallback: fallback,
    logicalWidth: logicalWidth,
    logicalHeight: logicalHeight,
    devicePixelRatio: devicePixelRatio,
  );
  return _resizeLocationChatBackgroundImageUrl(
    selected,
    logicalWidth: logicalWidth,
    devicePixelRatio: devicePixelRatio,
  );
}

String _resizeLocationChatBackgroundImageUrl(
  String selected, {
  required double? logicalWidth,
  required double devicePixelRatio,
}) {
  final resolved = resolveAssetUrl(selected);
  if (resolved == _locationChatDefaultBackgroundAsset) return '';
  if (resolved.startsWith('assets/')) return resolved;
  final resized = resizeGenesisImageUrl(
    resolved,
    logicalWidth: logicalWidth,
    devicePixelRatio: devicePixelRatio,
  );
  if (resized.isNotEmpty) return resized;
  if (resolved.isNotEmpty) return resolved;
  return '';
}

class _LocationChatBackgroundImage extends StatefulWidget {
  const _LocationChatBackgroundImage({
    required this.previewUrl,
    required this.fullUrl,
  });

  final String previewUrl;
  final String fullUrl;

  @override
  State<_LocationChatBackgroundImage> createState() =>
      _LocationChatBackgroundImageState();
}

class _LocationChatBackgroundImageState
    extends State<_LocationChatBackgroundImage> {
  bool _loadFullImage = false;
  bool _fullImageReady = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scheduleFullImage();
  }

  @override
  void didUpdateWidget(covariant _LocationChatBackgroundImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewUrl == widget.previewUrl &&
        oldWidget.fullUrl == widget.fullUrl) {
      return;
    }
    _generation += 1;
    _loadFullImage = false;
    _fullImageReady = false;
    _scheduleFullImage();
  }

  void _scheduleFullImage() {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || _loadFullImage) return;
      setState(() => _loadFullImage = true);
    });
  }

  void _markFullImageReady(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || _fullImageReady) return;
      setState(() => _fullImageReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fullUrl = widget.fullUrl.trim();
    final previewUrl = widget.previewUrl.trim();
    final generation = _generation;
    final singleUrl = fullUrl.isNotEmpty ? fullUrl : previewUrl;
    if (singleUrl.isEmpty) return const SizedBox.expand();
    if (fullUrl.startsWith('assets/') ||
        previewUrl.isEmpty ||
        previewUrl == fullUrl) {
      return _LocationChatBackgroundLayer(
        key: const ValueKey<String>('location-chat-background-single'),
        url: singleUrl,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _LocationChatBackgroundLayer(
          key: const ValueKey<String>('location-chat-background-preview'),
          url: previewUrl,
        ),
        if (_loadFullImage)
          KeyedSubtree(
            key: const ValueKey<String>('location-chat-background-full'),
            child: AnimatedOpacity(
              key: ValueKey<String>('location-chat-background-full:$fullUrl'),
              opacity: _fullImageReady ? 1 : 0,
              duration: _locationChatBackgroundFadeDuration,
              curve: Curves.easeOut,
              child: _LocationChatBackgroundLayer(
                key: ValueKey<String>(
                  'location-chat-background-full-image:$fullUrl',
                ),
                url: fullUrl,
                onReady: () => _markFullImageReady(generation),
              ),
            ),
          ),
      ],
    );
  }
}

class _LocationChatBackgroundLayer extends StatelessWidget {
  const _LocationChatBackgroundLayer({
    super.key,
    required this.url,
    this.onReady,
  });

  final String url;
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) {
    final resolved = url.trim();
    if (resolved.startsWith('assets/')) {
      return Image.asset(
        resolved,
        key: ValueKey<String>('location-chat-background-asset:$resolved'),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) onReady?.call();
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.expand();
        },
      );
    }
    return GenesisStaticNetworkImage(
      key: ValueKey<String>('location-chat-background-network:$resolved'),
      imageUrl: resolved,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      onImageLoaded: onReady,
      placeholder: (_) => const SizedBox.expand(),
      errorWidget: (_, _) => const SizedBox.expand(),
    );
  }
}

@visibleForTesting
String resolveLocationChatBackgroundUrlForTesting({
  Object? imageUrl,
  Object? previewImageUrl,
  double logicalWidth = 390,
  double logicalHeight = 844,
  double devicePixelRatio = 1,
}) {
  return _resolveLocationChatBackgroundUrl(
    imageUrl,
    previewImageUrl: previewImageUrl,
    logicalWidth: logicalWidth,
    logicalHeight: logicalHeight,
    devicePixelRatio: devicePixelRatio,
  );
}

@visibleForTesting
String resolveLocationChatBackgroundPreviewUrlForTesting({
  Object? imageUrl,
  Object? previewImageUrl,
}) {
  return resolveLocationChatBackgroundPreviewUrl(
    imageUrl,
    previewImageUrl: previewImageUrl,
  );
}

class _LocationChatComposerExtension extends StatelessWidget {
  const _LocationChatComposerExtension({
    required this.style,
    required this.child,
  });

  final ChatUiStyleConfig style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: -_locationChatComposerBottomExtension,
          height: _locationChatComposerBottomExtension,
          child: DecoratedBox(
            decoration: BoxDecoration(color: _bottomExtensionColor(style)),
          ),
        ),
        child,
      ],
    );
  }

  Color _bottomExtensionColor(ChatUiStyleConfig style) {
    final gradient = style.composerBackgroundGradient;
    if (gradient is LinearGradient && gradient.colors.isNotEmpty) {
      return gradient.colors.last;
    }
    return style.composerBackgroundColor;
  }
}

class _LocationChatNewMessageNotice extends StatelessWidget {
  const _LocationChatNewMessageNotice({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC1E1E24),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const ValueKey('location-chat-new-message-notice'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            '$count new message',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

String _firstMapString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = _mapString(map, key);
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _firstMapImageUrl(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    if (!map.containsKey(key)) continue;
    final resolved = asResolvedImageUrl(map[key], resolveAssetUrl);
    if (resolved.isNotEmpty) return resolved;
  }
  return '';
}

Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> map) {
  return {
    for (final entry in map.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

String _chatroomIdentityKey(String? value) {
  return (value ?? '').trim().toLowerCase();
}

@visibleForTesting
bool locationChatMessageBelongsToCurrentRoleForTesting({
  String messageBusinessType = '',
  required String messageUserId,
  required String messageSenderId,
  required Iterable<String> currentUserIds,
  required Iterable<String> currentSenderIds,
  required Iterable<Map<String, dynamic>> characters,
  required Iterable<Map<String, dynamic>> characterPositions,
}) {
  return _locationChatMessageBelongsToCurrentRole(
    messageBusinessType: messageBusinessType,
    messageUserId: messageUserId,
    messageSenderId: messageSenderId,
    currentUserIds: currentUserIds,
    currentSenderIds: currentSenderIds,
    characters: characters,
    characterPositions: characterPositions,
  );
}

bool _locationChatMessageBelongsToCurrentRole({
  String messageBusinessType = '',
  required String messageUserId,
  required String messageSenderId,
  required Iterable<String> currentUserIds,
  required Iterable<String> currentSenderIds,
  required Iterable<Map<String, dynamic>> characters,
  required Iterable<Map<String, dynamic>> characterPositions,
}) {
  // V2 AI replies carry the initiating user's ID, not the speaker's account.
  if (const {
    'character',
    'narrator',
    'ai',
    'llm',
  }.contains(messageBusinessType.trim().toLowerCase())) {
    return false;
  }
  final identityKeys = <String>{
    ...currentUserIds.map(_chatroomIdentityKey),
    ...currentSenderIds.map(_chatroomIdentityKey),
  }..remove('');
  if (identityKeys.isEmpty) return false;

  for (final candidate in <Map<String, dynamic>>[
    ...characters,
    ...characterPositions,
  ]) {
    final rawCharacter = candidate['character'];
    final character = rawCharacter is Map
        ? _stringKeyMap(rawCharacter)
        : candidate;
    final ownerKeys = <String>{
      for (final key in const ['player_uid', 'user_id', 'uid'])
        _chatroomIdentityKey(_mapString(character, key)),
    }..remove('');
    final characterKeys = <String>{
      for (final key in const ['character_id', 'char_id', 'id'])
        _chatroomIdentityKey(_mapString(character, key)),
    }..remove('');
    if (!ownerKeys.any(identityKeys.contains) &&
        !characterKeys.any(identityKeys.contains)) {
      continue;
    }
    identityKeys
      ..addAll(ownerKeys)
      ..addAll(characterKeys);
  }

  final messageUserIdKey = _chatroomIdentityKey(messageUserId);
  if (messageUserIdKey.isNotEmpty && identityKeys.contains(messageUserIdKey)) {
    return true;
  }
  final messageSenderIdKey = _chatroomIdentityKey(messageSenderId);
  return messageSenderIdKey.isNotEmpty &&
      identityKeys.contains(messageSenderIdKey);
}
