import 'package:isar/isar.dart';

part 'workspace_item.g.dart';

@collection
class WorkspaceItem {
  WorkspaceItem();

  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String remoteId;

  @Index()
  late String userId;

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

  @Name('is_synced')
  bool isSynced = false;
}
