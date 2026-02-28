import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:verabolt/core/utils/entitlement_cache.dart';
import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/licensing/application/pro_status_provider.dart';
import 'package:verabolt/features/licensing/data/licensing_repository.dart';

final licenseInfoProvider = FutureProvider<LicenseInfo?>((ref) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) return null;

  final repo = ref.watch(licensingRepositoryProvider);

  LicenseInfo? normalize(LicenseInfo? lic) {
    if (lic == null) return null;
    final exp = lic.expiresAt;
    if (exp == null) return lic;
    final expired = !exp.toUtc().isAfter(DateTime.now().toUtc());
    if (!expired) return lic;
    if (lic.status.trim().toLowerCase() == 'expired') return lic;
    return LicenseInfo(
      keyString: lic.keyString,
      status: 'expired',
      expiresAt: lic.expiresAt,
      durationDays: lic.durationDays,
    );
  }

  try {
    final lic = normalize(await repo.fetchMyLicense(userId: user.id));
    await EntitlementCache.writeLicenseInfo(lic, userId: user.id);
    return lic;
  } catch (_) {
    final cached = normalize(await EntitlementCache.readLicenseInfo(userId: user.id));
    if (cached != null) return cached;
    rethrow;
  }
});
