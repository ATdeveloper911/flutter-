import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import 'package:verabolt/features/workspace/data/workspace_item.dart';
import 'package:verabolt/features/workspace/data/workspace_item_backup.dart';

typedef ProAccessChecker = Future<bool> Function();

class IsarService {
  IsarService(this._isar);

  final Isar _isar;
  final Uuid _uuid = const Uuid();

  ProAccessChecker? _proAccessChecker;

  void registerProAccessChecker(ProAccessChecker checker) {
    _proAccessChecker = checker;
  }

  Future<void> updateAttachment({
    required String remoteId,
    required String? fileUrl,
    required String? fileType,
    required String? fileName,
    required int? fileSize,
    required String? localFilePath,
  }) async {
    await _ensureProAccess();

    final item = await _isar.workspaceItems.filter().remoteIdEqualTo(remoteId).findFirst();
    if (item == null) return;

    item
      ..fileUrl = fileUrl
      ..fileType = fileType
      ..fileName = fileName
      ..fileSize = fileSize
      ..localFilePath = localFilePath
      ..lastModified = DateTime.now().toUtc()
      ..isSynced = false;

    await _isar.writeTxn(() async {
      await _isar.workspaceItems.put(item);
    });
  }

  Future<void> setLocalFilePath({
    required String remoteId,
    required String? localFilePath,
  }) async {
    final item = await _isar.workspaceItems.filter().remoteIdEqualTo(remoteId).findFirst();
    if (item == null) return;

    item.localFilePath = localFilePath;

    await _isar.writeTxn(() async {
      await _isar.workspaceItems.put(item);
    });
  }

  Future<void> _ensureProAccess() async {
    final checker = _proAccessChecker;
    if (checker == null) return;
    final allowed = await checker();
    if (!allowed) {
      throw StateError('Pro access required. Activate your license to continue.');
    }
  }

  Stream<List<WorkspaceItem>> watchItems({required String userId}) {
    return _isar.workspaceItems
        .filter()
        .userIdEqualTo(userId)
        .sortByLastModifiedDesc()
        .watch(fireImmediately: true);
  }

  Future<List<WorkspaceItem>> getAllItems({required String userId}) {
    return _isar.workspaceItems
        .filter()
        .userIdEqualTo(userId)
        .sortByLastModifiedDesc()
        .findAll();
  }

  Future<List<WorkspaceItem>> getUnsyncedItems() {
    return _isar.workspaceItems.filter().isSyncedEqualTo(false).findAll();
  }

  Future<WorkspaceItem> createItem({
    required String userId,
    required String title,
    required String description,
    required String category,
    String? fileUrl,
    String? fileType,
    String? fileName,
    int? fileSize,
    String? localFilePath,
  }) async {
    await _ensureProAccess();

    final item = WorkspaceItem()
      ..userId = userId
      ..remoteId = _uuid.v4()
      ..title = title
      ..description = description
      ..category = category
      ..lastModified = DateTime.now().toUtc()
      ..fileUrl = fileUrl
      ..fileType = fileType
      ..fileName = fileName
      ..fileSize = fileSize
      ..localFilePath = localFilePath
      ..isSynced = false;

    await _isar.writeTxn(() async {
      await _isar.workspaceItems.put(item);
    });
    return item;
  }

  Future<void> updateItem({
    required String remoteId,
    required String title,
    required String description,
    required String category,
    String? fileUrl,
    String? fileType,
    String? fileName,
    int? fileSize,
    String? localFilePath,
  }) async {
    await _ensureProAccess();

    final item = await _isar.workspaceItems.filter().remoteIdEqualTo(remoteId).findFirst();
    if (item == null) return;

    item
      ..title = title
      ..description = description
      ..category = category
      ..fileUrl = fileUrl ?? item.fileUrl
      ..fileType = fileType ?? item.fileType
      ..fileName = fileName ?? item.fileName
      ..fileSize = fileSize ?? item.fileSize
      ..localFilePath = localFilePath ?? item.localFilePath
      ..lastModified = DateTime.now().toUtc()
      ..isSynced = false;

    await _isar.writeTxn(() async {
      await _isar.workspaceItems.put(item);
    });
  }

  Future<void> deleteItem({required String userId, required String remoteId}) async {
    await _ensureProAccess();
    await _isar.writeTxn(() async {
      final item = await _isar.workspaceItems
          .filter()
          .userIdEqualTo(userId)
          .remoteIdEqualTo(remoteId)
          .findFirst();

      if (item == null) {
        throw Exception('Item not found or already deleted');
      }

      final backup = WorkspaceItemBackup()
        ..userId = userId
        ..remoteId = item.remoteId
        ..title = item.title
        ..description = item.description
        ..category = item.category
        ..lastModified = item.lastModified
        ..fileUrl = item.fileUrl
        ..fileType = item.fileType
        ..fileName = item.fileName
        ..fileSize = item.fileSize
        ..localFilePath = item.localFilePath
        ..deletedAt = DateTime.now().toUtc();

      await _isar.workspaceItemBackups.put(backup);

      final success = await _isar.workspaceItems
          .filter()
          .userIdEqualTo(userId)
          .remoteIdEqualTo(remoteId)
          .deleteFirst();
      if (!success) {
        throw Exception('Item not found or already deleted');
      }
    });
  }

  Stream<List<WorkspaceItemBackup>> watchBackups({required String userId}) {
    return _isar.workspaceItemBackups
        .filter()
        .userIdEqualTo(userId)
        .sortByDeletedAtDesc()
        .watch(fireImmediately: true);
  }

