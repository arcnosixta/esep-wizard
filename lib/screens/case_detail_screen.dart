import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/report_service.dart';
import '../widgets/assistant_tab_bar.dart';
import '../utils/formatters.dart';
import '../widgets/information_tile.dart';
import '../widgets/option_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/case_progress_bar.dart';
import '../navigation/app_navigator.dart';
import '../services/supabase_service.dart';
import 'payment_screen.dart';
import 'report_screen.dart';

class CaseDetailScreen extends StatelessWidget {
  final Map<String, dynamic> application;

  const CaseDetailScreen({super.key, required this.application});

  /// Есть ли официальный (оплаченный) отчёт для скачивания.
  Future<String?> _officialReportUrl(String applicationId) async {
    try {
      final report = await SupabaseService.getReportForApplication(applicationId);
      if (report == null) return null;
      final status = report['status'] ?? '';
      // Официальный PDF доступен только после оплаты И подписи
      if (status != 'paid' && status != 'signed') return null;
      final stored = (report['file_url'] ?? '').toString();
      if (stored.isEmpty) return null;
      // Бакет приватный: путь → временная signed-ссылка (1 час).
      return SupabaseService.getReportPdfUrl(stored);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final prop = application['properties'] as Map<String, dynamic>? ?? {};
    final id = (application['id'] ?? '').toString();
    final status = application['status'] ?? 'new';
    final type = prop['type'] ?? '';
    final address = prop['address'] ?? '';
    final area = (prop['area'] as num?)?.toDouble() ?? 0;
    final rooms = prop['rooms'] as int?;
    final floor = prop['floor'] as int?;
    final totalFloors = prop['total_floors'] as int?;
    final estimated = application['estimated_price'] as num?;
    final createdAt = application['created_at'] as String?;

    final progress = switch (status) {
      'new' => 0.15,
      'pending_payment' => 0.4,
      'in_progress' => 0.55,
      'completed' => 1.0,
      'paid' => 1.0,
      'rejected' => 0.0,
      _ => 0.15,
    };

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
                    Expanded(
                      child: AssistantTabBar(
                        activeTab: AssistantTab.wizard,
                        onTabChanged: (_) {},
                      ),
                    ),
                    StatusBadge(
                      status: badgeStatusFromKey(status),
                      label: statusLabel(context, status),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Container(
                  padding: const EdgeInsets.all(20),
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
                      Container(
                        width: double.infinity,
                        height: 160,
                        decoration: BoxDecoration(
                          color: c.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(
                            propertyTypeIcon(type),
                            size: 48,
                            color: propertyTypeColor(context, type),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        propertyTypeLabel(context, type),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style: TextStyle(
                          fontSize: 14,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      CaseProgressBar(progress: progress),
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Text(
                  'Детали объекта',
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
                      content: area > 0 ? '${area.round()}' : '—',
                      name: 'Площадь м²',
                      icon: Icons.square_foot_rounded,
                      valueColor: c.textPrimary,
                    ),
                    InformationTile(
                      content: rooms != null ? '$rooms' : '—',
                      name: 'Комнаты',
                      icon: Icons.meeting_room_rounded,
                      valueColor: c.info,
                    ),
                    InformationTile(
                      content: floor != null
                          ? totalFloors != null
                              ? '$floor/$totalFloors'
                              : '$floor'
                          : '—',
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
                      infoRow(context, 'Тип', propertyTypeLabel(context, type)),
                      divider(context),
                      infoRow(context, 'Адрес', address),
                      if (estimated != null) ...[
                        divider(context),
                        infoRow(
                          context,
                          'Стоимость',
                          formatTenge(estimated.toDouble()),
                          highlight: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Text(
                  'История',
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
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border, width: 1),
                  ),
                  child: Column(
                    children: [
                      _statusStep(
                        context: context,
                        title: 'ИИ-анализ пройден',
                        time: _formatDate(createdAt),
                        done: true,
                        isFirst: true,
                      ),
                      _statusStep(
                        context: context,
                        title: 'В работе у оценщика',
                        done: status == 'in_progress' ||
                            status == 'completed' ||
                            status == 'paid',
                      ),
                      _statusStep(
                        context: context,
                        title: 'Отчёт готов',
                        done: status == 'completed' || status == 'paid',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Column(
                  children: [
                    if (status == 'pending_payment' ||
                        status == 'new' ||
                        status == 'in_progress') ...[
                      OptionButton(
                        text: 'Оплатить',
                        icon: Icons.payments_rounded,
                        onTap: () => AppNavigator.push(
                          context,
                          PaymentScreen(applicationId: id),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OptionButton(
                      text: 'Сформировать отчёт',
                      icon: Icons.description_rounded,
                      backgroundColor: AppColors.of(context).surface,
                      textColor: AppColors.of(context).textPrimary,
                      onTap: () async {
                        try {
                          final c = AppColors.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          final report = await SupabaseService.getReportForApplication(id);
                          final data = await ReportService.generateReportData(
                            propertyType: prop['type'] ?? 'apartment',
                            address: address,
                            area: area,
                            rooms: rooms ?? 1,
                            floor: floor ?? 1,
                            totalFloors: totalFloors ?? 1,
                            condition: prop['condition'] ?? 'cosmetic',
                            yearBuilt: (prop['year_built'] as int?) ?? DateTime.now().year,
                            clientName: application['client_name'] ?? '',
                            clientIin: application['client_iin'] ?? '',
                          );
                          if (data == null) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: const Text('Не удалось сформировать отчёт'),
                                backgroundColor: c.error,
                              ),
                            );
                            return;
                          }
                          final reportData = await SupabaseService.createReport(
                            applicationId: id,
                            reportData: data.toJson(),
                          );
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text('Отчёт сформирован'),
                              backgroundColor: c.success,
                            ),
                          );
                        } catch (e) {
                          final c = AppColors.of(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Ошибка: $e'),
                              backgroundColor: c.error,
                            ),
                          );
                        }
                      },
                    ),
                    OptionButton(
                      text: 'Посмотреть отчёт',
                      icon: Icons.description_rounded,
                      backgroundColor: AppColors.of(context).surface,
                      textColor: AppColors.of(context).textPrimary,
                      onTap: () => AppNavigator.push(
                        context,
                        ReportScreen(applicationId: id),
                      ),
                    ),
                    if (status == 'paid' || status == 'completed') ...[
                      const SizedBox(height: 12),
                      OptionButton(
                        text: 'Скачивание PDF',
                        icon: Icons.lock_rounded,
                        onTap: null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $hh:$mm';
  }

  Widget _statusStep({
    required BuildContext context,
    required String title,
    String? time,
    bool done = false,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final c = AppColors.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? c.accent : c.muted,
                shape: BoxShape.circle,
              ),
              child: done
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: c.textHint,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
            ),
            if (!isLast)
              Container(
                width: 1.5,
                height: 32,
                color: done ? c.accent : c.muted,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: done
                        ? c.textPrimary
                        : c.textSecondary,
                  ),
                ),
                if (time != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: TextStyle(
                        fontSize: 12, color: c.textHint),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
