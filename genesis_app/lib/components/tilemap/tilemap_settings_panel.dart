part of 'tilemap_library.dart';

class _TilemapSettingsButton extends StatelessWidget {
  const _TilemapSettingsButton({required this.isOpen, required this.onPressed});

  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isOpen ? 'Close map settings' : 'Open map settings',
      child: Material(
        color: const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey<String>('tilemap-settings-button'),
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: const SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              Icons.settings_outlined,
              key: ValueKey<String>('tilemap-settings-icon'),
              color: Colors.black,
              size: 20,
              semanticLabel: 'Map settings',
            ),
          ),
        ),
      ),
    );
  }
}

class _TilemapSettingsPanel extends StatelessWidget {
  const _TilemapSettingsPanel({
    required this.visualMode,
    required this.loadingStyle,
    required this.fogControlPoints,
    required this.blendFogWithShadowTiles,
    required this.cacheFogTileBitmaps,
    required this.showShadowZeroBorders,
    required this.showLocationImageFlow,
    required this.locationImageFlowAngleDegrees,
    required this.locationImageFlowGradientPoints,
    required this.locationImageFlowOpacity,
    required this.locationImageFlowDurationSeconds,
    required this.locationImageFlowBlendMode,
    required this.nearbyLocationDistanceTiles,
    required this.distantLocationDistanceTiles,
    required this.nearbyLocationInitialScale,
    required this.distantLocationInitialScale,
    required this.dragBoundaryPaddingTiles,
    required this.onVisualModeChanged,
    required this.onLoadingStyleChanged,
    required this.onFogControlPointsChanged,
    required this.onBlendFogWithShadowTilesChanged,
    required this.onCacheFogTileBitmapsChanged,
    required this.onShowShadowZeroBordersChanged,
    required this.onShowLocationImageFlowChanged,
    required this.onLocationImageFlowAngleDegreesChanged,
    required this.onLocationImageFlowGradientPointsChanged,
    required this.onLocationImageFlowOpacityChanged,
    required this.onLocationImageFlowDurationSecondsChanged,
    required this.onLocationImageFlowBlendModeChanged,
    required this.onNearbyLocationDistanceChanged,
    required this.onDistantLocationDistanceChanged,
    required this.onNearbyLocationInitialScaleChanged,
    required this.onDistantLocationInitialScaleChanged,
    required this.onDragBoundaryPaddingTilesChanged,
    required this.onCopySettings,
    required this.onResetSettings,
    required this.onClose,
  });

  final TilemapVisualMode visualMode;
  final TilemapLoadingStyle loadingStyle;
  final List<TilemapFogControlPoint> fogControlPoints;
  final bool blendFogWithShadowTiles;
  final bool cacheFogTileBitmaps;
  final bool showShadowZeroBorders;
  final bool showLocationImageFlow;
  final double locationImageFlowAngleDegrees;
  final List<TilemapLocationImageFlowGradientPoint>
  locationImageFlowGradientPoints;
  final double locationImageFlowOpacity;
  final double locationImageFlowDurationSeconds;
  final TilemapLocationImageFlowBlendMode locationImageFlowBlendMode;
  final double nearbyLocationDistanceTiles;
  final double distantLocationDistanceTiles;
  final double nearbyLocationInitialScale;
  final double distantLocationInitialScale;
  final double dragBoundaryPaddingTiles;
  final ValueChanged<TilemapVisualMode> onVisualModeChanged;
  final ValueChanged<TilemapLoadingStyle> onLoadingStyleChanged;
  final ValueChanged<List<TilemapFogControlPoint>> onFogControlPointsChanged;
  final ValueChanged<bool> onBlendFogWithShadowTilesChanged;
  final ValueChanged<bool> onCacheFogTileBitmapsChanged;
  final ValueChanged<bool> onShowShadowZeroBordersChanged;
  final ValueChanged<bool> onShowLocationImageFlowChanged;
  final ValueChanged<double> onLocationImageFlowAngleDegreesChanged;
  final ValueChanged<List<TilemapLocationImageFlowGradientPoint>>
  onLocationImageFlowGradientPointsChanged;
  final ValueChanged<double> onLocationImageFlowOpacityChanged;
  final ValueChanged<double> onLocationImageFlowDurationSecondsChanged;
  final ValueChanged<TilemapLocationImageFlowBlendMode>
  onLocationImageFlowBlendModeChanged;
  final ValueChanged<double> onNearbyLocationDistanceChanged;
  final ValueChanged<double> onDistantLocationDistanceChanged;
  final ValueChanged<double> onNearbyLocationInitialScaleChanged;
  final ValueChanged<double> onDistantLocationInitialScaleChanged;
  final ValueChanged<double> onDragBoundaryPaddingTilesChanged;
  final VoidCallback onCopySettings;
  final VoidCallback onResetSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isDark = visualMode == TilemapVisualMode.dark;
    final backgroundColor = isDark
        ? const Color(0xF224241F)
        : const Color(0xF7FFFFFF);
    final foregroundColor = isDark ? Colors.white : const Color(0xFF25251F);
    final secondaryColor = foregroundColor.withValues(alpha: 0.68);
    final dividerColor = foregroundColor.withValues(alpha: 0.14);

