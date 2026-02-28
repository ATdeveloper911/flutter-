import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import 'package:verabolt/core/utils/connectivity_provider.dart';
import 'package:verabolt/core/utils/device_id.dart';
import 'package:verabolt/core/utils/friendly_error.dart';
import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/licensing/application/pro_status_provider.dart';
import 'package:verabolt/features/profile/application/profile_providers.dart';
import 'package:verabolt/features/profile/data/local_profile.dart';
import 'package:verabolt/features/workspace/application/workspace_providers.dart';
import 'package:verabolt/features/workspace/data/workspace_sync_repository.dart';
import 'package:verabolt/services/workspace_vault_service.dart';
import 'package:verabolt/services/local_storage.dart';
import 'package:verabolt/services/supabase_service.dart';

class SyncStatusState {
  const SyncStatusState({
    this.lastSyncedAt,
    this.isSyncing = false,
    this.error,
  });

  final DateTime? lastSyncedAt;
  final bool isSyncing;
  final String? error;

  SyncStatusState copyWith({
    DateTime? lastSyncedAt,
    bool? isSyncing,
    String? error,
    bool clearError = false,
  }) {
    return SyncStatusState(
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isSyncing: isSyncing ?? this.isSyncing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

Future<void> _syncPendingWorkspaceAttachments(Ref ref, {required String userId}) async {
  final offline = ref.read(isOfflineProvider);
  if (offline) return;

  final isarService = ref.read(isarServiceProvider);
  final items = await isarService.getAllItems(userId: userId);

  for (final item in items) {
    final hasRemote = item.fileUrl != null && item.fileUrl!.trim().isNotEmpty;
    if (hasRemote) continue;

    final localPath = item.localFilePath;
    if (localPath == null || localPath.trim().isEmpty) continue;

    final f = File(localPath);
    if (!await f.exists()) continue;

    final upload = await WorkspaceVaultService().uploadAttachment(
      userId: userId,
      remoteId: item.remoteId,
      file: f,
      fileName: item.fileName,
      fileType: item.fileType,
    );

    await isarService.updateAttachment(
      remoteId: item.remoteId,
      fileUrl: upload.objectPath,
      fileType: upload.fileType,
      fileName: upload.fileName,
      fileSize: upload.fileSize,
      localFilePath: upload.localFilePath,
    );
  }
}

class SyncStatusNotifier extends StateNotifier<SyncStatusState> {
  SyncStatusNotifier() : super(const SyncStatusState());

  void setSyncing(bool value) {
    state = state.copyWith(isSyncing: value);
  }

  void markSyncedNow() {
    state = state.copyWith(
      lastSyncedAt: DateTime.now(),
      clearError: true,
    );
  }

  void setError(String message) {
    state = state.copyWith(error: message);
  }

  void reset() {
    state = const SyncStatusState();
  }
}

final workspaceSyncRepositoryProvider = Provider<WorkspaceSyncRepository>((ref) {
  return WorkspaceSyncRepository();
});

final syncStatusProvider = StateNotifierProvider<SyncStatusNotifier, SyncStatusState>((ref) {
  return SyncStatusNotifier();
});

final syncStatusLabelProvider = Provider<String>((ref) {
  final state = ref.watch(syncStatusProvider);
  if (state.isSyncing) return 'Syncing now...';
  final at = state.lastSyncedAt;
  if (at == null) return 'Last synced: never';

  final diff = DateTime.now().difference(at);
  if (diff.inSeconds < 45) return 'Last synced: just now';
  if (diff.inMinutes < 60) return 'Last synced: ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'Last synced: ${diff.inHours}h ago';
  return 'Last synced: ${diff.inDays}d ago';
});

Future<String?> _compressAvatarForUpload({required String inputPath}) async {
  final dir = await getTemporaryDirectory();
  final target = '${dir.path}/vb_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final out = await FlutterImageCompress.compressAndGetFile(
    inputPath,
    target,
    quality: 85,
    minWidth: 500,
    minHeight: 500,
    format: CompressFormat.jpeg,
  );
  return out?.path;
}

Future<void> _syncDirtyLocalProfile(Ref ref, {required String userId}) async {
  final offline = ref.read(isOfflineProvider);
  if (offline) return;

  final isar = LocalStorage.isar;
  final existing = await isar.localProfiles.getByUserId(userId);
  if (existing == null || !existing.isDirty) return;

  final displayName = existing.displayName?.trim();
  final avatarLocalPath = existing.avatarLocalPath?.trim();

  String? avatarUrl;
  if (avatarLocalPath != null && avatarLocalPath.isNotEmpty) {
    final file = File(avatarLocalPath);
    if (await file.exists()) {
      final compressed = await _compressAvatarForUpload(inputPath: avatarLocalPath);
      final bytes = await File(compressed ?? avatarLocalPath).readAsBytes();
      final path = '$userId/avatar.jpg';
      await SupabaseService.client.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      avatarUrl = SupabaseService.client.storage.from('avatars').getPublicUrl(path);
    }
  }

  await ref.read(profileRepositoryProvider).updateMyProfile(
        userId: userId,
        displayName: (displayName != null && displayName.isNotEmpty) ? displayName : null,
        avatarUrl: avatarUrl,
      );

  await isar.writeTxn(() async {
    final lp = await isar.localProfiles.getByUserId(userId);
    if (lp == null) return;
    lp
      ..isDirty = false
      ..avatarUrl = avatarUrl ?? lp.avatarUrl
      ..updatedAt = DateTime.now().toUtc();
    await isar.localProfiles.put(lp);
  });
}

Future<void> _syncNow(Ref ref, {required bool disposed}) async {
  final user = await ref.read(authUserProvider.future);
  if (user == null || disposed) return;
  await _syncDirtyLocalProfile(ref, userId: user.id);
  await _syncPendingWorkspaceAttachments(ref, userId: user.id);

  final status = await ref.read(profileStatusProvider.future);
  final isPro = await ref.read(isProProvider.future);

  if (disposed) return;
  if (status != 'active' || !isPro) {
    ref.read(syncStatusProvider.notifier).reset();
    return;
  }

  final notifier = ref.read(syncStatusProvider.notifier);
  notifier.setSyncing(true);

  try {
    final isarService = ref.read(isarServiceProvider);
    final syncRepo = ref.read(workspaceSyncRepositoryProvider);

    final unsynced = await isarService.getUnsyncedItems();
    if (unsynced.isNotEmpty) {
      await syncRepo.upsertUnsyncedItems(userId: user.id, items: unsynced);
      await isarService.markSyncedByRemoteIds(userId: user.id, remoteIds: unsynced.map((e) => e.remoteId));
    }

    final serverItems = await syncRepo.fetchServerItems(userId: user.id);
    await isarService.applyServerWins(serverItems, userId: user.id);
    notifier.markSyncedNow();

    try {
      final deviceId = await DeviceId.get();
      await SupabaseService.client.from('sync_events').insert({
            'user_id': user.id,
            'device_id': deviceId,
            'operation_count': 1,
          });
    } catch (_) {}
  } catch (e) {
    final msg = friendlyError(e);
    notifier.setError(msg);
  } finally {
    notifier.setSyncing(false);
  }
}

final syncNowProvider = Provider<Future<void> Function()>((ref) {
  return () => _syncNow(ref, disposed: false);
});

final syncEngineProvider = Provider<void>((ref) {
  bool disposed = false;
  Timer? timer;

  void startTimerIfNeeded(Future<void> Function() syncNow) {
    if (timer != null) return;
    timer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(syncNow()));
  }

  void stopTimer() {
    timer?.cancel();
    timer = null;
  }

  Future<void> syncNow() async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || disposed) return;
    await _syncDirtyLocalProfile(ref, userId: user.id);

    final status = await ref.read(profileStatusProvider.future);
    final isPro = await ref.read(isProProvider.future);

    if (disposed) return;
    if (status != 'active' || !isPro) {
      stopTimer();
      ref.read(syncStatusProvider.notifier).reset();
      return;
    }

    startTimerIfNeeded(syncNow);
    await _syncNow(ref, disposed: disposed);
  }

  unawaited(syncNow());
  ref.listen(connectivityProvider, (_, next) {
    next.whenData((value) {
      if (value == ConnectivityResult.none) return;
      unawaited(syncNow());
    });
  });

  ref.listen<AsyncValue<String>>(profileStatusProvider, (_, next) {
    next.whenData((status) {
      if (status == 'active') {
        startTimerIfNeeded(syncNow);
        unawaited(syncNow());
      } else {
        stopTimer();
        ref.read(syncStatusProvider.notifier).reset();
      }
    });
  });

  ref.onDispose(() {
    disposed = true;
    stopTimer();
  });
});
