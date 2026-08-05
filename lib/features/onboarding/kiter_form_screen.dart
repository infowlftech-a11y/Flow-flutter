import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/picker_field.dart';
import '../../data/firestore_paths.dart';
import '../../providers/providers.dart';
import 'onboarding_validators.dart';
import 'onboarding_widgets.dart';

/// Rider onboarding — one page (§3.2, §9.2). On failure the first unmet
/// field scrolls into view. Back-navigation is blocked while saving (§10.5).
class KiterFormScreen extends ConsumerStatefulWidget {
  const KiterFormScreen({super.key});

  @override
  ConsumerState<KiterFormScreen> createState() => _KiterFormScreenState();
}

class _KiterFormScreenState extends ConsumerState<KiterFormScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _bio = TextEditingController();

  XFile? _avatar;
  String _level = 'Independent';
  String? _homeSpot;
  String? _nationality;
  List<String> _languages = [];
  List<String> _quiver = [];

  bool _attempted = false;
  bool _busy = false;

  final _nameKey = GlobalKey();
  final _detailsKey = GlobalKey();
  final _languagesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // knownName, not displayName — an empty field is honest, "Rider" is not.
    _name.text = ref.read(sessionProvider).knownName;
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _bio.dispose();
    super.dispose();
  }

  // Validation lives in one place per field so the submit-time scroll target
  // and the inline message can never disagree about what is wrong.
  String? get _nameError {
    if (!_attempted) return null;
    return OnboardingValidators.name(_name.text);
  }

  String? get _nationalityError =>
      _attempted && _nationality == null ? 'Pick your nationality' : null;

  String? get _ageError {
    if (!_attempted) return null;
    return OnboardingValidators.age(_age.text);
  }

  String? get _languagesError =>
      _attempted && _languages.isEmpty ? 'Pick at least one language' : null;

  String? get _bioError {
    if (!_attempted) return null;
    return OnboardingValidators.bio(_bio.text);
  }

  Future<void> _submit() async {
    setState(() => _attempted = true);
    // Scroll the first unmet field into view: name → details row → languages.
    final GlobalKey? firstProblem = _nameError != null
        ? _nameKey
        : (_nationalityError != null || _ageError != null)
            ? _detailsKey
            : (_languagesError != null || _bioError != null)
                ? _languagesKey
                : null;
    if (firstProblem != null) {
      final ctx = firstProblem.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300),
            alignment: .1,
            curve: Curves.easeOutCubic);
      }
      return;
    }

    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      String? photoUrl;
      if (_avatar != null) {
        photoUrl = await ref.read(storageRepositoryProvider).upload(
              folder: StorageFolder.profiles,
              file: _avatar!,
              ownerId: session.uid,
            );
      }
      await ref.read(userRepositoryProvider).createRiderProfile(
            uid: session.uid,
            name: _name.text.trim(),
            email: session.firebaseUser?.email ?? '',
            nationality: _nationality!,
            age: int.parse(_age.text.trim()),
            level: _level,
            homeSpot: _homeSpot,
            languages: _languages,
            quiver: _quiver,
            bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
            photoUrl: photoUrl,
          );
      Haptics.medium();
      // The profile stream flips the session to ready; the router takes over.
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showFlowToast(
            context, "Couldn't save your profile. Check your connection.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Set up your profile')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Center(
                child: AvatarPicker(
                  file: _avatar,
                  enabled: !_busy,
                  onPicked: (f) => setState(() => _avatar = f),
                ),
              ),
              const SizedBox(height: 26),
              FormGroup(
                key: _nameKey,
                label: 'Full name',
                required: true,
                errorText: _nameError,
                child: TextField(
                  controller: _name,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(hintText: 'How riders know you'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              KeyedSubtree(
                key: _detailsKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: FormGroup(
                        label: 'Nationality',
                        required: true,
                        errorText: _nationalityError,
                        child: FlowPickerField(
                          values: [?_nationality],
                          options: FlowConst.nationalities,
                          sheetTitle: 'Nationality',
                          hintText: 'Select',
                          enabled: !_busy,
                          hasError: _nationalityError != null,
                          onChanged: (v) =>
                              setState(() => _nationality = v.firstOrNull),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: FormGroup(
                        label: 'Age',
                        required: true,
                        errorText: _ageError,
                        child: TextField(
                          controller: _age,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: const InputDecoration(hintText: '18'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              FormGroup(
                label: 'Kite level',
                child: FlowPickerField(
                  values: [_level],
                  options: FlowConst.riderLevels,
                  sheetTitle: 'Kite level',
                  sheetSubtitle: 'Sets what trainers see before your first session.',
                  enabled: !_busy,
                  onChanged: (v) =>
                      setState(() => _level = v.firstOrNull ?? 'Independent'),
                ),
              ),
              FormGroup(
                label: 'Home spot',
                child: FlowPickerField(
                  values: [?_homeSpot],
                  options: FlowConst.kiteSpots,
                  sheetTitle: 'Home spot',
                  hintText: 'Where you ride most',
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _homeSpot = v.firstOrNull),
                ),
              ),
              FormGroup(
                key: _languagesKey,
                label: 'Languages',
                required: true,
                errorText: _languagesError,
                child: FlowPickerField(
                  values: _languages,
                  options: FlowConst.languages,
                  sheetTitle: 'Languages',
                  sheetSubtitle: 'Search, or add one that is not listed.',
                  hintText: 'Add the languages you speak',
                  multiSelect: true,
                  allowCustom: true,
                  enabled: !_busy,
                  hasError: _languagesError != null,
                  onChanged: (v) => setState(() => _languages = v),
                ),
              ),
              FormGroup(
                label: 'Your quiver',
                child: FlowPickerField(
                  values: _quiver,
                  options: FlowConst.quiverSuggestions,
                  sheetTitle: 'Your quiver',
                  sheetSubtitle: 'Kites and boards you bring with you.',
                  hintText: 'Add your gear',
                  multiSelect: true,
                  allowCustom: true,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _quiver = v),
                ),
              ),
              FormGroup(
                label: 'Short bio',
                errorText: _bioError,
                child: TextField(
                  controller: _bio,
                  enabled: !_busy,
                  maxLines: 3,
                  maxLength: OnboardingValidators.maxBioLength,
                  decoration: const InputDecoration(
                      hintText: 'A line about you and your riding'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              PrimaryButton(
                label: "Let's ride",
                icon: Icons.kitesurfing_rounded,
                busy: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
