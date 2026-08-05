// The cast. Shared by the account pass (seed_app.dart) and the activity pass
// (seed_content.dart) so an email is spelled once.
//
// ## What this cast is for
//
// Enough people, spread widely enough, that the UI is actually under load:
// every one of the ten spots is represented, ratings vary rather than all
// reading 5.0, and the awkward cases that break layouts are here on purpose —
// a 36-character name, a name in Arabic script, an empty bio, a bio at the
// 240-character ceiling, both ends of the €60–110 rate band, six languages
// against one, and operators of all three kinds so the station and expedition
// screens have something to render.

/// One shared password across every seeded account — these are throwaway test
/// logins on a test project, and one password you can remember beats thirty
/// you cannot.
const seedPassword = 'FlowTest!2026';

/// Anything at this domain is a seeded account. Kept distinctive so you can
/// find and delete them all later in the Firebase console.
const seedDomain = 'flowtest.dev';

/// Every seeded document carries `seeded: true`. Firestore console → filter on
/// it to find everything this file created. It is also the guard the bulk
/// approver uses so it can never touch a real account.
const seedMarker = 'seeded';

enum SeedLevel { info, ok, warn, error }

/// What the seeder writes to the log pane.
typedef SeedLog = void Function(String message, SeedLevel level);

enum SeedRole {
  rider,

  /// A solo coach — `businessType: 'Instructor'`.
  trainer,

  /// A centre — `businessType: 'Station'`, which unlocks the three-tab
  /// station profile (Lessons / Rentals / Beach).
  station,

  /// `businessType` containing "safari", which switches the profile to a
  /// single Expeditions tab.
  safari,

  admin,
}

class SeedAccount {
  const SeedAccount({
    required this.email,
    required this.name,
    required this.role,
    this.nationality = 'German',
    this.age = 29,
    this.level = 'Independent',
    this.spot = 'El Gouna',
    this.languages = const ['English'],
    this.rate = 75,
    this.bio = '',
    this.note = '',
    this.keepPending = false,
    this.mapsLink,
  });

  final String email;
  final String name;
  final SeedRole role;
  final String nationality;
  final int age;
  final String level;
  final String spot;
  final List<String> languages;
  final int rate;
  final String bio;

  /// Shown in the summary so you know what each account is *for*.
  final String note;

  /// Excluded from "approve all". These exist precisely so there is always
  /// something waiting in the admin console's Approvals queue.
  final bool keepPending;

  final String? mapsLink;

  bool get isBusiness =>
      role == SeedRole.trainer ||
      role == SeedRole.station ||
      role == SeedRole.safari;

  /// The `businessType` written to the profile document.
  String? get businessType => switch (role) {
        SeedRole.trainer => 'Instructor',
        SeedRole.station => 'Station',
        SeedRole.safari => 'Safari operator',
        _ => null,
      };
}

// Addresses referenced by the activity pass. Typo-proofing: a wrong string
// here fails loudly at seed time rather than silently writing orphan data.
const emailRider1 = 'rider1@$seedDomain';
const emailRider2 = 'rider2@$seedDomain';
const emailRider3 = 'rider3@$seedDomain';
const emailRider4 = 'rider4@$seedDomain';
const emailRider5 = 'rider5@$seedDomain';
const emailRider6 = 'rider6@$seedDomain';
const emailRider7 = 'rider7@$seedDomain';
const emailRider8 = 'rider8@$seedDomain';
const emailRider9 = 'rider9@$seedDomain';
const emailTrainer1 = 'trainer1@$seedDomain';
const emailTrainer2 = 'trainer2@$seedDomain';
const emailTrainer3 = 'trainer3@$seedDomain';
const emailTrainer4 = 'trainer4@$seedDomain';
const emailTrainer5 = 'trainer5@$seedDomain';
const emailTrainer6 = 'trainer6@$seedDomain';
const emailTrainer7 = 'trainer7@$seedDomain';
const emailTrainer8 = 'trainer8@$seedDomain';
const emailTrainer9 = 'trainer9@$seedDomain';
const emailTrainer10 = 'trainer10@$seedDomain';
const emailStation1 = 'station1@$seedDomain';
const emailStation2 = 'station2@$seedDomain';
const emailSafari1 = 'safari1@$seedDomain';
const emailPending1 = 'pending1@$seedDomain';
const emailPending2 = 'pending2@$seedDomain';
const emailAdmin = 'admin@$seedDomain';

