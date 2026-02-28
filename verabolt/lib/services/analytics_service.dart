import 'dart:io';

import 'package:verabolt/features/workspace/data/workspace_item.dart';

class ProAnalyticsSummary {
  const ProAnalyticsSummary({
    required this.totalItems,
    required this.textItems,
    required this.pdfItems,
    required this.imageItems,
    required this.csvItems,
    required this.otherBinaryItems,
    required this.syncedItems,
    required this.pendingItems,
    required this.localBytes,
    required this.last7DayCounts,
    required this.last7DayLabels,
  });

  final int totalItems;
  final int textItems;
  final int pdfItems;
  final int imageItems;
  final int csvItems;
  final int otherBinaryItems;

  final int syncedItems;
  final int pendingItems;

  final int localBytes;

  final List<int> last7DayCounts;
  final List<String> last7DayLabels;
}

class AnalyticsService {
  const AnalyticsService._();
  static const AnalyticsService instance = AnalyticsService._();

  Future<ProAnalyticsSummary> buildProSummary(List<WorkspaceItem> items) async {
    int text = 0;
    int pdf = 0;
    int img = 0;
    int csv = 0;
    int otherBinary = 0;

    int synced = 0;
    int localBytes = 0;

    final now = DateTime.now();
    final todayLocal = DateTime(now.year, now.month, now.day);

    final dayLabels = <String>[];
    final dayCounts = List<int>.filled(7, 0);

    for (int i = 6; i >= 0; i--) {
      final day = todayLocal.subtract(Duration(days: i));
      dayLabels.add(_weekdayShort(day.weekday));
    }

    for (final item in items) {
      if (item.isSynced) synced++;

      final localPath = item.localFilePath;
      if (localPath != null && localPath.trim().isNotEmpty) {
        try {
          final f = File(localPath);
          if (await f.exists()) {
            localBytes += await f.length();
          } else if (item.fileSize != null && item.fileSize! > 0) {
            localBytes += item.fileSize!;
          }
        } catch (_) {
          if (item.fileSize != null && item.fileSize! > 0) {
            localBytes += item.fileSize!;
          }
        }
      } else if (item.fileSize != null && item.fileSize! > 0) {
        localBytes += item.fileSize!;
      }

      final mime = (item.fileType ?? '').toLowerCase();
      final hasBinary = (item.fileUrl != null && item.fileUrl!.trim().isNotEmpty) ||
          (item.localFilePath != null && item.localFilePath!.trim().isNotEmpty);

      if (!hasBinary) {
        text++;
      } else if (mime.contains('pdf')) {
        pdf++;
      } else if (mime.startsWith('image/')) {
        img++;
      } else if (mime.contains('csv')) {
        csv++;
      } else {
        otherBinary++;
      }

      final mod = item.lastModified.toLocal();
      final modDay = DateTime(mod.year, mod.month, mod.day);
      final diff = todayLocal.difference(modDay).inDays;
      if (diff >= 0 && diff <= 6) {
        final idx = 6 - diff;
        if (idx >= 0 && idx < 7) {
          dayCounts[idx] = dayCounts[idx] + 1;
        }
      }
    }

    final total = items.length;
    final pending = total - synced;

    return ProAnalyticsSummary(
      totalItems: total,
      textItems: text,
      pdfItems: pdf,
      imageItems: img,
      csvItems: csv,
      otherBinaryItems: otherBinary,
      syncedItems: synced,
      pendingItems: pending < 0 ? 0 : pending,
      localBytes: localBytes,
      last7DayCounts: dayCounts,
      last7DayLabels: dayLabels,
    );
  }

  String _weekdayShort(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return 'Day';
    }
  }
}
