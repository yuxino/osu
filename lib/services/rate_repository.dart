import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rate_quote.dart';

abstract interface class RateRepository {
  Future<RateQuote> getRate({required String base, required String quote});
}

class FrankfurterRateRepository implements RateRepository {
  FrankfurterRateRepository({
    http.Client? client,
    Future<SharedPreferences> Function()? preferencesFactory,
    this.freshness = const Duration(hours: 24),
  }) : _client = client ?? http.Client(),
       _preferencesFactory =
           preferencesFactory ?? SharedPreferences.getInstance;

  static const _cachePrefix = 'osu:rate:v2';
  static const _timeout = Duration(seconds: 8);

  final http.Client _client;
  final Future<SharedPreferences> Function() _preferencesFactory;
  final Duration freshness;

  @override
  Future<RateQuote> getRate({
    required String base,
    required String quote,
  }) async {
    if (base == quote) {
      final now = DateTime.now();
      return RateQuote(
        base: base,
        quote: quote,
        rate: 1,
        date: now,
        fetchedAt: now,
      );
    }

    final preferences = await _preferencesFactory();
    final cached = _readCache(preferences, base, quote);
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < freshness) {
      return cached;
    }

    try {
      final uri = Uri.https('api.frankfurter.dev', '/v2/rate/$base/$quote');
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        throw RateException('Rate service returned ${response.statusCode}.');
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const RateException('Rate service returned invalid data.');
      }

      final rate = (data['rate'] as num?)?.toDouble();
      final date = DateTime.tryParse(data['date'] as String? ?? '');
      if (rate == null || !rate.isFinite || rate <= 0 || date == null) {
        throw const RateException('Rate service returned an invalid rate.');
      }

      final result = RateQuote(
        base: base,
        quote: quote,
        rate: rate,
        date: date,
        fetchedAt: DateTime.now(),
      );
      await preferences.setString(
        _cacheKey(base, quote),
        jsonEncode(_toJson(result)),
      );
      return result;
    } on TimeoutException {
      if (cached != null) return cached.copyWith(isCached: true);
      throw const RateException('The rate service timed out.');
    } on RateException {
      if (cached != null) return cached.copyWith(isCached: true);
      rethrow;
    } catch (_) {
      if (cached != null) return cached.copyWith(isCached: true);
      throw const RateException('Unable to reach the rate service.');
    }
  }

  String _cacheKey(String base, String quote) {
    return '$_cachePrefix:$base:$quote';
  }

  RateQuote? _readCache(
    SharedPreferences preferences,
    String base,
    String quote,
  ) {
    try {
      final raw = preferences.getString(_cacheKey(base, quote));
      if (raw == null) return null;
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;

      final rate = (data['rate'] as num?)?.toDouble();
      final date = DateTime.tryParse(data['date'] as String? ?? '');
      final fetchedAt = DateTime.tryParse(data['fetchedAt'] as String? ?? '');
      if (rate == null || date == null || fetchedAt == null) return null;

      return RateQuote(
        base: base,
        quote: quote,
        rate: rate,
        date: date,
        fetchedAt: fetchedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, Object> _toJson(RateQuote value) {
    return {
      'rate': value.rate,
      'date': value.date.toIso8601String(),
      'fetchedAt': value.fetchedAt.toIso8601String(),
    };
  }
}

class RateException implements Exception {
  const RateException(this.message);

  final String message;

  @override
  String toString() => message;
}
