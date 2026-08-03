import 'package:cloud_firestore/cloud_firestore.dart';

/// Tolerant readers for Firestore documents (APP_LOGIC_BLUEPRINT.md §5).
///
/// The database was written over years by a loosely-typed web client: the same
/// logical field arrives in several shapes. A single malformed document must
/// never crash a screen, so every reader here degrades to null / empty instead
/// of throwing.
extension DocX on Map<String, dynamic> {
  String? str(String key) {
    final v = this[key];
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  /// First non-empty string among [keys].
  String? strAny(List<String> keys) {
    for (final k in keys) {
      final v = str(k);
      if (v != null) return v;
    }
    return null;
  }

  bool boolean(String key, {bool fallback = false}) {
    final v = this[key];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    if (v is num) return v != 0;
    return fallback;
  }

  int? integer(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.round();
    return null;
  }

  double? decimal(String key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// Money parser — strips `€`, `EUR` and spaces before parsing.
  double? money(String key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll('€', '').replaceAll(RegExp('EUR', caseSensitive: false), '').replaceAll(' ', '').replaceAll(',', '.').trim();
      return double.tryParse(cleaned);
    }
    return null;
  }

  double? moneyAny(List<String> keys) {
    for (final k in keys) {
      final v = money(k);
      if (v != null) return v;
    }
    return null;
  }

  /// String list — accepts a bare string, drops nulls and empties.
  List<String> strList(String key) {
    final v = this[key];
    if (v is String) return v.trim().isEmpty ? const [] : [v.trim()];
    if (v is List) {
      return v
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> nested(String key) {
    final v = this[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return const {};
  }

  List<Map<String, dynamic>> nestedList(String key) {
    final v = this[key];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map<String, dynamic>)
          e
        else if (e is Map)
          e.map((k, val) => MapEntry(k.toString(), val)),
    ];
  }

  /// Accepts `Timestamp`, `DateTime`, epoch seconds *or* millis, ISO string,
  /// and `{_seconds: …}` maps.
  DateTime? date(String key) => _asDate(this[key]);

  DateTime? dateAny(List<String> keys) {
    for (final k in keys) {
      final v = date(k);
      if (v != null) return v;
    }
    return null;
  }
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is num) {
    final n = v.toInt();
    // Heuristic: values before ~2001-09 in millis are seconds.
    return DateTime.fromMillisecondsSinceEpoch(n < 1000000000000 ? n * 1000 : n);
  }
  if (v is String) return DateTime.tryParse(v.trim());
  if (v is Map) {
    final secs = v['_seconds'] ?? v['seconds'];
    if (secs is num) return DateTime.fromMillisecondsSinceEpoch(secs.toInt() * 1000);
  }
  return null;
}

/// Strips nulls before an `update()` — a null must never overwrite a field the
/// web client still needs.
Map<String, dynamic> compact(Map<String, dynamic> data) =>
    {for (final e in data.entries) if (e.value != null) e.key: e.value};
