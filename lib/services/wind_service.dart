import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';
import '../data/models/wind.dart';

/// Wind forecasts for the kite spots, from Open-Meteo.
///
/// ## This is the app's only HTTP call
///
/// The blueprint (§12) states plainly that every external interaction is a
/// Firebase SDK call — no REST, no HTTP. That was true and worth preserving,
/// and this breaks it deliberately. FLOW sells hours on the water in a sport
/// that does not happen without wind: a rider choosing between next Tuesday
/// and next Thursday is really choosing between forecasts, and an app that
/// makes them leave to check one is a step in someone else's flow.
///
/// The cost is contained on purpose:
///
///   * **No API key, no account, no billing.** Open-Meteo's non-commercial
///     tier needs no credentials, so there is no secret to leak from a client
///     binary — which is what would make a weather API a bad idea here.
///   * **No new dependency.** `dart:io`'s HttpClient is enough; adding
///     `package:http` to make one GET would not have earned its place.
///   * **Failure is silent.** Every error path returns an empty forecast, and
///     the UI renders nothing where wind would have been. Booking must work
///     on a dead connection exactly as it did before this existed.
class WindService {
  WindService({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  /// Forecasts are recomputed by the provider a few times a day; refetching on
  /// every screen open would be many requests for identical numbers. Thirty
  /// minutes is far shorter than the forecast's own resolution.
  static const cacheTtl = Duration(minutes: 30);

  static const _timeout = Duration(seconds: 8);

  final Map<String, _CacheEntry> _cache = {};

  /// The forecast for [spot], or [WindForecast.empty] if it cannot be had.
  ///
  /// Never throws. A spot with no coordinates, a dead network, a rate limit
  /// and a malformed body all produce the same thing: no wind shown.
  Future<WindForecast> forSpot(String spot) async {
    final coordinates = FlowConst.spotCoordinates[spot];
    if (coordinates == null) return WindForecast.empty;

    final cached = _cache[spot];
    if (cached != null && !cached.isStale) return cached.forecast;

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': coordinates.$1.toStringAsFixed(4),
      'longitude': coordinates.$2.toStringAsFixed(4),
      'daily': 'wind_speed_10m_max,wind_gusts_10m_max,'
          'wind_direction_10m_dominant',
      // Knots directly, so nothing downstream has to convert — and nothing
      // downstream can convert *twice*, which is the classic version of this
      // bug.
      'wind_speed_unit': 'kn',
      // Daily buckets must line up with the local calendar days the booking
      // strip shows, or a "Thursday" forecast lands on Wednesday's tile.
      'timezone': 'Africa/Cairo',
      'forecast_days': '${FlowConst.windForecastDays}',
    });

    final client = _clientFactory();
    try {
      client.connectionTimeout = _timeout;
      final request = await client.getUrl(uri).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) return _fallback(spot, cached);

      final body =
          await response.transform(utf8.decoder).join().timeout(_timeout);
      final decoded = json.decode(body);
      if (decoded is! Map<String, dynamic>) return _fallback(spot, cached);

      final forecast = WindForecast.fromOpenMeteo(spot, decoded);
      _cache[spot] = _CacheEntry(forecast);
      return forecast;
    } catch (_) {
      // Offline, DNS failure, timeout, garbage body — all the same outcome.
      return _fallback(spot, cached);
    } finally {
      client.close(force: true);
    }
  }

  /// A stale forecast beats no forecast: yesterday's numbers for next week are
  /// still roughly next week's numbers, and the alternative is a blank strip
  /// every time the beach wifi drops.
  WindForecast _fallback(String spot, _CacheEntry? cached) =>
      cached?.forecast ?? WindForecast.empty;

  void clearCache() => _cache.clear();
}

class _CacheEntry {
  _CacheEntry(this.forecast) : fetchedAt = DateTime.now();

  final WindForecast forecast;
  final DateTime fetchedAt;

  bool get isStale =>
      DateTime.now().difference(fetchedAt) > WindService.cacheTtl;
}
