import 'dart:async';
import 'dart:convert';

export 'package:core/utils/resource_cache_key.dart';

import 'package:core/utils/resource_cache_key.dart';
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

  /// Selects the branch that matches the current resource state.
  ///
  /// Resolution order is deliberate:
  /// 1. Cached data wins over everything (stale-while-revalidate). A failed
  ///    background refresh must never blank out data the user can still read;
  ///    [BackgroundRefreshBanner] plus [shouldOfferManualRefresh] is how that
  ///    staleness gets disclosed instead.
  /// 2. With no data yet, an in-flight fetch is [loading] — never an empty
  ///    [data] payload, which would render "暂无数据" while the request is
  ///    still running and then jump when it lands.
  /// 3. With no data and no in-flight fetch, a recorded failure is [error]
  ///    from the very first failure, so the user gets a retry affordance
  ///    without having to fail three times first.
  ///
  /// [skipError] keeps showing [data] instead of [error] on a cold failure.
  /// It only applies to the no-data case, since cached data already wins.
  R when<R>({
    required R Function(T data) data,
    required R Function() loading,
    required R Function(Object error, StackTrace stackTrace) error,
    bool skipError = false,
    bool skipLoadingOnRefresh = false,
    bool skipLoadingOnReload = false,
  }) {
    if (hasData) return data(this.data);
    if (isRefreshing) return loading();
    if (hasError && !skipError) {
      return error(this.error!, stackTrace ?? StackTrace.current);
    }
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

class _RefreshResult<T> {
  const _RefreshResult.success(this.state) : error = null, stackTrace = null;

  const _RefreshResult.failure({
    required this.error,
    required this.stackTrace,
    required this.state,
  });

  final CachedResource<T> state;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isSuccess => error == null;

  CachedResource<T> unwrap({required bool throwOnError}) {
    if (throwOnError && error != null) {
      Error.throwWithStackTrace(error!, stackTrace ?? StackTrace.current);
    }
    return state;
  }
}

/// Shared refresh machinery for cached resources.
///
/// Applied to both [CachedResourceNotifier] (family) and
/// [SimpleCachedResourceNotifier] (non-family). The host must be a Riverpod
/// notifier whose state is [CachedResource]; the mixin declares [ref] and
/// [state] as abstract members that the host's inherited members satisfy.
///
/// Behavioural contract:
/// - A cached snapshot is restored first, then a background refresh runs.
/// - Concurrent refresh calls for the same account are merged: plain calls
///   reuse the in-flight chain, and force calls are serialized behind it so
///   the same resource never issues two concurrent network requests.
/// - When [cacheFreshness] is set, non-forced refreshes skip the network while
///   the cached data is younger than the freshness window; forced refreshes
///   and manual refreshes always bypass it.
mixin CachedResourceRefreshMixin<T> {
  late Ref<CachedResource<T>> _ref;
  CachedResource<T> get state;
  set state(CachedResource<T> value);

  T get emptyData;
  String get cacheNamespace;
  String? get cacheScope => null;
  Duration? get automaticRefreshInterval => null;

  /// Data-cache freshness window. Independent from session/domain health
  /// freshness. Null disables the skip (default).
  Duration? get cacheFreshness => null;

  Object? encode(T data);
  T decode(Object? json);

  Future<T> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  });

  FutureOr<void> onData(T data, {required bool changed}) {}

  Timer? _timer;
  Future<_RefreshResult<T>>? _queueTail;
  String? _inflightUsername;
  bool _forcePending = false;
  bool _disposed = false;

  /// Wires lifecycle listeners. Must be called from the host's [build]
  /// before returning the initial state.
  void wireResourceLifecycle(
    Ref<CachedResource<T>> ref,
    void Function() listenDependencies,
  ) {
    _ref = ref;
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
  }

  Future<CachedResource<T>> restoreCachedThenRefresh({
    bool forceRefresh = false,
  }) async {
    final username = _activeUsername(_ref);
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

  /// Refreshes the resource.
  ///
  /// Same-account refreshes are serialized behind a single chain tail:
  /// - plain refreshes join the in-flight chain (dedup);
  /// - force refreshes merge into an already-pending force instead of
  ///   queueing duplicate network work, and otherwise queue exactly one
  ///   force refresh behind the chain;
  /// - a queued force is dropped when the account changed while it waited,
  ///   so it never issues a request with the new account's credentials.
  Future<CachedResource<T>> refresh({
    bool forceRefresh = false,
    bool throwOnError = false,
  }) {
    final username = _activeUsername(_ref);
    if (username == null) return Future.value(state);

    final tail = _queueTail;
    final sameAccount = _inflightUsername == username;
    if (tail != null && sameAccount) {
      if (forceRefresh && _forcePending) {
        // Merge: an in-flight or queued force already covers this request.
        // The caller inspects the self-contained result of that force request,
        // rethrowing on failure if throwOnError is true, or returning state.
        return tail.then<CachedResource<T>>(
          (result) => result.unwrap(throwOnError: throwOnError),
        );
      }
      if (!forceRefresh) {
        // Plain refresh joins the in-flight chain (dedup).
        return tail.then<CachedResource<T>>(
          (result) => result.unwrap(throwOnError: throwOnError),
        );
      }

      _forcePending = true;
      final chained = tail.then<_RefreshResult<T>>((_) {
        if (_activeUsername(_ref) != username) {
          // Account switched while queued: never fetch with new creds.
          return _RefreshResult<T>.success(state);
        }
        return _refreshInternal(username: username, forceRefresh: true);
      });
      _queueTail = chained;
      chained.whenComplete(() {
        if (identical(_queueTail, chained)) {
          _queueTail = null;
          _inflightUsername = null;
          _forcePending = false;
        }
      }).ignore();
      return chained.then<CachedResource<T>>(
        (result) => result.unwrap(throwOnError: throwOnError),
      );
    }

    return _startRefresh(
      username: username,
      forceRefresh: forceRefresh,
      throwOnError: throwOnError,
    );
  }

  Future<CachedResource<T>> _startRefresh({
    required String username,
    required bool forceRefresh,
    required bool throwOnError,
  }) {
    final task = _refreshInternal(
      username: username,
      forceRefresh: forceRefresh,
    );
    final wasOtherAccount =
        _inflightUsername != null && _inflightUsername != username;
    _inflightUsername = username;
    if (forceRefresh) _forcePending = true;
    late final Future<_RefreshResult<T>> trackedTask;
    trackedTask = task.whenComplete(() {
      if (identical(_queueTail, trackedTask)) {
        _queueTail = null;
        _inflightUsername = null;
        _forcePending = false;
      }
    });
    // An account switch starts immediately (its tail replaces the previous
    // account's), while same-account refreshes keep the serialized tail so
    // queued work is never lost or duplicated.
    if (_queueTail == null || wasOtherAccount) _queueTail = trackedTask;
    return trackedTask.then<CachedResource<T>>(
      (result) => result.unwrap(throwOnError: throwOnError),
    );
  }

  Future<_RefreshResult<T>> _refreshInternal({
    required String username,
    required bool forceRefresh,
  }) async {
    final creds = _ref.read(credentialsProvider);
    if (creds == null) return _RefreshResult.success(state);
    final activeUsername = creds.username.trim();
    if (activeUsername.isEmpty || activeUsername != username) {
      return _RefreshResult.success(state);
    }

    // Data-cache freshness: skip the network while cached data is young.
    // Forced refreshes always bypass this window; a non-positive age means
    // the device clock moved backwards, so the cache is treated as stale.
    final freshness = cacheFreshness;
    if (!forceRefresh && freshness != null && state.hasData) {
      final updatedAt = state.updatedAt;
      if (updatedAt != null) {
        final age = DateTime.now().difference(updatedAt);
        if (!age.isNegative && age < freshness) {
          return _RefreshResult.success(state);
        }
      }
    }

    if (_isCurrentAccount(username)) {
      state = state.copyWith(isRefreshing: true, error: null, stackTrace: null);
    }

    try {
      final fresh = await fetch(creds, forceRefresh: forceRefresh);
      if (!_isCurrentAccount(username)) return _RefreshResult.success(state);

      final changed = !state.hasData || !_sameData(state.data, fresh);
      final updatedAt = DateTime.now();
      await _writeCache(fresh, username: username);
      if (!_isCurrentAccount(username)) return _RefreshResult.success(state);

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

      return _RefreshResult.success(state);
    } catch (error, stackTrace) {
      if (_isCurrentAccount(username)) {
        state = state.copyWith(
          isRefreshing: false,
          error: error,
          stackTrace: stackTrace,
          consecutiveFailures: state.consecutiveFailures + 1,
        );
      }
      return _RefreshResult.failure(
        error: error,
        stackTrace: stackTrace,
        state: state,
      );
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
      !_disposed && _activeUsername(_ref) == username;

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

/// Family variant of the cached-resource notifier.
///
/// Kept as the public base class for API compatibility; the shared logic
/// lives in [CachedResourceRefreshMixin].
abstract class CachedResourceNotifier<T, Arg>
    extends FamilyNotifier<CachedResource<T>, Arg>
    with CachedResourceRefreshMixin<T> {
  late Arg _arg;

  Arg get resourceArg => _arg;
  String? cacheScopeForArg(Arg arg);
  void listenDependencies(Arg arg) {}

  @override
  String? get cacheScope => cacheScopeForArg(_arg);

  @override
  CachedResource<T> build(Arg arg) {
    _arg = arg;
    wireResourceLifecycle(ref, () => listenDependencies(arg));
    return CachedResource<T>(data: emptyData);
  }
}

/// Non-family variant of the cached-resource notifier.
abstract class SimpleCachedResourceNotifier<T>
    extends Notifier<CachedResource<T>>
    with CachedResourceRefreshMixin<T> {
  @override
  String? get cacheScope => null;

  void listenDependencies() {}

  @override
  CachedResource<T> build() {
    wireResourceLifecycle(ref, listenDependencies);
    return CachedResource<T>(data: emptyData);
  }
}
