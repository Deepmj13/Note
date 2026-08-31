class ApiConfig {
  /// Base URL of the Note backend API.
  ///
  /// Defaults to the production backend hosted on Render.
  ///
  /// For local development, override at build/run time via --dart-define, e.g.:
  ///   flutter run --dart-define=API_BASE_URL=http://localhost:3000
  /// (on an Android emulator, use --dart-define=API_BASE_URL=http://10.0.2.2:3000).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://notebackend-1ct7.onrender.com',
  );
}
