import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../icons/custom_icon_assets.dart';
import '../ui/tokens/genesis_colors.dart';
import '../utils/genesis_image_resource.dart';
import 'chat/shared/chat_ui.dart';
import '../ui/components/genesis_soft_italic_text.dart';
import '../utils/genesis_timestamp_formatter.dart';

class WorldTickEventItem extends StatelessWidget {
  const WorldTickEventItem({
    super.key,
    required this.tick,
    required this.tickNumber,
    this.subTickNumber = 0,
    required this.fallbackBody,
    this.locationsById = const <String, Map<String, dynamic>>{},
    this.charactersById = const <String, Map<String, dynamic>>{},
    this.isLast = true,
    this.dateLabel,
    this.timeAgoLabel,
    this.stackedContent = false,
    this.contentTextStyle,
    this.contentLabelStyle,
    this.contentTimestampStyle,
    this.metricUnit = '',
    this.showParagraphClue = false,
    this.useChatEventStyle = false,
  });

  final Map<String, dynamic> tick;
  final int tickNumber;
  final int subTickNumber;
  final String fallbackBody;
  final Map<String, Map<String, dynamic>> locationsById;
  final Map<String, Map<String, dynamic>> charactersById;
  final bool isLast;
  final String? dateLabel;
  final String? timeAgoLabel;
  final bool stackedContent;
  final TextStyle? contentTextStyle;
  final TextStyle? contentLabelStyle;
  final TextStyle? contentTimestampStyle;
  final String metricUnit;
  final bool showParagraphClue;

  /// Share Location Chat Tick event rendering in the dark World Events sheet.
  final bool useChatEventStyle;

  @override
  Widget build(BuildContext context) {
    final tickResult = _tickResult(tick);
    final createdAt = _tickDateTime(tick['created_at']);
    final date = dateLabel ?? formatGenesisDateTime(createdAt);
    final timeAgo = timeAgoLabel ?? '';
    final body = _mapString(tickResult, const [
      'narrator',
    ], fallback: fallbackBody);
    final paragraphs = _tickParagraphs(tickResult);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (useChatEventStyle) ...[
            ChatTickHeader(
              label:
                  'Tick $tickNumber${subTickNumber > 0 ? '-$subTickNumber' : ''}',
              style: kLocationChatStyle,
            ),
            if (body.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              ChatTickGlobalSection(text: body, style: kLocationChatStyle),
            ],
            const SizedBox(height: 12),
          ] else ...[
            _TickHeader(
              tickNumber: tickNumber,
              subTickNumber: subTickNumber,
              date: date,
              timeAgo: timeAgo,
            ),
            const SizedBox(height: 6),
            _GlobalEventCard(
              body: body,
              stacked: stackedContent,
              labelStyle: contentLabelStyle,
              bodyStyle: contentTextStyle,
            ),
            const SizedBox(height: 6),
          ],
          for (final paragraph in paragraphs) ...[
            _TickParagraphRow(
              paragraph: paragraph,
              locationsById: locationsById,
              charactersById: charactersById,
              stacked: stackedContent,
              labelStyle: contentLabelStyle,
              bodyStyle: contentTextStyle,
              timestampStyle: contentTimestampStyle,
              metricUnit: metricUnit,
              showClue: showParagraphClue,
              useChatEventStyle: useChatEventStyle,
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

int worldTickEventNumber(Map<String, dynamic> tick, {int fallback = 0}) {
  return _mapInt(tick, const ['tick_no'], fallback: fallback);
}

class _TickHeader extends StatelessWidget {
  const _TickHeader({
    required this.tickNumber,
    required this.subTickNumber,
    required this.date,
    required this.timeAgo,
  });

  final int tickNumber;
  final int subTickNumber;
  final String date;
  final String timeAgo;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Tick $tickNumber${subTickNumber > 0 ? '-$subTickNumber' : ''}'
              '${date.isEmpty ? '' : ' · $date'}',
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111111),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeAgo.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              timeAgo,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF8F8F8F),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlobalEventCard extends StatelessWidget {
  const _GlobalEventCard({
    required this.body,
    required this.stacked,
    this.labelStyle,
    this.bodyStyle,
  });

  final String body;
  final bool stacked;
  final TextStyle? labelStyle;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    final label = Text('Global', style: labelStyle ?? _labelStyle);
    final bodyText = Text(body, style: bodyStyle ?? _bodyStyle);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F8F4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 4), bodyText],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 82, child: label),
                Expanded(child: bodyText),
              ],
            ),
    );
  }
}

