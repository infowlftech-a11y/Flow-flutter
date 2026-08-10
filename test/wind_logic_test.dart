// The wind stack, bottom to top: the knot bands riders decide with, the
// compass, the tolerant Open-Meteo parsing, and WindService's one contract —
// **it never throws and never blocks booking**. The service was built with an
// injectable HttpClient factory precisely so this file could exist; the fakes
// below implement only what the service touches and refuse everything else.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/constants.dart';
import 'package:flow/data/models/wind.dart';
import 'package:flow/services/wind_service.dart';

void main() {
  group('WindRating.fromKnots — band edges', () {
    test('each threshold belongs to the upper band', () {
      expect(WindRating.fromKnots(9.9), WindRating.calm);
      expect(WindRating.fromKnots(10), WindRating.light);
      expect(WindRating.fromKnots(14.9), WindRating.light);
      expect(WindRating.fromKnots(15), WindRating.good);
      expect(WindRating.fromKnots(24.9), WindRating.good);
      expect(WindRating.fromKnots(25), WindRating.strong);
      expect(WindRating.fromKnots(33.9), WindRating.strong);
      expect(WindRating.fromKnots(34), WindRating.extreme);
    });

    test('beginners get light and good only', () {
      expect([for (final r in WindRating.values) r.suitsBeginners],
          [false, true, true, false, false]);
    });
  });

  group('compass', () {
    WindDay day(int deg) => WindDay(
        date: '2026-01-01', knots: 20, gustKnots: 25, directionDegrees: deg);

    test('sectors centre on their label', () {
      expect(day(0).compass, 'N');
      expect(day(22).compass, 'N', reason: '22.4° still inside N’s sector');
      expect(day(23).compass, 'NE');
      expect(day(90).compass, 'E');
      expect(day(337).compass, 'NW');
      expect(day(338).compass, 'N', reason: 'wraps back into N at 337.5°');
    });

    test('degrees outside 0..360 normalise instead of crashing', () {
      expect(day(-45).compass, 'NW');
      expect(day(720).compass, 'N');
    });
  });

  group('WindForecast.fromOpenMeteo — ragged input', () {
    test('a null speed entry drops that day, never becomes zero knots', () {
      final f = WindForecast.fromOpenMeteo('El Gouna', {
        'daily': {
          'time': ['2026-01-01', '2026-01-02', '2026-01-03'],
          'wind_speed_10m_max': [18.0, null, '21.5'],
          'wind_gusts_10m_max': [26.0],
          'wind_direction_10m_dominant': <Object?>[],
          'temperature_2m_max': [24.0, 25.0],
        }
      });
      expect(f.days.length, 2, reason: 'null speed means no data, not calm');
      expect(f.forDate('2026-01-02'), isNull);
      expect(f.forDate('2026-01-03')!.knots, 21.5,
          reason: 'numeric strings are parsed');
    });

    test('short sibling arrays degrade per field', () {
      final f = WindForecast.fromOpenMeteo('spot', {
        'daily': {
          'time': ['2026-01-01', '2026-01-02'],
          'wind_speed_10m_max': [18.0, 20.0],
          'wind_gusts_10m_max': [26.0], // one short
          // directions absent entirely
          'temperature_2m_max': [24.0], // one short
        }
      });
      final second = f.forDate('2026-01-02')!;
      expect(second.gustKnots, 20.0, reason: 'missing gust defaults to speed');
      expect(second.directionDegrees, 0);
      expect(second.airC, isNull, reason: 'strip shows wind alone, no fake 0°');
      expect(second.hasUsefulGust, isFalse);
    });

    test('a body without a daily block is simply empty', () {
      expect(WindForecast.fromOpenMeteo('spot', const {}).isEmpty, isTrue);
      expect(
          WindForecast.fromOpenMeteo('spot', {'daily': 'not a map'}).isEmpty,
          isTrue);
    });
  });

  group('withMarine', () {
    final base = WindForecast.fromOpenMeteo('spot', {
      'daily': {
        'time': ['2026-01-01', '2026-01-02'],
        'wind_speed_10m_max': [18.0, 20.0],
      }
    });

    test('folds sea temperature into matching days only', () {
      final merged = base.withMarine({
        'daily': {
          'time': ['2026-01-02', '2026-01-09'],
          'sea_surface_temperature_max': [27.4, 26.0],
        }
      });
      expect(merged.forDate('2026-01-02')!.waterC, 27.4);
      expect(merged.forDate('2026-01-01')!.waterC, isNull);
      expect(merged.days.length, 2,
          reason: 'marine-only days must not invent forecast days');
    });

    test('an empty marine body changes nothing', () {
      expect(identical(base.withMarine(const {}), base), isTrue);
    });
  });

  group('WindService', () {
    test('a spot with no coordinates is empty without touching the network',
        () async {
      var built = 0;
      final service = WindService(clientFactory: () {
        built++;
        return _ThrowingClient();
      });
      final f = await service.forSpot('Atlantis');
      expect(f.isEmpty, isTrue);
      expect(built, 0);
    });

    test('a client that explodes on connect yields empty, never throws',
        () async {
      final service = WindService(clientFactory: _ThrowingClient.new);
      final spot = FlowConst.spotCoordinates.keys.first;
      final f = await service.forSpot(spot);
      expect(f.isEmpty, isTrue);
    });

    test('a non-200 yields empty, and garbage JSON yields empty', () async {
      final spot = FlowConst.spotCoordinates.keys.first;
      expect(
          (await WindService(clientFactory: () => _StubClient(status: 429))
                  .forSpot(spot))
              .isEmpty,
          isTrue);
      expect(
          (await WindService(
                      clientFactory: () => _StubClient(body: 'not json {'))
                  .forSpot(spot))
              .isEmpty,
          isTrue);
    });

    test('success parses wind, folds sea in, and caches for the next call',
        () async {
      final spot = FlowConst.spotCoordinates.keys.first;
      var built = 0;
      final service = WindService(clientFactory: () {
        built++;
        return _StubClient(bodyFor: (uri) {
          if (uri.host.startsWith('marine')) {
            return json.encode({
              'daily': {
                'time': ['2026-01-01'],
                'sea_surface_temperature_max': [27.0],
              }
            });
          }
          return json.encode({
            'daily': {
              'time': ['2026-01-01'],
              'wind_speed_10m_max': [22.0],
              'wind_gusts_10m_max': [30.0],
              'wind_direction_10m_dominant': [45],
              'temperature_2m_max': [28.0],
            }
          });
        });
      });

      final f = await service.forSpot(spot);
      final day = f.forDate('2026-01-01')!;
      expect(day.knots, 22.0);
      expect(day.compass, 'NE');
      expect(day.waterC, 27.0, reason: 'marine response folded in');
      expect(built, 2, reason: 'one client per endpoint');

      final again = await service.forSpot(spot);
      expect(again.forDate('2026-01-01')!.knots, 22.0);
      expect(built, 2, reason: 'second read served from cache');
    });

    test('a marine failure keeps the wind that already arrived', () async {
      final spot = FlowConst.spotCoordinates.keys.first;
      final service = WindService(clientFactory: () => _StubClient(
            bodyFor: (uri) {
              if (uri.host.startsWith('marine')) throw const SocketException('x');
              return json.encode({
                'daily': {
                  'time': ['2026-01-01'],
                  'wind_speed_10m_max': [22.0],
                }
              });
            },
          ));
      final f = await service.forSpot(spot);
      expect(f.forDate('2026-01-01')!.knots, 22.0);
      expect(f.forDate('2026-01-01')!.waterC, isNull);
    });
  });
}

/// Explodes on first use — the "beach wifi died" client.
class _ThrowingClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Setters (connectionTimeout) and close() must be inert; only actual
    // requests explode.
    final name = invocation.memberName.toString();
    if (invocation.isSetter || name.contains('close')) return null;
    throw const SocketException('no network in this test');
  }
}

/// Serves a canned body/status; routes by URI so one test can answer both the
/// forecast and the marine endpoints differently.
class _StubClient implements HttpClient {
  _StubClient({this.status = 200, this.body = '{}', this.bodyFor});

  final int status;
  final String body;
  final String Function(Uri)? bodyFor;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _StubRequest(status, bodyFor?.call(url) ?? body);

  @override
  dynamic noSuchMethod(Invocation invocation) => null; // setters, close()
}

class _StubRequest implements HttpClientRequest {
  _StubRequest(this._status, this._body);
  final int _status;
  final String _body;

  @override
  Future<HttpClientResponse> close() async => _StubResponse(_status, _body);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubResponse extends Stream<List<int>> implements HttpClientResponse {
  _StubResponse(this.statusCode, String body) : _bytes = utf8.encode(body);

  @override
  final int statusCode;
  final List<int> _bytes;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable([_bytes]).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
