import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/shared.dart';
import '../auth/auth_providers.dart';

typedef ResourceEncoder<T> = Object? Function(T data);
typedef ResourceDecoder<T> = T Function(Object? json);

const Object _unset = Object();

String? _activeUsername(Ref ref) {
  final username = ref.read(credentialsProvider)?.username.trim();
  return username == null || username.isEmpty ? null : username;
}

class CachedResource<T> {
  const CachedResource({
    required this.data,
    this.hasData = false,
    this.isRefreshing = false,
    this.error,
    this.stackTrace,
    this.consecutiveFailures = 0,
    this.updatedAt,
  });

  final T data;
  final bool hasData;
  final bool isRefreshing;
  final Object? error;
  final StackTrace? stackTrace;
  final int consecutiveFailures;
  final DateTime? updatedAt;

  bool get hasError => error != null;
  bool get shouldOfferManualRefresh => consecutiveFailures >= 3;
  bool get isLoading => isRefreshing && !hasData;
  bool get hasValue => hasData;
  T? get valueOrNull => hasData ? data : null;

  R when<R>({
    required R Function(T data) data,
    required R Function() loading,
    required R Function(Object error, StackTrace stackTrace) error,
    bool skipError = false,
    bool skipLoadingOnRefresh = false,
    bool skipLoadingOnReload = false,
  }) {
    if (hasData || !shouldOfferManualRefresh || skipError) {
      return data(this.data);
    }
    if (hasError) return error(this.error!, stackTrace ?? StackTrace.current);
    return data(this.data);
  }

