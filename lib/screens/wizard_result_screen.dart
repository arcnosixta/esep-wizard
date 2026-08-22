import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../theme/app_colors.dart';
import '../../services/report_service.dart';

/// Финальный экран wizard: сводка собранных данных.
/// Можно вернуться назад (pop) или продолжить к отчёту/оплате.
class WizardResultScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const WizardResultScreen({super.key, required this.data});

  @override
  State<WizardResultScreen> createState() => _WizardResultScreenState();
}

class _WizardResultScreenState extends State<WizardResultScreen> {
  bool _generating = false;

  Future<void> _generatePdf() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final data = widget.data;
      final pdfBytes = await ReportService.generateReport(data);
      if (!mounted) return;
      final dir = await getApplicationDocumentsDirectory();
      final safeTs = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'ESEP_отчёт_$safeTs.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF сохранён: ${file.path} (${pdfBytes.length} байт)'),
          duration: const Duration(seconds: 5),
        ),
      );
      if (kIsWeb) {
        await Printing.layoutPdf(
          onLayout: (_) async => pdfBytes,
          name: fileName,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка генерации: $e')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final propertyType = (widget.data['propertyType'] as int?) ?? 0;
    final types = const [
      'Квартира',
      'Дом',
      'Земля',
      'Авто',
      'Коммерция',
      'Другое',
    ];
    final typeName = types[propertyType.clamp(0, types.length - 1)];

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Результат'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, size: 72, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              'Отчёт готов',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              typeName,
              style: TextStyle(fontSize: 18, color: c.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Официальный отчёт с ЭЦП подписью',
              style: TextStyle(fontSize: 15, color: c.textSecondary),
            ),
            const SizedBox(height: 32),
            if (_generating)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: _generatePdf,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Скачать PDF'),
              ),
          ],
        ),
      ),
    );
  }
}
