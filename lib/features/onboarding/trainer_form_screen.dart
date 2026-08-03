import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../data/firestore_paths.dart';
import '../../providers/providers.dart';
import '../../services/image_service.dart';
import 'onboarding_widgets.dart';

/// Trainer onboarding — 4 gated steps (§3.2, §9.3).
///
/// The Next button is **always tappable**; tapping on an incomplete step
/// marks it "attempted", reveals the inline hints (quiet until then) and
/// scrolls to the first problem. Steps slide in the direction of travel.
class TrainerFormScreen extends ConsumerStatefulWidget {
  const TrainerFormScreen({super.key});

  @override
  ConsumerState<TrainerFormScreen> createState() => _TrainerFormScreenState();
}

class _TrainerFormScreenState extends ConsumerState<TrainerFormScreen> {
  int _step = 0;
  int _lastStep = 0;
  final _attempted = <int>{};
  bool _busy = false;

  // Step 1 — profile
  XFile? _photo;
  final _name = TextEditingController();
  final _bio = TextEditingController();
  List<String> _languages = [];
  final List<XFile> _gallery = [];

  // Step 2 — spot
  String? _spot;
  final _mapsLink = TextEditingController();

  // Step 3 — rate
  final _rate = TextEditingController();

  // Step 4 — verification
  final _ikoId = TextEditingController();
  XFile? _certificate;

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(sessionProvider).displayName;
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _mapsLink.dispose();
    _rate.dispose();
    _ikoId.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Per-step gates (§9.3).
  bool get _step1Ok =>
      _photo != null &&
      _name.text.trim().length > 2 &&
      _bio.text.trim().isNotEmpty &&
      _languages.isNotEmpty;
  bool get _step2Ok => _spot != null;
  bool get _step3Ok {
    final rate = int.tryParse(_rate.text.trim());
    return rate != null &&
        rate >= FlowConst.minHourlyRate &&
        rate <= FlowConst.maxHourlyRate;
  }

  bool get _step4Ok => _ikoId.text.trim().length > 3;

  bool _stepOk(int step) =>
      [_step1Ok, _step2Ok, _step3Ok, _step4Ok][step];

