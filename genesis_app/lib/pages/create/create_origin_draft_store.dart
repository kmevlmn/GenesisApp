import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/genesis_ugc_text.dart';

const Object _unchanged = Object();

class CreateOriginDraftStore {
  static const String _storageKey = 'create_origin_draft_v1';
  static const String _tempTableKey = 'create_origin_temp_table_v1';
  static const String _finalTableKey = 'create_origin_final_table_v1';

  static Future<CreateOriginDraft> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return CreateOriginDraft.empty();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return CreateOriginDraft.fromJson(decoded);
      }
      if (decoded is Map) {
        return CreateOriginDraft.fromJson(
          decoded.map((k, v) => MapEntry('$k', v)),
        );
      }
      return CreateOriginDraft.empty();
    } catch (_) {
      return CreateOriginDraft.empty();
    }
  }

  static Future<void> save(CreateOriginDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(draft.toJson()));
  }

  static Future<void> saveTemp(
    CreateOriginDraft draft, {
    required bool syncedToFinal,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final table = _decodeTable(prefs.getString(_tempTableKey));
    table[_rowIdFor(draft)] = {
      'synced_to_final': syncedToFinal,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'draft': draft.toJson(),
    };
    await prefs.setString(_tempTableKey, jsonEncode(table));
    await save(draft);
  }

  static Future<void> saveFinal(CreateOriginDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final rowId = _rowIdFor(draft);
    final finalTable = _decodeTable(prefs.getString(_finalTableKey));
    finalTable[rowId] = {
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'draft': draft.toJson(),
    };

    final tempTable = _decodeTable(prefs.getString(_tempTableKey));
    tempTable[rowId] = {
      'synced_to_final': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'draft': draft.toJson(),
    };

    await prefs.setString(_finalTableKey, jsonEncode(finalTable));
    await prefs.setString(_tempTableKey, jsonEncode(tempTable));
    await save(draft);
  }

  static Future<CreateOriginDraft> loadFinal() async {
    final prefs = await SharedPreferences.getInstance();
    final table = _decodeTable(prefs.getString(_finalTableKey));
    if (table.isEmpty) return CreateOriginDraft.empty();

    final current = await load();
    final rowId = _rowIdFor(current);
    final row = table[rowId] ?? table['pending_origin'];
    final draft = _draftFromTableRow(row);
    if (draft != null) return draft;

    for (final value in table.values) {
      final fallbackDraft = _draftFromTableRow(value);
      if (fallbackDraft != null) return fallbackDraft;
    }
    return CreateOriginDraft.empty();
  }

  static Future<List<CharacterDraft>> loadFinalCharacters() async {
    final draft = await loadFinal();
    if (!draft.charactersSaved) return const <CharacterDraft>[];
    return draft.characters
        .where(
          (item) =>
              item.charId.trim().isNotEmpty && item.name.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_tempTableKey);
    await prefs.remove(_finalTableKey);
  }

  static Map<String, dynamic> _decodeTable(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }

  static CreateOriginDraft? _draftFromTableRow(Object? row) {
    final rowMap = _asMap(row);
    if (rowMap.isEmpty) return null;
    final draftMap = _asMap(rowMap['draft']);
    if (draftMap.isEmpty) return null;
    return CreateOriginDraft.fromJson(draftMap);
  }

  static String _rowIdFor(CreateOriginDraft draft) {
    final originId = draft.basics.originId.trim();
    if (originId.isNotEmpty) return originId;
    return 'pending_origin';
  }
}

class CreateOriginDraft {
  const CreateOriginDraft({
    required this.basics,
    required this.characters,
    required this.locations,
    required this.storyEvents,
    required this.basicsSaved,
    required this.charactersSaved,
    required this.locationsSaved,
    required this.storyEventsSaved,
    this.opening = const OpeningDraft(),
    this.openingSaved = false,
  });

