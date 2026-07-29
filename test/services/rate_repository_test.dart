import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:osu/services/rate_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fetches and caches a valid Frankfurter response', () async {
    final repository = FrankfurterRateRepository(
      client: MockClient((request) async {
        expect(request.url.host, 'api.frankfurter.dev');
        expect(request.url.path, '/v2/rate/CNY/USD');
        return Response(
          jsonEncode({
            'date': '2026-07-29',
            'base': 'CNY',
            'quote': 'USD',
            'rate': 0.14779,
          }),
          200,
        );
      }),
    );

    final result = await repository.getRate(base: 'CNY', quote: 'USD');

    expect(result.rate, 0.14779);
    expect(result.date, DateTime(2026, 7, 29));
    expect(result.isCached, isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('osu:rate:v2:CNY:USD'), isNotNull);
  });

  test('falls back to a saved rate when the network fails', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'osu:rate:v2:CNY:USD',
      jsonEncode({
        'rate': 0.15,
        'date': '2026-07-28T00:00:00.000',
        'fetchedAt': '2026-07-28T00:00:00.000',
      }),
    );

    final repository = FrankfurterRateRepository(
      freshness: Duration.zero,
      client: MockClient((_) async => throw Exception('offline')),
    );

    final result = await repository.getRate(base: 'CNY', quote: 'USD');

    expect(result.rate, 0.15);
    expect(result.isCached, isTrue);
  });

  test('rejects an invalid response without a cached rate', () async {
    final repository = FrankfurterRateRepository(
      client: MockClient((_) async => Response('{"rate":0}', 200)),
    );

    expect(
      repository.getRate(base: 'CNY', quote: 'USD'),
      throwsA(isA<RateException>()),
    );
  });
}