class _TickParagraphRow extends StatelessWidget {
  const _TickParagraphRow({
    required this.paragraph,
    required this.locationsById,
    required this.charactersById,
    required this.stacked,
    this.labelStyle,
    this.bodyStyle,
    this.timestampStyle,
    this.metricUnit = '',
    this.showClue = false,
    this.useChatEventStyle = false,
  });

  final Map<String, dynamic> paragraph;
  final Map<String, Map<String, dynamic>> locationsById;
  final Map<String, Map<String, dynamic>> charactersById;
  final bool stacked;
  final TextStyle? labelStyle;
  final TextStyle? bodyStyle;
  final TextStyle? timestampStyle;
  final String metricUnit;
  final bool showClue;
  final bool useChatEventStyle;

  @override
  Widget build(BuildContext context) {
    final locationId = _mapString(paragraph, const ['location_id']);
    final mappedName = _locationName(locationId, locationsById);
    final name = mappedName.isEmpty
        ? _mapString(paragraph, const ['label'], fallback: locationId)
        : mappedName;
    final body = _mapString(paragraph, const [
      'text',
    ], fallback: _mapString(paragraph, const ['content', 'summary']));
    final timestamp = _mapString(paragraph, const [
      'timestamp',
      'timesamp',
      'time',
    ]);
    final clue = showClue ? _mapString(paragraph, const ['clue']) : '';
    final characterDetails = _characterDetails(
      paragraph,
      metricUnit: metricUnit,
    );
    final visibleRoles = _visibleRoles(paragraph, charactersById);

    if (useChatEventStyle) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 12,
                  color: GenesisColors.darkTextSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    name.isEmpty ? 'Location' : name,
                    style: labelStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ChatTickStoryEventParagraph(
              messageLocalId: 'world-event',
              index: 0,
              addTopSpacing: false,
              paragraph: ChatStoryEventParagraphVm(
                timestamp: timestamp,
                text: body,
                clue: clue,
                visibilityLabel: visibleRoles
                    .map((role) => role.name)
                    .join(', '),
                visibleRoles: [
                  for (final role in visibleRoles)
                    ChatStoryEventVisibleRoleVm(
                      roleId: role.id,
                      name: role.name,
                      isAi: role.isAi,
                      avatarUrl: role.avatarUrl,
                    ),
                ],
              ),
            ),
            if (characterDetails.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: _CharacterDetailsText(
                  details: characterDetails,
                  style:
                      bodyStyle ??
                      const TextStyle(
                        color: GenesisColors.darkTextSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                  nameColor: GenesisColors.darkTextPrimary,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final label = _LocationLabel(
      text: name.isEmpty ? 'Location' : name,
      style: labelStyle,
    );
    final resolvedBodyStyle = bodyStyle ?? _bodyStyle;
    final bodyText = Text(body, style: resolvedBodyStyle);
    final clueText = clue.isEmpty
        ? null
        : _ClueText(text: clue, style: resolvedBodyStyle);
    final timestampText = timestamp.isEmpty
        ? null
        : _TimestampLabel(text: timestamp, style: timestampStyle);
    final metadata = timestampText == null && visibleRoles.isEmpty
        ? null
        : _EventMetadata(
            timestamp: timestampText,
            visibleRoles: visibleRoles,
            style: timestampStyle,
          );
    final characterDetailsText = characterDetails.isEmpty
        ? null
        : _CharacterDetailsText(
            details: characterDetails,
            style: resolvedBodyStyle,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 4),
                if (metadata != null) ...[metadata, const SizedBox(height: 2)],
                bodyText,
                if (clueText != null) ...[const SizedBox(height: 8), clueText],
                if (characterDetailsText != null) ...[
                  const SizedBox(height: 6),
                  characterDetailsText,
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 82, child: label),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (metadata != null) ...[
                        metadata,
                        const SizedBox(height: 2),
                      ],
                      bodyText,
                      if (clueText != null) ...[
                        const SizedBox(height: 8),
                        clueText,
                      ],
                      if (characterDetailsText != null) ...[
                        const SizedBox(height: 6),
                        characterDetailsText,
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ClueText extends StatelessWidget {
  const _ClueText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    const iconColor = Color(0xFF444444);
    final textStyle = style.copyWith(
      color: const Color(0xFF666666),
      height: 1.35,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SvgPicture.asset(
            clueIconAsset,
            width: 14,
            height: 14,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(child: GenesisSoftItalicText(text, style: textStyle)),
      ],
    );
  }
}

const _labelStyle = TextStyle(
  fontSize: 12,
  height: 1.6,
  fontWeight: FontWeight.w600,
  color: Color(0xFF111111),
);

const _bodyStyle = TextStyle(
  fontSize: 12,
  height: 1.6,
  fontWeight: FontWeight.w400,
  color: Color(0xFF444444),
);

const _timestampStyle = TextStyle(
  fontSize: 12,
  height: 1.4,
  fontWeight: FontWeight.w400,
  color: Color(0xFF111111),
);

const _characterDetailNameColor = Color(0xFF4B6192);
const _positiveDeltaColor = Color(0xFF338960);
const _negativeDeltaColor = Color(0xFFFF2442);

class _CharacterDetailsText extends StatelessWidget {
  const _CharacterDetailsText({
    required this.details,
    required this.style,
    this.nameColor = _characterDetailNameColor,
  });

  final Color nameColor;

  final List<_CharacterDetailLine> details;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final nameStyle = style.copyWith(
      color: nameColor,
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (int index = 0; index < details.length; index++) ...[
            if (index > 0) const TextSpan(text: '\n'),
            if (details[index].name.isNotEmpty)
              TextSpan(text: details[index].name, style: nameStyle),
            if (details[index].delta.isNotEmpty)
              TextSpan(
                text: details[index].name.isEmpty
                    ? details[index].delta
                    : ' ${details[index].delta}',
                style: details[index].deltaColor == null
                    ? null
                    : style.copyWith(
                        color: details[index].deltaColor,
                        fontWeight: FontWeight.w600,
                      ),
              ),
          ],
        ],
      ),
      style: style,
    );
  }
}

class _LocationLabel extends StatelessWidget {
  const _LocationLabel({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.place_outlined, size: 12, color: Color(0xFF111111)),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: style ?? _labelStyle)),
      ],
    );
  }
}