  final BasicsDraft basics;
  final List<CharacterDraft> characters;
  final List<LocationDraft> locations;
  final List<StoryEventDraft> storyEvents;
  final OpeningDraft opening;
  final bool basicsSaved;
  final bool charactersSaved;
  final bool locationsSaved;
  final bool storyEventsSaved;
  final bool openingSaved;

  factory CreateOriginDraft.empty() {
    return const CreateOriginDraft(
      basics: BasicsDraft(),
      characters: <CharacterDraft>[CharacterDraft()],
      locations: <LocationDraft>[LocationDraft()],
      storyEvents: <StoryEventDraft>[StoryEventDraft()],
      opening: OpeningDraft(),
      basicsSaved: false,
      charactersSaved: false,
      locationsSaved: false,
      storyEventsSaved: false,
      openingSaved: false,
    );
  }

  factory CreateOriginDraft.fromJson(Map<String, dynamic> json) {
    final charactersRaw = json['characters'];
    final locationsRaw = json['locations'];
    final storyEventsRaw = json['story_events'];

    return CreateOriginDraft(
      basics: BasicsDraft.fromJson(_asMap(json['basics'])),
      characters: _asList(charactersRaw)
          .map((item) => CharacterDraft.fromJson(_asMap(item)))
          .toList(growable: false),
      locations: _asList(locationsRaw)
          .map((item) => LocationDraft.fromJson(_asMap(item)))
          .toList(growable: false),
      storyEvents: _asList(storyEventsRaw)
          .map((item) => StoryEventDraft.fromJson(_asMap(item)))
          .toList(growable: false),
      opening: OpeningDraft.fromJson(_asMap(json['opening'])),
      basicsSaved: _asBool(json['basics_saved']),
      charactersSaved: _asBool(json['characters_saved']),
      locationsSaved: _asBool(json['locations_saved']),
      storyEventsSaved: _asBool(json['story_events_saved']),
      openingSaved: _asBool(json['opening_saved']),
    ).normalized();
  }

  Map<String, dynamic> toJson() {
    return {
      'basics': basics.toJson(),
      'characters': characters.map((item) => item.toJson()).toList(),
      'locations': locations.map((item) => item.toJson()).toList(),
      'story_events': storyEvents.map((item) => item.toJson()).toList(),
      'opening': opening.toJson(),
      'basics_saved': basicsSaved,
      'characters_saved': charactersSaved,
      'locations_saved': locationsSaved,
      'story_events_saved': storyEventsSaved,
      'opening_saved': openingSaved,
    };
  }

  CreateOriginDraft copyWith({
    BasicsDraft? basics,
    List<CharacterDraft>? characters,
    List<LocationDraft>? locations,
    List<StoryEventDraft>? storyEvents,
    OpeningDraft? opening,
    bool? basicsSaved,
    bool? charactersSaved,
    bool? locationsSaved,
    bool? storyEventsSaved,
    bool? openingSaved,
  }) {
    return CreateOriginDraft(
      basics: basics ?? this.basics,
      characters: characters ?? this.characters,
      locations: locations ?? this.locations,
      storyEvents: storyEvents ?? this.storyEvents,
      opening: opening ?? this.opening,
      basicsSaved: basicsSaved ?? this.basicsSaved,
      charactersSaved: charactersSaved ?? this.charactersSaved,
      locationsSaved: locationsSaved ?? this.locationsSaved,
      storyEventsSaved: storyEventsSaved ?? this.storyEventsSaved,
      openingSaved: openingSaved ?? this.openingSaved,
    ).normalized();
  }

  CreateOriginDraft normalized() {
    return CreateOriginDraft(
      basics: basics,
      characters: characters.isEmpty
          ? const <CharacterDraft>[CharacterDraft()]
          : characters,
      locations: locations.isEmpty
          ? const <LocationDraft>[LocationDraft()]
          : locations,
      storyEvents: storyEvents.isEmpty
          ? const <StoryEventDraft>[StoryEventDraft()]
          : storyEvents,
      opening: opening,
      basicsSaved: basicsSaved,
      charactersSaved: charactersSaved,
      locationsSaved: locationsSaved,
      storyEventsSaved: storyEventsSaved,
      openingSaved: openingSaved,
    );
  }

