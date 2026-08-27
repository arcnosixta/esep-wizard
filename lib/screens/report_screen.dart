import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/report_template.dart';
import '../models/user_profile.dart';
import '../services/cms_signature_parser.dart';
import '../services/cms_signature_verifier.dart';
import '../services/ncalayer_service.dart';
import '../services/report_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/information_tile.dart';
import '../widgets/option_button.dart';
import '../widgets/case_progress_bar.dart';
import 'report_edit_screen.dart';

class ReportScreen extends StatefulWidget {
  final String? applicationId;
  final ReportData? reportData;

  const ReportScreen({super.key, this.applicationId, this.reportData});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ReportData? _reportData;
  bool _loading = false;
  bool _generating = false;
  String? _error;
  bool _isPaid = false;

  /// Фото объекта из заявки (до 10) — вставляются в PDF (Приложение «Фото»).
  List<Uint8List> _photoBytes = const [];

  /// Роль текущего пользователя: подписывать ЭЦП может только оценщик/админ.
  UserRole? _myRole;

  /// Владелец заявки (клиент) — ему принадлежит строка отчёта в БД.
  String? _ownerUserId;

  @override
  void initState() {
    super.initState();
    _loadMyRole();
    final rd = widget.reportData;
    if (rd != null) {
      _reportData = rd;
    } else if (widget.applicationId != null) {
      _loadApplicationData();
    }
  }

  Future<void> _loadMyRole() async {
    final role = await SupabaseService.getUserRole();
    if (!mounted) return;
    setState(() => _myRole = role);
  }

  /// Может ли текущий пользователь ПОДПИСЫВАТЬ отчёт (оценщик или админ).
  bool get _canSign => _myRole == UserRole.appraiser || _myRole == UserRole.admin;

  Future<void> _loadApplicationData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final appId = widget.applicationId!;
      final app = await SupabaseService.getApplication(appId);

      _isPaid = app['status'] == 'paid' || app['status'] == 'completed';
      _ownerUserId = (app['user_id'] ?? '').toString();

      // Фото объекта из заявки — для PDF (Приложение «Фото», до 10).
      final photoBytes = await SupabaseService.loadApplicationPhotos(app['photo_urls']);

      final prop = app['properties'] ?? {};
      final profile = app['profiles'] ?? {};
      final isOrg = (profile['client_type'] ?? 'person') == 'org';

      final data = await ReportService.generateReportData(
        propertyType: prop['type'] ?? 'Квартира',
        address: prop['address'] ?? '',
        area: (prop['area'] as num?)?.toDouble() ?? 0,
        rooms: prop['rooms'] ?? 0,
        floor: prop['floor'] ?? 0,
        totalFloors: prop['total_floors'] ?? 0,
        condition: prop['condition'] ?? 'Не указано',
        yearBuilt: prop['year_built'] ?? 0,
        clientName: isOrg
            ? (profile['org_name'] ?? 'Не указано')
            : (profile['full_name'] ?? 'Не указано'),
        clientIin: isOrg
            ? (profile['bin'] ?? '')
            : (profile['iin'] ?? ''),
        clientPhone: (profile['phone'] ?? '').toString(),
        clientEmail: (profile['email'] ?? '').toString(),
        clientIsOrg: isOrg,
      );

