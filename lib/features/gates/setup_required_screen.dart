import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/brand.dart';
import '../../core/firebase_config.dart';

/// Shown instead of the app when the build has no real Firebase API key.
///
/// Without this, the first symptom of a missing key is a user filling in the
/// registration form and being told "Something went wrong" — a message that
/// blames them for a build problem and tells whoever is debugging nothing.
/// This states the actual cause and the exact fix.
class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});

  static const _steps = [
    (
      '1',
      'Register this package in Firebase',
      'This build ships as ${FlowFirebase.androidPackageName}, which '
          'is not the package the existing Firebase Android app was created '
          'for. Add a new Android app for it under Project settings.',
    ),
    (
      '2',
      'Run flutterfire configure',
      'flutterfire configure --project=go-kite-ccc33  regenerates '
          'lib/firebase_options.dart with the new appId and the real API key, '
          'and writes android/app/google-services.json for push delivery.',
    ),
    (
      '3',
      'Rebuild',
      'Stop the app and run it again — a full restart is required, hot reload '
          'will not re-initialise Firebase.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: FlowColors.ink,
        body: WaveBackdrop(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
              children: [
                const Center(child: FlowLogo(size: 72)),
                const SizedBox(height: 28),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: FlowColors.amber.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('SETUP REQUIRED',
                      textAlign: TextAlign.center,
                      style: inter(11, 800,
                          color: FlowColors.amber, spacing: 1.4)),
                ),
                const SizedBox(height: 18),
                Text(
                  'Firebase is not configured',
                  textAlign: TextAlign.center,
                  style:
                      sora(26, 760, color: FlowColors.mist, spacing: -.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'lib/firebase_options.dart still contains the placeholder '
                  'API key, so every sign-in, registration and database read '
                  'will fail with API_KEY_INVALID.',
                  textAlign: TextAlign.center,
                  style: inter(14.5, 440,
                      color: FlowColors.haze, height: 1.55),
                ),
                const SizedBox(height: 30),
                for (final (number, title, body) in _steps)
                  _Step(number: number, title: title, body: body),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: () => Clipboard.setData(const ClipboardData(
                        text:
                            'flutterfire configure --project=go-kite-ccc33')),
                    icon: const Icon(Icons.copy_rounded,
                        size: 17, color: FlowColors.azure),
                    label: Text('Copy the configure command',
                        style: inter(13.5, 620, color: FlowColors.azure)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FlowColors.azure.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(number,
                style: interNum(13.5, 760, color: FlowColors.azure)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: inter(15, 660, color: FlowColors.mist)),
                const SizedBox(height: 4),
                Text(body,
                    style: inter(13, 440,
                        color: FlowColors.haze, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
