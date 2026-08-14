import 'dart:convert';

/// Builds the namespaced, account-scoped cache key used by [CachedResource]
/// stores. Lives in core so background tasks (platform) can write into the
/// same cache slots that the app reads from.
String resourceCacheKey(
  String namespace, {
  required String? username,
  String? scope,
}) {
  return [
    'resource_cache_v1',
    _safeKeyPart(namespace),
    _safeKeyPart(username),
    _safeKeyPart(scope),
  ].join(':');
}

String _safeKeyPart(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'default';
  return base64Url.encode(utf8.encode(trimmed));
}