  CreateOriginDraft pruneLocationBindings(Set<String> validCharacterIds) {
    return copyWith(
      locations: locations
          .map((item) => item.pruneCharacterBindings(validCharacterIds))
          .toList(growable: false),
    );
  }

  /// Saves location edits and removes dialogue only for newly unbound speakers.
  /// Pre-existing invalid dialogue remains available for explicit repair.
  CreateOriginDraft withSavedLocations(List<LocationDraft> updatedLocations) {
    final updated = copyWith(
      locations: updatedLocations,
      locationsSaved: updatedLocations.isNotEmpty,
    );
    final id = opening.locationId.trim();
    if (id.isEmpty) return updated;
    final remaining = updatedLocations.where(
      (location) =>
          (location.level == 0 || location.level == 3) &&
          location.locationId.trim() == id,
    );
    if (remaining.isEmpty) {
      return updated.copyWith(
        opening: const OpeningDraft(),
        openingSaved: false,
      );
    }
    final previousIds = locations
        .where((location) => location.locationId.trim() == id)
        .expand((location) => location.initialCharacterIds)
        .map((id) => id.trim())
        .toSet();
    final currentIds = remaining.first.initialCharacterIds
        .map((id) => id.trim())
        .toSet();
    final removedIds = previousIds.difference(currentIds);
    final dialogue = opening.dialogue
        .where(
          (item) =>
              item.type.trim() != OpeningDialogueDraft.characterType ||
              !removedIds.contains(item.characterId.trim()),
        )
        .toList(growable: false);
    if (dialogue.length == opening.dialogue.length) return updated;
    return updated.copyWith(
      opening: OpeningDraft(
        locationId: opening.locationId,
        locationName: opening.locationName,
        dialogue: dialogue,
      ),
      openingSaved: openingSaved && dialogue.isNotEmpty,
    );
  }

  bool get hasAllSectionsSaved {
    return basicsSaved &&
        charactersSaved &&
        locationsSaved &&
        openingSaved &&
        storyEventsSaved;
  }

  bool get hasRequiredSectionsSaved {
    return basicsSaved && charactersSaved && locationsSaved && openingSaved;
  }

