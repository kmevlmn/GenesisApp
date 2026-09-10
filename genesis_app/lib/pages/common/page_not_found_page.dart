import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/page_header.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/tokens/genesis_colors.dart';

class PageNotFoundPage extends StatelessWidget {
  const PageNotFoundPage({super.key, this.fallbackRouteName = '/home'});

  final String fallbackRouteName;

  void _handleBack(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacementNamed(fallbackRouteName);
  }

  @override
  Widget build(BuildContext context) {
    return GenesisDarkTheme(
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: GenesisColors.darkBackground,
          appBar: GenesisBackAppBar(
            backgroundColor: GenesisColors.darkBackground,
            foregroundColor: GenesisColors.darkTextPrimary,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            pageName: '',
            onBack: () => _handleBack(context),
          ),
          body: const Center(
            child: Text(
              'Page not found.',
              style: TextStyle(color: GenesisColors.darkTextSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
