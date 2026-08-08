/// How a source is faring, so the UI can distinguish "this broke just now"
/// from "this has been broken for a week".
class SourceHealth {
  const SourceHealth({
    this.consecutiveFailures = 0,
    this.lastSuccess,
    this.lastError,
    this.lastFailure,
  });

  final int consecutiveFailures;
  final DateTime? lastSuccess;
  final String? lastError;
  final DateTime? lastFailure;

  bool get isFailing => consecutiveFailures > 0;

  /// Failing repeatedly rather than once. A single blip isn't worth
  /// bothering anyone about; a persistent one is.
  bool get isPersistentlyFailing => consecutiveFailures >= 3;

  SourceHealth succeeded(DateTime at) => SourceHealth(lastSuccess: at);

  SourceHealth failed(String error, [DateTime? at]) => SourceHealth(
        consecutiveFailures: consecutiveFailures + 1,
        lastSuccess: lastSuccess,
        lastError: error,
        lastFailure: at,
      );

  /// How long the source has been unreachable, if it ever worked.
  Duration? stalenessAt(DateTime now) =>
      lastSuccess == null ? null : now.difference(lastSuccess!);

  /// How long to leave a failing source alone before asking again.
  ///
  /// A source that answers 403 answers 403 to the next request too, and
  /// asking every thirty seconds is how a temporary block becomes a
  /// lasting one. The first couple of failures are treated as blips and
  /// retried immediately; after that it backs off, capped so a source is
  /// never abandoned outright.
  /// Indexed by [consecutiveFailures], so entry 0 is never used and the
  /// first two failures cost nothing.
  static const _backoff = [
    Duration.zero,
    Duration.zero,
    Duration.zero,
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];

  Duration get retryDelay => consecutiveFailures <= 0
      ? Duration.zero
      : _backoff[consecutiveFailures.clamp(0, _backoff.length - 1)];

  /// Whether this source should be asked again yet.
  ///
  /// A manual refresh passes [force], because someone watching the screen
  /// and pulling to refresh is asking for a real attempt, not a policy.
  bool shouldFetchAt(DateTime now, {bool force = false}) {
    if (force || lastFailure == null) return true;
    return now.difference(lastFailure!) >= retryDelay;
  }
}
