/// Estimates the offset between the local clock and the server clock from
/// ping/pong samples, NTP-style: for each round trip, assume the server
/// timestamp was taken at the midpoint. The median of several samples
/// rejects outliers from jittery round trips.
class ClockSync {
  final List<int> _offsets = []; // serverTime - localMidpoint, ms
  static const int maxSamples = 9;

  /// Record one round trip: [t0] local send time, [serverTime] the server's
  /// clock when it handled the ping, [t1] local receive time (all ms).
  void addSample({required int t0, required int serverTime, required int t1}) {
    final midpoint = t0 + ((t1 - t0) ~/ 2);
    _offsets.add(serverTime - midpoint);
    if (_offsets.length > maxSamples) _offsets.removeAt(0);
  }

  bool get hasFix => _offsets.isNotEmpty;

  /// Median offset in milliseconds (server − local). 0 until samples exist.
  int get offsetMs {
    if (_offsets.isEmpty) return 0;
    final sorted = List<int>.of(_offsets)..sort();
    return sorted[sorted.length ~/ 2];
  }

  int toServer(int localMs) => localMs + offsetMs;
  int toLocal(int serverMs) => serverMs - offsetMs;
}
