/// Fixed platform lists and numeric constants (APP_LOGIC_BLUEPRINT.md §13).
abstract final class FlowConst {
  static const appVersionLabel = 'FLOW 1.0.0';

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

  /// Where each spot in [kiteSpots] actually is, for the wind forecast.
  ///
  /// Approximate launch-area coordinates, not survey grade — a few hundred
  /// metres either way changes nothing in a forecast whose native resolution
  /// is measured in kilometres. Every key here must exist in [kiteSpots]; a
  /// spot with no entry simply shows no wind rather than a wrong one, and
  /// `test/core_logic_test.dart` asserts the two lists agree.
  static const spotCoordinates = <String, (double lat, double lon)>{
    'El Gouna': (27.3950, 33.6780),
    'Abu Soma Bay': (26.8480, 33.9930),
    'Safaga': (26.7330, 33.9380),
    'LahamiBay': (24.0960, 35.4620),
    'Dahab': (28.4810, 34.5130),
    'Hurghada-Magawish': (27.1500, 33.8260),
    'Marsa Alam Tulip': (25.0700, 34.8950),
    'Soma Bay': (26.8440, 33.9830),
    'Marsa Alam El Naaba': (25.0760, 34.8900),
    'Ras Soma Bay': (26.8500, 33.9700),
  };

  /// Open-Meteo's free tier caps a forecast at 16 days, while the booking day
  /// strip runs to [bookingDayStripLength]. Days past this simply carry no
  /// wind — shown as nothing, never as a guess.
  static const windForecastDays = 16;

  /// Suggested languages — users may add their own.
  static const languages = [
    'English', 'Arabic', 'German', 'French', 'Spanish', 'Italian',
    'Russian', 'Polish', 'Dutch', 'Portuguese', 'Czech', 'Turkish',
    'Mandarin', 'Hindi', 'Japanese', 'Korean',
  ];

  /// Nationalities as **demonyms** ("German", not "Germany") — the field asks
  /// who you are, not where you were born. Searchable rather than scrolled,
  /// so length costs nothing; the Red Sea draws riders from everywhere and a
  /// short list would just push people into "Other".
  ///
  /// The nationalities most represented on Egyptian kite beaches lead the
  /// list; the rest are alphabetical.
  static const nationalities = [
    'Egyptian', 'German', 'Russian', 'Polish', 'Italian', 'French', 'British',
    'Dutch', 'Czech', 'Austrian', 'Swiss', 'Ukrainian', 'Spanish',
    'Afghan', 'Albanian', 'Algerian', 'American', 'Andorran', 'Angolan',
    'Argentine', 'Armenian', 'Australian', 'Azerbaijani', 'Bahamian',
    'Bahraini', 'Bangladeshi', 'Barbadian', 'Belarusian', 'Belgian',
    'Belizean', 'Beninese', 'Bhutanese', 'Bolivian', 'Bosnian', 'Botswanan',
    'Brazilian', 'Bruneian', 'Bulgarian', 'Burkinabé', 'Burmese',
    'Burundian', 'Cambodian', 'Cameroonian', 'Canadian', 'Cape Verdean',
    'Chadian', 'Chilean', 'Chinese', 'Colombian', 'Comoran', 'Congolese',
    'Costa Rican', 'Croatian', 'Cuban', 'Cypriot', 'Danish', 'Djiboutian',
    'Dominican', 'Ecuadorean', 'Emirati', 'Equatorial Guinean', 'Eritrean',
    'Estonian', 'Ethiopian', 'Fijian', 'Filipino', 'Finnish', 'Gabonese',
    'Gambian', 'Georgian', 'Ghanaian', 'Greek', 'Grenadian', 'Guatemalan',
    'Guinean', 'Guyanese', 'Haitian', 'Honduran', 'Hungarian', 'Icelandic',
    'Indian', 'Indonesian', 'Iranian', 'Iraqi', 'Irish', 'Israeli',
    'Ivorian', 'Jamaican', 'Japanese', 'Jordanian', 'Kazakh', 'Kenyan',
    'Kuwaiti', 'Kyrgyz', 'Laotian', 'Latvian', 'Lebanese', 'Liberian',
    'Libyan', 'Liechtensteiner', 'Lithuanian', 'Luxembourgish',
    'Macedonian', 'Malagasy', 'Malawian', 'Malaysian', 'Maldivian',
    'Malian', 'Maltese', 'Mauritanian', 'Mauritian', 'Mexican', 'Moldovan',
    'Monacan', 'Mongolian', 'Montenegrin', 'Moroccan', 'Mozambican',
    'Namibian', 'Nepalese', 'New Zealander', 'Nicaraguan', 'Nigerian',
    'Nigerien', 'North Korean', 'Norwegian', 'Omani', 'Pakistani',
    'Palestinian', 'Panamanian', 'Papua New Guinean', 'Paraguayan',
    'Peruvian', 'Portuguese', 'Qatari', 'Romanian', 'Rwandan', 'Salvadoran',
    'Samoan', 'Saudi', 'Senegalese', 'Serbian', 'Seychellois',
    'Sierra Leonean', 'Singaporean', 'Slovak', 'Slovenian', 'Somali',
    'South African', 'South Korean', 'South Sudanese', 'Sri Lankan',
    'Sudanese', 'Surinamese', 'Swazi', 'Swedish', 'Syrian', 'Taiwanese',
    'Tajik', 'Tanzanian', 'Thai', 'Togolese', 'Tongan', 'Trinidadian',
    'Tunisian', 'Turkish', 'Turkmen', 'Ugandan', 'Uruguayan', 'Uzbek',
    'Vanuatuan', 'Venezuelan', 'Vietnamese', 'Yemeni', 'Zambian',
    'Zimbabwean',
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

  /// Trainers set their own price. There is no platform band: the old
  /// €60–€110 window was a euro-market assumption, and a marketplace that
  /// refuses a trainer's real rate simply loses that trainer.
  ///
  /// What remains is a typo guard. A rate of 0 is not a free lesson, it is an
  /// unfinished form; six figures an hour is a slipped keypad. Both are
  /// refused with a message about the number, not about a policy.
  static const maxSaneHourlyRate = 100000;

  /// Quick-pick chips under the rate field — a starting point, not a limit.
  static const rateSuggestions = [250, 400, 600, 850, 1200];

  static const defaultDisplayRate = 400.0;
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
  // `themeMode` used to live here. It is gone with dark mode; any value an
  // existing install still has under that key is simply never read.
  static String trainerTourDoneKey(String uid) => 'trainerTourDone_$uid';
}
