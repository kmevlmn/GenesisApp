import 'package:flutter/widgets.dart';

import '../theme/genesis_ui_theme.dart';

class GenesisPageTitle extends StatelessWidget {
  const GenesisPageTitle({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GenesisUiTheme.of(context).pageTitleStyle,
    );
  }
}
