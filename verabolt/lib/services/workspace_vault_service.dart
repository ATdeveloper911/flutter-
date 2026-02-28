import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:verabolt/features/workspace/data/isar_service.dart';
import 'package:verabolt/features/workspace/data/workspace_item.dart';
import 'package:verabolt/services/supabase_service.dart';

class WorkspaceVaultUploadResult {
  const WorkspaceVaultUploadResult({
    required this.objectPath,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.localFilePath,
  });

  final String objectPath;
  final String fileName;
  final String fileType;
  final int fileSize;
  final String localFilePath;
}

class WorkspaceVaultCacheResult {
  const WorkspaceVaultCacheResult({
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.localFilePath,
  });

  final String fileName;
  final String fileType;
  final int fileSize;
  final String localFilePath;
}

class WorkspaceVaultService {
  static const String bucketId = 'workspace_files';

  Future<WorkspaceVaultCacheResult> cacheAttachmentForOffline({
    required String remoteId,
    required File file,
    String? fileName,
    String? fileType,
  }) async {
    final originalPath = file.path;
    final originalName = (fileName != null && fileName.trim().isNotEmpty)
        ? fileName.trim()
        : _basename(originalPath);

    final inferredType = (fileType != null && fileType.trim().isNotEmpty)
        ? fileType.trim()
        : (lookupMimeType(originalPath) ?? 'application/octet-stream');

    final processed = await _maybeCompressImage(
      input: file,
      mimeType: inferredType,
    );

    final bytes = await processed.readAsBytes();
    final size = bytes.length;

    final safeName = _safeName(originalName);

    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/workspace_files');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final cachedPath = '${outDir.path}/${remoteId}_$safeName';
    await File(cachedPath).writeAsBytes(bytes, flush: true);

    return WorkspaceVaultCacheResult(
      fileName: originalName,
      fileType: inferredType,
      fileSize: size,
      localFilePath: cachedPath,
    );
  }

  Future<WorkspaceVaultUploadResult> uploadAttachment({
    required String userId,
    required String remoteId,
    required File file,
    String? fileName,
    String? fileType,
  }) async {
    final originalPath = file.path;
    final originalName = (fileName != null && fileName.trim().isNotEmpty)
        ? fileName.trim()
        : _basename(originalPath);

    final inferredType = (fileType != null && fileType.trim().isNotEmpty)
        ? fileType.trim()
        : (lookupMimeType(originalPath) ?? 'application/octet-stream');

    final processed = await _maybeCompressImage(
      input: file,
      mimeType: inferredType,
    );

    final bytes = await processed.readAsBytes();
    final size = bytes.length;

    final safeName = _safeName(originalName);
    final objectPath = '$userId/$remoteId/$safeName';

    await SupabaseService.client.storage.from(bucketId).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: inferredType,
          ),
        );

    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/workspace_files');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final cachedPath = '${outDir.path}/${remoteId}_$safeName';
    await File(cachedPath).writeAsBytes(bytes, flush: true);

    return WorkspaceVaultUploadResult(
      objectPath: objectPath,
      fileName: originalName,
      fileType: inferredType,
      fileSize: size,
      localFilePath: cachedPath,
    );
  }

  Future<String> ensureCached({
    required WorkspaceItem item,
  }) async {
    debugPrint(
      '[Vault] ensureCached remoteId=${item.remoteId} fileUrl=${item.fileUrl} fileName=${item.fileName} localFilePath=${item.localFilePath}',
    );

    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/workspace_files');

    final existing = item.localFilePath;
    String? existingOk;
    if (existing != null && existing.trim().isNotEmpty) {
      final f = File(existing);
      final okPath = _isVaultCachePath(
        existing,
        outDirPath: outDir.path,
        remoteId: item.remoteId,
      );
      if (okPath && await f.exists()) {
        existingOk = f.path;
      }
    }

    final objectPath = _resolveObjectPath(item);
    if (objectPath == null || objectPath.trim().isEmpty) {
      if (existingOk != null) return existingOk;
      throw StateError('No attachment is linked to this workspace item.');
    }

    debugPrint('[Vault] downloading objectPath=$objectPath');
    final bytes = await SupabaseService.client.storage.from(bucketId).download(objectPath);

    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final name = (item.fileName != null && item.fileName!.trim().isNotEmpty)
        ? item.fileName!.trim()
        : _basename(objectPath);

    final safeName = _safeName(name);

    final outPath = '${outDir.path}/${item.remoteId}_$safeName';
    final outFile = File(outPath);
    await outFile.writeAsBytes(bytes, flush: true);

    debugPrint('[Vault] cached to $outPath (${bytes.length} bytes)');
    return outFile.path;
  }

  bool _isVaultCachePath(
    String path, {
    required String outDirPath,
    required String remoteId,
  }) {
    final normalizedPath = path.replaceAll('\\', '/');
    final normalizedOutDir = outDirPath.replaceAll('\\', '/');
    if (!normalizedPath.startsWith('$normalizedOutDir/')) return false;

    final fileName = normalizedPath.split('/').last;
    return fileName.startsWith('${remoteId}_');
  }

  String? _resolveObjectPath(WorkspaceItem item) {
    final raw = item.fileUrl;
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Expected format: <userId>/<remoteId>/<safeName>
    if (trimmed.contains('/')) return trimmed;

    // Legacy/buggy values sometimes contain only a UUID. Reconstruct using auth user id.
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null || userId.trim().isEmpty) return null;

    final name = (item.fileName != null && item.fileName!.trim().isNotEmpty)
        ? item.fileName!.trim()
        : 'attachment';
    final safeName = _safeName(name);
    return '$userId/${item.remoteId}/$safeName';
  }

  Future<void> openAttachment({
    required WorkspaceItem item,
    required IsarService isarService,
  }) async {
    final localPath = await ensureCached(item: item);
    debugPrint('[Vault] opening $localPath');
    await isarService.setLocalFilePath(remoteId: item.remoteId, localFilePath: localPath);
    await OpenFilex.open(localPath);
  }

  Future<File> _maybeCompressImage({
    required File input,
    required String mimeType,
  }) async {
    if (!mimeType.startsWith('image/')) return input;

    final dir = await getTemporaryDirectory();
    final target = '${dir.path}/vb_ws_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final out = await FlutterImageCompress.compressAndGetFile(
      input.path,
      target,
      quality: 85,
      minWidth: 1600,
      minHeight: 1600,
      format: CompressFormat.jpeg,
    );

    if (out == null) return input;
    return File(out.path);
  }

  String _safeName(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return 'attachment';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  String _basename(String path) {
    final idx = path.replaceAll('\\', '/').lastIndexOf('/');
    if (idx == -1) return path;
    return path.substring(idx + 1);
  }
}
