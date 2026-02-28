import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:verabolt/core/utils/entitlement_cache.dart';
import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/licensing/data/licensing_repository.dart';

final licensingRepositoryProvider = Provider<LicensingRepository>((ref) {
  return LicensingRepository();
});

final isProProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) return false;

  final repo = ref.watch(licensingRepositoryProvider);
  try {
    final value = await repo.fetchIsPro(userId: user.id);
    await EntitlementCache.writeIsPro(value, userId: user.id);
    return value;
  } catch (_) {
    final cached = await EntitlementCache.readIsPro(userId: user.id);
    if (cached != null) return cached;
    rethrow;
  }
});
