import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../navigation/app_navigator.dart';
import '../services/payment_service.dart';
import '../services/supabase_service.dart';
import '../services/xpayment_service.dart';
import '../theme/app_colors.dart';
import '../widgets/option_button.dart';
import 'new_application_screen.dart';

class XPaymentScreen extends StatefulWidget {
  /// Если не передан — берётся последняя заявка пользователя.
  final String? applicationId;

  const XPaymentScreen({super.key, this.applicationId});

  @override
  State<XPaymentScreen> createState() => _XPaymentScreenState();

}

class _XPaymentScreenState extends State<XPaymentScreen> {
  bool _loading = true;
  bool _submitting = false;
  bool _waiting = false;
  Map<String, dynamic>? _application;
  String? _error;
  int _pollCount = 0;
  Timer? _pollTimer;
  late final ConfettiController _confettiController;

  static const int _maxPolls = 60;

  String get _appId => (_application?['id'] as String?) ?? '';
  bool get _isPaid => _application?['status'] == 'paid';

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? app;
      if (widget.applicationId != null) {
        app = await SupabaseService.getApplication(widget.applicationId!);
      } else {
        final apps = await SupabaseService.getApplications();
        if (apps.isNotEmpty) app = apps.first;
      }
      if (!mounted) return;
      setState(() {
        _application = app;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startPayment() async {
    if (_appId.isEmpty || _submitting || _waiting) return;
    setState(() => _submitting = true);
    try {
      final checkoutUrl = await XPaymentService.createCheckout(
        applicationId: _appId,
        amount: PaymentService.appraisalPrice,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _waiting = true;
        _pollCount = 0;
      });

      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (opened) {
        _startPolling();
      } else {
        setState(() => _waiting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть страницу оплаты')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('XPayment: $e')),
      );
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_isPaid || !_waiting) return;
    _pollCount++;
    if (_pollCount > _maxPolls) {
      _pollTimer?.cancel();
      return;
    }
    await XPaymentService.syncStatus(_appId);
    try {
      final app = await SupabaseService.getApplication(_appId);
      if (!mounted) return;
      setState(() => _application = app);
      if (_isPaid) {
        _pollTimer?.cancel();
        setState(() => _waiting = false);
        _confettiController.play();
      }
    } catch (_) {}
  }

  String _formatAmount(int amount) {
    final s = amount.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]} ',
        );
    return '$s ₸';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          SafeArea(
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
                          'XPayment',
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
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child:
                        Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_error != null && _application == null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 48, color: c.error),
                            const SizedBox(height: 12),
                            const Text('Не удалось загрузить данные'),
                            const SizedBox(height: 16),
                            OptionButton(
                              text: 'Повторить',
                              icon: Icons.refresh_rounded,
                              onTap: _load,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (_application == null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_rounded,
                                size: 48, color: c.textHint),
                            const SizedBox(height: 12),
                            const Text(
                              'Нет заявок для оплаты.\nСначала получите официальный '
                              'отчёт через ИИ-анализ.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            OptionButton(
                              text: 'Рассчитать стоимость',
                              icon: Icons.calculate_rounded,
                              onTap: () => AppNavigator.push(
                                  context, const NewApplicationScreen()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  _amountCard(c),
                  _xpaymentBlock(c),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: -math.pi / 2,
              emissionFrequency: 0.08,
              numberOfParticles: 20,
              gravity: 0.25,
              maxBlastForce: 14,
              minBlastForce: 6,
              particleDrag: 0.4,
              colors: [
                c.accent,
                c.accentLight,
                c.gold,
                c.success,
                c.warning,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountCard(AppColors c) {
    final number = PaymentService.applicationNumber(_appId);
    return SliverToBoxAdapter(
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
                _isPaid ? 'ОПЛАЧЕНО' : 'СУММА К ОПЛАТЕ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: _isPaid ? c.success : c.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _formatAmount(PaymentService.appraisalPrice),
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: c.textPrimary,
                  letterSpacing: -1.5,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Оценка · Заявка $number',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
              if (_isPaid) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 18, color: c.success),
                    const SizedBox(width: 8),
                    Text(
                      'Оплата прошла успешно',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.success),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _xpaymentBlock(AppColors c) {
    if (_isPaid) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            children: [
              OptionButton(
                text: 'Вернуться к заявке',
                icon: Icons.arrow_back_rounded,
                backgroundColor: c.surface,
                textColor: c.textPrimary,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 20, color: const Color(0xFF00B14F)),
                  const SizedBox(width: 10),
                  Text(
                    'Онлайн-оплата через XPayment',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Откроется платёжная ссылка Kaspi Pay. После оплаты заявка '
                'автоматически перейдёт в статус «Оплачена» — подтверждение '
                'менеджера не нужно.',
                style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8394A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '⚠️ Ссылка активна ~5 минут. Не закрывайте этот экран, пока '
                  'не завершите оплату — статус обновится автоматически.',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFFB45309),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OptionButton(
                text: _submitting
                    ? 'Создание платежа…'
                    : _waiting
                        ? 'Ожидание оплаты…'
                        : 'Оплатить ${_formatAmount(PaymentService.appraisalPrice)}',
                icon: Icons.lock_rounded,
                backgroundColor: const Color(0xFF00B14F),
                onTap: _submitting || _waiting ? null : _startPayment,
              ),
              if (_waiting) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Проверяем статус оплаты…',
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    _pollTimer?.cancel();
                    setState(() => _waiting = false);
                  },
                  child: const Text('Отменить ожидание'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
