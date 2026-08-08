/// How a source is faring, so the UI can distinguish "this broke just now"
/// from "this has been broken for a week".
class SourceHealth {
  const SourceHealth({
    this.consecutiveFailures = 0,
    this.lastSuccess,
    this.lastError,
  });

  final int consecutiveFailures;
  final DateTime? lastSuccess;
  final String? lastError;

  bool get isFailing => consecutiveFailures > 0;

  /// Failing repeatedly rather than once. A single blip isn't worth
  /// bothering anyone about; a persistent one is.
  bool get isPersistentlyFailing => consecutiveFailures >= 3;

  SourceHealth succeeded(DateTime at) => SourceHealth(lastSuccess: at);

  SourceHealth failed(String error) => SourceHealth(
        consecutiveFailures: consecutiveFailures + 1,
        lastSuccess: lastSuccess,
        lastError: error,
      );

  /// How long the source has been unreachable, if it ever worked.
  Duration? stalenessAt(DateTime now) =>
      lastSuccess == null ? null : now.difference(lastSuccess!);
}
