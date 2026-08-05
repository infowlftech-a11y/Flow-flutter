// Test-data seeder. NOT part of the app — this is a second entry point, run
// deliberately:
//
//   flutter run -t lib/dev/seed_app.dart
//
// It lives outside `main.dart`'s import graph, so nothing here is compiled
// into a normal build.
//
// Two passes:
//   1. accounts   — 9 auth users + their profile documents (this file)
//   2. activity   — bookings, reviews, chats, notifications, calendar blocks
//                   and an expedition (seed_content.dart)
//
// ## Why it works this way
//
// Everything is created through the *client* SDK as the user themselves,
// because there is no service-account key in this repo and the Admin SDK
// cannot run on a device. That has one unavoidable consequence:
// `createUserWithEmailAndPassword` signs you in as the account it just made,
// so the accounts are created strictly one at a time, each writing its own
// profile while it holds the session, then signing out.
//
// It also means the seeder is bound by `firestore.rules` exactly like a real
// user (see `allow create` on /users):
//
//   * riders   → role 'kiter',    status 'active'   ✅ allowed
//   * trainers → role 'business', status 'pending'  ✅ allowed
//   * admins   → role 'admin'                       ❌ REFUSED, by design
//
// So a trainer cannot be seeded pre-approved, and an admin cannot be seeded
// at all. Both are deliberate: they are the rules that stop a rider
// self-approving as a trainer or promoting themselves to staff. The admin
// account is therefore created as an ordinary account, and you flip its role
// once by hand in the Firebase console — the same first-admin step the
// README describes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../core/firebase_config.dart';
import '../firebase_options.dart';
import 'seed_content.dart';
import 'seed_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!FlowFirebase.isConfigured) {
    runApp(const _Fatal(
        'Firebase is not configured — check firebase_options.dart.'));
    return;
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SeederApp());
}

class SeederApp extends StatelessWidget {
  const SeederApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FLOW seeder',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const SeederScreen(),
      );
}

class SeederScreen extends StatefulWidget {
  const SeederScreen({super.key});

  @override
  State<SeederScreen> createState() => _SeederScreenState();
}

class _SeederScreenState extends State<SeederScreen> {
  final _log = <_LogLine>[];
  final _scroll = ScrollController();
  bool _running = false;
  bool _done = false;

  /// Off gives you accounts and nothing else — useful when you want to see
  /// every screen in its empty state.
  bool _withActivity = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _say(String message, SeedLevel level) {
    if (!mounted) return;
    setState(() => _log.add(_LogLine(message, level)));
    // Keep the tail visible — the activity pass is long enough to scroll off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _seed() async {
    setState(() {
      _running = true;
      _done = false;
      _log.clear();
    });

    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;

    // Any pre-existing session would fight the create-then-sign-in dance.
    await auth.signOut();

    final uids = await _seedAccounts(auth, db);
    if (_withActivity) {
      _say('', SeedLevel.info);
      _say('── Activity ──────────────────────────────', SeedLevel.info);
      await seedContent(auth: auth, db: db, uids: uids, say: _say);
      // Leave no session behind: the app you launch next should start at the
      // welcome screen, not signed in as whoever the seeder finished as.
      await auth.signOut();
    }

    if (mounted) {
      setState(() {
        _running = false;
        _done = true;
      });
    }
  }

