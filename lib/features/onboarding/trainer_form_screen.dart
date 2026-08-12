import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/media.dart';
import '../../core/widgets/picker_field.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/firestore_paths.dart';
import '../../providers/providers.dart';
import '../../services/image_service.dart';
import '../media/crop_screen.dart';
import 'onboarding_validators.dart';
import 'onboarding_widgets.dart';

/// Trainer onboarding — 4 gated steps (§3.2, §9.3).
///
/// The Next button is **always tappable**; tapping on an incomplete step
/// marks it "attempted", reveals the inline hints (quiet until then) and
/// scrolls to the first problem. Steps slide in the direction of travel.
///
/// With [reapply] the same four steps become the correction form a declined
/// trainer fixes their application in: every field arrives filled with what
/// they submitted last time, the photo, gallery and certificate they already
/// uploaded stay uploaded unless they replace them, and submitting puts the
/// application back in the queue rather than creating a profile. Written as
/// a mode on this screen rather than a second screen because the fields, the
/// gating and the validation are the same — a copy would drift, and it is
/// the *declined* form that would be the stale one.
class TrainerFormScreen extends ConsumerStatefulWidget {
  const TrainerFormScreen({super.key, this.reapply = false});

  final bool reapply;

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

  // What is already on the profile, in re-application mode. A trainer who
  // does not re-pick their photo keeps the one they have; without these the
  // form would demand a fresh upload of every image to fix a typo in a bio.
  String? _existingPhotoUrl;
  String? _existingCertificateUrl;
  List<String> _existingGallery = const [];

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // knownName, not displayName — an empty field is honest, "Rider" is not.
    _name.text = ref.read(sessionProvider).knownName;
    if (widget.reapply) _prefillFromProfile();
  }

  void _prefillFromProfile() {
    final user = ref.read(sessionProvider).user;
    if (user == null) return;
    _name.text = user.name;
    _bio.text = user.bio ?? '';
    _languages = [...user.languages];
    _spot = user.location;
    _mapsLink.text = user.mapsLink ?? '';
    final rate = user.hourlyRate;
    if (rate != null) _rate.text = '${rate.round()}';
    _ikoId.text = user.ikoId ?? '';
    _existingPhotoUrl = user.photoUrl;
    _existingCertificateUrl = user.certificateUrl;
    _existingGallery = [...user.gallery];
  }

  bool get _hasPhoto => _photo != null || (_existingPhotoUrl ?? '').isNotEmpty;

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

  // Per-step gates (§9.3). Each defers to the shared validators so the
  // Continue button and the inline messages below cannot drift apart.
  String? get _nameError => OnboardingValidators.name(_name.text);
  String? get _bioError => _bio.text.trim().isEmpty
      ? 'Riders read this first — say something'
      : OnboardingValidators.bio(_bio.text);
  String? get _rateError => OnboardingValidators.rate(_rate.text);
  String? get _ikoError {
    final value = _ikoId.text.trim();
    if (value.isEmpty) return 'Required';
    if (value.length < 4) return 'That looks too short';
    return null;
  }

  bool get _step1Ok =>
      _hasPhoto &&
      _nameError == null &&
      _bioError == null &&
      _languages.isNotEmpty;
  bool get _step2Ok => _spot != null;
  bool get _step3Ok => _rateError == null;
  bool get _step4Ok => _ikoError == null;

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
    // Submitting hands the application to a human and locks the trainer
    // behind the review gate until someone answers. Worth a beat either way,
    // and the wording differs because the two situations do.
    final ok = await confirmAction(
      context,
      title: widget.reapply
          ? 'Send for review again?'
          : 'Submit your application?',
      body: widget.reapply
          ? 'Your corrected application goes back into our review queue.'
          : 'Our team checks your certification by hand. You will be live '
              'for riders the moment it is approved.',
      confirmLabel: widget.reapply ? 'Send for review' : 'Submit',
      cancelLabel: 'Keep editing',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      final storage = ref.read(storageRepositoryProvider);
      final repo = ref.read(userRepositoryProvider);

      // Only newly picked files are uploaded. On a re-application the images
      // already on the profile are kept as they are — re-uploading a photo
      // that has not changed costs the trainer their data allowance to
      // produce a byte-identical file.
      final photoUrl = _photo != null
          ? await storage.upload(
              folder: StorageFolder.profiles,
              file: _photo!,
              ownerId: session.uid)
          : _existingPhotoUrl!;
      final galleryUrls = [
        ..._existingGallery,
        ...await storage.uploadAll(
            folder: StorageFolder.galleries,
            files: _gallery,
            ownerId: session.uid),
      ];
      String? certificateUrl = _existingCertificateUrl;
      if (_certificate != null) {
        certificateUrl = await storage.upload(
            folder: StorageFolder.certificates,
            file: _certificate!,
            ownerId: session.uid);
      }

      final spot = _spot!;
      final rate = int.parse(_rate.text.trim());
      final mapsLink =
          _mapsLink.text.trim().isEmpty ? null : _mapsLink.text.trim();

      if (widget.reapply) {
        await repo.resubmitTrainerApplication(
          session.uid,
          name: _name.text.trim(),
          bio: _bio.text.trim(),
          languages: _languages,
          trainingSpot: spot,
          mapsLink: mapsLink,
          hourlyRate: rate,
          ikoId: _ikoId.text.trim(),
          certificateUrl: certificateUrl,
          photoUrl: photoUrl,
          gallery: galleryUrls,
        );
      } else {
        await repo.createTrainerProfile(
          uid: session.uid,
          name: _name.text.trim(),
          email: session.firebaseUser?.email ?? '',
          bio: _bio.text.trim(),
          languages: _languages,
          trainingSpot: spot,
          mapsLink: mapsLink,
          hourlyRate: rate,
          ikoId: _ikoId.text.trim(),
          certificateUrl: certificateUrl,
          photoUrl: photoUrl,
          gallery: galleryUrls,
        );
      }
      Haptics.medium();
      // Session flips to awaitingApproval; the router shows the gate.
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showFlowToast(context,
            "Couldn't submit your application. ${ErrorView.friendly(e)}");
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
                        duration: FlowMotion.base,
                        curve: FlowMotion.curve,
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
                  duration: FlowMotion.slow,
                  // Asymmetric on purpose, and left as-is: the step slides in
                  // decelerating and out accelerating, which reads as travel
                  // in a direction rather than a cross-fade. `FlowMotion.curve`
                  // is the same easeOutCubic; only the outgoing half differs.
                  switchInCurve: FlowMotion.curve,
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
                        child: const Icon(Symbols.arrow_back_rounded, size: 20),
                      ),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: _step < 3 ? 'Continue' : 'Submit for review',
                        icon: _step < 3 ? null : Symbols.verified_rounded,
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
            existingUrl: _existingPhotoUrl,
            enabled: !_busy,
            onPicked: (f) => setState(() => _photo = f),
          ),
        ),
        if (attempted && !_hasPhoto)
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
          // The gate getter, not a second rule. These used to re-implement
          // their own checks: `length <= 2` flagged a 2-character name the
          // validator accepts (a red message over a step that advanced
          // anyway), while an over-length name or bio failed _step1Ok and
          // displayed nothing at all — Continue did nothing and said nothing.
          errorText: attempted ? _nameError : null,
          child: TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            // Only once the step has been attempted does anything on screen
            // depend on this text — `errorText` above is the sole reader, and
            // it is null until then. Rebuilding the whole step per keystroke
            // before that produced a byte-identical tree. Continue is never
            // disabled (`onPressed: _next`), so nothing else is waiting on it.
            onChanged: attempted ? (_) => setState(() {}) : null,
          ),
        ),
        FormGroup(
          label: 'Professional bio',
          required: true,
          errorText: attempted ? _bioError : null,
          child: TextField(
            controller: _bio,
            enabled: !_busy,
            maxLines: 4,
            // Matches the rider form: the ceiling is visible while typing
            // rather than discovered by a Continue that refuses.
            maxLength: OnboardingValidators.maxBioLength,
            decoration: const InputDecoration(
                hintText: 'Years teaching, certifications, style…'),
            // As above. The character counter under this field is drawn by
            // TextField's own state, so it keeps updating regardless.
            onChanged: attempted ? (_) => setState(() {}) : null,
          ),
        ),
        FormGroup(
          label: 'Languages',
          required: true,
          errorText: attempted && _languages.isEmpty
              ? 'Pick at least one language'
              : null,
          child: FlowPickerField(
            values: _languages,
            options: FlowConst.languages,
            sheetTitle: 'Languages',
            sheetSubtitle: 'Riders filter by these. Add any that are missing.',
            hintText: 'Add a language',
            multiSelect: true,
            allowCustom: true,
            enabled: !_busy,
            hasError: attempted && _languages.isEmpty,
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
                ThumbTile.file(
                  _gallery[i].path,
                  onRemove: () => setState(() => _gallery.removeAt(i)),
                ),
              SizedBox(
                width: 84,
                height: 84,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final picked =
                              await ImageService.pickMultiCropped(context);
                          if (picked.isNotEmpty) {
                            setState(() => _gallery.addAll(picked));
                          }
                        },
                  style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: FlowRadii.chip)),
                  child: const Icon(Symbols.add_photo_alternate_rounded),
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
          child: FlowPickerField(
            values: [?_spot],
            options: FlowConst.kiteSpots,
            sheetTitle: 'Kite spot',
            sheetSubtitle: 'The beach you actually teach from.',
            hintText: 'Select your spot',
            enabled: !_busy,
            hasError: attempted && _spot == null,
            onChanged: (v) => setState(() => _spot = v.firstOrNull),
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
            'You set the price. One hourly rate, settled in person at the '
                'centre. FLOW takes nothing.'),
        FormGroup(
          label: 'Hourly rate',
          required: true,
          errorText: attempted
              ? OnboardingValidators.rate(_rate.text)
              : null,
          child: TextField(
            controller: _rate,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              // Six digits, not three: the band is gone and EGP prices run to
              // four figures, so a three-character limit would have silently
              // truncated every real rate to a tenth of itself.
              LengthLimitingTextInputFormatter(6),
            ],
            style: display(32, 720, color: context.scheme.onSurface),
            decoration: InputDecoration(
              prefixText: 'EGP ',
              prefixStyle: display(22, 720, color: tones.azureBrand),
              hintText: '400',
              helperText: 'Per hour. You can change this any time.',
            ),
            // Unguarded, unlike the other fields: the earnings notice below
            // reads `_rate.text` live, so this one really does have to
            // rebuild on every keystroke.
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 12),
        // Suggestions, not limits — a starting point for a trainer who has
        // never had to name a number before.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in FlowConst.rateSuggestions)
              ActionChip(
                label: Text(money(suggestion)),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _rate.text = '$suggestion';
                          _rate.selection = TextSelection.collapsed(
                              offset: _rate.text.length);
                        }),
              ),
          ],
        ),
        if (_step3Ok)
          FlowNotice(
            icon: Symbols.payments_rounded,
            title:
                'A 3-hour session earns you ${money(int.parse(_rate.text) * 3)}.',
            tone: tones.success,
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
            onChanged: attempted ? (_) => setState(() {}) : null,
          ),
        ),
        FormGroup(
          label: 'Certificate photo',
          child: _certificate == null
              ? OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          // Rectangular: a certificate is a document, and the
                          // crop step lets them straighten out the desk
                          // around a phone photo of it.
                          final picked = await ImageService.pickWithSheet(
                              context,
                              shape: CropShape.rect);
                          if (picked != null) {
                            setState(() => _certificate = picked);
                          }
                        },
                  icon: const Icon(Symbols.upload_file_rounded, size: 20),
                  label: const Text('Upload certificate (optional)'),
                )
              : Row(
                  children: [
                    ClipRRect(
                      borderRadius: FlowRadii.chip,
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
                      icon: const Icon(Symbols.delete_outline_rounded),
                    ),
                  ],
                ),
        ),
        FlowNotice(
          icon: Symbols.hourglass_top_rounded,
          title: 'Reviewed by hand',
          body: "After you submit, we review your application. You'll be "
              'live for riders the moment an admin approves it.',
          tone: tones.azureBrand,
        ),
      ],
    );
  }
}
