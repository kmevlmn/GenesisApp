import '../../ui/tokens/genesis_blur.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class LocationChatHeaderEffectSettings {
  const LocationChatHeaderEffectSettings({
    required this.transparencyStrength,
    required this.blurSigma,
  });

  static const double minTransparencyStrength = 0;
  static const double maxTransparencyStrength = 1;
  static const double defaultTransparencyStrength = 0;
  static const double minBlurSigma = 0;
  static const double maxBlurSigma = GenesisBlur.strong;
  static const double defaultBlurSigma = GenesisBlur.light;

  static const defaults = LocationChatHeaderEffectSettings(
    transparencyStrength: defaultTransparencyStrength,
    blurSigma: defaultBlurSigma,
  );

  final double transparencyStrength;
  final double blurSigma;

  LocationChatHeaderEffectSettings copyWith({
    double? transparencyStrength,
    double? blurSigma,
  }) {
    return LocationChatHeaderEffectSettings(
      transparencyStrength: transparencyStrength ?? this.transparencyStrength,
      blurSigma: blurSigma ?? this.blurSigma,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LocationChatHeaderEffectSettings &&
        other.transparencyStrength == transparencyStrength &&
        other.blurSigma == blurSigma;
  }

  @override
  int get hashCode => Object.hash(transparencyStrength, blurSigma);
}

final locationChatHeaderEffectSettings =
    LocationChatHeaderEffectSettingsController();

class LocationChatHeaderEffectSettingsController
    extends ValueNotifier<LocationChatHeaderEffectSettings> {
  LocationChatHeaderEffectSettingsController()
    : super(LocationChatHeaderEffectSettings.defaults);

  static const String transparencyStorageKey =
      'developer_location_chat_surface_opacity_v4';
  static const String blurSigmaStorageKey =
      'developer_location_chat_surface_blur_sigma_v4';

  bool _loaded = false;
  int _revision = 0;
  Future<LocationChatHeaderEffectSettings>? _pendingLoad;

  Future<LocationChatHeaderEffectSettings> load() {
    if (_loaded) {
      return SynchronousFuture<LocationChatHeaderEffectSettings>(value);
    }
    final pending = _pendingLoad;
    if (pending != null) return pending;
    final load = _readStoredSettings();
    _pendingLoad = load;
    return load.whenComplete(() {
      if (identical(_pendingLoad, load)) _pendingLoad = null;
    });
  }

  Future<LocationChatHeaderEffectSettings> _readStoredSettings() async {
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = LocationChatHeaderEffectSettings(
        transparencyStrength:
            _storedDouble(
                  prefs,
                  transparencyStorageKey,
                  LocationChatHeaderEffectSettings.defaultTransparencyStrength,
                )
                .clamp(
                  LocationChatHeaderEffectSettings.minTransparencyStrength,
                  LocationChatHeaderEffectSettings.maxTransparencyStrength,
                )
                .toDouble(),
        blurSigma: GenesisBlur.normalize(
          _storedDouble(
            prefs,
            blurSigmaStorageKey,
            LocationChatHeaderEffectSettings.defaultBlurSigma,
          ),
        ),
      );
      if (revision == _revision) {
        value = loaded;
        _loaded = true;
      }
    } catch (_) {
      if (revision == _revision) _loaded = true;
    }
    return value;
  }

  void previewTransparencyStrength(double transparencyStrength) {
    _revision += 1;
    _loaded = true;
    value = value.copyWith(
      transparencyStrength: transparencyStrength
          .clamp(
            LocationChatHeaderEffectSettings.minTransparencyStrength,
            LocationChatHeaderEffectSettings.maxTransparencyStrength,
          )
          .toDouble(),
    );
  }

  void previewBlurSigma(double blurSigma) {
    _revision += 1;
    _loaded = true;
    value = value.copyWith(blurSigma: GenesisBlur.normalize(blurSigma));
  }

  Future<void> save() async {
    final current = value;
    final prefs = await SharedPreferences.getInstance();
    final transparencySaved = await prefs.setDouble(
      transparencyStorageKey,
      current.transparencyStrength,
    );
    final blurSaved = await prefs.setDouble(
      blurSigmaStorageKey,
      current.blurSigma,
    );
    if (!transparencySaved || !blurSaved) {
      throw StateError('Failed to save LocationChat header effects.');
    }
  }

  static double _storedDouble(
    SharedPreferences prefs,
    String key,
    double fallback,
  ) {
    final stored = prefs.get(key);
    return stored is num ? stored.toDouble() : fallback;
  }

  @visibleForTesting
  void resetForTesting() {
    _revision += 1;
    _loaded = false;
    _pendingLoad = null;
    value = LocationChatHeaderEffectSettings.defaults;
  }
}
