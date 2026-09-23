import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';

/// Opens [url] for the user. Injected into [AboutScreen] so the screen can be
/// tested without launching a real browser.
typedef LinkOpener = Future<bool> Function(Uri url);

/// Hands the link to the device's browser rather than an in-app web view: the
/// source and privacy pages are the council-facing record, and the user may
/// want to keep them.
Future<bool> openInBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

const String sourcesUrl = 'https://whenisbins.com/sources';
const String privacyUrl = 'https://whenisbins.com/privacy';
const String aiAgentsUrl =
    'https://loosemore.com/2026/02/25/ai-agents-will-join-up-government-'
    'before-government-does/';

/// A short About: what the app does, who operates it, and what the
/// demonstrator is really for. Mirrors the wording of the service it reads
/// from, so an answer given in the app can be checked against the same
/// explanation on the website.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.openLink = openInBrowser});

  final LinkOpener openLink;

  static const _paragraphStyle = TextStyle(fontSize: 16, height: 1.5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _paragraph(const [
            TextSpan(
              text: 'When Is Bins tells you when to put your bins out. '
                  'Enter your postcode, pick your address, done. Add the '
                  'dates to your calendar or get an email reminder. All of '
                  'it built by LLMs.',
            ),
          ]),
          const SizedBox(height: 20),
          _paragraph([
            const TextSpan(
              text: 'When Is Bins is a free, independent demonstrator '
                  'operated and funded by Public Digital Limited. Coverage '
                  'and the dates available vary. For help, corrections, '
                  'accessibility problems or privacy requests, email '
                  'hello@whenisbins.com, or use the feedback link on the '
                  'page concerned. Your council handles missed collections '
                  'and changes to its service. Read ',
            ),
            _link('Sources', sourcesUrl),
            const TextSpan(text: ' for how to interpret an answer and '),
            _link('Privacy', privacyUrl),
            const TextSpan(text: ' for how we use information.'),
          ]),
          const SizedBox(height: 20),
          _paragraph([
            const TextSpan(
              text: 'But a UK-wide bin day website isn\u2019t the point. '
                  'The point is to learn how to respond to what\u2019s '
                  'coming. And what\u2019s coming is ',
            ),
            _link('AI agents', aiAgentsUrl),
            const TextSpan(text: '.'),
          ]),
        ],
      ),
    );
  }

  Widget _paragraph(List<InlineSpan> spans) => Text.rich(
        TextSpan(children: spans),
        style: _paragraphStyle,
      );

  InlineSpan _link(String label, String url) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Semantics(
          // container: true gives the link its own node. Without it the
          // annotation merges upward into the paragraph, so a link that ends
          // the paragraph turns the entire sentence into one button — announced
          // as a button, and tappable anywhere along the line.
          container: true,
          // A GestureDetector around a Text is invisible to assistive tech: no
          // button role, nothing to tap by voice.
          button: true,
          child: GestureDetector(
            onTap: () => openLink(Uri.parse(url)),
            child: Text(
              label,
              style: _paragraphStyle.copyWith(
                color: AppColors.teal,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.teal,
              ),
            ),
          ),
        ),
      );
}