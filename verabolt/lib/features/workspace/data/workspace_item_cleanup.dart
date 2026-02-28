import 'package:isar/isar.dart';

import 'package:verabolt/services/local_storage.dart';

import 'package:verabolt/features/workspace/data/workspace_item.dart';

/// One‑time migration helper.
/// Call this at app start to clear any cross‑user workspace items
/// that may have been cached before per‑user isolation was added.
Future<void> clearCrossUserWorkspaceData({required String currentUserId}) async {
  final isar = LocalStorage.isar;
  await isar.writeTxn(() async {
    final all = await isar.workspaceItems.where().anyId().findAll();

    for (final item in all) {
      final uid = item.userId.trim();

      if (uid.isEmpty) {
        item.userId = currentUserId;
        await isar.workspaceItems.put(item);
        continue;
      }

      if (uid != currentUserId) {
        await isar.workspaceItems.delete(item.id);
      }
    }
  });
}
