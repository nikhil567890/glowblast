import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../services/excel_service.dart';

class ExcelImportScreen extends StatefulWidget {
  final AppRepository repository;

  const ExcelImportScreen({super.key, required this.repository});

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  bool _isLoadingFile = false;
  bool _isImporting = false;
  double _importProgress = 0.0;
  bool _isImportComplete = false;
  int _importedCount = 0;

  String? _fileName;
  ExcelValidationResult? _validationResult;
  bool _showErrorReview = false;

  Future<void> _pickExcelFile() async {
    setState(() => _isLoadingFile = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();

        if (bytes.isNotEmpty) {
          _processExcelBytes(file.name, bytes);
        } else {
          _showError('The selected Excel file is empty or cannot be read.');
        }
      }
    } catch (e) {
      _showError('Could not open Excel file: $e');
    } finally {
      if (mounted) setState(() => _isLoadingFile = false);
    }
  }

  void _loadSample200Excel() {
    setState(() => _isLoadingFile = true);
    try {
      final sampleBytes = ExcelService.generate200RowTestSampleBytes();
      _processExcelBytes('sample_customers.xlsx', sampleBytes);
    } catch (e) {
      _showError('Error loading sample dataset: $e');
    } finally {
      if (mounted) setState(() => _isLoadingFile = false);
    }
  }

  Future<void> _downloadSampleTemplate() async {
    try {
      final bytes = ExcelService.generateSampleTemplateBytes();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/GlowBlast_Customers_Template.xlsx');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'GlowBlast Customer Import Template (.xlsx)',
        ),
      );
    } catch (e) {
      _showError('Could not export template: $e');
    }
  }

  Future<void> _downloadSample200Dataset() async {
    try {
      final bytes = ExcelService.generate200RowTestSampleBytes();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/sample_customers.xlsx');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'GlowBlast 200-Row Sample Customer Dataset (.xlsx)',
        ),
      );
    } catch (e) {
      _showError('Could not export sample dataset: $e');
    }
  }

  void _processExcelBytes(String name, List<int> bytes) {
    try {
      final validation = ExcelService.parseAndValidate(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        existingCustomers: widget.repository.customers,
      );

      setState(() {
        _fileName = name;
        _validationResult = validation;
        _showErrorReview = false;
        _isImportComplete = false;
      });
    } catch (e) {
      _showError('Could not parse Excel spreadsheet. Please ensure it is a valid .xlsx or .xls file.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _executeImport() async {
    if (_validationResult == null || _validationResult!.validCustomers.isEmpty) {
      _showError('No valid customers to import.');
      return;
    }

    setState(() {
      _isImporting = true;
      _importProgress = 0.1;
    });

    // Simulate animated import progress
    for (int step = 1; step <= 10; step++) {
      await Future.delayed(const Duration(milliseconds: 70));
      if (!mounted) return;
      setState(() => _importProgress = step / 10.0);
    }

    final added = await widget.repository.bulkImportCustomers(_validationResult!.validCustomers);

    if (!mounted) return;
    setState(() {
      _isImporting = false;
      _isImportComplete = true;
      _importedCount = added;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Customers via Excel'),
        actions: [
          IconButton(
            tooltip: 'Download Sample Template',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _downloadSampleTemplate,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const DemoRibbon(label: 'EXCEL CUSTOMER PARSER & IMPORTER'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Intro
                    Text(
                      'Bulk Import from Excel (.xlsx / .xls)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Upload an Excel spreadsheet with 2 columns: Full Name and Phone Number. Phone numbers are automatically sanitized and duplicate entries are detected.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // File upload / picker box
                    if (_validationResult == null) ...[
                      InkWell(
                        onTap: _isLoadingFile ? null : _pickExcelFile,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surfaceDark : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primarySage.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySageContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: _isLoadingFile
                                    ? const SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: CircularProgressIndicator(strokeWidth: 3),
                                      )
                                    : const Icon(
                                        Icons.table_view_rounded,
                                        size: 36,
                                        color: AppColors.primarySageDark,
                                      ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isLoadingFile ? 'Reading spreadsheet...' : 'Import from Excel',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap to browse files on your device (.xlsx, .xls)',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Template Download Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.cardDark : AppColors.warmCream,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.description_outlined, color: AppColors.primarySage, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'Excel Template & Test Datasets',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Download our pre-formatted blank template or test our ready-to-test 200-customer spreadsheet (190 valid, 7 duplicates, 3 invalid phones).',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.download_rounded, size: 16),
                                  label: const Text('Download sample Excel'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primarySage,
                                    side: const BorderSide(color: AppColors.primarySage),
                                  ),
                                  onPressed: _downloadSampleTemplate,
                                ),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                  label: const Text('Test 200-Row Sample'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primarySage,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _loadSample200Excel,
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.share_outlined, size: 16),
                                  label: const Text('Share 200 Dataset'),
                                  onPressed: _downloadSample200Dataset,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    // After file parsed: Validation Results Preview
                    if (_validationResult != null && !_isImportComplete) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppColors.primarySage),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _fileName ?? 'Spreadsheet',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _validationResult = null),
                            child: const Text('Choose Different File'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // KPI Stats Grid
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.8,
                        children: [
                          _buildStatCard('Total Rows Found', '${_validationResult!.totalRows}', Icons.format_list_numbered_rounded, Colors.grey.shade700, isDark),
                          _buildStatCard('Valid Customers', '${_validationResult!.validCount}', Icons.check_circle_rounded, AppColors.success, isDark),
                          _buildStatCard('Duplicate Records', '${_validationResult!.duplicateCount}', Icons.copy_rounded, AppColors.warning, isDark),
                          _buildStatCard('Invalid Phones / Data', '${_validationResult!.invalidPhoneCount + _validationResult!.otherErrorCount}', Icons.error_outline_rounded, AppColors.error, isDark),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Toggle error view vs preview table
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _showErrorReview ? 'Errors to Review' : 'Preview Valid Customers (${_validationResult!.validCount})',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          if (_validationResult!.totalErrors > 0)
                            TextButton.icon(
                              icon: Icon(_showErrorReview ? Icons.table_chart_outlined : Icons.warning_amber_rounded, size: 16),
                              label: Text(_showErrorReview ? 'Show Valid Table' : 'Review Errors (${_validationResult!.totalErrors})'),
                              style: TextButton.styleFrom(
                                foregroundColor: _showErrorReview ? AppColors.primarySage : AppColors.error,
                              ),
                              onPressed: () => setState(() => _showErrorReview = !_showErrorReview),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (_showErrorReview) ...[
                        _buildErrorListView(isDark),
                      ] else ...[
                        _buildValidPreviewTable(isDark),
                      ],

                      const SizedBox(height: 20),

                      if (_isImporting) ...[
                        LinearProgressIndicator(
                          value: _importProgress,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primarySage),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Importing customers... (${(_importProgress * 100).toInt()}%)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: PrimaryButton(
                                text: 'Import ${_validationResult!.validCount} Valid Customers',
                                icon: Icons.download_done_rounded,
                                onPressed: _validationResult!.validCount == 0 ? null : _executeImport,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 1,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => setState(() => _validationResult = null),
                                child: const Text('Cancel'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    // Import Complete Success State
                    if (_isImportComplete) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.cardDark : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: const BoxDecoration(
                                color: Color(0xFFE8F5E9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_rounded, color: AppColors.success, size: 40),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Import Complete',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '✓ $_importedCount customers imported and saved to your directory.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 24),
                            PrimaryButton(
                              text: 'View Customers Directory',
                              icon: Icons.people_rounded,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidPreviewTable(bool isDark) {
    final list = _validationResult!.validCustomers.take(15).toList();
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        child: const Text('No valid records found in file.', style: TextStyle(color: AppColors.error)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Full Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                Expanded(flex: 3, child: Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
              ],
            ),
          ),
          ...list.map((c) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
              ),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  Expanded(flex: 3, child: Text(c.phone, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
                ],
              ),
            );
          }),
          if (_validationResult!.validCustomers.length > 15)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '+ ${_validationResult!.validCustomers.length - 15} more valid rows will be imported',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorListView(bool isDark) {
    final allErrors = [
      ..._validationResult!.duplicateRows,
      ..._validationResult!.invalidPhoneRows,
      ..._validationResult!.invalidDataRows,
    ];

    if (allErrors.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: allErrors.length.clamp(0, 30),
        separatorBuilder: (context, index) => Divider(height: 1, color: AppColors.borderLight),
        itemBuilder: (context, index) {
          final err = allErrors[index];
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.error.withValues(alpha: 0.15),
              child: Text('${err.rowNumber}', style: const TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.bold)),
            ),
            title: Text(err.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text('${err.rawPhone} • ${err.errorReason}', style: const TextStyle(fontSize: 11.5, color: AppColors.error)),
          );
        },
      ),
    );
  }
}