  List<String> validateForSubmit() {
    final errors = <String>[];

    if (!hasRequiredSectionsSaved) {
      final missing = <String>[
        if (!basicsSaved) 'Basics',
        if (!charactersSaved) 'Characters',
        if (!locationsSaved) 'Locations',
        if (!openingSaved) 'Opening',
      ];
      errors.add('Please save ${missing.join(', ')} before creating.');
    }

    if (characters.where(_characterHasContent).isEmpty) {
      errors.add('Characters: Please create at least one character.');
    }
    if (characters.where((item) => item.isRecommended).length > 1) {
      errors.add('Characters: Only one character can be recommended.');
    }

    if (basics.originName.trim().isEmpty) {
      errors.add('Basics: Worldo Name is required.');
    }
    if (basics.worldView.trim().isEmpty) {
      errors.add('Basics: Worldo Brief is required.');
    }
    if (basics.coverImageUrl.trim().isEmpty) {
      errors.add('Basics: Cover Image is required.');
    }
    if (basics.metricJson.trim().isNotEmpty) {
      try {
        jsonDecode(basics.metricJson);
      } catch (_) {
        errors.add('Basics: Metric must be valid JSON.');
      }
    }

    for (int i = 0; i < characters.length; i++) {
      final item = characters[i];
      if (!_characterHasContent(item)) continue;
      if (item.name.trim().isEmpty) {
        errors.add('Characters #${i + 1}: Name is required.');
      }
      if (item.identity.trim().isEmpty) {
        errors.add('Characters #${i + 1}: Identity is required.');
      }
      if (item.personality.trim().isEmpty) {
        errors.add('Characters #${i + 1}: Personality is required.');
      }
    }
    if (!characters.any(_characterIsComplete)) {
      errors.add('Characters: At least one character is required.');
    }

    final leafLocations = locations.where(
      (item) =>
          _locationHasContent(item) && (item.level == 0 || item.level == 3),
    );
    if (leafLocations.isEmpty) {
      errors.add('Locations: Please create at least one location.');
    }
    for (int i = 0; i < locations.length; i++) {
      final item = locations[i];
      if (!_locationHasContent(item)) continue;
      if (item.name.trim().isEmpty) {
        errors.add('Locations #${i + 1}: Location Name is required.');
      }
    }

    if (openingSaved && !opening.isComplete) {
      errors.add(
        'Opening: Select a location and complete every dialogue item.',
      );
    } else if (openingSaved) {
      final validLocationIds = locations
          .where(
            (item) =>
                _locationHasContent(item) &&
                (item.level == 0 || item.level == 3),
          )
          .map(
            (item) => item.locationId.trim().isEmpty
                ? item.name.trim()
                : item.locationId.trim(),
          )
          .where((item) => item.isNotEmpty)
          .toSet();
      if (!validLocationIds.contains(opening.locationId.trim())) {
        errors.add('Opening: The selected location is no longer available.');
      }
      final validCharacterIds = characters
          .map((item) => item.charId.trim())
          .where((item) => item.isNotEmpty)
          .toSet();
      if (opening.dialogue.any(
        (item) =>
            item.type.trim() == OpeningDialogueDraft.characterType &&
            !validCharacterIds.contains(item.characterId.trim()),
      )) {
        errors.add('Opening: A selected character is no longer available.');
      }
      final openingCharacterIds = locations
          .where(
            (location) =>
                (location.level == 0 || location.level == 3) &&
                (location.locationId.trim().isEmpty
                        ? location.name.trim()
                        : location.locationId.trim()) ==
                    opening.locationId.trim(),
          )
          .expand((location) => location.initialCharacterIds)
          .map((id) => id.trim())
          .toSet();
      if (opening.dialogue.any(
        (item) =>
            item.type.trim() == OpeningDialogueDraft.characterType &&
            !openingCharacterIds.contains(item.characterId.trim()),
      )) {
        errors.add(
          'Opening: A dialogue character is not in the selected location. Open Opening to fix it.',
        );
      }
    }

    return errors;
  }

  Map<String, dynamic> toCreateOriginPayload() {
    final payload = <String, dynamic>{
      if (basics.originId.trim().isNotEmpty)
        'origin_id': basics.originId.trim(),
      if (basics.originVersion.trim().isNotEmpty)
        'origin_version': basics.originVersion.trim(),
      'name': normalizeGenesisUgcTextForSubmission(basics.originName),
      'world_view': normalizeGenesisUgcTextForSubmission(basics.worldView),
      'world_setting': normalizeGenesisUgcTextForSubmission(basics.worldLogic),
      'cover': basics.coverImageUrl.trim(),
      if (basics.startedAt.trim().isNotEmpty)
        'started_at': basics.startedAt.trim(),
      if (basics.tickDurationTime.trim().isNotEmpty)
        'tick_duration_time': basics.tickDurationTime.trim()
      else if (basics.tickDurationDays != null)
        'tick_duration_days': basics.tickDurationDays,
      'character_list': characters
          .where(_characterHasContent)
          .map(
            (item) => <String, dynamic>{
              if (item.charId.trim().isNotEmpty) 'char_id': item.charId.trim(),
              'name': normalizeGenesisUgcTextForSubmission(item.name),
              'identity': normalizeGenesisUgcTextForSubmission(item.identity),
              'tagline': normalizeGenesisUgcTextForSubmission(item.personality),
              'description': normalizeGenesisUgcTextForSubmission(item.bio),
              'goal': normalizeGenesisUgcTextForSubmission(item.goal),
              'avatar': item.avatarUrl.trim(),
              'is_recommend': item.isRecommended ? 1 : 0,
            },
          )
          .toList(growable: false),
      'location_list': _createLocationPayloadList(),
      'event_list': storyEvents
          .map((item) => normalizeGenesisUgcTextForSubmission(item.event))
          .where((text) => !isGenesisUgcTextBlank(text))
          .map((text) => <String, dynamic>{'content': text})
          .toList(growable: false),
      if (openingSaved && opening.isComplete)
        'init_location_group': _createOpeningPayload(),
    };

    if (basics.metricJson.trim().isNotEmpty) {
      try {
        payload['metric'] = normalizeGenesisUgcValueForSubmission(
          jsonDecode(basics.metricJson),
        );
      } catch (_) {
        payload['metric_json'] = basics.metricJson.trim();
      }
    }

    return payload;
  }

