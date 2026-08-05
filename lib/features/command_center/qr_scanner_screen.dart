import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';

/// Trainer QR check-in scanner (§3.10).
///
/// Rear camera, no-duplicate detection, torch toggle reflecting real torch
/// state. Payload must be JSON with `bookingId` + `trainerId`, and the
/// trainerId must match the scanning trainer — failures show an inline
/// banner for 3s and **keep the camera open**. Pops with the bookingId on
/// success after a 250ms emerald flash.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, required this.trainerId});

  final String trainerId;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  // `noDuplicates` suppresses a repeat of the same barcode for the life of
  // the controller, which broke retrying a *rejected* ticket: after "This
  // ticket belongs to another trainer" the trainer re-aims at the very same
  // QR and gets nothing — no banner, no haptic — so the scanner looks dead
  // and the only way out is backing out and reopening it. `normal` keeps
  // emitting; the guards in _onDetect do the de-duplication we actually
  // want, which is "one accepted scan" rather than "one scan ever".
  late final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
  );

  String? _warning;
  Timer? _warningTimer;
  bool _captured = false;

  @override
  void dispose() {
    _warningTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _warn(String message) {
    Haptics.error();
    _warningTimer?.cancel();
    setState(() => _warning = message);
    _warningTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _warning = null);
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_captured) return;
    // While a warning is on screen, swallow detections: `normal` speed fires
    // many times a second, and without this the banner would re-arm its
    // timer forever and never clear. Once it does clear, the same code is
    // free to be scanned again — which is the whole point.
    if (_warning != null) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } catch (_) {
      payload = null;
    }
    if (payload == null ||
        payload['bookingId'] is! String ||
        payload['trainerId'] is! String) {
      _warn("That's not a FLOW ticket.");
      return;
    }
    if (payload['trainerId'] != widget.trainerId) {
      _warn('This ticket belongs to another trainer.');
      return;
    }

    // Valid — flash emerald for 250ms, then pop with the booking id.
    setState(() => _captured = true);
    Haptics.medium();
    final bookingId = payload['bookingId'] as String;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) Navigator.pop(context, bookingId);
    });
  }

  @override
  Widget build(BuildContext context) {
    const cutout = 260.0;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // Denied/unavailable camera → explanation + retry, never a black
            // void (§3.10).
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined,
                        color: FlowColors.haze, size: 44),
                    const SizedBox(height: 18),
                    Text('Camera unavailable',
                        style: sora(20, 700, color: FlowColors.mist)),
                    const SizedBox(height: 8),
                    Text(
                      'FLOW needs the camera to scan rider tickets. Check the '
                      'camera permission in your system settings, then retry.',
                      textAlign: TextAlign.center,
                      style: inter(13.5, 460,
                          color: FlowColors.haze, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _controller.start(),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Scrimmed viewfinder cutout.
          IgnorePointer(
            child: CustomPaint(
              painter: _ScrimPainter(cutout: cutout, success: _captured),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _RoundButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Close scanner',
                        onTap: () => Navigator.pop(context),
                      ),
                      // Torch icon reflects actual torch state.
                      ValueListenableBuilder(
                        valueListenable: _controller,
                        builder: (context, state, _) {
                          final on = state.torchState == TorchState.on;
                          return _RoundButton(
                            icon: on
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            tooltip: on ? 'Torch off' : 'Torch on',
                            active: on,
                            onTap: () => _controller.toggleTorch(),
                          );
                        },
                      ),
                    ],
                  ),
                  const Spacer(),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _warning == null
                        ? Text(
                            "Point at the rider's ticket",
                            style: inter(14.5, 600, color: Colors.white),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: FlowColors.coral,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: Colors.white, size: 19),
                                const SizedBox(width: 9),
                                Flexible(
                                  child: Text(_warning!,
                                      style: inter(13.5, 640,
                                          color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.cutout, required this.success});

  final double cutout;
  final bool success;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 40);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: cutout, height: cutout),
      const Radius.circular(28),
    );

    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
        scrim, Paint()..color = Colors.black.withValues(alpha: .55));

    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        // Emerald flash on capture (§3.10).
        ..color = success ? FlowColors.emerald : Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter oldDelegate) =>
      oldDelegate.success != success;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? FlowColors.azure
            : Colors.black.withValues(alpha: .4),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon,
                size: 22, color: active ? FlowColors.ink : Colors.white),
          ),
        ),
      ),
    );
  }
}