  CachedResource<T> copyWith({
    Object? data = _unset,
    bool? hasData,
    bool? isRefreshing,
    Object? error = _unset,
    Object? stackTrace = _unset,
    int? consecutiveFailures,
    Object? updatedAt = _unset,
  }) {
    return CachedResource<T>(
      data: identical(data, _unset) ? this.data : data as T,
      hasData: hasData ?? this.hasData,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: identical(error, _unset) ? this.error : error,
      stackTrace: identical(stackTrace, _unset)
          ? this.stackTrace
          : stackTrace as StackTrace?,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      updatedAt: identical(updatedAt, _unset)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

class CachedSnapshot<T> {
  const CachedSnapshot({required this.data, required this.updatedAt});

  final T data;
  final DateTime updatedAt;
}

class ResourceCacheStore<T> {
  const ResourceCacheStore({
    required this.key,
    required this.encode,
    required this.decode,
  });

  final String key;
  final ResourceEncoder<T> encode;
  final ResourceDecoder<T> decode;

  Future<CachedSnapshot<T>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final updatedAtMs =
        int.tryParse(decoded['updatedAtMs']?.toString() ?? '') ?? 0;
    return CachedSnapshot<T>(
      data: decode(decoded['data']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
  }

  Future<void> write(T data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'data': encode(data),
      }),
    );
  }
}

abstract class CachedResourceNotifier<T, Arg>
    extends FamilyNotifier<CachedResource<T>, Arg> {
  late Arg _arg;
  Timer? _timer;
  Future<CachedResource<T>>? _inflightRefresh;
  String? _inflightUsername;
  bool _disposed = false;

  T get emptyData;
  Arg get resourceArg => _arg;
  String get cacheNamespace;
  Duration? get automaticRefreshInterval => null;

  Object? encode(T data);
  T decode(Object? json);
  String? cacheScopeForArg(Arg arg);

  void listenDependencies(Arg arg) {}

  Future<T> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  });

  FutureOr<void> onData(T data, {required bool changed}) {}

  @override
  CachedResource<T> build(Arg arg) {
    _arg = arg;
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });

    ref.listen<({String username, String password})?>(credentialsProvider, (
      previous,
      next,
    ) {
      if (next == null) {
        state = CachedResource<T>(data: emptyData);
      } else if (previous?.username != next.username) {
        state = CachedResource<T>(data: emptyData);
        unawaited(restoreCachedThenRefresh(forceRefresh: true));
      }
    });

    ref.listen<int>(sessionUpdateProvider, (_, next) {
      unawaited(refresh(forceRefresh: true));
    });

    listenDependencies(arg);
    _scheduleAutomaticRefresh();
    unawaited(restoreCachedThenRefresh());

    return CachedResource<T>(data: emptyData);
  }

  Future<CachedResource<T>> restoreCachedThenRefresh({
    bool forceRefresh = false,
  }) async {
    final username = _activeUsername(ref);
    if (username == null) {
      if (!_disposed) state = CachedResource<T>(data: emptyData);
      return state;
    }

    final cached = await _readCache(username: username);
    if (!_isCurrentAccount(username)) return state;

    if (cached != null) {
      state = state.copyWith(
        data: cached.data,
        hasData: true,
        updatedAt: cached.updatedAt,
      );
    } else {
      state = CachedResource<T>(data: emptyData);
    }

    return refresh(forceRefresh: forceRefresh);
  }

  Future<CachedResource<T>> refresh({
    bool forceRefresh = false,
    bool throwOnError = false,
  }) {
    final username = _activeUsername(ref);
    if (username == null) return Future.value(state);
    final existing = _inflightRefresh;
    if (existing != null && !forceRefresh && _inflightUsername == username) {
      return existing;
    }

    final task = _refreshInternal(
      forceRefresh: forceRefresh,
      throwOnError: throwOnError,
    );
    _inflightUsername = username;
    late final Future<CachedResource<T>> trackedTask;
    trackedTask = task.whenComplete(() {
      if (identical(_inflightRefresh, trackedTask)) {
        _inflightRefresh = null;
        _inflightUsername = null;
      }
    });
    _inflightRefresh = trackedTask;
    return trackedTask;
  }

  Future<CachedResource<T>> _refreshInternal({
    required bool forceRefresh,
    required bool throwOnError,
  }) async {
    final creds = ref.read(credentialsProvider);
    if (creds == null) return state;
    final username = creds.username.trim();
    if (username.isEmpty) return state;

    state = state.copyWith(isRefreshing: true, error: null, stackTrace: null);

    try {
      final fresh = await fetch(creds, forceRefresh: forceRefresh);
      if (!_isCurrentAccount(username)) return state;

      final changed = !state.hasData || !_sameData(state.data, fresh);
      final updatedAt = DateTime.now();
      await _writeCache(fresh, username: username);
      if (!_isCurrentAccount(username)) return state;

      state = state.copyWith(
        data: fresh,
        hasData: true,
        isRefreshing: false,
        error: null,
        stackTrace: null,
        consecutiveFailures: 0,
        updatedAt: updatedAt,
      );

      try {
        await onData(fresh, changed: changed);
      } catch (error) {
        debugPrint('[CachedResource] post-update hook failed: $error');
      }

      return state;
    } catch (error, stackTrace) {
      if (_isCurrentAccount(username)) {
        state = state.copyWith(
          isRefreshing: false,
          error: error,
          stackTrace: stackTrace,
          consecutiveFailures: state.consecutiveFailures + 1,
        );
      }
      if (throwOnError) Error.throwWithStackTrace(error, stackTrace);
      return state;
    }
  }

  Future<CachedSnapshot<T>?> _readCache({required String? username}) {
    return ResourceCacheStore<T>(
      key: resourceCacheKey(
        cacheNamespace,
        username: username,
        scope: cacheScopeForArg(_arg),
      ),
      encode: encode,
      decode: decode,
    ).read();
  }

  bool _isCurrentAccount(String username) =>
      !_disposed && _activeUsername(ref) == username;

  Future<void> _writeCache(T data, {required String username}) async {
    if (!_isCurrentAccount(username)) return;
    final scopedStore = ResourceCacheStore<T>(
      key: resourceCacheKey(
        cacheNamespace,
        username: username,
        scope: cacheScopeForArg(_arg),
      ),
      encode: encode,
      decode: decode,
    );
    await scopedStore.write(data);
  }

  bool _sameData(T current, T next) {
    try {
      return jsonEncode(encode(current)) == jsonEncode(encode(next));
    } catch (_) {
      return false;
    }
  }

  void _scheduleAutomaticRefresh() {
    final interval = automaticRefreshInterval;
    if (interval == null) return;

    _timer?.cancel();
    _timer = Timer(interval, () {
      if (_disposed) return;
      unawaited(refresh());
      _scheduleAutomaticRefresh();
    });
  }
}