  Map<String, dynamic> _createOpeningPayload() {
    return <String, dynamic>{
      'location_id': opening.locationId.trim(),
      'initial_dialogue': opening.dialogue
          .map((item) {
            final type = item.type.trim();
            return <String, dynamic>{
              'char_id': switch (type) {
                OpeningDialogueDraft.narratorType => 'nar',
                OpeningDialogueDraft.imageType => 'nar_pic',
                OpeningDialogueDraft.characterType => item.characterId.trim(),
                _ => throw StateError('Unsupported opening dialogue: $type'),
              },
              'content': type == OpeningDialogueDraft.imageType
                  ? item.content.trim()
                  : normalizeGenesisUgcTextForSubmission(item.content),
            };
          })
          .toList(growable: false),
    };
  }

  List<Map<String, dynamic>> _createLocationPayloadList() {
    final userLocations = locations
        .where((item) => item.name.trim().isNotEmpty)
        .toList(growable: false);

    return <Map<String, dynamic>>[
      for (final item in userLocations)
        <String, dynamic>{
          if (item.locationId.trim().isNotEmpty)
            'location_id': item.locationId.trim(),
          if (item.parentLocationId.trim().isNotEmpty)
            'location_pid': item.parentLocationId.trim(),
          if (item.level > 0) 'level': item.level,
          'name': normalizeGenesisUgcTextForSubmission(item.name),
          'image': item.imageUrl.trim(),
          'description': normalizeGenesisUgcTextForSubmission(item.description),
          'initial_character_ids': item.initialCharacterIds,
        },
    ];
  }
}

bool _characterHasContent(CharacterDraft item) {
  return item.isRecommended ||
      item.avatarUrl.trim().isNotEmpty ||
      item.name.trim().isNotEmpty ||
      item.identity.trim().isNotEmpty ||
      item.personality.trim().isNotEmpty ||
      item.bio.trim().isNotEmpty ||
      item.goal.trim().isNotEmpty;
}

bool _characterIsComplete(CharacterDraft item) {
  return item.name.trim().isNotEmpty &&
      item.identity.trim().isNotEmpty &&
      item.personality.trim().isNotEmpty;
}

bool _locationHasContent(LocationDraft item) {
  return item.imageUrl.trim().isNotEmpty ||
      item.name.trim().isNotEmpty ||
      item.description.trim().isNotEmpty ||
      item.initialCharacterIds.isNotEmpty;
}

class BasicsDraft {
  const BasicsDraft({
    this.originId = '',
    this.originVersion = '',
    this.originName = '',
    this.worldView = '',
    this.worldLogic = '',
    this.metricJson = '',
    this.startedAt = '',
    this.tickDurationTime = '',
    this.tickDurationDays,
    this.coverImageUrl = '',
  });

  final String originId;
  final String originVersion;
  final String originName;
  final String worldView;
  final String worldLogic;
  final String metricJson;
  final String startedAt;
  final String tickDurationTime;
  final int? tickDurationDays;
  final String coverImageUrl;

  factory BasicsDraft.fromJson(Map<String, dynamic> json) {
    return BasicsDraft(
      originId: _asString(json['origin_id']),
      originVersion: _asString(json['origin_version']),
      originName: _asString(json['origin_name']),
      worldView: _asString(json['world_view']),
      worldLogic: _asString(json['world_logic']),
      metricJson: _asString(json['metric_json']),
      startedAt: _asString(json['started_at']),
      tickDurationTime: _asString(json['tick_duration_time']),
      tickDurationDays: _asNullableInt(json['tick_duration_days']),
      coverImageUrl: _asString(json['cover_image_url']),
    );
  }