  /// Activates every seeded business account, signed in as the admin.
  ///
  /// ## Why this is not cheating
  ///
  /// The rules forbid a business account setting its own `status` — that is
  /// the check stopping a rider self-approving as a trainer, and it is not
  /// weakened here. This signs in as the **admin** and takes exactly the path
  /// the admin console takes, which staff are allowed to write. If the admin
  /// has not been promoted in the Firebase console yet, every write is denied
  /// and the button says so.
  ///
  /// It exists because the cast is now large enough that approving it by hand
  /// is a genuinely tedious job, and a tedious setup step is one people skip.
  Future<void> _approveAll() async {
    setState(() {
      _running = true;
      _log.clear();
    });

    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    await auth.signOut();

    _say('── Approving seeded businesses ───────────', SeedLevel.info);
    try {
      await auth.signInWithEmailAndPassword(
          email: emailAdmin, password: seedPassword);

      final me = await db.collection('users').doc(auth.currentUser!.uid).get();
      if (me.data()?['role'] != 'admin') {
        _say('$emailAdmin is not an admin yet.', SeedLevel.error);
        _say('Set  role: "admin"  on that user in the Firebase console '
            'first — the rules refuse it from any client.', SeedLevel.warn);
        return;
      }

      // Never a blanket "activate every business": only accounts this seeder
      // created, and never the two that exist to sit in the approvals queue.
      final wanted = {for (final a in approvableAccounts) a.email};
      final all = await db
          .collection('users')
          .where('role', isEqualTo: 'business')
          .get();

      var approved = 0;
      var already = 0;
      for (final doc in all.docs) {
        final data = doc.data();
        if (data[seedMarker] != true) continue; // Not ours. Leave it alone.
        if (!wanted.contains(data['email'])) continue;
        if (data['status'] == 'active') {
          already++;
          continue;
        }
        await doc.reference.update({
          'status': 'active',
          'reviewedAt': FieldValue.serverTimestamp(),
          'reviewNote': 'Approved by the seeder',
        });
        approved++;
        _say('  ✓ ${data['name']}', SeedLevel.ok);
      }

      _say('', SeedLevel.info);
      _say(
          'Approved $approved, $already already active. '
          '${seedAccounts.where((a) => a.keepPending).length} left pending '
          'for the admin console.',
          SeedLevel.ok);
    } catch (error) {
      _say('✗ $error', SeedLevel.error);
    } finally {
      await auth.signOut();
      if (mounted) setState(() => _running = false);
    }
  }

  /// Pass 1. Returns email → uid for every account that now exists, which is
  /// what the activity pass needs to wire documents together.
  Future<Map<String, String>> _seedAccounts(
      FirebaseAuth auth, FirebaseFirestore db) async {
    final uids = <String, String>{};
    var created = 0;
    var existing = 0;
    var failed = 0;

    _say('── Accounts ──────────────────────────────', SeedLevel.info);

    for (final account in seedAccounts) {
      try {
        _say('Creating ${account.email}…', SeedLevel.info);
        UserCredential credential;
        try {
          credential = await auth.createUserWithEmailAndPassword(
            email: account.email,
            password: seedPassword,
          );
          created++;
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            // Re-runnable: sign in instead so the profile can be refreshed.
            _say('  already exists — signing in to refresh its profile',
                SeedLevel.warn);
            credential = await auth.signInWithEmailAndPassword(
              email: account.email,
              password: seedPassword,
            );
            existing++;
          } else {
            rethrow;
          }
        }

        final uid = credential.user!.uid;
        await _writeProfile(db, account, uid);
        uids[account.email] = uid;
        _say('  ✓ ${account.name} (${_roleLabel(account.role)})', SeedLevel.ok);
      } catch (error) {
        failed++;
        _say('  ✗ ${account.email}: $error', SeedLevel.error);
      } finally {
        // Always drop the session before the next account, or the following
        // create would write its profile under the wrong uid.
        await auth.signOut();
      }
    }

