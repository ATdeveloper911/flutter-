import 'package:isar/isar.dart';

part 'workspace_item_backup.g.dart';

@collection
class WorkspaceItemBackup {
  WorkspaceItemBackup();

  Id id = Isar.autoIncrement;

  @Index()
  late String userId;

  @Index()
  late String remoteId;

  late String title;

  @Name('description')
  String description = '';

  @Name('category')
  String category = 'general';

  @Name('last_modified')
  late DateTime lastModified;

  @Name('file_url')
  String? fileUrl;

  @Name('file_type')
  String? fileType;

  @Name('file_name')
  String? fileName;

  @Name('file_size')
  int? fileSize;

  @Name('local_file_path')
  String? localFilePath;

  @Name('deleted_at')
  late DateTime deletedAt;
}
