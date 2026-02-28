import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

import 'package:verabolt/core/widgets/overlay_message.dart';
import 'package:verabolt/core/utils/connectivity_provider.dart';
import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/licensing/application/pro_status_provider.dart';
import 'package:verabolt/features/profile/application/profile_providers.dart';
import 'package:verabolt/features/profile/data/local_profile.dart';
import 'package:verabolt/features/workspace/application/workspace_providers.dart';
import 'package:verabolt/services/local_storage.dart';
import 'package:verabolt/services/supabase_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();

  bool _saving = false;
  String? _avatarLocalPath;
  Timer? _nameDebounce;
  bool _suspendNameListener = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _nameDebounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _safeBackToDashboard() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  void _onNameChanged() {
    if (_suspendNameListener) return;
    _nameDebounce?.cancel();

    final next = _name.text.trim();
    _nameDebounce = Timer(const Duration(milliseconds: 300), () async {
      final user = await ref.read(authUserProvider.future);
      if (user == null) return;

      final isar = LocalStorage.isar;
      await isar.writeTxn(() async {
        final existing =
            await isar.localProfiles.filter().userIdEqualTo(user.id).findFirst();
        final lp = existing ?? LocalProfile()..userId = user.id;
        lp
          ..email = user.email
          ..displayName = next.isEmpty ? null : next
          ..isDirty = true
          ..updatedAt = DateTime.now().toUtc();
        await isar.localProfiles.put(lp);
      });
    });
  }

  Future<String> _copyAvatarToDocuments({required String userId, required XFile file}) async {
    final dir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory('${dir.path}/avatars');
    if (!await avatarsDir.exists()) {
      await avatarsDir.create(recursive: true);
    }

    final target = File('${avatarsDir.path}/$userId-${DateTime.now().millisecondsSinceEpoch}.jpg');
    return (await File(file.path).copy(target.path)).path;
  }

  Future<String?> _compressAvatarForUpload({required String inputPath}) async {
    final dir = await getTemporaryDirectory();
    final target = '${dir.path}/vb_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final out = await FlutterImageCompress.compressAndGetFile(
      inputPath,
      target,
      quality: 85,
      minWidth: 500,
      minHeight: 500,
      format: CompressFormat.jpeg,
    );
    return out?.path;
  }

  Future<void> _pickImage() async {
    final user = await ref.read(authUserProvider.future);
    if (user == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    final previousPath = _avatarLocalPath;

    final localPath = await _copyAvatarToDocuments(userId: user.id, file: picked);

    setState(() {
      _avatarLocalPath = localPath;
    });

    try {
      if (previousPath != null && previousPath.trim().isNotEmpty) {
        PaintingBinding.instance.imageCache.evict(FileImage(File(previousPath)));
      }
      PaintingBinding.instance.imageCache.evict(FileImage(File(localPath)));
    } catch (_) {}

    final isar = LocalStorage.isar;
    await isar.writeTxn(() async {
      final existing = await isar.localProfiles.filter().userIdEqualTo(user.id).findFirst();
      final lp = existing ?? LocalProfile()..userId = user.id;
      lp
        ..email = user.email
        ..avatarLocalPath = localPath
        ..isDirty = true
        ..updatedAt = DateTime.now().toUtc();
      await isar.localProfiles.put(lp);
    });

    final offline = ref.read(isOfflineProvider);
    if (offline) return;

    unawaited(() async {
      try {
        final compressedPath = await _compressAvatarForUpload(inputPath: localPath);
        final bytes = await File(compressedPath ?? localPath).readAsBytes();
        final path = '${user.id}/avatar.jpg';
        await SupabaseService.client.storage.from('avatars').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
        final avatarUrl = SupabaseService.client.storage.from('avatars').getPublicUrl(path);

        await ref.read(profileRepositoryProvider).updateMyProfile(
              userId: user.id,
              avatarUrl: avatarUrl,
            );

        await isar.writeTxn(() async {
          final existing = await isar.localProfiles.filter().userIdEqualTo(user.id).findFirst();
          if (existing == null) return;
          existing
            ..avatarUrl = avatarUrl
            ..isDirty = false
            ..updatedAt = DateTime.now().toUtc();
          await isar.localProfiles.put(existing);
        });
      } catch (_) {
        if (!mounted) return;
        await OverlayMessage.error(context, 'Unable to upload avatar. Please try again.');
      }
    }());
  }

  Future<void> _save() async {
    if (_saving) return;

    final user = await ref.read(authUserProvider.future);
    if (user == null) return;

    final displayName = _name.text.trim();
    final offline = ref.read(isOfflineProvider);

    setState(() => _saving = true);
    try {
      final isar = LocalStorage.isar;
      bool wroteAnyLocalChange = false;
      await isar.writeTxn(() async {
        final existing = await isar.localProfiles.filter().userIdEqualTo(user.id).findFirst();
        final lp = existing ?? LocalProfile()..userId = user.id;

        final nextName = displayName.isEmpty ? lp.displayName : displayName;
        final nextAvatarPath = _avatarLocalPath ?? lp.avatarLocalPath;

        wroteAnyLocalChange = (nextName != lp.displayName) || (nextAvatarPath != lp.avatarLocalPath);

        lp
          ..email = user.email
          ..displayName = nextName
          ..avatarLocalPath = nextAvatarPath
          ..isDirty = wroteAnyLocalChange ? true : lp.isDirty
          ..updatedAt = DateTime.now().toUtc();
        await isar.localProfiles.put(lp);
      });

      if (!mounted) return;
      if (wroteAnyLocalChange) {
        await OverlayMessage.success(context, 'Profile updated');
      }

      if (offline) {
        _safeBackToDashboard();
        return;
      }

      String? avatarUrl;
      if (_avatarLocalPath != null && _avatarLocalPath!.trim().isNotEmpty) {
        final compressedPath = await _compressAvatarForUpload(inputPath: _avatarLocalPath!);
        final bytes = await File(compressedPath ?? _avatarLocalPath!).readAsBytes();
        final path = '${user.id}/avatar.jpg';
        await SupabaseService.client.storage.from('avatars').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
        avatarUrl = SupabaseService.client.storage.from('avatars').getPublicUrl(path);
      }

      await ref.read(profileRepositoryProvider).updateMyProfile(
            userId: user.id,
            displayName: displayName.isEmpty ? null : displayName,
            avatarUrl: avatarUrl,
          );

      await isar.writeTxn(() async {
        final existing = await isar.localProfiles.filter().userIdEqualTo(user.id).findFirst();
        if (existing == null) return;
        existing
          ..avatarUrl = avatarUrl ?? existing.avatarUrl
          ..isDirty = false
          ..updatedAt = DateTime.now().toUtc();
        await isar.localProfiles.put(existing);
      });

      _safeBackToDashboard();
    } catch (e) {
      if (!mounted) return;
      await OverlayMessage.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localProfile = ref.watch(localProfileProvider).maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );

    final isOffline = ref.watch(isOfflineProvider);
    final isProAsync = ref.watch(isProProvider);
    final profileStatusAsync = ref.watch(profileStatusProvider);
    final backupsAsync = ref.watch(workspaceBackupsProvider);

    if (_name.text.isEmpty && (localProfile?.displayName?.trim().isNotEmpty ?? false)) {
      _suspendNameListener = true;
      _name.text = localProfile!.displayName!.trim();
      _suspendNameListener = false;
    }

    final previewPath = _avatarLocalPath ?? localProfile?.avatarLocalPath;
    final previewFile =
        (previewPath != null && previewPath.trim().isNotEmpty) ? File(previewPath) : null;
    final hasAvatar = previewFile != null && previewFile.existsSync();

    return Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back to Dashboard',
        onPressed: _saving ? null : () => context.go('/dashboard'),
      ),
      title: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'lib/images/verabolt.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
              ),
              Text(
                'Profile & backup',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                      height: 1.0,
                    ),
              ),
            ],
          ),
        ],
      ),
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0F172A).withValues(alpha: 0.92),
              const Color(0xFF0B1D3A).withValues(alpha: 0.92),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.secondary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            minimumSize: const Size(84, 40),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
        const SizedBox(width: 10),
      ],
    ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF0B1D3A)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
  elevation: 0,
  color: Colors.transparent,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
  child: Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.08),
          Colors.white.withOpacity(0.03),
        ],
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withOpacity(0.12)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.25),
          blurRadius: 30,
          spreadRadius: 5,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      child: Column(
        children: [
          // Avatar with camera overlay + tap feedback
          GestureDetector(
            onTap: _saving ? null : _pickImage,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                        blurRadius: 32,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 64,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    backgroundImage: hasAvatar ? FileImage(previewFile!) : null,
                    child: hasAvatar
                        ? null
                        : Icon(
                            Icons.person_outline_rounded,
                            size: 80,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                  ),
                ),
                // Camera icon overlay
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Subtle hint
          AnimatedOpacity(
            opacity: _saving ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: Text(
              'Tap photo to change',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
          const SizedBox(height: 32),

          // Display name field with modern style
          TextField(
            controller: _name,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: 'Display name',
              labelStyle: TextStyle(
                color: _name.text.isEmpty
                    ? Colors.white60
                    : Theme.of(context).colorScheme.primary,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 18,
              ),
              suffixIcon: _saving
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            style: const TextStyle(color: Colors.white, fontSize: 17),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 24),

          // Email (selectable + styled container)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Email: ',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 15,
                    ),
                  ),
                  TextSpan(
                    text: localProfile?.email ?? 'Not available',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Profile status pill
          profileStatusAsync.when(
            data: (status) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: status == 'active'
                    ? Colors.green.withOpacity(0.18)
                    : status == 'pending'
                        ? Colors.orange.withOpacity(0.18)
                        : Colors.red.withOpacity(0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: status == 'active'
                      ? Colors.green.withOpacity(0.5)
                      : status == 'pending'
                          ? Colors.orange.withOpacity(0.5)
                          : Colors.red.withOpacity(0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    status == 'active'
                        ? Icons.verified
                        : status == 'pending'
                            ? Icons.hourglass_top_rounded
                            : Icons.warning_amber_rounded,
                    size: 20,
                    color: status == 'active'
                        ? Colors.greenAccent
                        : status == 'pending'
                            ? Colors.orangeAccent
                            : Colors.redAccent,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Profile status: $status',
                    style: TextStyle(
                      color: status == 'active'
                          ? Colors.greenAccent
                          : status == 'pending'
                              ? Colors.orangeAccent
                              : Colors.redAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const Text('Loading status...', style: TextStyle(color: Colors.white54)),
            error: (_, __) => const Text('Status error', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    ),
  ),
),
              const SizedBox(height: 14),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                color: const Color(0xFF0F172A).withValues(alpha: 0.55),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.lightBlueAccent.withValues(alpha: 0.14),
                              border: Border.all(
                                color: Colors.lightBlueAccent.withValues(alpha: 0.28),
                              ),
                            ),
                            child: const Icon(
                              Icons.backup_rounded,
                              size: 18,
                              color: Colors.lightBlueAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Backup & Restore',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          if (isOffline)
                            Text(
                              'Offline',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Deleted workspace items are stored locally so you can restore them anytime (Pro only).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                              height: 1.25,
                            ),
                      ),
                      const SizedBox(height: 12),
                      isProAsync.when(
                        data: (isPro) {
                          final isActive = profileStatusAsync.maybeWhen(
                            data: (s) => s == 'active',
                            orElse: () => false,
                          );
                          final allowed = isPro && isActive;

                          return backupsAsync.when(
                            data: (backups) {
                              final count = backups.length;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Items in backup: $count',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      FilledButton.icon(
                                        onPressed: (!allowed || _saving || count == 0)
                                            ? null
                                            : () async {
                                                final user = await ref.read(authUserProvider.future);
                                                if (user == null) return;
                                                try {
                                                  await ref
                                                      .read(isarServiceProvider)
                                                      .restoreAllBackups(userId: user.id);
                                                  if (!mounted) return;
                                                  await OverlayMessage.success(
                                                    context,
                                                    'Restored $count item(s) to workspace.',
                                                  );
                                                } catch (_) {
                                                  if (!mounted) return;
                                                  await OverlayMessage.error(
                                                    context,
                                                    'This feature is available for active Pro members only.',
                                                  );
                                                }
                                              },
                                        icon: const Icon(Icons.restore_rounded),
                                        label: const Text('Restore all'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: scheme.secondary,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (count == 0)
                                    Text(
                                      'No deleted items found.',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.white70,
                                          ),
                                    )
                                  else
                                    ...backups.take(8).map((b) {
                                      final title = (b.title).trim().isEmpty ? 'Untitled' : b.title.trim();
                                      final cat = (b.category).trim();
                                      final deletedAt = b.deletedAt.toLocal();
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(14),
                                            color: Colors.white.withValues(alpha: 0.06),
                                            border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.10),
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(12),
                                                  color: Colors.orangeAccent.withValues(alpha: 0.14),
                                                  border: Border.all(
                                                    color: Colors.orangeAccent.withValues(alpha: 0.28),
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 18,
                                                  color: Colors.orangeAccent,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      title,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.w800,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      cat.isEmpty
                                                          ? 'Deleted: ${deletedAt.toString()}'
                                                          : '$cat • Deleted: ${deletedAt.toString()}',
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                            color: Colors.white70,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              OutlinedButton(
                                                onPressed: (!allowed || _saving)
                                                    ? null
                                                    : () async {
                                                        final user = await ref.read(authUserProvider.future);
                                                        if (user == null) return;
                                                        try {
                                                          await ref
                                                              .read(isarServiceProvider)
                                                              .restoreBackup(
                                                                userId: user.id,
                                                                backupId: b.id,
                                                              );
                                                          if (!mounted) return;
                                                          await OverlayMessage.success(
                                                            context,
                                                            'Restored to workspace.',
                                                          );
                                                        } catch (_) {
                                                          if (!mounted) return;
                                                          await OverlayMessage.error(
                                                            context,
                                                            'This feature is available for active Pro members only.',
                                                          );
                                                        }
                                                      },
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                                                ),
                                                child: const Text('Restore'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                  if (count > 8)
                                    Text(
                                      'Showing latest 8 items. Restore all to bring everything back.',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.white70,
                                          ),
                                    ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: (!allowed || _saving || count == 0)
                                        ? null
                                        : () async {
                                            final user = await ref.read(authUserProvider.future);
                                            if (user == null) return;
                                            try {
                                              await ref.read(isarServiceProvider).clearBackups(userId: user.id);
                                              if (!mounted) return;
                                              await OverlayMessage.success(context, 'Backup cleared.');
                                            } catch (_) {
                                              if (!mounted) return;
                                              await OverlayMessage.error(
                                                context,
                                                'This feature is available for active Pro members only.',
                                              );
                                            }
                                          },
                                    icon: const Icon(Icons.delete_sweep_rounded),
                                    label: const Text('Clear backup'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                      side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                                    ),
                                  ),
                                ],
                              );
                            },
                            loading: () => const Center(
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            error: (_, __) => Text(
                              'Unable to load backup items.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _safeBackToDashboard,
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text('Back to Dashboard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