  void _next() {
    if (!_stepOk(_step)) {
      Haptics.select();
      setState(() => _attempted.add(_step));
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
      return;
    }
    if (_step < 3) {
      Haptics.select();
      setState(() {
        _lastStep = _step;
        _step++;
      });
      _scroll.jumpTo(0);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() {
      _lastStep = _step;
      _step--;
    });
    _scroll.jumpTo(0);
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      final storage = ref.read(storageRepositoryProvider);

      final photoUrl = await storage.upload(
          folder: StorageFolder.profiles, file: _photo!, ownerId: session.uid);
      final galleryUrls = await storage.uploadAll(
          folder: StorageFolder.galleries,
          files: _gallery,
          ownerId: session.uid);
      String? certificateUrl;
      if (_certificate != null) {
        certificateUrl = await storage.upload(
            folder: StorageFolder.certificates,
            file: _certificate!,
            ownerId: session.uid);
      }

      await ref.read(userRepositoryProvider).createTrainerProfile(
            uid: session.uid,
            name: _name.text.trim(),
            email: session.firebaseUser?.email ?? '',
            bio: _bio.text.trim(),
            languages: _languages,
            trainingSpot: _spot!,
            mapsLink: _mapsLink.text.trim().isEmpty
                ? null
                : _mapsLink.text.trim(),
            hourlyRate: int.parse(_rate.text.trim()),
            ikoId: _ikoId.text.trim(),
            certificateUrl: certificateUrl,
            photoUrl: photoUrl,
            gallery: galleryUrls,
          );
      Haptics.medium();
      // Session flips to awaitingApproval; the router shows the gate.
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showFlowToast(context,
            "Couldn't submit your application. Check your connection.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attempted = _attempted.contains(_step);
    final forward = _step >= _lastStep;

    return PopScope(
      canPop: !_busy && _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Become a trainer'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(26),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _step
                              ? context.tones.azureBrand
                              : context.tones.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (i < 3) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    // Slide in the direction of travel (§10.9).
                    final entering =
                        child.key == ValueKey('step$_step');
                    final begin = entering
                        ? Offset(forward ? .12 : -.12, 0)
                        : Offset.zero;
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(begin: begin, end: Offset.zero)
                            .animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: SingleChildScrollView(
                    key: ValueKey('step$_step'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                    child: switch (_step) {
                      0 => _buildStep1(attempted),
                      1 => _buildStep2(attempted),
                      2 => _buildStep3(attempted),
                      _ => _buildStep4(attempted),
                    },
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: BoxDecoration(
                  border:
                      Border(top: BorderSide(color: context.tones.line)),
                ),
                child: Row(
                  children: [
                    if (_step > 0)
                      OutlinedButton(
                        onPressed: _busy ? null : _back,
                        child: const Icon(Icons.arrow_back_rounded, size: 20),
                      ),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: _step < 3 ? 'Continue' : 'Submit for review',
                        icon: _step < 3 ? null : Icons.verified_outlined,
                        busy: _busy,
                        onPressed: _next,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String title, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 6),
          Text(sub, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
        ],
      );

  Widget _buildStep1(bool attempted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Your trainer profile',
            'This is what riders see first. Make it count.'),
        Center(
          child: AvatarPicker(
            file: _photo,
            enabled: !_busy,
            onPicked: (f) => setState(() => _photo = f),
          ),
        ),
        if (attempted && _photo == null)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('A profile photo is required',
                  style: inter(12.5, 560, color: context.tones.danger)),
            ),
          ),
        const SizedBox(height: 24),
        FormGroup(
          label: 'Name',
          required: true,
          errorText: attempted && _name.text.trim().length <= 2
              ? 'At least 3 characters'
              : null,
          child: TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
        ),
        FormGroup(
          label: 'Professional bio',
          required: true,
          errorText: attempted && _bio.text.trim().isEmpty
              ? 'Tell riders about your experience'
              : null,
          child: TextField(
            controller: _bio,
            enabled: !_busy,
            maxLines: 4,
            decoration: const InputDecoration(
                hintText: 'Years teaching, certifications, style…'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        FormGroup(
          label: 'Languages',
          required: true,
          child: LanguagePicker(
            selected: _languages,
            errorText: attempted && _languages.isEmpty
                ? 'Pick at least one language'
                : null,
            onChanged: (v) => setState(() => _languages = v),
          ),
        ),
        FormGroup(
          label: 'Gallery',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _gallery.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(_gallery[i].path),
                          width: 84, height: 84, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Semantics(
                        button: true,
                        label: 'Remove photo',
                        child: GestureDetector(
                          onTap: () => setState(() => _gallery.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              SizedBox(
                width: 84,
                height: 84,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final picked = await ImageService.pickMulti();
                          if (picked.isNotEmpty) {
                            setState(() => _gallery.addAll(picked));
                          }
                        },
                  style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Icon(Icons.add_photo_alternate_outlined),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep2(bool attempted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Your training spot',
            'Riders filter by spot — pick where you actually teach.'),
        FormGroup(
          label: 'Kite spot',
          required: true,
          errorText:
              attempted && _spot == null ? 'Pick your home spot' : null,
          child: ChipSelect(
            options: FlowConst.kiteSpots,
            value: _spot,
            onChanged: (v) => setState(() => _spot = v),
          ),
        ),
        FormGroup(
          label: 'Google Maps link',
          child: TextField(
            controller: _mapsLink,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                hintText: 'https://maps.app.goo.gl/…',
                helperText:
                    'Optional — riders can jump straight to your beach.'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3(bool attempted) {
    final tones = context.tones;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Your rate',
            'One hourly price, settled in person at the centre. '
                'FLOW takes nothing.'),
        FormGroup(
          label: 'Hourly rate',
          required: true,
          errorText: attempted && !_step3Ok
              ? 'Between €${FlowConst.minHourlyRate} and €${FlowConst.maxHourlyRate}'
              : null,
          child: TextField(
            controller: _rate,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            style: sora(30, 720, color: context.scheme.onSurface),
            decoration: InputDecoration(
              prefixText: '€ ',
              prefixStyle: sora(30, 720, color: tones.azureBrand),
              hintText: '80',
              helperText:
                  'Platform range: €${FlowConst.minHourlyRate}–€${FlowConst.maxHourlyRate}/h',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (_step3Ok)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tones.successTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.payments_outlined, color: tones.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'A 3-hour session earns you ${euro(int.parse(_rate.text) * 3)}.',
                    style: inter(13.5, 580, color: tones.success),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStep4(bool attempted) {
    final tones = context.tones;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Verification',
            'Every FLOW trainer is certified. Our team checks this by hand.'),
        FormGroup(
          label: 'IKO / VDWS ID',
          required: true,
          errorText: attempted && !_step4Ok
              ? 'Enter your full certification ID'
              : null,
          child: TextField(
            controller: _ikoId,
            enabled: !_busy,
            decoration: const InputDecoration(hintText: 'e.g. IKO-482913'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        FormGroup(
          label: 'Certificate photo',
          child: _certificate == null
              ? OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final picked =
                              await ImageService.pickWithSheet(context);
                          if (picked != null) {
                            setState(() => _certificate = picked);
                          }
                        },
                  icon: const Icon(Icons.upload_file_rounded, size: 20),
                  label: const Text('Upload certificate (optional)'),
                )
              : Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(_certificate!.path),
                          width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Certificate attached',
                          style: inter(14, 580, color: tones.success)),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _certificate = null),
                      tooltip: 'Remove certificate',
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tones.azureBrand.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.hourglass_top_rounded, color: tones.azureBrand),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "After you submit, we review your application. You'll be "
                  'live for riders the moment an admin approves it.',
                  style: inter(13, 500,
                      color: context.scheme.onSurfaceVariant, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