      if (mounted) {
        setState(() {
          _reportData = data == null ? null : ReportService.fillCompanyData(data);
          _photoBytes = photoBytes;
          _loading = false;

          // Восстанавливаем статус ЭЦП-подписи из БД (если отчёт уже подписан)
          final signerName = app['signer_name'] ?? '';
          final signedAtRaw = app['signed_at'];
          if (signerName.toString().isNotEmpty && signedAtRaw != null) {
            _signatureInfo = CmsSignatureInfo(
              signerName: signerName.toString(),
              signerIin: (app['signer_iin'] ?? '').toString(),
              organization: '',
            );
            _signedAt = DateTime.tryParse(signedAtRaw.toString());
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Ошибка: $e';
        });
      }
    }
  }

  /// Открыть экран редактирования отчёта (доступно оценщику/админу).
  Future<void> _editReport() async {
    final data = _reportData;
    if (data == null) return;
    final edited = await Navigator.push<ReportData>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportEditScreen(
          data: data,
          applicationId: widget.applicationId,
          initialPhotoUrls: _reportData?.photoUrls ?? const [],
        ),
      ),
    );
    if (edited != null && mounted) {
      setState(() => _reportData = edited);
      _showSuccessSnack('Данные отчёта обновлены');
    }
  }

  Future<void> _downloadPdf() async {
    if (_reportData == null) return;

    // Вариант А: до оплаты скачивание официального PDF заблокировано.
    if (!_isPaid) {
      _showPreviewLockedDialog();
      return;
    }

    setState(() => _generating = true);

    try {
      final pdfBytes = await ReportService.generatePdf(
        _reportData!,
        signature: _signatureInfo,
        photos: _photoBytes,
      );

      if (mounted) {
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
          name: 'ESEP_Report_${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка генерации PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _showPreviewLockedDialog() async {
    final c = AppColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отчёт станет доступен после оплаты'),
        content: SingleChildScrollView(
          child: Text(
            'Сейчас вы видите предварительный вариант отчёта — он не имеет '
            'юридической силы. После оплаты оценщик подготовит и подпишет '
            'официальный отчёт, который можно будет скачать.',
            style: TextStyle(color: c.textSecondary, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Понятно', style: TextStyle(color: c.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _sharePdf() async {
    if (_reportData == null) return;

    setState(() => _generating = true);

    try {
      // До оплаты можно поделиться только ПРЕДВАРИТЕЛЬНЫМ вариантом
      // (с водяным знаком) — официальный PDF доступен после оплаты.
      final pdfBytes = await ReportService.generatePdf(
        _reportData!,
        preview: !_isPaid,
        signature: _isPaid ? _signatureInfo : null,
        photos: _photoBytes,
      );
      await Printing.sharePdf(bytes: pdfBytes, filename: 'report.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ============================================
  // ЭЦП-ПОДПИСЬ (NCALayer + CMS)
  // ============================================

  static const _ezSignerUrl = 'https://ezsigner.kz/#!/signCMS';
  static const _ncalayerUrl = 'https://pki.gov.kz';

  CmsSignatureInfo? _signatureInfo;
  DateTime? _signedAt;
  bool _signing = false;
  Uint8List? _cmsBytes;

  Future<void> _signWithNcalayer() async {
    if (!_canSign) {
      _showErrorSnack('Подписывать отчёт может только оценщик');
      return;
    }
    final c = AppColors.of(context);
    setState(() => _signing = true);
    try {
      final available = await NcalayerService.isAvailable();
      if (!mounted) return;
      if (!available) {
        await _showNcalayerMissingDialog();
        return;
      }

      final result = await NcalayerService.signDocument();
      if (!mounted) return;

      if (result.success) {
        await _showSignedDialog(result.message ?? '');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Ошибка подписи',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: c.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  Future<void> _showNcalayerMissingDialog() async {
    final c = AppColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('NCALayer не запущен'),
        content: SingleChildScrollView(
          child: Text(
            'Для подписи ЭЦП нужна программа NCALayer от НУЦ РК '
            '(Windows, macOS или Linux).\n\n'
            '1. Скачайте и установите NCALayer с pki.gov.kz\n'
            '2. Запустите программу\n'
            '3. Вернитесь сюда и нажмите «Подписать ЭЦП»\n\n'
            'Или подпишите документ вручную на ezsigner.kz '
            'и загрузите .cms файл в отчёт.',
            style: TextStyle(color: c.textSecondary, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Позже', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrl(_ncalayerUrl);
            },
            child: const Text('Скачать NCALayer'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrl(_ezSignerUrl);
            },
            child: Text('Открыть ezSigner',
                style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showSignedDialog(String savedPath) async {
    final c = AppColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Документ подписан'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ЭЦП-подпись сохранена:',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                savedPath,
                style: TextStyle(
                    color: c.textPrimary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              Text(
                'Загрузите .cms файл в отчёт, чтобы сохранить подпись в ESEP.',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Позже', style: TextStyle(color: c.textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _uploadCms();
            },
            child: const Text('Загрузить .cms'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadCms() async {
    if (!_canSign) {
      _showErrorSnack('Подписывать отчёт может только оценщик');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['cms'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await file.xFile.readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        _showErrorSnack('Не удалось прочитать файл');
        return;
      }

      final info = CmsSignatureParser.parse(bytes);
      if (info == null || !info.hasName) {
        _showErrorSnack(
            'Не удалось распознать ЭЦП-подпись. Убедитесь, что это .cms файл.');
        return;
      }

      _cmsBytes = bytes;

      final appId = widget.applicationId;
      if (appId == null) {
        if (!mounted) return;
        setState(() {
          _signatureInfo = info;
          _signedAt = DateTime.now();
        });
        _showSuccessSnack('Подпись распознана: ${info.signerName}');
        return;
      }

      await SupabaseService.attachCmsSignature(
        applicationId: appId,
        cmsBytes: bytes,
        signerName: info.signerName,
        signerIin: info.signerIin,
      );

      // Отмечаем отчёт как подписанный + встраиваем подпись в PDF
      await _markReportSigned(info);

      if (!mounted) return;
      setState(() {
        _signatureInfo = info;
        _signedAt = DateTime.now();
      });
      _showSuccessSnack('ЭЦП-подпись сохранена: ${info.signerName}');
    } catch (e) {
      _showErrorSnack('Ошибка загрузки: $e');
    }
  }

  Future<void> _verifySignature() async {
    if (!_canSign) {
      _showErrorSnack('Проверка подписи доступна оценщику');
      return;
    }
    final c = AppColors.of(context);
    final bytes = _cmsBytes;
    if (bytes == null) {
      _showErrorSnack(
          'Сначала загрузите .cms подпись (или подпишите через NCALayer)');
      return;
    }

    final result = CmsSignatureVerifier.verify(bytes);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.verified
                  ? Icons.verified_rounded
                  : Icons.gpp_maybe_rounded,
              color: result.verified ? c.success : c.warning,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(result.verified ? 'Подпись действительна' : 'Проверка'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.message,
                style: TextStyle(
                    color: result.verified ? c.textPrimary : c.warning,
                    fontSize: 13.5,
                    height: 1.4),
              ),
              if (result.signer != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Подписант: ${result.signer!.signerName}',
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                ),
                if (result.signer!.signerIin.isNotEmpty)
                  Text(
                    'ИИН: ${result.signer!.signerIin}',
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                'Проверка цепочки сертификатов НУЦ — на ezsigner.kz/#!/checkCMS',
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Закрыть', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrl('https://ezsigner.kz/#!/checkCMS');
            },
            child: Text('Проверить на ezSigner', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
  }

  void _openUrl(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    final c = AppColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: c.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    final c = AppColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: c.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatDate(DateTime d) => DateFormat('d MMM yyyy, HH:mm').format(d);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    if (_loading || _generating) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: c.accent, strokeWidth: 2),
                const SizedBox(height: 16),
                Text(
                  _generating ? 'Генерация PDF...' : 'Анализ данных...',
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 56, color: c.error),
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Назад'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = _reportData;
    if (data == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Center(
            child: Text('Нет данных', style: TextStyle(color: c.textSecondary)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Отчёт об оценке',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ИТОГОВАЯ СТОИМОСТЬ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.formattedPrice,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: c.textPrimary,
                          letterSpacing: -1,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: c.accent.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                data.confidencePercent,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Уверенность оценки',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                CaseProgressBar(progress: data.confidence),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Диапазон оценки',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            data.formattedPriceRangeLow,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            data.formattedPriceRangeHigh,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CaseProgressBar(
                        progress: (data.estimatedPrice - data.priceRangeLow) /
                            (data.priceRangeHigh - data.priceRangeLow),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Text(
                  'Данные объекта',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    InformationTile(
                      content: '${data.area.round()}',
                      name: 'Площадь м²',
                      icon: Icons.square_foot_rounded,
                      valueColor: c.textPrimary,
                    ),
                    InformationTile(
                      content: '${data.rooms}',
                      name: 'Комнаты',
                      icon: Icons.meeting_room_rounded,
                      valueColor: c.info,
                    ),
                    InformationTile(
                      content: '${data.floor}',
                      name: 'Этаж',
                      icon: Icons.layers_rounded,
                      valueColor: c.warning,
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border, width: 1),
                  ),
                  child: Column(
                    children: [
                      infoRow(context, 'Адрес', data.address),
                      divider(context),
                      infoRow(context, 'Дата оценки', data.appraisalDate),
                      divider(context),
                      infoRow(context, 'Тип', data.propertyType),
                      divider(context),
                      infoRow(context, 'Цена за м²', data.formattedPricePerMeter),
                    ],
                  ),
                ),
              ),
            ),

            if (data.comparables.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Text(
                    'Аналоги (${data.comparables.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final comp = data.comparables[index];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.border, width: 1),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(comp.address,
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary),
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text('${comp.area.round()} м² · ${comp.source}',
                                      style: TextStyle(fontSize: 11, color: c.textSecondary)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(comp.formattedPrice,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.accent)),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: data.comparables.length,
                ),
              ),
            ],

            if (data.recommendations.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Text(
                    'Рекомендации',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border, width: 1),
                    ),
                    child: Column(
                      children: data.recommendations
                          .map((r) => _recItem(
                                context,
                                _iconFromString(r.icon),
                                r.title,
                                r.description,
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Column(
                  children: [
                    // Плашка статуса: предварительный / официальный
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isPaid
                            ? c.success.withValues(alpha: 0.1)
                            : c.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isPaid
                              ? c.success.withValues(alpha: 0.4)
                              : c.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isPaid
                                ? Icons.verified_rounded
                                : Icons.info_outline_rounded,
                            color: _isPaid ? c.success : c.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isPaid
                                  ? 'Отчёт оплачен и действителен. Можно скачать официальный PDF.'
                                  : 'Предварительный отчёт — не имеет юридической силы. '
                                      'Официальный станет доступен после оплаты.',
                              style: TextStyle(
                                fontSize: 13,
                                color: _isPaid ? c.textPrimary : c.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OptionButton(
                            text: 'Скачивание PDF',
                            icon: Icons.lock_rounded,
                            onTap: null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OptionButton(
                            text: 'Поделиться',
                            icon: Icons.share_rounded,
                            backgroundColor: Colors.transparent,
                            textColor: c.accent,
                            onTap: _sharePdf,
                          ),
                        ),
                      ],
                    ),
                    // Оценщик/админ может поправить данные отчёта перед подписанием.
                    if (_canSign) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OptionButton(
                          text: 'Редактировать отчёт',
                          icon: Icons.edit_rounded,
                          backgroundColor: c.surfaceLight,
                          textColor: c.accent,
                          onTap: _editReport,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ЭЦП-подпись отчёта (NCALayer / ezSigner)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: _buildEcpBlock(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEcpBlock(BuildContext context) {
    final c = AppColors.of(context);
    final info = _signatureInfo;
    final signed = info != null && _signedAt != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: signed ? c.success.withValues(alpha: 0.5) : c.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                signed ? Icons.verified_rounded : Icons.lock_outline_rounded,
                color: signed ? c.success : c.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  signed ? 'Отчёт подписан ЭЦП' : 'ЭЦП-подпись отчёта',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (signed) ...[
            Text(
              'Подписал: ${info.signerName}',
              style: TextStyle(fontSize: 13, color: c.textPrimary),
            ),
            if (info.signerIin.isNotEmpty)
              Text(
                'ИИН: ${info.signerIin}',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            Text(
              'Дата: ${_formatDate(_signedAt!)}',
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            const SizedBox(height: 10),
          ] else
            Text(
              _canSign
                  ? 'Подпишите PDF-отчёт своей ЭЦП (NCALayer, десктоп) или '
                      'загрузите готовый .cms файл с ezsigner.kz.'
                  : 'После оплаты оценщик подпишет официальный отчёт ЭЦП — '
                      'статус подписи появится здесь.',
              style: TextStyle(
                  fontSize: 13, color: c.textSecondary, height: 1.4),
            ),
          if (_canSign) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OptionButton(
                    text: _signing ? 'Подписание…' : 'Подписать ЭЦП',
                    icon: Icons.draw_rounded,
                    onTap: _signing ? null : _signWithNcalayer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OptionButton(
                    text: 'Загрузить .cms',
                    icon: Icons.upload_file_rounded,
                    backgroundColor: Colors.transparent,
                    textColor: c.accent,
                    onTap: _uploadCms,
                  ),
                ),
              ],
            ),
            if (signed) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OptionButton(
                  text: 'Проверить подпись',
                  icon: Icons.verified_user_rounded,
                  backgroundColor: c.surfaceLight,
                  textColor: c.accent,
                  onTap: _verifySignature,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Отметить отчёт как подписанный и встроить ЭЦП-подпись в PDF.
  Future<void> _markReportSigned(CmsSignatureInfo info) async {
    try {
      final appId = widget.applicationId;
      if (appId == null || _reportData == null) return;

      // 1. Обновляем запись в таблице reports
      final report = await SupabaseService.getReportForApplication(appId);
      Map<String, dynamic>? created;
      if (report == null) {
        // Отчёта ещё нет — создаём черновик, потом подписываем.
        // user_id отчёта = владелец заявки (клиент), а не оценщик.
        created = await SupabaseService.createReport(
          applicationId: appId,
          ownerId: _ownerUserId,
          reportNumber: await ReportService.nextReportNumber(),
        );
        await SupabaseService.markReportSigned(
          created['id'].toString(),
          signerName: info.signerName,
          signerIin: info.signerIin,
        );
      } else {
        await SupabaseService.markReportSigned(
          report['id'].toString(),
          signerName: info.signerName,
          signerIin: info.signerIin,
        );
      }

      // 2. Генерируем официальный PDF со встроенной подписью и загружаем
      final pdfBytes = await ReportService.generatePdf(
        _reportData!,
        signature: info,
        photos: _photoBytes,
      );
      final url = await ReportService.uploadReportPdf(pdfBytes, appId);

      if (url != null) {
        // Обновляем отчёт (если создали черновик выше — берём его id)
        final reportId = (report ?? created)?['id']?.toString();
        if (reportId != null) {
          await SupabaseService.updateReport(
            reportId,
            fileUrl: url,
            reportData: _reportData!.toJson(),
          );
        }
      }

      // Работа оценщика по заявке завершена: in_progress -> completed.
      // (Раньше это делала фейковая signApplication-заглушка.)
      await SupabaseService.updateApplicationStatus(appId, 'completed');
    } catch (e) {
      debugPrint('[Report] markReportSigned error: $e');
    }
  }

  Widget _recItem(BuildContext context, IconData icon, String title, String subtitle) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.accent, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFromString(String icon) {
    switch (icon) {
      case 'trending_up':
        return Icons.trending_up_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'location':
        return Icons.location_on_rounded;
      case 'info':
        return Icons.info_outline_rounded;
      default:
        return Icons.lightbulb_outline_rounded;
    }
  }
}
