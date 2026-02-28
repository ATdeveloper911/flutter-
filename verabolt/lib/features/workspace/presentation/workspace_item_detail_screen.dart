import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:verabolt/core/utils/connectivity_provider.dart';
import 'package:verabolt/core/widgets/overlay_message.dart';
import 'package:verabolt/features/workspace/data/workspace_item.dart';
import 'package:verabolt/features/workspace/application/workspace_providers.dart';
import 'package:verabolt/services/workspace_vault_service.dart';

class WorkspaceItemDetailScreen extends ConsumerWidget {
  const WorkspaceItemDetailScreen({super.key, required this.item});

  final WorkspaceItem item;

  Widget _statusChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  bool _isPdf(String? mime) => (mime ?? '').toLowerCase().contains('pdf');
  bool _isCsv(String? mime) => (mime ?? '').toLowerCase().contains('csv');

  String _attachmentLabel(String? mime) {
    if (_isPdf(mime)) return 'Open PDF';
    if (_isCsv(mime)) return 'Open CSV';
    final t = (mime ?? '').trim();
    if (t.isEmpty) return 'Open Attachment';
    return 'Open Attachment';
  }

  IconData _attachmentIcon(String? mime) {
    if (_isPdf(mime)) return Icons.picture_as_pdf_outlined;
    if (_isCsv(mime)) return Icons.table_chart_outlined;
    final t = (mime ?? '').toLowerCase();
    if (t.startsWith('image/')) return Icons.image_outlined;
    return Icons.attach_file_rounded;
  }

  Color _attachmentColor(String? mime) {
    if (_isPdf(mime)) return const Color(0xFFEF4444);
    if (_isCsv(mime)) return const Color(0xFF22C55E);
    final t = (mime ?? '').toLowerCase();
    if (t.startsWith('image/')) return const Color(0xFFA855F7);
    return const Color(0xFF60A5FA);
  }

  Future<void> _openAttachment(BuildContext context, WidgetRef ref) async {
    try {
      final local = item.localFilePath;
      final hasLocal =
          local != null && local.trim().isNotEmpty && await File(local).exists();

      if (!context.mounted) return;

      final offline = ref.read(isOfflineProvider);
      if (offline && !hasLocal) {
        if (!context.mounted) return;
        await OverlayMessage.error(
          context,
          'Offline: open once while online to cache this file for secure offline access.',
        );
        return;
      }

      await WorkspaceVaultService().openAttachment(
        item: item,
        isarService: ref.read(isarServiceProvider),
      );
    } catch (e) {
      if (!context.mounted) return;
      await OverlayMessage.error(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAttachment = (item.fileUrl != null && item.fileUrl!.trim().isNotEmpty) ||
        (item.localFilePath != null && item.localFilePath!.trim().isNotEmpty);

    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0F172A).withValues(alpha: 0.92),
                const Color(0xFF0B1D3A).withValues(alpha: 0.75),
              ],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: const Text(
          'Workspace Item',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: false,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF111827)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1E293B).withValues(alpha: 0.95),
                        const Color(0xFF0F172A).withValues(alpha: 0.98),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 30,
                        spreadRadius: 5,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _statusChip(
                            icon: Icons.category_rounded,
                            label: item.category.isEmpty ? 'Uncategorized' : item.category,
                            color: primary,
                          ),
                          _statusChip(
                            icon: item.isSynced
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_upload_rounded,
                            label: item.isSynced ? 'Synced' : 'Pending Sync',
                            color: item.isSynced ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _glassSection(
                  icon: Icons.description_rounded,
                  title: 'Description',
                  color: Colors.blueAccent,
                  child: Text(
                    item.description.trim().isEmpty
                        ? 'No description provided.'
                        : item.description,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (hasAttachment)
                  _glassSection(
                    icon: _attachmentIcon(item.fileType),
                    title: item.fileName?.trim().isNotEmpty == true
                        ? item.fileName!
                        : 'Attachment',
                    color: _attachmentColor(item.fileType),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (item.fileType ?? '').trim().isEmpty
                              ? 'Unknown type'
                              : item.fileType!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _openAttachment(context, ref),
                            icon: const Icon(Icons.open_in_new),
                            label: Text(_attachmentLabel(item.fileType)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _glassSection(
                    icon: Icons.attach_file_rounded,
                    title: 'Attachment',
                    color: Colors.white70,
                    child: const Text(
                      'No attachment linked.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassSection({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}
