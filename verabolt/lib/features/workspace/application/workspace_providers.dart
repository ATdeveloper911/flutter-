import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/licensing/application/pro_status_provider.dart';
import 'package:verabolt/features/profile/application/profile_providers.dart';
import 'package:verabolt/features/workspace/data/isar_service.dart';
import 'package:verabolt/features/workspace/data/workspace_item.dart';
import 'package:verabolt/features/workspace/data/workspace_item_backup.dart';
import 'package:verabolt/services/local_storage.dart';

final isarServiceProvider = Provider<IsarService>((ref) {
  final service = IsarService(LocalStorage.isar);
  service.registerProAccessChecker(() async {
    final status = await ref.read(profileStatusProvider.future);
    final isPro = await ref.read(isProProvider.future);
    return status == 'active' && isPro;
  });
  return service;
});

final workspaceItemsProvider = StreamProvider<List<WorkspaceItem>>((ref) {
  final service = ref.watch(isarServiceProvider);
  final userAsync = ref.watch(authUserProvider);
  return userAsync.when(
    data: (user) => user != null ? service.watchItems(userId: user.id) : Stream.value([]),
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

final workspaceBackupsProvider = StreamProvider<List<WorkspaceItemBackup>>((ref) {
  final service = ref.watch(isarServiceProvider);
  final userAsync = ref.watch(authUserProvider);
  return userAsync.when(
    data: (user) => user != null ? service.watchBackups(userId: user.id) : Stream.value([]),
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

final workspaceUnsyncedCountProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(isarServiceProvider);
  final items = await service.getUnsyncedItems();
  return items.length;
});

final workspaceSearchQueryProvider = StateProvider<String>((ref) => '');

final workspaceCategoryFilterProvider = StateProvider<String?>((ref) => null);

final filteredWorkspaceItemsProvider = Provider<AsyncValue<List<WorkspaceItem>>>((ref) {
  final raw = ref.watch(workspaceItemsProvider);
  final query = ref.watch(workspaceSearchQueryProvider).trim().toLowerCase();
  final category = ref.watch(workspaceCategoryFilterProvider);

  return raw.whenData((items) {
    var filtered = items;
    if (query.isNotEmpty) {
      filtered = filtered
          .where((i) =>
              i.title.toLowerCase().contains(query) ||
              i.description.toLowerCase().contains(query))
          .toList();
    }
    if (category != null) {
      filtered = filtered.where((i) => i.category == category).toList();
    }
    return filtered;
  });
});