  BasicsDraft copyWith({
    String? originId,
    String? originVersion,
    String? originName,
    String? worldView,
    String? worldLogic,
    String? metricJson,
    String? startedAt,
    Object? tickDurationTime = _unchanged,
    Object? tickDurationDays = _unchanged,
    String? coverImageUrl,
  }) {
    return BasicsDraft(
      originId: originId ?? this.originId,
      originVersion: originVersion ?? this.originVersion,
      originName: originName ?? this.originName,
      worldView: worldView ?? this.worldView,
      worldLogic: worldLogic ?? this.worldLogic,
      metricJson: metricJson ?? this.metricJson,
      startedAt: startedAt ?? this.startedAt,
      tickDurationTime: identical(tickDurationTime, _unchanged)
          ? this.tickDurationTime
          : (tickDurationTime as String?) ?? '',
      tickDurationDays: identical(tickDurationDays, _unchanged)
          ? this.tickDurationDays
          : tickDurationDays as int?,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'origin_id': originId,
      'origin_version': originVersion,
      'origin_name': originName,
      'world_view': worldView,
      'world_logic': worldLogic,
      'metric_json': metricJson,
      'started_at': startedAt,
      if (tickDurationTime.trim().isNotEmpty)
        'tick_duration_time': tickDurationTime,
      if (tickDurationDays != null) 'tick_duration_days': tickDurationDays,
      'cover_image_url': coverImageUrl,
    };
  }
}

class CharacterDraft {
  const CharacterDraft({
    this.charId = '',
    this.avatarUrl = '',
    this.name = '',
    this.identity = '',
    this.personality = '',
    this.bio = '',
    this.goal = '',
    this.isRecommend = 0,
  });

  final String charId;
  final String avatarUrl;
  final String name;
  final String identity;
  final String personality;
  final String bio;
  final String goal;
  final int isRecommend;

  bool get isRecommended => isRecommend == 1;

  factory CharacterDraft.fromJson(Map<String, dynamic> json) {
    return CharacterDraft(
      charId: _asString(json['char_id']),
      avatarUrl: _asString(json['avatar_url']),
      name: _asString(json['name']),
      identity: _asString(json['identity']),
      personality: _asString(json['personality']),
      bio: _asString(json['bio']),
      goal: _asString(json['goal']),
      isRecommend: _asNullableInt(json['is_recommend']) == 1 ? 1 : 0,
    );
  }

  CharacterDraft copyWith({
    String? charId,
    String? avatarUrl,
    String? name,
    String? identity,
    String? personality,
    String? bio,
    String? goal,
    int? isRecommend,
  }) {
    return CharacterDraft(
      charId: charId ?? this.charId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      name: name ?? this.name,
      identity: identity ?? this.identity,
      personality: personality ?? this.personality,
      bio: bio ?? this.bio,
      goal: goal ?? this.goal,
      isRecommend: isRecommend ?? this.isRecommend,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'char_id': charId,
      'avatar_url': avatarUrl,
      'name': name,
      'identity': identity,
      'personality': personality,
      'bio': bio,
      'goal': goal,
      'is_recommend': isRecommended ? 1 : 0,
    };
  }
}

class LocationDraft {
  const LocationDraft({
    this.locationId = '',
    this.parentLocationId = '',
    this.level = 0,
    this.imageUrl = '',
    this.name = '',
    this.description = '',
    this.initialCharacterIds = const <String>[],
  });

  final String locationId;
  final String parentLocationId;
  final int level;
  final String imageUrl;
  final String name;
  final String description;
  final List<String> initialCharacterIds;

