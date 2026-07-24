import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../version.dart';
import '../widgets/bits.dart';

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
          title: t.setAppearance,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 130,
                      child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(t.setSeedColor))),
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final entry in kSeeds.entries)
                          Tooltip(
                            message: _seedName(t, entry.key),
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
        TextButton(
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
          child: Text(AppLocalizations.of(context).setSave),
        ),
      ],
    );
  }
}
