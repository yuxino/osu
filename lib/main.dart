import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/rate_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(OsuApp(repository: FrankfurterRateRepository()));
}
