/// Fixed platform lists and numeric constants (APP_LOGIC_BLUEPRINT.md §13).
abstract final class FlowConst {
  static const appVersionLabel = 'FLOW 3.0.0';

  /// The fixed, closed list of Egyptian kite spots — filters + onboarding.
  static const kiteSpots = [
    'El Gouna',
    'Abu Soma Bay',
    'Safaga',
    'LahamiBay',
    'Dahab',
    'Hurghada-Magawish',
    'Marsa Alam Tulip',
    'Soma Bay',
    'Marsa Alam El Naaba',
    'Ras Soma Bay',
  ];

  /// Suggested languages — users may add their own.
  static const languages = [
    'English', 'Arabic', 'German', 'French', 'Spanish', 'Italian',
    'Russian', 'Polish', 'Dutch', 'Portuguese', 'Czech', 'Turkish',
    'Mandarin', 'Hindi', 'Japanese', 'Korean',
  ];

  /// Rider skill levels (closed list).
  static const riderLevels = ['New', 'Independent', 'Advanced', 'PRO'];

  /// Report reasons (closed list).
  static const reportReasons = [
    'Inappropriate behavior',
    'Fake profile / Scam',
    'Unprofessional conduct',
    'Safety concerns',
    'Other',
  ];

  static const quiverSuggestions = [
    '7m', '9m', '10m', '12m', '14m', '17m', 'Twin tip', 'Surfboard', 'Foil',
  ];

  static const minHourlyRate = 60;
  static const maxHourlyRate = 110;
  static const defaultDisplayRate = 50.0;
  static const defaultBufferMinutes = 60;
  static const bookingDayStripLength = 21;
  static const walkInDurations = [1, 2, 3, 4];
  static const comingUpLimit = 10;
  static const chatFollowThresholdPx = 120.0;
  static const chatTimestampGapMinutes = 10;
  static const messagePreviewMaxChars = 117;
  static const uploadMaxDimension = 1600;
  static const uploadJpegQuality = 82;
  static const minTextScale = 0.9;
  static const maxTextScale = 1.3;

  // Persisted local keys.
  static const themeModeKey = 'themeMode';
  static String trainerTourDoneKey(String uid) => 'trainerTourDone_$uid';
}
