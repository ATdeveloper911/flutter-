import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:verabolt/core/constants/env_keys.dart';
import 'package:verabolt/services/supabase_service.dart';

class LicenseVerificationResult {
  const LicenseVerificationResult({
    required this.status,
    required this.isPro,
    required this.expiresAt,
  });

  final String status;
  final bool isPro;
  final DateTime? expiresAt;

  factory LicenseVerificationResult.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['expires_at'];
    return LicenseVerificationResult(
      status: (json['status'] ?? '').toString(),
      isPro: (json['is_pro'] as bool?) ?? false,
      expiresAt: expiresRaw is String && expiresRaw.isNotEmpty
          ? DateTime.tryParse(expiresRaw)
          : null,
    );
  }
}

class LicenseInfo {
  const LicenseInfo({
    required this.keyString,
    required this.status,
    required this.expiresAt,
    required this.durationDays,
  });

  final String keyString;
  final String status;
  final DateTime? expiresAt;
  final int durationDays;

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['expires_at'];
    final durationRaw = json['duration_days'];
    final duration = durationRaw is int
        ? durationRaw
        : int.tryParse(durationRaw?.toString() ?? '') ?? 0;
    return LicenseInfo(
      keyString: (json['key_string'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      expiresAt: expiresRaw is String && expiresRaw.isNotEmpty
          ? DateTime.tryParse(expiresRaw)
          : null,
      durationDays: duration,
    );
  }
}

class LicensingRepository {
  SupabaseClient get _client => SupabaseService.client;

  String? _tryGetJwtIssuer(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final obj = jsonDecode(decoded);
      if (obj is Map && obj['iss'] is String) {
        return (obj['iss'] as String).trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Session> _ensureValidSession() async {
    var session = _client.auth.currentSession;
    if (session == null) {
      throw const AuthException('Not authenticated');
    }

    final expiresAt = session.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final shouldRefresh = expiresAt == null || (expiresAt - now) < 60;
    if (shouldRefresh) {
      await _client.auth.refreshSession();
      session = _client.auth.currentSession;
      if (session == null) {
        throw const AuthException('Not authenticated');
      }
    }

    final token = session.accessToken;
    if (token.isEmpty) {
      throw const AuthException('Not authenticated');
    }

    final supabaseUrl = dotenv.env[EnvKeys.supabaseUrl];
    if (supabaseUrl != null && supabaseUrl.isNotEmpty) {
      final iss = _tryGetJwtIssuer(token);
      if (iss != null && iss.isNotEmpty && !iss.startsWith(supabaseUrl)) {
        throw Exception(
          'Supabase project mismatch. Token issuer ($iss) does not match SUPABASE_URL ($supabaseUrl).',
        );
      }
    }

    return session;
  }

  Future<Map<String, String>> _authHeaders() async {
    final anonKey = dotenv.env[EnvKeys.supabaseAnonKey];
    if (anonKey == null || anonKey.isEmpty) {
      throw Exception('Missing ${EnvKeys.supabaseAnonKey} in .env');
    }

    final session = await _ensureValidSession();
    final token = session.accessToken;

    return {
      'Authorization': 'Bearer $token',
      'apikey': anonKey,
    };
  }

  Future<LicenseVerificationResult> verifyLicense({
    required String keyString,
    required String deviceId,
  }) async {
    final response = await _client.functions.invoke(
      'verify-license',
      body: {
        'key_string': keyString,
        'device_id': deviceId,
      },
      headers: await _authHeaders(),
    );

    final data = response.data;

    if (response.status != 200) {
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      throw Exception('verify-license failed (status ${response.status})');
    }

    if (data is Map<String, dynamic>) {
      return LicenseVerificationResult.fromJson(data);
    }

    if (data is Map) {
      return LicenseVerificationResult.fromJson(Map<String, dynamic>.from(data));
    }

    throw const FormatException('Unexpected verify-license response');
  }

  Future<bool> fetchIsPro({required String userId}) async {
    await _ensureValidSession();
    final lic = await fetchMyLicense(userId: userId);
    if (lic == null) return false;

    final status = lic.status.trim().toLowerCase();
    if (status != 'active') return false;

    final expiresAt = lic.expiresAt;
    if (expiresAt == null) return true;
    return expiresAt.toUtc().isAfter(DateTime.now().toUtc());
  }

  Future<LicenseInfo?> fetchMyLicense({required String userId}) async {
    await _ensureValidSession();
    final row = await _client
        .from('license_keys')
        .select('id,key_string,status,expires_at,duration_days')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;

    final json = Map<String, dynamic>.from(row);
    final info = LicenseInfo.fromJson(json);

    final status = info.status.trim().toLowerCase();
    final exp = info.expiresAt;
    final isExpired = exp != null && !exp.toUtc().isAfter(DateTime.now().toUtc());
    if (isExpired && status != 'expired') {
      try {
        final id = json['id'];
        if (id != null) {
          await _client
              .from('license_keys')
              .update({'status': 'expired'})
              .eq('id', id)
              .eq('user_id', userId);
        }
      } catch (_) {}
    }

    return info;
  }
}