  Future<List<WorkspaceItemBackup>> getBackups({required String userId}) {
    return _isar.workspaceItemBackups
        .filter()
        .userIdEqualTo(userId)
        .sortByDeletedAtDesc()
        .findAll();
  }

  Future<void> restoreBackup({required String userId, required int backupId}) async {
    await _ensureProAccess();
    await _isar.writeTxn(() async {
      final backup = await _isar.workspaceItemBackups.get(backupId);
      if (backup == null) return;
      if (backup.userId != userId) return;

      final existing = await _isar.workspaceItems
          .filter()
          .userIdEqualTo(userId)
          .remoteIdEqualTo(backup.remoteId)
          .findFirst();

      final item = existing ?? WorkspaceItem();
      item
        ..userId = userId
        ..remoteId = backup.remoteId
        ..title = backup.title
        ..description = backup.description
        ..category = backup.category
        ..lastModified = DateTime.now().toUtc()
        ..fileUrl = backup.fileUrl
        ..fileType = backup.fileType
        ..fileName = backup.fileName
        ..fileSize = backup.fileSize
        ..localFilePath = backup.localFilePath
        ..isSynced = false;

      await _isar.workspaceItems.put(item);
      await _isar.workspaceItemBackups.delete(backupId);
    });
  }

  Future<void> restoreAllBackups({required String userId}) async {
    await _ensureProAccess();
    await _isar.writeTxn(() async {
      final backups = await _isar.workspaceItemBackups
          .filter()
          .userIdEqualTo(userId)
          .sortByDeletedAtDesc()
          .findAll();

      for (final backup in backups) {
        final existing = await _isar.workspaceItems
            .filter()
            .userIdEqualTo(userId)
            .remoteIdEqualTo(backup.remoteId)
            .findFirst();

        final item = existing ?? WorkspaceItem();
        item
          ..userId = userId
          ..remoteId = backup.remoteId
          ..title = backup.title
          ..description = backup.description
          ..category = backup.category
          ..lastModified = DateTime.now().toUtc()
          ..fileUrl = backup.fileUrl
          ..fileType = backup.fileType
          ..fileName = backup.fileName
          ..fileSize = backup.fileSize
          ..localFilePath = backup.localFilePath
          ..isSynced = false;

        await _isar.workspaceItems.put(item);
        await _isar.workspaceItemBackups.delete(backup.id);
      }
    });
  }

  Future<void> clearBackups({required String userId}) async {
    await _ensureProAccess();
    await _isar.writeTxn(() async {
      await _isar.workspaceItemBackups.filter().userIdEqualTo(userId).deleteAll();
    });
  }

  Future<void> markSyncedByRemoteIds({required String userId, required Iterable<String> remoteIds}) async {
    if (remoteIds.isEmpty) return;
    final ids = remoteIds.toSet();
    await _isar.writeTxn(() async {
      for (final remoteId in ids) {
        final item = await _isar.workspaceItems.filter().userIdEqualTo(userId).remoteIdEqualTo(remoteId).findFirst();
        if (item == null) continue;
        item.isSynced = true;
        await _isar.workspaceItems.put(item);
      }
    });
  }

  Future<void> applyServerWins(List<Map<String, dynamic>> serverItems, {required String userId}) async {
    await _ensureProAccess();

    final normalized = _normalizeServerRows(serverItems);

    await _isar.writeTxn(() async {
      for (final row in normalized) {
        final remoteId = row.remoteId;
        if (remoteId.isEmpty) continue;

        final existing = await _isar.workspaceItems
            .filter()
            .userIdEqualTo(userId)
            .remoteIdEqualTo(remoteId)
            .findFirst();
        final item = existing ?? WorkspaceItem()
          ..userId = userId
          ..remoteId = remoteId
          ..title = row.title
          ..description = row.description
          ..category = row.category
          ..fileUrl = row.fileUrl
          ..fileType = row.fileType
          ..fileName = row.fileName
          ..fileSize = row.fileSize
          ..lastModified = row.lastModified
          ..isSynced = true;

        await _isar.workspaceItems.put(item);
      }
    });
  }
}

List<_ServerWorkspaceRow> _normalizeServerRows(List<Map<String, dynamic>> rows) {
  return rows
      .map((row) {
        final remoteId = (row['remote_id'] ?? '').toString();
        if (remoteId.isEmpty) return null;

        final parsed = DateTime.tryParse((row['last_modified'] ?? '').toString())?.toUtc();
        return _ServerWorkspaceRow(
          remoteId: remoteId,
          title: (row['title'] ?? '').toString(),
          description: (row['description'] ?? '').toString(),
          category: (row['category'] ?? 'general').toString(),
          lastModified: parsed ?? DateTime.now().toUtc(),
          fileUrl: row['file_url']?.toString(),
          fileType: row['file_type']?.toString(),
          fileName: row['file_name']?.toString(),
          fileSize: (row['file_size'] is int)
              ? row['file_size'] as int
              : int.tryParse((row['file_size'] ?? '').toString()),
        );
      })
      .whereType<_ServerWorkspaceRow>()
      .toList(growable: false);
}

class _ServerWorkspaceRow {
  const _ServerWorkspaceRow({
    required this.remoteId,
    required this.title,
    required this.description,
    required this.category,
    required this.lastModified,
    required this.fileUrl,
    required this.fileType,
    required this.fileName,
    required this.fileSize,
  });

  final String remoteId;
  final String title;
  final String description;
  final String category;
  final DateTime lastModified;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? fileSize;
}