class _TimestampLabel extends StatelessWidget {
  const _TimestampLabel({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = (style ?? _timestampStyle).copyWith(
      fontWeight: FontWeight.w400,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule, size: 12, color: Color(0xFF111111)),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: resolvedStyle)),
      ],
    );
  }
}

class _EventMetadata extends StatelessWidget {
  const _EventMetadata({
    required this.timestamp,
    required this.visibleRoles,
    this.style,
  });

  final Widget? timestamp;
  final List<_VisibleRole> visibleRoles;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final aiNames = visibleRoles
        .where((role) => role.isAi)
        .map((role) => role.name)
        .toList(growable: false);
    final userNames = visibleRoles
        .where((role) => !role.isAi)
        .map((role) => role.name)
        .toList(growable: false);
    final roleNames = <String>[...aiNames, ...userNames];
    final roleGroup = _VisibleRoleGroup(
      iconAsset: characterStatIconAsset,
      names: roleNames,
      style: style,
    );
    if (visibleRoles.isEmpty) return timestamp ?? const SizedBox.shrink();
    if (timestamp == null) return roleGroup;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        timestamp!,
        const SizedBox(width: 8),
        Expanded(child: roleGroup),
      ],
    );
  }
}

class _VisibleRoleGroup extends StatelessWidget {
  const _VisibleRoleGroup({
    required this.iconAsset,
    required this.names,
    this.style,
  });

  final String iconAsset;
  final List<String> names;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = (style ?? _timestampStyle).copyWith(
      fontWeight: FontWeight.w400,
      color: style?.color ?? const Color(0xFF444444),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SvgPicture.asset(
            iconAsset,
            width: 12,
            height: 12,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(child: Text(names.join(', '), style: resolvedStyle)),
      ],
    );
  }
}

