import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:verabolt/services/supabase_service.dart';

class ProfileRepository {
  SupabaseClient get _client => SupabaseService.client;

  Future<Map<String, dynamic>?> fetchMyProfile({required String userId}) async {
    final row = await _client
        .from('profiles')
        .select('id,status,device_id,updated_at,full_name,avatar_url')
        .eq('id', userId)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<void> updateMyProfile({
    required String userId,
    String? displayName,
    String? avatarUrl,
  }) async {
    final payload = <String, dynamic>{};
    if (displayName != null) payload['full_name'] = displayName;
    if (avatarUrl != null) payload['avatar_url'] = avatarUrl;
    if (payload.isEmpty) return;

    await _client.from('profiles').update(payload).eq('id', userId);
  }

  Future<String> fetchMyStatus({required String userId}) async {
    final row = await _client
        .from('profiles')
        .select('status')
        .eq('id', userId)
        .maybeSingle();

    return (row?['status']?.toString() ?? 'new');
  }

  Future<void> requestAccess({required String userId, required String deviceId}) async {
    await _client.rpc(
      'request_access',
      params: {'p_device_id': deviceId},
    );
  }
}
