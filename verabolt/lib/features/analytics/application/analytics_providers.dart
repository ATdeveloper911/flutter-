import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/workspace/application/workspace_providers.dart';
import 'package:verabolt/services/analytics_service.dart';

final proAnalyticsSummaryProvider = FutureProvider<ProAnalyticsSummary>((ref) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    return const ProAnalyticsSummary(
      totalItems: 0,
      textItems: 0,
      pdfItems: 0,
      imageItems: 0,
      csvItems: 0,
      otherBinaryItems: 0,
      syncedItems: 0,
      pendingItems: 0,
      localBytes: 0,
      last7DayCounts: [0, 0, 0, 0, 0, 0, 0],
      last7DayLabels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    );
  }

  final isar = ref.watch(isarServiceProvider);
  final items = await isar.getAllItems(userId: user.id);
  return AnalyticsService.instance.buildProSummary(items);
});
