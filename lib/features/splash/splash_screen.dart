import 'package:flutter/material.dart';

import '../../core/widgets/brand.dart';
import '../../core/widgets/loader.dart';

/// The `/` gate — shown only while the session resolves. Always dark navy so
/// the hand-off from the native launch screen is seamless.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: WaveBackdrop(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FlowLogo(size: 120),
              const SizedBox(height: 28),
              const FlowWordmark(),
              const SizedBox(height: 48),
              const FlowLoader(size: 30),
            ],
          ),
        ),
      ),
    );
  }
}