/// 229 characters, against the 240 ceiling `OnboardingValidators.bio`
/// enforces. Here so a profile card is tested near its worst case rather than
/// its average one.
///
/// The length is asserted in `test/core_logic_test.dart` — the first draft of
/// this string was 250 characters, i.e. a bio the app's own validator would
/// have refused, seeded straight past it into the database.
const _maxBio =
    'Twelve seasons on this coast and I still check the forecast twice before '
    'breakfast. I teach slowly, safety first, and will happily spend a whole '
    'session on one transition if that is the thing standing between you and '
    'enjoying it.';

const seedAccounts = <SeedAccount>[
  // ── Riders ───────────────────────────────────────────────────────────────
  SeedAccount(
    email: emailRider1,
    name: 'Lina Hassan',
    role: SeedRole.rider,
    nationality: 'Egyptian',
    age: 27,
    level: 'Independent',
    spot: 'El Gouna',
    languages: ['Arabic', 'English'],
    bio: 'Weekend rider, twin tip only, still scared of the foil.',
    note: 'Main rider — full history, reviews, unread chat.',
  ),
  SeedAccount(
    email: emailRider2,
    name: 'Tomas Novak',
    role: SeedRole.rider,
    nationality: 'Czech',
    age: 34,
    level: 'Advanced',
    spot: 'Soma Bay',
    languages: ['Czech', 'English', 'German'],
    bio: 'Here every winter. Big kites, small board.',
    note: 'Second rider — past session, upcoming, an expedition seat.',
  ),
  SeedAccount(
    email: emailRider3,
    name: 'Marta Kowalska',
    role: SeedRole.rider,
    nationality: 'Polish',
    age: 22,
    level: 'New',
    spot: 'Dahab',
    languages: ['Polish', 'English'],
    bio: 'Two lessons in. Water start is a rumour so far.',
    note: 'Deliberately empty — this is how you test the empty states.',
  ),
  SeedAccount(
    email: emailRider4,
    name: 'Youssef Abdel-Rahman',
    role: SeedRole.rider,
    nationality: 'Egyptian',
    age: 19,
    level: 'PRO',
    spot: 'Safaga',
    languages: ['Arabic', 'English', 'French'],
    bio: 'Competing this season. Looking for coaching, not lessons.',
    note: 'PRO level — checks the level pill at its top end.',
  ),
  SeedAccount(
    email: emailRider5,
    name: 'Annelies van der Berg-Hoekstra',
    role: SeedRole.rider,
    nationality: 'Dutch',
    age: 41,
    level: 'Independent',
    spot: 'Hurghada-Magawish',
    languages: ['Dutch', 'English', 'German'],
    bio: '',
    note: 'Long name + empty bio — the two things that break a profile card.',
  ),
  SeedAccount(
    email: emailRider6,
    name: 'مريم فاروق',
    role: SeedRole.rider,
    nationality: 'Egyptian',
    age: 25,
    level: 'New',
    spot: 'El Gouna',
    languages: ['Arabic'],
    bio: 'أتعلم الكايت سيرف من شهرين.',
    note: 'Arabic script, one language — checks RTL rendering and avatar '
        'initials for a non-Latin name.',
  ),
  SeedAccount(
    email: emailRider7,
    name: 'Bo Lin',
    role: SeedRole.rider,
    nationality: 'Chinese',
    age: 31,
    level: 'Advanced',
    spot: 'Marsa Alam Tulip',
    languages: ['English'],
    bio: 'Short name, long trips.',
    note: 'Very short name — the other end of the avatar/initials case.',
  ),
  SeedAccount(
    email: emailRider8,
    name: 'Grace Adeyemi',
    role: SeedRole.rider,
    nationality: 'Nigerian',
    age: 28,
    level: 'Independent',
    spot: 'Dahab',
    languages: ['English', 'French'],
    bio: 'Downwinders or nothing.',
    note: 'Ordinary rider — bulk, so Explore and chat lists are not sparse.',
  ),
  SeedAccount(
    email: emailRider9,
    name: 'Matteo Brambilla',
    role: SeedRole.rider,
    nationality: 'Italian',
    age: 37,
    level: 'Advanced',
    spot: 'Ras Soma Bay',
    languages: ['Italian', 'English', 'Spanish'],
    bio: 'Foil convert. Never going back.',
    note: 'Ordinary rider.',
  ),

  // ── Coaches (solo instructors) ──────────────────────────────────────────
  SeedAccount(
    email: emailTrainer1,
    name: 'Omar Farouk',
    role: SeedRole.trainer,
    spot: 'El Gouna',
    languages: ['Arabic', 'English', 'German'],
    rate: 80,
    bio: 'IKO Level 2. Ten seasons on the Red Sea, beginners welcome.',
    note: 'Busiest coach — 3 reviews, hosts the expedition, has bookings.',
    mapsLink: 'https://maps.google.com/?q=27.3950,33.6780',
  ),
  SeedAccount(
    email: emailTrainer2,
    name: 'Sofia Ricci',
    role: SeedRole.trainer,
    spot: 'Soma Bay',
    languages: ['Italian', 'English'],
    rate: 95,
    bio: 'Freestyle and foil coaching. Video analysis after every session.',
    note: 'Has a vacation booked — use this to test "Away" on the day strip.',
  ),
  SeedAccount(
    email: emailTrainer3,
    name: 'Yannick Weber',
    role: SeedRole.trainer,
    spot: 'Safaga',
    languages: ['German', 'English', 'French'],
    rate: 70,
    bio: 'Patient with nervous beginners. Gear included in the hourly rate.',
    note: 'Declined a request — the rejected path.',
  ),
  SeedAccount(
    email: emailTrainer4,
    name: 'محمود سعيد',
    role: SeedRole.trainer,
    spot: 'Hurghada-Magawish',
    languages: ['Arabic', 'English'],
    rate: 60,
    bio: 'مدرب كايت سيرف معتمد. خمس سنوات خبرة في البحر الأحمر.',
    note: 'Arabic name AND bio, at the €60 floor — RTL plus the cheapest '
        'card in the grid.',
  ),
  SeedAccount(
    email: emailTrainer5,
    name: 'Konstantinos Papadopoulos',
    role: SeedRole.trainer,
    spot: 'Dahab',
    languages: ['Greek', 'English', 'German', 'Russian', 'Turkish', 'Italian'],
    rate: 110,
    bio: _maxBio,
    note: 'The stress test: longest name, six languages, 240-char bio, and '
        'the €110 ceiling. If a layout breaks anywhere, it breaks here.',
  ),
  SeedAccount(
    email: emailTrainer6,
    name: 'Elena Volkova',
    role: SeedRole.trainer,
    spot: 'Marsa Alam Tulip',
    languages: ['Russian', 'English'],
    rate: 85,
    bio: '',
    note: 'No bio at all — checks the About section when there is nothing '
        'to put in it.',
  ),
  SeedAccount(
    email: emailTrainer7,
    name: 'Liam O\'Sullivan',
    role: SeedRole.trainer,
    spot: 'LahamiBay',
    languages: ['English'],
    rate: 72,
    bio: 'Wave riding and strapless. The southern spots are my patch.',
    note: 'Apostrophe in the name — the classic string-handling trip-up.',
  ),
  SeedAccount(
    email: emailTrainer8,
    name: 'Ines Duarte',
    role: SeedRole.trainer,
    spot: 'Marsa Alam El Naaba',
    languages: ['Portuguese', 'Spanish', 'English'],
    rate: 78,
    bio: 'Ex-competitor, now teaching. Big on technique, light on drills.',
    note: 'Covers a spot nothing else does.',
  ),
  SeedAccount(
    email: emailTrainer9,
    name: 'Anders Lindqvist',
    role: SeedRole.trainer,
    spot: 'Abu Soma Bay',
    languages: ['Swedish', 'English', 'German'],
    rate: 88,
    bio: 'Foil specialist. I will get you flying in three sessions.',
    note: 'Covers a spot nothing else does.',
  ),
  SeedAccount(
    email: emailTrainer10,
    name: 'Nadia Cherif',
    role: SeedRole.trainer,
    spot: 'Ras Soma Bay',
    languages: ['Arabic', 'French', 'English'],
    rate: 82,
    bio: 'Women-only sessions available on request.',
    note: 'Covers a spot nothing else does. Unrated — tests the 5.0 default.',
  ),

  // ── Stations & operators ────────────────────────────────────────────────
  SeedAccount(
    email: emailStation1,
    name: 'Gouna Kite Centre',
    role: SeedRole.station,
    spot: 'El Gouna',
    languages: ['English', 'Arabic', 'German', 'Russian'],
    rate: 75,
    bio: 'Full-service centre on the north lagoon. Lessons, rentals, storage '
        'and a beach bar that does a decent flat white.',
    note: 'STATION — three-tab profile (Lessons / Rentals / Beach). Its '
        'instructors and services are seeded as subcollections.',
    mapsLink: 'https://maps.google.com/?q=27.3950,33.6780',
  ),
  SeedAccount(
    email: emailStation2,
    name: 'Safaga Watersports',
    role: SeedRole.station,
    spot: 'Safaga',
    languages: ['English', 'Arabic'],
    rate: 68,
    bio: 'Small centre, big lagoon. Gear is new this season.',
    note: 'STATION — deliberately has no services seeded, so you can see '
        'the station tabs in their empty state.',
  ),
  SeedAccount(
    email: emailSafari1,
    name: 'Red Sea Downwind Co.',
    role: SeedRole.safari,
    spot: 'Hurghada-Magawish',
    languages: ['English', 'Arabic', 'Italian'],
    rate: 90,
    bio: 'Multi-day downwind expeditions with a chase boat and a cook.',
    note: 'SAFARI OPERATOR — single Expeditions tab. Hosts three trips, one '
        'of them sold out.',
  ),

  // ── Left pending on purpose ─────────────────────────────────────────────
  SeedAccount(
    email: emailPending1,
    name: 'Karim Adel',
    role: SeedRole.trainer,
    spot: 'Hurghada-Magawish',
    languages: ['Arabic', 'English'],
    rate: 65,
    bio: 'New to the platform, six years teaching at the centre.',
    keepPending: true,
    note: 'LEAVE PENDING — for testing Accept in the admin console.',
  ),
  SeedAccount(
    email: emailPending2,
    name: 'Greg Sullivan',
    role: SeedRole.trainer,
    spot: 'Dahab',
    languages: ['English'],
    rate: 110,
    bio: 'Applying with an expired certificate on purpose.',
    keepPending: true,
    note: 'LEAVE PENDING — for testing Reject in the admin console.',
  ),

  // ── Admin — needs the one manual console step, see seed_app.dart ─────────
  SeedAccount(
    email: emailAdmin,
    name: 'Flow Admin',
    role: SeedRole.admin,
    nationality: 'Egyptian',
    age: 35,
    spot: 'El Gouna',
    languages: ['Arabic', 'English'],
    note: 'Set role to "admin" in the Firebase console — see the banner.',
  ),
];

/// Business accounts that "Approve all" should activate.
Iterable<SeedAccount> get approvableAccounts =>
    seedAccounts.where((a) => a.isBusiness && !a.keepPending);
