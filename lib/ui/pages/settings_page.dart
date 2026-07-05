import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets/bits.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineSmall),
        Text('环境、外观与默认行为',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        SectionCard(
          title: '发布引擎',
          subtitle: '默认 Steamworks:开着 Steam 即可,免账号免密码(与官方工具同机制);steamcmd 供 CI / 无桌面 Steam 环境',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'steamworks', label: Text('Steamworks(推荐)')),
                  ButtonSegment(value: 'steamcmd', label: Text('steamcmd')),
                ],
                selected: {state.engine},
                onSelectionChanged: (s) => state.setEngine(s.first),
              ),
              const SizedBox(height: 10),
              Text(
                state.engine == 'steamworks'
                    ? (state.steamReady
                        ? '✓ 助手已就绪 —— Steam 客户端开着就能发布,身份来自 Steam 本身'
                        : '✗ 未找到 helper\\CpSteamHelper.exe —— 请使用完整发行包(开发模式需先构建 helper)')
                    : (state.steamReady
                        ? '✓ steamcmd 已配置'
                        : '✗ 需要配置下方 steamcmd 路径与账号'),
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '通用',
          child: _PathRow(
            label: 'mods 目录',
            value: state.modsDir.isEmpty ? '未设置' : state.modsDir,
            onPick: () async {
              final dir = await getDirectoryPath();
              if (dir != null) await state.setModsDir(dir);
            },
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'steamcmd(高级 · 仅 steamcmd 引擎需要)',
          child: Column(
            children: [
              _PathRow(
                label: 'steamcmd 路径',
                value: state.steamcmdPath.isEmpty
                    ? '未设置 —— 从 https://developer.valvesoftware.com/wiki/SteamCMD 下载'
                    : state.steamcmdPath,
                onPick: () async {
                  const group = XTypeGroup(label: 'steamcmd', extensions: ['exe']);
                  final f = await openFile(acceptedTypeGroups: [group]);
                  if (f != null) await state.setSteamcmdPath(f.path);
                },
              ),
              const Divider(height: 20),
              _TextRow(
                label: 'Steam 账号',
                hint: '首次需在终端运行 steamcmd +login <账号> 过一次 Steam Guard',
                value: state.steamUser,
                onSave: state.setSteamUser,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '工坊巡检(可选)',
          subtitle:
              '用 Steam Web API 拉取账号名下条目;不配置也不影响发布(真相源是本地 dstpub.json)',
          child: Column(
            children: [
              _TextRow(
                label: 'Web API Key',
                hint: 'steamcommunity.com/dev/apikey 申请',
                value: state.webApiKey,
                obscure: true,
                onSave: (v) => state.setWebApi(v, state.steamId64),
              ),
              const Divider(height: 20),
              _TextRow(
                label: 'SteamID64',
                hint: '17 位数字,steamid.io 可查',
                value: state.steamId64,
                onSave: (v) => state.setWebApi(state.webApiKey, v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '外观',
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                      width: 130,
                      child: Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('主题色'))),
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final entry in kSeeds.entries)
                          Tooltip(
                            message: kSeedNames[entry.key] ?? entry.key,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => state.setSeed(entry.key),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: entry.value,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: state.seed == entry.key
                                        ? scheme.primary
                                        : scheme.outlineVariant,
                                    width: state.seed == entry.key ? 3 : 1,
                                  ),
                                ),
                                child: state.seed == entry.key
                                    ? const Icon(Icons.check,
                                        size: 16, color: Colors.white)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(child: Text('深色模式')),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system, label: Text('跟随系统')),
                      ButtonSegment(
                          value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(
                          value: ThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {state.themeMode},
                    onSelectionChanged: (s) => state.setThemeMode(s.first),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '关于',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DST Mod Publisher 0.1.0',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '开源(GPL-3.0)· 界面布局致敬 FlClash 的 Material You 设计,代码全部原创\n'
                '非 Klei / Valve 官方软件 · Don\'t Starve 是 Klei Entertainment 商标,Steam 是 Valve 商标',
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PathRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onPick;
  const _PathRow(
      {required this.label, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
              Text(value,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        TextButton(onPressed: onPick, child: const Text('选择…')),
      ],
    );
  }
}

class _TextRow extends StatefulWidget {
  final String label;
  final String hint;
  final String value;
  final bool obscure;
  final Future<void> Function(String) onSave;
  const _TextRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onSave,
    this.obscure = false,
  });

  @override
  State<_TextRow> createState() => _TextRowState();
}

class _TextRowState extends State<_TextRow> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
            width: 130,
            child: Text(widget.label,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600))),
        Expanded(
          child: TextField(
            controller: _ctrl,
            obscureText: widget.obscure,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              hintText: widget.hint,
            ),
            onSubmitted: (v) => widget.onSave(v.trim()),
          ),
        ),
        TextButton(
          onPressed: () => widget.onSave(_ctrl.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
