
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/theme/radii.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/media.dart';
import '../../core/widgets/picker_field.dart';
import '../../core/widgets/sheets.dart';
import '../../data/firestore_paths.dart';
import '../../data/models/app_user.dart';
import '../../providers/providers.dart';
import '../../services/image_service.dart';
import '../onboarding/onboarding_widgets.dart';

/// Edit personal details (§3.13, §9.4). Save stays disabled until the form
/// differs from its loaded snapshot; leaving dirty prompts to discard (also
/// intercepts predictive back). Trainer rate and spot are deliberately not
/// editable here (§14.3).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  AppUser? _snapshot;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _age = TextEditingController();
  final _bio = TextEditingController();

  XFile? _newAvatar;
  String? _nationality;
  String? _level;
  List<String> _languages = [];
  List<String> _existingGallery = [];
  final List<XFile> _newGallery = [];

  bool _busy = false;
  bool _attempted = false;

  /// Last value [_dirty] was rebuilt for — see [_onTextChanged].
  bool _lastDirty = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider).value;
    if (user != null) _load(user);
    for (final c in [_name, _phone, _age, _bio]) {
      c.addListener(_onTextChanged);
    }
  }

  /// Only two things on this screen react to a keystroke: whether Save is
  /// enabled, and the inline errors once you have tried to submit. Rebuilding
  /// unconditionally re-ran four `FormGroup`s, two picker fields and the
  /// gallery grid on every character typed into the bio — the whole form, to
  /// produce an identical tree, 200 characters in a row.
  ///
  /// It also cost a second full build on arrival: [_load] runs from `build()`
  /// and assigns all four controllers, and each assignment re-marked the
  /// element that was building at the time. Flutter permits that — you are in
  /// scope of your own build target — so it never showed up as an error, only
  /// as a frame's worth of work nobody asked for.
  void _onTextChanged() {
    final dirty = _dirty;
    if (_attempted || dirty != _lastDirty) {
      setState(() => _lastDirty = dirty);
    }
  }

  void _load(AppUser user) {
    _snapshot = user;
    _name.text = user.name;
    _phone.text = user.phoneNumber ?? '';
    _nationality = user.nationality;
    _age.text = user.age?.toString() ?? '';
    _bio.text = user.bio ?? '';
    _level = user.level;
    _languages = [...user.languages];
    _existingGallery = [...user.gallery];
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _age, _bio]) {
      c.removeListener(_onTextChanged);
      c.dispose();
    }
    super.dispose();
  }

  bool get _dirty {
    final s = _snapshot;
    if (s == null) return false;
    bool listChanged(List<String> a, List<String> b) =>
        a.length != b.length || !a.every(b.contains);
    return _newAvatar != null ||
        _newGallery.isNotEmpty ||
        _name.text.trim() != s.name ||
        _phone.text.trim() != (s.phoneNumber ?? '') ||
        _nationality != s.nationality ||
        _age.text.trim() != (s.age?.toString() ?? '') ||
        _bio.text.trim() != (s.bio ?? '') ||
        _level != s.level ||
        listChanged(_languages, s.languages) ||
        listChanged(_existingGallery, s.gallery);
  }

  String? get _nameError =>
      _attempted && _name.text.trim().isEmpty ? 'Your name is required' : null;
  String? get _languagesError =>
      _attempted && _languages.isEmpty ? 'Pick at least one language' : null;

  Future<void> _save() async {
    setState(() => _attempted = true);
    if (_nameError != null || _languagesError != null) return;
    final s = _snapshot;
    if (s == null) return;

    setState(() => _busy = true);
    try {
      final storage = ref.read(storageRepositoryProvider);
      String? photoUrl;
      if (_newAvatar != null) {
        photoUrl = await storage.upload(
            folder: StorageFolder.profiles, file: _newAvatar!, ownerId: s.uid);
      }
      List<String>? gallery;
      if (_newGallery.isNotEmpty ||
          _existingGallery.length != s.gallery.length) {
        final uploaded = await storage.uploadAll(
            folder: StorageFolder.galleries,
            files: _newGallery,
            ownerId: s.uid);
        gallery = [..._existingGallery, ...uploaded];
      }

      await ref.read(userRepositoryProvider).updateProfile(
            s.uid,
            name: _name.text.trim(),
            phoneNumber:
                _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            nationality: _nationality,
            age: int.tryParse(_age.text.trim()),
            level: s.isTrainer ? null : _level,
            bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
            languages: _languages,
            photoUrl: photoUrl,
            gallery: gallery,
            // A null above means "leave this alone", so an emptied optional
            // field has to be named here or it is never actually removed.
            clear: {
              if (_phone.text.trim().isEmpty) 'phoneNumber',
              if (_nationality == null) 'nationality',
              if (_bio.text.trim().isEmpty) 'bio',
              if (_age.text.trim().isEmpty) 'age',
            },
          );
      Haptics.medium();
      if (mounted) {
        showFlowToast(context, 'Profile updated');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        // Was a flat "Check your connection", which is the one cause this
        // almost never has: a rejected write comes back from the server, so
        // the connection demonstrably worked. Blaming the network sent people
        // to their wifi settings for a permissions problem.
        showFlowToast(context, "Couldn't save. ${ErrorView.friendly(e)}");
      }
    }
  }

  Future<void> _confirmLeave() async {
    final discard = await confirmAction(
      context,
      title: 'Discard changes?',
      body: "You've made changes that aren't saved yet.",
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
    );
    if (discard && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    // First arrival of the profile (e.g. cold start on this route).
    if (_snapshot == null && userAsync.value != null) {
      _load(userAsync.value!);
    }
    final user = _snapshot;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Personal details')),
        body: const SkeletonList(count: 5),
      );
    }

    final isTrainer = user.isTrainer;

    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Personal details'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: FilledButton(
                  // Disabled until something actually changes (§9.4).
                  onPressed: _dirty && !_busy ? _save : null,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(76, 40),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16)),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Center(
              child: AvatarPicker(
                file: _newAvatar,
                existingUrl: user.photoUrl,
                enabled: !_busy,
                onPicked: (f) => setState(() => _newAvatar = f),
              ),
            ),
            const SizedBox(height: 24),
            FormGroup(
              label: 'Full name',
              required: true,
              errorText: _nameError,
              child: TextField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            FormGroup(
              label: 'Email',
              // initialValue, not a controller: this is read-only, and a
              // controller built in build() leaks one undisposed instance per
              // rebuild — and the state listeners rebuild this form on every
              // keystroke in the fields above. TextFormField owns and
              // disposes its own controller.
              child: TextFormField(
                key: ValueKey(user.email),
                initialValue: user.email,
                enabled: false,
                decoration: const InputDecoration(
                    helperText: 'Your email is your sign-in and cannot change.'),
              ),
            ),
            FormGroup(
              label: 'Phone',
              child: TextField(
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: '+20 …'),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: FormGroup(
                    label: 'Nationality',
                    child: FlowPickerField(
                      values: [?_nationality],
                      options: FlowConst.nationalities,
                      sheetTitle: 'Nationality',
                      enabled: !_busy,
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
                    child: TextField(
                      controller: _age,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (!isTrainer)
              FormGroup(
                label: 'Kite level',
                child: FlowPickerField(
                  values: [?_level],
                  options: FlowConst.riderLevels,
                  sheetTitle: 'Kite level',
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _level = v.firstOrNull),
                ),
              ),
            if (isTrainer)
              FormGroup(
                label: 'Training spot',
                // Read-only — see the Email field above on why this is not a
                // build-time TextEditingController.
                child: TextFormField(
                  key: ValueKey(user.location),
                  initialValue: user.location ?? '',
                  enabled: false,
                  decoration: const InputDecoration(
                      helperText:
                          "Message support if you've moved spots."),
                ),
              ),
            FormGroup(
              label: 'Bio',
              child: TextField(
                controller: _bio,
                enabled: !_busy,
                maxLines: 4,
              ),
            ),
            FormGroup(
              label: 'Languages',
              required: true,
              errorText: _languagesError,
              child: FlowPickerField(
                values: _languages,
                options: FlowConst.languages,
                sheetTitle: 'Languages',
                sheetSubtitle: 'Search, or add one that is not listed.',
                hintText: 'Add a language',
                multiSelect: true,
                allowCustom: true,
                enabled: !_busy,
                hasError: _languagesError != null,
                onChanged: (v) => setState(() => _languages = v),
              ),
            ),
            if (isTrainer)
              FormGroup(
                label: 'Gallery',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _existingGallery.length; i++)
                      ThumbTile(
                        onRemove: _busy
                            ? null
                            : () => setState(
                                () => _existingGallery.removeAt(i)),
                        child: FlowImage(
                          url: _existingGallery[i],
                          width: 84,
                          height: 84,
                          borderRadius: FlowRadii.chip,
                        ),
                      ),
                    for (var i = 0; i < _newGallery.length; i++)
                      ThumbTile.file(
                        _newGallery[i].path,
                        isNew: true,
                        onRemove: _busy
                            ? null
                            : () =>
                                setState(() => _newGallery.removeAt(i)),
                      ),
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final picked = await ImageService
                                    .pickMultiCropped(context);
                                if (picked.isNotEmpty) {
                                  setState(
                                      () => _newGallery.addAll(picked));
                                }
                              },
                        style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: const RoundedRectangleBorder(
                                borderRadius: FlowRadii.chip)),
                        child: const Icon(
                            Symbols.add_photo_alternate_rounded),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
