import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'package:verabolt/features/profile/data/local_profile.dart';
import 'package:verabolt/features/workspace/data/workspace_item.dart';
import 'package:verabolt/features/workspace/data/workspace_item_backup.dart';

class LocalStorage {
  static Isar? _isar;

  static Isar get isar {
    final db = _isar;
    if (db == null) {
      throw StateError('LocalStorage.init() must be called before using Isar.');
    }
    return db;
  }

  static Future<void> init() async {
    if (_isar != null) return;

    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [WorkspaceItemSchema, WorkspaceItemBackupSchema, LocalProfileSchema],
      directory: dir.path,
      inspector: false,
      name: 'verabolt_workspace',
    );
  }
}