    return Material(
      key: const ValueKey<String>('tilemap-settings-panel'),
      elevation: 12,
      color: backgroundColor,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Map settings',
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('tilemap-settings-copy-json'),
                  tooltip: 'Copy settings JSON',
                  visualDensity: VisualDensity.compact,
                  onPressed: onCopySettings,
                  icon: Icon(
                    Icons.copy_all_outlined,
                    color: foregroundColor,
                    size: 19,
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('tilemap-settings-reset'),
                  tooltip: 'Reset settings',
                  visualDensity: VisualDensity.compact,
                  onPressed: onResetSettings,
                  icon: Icon(
                    Icons.restart_alt,
                    color: foregroundColor,
                    size: 19,
                  ),
                ),
                if (isDark)
                  GenesisDarkCloseButton(
                    key: const ValueKey<String>('tilemap-settings-close'),
                    onPressed: onClose,
                  )
                else
                  IconButton(
                    key: const ValueKey<String>('tilemap-settings-close'),
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: Icon(Icons.close, color: foregroundColor, size: 19),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Appearance',
              style: TextStyle(
                color: secondaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TilemapModeChoice(
                    key: const ValueKey<String>('tilemap-settings-mode-light'),
                    label: 'Light',
                    icon: Icons.light_mode_outlined,
                    selected: visualMode == TilemapVisualMode.light,
                    foregroundColor: foregroundColor,
                    onTap: () => onVisualModeChanged(TilemapVisualMode.light),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TilemapModeChoice(
                    key: const ValueKey<String>('tilemap-settings-mode-dark'),
                    label: 'Dark',
                    icon: Icons.dark_mode_outlined,
                    selected: visualMode == TilemapVisualMode.dark,
                    foregroundColor: foregroundColor,
                    onTap: () => onVisualModeChanged(TilemapVisualMode.dark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Loading screen',
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Shown only on the first Tilemap entry.',
              style: TextStyle(color: secondaryColor, fontSize: 10),
            ),
            const SizedBox(height: 5),
            _TilemapLoadingStyleEditor(
              value: loadingStyle,
              foregroundColor: foregroundColor,
              onChanged: onLoadingStyleChanged,
            ),
            const SizedBox(height: 10),
            Text(
              'Automatic initial zoom',
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Uses the nearest top-down location distance and linearly interpolates between both endpoints.',
              style: TextStyle(color: secondaryColor, fontSize: 10),
            ),
            _TilemapSettingsSlider(
              label: 'Nearby distance',
              value: nearbyLocationDistanceTiles,
              min: tilemapLocationDistanceThresholdMin,
              max: tilemapLocationDistanceThresholdMax,
              divisions:
                  ((tilemapLocationDistanceThresholdMax -
                              tilemapLocationDistanceThresholdMin) /
                          tilemapLocationDistanceThresholdStep)
                      .round(),
              valueLabel:
                  '${nearbyLocationDistanceTiles.toStringAsFixed(2)} tiles',
              sliderKey: const ValueKey<String>(
                'tilemap-settings-nearby-location-distance',
              ),
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onNearbyLocationDistanceChanged,
            ),
            _TilemapSettingsSlider(
              label: 'Distant distance',
              value: distantLocationDistanceTiles,
              min: tilemapLocationDistanceThresholdMin,
              max: tilemapLocationDistanceThresholdMax,
              divisions:
                  ((tilemapLocationDistanceThresholdMax -
                              tilemapLocationDistanceThresholdMin) /
                          tilemapLocationDistanceThresholdStep)
                      .round(),
              valueLabel:
                  '${distantLocationDistanceTiles.toStringAsFixed(2)} tiles',
              sliderKey: const ValueKey<String>(
                'tilemap-settings-distant-location-distance',
              ),
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onDistantLocationDistanceChanged,
            ),
            _TilemapSettingsSlider(
              label: 'Zoom at nearby distance',
              value: nearbyLocationInitialScale,
              min: tilemapNearbyLocationInitialScaleMin,
              max: tilemapNearbyLocationInitialScaleMax,
              divisions:
                  (tilemapNearbyLocationInitialScaleMax -
                          tilemapNearbyLocationInitialScaleMin)
                      .round(),
              valueLabel: '${nearbyLocationInitialScale.round()}×',
              sliderKey: const ValueKey<String>(
                'tilemap-settings-nearby-location-scale',
              ),
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onNearbyLocationInitialScaleChanged,
            ),
            _TilemapSettingsSlider(
              label: 'Zoom at distant distance',
              value: distantLocationInitialScale,
              min: tilemapDistantLocationInitialScaleMin,
              max: tilemapDistantLocationInitialScaleMax,
              divisions:
                  (tilemapDistantLocationInitialScaleMax -
                          tilemapDistantLocationInitialScaleMin)
                      .round(),
              valueLabel: '${distantLocationInitialScale.round()}×',
              sliderKey: const ValueKey<String>(
                'tilemap-settings-distant-location-scale',
              ),
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onDistantLocationInitialScaleChanged,
            ),
            const SizedBox(height: 6),
            Text(
              'Drag boundary',
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'The shadow == 1 tile bounds are expanded by this thickness.',
              style: TextStyle(color: secondaryColor, fontSize: 10),
            ),
            _TilemapSettingsSlider(
              label: 'Padding',
              value: dragBoundaryPaddingTiles,
              min: tilemapDragBoundaryPaddingTilesMin,
              max: tilemapDragBoundaryPaddingTilesMax,
              divisions:
                  (tilemapDragBoundaryPaddingTilesMax -
                          tilemapDragBoundaryPaddingTilesMin)
                      .round(),
              valueLabel: '${dragBoundaryPaddingTiles.round()} tiles',
              sliderKey: const ValueKey<String>(
                'tilemap-settings-drag-boundary-padding',
              ),
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onDragBoundaryPaddingTilesChanged,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: dividerColor),
            ),
            _TilemapSettingsSwitch(
              label: 'Show location tile shimmer',
              value: showLocationImageFlow,
              switchKey: const ValueKey<String>(
                'tilemap-settings-location-flow',
              ),
              foregroundColor: foregroundColor,
              onChanged: onShowLocationImageFlowChanged,
            ),
            const SizedBox(height: 4),
            Text(
              'Location shimmer',
              style: TextStyle(
                color: foregroundColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              showLocationImageFlow
                  ? 'Applied to named location tile images.'
                  : 'The effect is off; parameters can still be edited.',
              style: TextStyle(color: secondaryColor, fontSize: 10),
            ),
            _TilemapSettingsSlider(
              label: 'Angle',
              value: locationImageFlowAngleDegrees,
              min: 0,
              max: 360,
              valueLabel: '${locationImageFlowAngleDegrees.round()}°',
              sliderKey: const ValueKey<String>(
                'tilemap-settings-location-flow-angle',
              ),
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onLocationImageFlowAngleDegreesChanged,
            ),
            const SizedBox(height: 5),
            Text(
              'Gradient color stops',
              style: TextStyle(
                color: secondaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            _LocationImageFlowGradientEditor(
              points: locationImageFlowGradientPoints,
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onLocationImageFlowGradientPointsChanged,
            ),
            const SizedBox(height: 4),
            _TilemapSettingsSlider(
              label: 'Opacity',
              value: locationImageFlowOpacity,
              min: 0,
              max: 1,
              valueLabel: '${(locationImageFlowOpacity * 100).round()}%',
              sliderKey: const ValueKey<String>(
                'tilemap-settings-location-flow-opacity',
              ),
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onLocationImageFlowOpacityChanged,
            ),
            _TilemapSettingsSlider(
              label: 'Duration',
              value: locationImageFlowDurationSeconds,
              min: tilemapLocationImageFlowDurationSecondsMin,
              max: tilemapLocationImageFlowDurationSecondsMax,
              valueLabel:
                  '${locationImageFlowDurationSeconds.toStringAsFixed(1)}s',
              sliderKey: const ValueKey<String>(
                'tilemap-settings-location-flow-duration',
              ),
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onLocationImageFlowDurationSecondsChanged,
            ),
            _TilemapLocationImageFlowBlendModeEditor(
              value: locationImageFlowBlendMode,
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onLocationImageFlowBlendModeChanged,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: dividerColor),
            ),
            _TilemapSettingsSwitch(
              label: 'Blend fog with shadow == 1 tiles',
              value: blendFogWithShadowTiles,
              switchKey: const ValueKey<String>('tilemap-settings-fog-blend'),
              foregroundColor: foregroundColor,
              onChanged: onBlendFogWithShadowTilesChanged,
            ),
            _TilemapSettingsSwitch(
              label: 'Cache fog-blended tile bitmaps',
              value: cacheFogTileBitmaps,
              switchKey: const ValueKey<String>(
                'tilemap-settings-fog-bitmap-cache',
              ),
              foregroundColor: foregroundColor,
              onChanged: onCacheFogTileBitmapsChanged,
            ),
            _TilemapSettingsSwitch(
              label: 'Show shadow == 0 wireframe',
              value: showShadowZeroBorders,
              switchKey: const ValueKey<String>('tilemap-settings-wireframe'),
              foregroundColor: foregroundColor,
              onChanged: onShowShadowZeroBordersChanged,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: dividerColor),
            ),
            Text(
              'Fog gradient control points',
              style: TextStyle(
                color: foregroundColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Drag points horizontally for position and vertically for opacity.',
              style: TextStyle(color: secondaryColor, fontSize: 11),
            ),
            const SizedBox(height: 8),
            _FogCurveEditor(
              points: fogControlPoints,
              foregroundColor: foregroundColor,
              secondaryColor: secondaryColor,
              onChanged: onFogControlPointsChanged,
            ),
            const SizedBox(height: 8),
            Text(
              'Opacity fine tuning',
              style: TextStyle(
                color: secondaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            for (var index = 0; index < fogControlPoints.length; index += 1)
              _FogOpacityEditor(
                index: index,
                points: fogControlPoints,
                foregroundColor: foregroundColor,
                secondaryColor: secondaryColor,
                onChanged: onFogControlPointsChanged,
              ),
          ],
        ),
      ),
    );
  }
}

class _TilemapLoadingStyleEditor extends StatelessWidget {
  const _TilemapLoadingStyleEditor({
    required this.value,
    required this.foregroundColor,
    required this.onChanged,
  });

  final TilemapLoadingStyle value;
  final Color foregroundColor;
  final ValueChanged<TilemapLoadingStyle> onChanged;

  String _labelFor(TilemapLoadingStyle style) {
    return switch (style) {
      TilemapLoadingStyle.disabled => 'Off',
      TilemapLoadingStyle.tileAssembly => 'A · Tile assembly',
      TilemapLoadingStyle.worldPortal => 'B · World portal',
      TilemapLoadingStyle.progressiveReveal => 'C · Progressive reveal',
      TilemapLoadingStyle.coordinatePulse => 'D · Coordinate pulse',
      TilemapLoadingStyle.minimalProgress => 'E · Minimal progress',
    };
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: foregroundColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<TilemapLoadingStyle>(
            key: const ValueKey<String>('tilemap-settings-loading-style'),
            value: value,
            isExpanded: true,
            dropdownColor: foregroundColor.computeLuminance() > 0.5
                ? const Color(0xFF35352F)
                : Colors.white,
            iconEnabledColor: foregroundColor,
            style: TextStyle(color: foregroundColor, fontSize: 12),
            items: [
              for (final style in TilemapLoadingStyle.values)
                DropdownMenuItem(value: style, child: Text(_labelFor(style))),
            ],
            onChanged: (style) {
              if (style != null) onChanged(style);
            },
          ),
        ),
      ),
    );
  }
}

class _TilemapModeChoice extends StatelessWidget {
  const _TilemapModeChoice({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.foregroundColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF7C6CF2).withValues(alpha: 0.26)
          : foregroundColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foregroundColor, size: 17),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
