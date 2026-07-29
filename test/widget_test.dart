import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu/app.dart';
import 'package:osu/models/rate_quote.dart';
import 'package:osu/services/rate_repository.dart';

class FakeRateRepository implements RateRepository {
  FakeRateRepository({this.cached = false});

  final bool cached;
  final calls = <(String, String)>[];

  @override
  Future<RateQuote> getRate({
    required String base,
    required String quote,
  }) async {
    calls.add((base, quote));
    final rate = switch ('$base-$quote') {
      'CNY-USD' => 0.14779,
      'USD-CNY' => 6.766,
      _ => 1.12,
    };
    return RateQuote(
      base: base,
      quote: quote,
      rate: rate,
      date: DateTime(2026, 7, 29),
      fetchedAt: DateTime(2026, 7, 29),
      isCached: cached,
    );
  }
}

Future<void> pumpOsu(WidgetTester tester, FakeRateRepository repository) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(OsuApp(repository: repository));
  await tester.pumpAndSettle();
}

TextEditingController controllerFor(WidgetTester tester, Key key) {
  return tester.widget<TextField>(find.byKey(key)).controller!;
}

void main() {
  testWidgets('converts the default amount and responds to typing', (
    tester,
  ) async {
    await pumpOsu(tester, FakeRateRepository());

    expect(controllerFor(tester, const Key('from_amount')).text, '1000');
    expect(controllerFor(tester, const Key('to_amount')).text, '147.79');
    expect(find.text('1 CNY = 0.1478 USD'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('from_amount')), '200');
    await tester.pump();

    expect(controllerFor(tester, const Key('to_amount')).text, '29.558');
  });

  testWidgets('swaps the pair while preserving the converted value', (
    tester,
  ) async {
    final repository = FakeRateRepository();
    await pumpOsu(tester, repository);

    await tester.ensureVisible(find.byKey(const Key('swap_button')));
    await tester.tap(find.byKey(const Key('swap_button')));
    await tester.pumpAndSettle();

    expect(controllerFor(tester, const Key('from_amount')).text, '147.79');
    expect(repository.calls.last, ('USD', 'CNY'));
    expect(find.text('1 USD = 6.7660 CNY'), findsOneWidget);
  });

  testWidgets('searches and selects a different currency', (tester) async {
    final repository = FakeRateRepository();
    await pumpOsu(tester, repository);

    await tester.ensureVisible(find.byKey(const Key('to_currency_button')));
    await tester.tap(find.byKey(const Key('to_currency_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('currency_search')),
      'Japanese',
    );
    await tester.pumpAndSettle();
    expect(find.text('Japanese yen'), findsOneWidget);

    await tester.tap(find.byKey(const Key('currency_JPY')));
    await tester.pumpAndSettle();

    expect(repository.calls.last, ('CNY', 'JPY'));
    expect(find.text('1 CNY = 1.1200 JPY'), findsOneWidget);
  });

  testWidgets('labels an offline cached rate', (tester) async {
    await pumpOsu(tester, FakeRateRepository(cached: true));

    expect(find.text('Offline — using your last saved rate.'), findsOneWidget);
  });
}
