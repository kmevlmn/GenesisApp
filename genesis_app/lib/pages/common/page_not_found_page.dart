import 'package:flutter/material.dart';

import '../../components/page_header.dart';

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
    return Scaffold(
      appBar: GenesisBackAppBar(
        pageName: '',
        onBack: () => _handleBack(context),
      ),
      body: const Center(child: Text('Page not found.')),
    );
  }
}
