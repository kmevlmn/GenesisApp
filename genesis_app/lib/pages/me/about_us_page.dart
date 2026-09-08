import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../components/common/genesis_center_toast.dart';
import '../../components/page_header.dart';
import '../../platform/app/app_metadata_service.dart';
import '../../routers/app_router.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../legal/legal_document_page.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  static const _fallbackAppVersion = 'v1.0.0';
  static const _descriptionBeforeEmail =
      'Worldo lets you create, discover, and enter AI-powered worlds filled '
      'with characters, stories, and evolving events. Chat with AI characters, '
      'play with friends, and progress each world through immersive scenes and '
      'choices.\n\n'
      'Our app offers a new way to experience interactive stories — not just '
      'as a reader, but as someone inside the world. If you have any questions, '
      'please contact us at ';
  static const _contactEmail = 'worldodeveloper@gmail.com';

  static String versionLabel(String versionName) {
    final trimmed = versionName.trim();
    return trimmed.isEmpty ? _fallbackAppVersion : 'v$trimmed';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GenesisBackAppBar(pageName: 'About'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
                children: [
                  const _AboutBrandHeader(),
                  const SizedBox(height: 8),
                  const _AboutVersionText(),
                  const SizedBox(height: 34),
                  const _AboutDescription(),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _AboutLegalLinks(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _AboutVersionText extends StatelessWidget {
  const _AboutVersionText();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppVersionInfo>(
      future: AppMetadataService.appVersion(),
      builder: (context, snapshot) {
        final versionName = snapshot.data?.versionName.trim() ?? '';

        return Text(
          AboutUsPage.versionLabel(versionName),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w400,
            color: Colors.black,
          ),
        );
      },
    );
  }
}

class _AboutDescription extends StatefulWidget {
  const _AboutDescription();

  @override
  State<_AboutDescription> createState() => _AboutDescriptionState();
}

class _AboutDescriptionState extends State<_AboutDescription> {
  late final TapGestureRecognizer _emailRecognizer;

  @override
  void initState() {
    super.initState();
    _emailRecognizer = TapGestureRecognizer()..onTap = _copyEmail;
  }

  @override
  void dispose() {
    _emailRecognizer.dispose();
    super.dispose();
  }

  Future<void> _copyEmail() async {
    await Clipboard.setData(
      const ClipboardData(text: AboutUsPage._contactEmail),
    );
    if (mounted) showGenesisToast(context, 'Email copied');
  }

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(
      fontSize: 15,
      height: 1.55,
      fontWeight: FontWeight.w400,
      color: Color(0xFF333333),
    );
    final emailStyle = bodyStyle.copyWith(
      color: const Color(0xFF3E5B8A),
      fontWeight: FontWeight.w600,
    );

    return Text.rich(
      TextSpan(
        style: bodyStyle,
        children: [
          const TextSpan(text: AboutUsPage._descriptionBeforeEmail),
          TextSpan(
            text: AboutUsPage._contactEmail,
            style: emailStyle,
            recognizer: _emailRecognizer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.left,
    );
  }
}

class _AboutBrandHeader extends StatelessWidget {
  const _AboutBrandHeader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SvgPicture.asset(
        'assets/svg/worldo-logo.svg',
        key: const Key('about_genesis_launch_logo'),
        width: 236,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _AboutLegalLinks extends StatefulWidget {
  const _AboutLegalLinks();

  @override
  State<_AboutLegalLinks> createState() => _AboutLegalLinksState();
}

class _AboutLegalLinksState extends State<_AboutLegalLinks> {
  late final TapGestureRecognizer _privacyRecognizer;
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _eulaRecognizer;

  @override
  void initState() {
    super.initState();
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocument.privacy);
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocument.terms);
    _eulaRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(LegalDocument.eula);
  }

  @override
  void dispose() {
    _privacyRecognizer.dispose();
    _termsRecognizer.dispose();
    _eulaRecognizer.dispose();
    super.dispose();
  }

  void _openDocument(LegalDocument document) {
    Navigator.of(
      context,
    ).pushNamed(RouteNames.legal, arguments: {'document': document.name});
  }

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(
      fontSize: 11,
      height: 1.35,
      color: Color(0xFF6F6F6F),
      fontWeight: FontWeight.w400,
    );
    const linkStyle = TextStyle(
      fontSize: 11,
      height: 1.35,
      color: GenesisColors.brand,
      fontWeight: FontWeight.w600,
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          style: bodyStyle,
          children: [
            TextSpan(
              text: 'Privacy Policy',
              style: linkStyle,
              recognizer: _privacyRecognizer,
            ),
            const TextSpan(text: ' , '),
            TextSpan(
              text: 'Terms of Use',
              style: linkStyle,
              recognizer: _termsRecognizer,
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'End User License Agreement',
              style: linkStyle,
              recognizer: _eulaRecognizer,
            ),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.left,
      ),
    );
  }
}
