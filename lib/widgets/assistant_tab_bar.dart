import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum AssistantTab { wizard, report, aiChat }

class AssistantTabBar extends StatelessWidget {
  final AssistantTab activeTab;
  final ValueChanged<AssistantTab> onTabChanged;
  final Map<String, dynamic>? wizardData;

  const AssistantTabBar({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    this.wizardData,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Row(
        children: [
          _buildTab(context, AssistantTab.wizard, 'Wizard', Icons.auto_fix_high_rounded),
          const SizedBox(width: 10),
          _buildTab(context, AssistantTab.report, 'Отчёт', Icons.description_rounded),
          const SizedBox(width: 10),
          _buildTab(context, AssistantTab.aiChat, 'ИИ-чат', Icons.auto_awesome_rounded),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, AssistantTab tab, String label, IconData icon) {
    final c = AppColors.of(context);
    final isActive = activeTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => onTabChanged(tab),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? c.accent.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? c.accent : c.border, width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isActive ? c.accent : c.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? c.accent : c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
