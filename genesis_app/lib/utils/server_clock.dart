/// Server UTC time advanced by elapsed time, unaffected by device clock edits.
class ServerClock {
  ServerClock({Duration Function()? elapsed})
    : _elapsed = elapsed ?? _startElapsedClock();

  final Duration Function() _elapsed;
  DateTime? _serverTime;
  Duration _synchronizedAt = Duration.zero;

  DateTime? get now => _serverTime?.add(_elapsed() - _synchronizedAt);

  void synchronize(DateTime serverTime) {
    _serverTime = serverTime.toUtc();
    _synchronizedAt = _elapsed();
  }

  static Duration Function() _startElapsedClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
