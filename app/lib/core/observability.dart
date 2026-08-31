import 'package:sentry_flutter/sentry_flutter.dart';

/// Build-time configuration for the Sentry SDK.
///
/// Override at build/run time, e.g.:
///   flutter run --dart-define=SENTRY_DSN=https://...@ingest.sentry.io/...
class AppConfig {
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );
}

final bool _sentryEnabled = AppConfig.sentryDsn.isNotEmpty;

/// Whether Sentry error tracking is active (requires a SENTRY_DSN).
bool get sentryEnabled => _sentryEnabled;

/// Initializes Sentry only when a SENTRY_DSN was provided at build time.
/// Without one the app runs normally with no crash-reporting overhead.
Future<void> initObservability() async {
  if (!sentryEnabled) return;
  await SentryFlutter.init(
    (options) {
      options.dsn = AppConfig.sentryDsn;
      options.tracesSampleRate = 0.1;
    },
  );
}
