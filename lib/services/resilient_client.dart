import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Wraps an [http.Client] with the retry behaviour every one of these
/// networks eventually demands.
///
/// The distinction that matters is between *terminal* and *transient*
/// failures. A 404 means the same thing however many times you ask; a 429 or
/// a dropped connection usually doesn't. Retrying the first wastes time and
/// makes rate limiting worse, so only the second is retried.
///
/// 403 is deliberately terminal here. Reddit and X use it for "blocked",
/// which retrying won't fix — the clients handle it by falling back to
/// another route instead.
class ResilientClient extends http.BaseClient {
  ResilientClient({
    http.Client? inner,
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 400),
    this.timeout = const Duration(seconds: 25),
    this.maxRetryAfter = const Duration(seconds: 20),
    Random? random,
  })  : _inner = inner ?? http.Client(),
        _random = random ?? Random();

  final http.Client _inner;
  final int maxAttempts;
  final Duration baseDelay;
  final Duration timeout;

  /// A server asking us to wait longer than this is telling us to come back
  /// later, not to block the refresh.
  final Duration maxRetryAfter;

  final Random _random;

  static const _retryableStatuses = {408, 429, 500, 502, 503, 504};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _inner
            .send(_copy(request))
            .timeout(timeout);

        if (!_retryableStatuses.contains(response.statusCode) ||
            attempt == maxAttempts) {
          return response;
        }

        final wait = _retryAfter(response) ?? _backoff(attempt);
        if (wait > maxRetryAfter) return response;

        // The body has to be drained or the connection leaks.
        await response.stream.drain<void>();
        await Future<void>.delayed(wait);
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(_backoff(attempt));
      } on SocketException catch (e) {
        lastError = e;
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(_backoff(attempt));
      } on http.ClientException catch (e) {
        lastError = e;
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(_backoff(attempt));
      }
    }

    throw lastError ?? http.ClientException('Request failed', request.url);
  }

  /// Exponential, with jitter so several sources refreshing together don't
  /// retry in lockstep and hit the same server at the same instant.
  Duration _backoff(int attempt) {
    final exponential = baseDelay * pow(2, attempt - 1).toDouble();
    final jitter = _random.nextDouble() * 0.3 + 0.85;
    return Duration(
        milliseconds: (exponential.inMilliseconds * jitter).round());
  }

  /// `Retry-After` is either a number of seconds or an HTTP date.
  static Duration? _retryAfter(http.BaseResponse response) {
    final value = response.headers['retry-after'];
    if (value == null) return null;

    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: seconds);

    try {
      final when = HttpDate.parse(value);
      final delta = when.difference(DateTime.now());
      return delta.isNegative ? Duration.zero : delta;
    } catch (_) {
      return null;
    }
  }

  /// A request can only be sent once, so each attempt needs a fresh copy.
  static http.BaseRequest _copy(http.BaseRequest request) {
    if (request is http.Request) {
      return http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;
    }
    // Streamed and multipart bodies can't be replayed; send as-is and let
    // a failure be terminal rather than corrupting the request.
    return request;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
