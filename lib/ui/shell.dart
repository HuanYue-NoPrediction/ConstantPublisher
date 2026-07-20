import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';
import 'pages/dashboard_page.dart';
import 'pages/logs_page.dart';
import 'pages/publish_page.dart';
import 'pages/settings_page.dart';
import 'pages/workshop_page.dart';

/// 应用外壳:自绘标题栏 + 左侧 NavigationRail + 页面区。
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = AppLocalizations.of(context);
    const pages = [
      DashboardPage(),
      WorkshopPage(),
      PublishPage(),
      LogsPage(),
      SettingsPage(),
    ];

    return Scaffold(
      body: Column(
        children: [
          const _TitleBar(),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: state.navIndex,
                  onDestinationSelected: state.goto,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    NavigationRailDestination(
                        icon: const Icon(Icons.dashboard_outlined),
                        selectedIcon: const Icon(Icons.dashboard),
                        label: Text(t.navDashboard)),
                    NavigationRailDestination(
                        icon: const Icon(Icons.public_outlined),
                        selectedIcon: const Icon(Icons.public),
                        label: Text(t.navWorkshop)),
                    NavigationRailDestination(
                        icon: const Icon(Icons.upload_outlined),
                        selectedIcon: const Icon(Icons.upload),
                        label: Text(t.navPublish)),
                    NavigationRailDestination(
                        icon: const Icon(Icons.terminal_outlined),
                        selectedIcon: const Icon(Icons.terminal),
                        label: Text(t.navLogs)),
                    NavigationRailDestination(
                        icon: const Icon(Icons.tune_outlined),
                        selectedIcon: const Icon(Icons.tune),
                        label: Text(t.navSettings)),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: pages[state.navIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          const SizedBox(width: 14),
          // 会扑腾的恐怖之眼(GIF 动画,ico 做不到,窗口内可以)
          Image.asset('assets/eye.gif',
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium),
          const SizedBox(width: 9),
          const Text('DST Mod Publisher',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context).appSubtitle,
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          // 拖拽区
          const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
          IconButton(
            tooltip: AppLocalizations.of(context).tooltipToggleTheme,
            iconSize: 17,
            onPressed: () {
              final dark = Theme.of(context).brightness == Brightness.dark;
              state.setThemeMode(dark ? ThemeMode.light : ThemeMode.dark);
            },
            icon: const Icon(Icons.brightness_medium_outlined),
          ),
          _WinButton(
              icon: Icons.remove, onTap: () => windowManager.minimize()),
          _WinButton(
              icon: Icons.crop_square,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              }),
          _WinButton(
              icon: Icons.close,
              hoverColor: const Color(0xFFE81123),
              onTap: () => windowManager.close()),
        ],
      ),
    );
  }
}

class _WinButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? hoverColor;
  const _WinButton({required this.icon, required this.onTap, this.hoverColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 42,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: Icon(icon, size: 16),
      ),
    );
  }
}
