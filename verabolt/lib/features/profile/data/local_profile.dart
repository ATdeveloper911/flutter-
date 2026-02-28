import 'package:isar/isar.dart';

part 'local_profile.g.dart';

@collection
class LocalProfile {
  LocalProfile();

  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String userId;

  String? email;

  String? displayName;

  String? avatarUrl;

  String? avatarLocalPath;

  bool isDirty = false;

  DateTime? updatedAt;
}
