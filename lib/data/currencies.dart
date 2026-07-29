import '../models/currency_info.dart';

const currencies = <CurrencyInfo>[
  CurrencyInfo(code: 'CNY', name: 'Chinese yuan', symbol: '¥', flag: '🇨🇳'),
  CurrencyInfo(code: 'USD', name: 'US dollar', symbol: '\$', flag: '🇺🇸'),
  CurrencyInfo(code: 'EUR', name: 'Euro', symbol: '€', flag: '🇪🇺'),
  CurrencyInfo(code: 'JPY', name: 'Japanese yen', symbol: '¥', flag: '🇯🇵'),
  CurrencyInfo(code: 'GBP', name: 'British pound', symbol: '£', flag: '🇬🇧'),
  CurrencyInfo(
    code: 'HKD',
    name: 'Hong Kong dollar',
    symbol: 'HK\$',
    flag: '🇭🇰',
  ),
  CurrencyInfo(
    code: 'SGD',
    name: 'Singapore dollar',
    symbol: 'S\$',
    flag: '🇸🇬',
  ),
  CurrencyInfo(
    code: 'KRW',
    name: 'South Korean won',
    symbol: '₩',
    flag: '🇰🇷',
  ),
  CurrencyInfo(
    code: 'AUD',
    name: 'Australian dollar',
    symbol: 'A\$',
    flag: '🇦🇺',
  ),
  CurrencyInfo(
    code: 'CAD',
    name: 'Canadian dollar',
    symbol: 'C\$',
    flag: '🇨🇦',
  ),
  CurrencyInfo(code: 'CHF', name: 'Swiss franc', symbol: 'Fr', flag: '🇨🇭'),
  CurrencyInfo(
    code: 'NZD',
    name: 'New Zealand dollar',
    symbol: 'NZ\$',
    flag: '🇳🇿',
  ),
  CurrencyInfo(code: 'INR', name: 'Indian rupee', symbol: '₹', flag: '🇮🇳'),
  CurrencyInfo(code: 'THB', name: 'Thai baht', symbol: '฿', flag: '🇹🇭'),
  CurrencyInfo(
    code: 'MYR',
    name: 'Malaysian ringgit',
    symbol: 'RM',
    flag: '🇲🇾',
  ),
  CurrencyInfo(code: 'PHP', name: 'Philippine peso', symbol: '₱', flag: '🇵🇭'),
  CurrencyInfo(code: 'SEK', name: 'Swedish krona', symbol: 'kr', flag: '🇸🇪'),
  CurrencyInfo(
    code: 'NOK',
    name: 'Norwegian krone',
    symbol: 'kr',
    flag: '🇳🇴',
  ),
  CurrencyInfo(code: 'DKK', name: 'Danish krone', symbol: 'kr', flag: '🇩🇰'),
  CurrencyInfo(code: 'PLN', name: 'Polish złoty', symbol: 'zł', flag: '🇵🇱'),
  CurrencyInfo(
    code: 'BRL',
    name: 'Brazilian real',
    symbol: 'R\$',
    flag: '🇧🇷',
  ),
  CurrencyInfo(code: 'MXN', name: 'Mexican peso', symbol: 'MX\$', flag: '🇲🇽'),
  CurrencyInfo(
    code: 'ZAR',
    name: 'South African rand',
    symbol: 'R',
    flag: '🇿🇦',
  ),
  CurrencyInfo(code: 'TRY', name: 'Turkish lira', symbol: '₺', flag: '🇹🇷'),
];

const quickPairs = <(String, String)>[
  ('CNY', 'USD'),
  ('USD', 'JPY'),
  ('EUR', 'GBP'),
  ('HKD', 'CNY'),
];

CurrencyInfo currencyByCode(String code) {
  return currencies.firstWhere(
    (currency) => currency.code == code,
    orElse: () => currencies.first,
  );
}
