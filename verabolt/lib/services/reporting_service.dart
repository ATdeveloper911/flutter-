import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';

import 'package:verabolt/features/workspace/data/workspace_item.dart';

class ReportingService {
  const ReportingService._();
  static const ReportingService instance = ReportingService._();

  static const _primary = PdfColor.fromInt(0xFF0F172A);
  static const _accent = PdfColor.fromInt(0xFF3B82F6);
  static const _white = PdfColors.white;
  static const _grey = PdfColors.grey600;
  static const _lightBg = PdfColor.fromInt(0xFFF1F5F9);
  static const _white70 = PdfColor(1, 1, 1, 0.70);
  static const _chipBg = PdfColor(1, 1, 1, 0.18);
  static const _statCardBg = PdfColor.fromInt(0xFF111827);
  static const _statCardBorder = PdfColor.fromInt(0xFF1F2937);

  Future<Uint8List> buildPdf(List<WorkspaceItem> items, {String userName = ''}) async {
    final doc = pw.Document();

    pw.ImageProvider? logo;
    try {
      final bytes = await rootBundle.load('lib/images/verabolt.png');
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final now = DateTime.now();
    final dateStr = _formatDate(now);

    final categories = <String, List<WorkspaceItem>>{};
    for (final item in items) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }
    final sortedCategories = categories.keys.toList()..sort();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        header: (ctx) => _buildHeader(ctx, logo, userName, dateStr),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          _buildHeroSection(items, dateStr),
          pw.SizedBox(height: 20),
          _buildTableOfContents(sortedCategories, categories),
          pw.SizedBox(height: 24),
          ..._buildCategorySections(ctx, sortedCategories, categories),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildHeader(
    pw.Context ctx,
    pw.ImageProvider? logo,
    String userName,
    String dateStr,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 2)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              if (logo != null)
                pw.Container(
                  width: 32,
                  height: 32,
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Image(logo),
                ),
              if (logo != null) pw.SizedBox(width: 10),
              pw.Text(
                'VeraBolt',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: _primary,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Workspace Report',
                style: pw.TextStyle(
                  fontSize: 11,
                  color: _grey,
                ),
              ),
              if (userName.isNotEmpty)
                pw.Text(
                  userName,
                  style: pw.TextStyle(fontSize: 10, color: _grey),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context ctx) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _accent, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 10,
                height: 10,
                decoration: pw.BoxDecoration(
                  color: _accent,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                'Data Integrity Verified  -  Generated on-device by VeraBolt',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: _grey,
                ),
              ),
            ],
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _grey),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildHeroSection(List<WorkspaceItem> items, String dateStr) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(24),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [_primary, PdfColor.fromInt(0xFF1E293B)],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: _accent,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Container(
                  width: 14,
                  height: 14,
                  decoration: pw.BoxDecoration(
                    color: _white,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Pro Workspace Report',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: _white,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Generated: $dateStr',
                      style: pw.TextStyle(fontSize: 10, color: _white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            children: [
              pw.Expanded(
                child: _statCard(
                  value: '${items.length}',
                  label: 'Total Items',
                  accent: PdfColor.fromInt(0xFF60A5FA),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _statCard(
                  value: '${items.where((i) => i.isSynced).length}',
                  label: 'Synced',
                  accent: PdfColor.fromInt(0xFF22C55E),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _statCard(
                  value: '${items.where((i) => !i.isSynced).length}',
                  label: 'Pending',
                  accent: PdfColor.fromInt(0xFFF59E0B),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  pw.Widget _statCard({
    required String value,
    required String label,
    required PdfColor accent,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: _statCardBg,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _statCardBorder, width: 0.8),
      ),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(
                width: 10,
                height: 10,
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 9,
                  color: _white70,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: _white,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTableOfContents(List<String> sortedCategories, Map<String, List<WorkspaceItem>> categories) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: _accent,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Container(
                  width: 12,
                  height: 12,
                  decoration: pw.BoxDecoration(
                    color: _white,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                'Table of Contents',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _primary,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _white,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey100, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: sortedCategories.asMap().entries.map((entry) {
                return pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: 24,
                        height: 24,
                        decoration: pw.BoxDecoration(
                          gradient: pw.LinearGradient(
                            colors: [_accent, PdfColor.fromInt(0xFF2563EB)],
                          ),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            '${entry.key + 1}',
                            style: pw.TextStyle(
                              fontSize: 10,
                              color: _white,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Expanded(
                        child: pw.Text(
                          _capitalise(entry.value),
                          style: pw.TextStyle(
                            fontSize: 11,
                            color: _primary,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFEBF5FF),
                          borderRadius: pw.BorderRadius.circular(10),
                        ),
                        child: pw.Text(
                          '${categories[entry.value]?.length ?? 0}',
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: _accent,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _buildCategorySections(
    pw.Context ctx,
    List<String> sortedCategories,
    Map<String, List<WorkspaceItem>> categories,
  ) {
    final widgets = <pw.Widget>[];
    for (final cat in sortedCategories) {
      final catItems = categories[cat]!;
      widgets.add(_buildCategorySection(cat, catItems));
      widgets.add(pw.SizedBox(height: 20));
    }
    return widgets;
  }

  pw.Widget _buildCategorySection(String category, List<WorkspaceItem> items) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [_accent, PdfColor.fromInt(0xFF2563EB)],
              begin: pw.Alignment.topLeft,
              end: pw.Alignment.bottomRight,
            ),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: _chipBg,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  _categoryIcon(category),
                  style: pw.TextStyle(fontSize: 12),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Text(
                  _capitalise(category),
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _white,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: pw.BoxDecoration(
                  color: _chipBg,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Text(
                  '${items.length} item${items.length == 1 ? "" : "s"}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: _white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        ...items.map((item) => _buildItemRow(item)),
      ],
    );
  }

  String _categoryIcon(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('general')) return 'G';
    if (lower.contains('strategy')) return 'S';
    if (lower.contains('notes')) return 'N';
    if (lower.contains('archive')) return 'A';
    return 'W';
  }

  pw.Widget _buildItemRow(WorkspaceItem item) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 8,
            height: 8,
            margin: const pw.EdgeInsets.only(top: 6, right: 12),
            decoration: pw.BoxDecoration(
              color: item.isSynced ? PdfColors.green600 : PdfColors.orange,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  item.title,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _primary,
                  ),
                ),
                if (item.description.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    item.description,
                    style: pw.TextStyle(fontSize: 9, color: _grey),
                    maxLines: 3,
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: item.isSynced ? PdfColors.green50 : PdfColors.orange50,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(
                  width: 6,
                  height: 6,
                  decoration: pw.BoxDecoration(
                    color: item.isSynced ? PdfColors.green700 : PdfColors.orange,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 5),
                pw.Text(
                  item.isSynced ? 'Synced' : 'Pending',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: item.isSynced ? PdfColors.green700 : PdfColors.orange,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _capitalise(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m';
  }

  Future<void> sharePdf(List<WorkspaceItem> items, {String userName = ''}) async {
    final bytes = await buildPdf(items, userName: userName);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/verabolt_report_$stamp.pdf');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'VeraBolt Workspace Report',
    );
  }

  Future<void> previewPdf(List<WorkspaceItem> items, {String userName = ''}) async {
    final bytes = await buildPdf(items, userName: userName);
    
    // Check if we can use the printing UI (online) or need to save locally (offline)
    bool canUsePrinting = true;
    try {
      // Try to detect if printing is available
      await Printing.info();
    } catch (_) {
      canUsePrinting = false;
    }
    
    if (canUsePrinting) {
      try {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
        return;
      } catch (_) {
        // If printing fails, fall back to saving locally
        canUsePrinting = false;
      }
    }
    
    // Save locally (offline mode or printing failed)
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/verabolt_report_$stamp.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

  String buildCsv(List<WorkspaceItem> items) {
    final buffer = StringBuffer();
    buffer.writeln('"Title","Description","Category","Synced","Last Modified"');
    for (final item in items) {
      buffer.writeln([
        _csvCell(item.title),
        _csvCell(item.description),
        _csvCell(item.category),
        item.isSynced ? '"Yes"' : '"No"',
        '"${item.lastModified.toLocal().toIso8601String()}"',
      ].join(','));
    }
    return buffer.toString();
  }

  Future<void> shareCsv(List<WorkspaceItem> items) async {
    final csv = buildCsv(items);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/verabolt_workspace_$stamp.csv');
    await file.writeAsString(csv);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'VeraBolt Workspace Data',
    );
  }

  String _csvCell(String v) => '"${v.replaceAll('"', '""')}"';
}
