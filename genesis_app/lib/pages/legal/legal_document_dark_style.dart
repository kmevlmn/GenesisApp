import 'dart:convert';
import 'dart:ui';

import '../../ui/tokens/genesis_colors.dart';

bool isWorldoLegalDocument(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'worldo.ai' &&
      (!uri.hasPort || uri.port == 443) &&
      const {
        '/terms',
        '/privacy',
        '/eula',
      }.contains(uri.path.replaceFirst(RegExp(r'/$'), ''));
}

String _cssColor(Color color) =>
    'rgba(${(color.r * 255).round()}, ${(color.g * 255).round()}, '
    '${(color.b * 255).round()}, ${color.a})';

/// Override the first-party legal site's palette without changing its content
/// or layout. Colors remain derived from the same tokens as native pages.
String legalDocumentDarkStyleScript({required String readyMessage}) {
  final background = _cssColor(GenesisColors.darkBackground);
  final primary = _cssColor(GenesisColors.darkTextPrimary);
  final secondary = _cssColor(GenesisColors.darkTextSecondary);
  final tertiary = _cssColor(GenesisColors.darkTextTertiary);
  final fill = _cssColor(GenesisColors.darkFaintFill);
  final raised = _cssColor(GenesisColors.darkRaisedBackground);
  final css =
      '''
:root {
  color-scheme: dark !important;
  --ink: $secondary !important;
  --muted: $tertiary !important;
  --line: $fill !important;
  --panel: $raised !important;
  --accent: $primary !important;
  --accent-ink: $primary !important;
  --paper: $background !important;
  --warn-bg: $fill !important;
  --warn-line: $fill !important;
}
html, body { background: $background !important; color: $secondary !important; }
h1, h2, h3, h4, h5, h6, strong, .brand { color: $primary !important; }
.lead { color: $secondary !important; }
.updated, .site-footer { color: $tertiary !important; }
.site-header { background: $background !important; }
''';
  return '''
(() => {
  if (location.origin !== 'https://worldo.ai' ||
      !['/terms', '/terms/', '/privacy', '/privacy/', '/eula', '/eula/']
        .includes(location.pathname)) return false;
  const id = 'genesis-legal-dark-style';
  let style = document.getElementById(id);
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    document.head.appendChild(style);
  }
  style.textContent = ${jsonEncode(css)};
  // A script result only confirms the DOM mutation. Keep the native view
  // covered until a rendering opportunity has passed with the new palette.
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      GenesisLegalStyleReady.postMessage(${jsonEncode(readyMessage)});
    });
  });
  return true;
})()
''';
}
