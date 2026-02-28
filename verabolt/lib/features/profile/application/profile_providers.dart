import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'package:verabolt/core/utils/entitlement_cache.dart';
import 'package:verabolt/core/utils/connectivity_provider.dart';
import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/profile/data/local_profile.dart';
import 'package:verabolt/features/profile/data/profile_repository.dart';
import 'package:verabolt/services/local_storage.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository();
});

Future<String?> _downloadAvatarToLocalPath({
  required String userId,
  required String avatarUrl,
}) async {
  final uri = Uri.tryParse(avatarUrl);
  if (uri == null) return null;

  final dir = await getApplicationDocumentsDirectory();
  final avatarsDir = Directory('${dir.path}/avatars');
  if (!await avatarsDir.exists()) {
    await avatarsDir.create(recursive: true);
  }

  final file = File('${avatarsDir.path}/$userId.jpg');

  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final bytes = await consolidateHttpClientResponseBytes(response);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

final localProfileProvider = StreamProvider<LocalProfile?>((ref) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield null;
    return;
  }

  final isar = LocalStorage.isar;
  final userId = user.id;

  final stream = isar.localProfiles.filter().userIdEqualTo(userId).watch(
        fireImmediately: true,
      );

  // Background refresh (does not block initial offline identity).
  Future<void> refresh() async {
    final offline = ref.read(isOfflineProvider);
    if (offline) return;

    final repo = ref.read(profileRepositoryProvider);
    final row = await repo.fetchMyProfile(userId: userId);
    if (row == null) return;

    final displayName = row['full_name']?.toString();
    final avatarUrl = row['avatar_url']?.toString();
    final updatedAt = DateTime.tryParse((row['updated_at'] ?? '').toString());

    String? avatarLocalPath;
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      avatarLocalPath = await _downloadAvatarToLocalPath(
        userId: userId,
        avatarUrl: avatarUrl,
      );
    }

    await isar.writeTxn(() async {
      final existing =
          await isar.localProfiles.filter().userIdEqualTo(userId).findFirst();
      final lp = existing ?? LocalProfile()..userId = userId;
      if (lp.isDirty) {
        lp
          ..email = user.email
          ..updatedAt = DateTime.now().toUtc();
        await isar.localProfiles.put(lp);
        return;
      }

      lp
        ..email = user.email
        ..displayName = displayName
        ..avatarUrl = avatarUrl
        ..avatarLocalPath = avatarLocalPath ?? lp.avatarLocalPath
        ..updatedAt = updatedAt ?? DateTime.now().toUtc();
      await isar.localProfiles.put(lp);
    });
  }

  // Fire and forget.
  unawaited(refresh());

  await for (final list in stream) {
    yield list.isNotEmpty ? list.first : null;
  }
});

final profileStatusProvider = FutureProvider<String>((ref) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) return 'new';

  final repo = ref.watch(profileRepositoryProvider);
  try {
    final status = await repo.fetchMyStatus(userId: user.id);
    await EntitlementCache.writeProfileStatus(status, userId: user.id);
    return status;
  } catch (_) {
    final cached = await EntitlementCache.readProfileStatus(userId: user.id);
    if (cached != null) return cached;
    rethrow;
  }
});