DateTime? _tickDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt() * 1000,
      isUtc: true,
    );
  }
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text);
}

List<Map<String, dynamic>> _tickParagraphs(Map<String, dynamic> tick) {
  final raw = tick['paragraphs'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList(growable: false);
}

Map<String, dynamic> _tickResult(Map<String, dynamic> tick) {
  final raw = tick['tick_result'];
  if (raw is Map) return raw.cast<String, dynamic>();
  return const <String, dynamic>{};
}

String _locationName(
  String locationId,
  Map<String, Map<String, dynamic>> locationsById,
) {
  final location = locationsById[locationId];
  if (location == null) return '';
  return _mapString(location, const ['location_name', 'name']);
}

class _VisibleRole {
  const _VisibleRole({
    required this.id,
    required this.name,
    required this.isAi,
    required this.avatarUrl,
  });

  final String id;
  final String avatarUrl;

  final String name;
  final bool isAi;
}

List<_VisibleRole> _visibleRoles(
  Map<String, dynamic> paragraph,
  Map<String, Map<String, dynamic>> charactersById,
) {
  final visibility = _mapString(paragraph, const ['visibility']).toLowerCase();
  if (visibility == 'public') return const <_VisibleRole>[];
  final rawVisibleTo = paragraph['visible_to'] ?? paragraph['visibleTo'];
  if (rawVisibleTo is! List) return const <_VisibleRole>[];
  final roles = <_VisibleRole>[];
  final seenNames = <String>{};
  for (final rawRoleId in rawVisibleTo) {
    final roleId = '$rawRoleId'.trim();
    if (roleId.isEmpty) continue;
    final character = charactersById[roleId];
    if (character == null) continue;
    final name = _mapString(character, const ['name']).trim();
    if (name.isEmpty || !seenNames.add(name)) continue;
    roles.add(
      _VisibleRole(
        id: roleId,
        avatarUrl: GenesisImageResource.fromJson(
          character['avatar'],
        ).displayUrl,
        name: name,
        isAi: _mapString(character, const ['player_uid']).isEmpty,
      ),
    );
  }
  return roles;
}

class _CharacterDetailLine {
  const _CharacterDetailLine({
    required this.name,
    required this.delta,
    this.deltaColor,
  });

  final String name;
  final String delta;
  final Color? deltaColor;

  bool get isNotEmpty => name.isNotEmpty || delta.isNotEmpty;
}

List<_CharacterDetailLine> _characterDetails(
  Map<String, dynamic> paragraph, {
  String metricUnit = '',
}) {
  final raw = paragraph['character_deltas'];
  if (raw is! List) return const <_CharacterDetailLine>[];
  final unit = metricUnit.trim();
  return raw
      .whereType<Map>()
      .map((item) {
        final detail = item.cast<String, dynamic>();
        final rawDelta = detail['delta'];
        final delta = _characterDeltaText(rawDelta, unit);
        return _CharacterDetailLine(
          name: _mapString(detail, const ['name']),
          delta: delta,
          deltaColor: _characterDeltaColor(rawDelta),
        );
      })
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

String _characterDeltaText(Object? rawDelta, String unit) {
  final delta = _mapString({'delta': rawDelta}, const ['delta']);
  if (delta.isEmpty) return '';
  final number = _pureIntegerDelta(rawDelta);
  final prefix = number != null && number > 0 ? '+' : '';
  return '$prefix$delta$unit';
}

Color? _characterDeltaColor(Object? rawDelta) {
  final number = _pureIntegerDelta(rawDelta);
  if (number == null) return null;
  if (number > 0) return _positiveDeltaColor;
  if (number < 0) return _negativeDeltaColor;
  return null;
}

int? _pureIntegerDelta(Object? value) {
  if (value is int) return value;
  if (value is num) {
    return value % 1 == 0 ? value.toInt() : null;
  }
  final text = '$value'.trim();
  if (!RegExp(r'^[+-]?\d+$').hasMatch(text)) return null;
  return int.tryParse(text);
}

int _mapInt(Map<String, dynamic> map, List<String> keys, {int fallback = 0}) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return fallback;
}

String _mapString(
  Map<String, dynamic> map,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = '$value'.trim();
    if (text.isNotEmpty) return text;
  }
  return fallback;
}
