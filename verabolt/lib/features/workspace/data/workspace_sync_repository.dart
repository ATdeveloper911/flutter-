import 'package:verabolt/services/supabase_service.dart';

import 'package:verabolt/features/workspace/data/workspace_item.dart';

class WorkspaceSyncRepository {
  Future<List<Map<String, dynamic>>> fetchServerItems({required String userId}) async {
    final rows = await SupabaseService.client
        .from('workspace_items')
        .select('remote_id,title,description,category,last_modified,file_url,file_type,file_name,file_size')
        .eq('user_id', userId)
        .order('last_modified', ascending: false);

    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> upsertUnsyncedItems({
    required String userId,
    required List<WorkspaceItem> items,
  }) async {
    if (items.isEmpty) return;

    final payload = items
        .map(
          (item) => {
            'user_id': userId,
            'remote_id': item.remoteId,
            'title': item.title,
            'description': item.description,
            'category': item.category,
            'last_modified': item.lastModified.toUtc().toIso8601String(),
            'file_url': item.fileUrl,
            'file_type': item.fileType,
            'file_name': item.fileName,
            'file_size': item.fileSize,
          },
        )
        .toList();

    await SupabaseService.client.from('workspace_items').upsert(
          payload,
          onConflict: 'user_id,remote_id',
        );
  }

  Future<void> deleteServerItem({
    required String userId,
    required String remoteId,
  }) async {
    await SupabaseService.client
        .from('workspace_items')
        .delete()
        .eq('user_id', userId)
        .eq('remote_id', remoteId);
  }
}