  factory LocationDraft.fromJson(Map<String, dynamic> json) {
    return LocationDraft(
      locationId: _asString(json['location_id']),
      parentLocationId: _asString(json['location_pid']),
      level: _asNullableInt(json['level']) ?? 0,
      imageUrl: _asString(json['image_url']),
      name: _asString(json['name']),
      description: _asString(json['description']),
      initialCharacterIds: _asList(json['initial_character_ids'])
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }

  LocationDraft copyWith({
    String? locationId,
    String? parentLocationId,
    int? level,
    String? imageUrl,
    String? name,
    String? description,
    List<String>? initialCharacterIds,
  }) {
    return LocationDraft(
      locationId: locationId ?? this.locationId,
      parentLocationId: parentLocationId ?? this.parentLocationId,
      level: level ?? this.level,
      imageUrl: imageUrl ?? this.imageUrl,
      name: name ?? this.name,
      description: description ?? this.description,
      initialCharacterIds: initialCharacterIds ?? this.initialCharacterIds,
    );
  }

  LocationDraft pruneCharacterBindings(Set<String> validCharacterIds) {
    return copyWith(
      initialCharacterIds: initialCharacterIds
          .where(validCharacterIds.contains)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'location_id': locationId,
      if (parentLocationId.trim().isNotEmpty)
        'location_pid': parentLocationId.trim(),
      if (level > 0) 'level': level,
      'image_url': imageUrl,
      'name': name,
      'description': description,
      'initial_character_ids': initialCharacterIds,
    };
  }
}

class OpeningDraft {
  const OpeningDraft({
    this.locationId = '',
    this.locationName = '',
    this.dialogue = const <OpeningDialogueDraft>[],
  });

  final String locationId;
  final String locationName;
  final List<OpeningDialogueDraft> dialogue;

  bool get isComplete {
    return locationId.trim().isNotEmpty &&
        dialogue.isNotEmpty &&
        dialogue.every((item) => item.isComplete);
  }

  factory OpeningDraft.fromJson(Map<String, dynamic> json) {
    return OpeningDraft(
      locationId: _asString(json['location_id']),
      locationName: _asString(json['location_name']),
      dialogue: _asList(json['dialogue'])
          .map((item) => OpeningDialogueDraft.fromJson(_asMap(item)))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'location_id': locationId,
      'location_name': locationName,
      'dialogue': dialogue.map((item) => item.toJson()).toList(),
    };
  }
}

class OpeningDialogueDraft {
  const OpeningDialogueDraft({
    this.type = '',
    this.content = '',
    this.characterId = '',
  });

  static const String narratorType = 'narrator';
  static const String characterType = 'character';
  static const String imageType = 'image';

  final String type;
  final String content;
  final String characterId;

  bool get isComplete {
    final normalizedType = type.trim();
    if (content.trim().isEmpty) return false;
    if (normalizedType == characterType) {
      return characterId.trim().isNotEmpty;
    }
    return normalizedType == narratorType || normalizedType == imageType;
  }

  factory OpeningDialogueDraft.fromJson(Map<String, dynamic> json) {
    return OpeningDialogueDraft(
      type: _asString(json['type']),
      content: _asString(json['content']),
      characterId: _asString(json['character_id']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'content': content,
      if (characterId.trim().isNotEmpty) 'character_id': characterId,
    };
  }
}

class StoryEventDraft {
  const StoryEventDraft({this.event = ''});

  final String event;

  factory StoryEventDraft.fromJson(Map<String, dynamic> json) {
    return StoryEventDraft(event: _asString(json['event']));
  }

  StoryEventDraft copyWith({String? event}) {
    return StoryEventDraft(event: event ?? this.event);
  }

  Map<String, dynamic> toJson() {
    return {'event': event};
  }
}

List<dynamic> _asList(Object? raw) => raw is List ? raw : const <dynamic>[];

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.map((k, v) => MapEntry('$k', v));
  return const <String, dynamic>{};
}

String _asString(Object? raw) => raw?.toString() ?? '';

int? _asNullableInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString().trim());
}

bool _asBool(Object? raw) => raw == true;
