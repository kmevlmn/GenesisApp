import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/utils/server_clock.dart';

void main() {
  test(
    'server clock stays unknown until synchronized and advances by elapsed time',
    () {
      var elapsed = Duration.zero;
      final clock = ServerClock(elapsed: () => elapsed);
      expect(clock.now, isNull);

      final serverTime = DateTime.utc(2040, 1, 1);
      clock.synchronize(serverTime);
      elapsed = const Duration(minutes: 10);
      expect(clock.now, serverTime.add(elapsed));

      final correctedTime = DateTime.utc(2040, 1, 2);
      clock.synchronize(correctedTime);
      elapsed += const Duration(seconds: 3);
      expect(clock.now, correctedTime.add(const Duration(seconds: 3)));
      expect(clock.now!.isUtc, isTrue);
    },
  );
}
