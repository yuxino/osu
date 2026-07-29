class RateQuote {
  const RateQuote({
    required this.base,
    required this.quote,
    required this.rate,
    required this.date,
    required this.fetchedAt,
    this.isCached = false,
  });

  final String base;
  final String quote;
  final double rate;
  final DateTime date;
  final DateTime fetchedAt;
  final bool isCached;

  RateQuote copyWith({bool? isCached}) {
    return RateQuote(
      base: base,
      quote: quote,
      rate: rate,
      date: date,
      fetchedAt: fetchedAt,
      isCached: isCached ?? this.isCached,
    );
  }
}
