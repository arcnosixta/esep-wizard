import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../navigation/app_navigator.dart';
import '../services/payment_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../utils/whatsapp.dart';
import '../widgets/option_button.dart';
import 'new_application_screen.dart';
import 'xpayment_screen.dart';

class PaymentScreen extends StatefulWidget {
  /// Если не передан — берётся последняя заявка пользователя.
  final String? applicationId;

  const PaymentScreen({super.key, this.applicationId});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  int _selectedMethod = 0;
  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic>? _application;
  List<Map<String, dynamic>> _payments = [];
  String? _error;
  late final ConfettiController _confettiController;

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
      if (app != null) await _loadPayments();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadPayments() async {
    if (_appId.isEmpty) return;
    try {
      final payments = await PaymentService.getPaymentsForApplication(_appId);
      if (!mounted) return;
      setState(() => _payments = payments);
      // Если заявка только что подтверждена админом — подтянуть актуальный статус.
      final app = await SupabaseService.getApplication(_appId);
      if (!mounted) return;
      setState(() => _application = app);
    } catch (e) {
      debugPrint('[Payment] load payments error: $e');
    }
  }

  Future<void> _submitPayment(String method) async {
    if (_appId.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await PaymentService.createPayment(
        applicationId: _appId,
        amount: PaymentService.appraisalPrice,
        method: method,
      );
      await PaymentService.markApplicationPendingPayment(_appId);
      await _loadPayments();

      if (!mounted) return;
      setState(() => _submitting = false);
      _confettiController.play();
      await _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось оформить платёж: $e')),
      );
    }
  }

  /// Kaspi Pay (онлайн): создаём сессию через edge-функцию и открываем
  /// checkout-страницу (сейчас — демо; статус обновится через вебхук).
  Future<void> _submitKaspiOnline() async {
    if (_appId.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final checkoutUrl = await PaymentService.createKaspiSession(
        applicationId: _appId,
        amount: PaymentService.appraisalPrice,
      );
      if (!mounted) return;
      setState(() => _submitting = false);

      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (opened) {
        await _showKaspiDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть страницу оплаты')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaspi Pay: $e')),
      );
    }
  }

  Future<void> _showKaspiDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Оплата через Kaspi Pay'),
        content: const Text(
          'Открылась страница Kaspi Pay. После оплаты заявка автоматически '
          'перейдёт в статус «Оплачена» — подтверждение менеджера не нужно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSuccessDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Платёж зарегистрирован'),
        content: const Text(
          'Ожидает подтверждения менеджера. '
          'Обычно это занимает несколько минут — статус заявки обновится автоматически.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Готово'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await WhatsApp.open(
                text: 'Здравствуйте! Я оплатил(а) заявку ${PaymentService.applicationNumber(_appId)}. '
                    'Прошу подтвердить оплату.',
              );
            },
            child: const Text('Написать в WhatsApp'),
          ),
        ],
      ),
    );
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
                      'Оплата',
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
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
              _methodsSection(c),
              _paymentHistory(c),
              _submitSection(c),
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

  // ── Карточка суммы ─────────────────────────────────────────────
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

  // ── Способы оплаты ─────────────────────────────────────────────
  Widget _methodsSection(AppColors c) {
    if (_isPaid) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Способ оплаты',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border, width: 1),
              ),
              child: Column(
                children: [
                  _paymentRow(
                    context: context,
                    index: 0,
                    icon: Icons.account_balance_rounded,
                    label: 'Банковский перевод',
                    subtitle: 'На счёт ТОО «GaMa Group»',
                    color: c.accent,
                  ),
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 56),
                    color: c.divider,
                  ),
                  _paymentRow(
                    context: context,
                    index: 1,
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Kaspi Pay',
                    subtitle: 'Перевод на Kaspi — без комиссии',
                    color: const Color(0xFFE8394A),
                  ),
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 56),
                    color: c.divider,
                  ),
                  _paymentRow(
                    context: context,
                    index: 2,
                    icon: Icons.bolt_rounded,
                    label: 'Kaspi Pay (онлайн)',
                    subtitle: 'Автоподтверждение — без ожидания менеджера',
                    color: const Color(0xFFE8394A),
                  ),
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 56),
                    color: c.divider,
                  ),
                  _paymentRow(
                    context: context,
                    index: 3,
                    icon: Icons.payment_rounded,
                    label: 'XPayment',
                    subtitle: 'Онлайн-оплата через XPayment',
                    color: c.accent,
                  ),
                ],
              ),
            ),

            if (_selectedMethod == 0) ...[
              const SizedBox(height: 14),
              _bankBlock(c),
            ] else if (_selectedMethod == 1) ...[
              const SizedBox(height: 14),
              _kaspiBlock(c),
            ] else if (_selectedMethod == 2) ...[
              const SizedBox(height: 14),
              _kaspiOnlineBlock(c),
            ] else ...[
              const SizedBox(height: 14),
              _xpaymentBlock(c),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kaspiBlock(AppColors c) {
    return Container(
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
              Icon(Icons.qr_code_2_rounded, size: 20, color: c.textPrimary),
              const SizedBox(width: 10),
              Text(
                'Оплата через Kaspi',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _step(c, '1', 'Откройте приложение Kaspi'),
          _step(c, '2', 'Переводы → на счёт'),
          _step(c, '3',
              'Получатель: ${PaymentService.kaspiBusinessPhone} (ESEP)'),
          _step(c, '4', 'Сумма: ${_formatAmount(PaymentService.appraisalPrice)}'),
          _step(c, '5', 'Нажмите «Я оплатил(а)» ниже'),
          const SizedBox(height: 16),
          OptionButton(
            text: _submitting ? 'Отправка…' : 'Я оплатил(а)',
            icon: Icons.check_rounded,
            backgroundColor: const Color(0xFFE8394A),
            onTap: _submitting ? null : () => _submitPayment('kaspi'),
          ),
          const SizedBox(height: 10),
          Text(
            'После нажатия менеджер получит уведомление и подтвердит оплату. '
            'Заявка перейдёт в статус «Оплачена».',
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _kaspiOnlineBlock(AppColors c) {
    return Container(
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
              Icon(Icons.bolt_rounded, size: 20, color: const Color(0xFFE8394A)),
              const SizedBox(width: 10),
              Text(
                'Kaspi Pay — онлайн',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Оплата через Kaspi Pay с автоматическим подтверждением: '
            'после оплаты заявка сразу перейдёт в статус «Оплачена», '
            'ждать менеджера не нужно.',
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
              '⚠️ Тестовый режим: реальный Kaspi Pay подключим после договора '
              'с Kaspi. Сейчас откроется демо-страница оплаты.',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFFB45309),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          OptionButton(
            text: _submitting ? 'Отправка…' : 'Оплатить через Kaspi Pay',
            icon: Icons.bolt_rounded,
            backgroundColor: const Color(0xFFE8394A),
            onTap: _submitting ? null : () => _submitKaspiOnline(),
          ),
        ],
      ),
    );
  }

  Widget _xpaymentBlock(AppColors c) {
    return Container(
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
              Icon(Icons.payment_rounded, size: 20, color: c.accent),
              const SizedBox(width: 10),
              Text(
                'XPayment — онлайн',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Оплата через Kaspi Pay по платёжной ссылке XPayment '
            'с автоматическим подтверждением: после оплаты заявка сразу '
            'перейдёт в статус «Оплачена», ждать менеджера не нужно.',
            style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          OptionButton(
            text: 'Оплатить через XPayment',
            icon: Icons.payment_rounded,
            backgroundColor: c.accent,
            onTap: _appId.isEmpty
                ? null
                : () => AppNavigator.push(
                      context,
                      XPaymentScreen(applicationId: _appId),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _bankBlock(AppColors c) {
    return Container(
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
              Icon(Icons.account_balance_rounded,
                  size: 20, color: c.textPrimary),
              const SizedBox(width: 10),
              Text(
                'Реквизиты для перевода',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _reqRow(c, 'Получатель', 'ТОО «GaMa Group»'),
          _reqRow(c, 'БИН', '160840018855'),
          _reqRow(c, 'ИИК', 'KZ646017131000019202', copyable: true),
          _reqRow(c, 'БИК', 'HSBKKZKX'),
          _reqRow(c, 'Банк', 'АО «Народный банк Казахстана»'),
          _reqRow(c, 'Телефон', '+7 (727) 327-27-73'),
          const SizedBox(height: 16),
          OptionButton(
            text: _submitting ? 'Отправка…' : 'Я оплатил(а)',
            icon: Icons.check_rounded,
            onTap: _submitting ? null : () => _submitPayment('bank'),
          ),
          const SizedBox(height: 10),
          Text(
            'После нажатия менеджер проверит перевод и подтвердит оплату. '
            'Заявка перейдёт в статус «Оплачена».',
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _reqRow(AppColors c, String label, String value,
      {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
          ),
          Expanded(
            child: copyable
                ? SelectableText(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  )
                : Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _step(AppColors c, String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: c.surfaceLight,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              num,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, color: c.textPrimary, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  // ── История платежей ───────────────────────────────────────────
  Widget _paymentHistory(AppColors c) {
    if (_payments.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Платежи по заявке',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border, width: 1),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _payments.length; i++) ...[
                    if (i > 0)
                      Container(
                        height: 1,
                        margin: const EdgeInsets.only(left: 20),
                        color: c.divider,
                      ),
                    _paymentRowItem(c, _payments[i]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentRowItem(AppColors c, Map<String, dynamic> p) {
    final status = (p['status'] as String?) ?? 'pending';
    final paid = status == 'paid';
    final method = (p['method'] as String?) ?? 'manual';
    final amount = (p['amount'] as num?)?.toInt() ?? PaymentService.appraisalPrice;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Icon(
            paid ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
            size: 20,
            color: paid ? c.success : c.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PaymentService.methodLabel(method),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAmount(amount),
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            PaymentService.statusLabel(status),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: paid ? c.success : c.warning,
            ),
          ),
        ],
      ),
    );
  }

  // ── Нижняя кнопка (если метод не выбран — не показываем) ───────
  Widget _submitSection(AppColors c) {
    if (_isPaid || _selectedMethod == 3) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: OptionButton(
          text: _submitting
              ? 'Обработка…'
              : 'Оплатить ${_formatAmount(PaymentService.appraisalPrice)}',
          icon: Icons.lock_rounded,
          onTap: _submitting
              ? null
              : () => _submitPayment(switch (_selectedMethod) {
                    0 => 'bank',
                    1 => 'kaspi',
                    _ => 'kaspi_online',
                  }),
        ),
      ),
    );
  }

  // ── Строка выбора метода ───────────────────────────────────────
  Widget _paymentRow({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
  }) {
    final c = AppColors.of(context);
    final selected = _selectedMethod == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedMethod = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : c.textHint,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
