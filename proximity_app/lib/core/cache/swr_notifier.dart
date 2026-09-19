import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'local_cache.dart';

/// Sprint 15's stale-while-revalidate shape (Sprint planning/Sprint 15.md):
/// "show the cached result instantly, refresh in the background, swap in
/// place if it changed." `StateNotifier<AsyncValue<T>>` rather than
/// Riverpod 3's native `AsyncNotifier` -- this codebase's own hand-written
/// notifiers (auth_provider.dart's `AuthNotifier`, this file's only
/// precedent for "notifier that isn't a plain FutureProvider") already
/// standardized on `StateNotifier`/`legacy.dart` for the documented reason
/// that file's header gives (no riverpod_generator in this project), so this
/// follows the same convention rather than introducing a second one.
///
/// Sequence on construction:
/// 1. A warm, still-within-[ttl] cache entry (if any) is decoded and emitted
///    immediately as `AsyncData` -- no loading state, per the exit
///    criteria's "renders instantly with no loading spinner."
/// 2. The real network [fetch] always runs regardless (even after a cache
///    hit) -- on success its result replaces the state and is written back
///    to the cache; on failure, a cache hit's already-shown data is left in
///    place (a background revalidation failing shouldn't blank out a
///    perfectly fine cached screen) and only surfaces as `AsyncError` when
///    there was nothing cached to fall back to.
/// A cold cache (nothing cached, or past its TTL) skips step 1 entirely, so
/// this behaves exactly like a plain `FutureProvider` -- `AsyncLoading` then
/// `AsyncData`/`AsyncError` -- matching Sprint 15.md's "a cold cache behaves
/// exactly as it does today."
class SwrNotifier<T> extends StateNotifier<AsyncValue<T>> {
  SwrNotifier({
    required LocalCache cache,
    required String cacheKey,
    required Duration ttl,
    required Future<T> Function() fetch,
    required Object? Function(T value) encode,
    required T Function(dynamic json) decode,
  })  : _cache = cache,
        _cacheKey = cacheKey,
        _ttl = ttl,
        _fetch = fetch,
        _encode = encode,
        _decode = decode,
        super(const AsyncValue.loading()) {
    _load();
  }

  final LocalCache _cache;
  final String _cacheKey;
  final Duration _ttl;
  final Future<T> Function() _fetch;
  final Object? Function(T value) _encode;
  final T Function(dynamic json) _decode;

  Future<void> _load() async {
    final cached = await _cache.read<T>(_cacheKey, _ttl, _decode);
    if (!mounted) return;
    final hadCachedValue = cached != null;
    if (hadCachedValue) state = AsyncValue.data(cached);

    try {
      final fresh = await _fetch();
      await _cache.write(_cacheKey, _encode(fresh));
      if (!mounted) return;
      state = AsyncValue.data(fresh);
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (!hadCachedValue) state = AsyncValue.error(error, stackTrace);
    }
  }
}

/// A provider built on [SwrNotifier] whose cache key or query depends on
/// another async provider (e.g. `buyerLocationProvider`) needs somewhere to
/// sit while that upstream value is still resolving -- it can't build a real
/// [SwrNotifier] yet (there's no cache key to use), but it also can't just
/// treat "not resolved yet" as "resolved to null," since that would flash
/// whatever empty state a real null resolves to. This holds a fixed
/// [AsyncValue] (`AsyncValue.loading()`, always) until the caller's own
/// `ref.watch` on the upstream provider triggers a rebuild into the real
/// [SwrNotifier] once it resolves.
class StaticAsyncNotifier<T> extends StateNotifier<AsyncValue<T>> {
  StaticAsyncNotifier(super.state);
}