abstract class SimpleCachedResourceNotifier<T>
    extends Notifier<CachedResource<T>> {
  Timer? _timer;
  Future<CachedResource<T>>? _inflightRefresh;
  String? _inflightUsername;
  bool _disposed = false;

  T get emptyData;
  String get cacheNamespace;
  String? get cacheScope => null;
  Duration? get automaticRefreshInterval => null;

  Object? encode(T data);
  T decode(Object? json);

  void listenDependencies() {}

  Future<T> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  });

  FutureOr<void> onData(T data, {required bool changed}) {}

  @override
  CachedResource<T> build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });

    ref.listen<({String username, String password})?>(credentialsProvider, (
      previous,
      next,
    ) {
      if (next == null) {
        state = CachedResource<T>(data: emptyData);
      } else if (previous?.username != next.username) {
        state = CachedResource<T>(data: emptyData);
        unawaited(restoreCachedThenRefresh(forceRefresh: true));
      }
    });

    ref.listen<int>(sessionUpdateProvider, (_, next) {
      unawaited(refresh(forceRefresh: true));
    });

    listenDependencies();
    _scheduleAutomaticRefresh();
    unawaited(restoreCachedThenRefresh());

    return CachedResource<T>(data: emptyData);
  }

  Future<CachedResource<T>> restoreCachedThenRefresh({
    bool forceRefresh = false,
  }) async {
    final username = _activeUsername(ref);
    if (username == null) {
      if (!_disposed) state = CachedResource<T>(data: emptyData);
      return state;
    }

    final cached = await _readCache(username: username);
    if (!_isCurrentAccount(username)) return state;

    if (cached != null) {
      state = state.copyWith(
        data: cached.data,
        hasData: true,
        updatedAt: cached.updatedAt,
      );
    } else {
      state = CachedResource<T>(data: emptyData);
    }

    return refresh(forceRefresh: forceRefresh);
  }

  Future<CachedResource<T>> refresh({
    bool forceRefresh = false,
    bool throwOnError = false,
  }) {
    final username = _activeUsername(ref);
    if (username == null) return Future.value(state);
    final existing = _inflightRefresh;
    if (existing != null && !forceRefresh && _inflightUsername == username) {
      return existing;
    }

    final task = _refreshInternal(
      forceRefresh: forceRefresh,
      throwOnError: throwOnError,
    );
    _inflightUsername = username;
    late final Future<CachedResource<T>> trackedTask;
    trackedTask = task.whenComplete(() {
      if (identical(_inflightRefresh, trackedTask)) {
        _inflightRefresh = null;
        _inflightUsername = null;
      }
    });
    _inflightRefresh = trackedTask;
    return trackedTask;
  }

  Future<CachedResource<T>> _refreshInternal({
    required bool forceRefresh,
    required bool throwOnError,
  }) async {
    final creds = ref.read(credentialsProvider);
    if (creds == null) return state;
    final username = creds.username.trim();
    if (username.isEmpty) return state;

    state = state.copyWith(isRefreshing: true, error: null, stackTrace: null);

    try {
      final fresh = await fetch(creds, forceRefresh: forceRefresh);
      if (!_isCurrentAccount(username)) return state;

      final changed = !state.hasData || !_sameData(state.data, fresh);
      final updatedAt = DateTime.now();
      await _writeCache(fresh, username: username);
      if (!_isCurrentAccount(username)) return state;

      state = state.copyWith(
        data: fresh,
        hasData: true,
        isRefreshing: false,
        error: null,
        stackTrace: null,
        consecutiveFailures: 0,
        updatedAt: updatedAt,
      );

      try {
        await onData(fresh, changed: changed);
      } catch (error) {
        debugPrint('[CachedResource] post-update hook failed: $error');
      }

      return state;
    } catch (error, stackTrace) {
      if (_isCurrentAccount(username)) {
        state = state.copyWith(
          isRefreshing: false,
          error: error,
          stackTrace: stackTrace,
          consecutiveFailures: state.consecutiveFailures + 1,
        );
      }
      if (throwOnError) Error.throwWithStackTrace(error, stackTrace);
      return state;
    }
  }

  Future<CachedSnapshot<T>?> _readCache({required String? username}) {
    return ResourceCacheStore<T>(
      key: resourceCacheKey(
        cacheNamespace,
        username: username,
        scope: cacheScope,
      ),
      encode: encode,
      decode: decode,
    ).read();
  }

  bool _isCurrentAccount(String username) =>
      !_disposed && _activeUsername(ref) == username;

  Future<void> _writeCache(T data, {required String username}) async {
    if (!_isCurrentAccount(username)) return;
    final scopedStore = ResourceCacheStore<T>(
      key: resourceCacheKey(
        cacheNamespace,
        username: username,
        scope: cacheScope,
      ),
      encode: encode,
      decode: decode,
    );
    await scopedStore.write(data);
  }

  bool _sameData(T current, T next) {
    try {
      return jsonEncode(encode(current)) == jsonEncode(encode(next));
    } catch (_) {
      return false;
    }
  }

  void _scheduleAutomaticRefresh() {
    final interval = automaticRefreshInterval;
    if (interval == null) return;

    _timer?.cancel();
    _timer = Timer(interval, () {
      if (_disposed) return;
      unawaited(refresh());
      _scheduleAutomaticRefresh();
    });
  }
}

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
