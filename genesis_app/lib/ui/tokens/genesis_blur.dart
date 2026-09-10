/// Background glass blur strengths. Zero remains available to disable blur.
abstract final class GenesisBlur {
  static const double light = 4;
  static const double strong = 14;
  static const List<double> presets = [0, light, strong];

  static double normalize(double sigma) {
    if (!sigma.isFinite) return light;
    if (sigma <= 0) return 0;
    return sigma <= (light + strong) / 2 ? light : strong;
  }
}
