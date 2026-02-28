import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:verabolt/features/analytics/application/analytics_providers.dart';
import 'package:verabolt/services/analytics_service.dart';

class ProAnalyticsScreen extends ConsumerWidget {
  const ProAnalyticsScreen({super.key});

  static const _bgTop = Color(0xFF0B1D3A);
  static const _bgBottom = Color(0xFF0F172A);

  static const _blue = Color(0xFF3B82F6);
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _purple = Color(0xFFA855F7);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(proAnalyticsSummaryProvider);

    return Scaffold(
      backgroundColor: _bgBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0F172A).withValues(alpha: 0.92),
                const Color(0xFF0B1D3A).withValues(alpha: 0.85),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        title: const Text(
          'Analytics',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: 0.4,
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
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: summaryAsync.when(
            data: (summary) => _buildBody(context, summary),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load analytics: $e',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ProAnalyticsSummary s) {
    final limitBytes = 1024 * 1024 * 1024;
    final progress = (limitBytes <= 0) ? 0.0 : (s.localBytes / limitBytes).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        _glassCard(
          title: 'Storage Pulse',
          child: Row(
            children: [
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 82,
                      height: 82,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: const AlwaysStoppedAnimation(_blue),
                      ),
                    ),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatBytes(s.localBytes),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Local data usage (of 1.0 GB)',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill(label: 'Text', value: s.textItems.toString(), accent: Colors.white),
                        _pill(label: 'Binary', value: (s.totalItems - s.textItems).toString(), accent: _blue),
                        _pill(label: 'Backed up', value: s.syncedItems.toString(), accent: _green),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _glassCard(
          title: 'Workspace Composition',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 190,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 52,
                    sectionsSpace: 2,
                    startDegreeOffset: -90,
                    sections: _compositionSections(s),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _legendDot(color: Colors.white, label: 'Text'),
                  _legendDot(color: _red, label: 'PDF'),
                  _legendDot(color: _purple, label: 'Images'),
                  _legendDot(color: _green, label: 'CSV'),
                  _legendDot(color: _blue, label: 'Other'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _glassCard(
          title: 'Sync Frequency (7 days)',
          child: SizedBox(
            height: 210,
            child: BarChart(
              BarChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 2),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 2,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        final label = (idx >= 0 && idx < s.last7DayLabels.length)
                            ? s.last7DayLabels[idx]
                            : '';
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            label,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(7, (i) {
                  final v = (i >= 0 && i < s.last7DayCounts.length) ? s.last7DayCounts[i] : 0;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: v.toDouble(),
                        width: 14,
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            _blue.withValues(alpha: 0.55),
                            _blue.withValues(alpha: 0.95),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
                maxY: math.max(4, (s.last7DayCounts.fold<int>(0, (a, b) => a > b ? a : b) + 2)).toDouble(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _glassCard(
          title: 'Sync Health',
          child: Row(
            children: [
              Expanded(
                child: _metric(
                  label: 'Synced',
                  value: s.syncedItems.toString(),
                  accent: _green,
                  icon: Icons.cloud_done_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metric(
                  label: 'Pending',
                  value: s.pendingItems.toString(),
                  accent: _red,
                  icon: Icons.cloud_upload_rounded,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _compositionSections(ProAnalyticsSummary s) {
    final total = math.max(1, s.totalItems);

    double pct(int v) => (v / total) * 100;

    return [
      PieChartSectionData(
        value: s.textItems.toDouble(),
        color: Colors.white.withValues(alpha: 0.65),
        radius: 46,
        title: '${pct(s.textItems).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 11),
      ),
      PieChartSectionData(
        value: s.pdfItems.toDouble(),
        color: _red,
        radius: 50,
        title: '${pct(s.pdfItems).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
      ),
      PieChartSectionData(
        value: s.imageItems.toDouble(),
        color: _purple,
        radius: 50,
        title: '${pct(s.imageItems).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
      ),
      PieChartSectionData(
        value: s.csvItems.toDouble(),
        color: _green,
        radius: 50,
        title: '${pct(s.csvItems).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
      ),
      PieChartSectionData(
        value: s.otherBinaryItems.toDouble(),
        color: _blue,
        radius: 50,
        title: '${pct(s.otherBinaryItems).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    ];
  }

  Widget _glassCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _pill({required String label, required String value, required Color accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  Widget _legendDot({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12)),
      ],
    );
  }

  Widget _metric({required String label, required String value, required Color accent, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double v = bytes.toDouble();
    int idx = 0;
    while (v >= 1024 && idx < units.length - 1) {
      v /= 1024;
      idx++;
    }
    return '${v.toStringAsFixed(v >= 10 || idx == 0 ? 0 : 1)} ${units[idx]}';
  }
}
