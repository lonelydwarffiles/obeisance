const String backendBaseUrl = String.fromEnvironment(
  'BACKEND_BASE_URL',
  defaultValue: 'http://<backend-url>',
);

const int centralAutoRefreshSeconds = int.fromEnvironment(
  'CENTRAL_AUTO_REFRESH_SECONDS',
  defaultValue: 45,
);
