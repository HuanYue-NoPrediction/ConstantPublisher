import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../version.dart';
import '../widgets/bits.dart';
import '../widgets/color_picker.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        Text(t.setTitle, style: Theme.of(context).textTheme.headlineSmall),
        Text(t.setSubtitle,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        SectionCard(
          icon: Icons.bolt_outlined,
          title: t.setEngineTitle,
          subtitle: t.setEngineSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'steamworks', label: Text(t.setEngineSw)),
                  const ButtonSegment(
                      value: 'steamcmd', label: Text('steamcmd')),
                ],
                selected: {state.engine},
                onSelectionChanged: (s) => state.setEngine(s.first),
              ),
              const SizedBox(height: 10),
              Text(
                state.engine == 'steamworks'
                    ? (state.steamReady ? t.setSwReady : t.setSwMissing)
                    : (state.steamReady ? t.setCmdReady : t.setCmdNeed),
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          icon: Icons.folder_outlined,
          title: t.setGeneral,
          child: _PathRow(
            label: t.setModsDir,
            value: state.modsDir.isEmpty ? t.setNotSet : state.modsDir,
            onPick: () async {
              final dir = await getDirectoryPath();
              if (dir != null) await state.setModsDir(dir);
            },
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          icon: Icons.terminal_outlined,
          title: t.setCmdCard,
          child: Column(
            children: [
              _PathRow(
                label: t.setCmdPath,
                value: state.steamcmdPath.isEmpty
                    ? t.setCmdPathHint
                    : state.steamcmdPath,
                onPick: () async {
                  const group = XTypeGroup(label: 'steamcmd', extensions: ['exe']);
                  final f = await openFile(acceptedTypeGroups: [group]);
                  if (f != null) await state.setSteamcmdPath(f.path);
                },
              ),
              const Divider(height: 20),
              _TextRow(
                label: t.setSteamUser,
                hint: t.setSteamUserHint,
                value: state.steamUser,
                onSave: state.setSteamUser,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          icon: Icons.travel_explore_outlined,
          title: t.setInspect,
          subtitle: t.setInspectSubtitle,
          child: Column(
            children: [
              _TextRow(
                label: 'Web API Key',
                hint: t.setApiKeyHint,
                value: state.webApiKey,
                obscure: true,
                onSave: (v) => state.setWebApi(v, state.steamId64),
              ),
              const Divider(height: 20),
              _TextRow(
                label: 'SteamID64',
                hint: t.setSteamIdHint,
                value: state.steamId64,
                onSave: (v) => state.setWebApi(state.webApiKey, v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          icon: Icons.palette_outlined,
          title: t.setAppearance,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.setSeedColor,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                              kSeeds.containsKey(state.seed)
                                  ? _seedName(t, state.seed)
                                  : state.seed.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontFamily: kSeeds.containsKey(state.seed)
                                      ? null
                                      : 'monospace',
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final entry in kSeeds.entries)
                          _Swatch(
                            color: entry.value,
                            name: _seedName(t, entry.key),
                            selected: state.seed == entry.key,
                            onTap: () => state.setSeed(entry.key),
                          ),
                        _CustomSwatch(
                          selected: !kSeeds.containsKey(state.seed),
                          current: resolveSeed(state.seed),
                          name: t.seedCustom,
                          onPick: () async {
                            final c = await showSeedPicker(
                                context, resolveSeed(state.seed));
                            if (c != null) {
                              final hex =
                                  '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0')}';
                              await state.setSeed(hex);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(child: Text(t.setDarkMode)),
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(t.setFollowSystem)),
                      ButtonSegment(
                          value: ThemeMode.light, label: Text(t.setLight)),
                      ButtonSegment(
                          value: ThemeMode.dark, label: Text(t.setDark)),
                    ],
                    selected: {state.themeMode},
                    onSelectionChanged: (s) => state.setThemeMode(s.first),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(child: Text(t.setLanguage)),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                          value: 'system', label: Text(t.setLangSystem)),
                      ButtonSegment(value: 'zh', label: Text(t.setLangZh)),
                      ButtonSegment(value: 'en', label: Text(t.setLangEn)),
                    ],
                    selected: {state.localePref},
                    onSelectionChanged: (s) => state.setLocalePref(s.first),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          icon: Icons.info_outline,
          title: t.setAbout,
          trailing: TextButton(
            onPressed: () async {
              await state.checkUpdates(manual: true);
              if (context.mounted) {
                final tt = AppLocalizations.of(context);
                toast(
                    context,
                    state.update == null
                        ? tt.setLatestToast(kAppVersion)
                        : tt.setFoundToast(state.update!.version));
              }
            },
            child: Text(t.setCheckUpdate),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DST Mod Publisher v$kAppVersion',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${t.setAuthorLine}\n${t.setMacMaintainer}\n${t.setAboutLine1}\n${t.setAboutLine2}',
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(
                        'https://github.com/HuanYue-NoPrediction/ConstantPublisher')),
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('GitHub'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(
                        'https://github.com/HuanYue-NoPrediction/ConstantPublisher/issues')),
                    icon: const Icon(Icons.bug_report_outlined, size: 16),
                    label: Text(t.setBtnIssues),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(
                        Uri.parse('mailto:1713597367@qq.com')),
                    icon: const Icon(Icons.mail_outline, size: 16),
                    label: Text(t.setBtnMail),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => openSteamPage(
                        'https://steamcommunity.com/sharedfiles/filedetails/?id=3758340920'),
                    icon: const Icon(Icons.cloud_outlined, size: 16),
                    label: Text(t.setBtnWorkshop),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => openSteamPage(
                        'https://steamcommunity.com/id/Chilla_s_url/'),
                    icon: const Icon(Icons.person_outline, size: 16),
                    label: Text(t.setBtnMacHome),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _seedName(AppLocalizations t, String key) => switch (key) {
      'purple' => t.seedPurple,
      'indigo' => t.seedIndigo,
      'blue' => t.seedBlue,
      'cyan' => t.seedCyan,
      'teal' => t.seedTeal,
      'green' => t.seedGreen,
      'lime' => t.seedLime,
      'amber' => t.seedAmber,
      'orange' => t.seedOrange,
      'clay' => t.seedClay,
      'red' => t.seedRed,
      'pink' => t.seedPink,
      'magenta' => t.seedMagenta,
      'slate' => t.seedSlate,
      _ => key,
    };

class _Swatch extends StatelessWidget {
  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 400),
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(3.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: .6)),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: .45),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

class _CustomSwatch extends StatelessWidget {
  final bool selected;
  final Color current;
  final String name;
  final VoidCallback onPick;

  const _CustomSwatch({
    required this.selected,
    required this.current,
    required this.name,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 400),
      child: InkResponse(
        onTap: onPick,
        radius: 26,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(3.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? current : Colors.transparent,
              width: 2,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: .6)),
              gradient: const SweepGradient(
                colors: [
                  Color(0xFFE53935),
                  Color(0xFFFFB300),
                  Color(0xFF43A047),
                  Color(0xFF00ACC1),
                  Color(0xFF3949AB),
                  Color(0xFF8E24AA),
                  Color(0xFFE53935),
                ],
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: current.withValues(alpha: .45),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              selected ? Icons.check : Icons.add,
              size: 15,
              color: Colors.white,
            ),
          ),
        ),
      ),
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
        SizedBox(
          width: 140,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant)),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
            onPressed: onPick,
            child: Text(AppLocalizations.of(context).setPick)),
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
            width: 140,
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
          child: Text(AppLocalizations.of(context).setSave),
        ),
      ],
    );
  }
}
