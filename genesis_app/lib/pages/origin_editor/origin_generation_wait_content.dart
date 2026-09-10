import '../../components/common/genesis_generation_wait_overlay.dart';
import 'package:flutter/material.dart';
import '../create/create_origin_draft_store.dart';

List<GenesisGenerationWaitAvatar> originDraftGenerationWaitAvatars(
  CreateOriginDraft draft,
) => [
  for (final character in draft.characters)
    if (character.avatarUrl.trim().isNotEmpty)
      GenesisGenerationWaitAvatar(
        name: character.name,
        url: character.avatarUrl,
      ),
];

class OriginGenerationWaitOverlay extends StatelessWidget {
  const OriginGenerationWaitOverlay({
    super.key,
    this.publishing = false,
    this.avatars = const [],
    this.onBackPressed,
    this.onBarrierTap,
  });
  final bool publishing;
  final List<GenesisGenerationWaitAvatar> avatars;
  final VoidCallback? onBackPressed;
  final VoidCallback? onBarrierTap;
  @override
  Widget build(BuildContext context) => GenesisGenerationWaitOverlay(
    brightness: Brightness.dark,
    title: publishing ? 'Publishing your Worldo' : 'Creating your Worldo',
    message: publishing
        ? 'Preparing your Worldo updates.\nPlease wait for a moment.'
        : 'Bringing your Worldo to life.\nPlease wait for a moment.',
    characterAvatars: avatars,
    illustration: avatars.isEmpty
        ? Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 88,
                height: 88,
              ),
            ),
          )
        : null,
    onBackPressed: onBackPressed,
    onBarrierTap: onBarrierTap,
  );
}
