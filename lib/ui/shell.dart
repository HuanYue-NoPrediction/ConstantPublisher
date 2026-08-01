import 'dart:io' show Platform;

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
                _Rail(
                  index: state.navIndex,
                  onSelect: state.goto,
                  primary: [
                    (Icons.dashboard_outlined, Icons.dashboard, t.navDashboard),
                    (Icons.public_outlined, Icons.public, t.navWorkshop),
                    (Icons.upload_outlined, Icons.upload, t.navPublish),
                  ],
                  utility: [
                    (Icons.terminal_outlined, Icons.terminal, t.navLogs),
                    (Icons.tune_outlined, Icons.tune, t.navSettings),
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

typedef _NavItem = (IconData, IconData, String);

class _Rail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final List<_NavItem> primary;
  final List<_NavItem> utility;

  const _Rail({
    required this.index,
    required this.onSelect,
    required this.primary,
    required this.utility,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          const SizedBox(height: 10),
          for (var i = 0; i < primary.length; i++)
            _RailButton(
              item: primary[i],
              selected: index == i,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Divider(height: 1, color: scheme.outlineVariant),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < utility.length; i++)
            _RailButton(
              item: utility[i],
              selected: index == primary.length + i,
              onTap: () => onSelect(primary.length + i),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _RailButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                width: 46,
                height: 28,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(selected ? item.$2 : item.$1, size: 19, color: fg),
              ),
              const SizedBox(height: 4),
              Text(
                item.$3,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.1,
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
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
    final isMac = Platform.isMacOS;
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          // macOS 原生窗口按钮(红绿灯)在左上角,留出空间避免挡住 eye.gif
          SizedBox(width: isMac ? 78 : 14),
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
          // Windows 无原生窗口按钮,才画自绘的最小化/最大化/关闭;macOS 用系统红绿灯
          if (!isMac) ...[
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
          ] else
            const SizedBox(width: 8),
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
