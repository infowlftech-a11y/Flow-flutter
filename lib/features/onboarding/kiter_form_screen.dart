import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/misc.dart';
import '../../data/firestore_paths.dart';
import '../../providers/providers.dart';
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
  final _nationality = TextEditingController();
  final _age = TextEditingController();
  final _bio = TextEditingController();

  XFile? _avatar;
  String _level = 'Independent';
  String? _homeSpot;
  List<String> _languages = [];
  final List<String> _quiver = [];

  bool _attempted = false;
  bool _busy = false;

  final _nameKey = GlobalKey();
  final _detailsKey = GlobalKey();
  final _languagesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(sessionProvider).displayName;
  }

  @override
  void dispose() {
    _name.dispose();
    _nationality.dispose();
    _age.dispose();
    _bio.dispose();
    super.dispose();
  }

  String? get _nameError =>
      _attempted && _name.text.trim().isEmpty ? 'Your name is required' : null;
  String? get _nationalityError => _attempted && _nationality.text.trim().isEmpty
      ? 'Where are you from?'
      : null;
  String? get _ageError {
    if (!_attempted) return null;
    final age = int.tryParse(_age.text.trim());
    if (age == null || age < 8 || age > 99) return '8–99';
    return null;
  }

  String? get _languagesError =>
      _attempted && _languages.isEmpty ? 'Pick at least one language' : null;

  Future<void> _submit() async {
    setState(() => _attempted = true);
    // Scroll the first unmet field into view: name → details row → languages.
    final GlobalKey? firstProblem = _nameError != null
        ? _nameKey
        : (_nationalityError != null || _ageError != null)
            ? _detailsKey
            : _languagesError != null
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
            nationality: _nationality.text.trim(),
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
                        child: TextField(
                          controller: _nationality,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          decoration:
                              const InputDecoration(hintText: 'e.g. German'),
                          onChanged: (_) => setState(() {}),
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
                child: ChipSelect(
                  options: FlowConst.riderLevels,
                  value: _level,
                  onChanged: (v) =>
                      setState(() => _level = v ?? 'Independent'),
                ),
              ),
              FormGroup(
                label: 'Home spot',
                child: ChipSelect(
                  options: FlowConst.kiteSpots,
                  value: _homeSpot,
                  onChanged: (v) => setState(() => _homeSpot = v),
                ),
              ),
              FormGroup(
                key: _languagesKey,
                label: 'Languages',
                required: true,
                child: LanguagePicker(
                  selected: _languages,
                  errorText: _languagesError,
                  onChanged: (v) => setState(() => _languages = v),
                ),
              ),
              FormGroup(
                label: 'Your quiver',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in FlowConst.quiverSuggestions)
                      FlowChoiceChip(
                        label: q,
                        selected: _quiver.contains(q),
                        onTap: () {
                          Haptics.select();
                          setState(() => _quiver.contains(q)
                              ? _quiver.remove(q)
                              : _quiver.add(q));
                        },
                      ),
                  ],
                ),
              ),
              FormGroup(
                label: 'Short bio',
                child: TextField(
                  controller: _bio,
                  enabled: !_busy,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText: 'A line about you and your riding'),
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