    _say('', SeedLevel.info);
    _say('Accounts: $created created, $existing already existed, $failed failed.',
        failed == 0 ? SeedLevel.ok : SeedLevel.warn);
    return uids;
  }

  /// Creates the profile, or refreshes an existing one **without touching
  /// `role` or `status`**.
  ///
  /// This is not politeness, it is the only write the rules will accept.
  /// `privilegedFieldsUnchanged()` rejects any self-update whose diff touches
  /// those fields, and a diff only lists keys whose *value* changed — so
  /// re-seeding is fine until you approve a trainer in the admin console, at
  /// which point re-writing `status: 'pending'` becomes a real change and the
  /// entire profile write is denied. That failure used to cascade: the
  /// account would be dropped from the uid map and its whole activity set
  /// silently skipped.
  Future<void> _writeProfile(
      FirebaseFirestore db, SeedAccount account, String uid) async {
    final ref = db.collection('users').doc(uid);
    final profile = _profileFor(account, uid);
    if ((await ref.get()).exists) {
      profile.remove('role');
      profile.remove('status');
      profile.remove('createdAt'); // Keep the original signup instant.
      await ref.set(profile, SetOptions(merge: true));
      return;
    }
    await ref.set(profile);
  }

  /// Written directly rather than through UserRepository so the seeder cannot
  /// drift into depending on app code that later changes shape.
  Map<String, dynamic> _profileFor(SeedAccount a, String uid) {
    final base = <String, dynamic>{
      'name': a.name,
      'email': a.email,
      'languages': a.languages,
      'favorites': <String>[],
      'photoURL': '',
      'createdAt': FieldValue.serverTimestamp(),
      // Marks every seeded document so you can find and delete them later.
      seedMarker: true,
    };

    return switch (a.role) {
      // The admin is created as an ordinary rider — the rules refuse
      // role 'admin' on create, so the console step does the promotion.
      SeedRole.rider || SeedRole.admin => {
          ...base,
          'role': 'kiter',
          'status': 'active',
          'nationality': a.nationality,
          'age': a.age,
          'level': a.level,
          'homeSpot': a.spot,
          'quiver': const ['12m', 'Twin tip'],
          'bio': a.bio,
        },
      SeedRole.trainer || SeedRole.station || SeedRole.safari => {
          ...base,
          'role': 'business',
          // Cannot be 'active' here — see the header. Approve in-app, or with
          // the "Approve all" button once the admin exists.
          'status': 'pending',
          'businessType': a.businessType,
          'bio': a.bio,
          'location': a.spot,
          'hourlyRate': a.rate,
          'ikoId': 'IKO-${uid.substring(0, 6).toUpperCase()}',
          'gallery': <String>[],
          'mapsLink': ?a.mapsLink,
        },
    };
  }

  String _roleLabel(SeedRole role) => switch (role) {
        SeedRole.rider => 'rider',
        SeedRole.trainer => 'coach, pending',
        SeedRole.station => 'station, pending',
        SeedRole.safari => 'safari operator, pending',
        SeedRole.admin => 'admin-to-be',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FLOW — seed test data')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${seedAccounts.length} accounts — '
                  '${seedAccounts.where((a) => a.role == SeedRole.rider).length}'
                  ' riders, '
                  '${seedAccounts.where((a) => a.isBusiness).length} coaches '
                  'and operators across all 10 spots — plus bookings, '
                  'reviews, conversations, notifications, blocked hours, time '
                  'off, station rentals and four expeditions. Safe to re-run: '
                  'nothing is duplicated and nothing already there is '
                  'overwritten.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  'Password for every account:  $seedPassword',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.tealAccent),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _withActivity,
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _withActivity = v),
                  title: const Text('Also seed activity',
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text(
                    'Off = bare accounts, every screen empty.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _running ? null : _seed,
                    icon: _running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_rounded),
                    label: Text(_running ? 'Seeding…' : 'Seed test data'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _running ? null : _approveAll,
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('Approve all coaches (as admin)'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Approving needs $emailAdmin to already have '
                    'role: "admin" in the Firebase console. Karim and Greg '
                    'stay pending on purpose.',
                    style: const TextStyle(fontSize: 11.5, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          if (_done) const _NextStepsBanner(),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _log.length,
              itemBuilder: (_, i) {
                final line = _log[i];
                return Text(
                  line.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: switch (line.level) {
                      SeedLevel.ok => Colors.greenAccent,
                      SeedLevel.warn => Colors.amberAccent,
                      SeedLevel.error => Colors.redAccent,
                      SeedLevel.info => Colors.white70,
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The steps this seeder is forbidden from doing for you, and the ones that
/// only make sense once you can see the data.
class _NextStepsBanner extends StatelessWidget {
  const _NextStepsBanner();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.amber.withValues(alpha: .16),
        padding: const EdgeInsets.all(14),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('One manual step left',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            SelectableText(
              'Firebase console → Firestore → users → find the doc whose '
              'email is $emailAdmin → set  role: "admin"  → save.\n\n'
              'The rules refuse role "admin" from any client write. That is '
              'the check that stops a rider promoting themselves, so it also '
              'stops this seeder. Reopen the app afterwards and Profile → '
              'Admin console appears without a restart.\n\n'
              'Then come back here and tap "Approve all coaches" — it signs '
              'in as that admin and activates every seeded business the same '
              'way the admin console would. Until they are approved they do '
              'not appear in Explore; their bookings and reviews already '
              'exist and show up the moment they do.',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ],
        ),
      );
}

class _LogLine {
  const _LogLine(this.text, this.level);
  final String text;
  final SeedLevel level;
}

class _Fatal extends StatelessWidget {
  const _Fatal(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}
