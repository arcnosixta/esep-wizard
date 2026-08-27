import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/case_progress_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_badge.dart';
import '../widgets/aurora_background.dart';
import '../widgets/scroll_reveal.dart';
import '../widgets/assistant_tab_bar.dart';
import '../l10n/app_strings.dart';
import '../navigation/app_navigator.dart';
import '../services/supabase_service.dart';
import 'ai_chat_screen.dart';
import 'case_detail_screen.dart';
import 'cases_list_screen.dart';
import 'new_application_screen.dart';
import 'payment_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onDocumentsTap;

  /// Ключ для кнопки «Новая заявка» — цель экскурсии по приложению.
  final GlobalKey? newAppKey;

  const HomeScreen({super.key, this.onDocumentsTap, this.newAppKey});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recentApps = [];
  bool _loading = true;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        SupabaseService.getApplications(),
        SupabaseService.getProfile(),
      ]);
      if (mounted) {
        final profile = results[1] as Map<String, dynamic>?;
        setState(() {
          _recentApps = (results[0] as List<Map<String, dynamic>>)
              .take(3)
              .toList();
          _userName = (profile?['full_name'] ?? '').toString().split(' ').first;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          const AuroraBackground(),
          SafeArea(
        child: Column(
          children: [
            AssistantTabBar(activeTab: AssistantTab.wizard, onTabChanged: (_) {}),
            const Divider(height: 1),
            Expanded(
              child: RefreshIndicator(
          onRefresh: _loadData,
          color: c.accent,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              // ── Шапка: приветствие + аватар ─────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${greeting(context)},',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _userName.isNotEmpty ? _userName : 'ESEP',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () =>
                            AppNavigator.push(context, const ProfileScreen()),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [c.accent, c.accentLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: c.accent.withValues(alpha: 0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _userName.isNotEmpty
                                  ? _userName[0].toUpperCase()
                                  : 'E',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.08),
                ),
              ),

              // ── Hero-карточка: текущая заявка ───────────────────────
              if (!_loading && _recentApps.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                    child: ScrollReveal(
                      delay: 100.ms,
                      child: AppCard(
                      padding: const EdgeInsets.all(20),
                      onTap: () => AppNavigator.push(
                          context,
                          CaseDetailScreen(
                              application: _recentApps.first)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                s.homeCurrentApplication,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: c.textSecondary,
                                ),
                              ),
                              StatusBadge(
                                status: badgeStatusFromKey(
                                  _recentApps.first['status'] ?? 'new',
                                ),
                                label: statusLabel(
                                  context,
                                  _recentApps.first['status'] ?? 'new',
                                ),
                                small: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            caseNumber(
                              (_recentApps.first['id'] ?? '').toString(),
                            ),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _buildCaseSubtitle(_recentApps.first),
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          CaseProgressBar(
                            progress: _getProgress(
                              _recentApps.first['status'] ?? 'new',
                            ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),
                ),

              // ── Быстрые действия ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                  child: Text(
                    s.homeContinueWork,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ).animate(delay: 200.ms).fadeIn(duration: 350.ms),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: KeyedSubtree(
                          key: widget.newAppKey,
                          child: _quickAction(
                            Icons.calculate_rounded,
                            s.homeNewApplication,
                            c.accent,
                            () => AppNavigator.push(
                                context, const NewApplicationScreen()),
                          ),
                        ).animate(delay: 250.ms)
                            .fadeIn(duration: 350.ms)
                            .slideY(begin: 0.15),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _quickAction(
                          Icons.description_rounded,
                          s.homeDocuments,
                          c.warning,
                          widget.onDocumentsTap ?? () {},
                        ).animate(delay: 320.ms)
                            .fadeIn(duration: 350.ms)
                            .slideY(begin: 0.15),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _quickAction(
                          Icons.payments_rounded,
                          s.homePayment,
                          c.success,
                          () => AppNavigator.push(
                              context, const PaymentScreen()),
                        ).animate(delay: 390.ms)
                            .fadeIn(duration: 350.ms)
                            .slideY(begin: 0.15),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _quickAction(
                          Icons.auto_awesome_rounded,
                          s.homeEvaluate,
                          c.gold,
                          () => AppNavigator.push(
                              context, const AiChatScreen()),
                        ).animate(delay: 460.ms)
                            .fadeIn(duration: 350.ms)
                            .slideY(begin: 0.15),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Недавние заявки ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        s.homeRecentApplications,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => AppNavigator.push(
                          context,
                          const CasesListScreen(),
                        ),
                        child: Text(
                          s.homeAll,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: c.accent,
                          ),
                        ),
                      ),
                    ],
                  ).animate(delay: 500.ms).fadeIn(duration: 350.ms),
                ),
              ),

              _loading
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: c.accent, strokeWidth: 2),
                        ),
                      ),
                    )
                  : _recentApps.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: EmptyState(
                              icon: Icons.folder_open_rounded,
                              title: s.homeNoApplications,
                            ),
                          ),
                        )
                      : SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: c.border, width: 1),
                              ),
                               child: Column(
                                children: [
                                  ..._recentApps.map((app) {
                                    final prop = app['properties'];
                                    final propType =
                                        prop != null ? (prop['type'] ?? '') : '';
                                    final address = prop != null
                                        ? (prop['address'] ?? '')
                                        : '';
                                    final area = prop != null
                                        ? '${prop['area'] ?? 0} м²'
                                        : '';
                                    final status = app['status'] ?? 'new';
                                    final detail = area.isNotEmpty
                                        ? '$area · $address'
                                        : address;

                                    return ScrollReveal(
                                      delay: 80.ms *
                                          _recentApps.indexOf(app),
                                      duration: 300.ms,
                                      slideFrom: 0.08,
                                      child: _RecentAppTile(
                                        app: app,
                                        propType: propType,
                                        detail: detail,
                                        status: status,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 32),
              ),
            ],
          ),
        ),
        ),
      ],
    ),
    ),
  ],
  ),
);
  }

  String _buildCaseSubtitle(Map<String, dynamic> app) {
    final prop = app['properties'];
    if (prop == null) return '';
    final type = propertyTypeLabel(context, prop['type'] ?? '');
    final address = prop['address'] ?? '';
    return '$type · $address';
  }

  double _getProgress(String status) {
    return switch (status) {
      'new' => 0.15,
      'in_progress' => 0.55,
      'completed' => 1.0,
      'paid' => 1.0,
      'rejected' => 0.0,
      _ => 0.15,
    };
  }

  Widget _quickAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    final c = AppColors.of(context);
    return _HoverCard(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border, width: 1),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка заявки в списке «Недавние»: hover-подсветка.
class _RecentAppTile extends StatefulWidget {
  final Map<String, dynamic> app;
  final String propType;
  final String detail;
  final String status;

  const _RecentAppTile({
    required this.app,
    required this.propType,
    required this.detail,
    required this.status,
  });

  @override
  State<_RecentAppTile> createState() => _RecentAppTileState();
}

class _RecentAppTileState extends State<_RecentAppTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => AppNavigator.push(
            context, CaseDetailScreen(application: widget.app)),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          color: _hovered
              ? c.accent.withValues(alpha: 0.03)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '#${(widget.app['id'] ?? '').toString().substring(0, 4).toUpperCase()}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      propertyTypeLabel(context, widget.propType),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.detail,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusBadge(
                status: badgeStatusFromKey(widget.status),
                label: statusLabel(context, widget.status),
                small: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка с hover-подъёмом и press-сжатием (для быстрых действий).
class _HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _HoverCard({required this.child, required this.onTap});

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(
            0.0,
            _pressed ? 1.0 : (_hovered ? -2.0 : 0.0),
            0.0,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
