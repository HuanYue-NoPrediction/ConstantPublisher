import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../l10n/gen/app_localizations.dart';
import '../models/mod.dart';
import '../version.dart';

class UpdateInfo {
  final String version;
  final String source;
  final String? zipPath;
  final String? downloadUrl;

  const UpdateInfo({
    required this.version,
    required this.source,
    this.zipPath,
    this.downloadUrl,
  });
}

Future<UpdateInfo?> checkWorkshopUpdate(String modsDir) async {
  if (modsDir.isEmpty) return null;
  try {
    final steamapps =
        Directory(p.normalize(p.join(modsDir, '..', '..', '..')));
    final content =
        Directory(p.join(steamapps.path, 'workshop', 'content', '322330'));
    if (!await content.exists()) return null;
    await for (final ent in content.list(followLinks: false)) {
      if (ent is! Directory) continue;
      final vf = File(p.join(ent.path, 'version.txt'));
      final zf = File(p.join(ent.path, 'DSTModPublisher-windows.zip'));
      if (!await vf.exists() || !await zf.exists()) continue;
      final v = (await vf.readAsString()).trim();
      if (v.isNotEmpty && cmpVer(v, kAppVersion) > 0) {
        return UpdateInfo(version: v, source: 'workshop', zipPath: zf.path);
      }
    }
  } catch (_) {}
  return null;
}

const _kRepo = 'HuanYue-NoPrediction/ConstantPublisher';

Future<UpdateInfo?> checkGithubUpdate() async {
  return await _checkGithubAsset() ?? await _checkGithubApi();
}

Future<UpdateInfo?> _checkGithubAsset() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(
        'https://github.com/$_kRepo/releases/latest/download/version.txt'));
    req.headers.set('User-Agent', 'dst-mod-publisher');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final v = (await res.transform(utf8.decoder).join()).trim();
    if (v.isEmpty || cmpVer(v, kAppVersion) <= 0) return null;
    return UpdateInfo(
        version: v,
        source: 'github',
        downloadUrl:
            'https://github.com/$_kRepo/releases/latest/download/DSTModPublisher-windows.zip');
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Future<UpdateInfo?> _checkGithubApi() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(
        'https://api.github.com/repos/$_kRepo/releases/latest'));
    req.headers.set('User-Agent', 'dst-mod-publisher');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final j =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    var tag = (j['tag_name'] as String? ?? '').trim();
    if (tag.startsWith('v')) tag = tag.substring(1);
    if (tag.isEmpty || cmpVer(tag, kAppVersion) <= 0) return null;
    for (final a in (j['assets'] as List?) ?? const []) {
      final m = a as Map<String, dynamic>;
      if (m['name'] == 'DSTModPublisher-windows.zip') {
        return UpdateInfo(
            version: tag,
            source: 'github',
            downloadUrl: m['browser_download_url'] as String?);
      }
    }
  } catch (_) {
  } finally {
    client.close();
  }
  return null;
}

Future<String?> downloadZip(String url,
    {void Function(int done, int total)? onProgress}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'dst-mod-publisher');
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final out = File(p.join(
        Directory.systemTemp.path, 'dst_mod_publisher_update', 'update.zip'));
    await out.parent.create(recursive: true);
    final total = res.contentLength;
    final sink = out.openWrite();
    var done = 0;
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        done += chunk.length;
        onProgress?.call(done, total);
      }
    } finally {
      await sink.close();
    }
    return out.path;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Future<String?> applyUpdate(String zipPath, AppLocalizations t) async {
  if (!Platform.isWindows) return t.errUpdateWinOnly;
  final updDir =
      Directory(p.join(Directory.systemTemp.path, 'dst_mod_publisher_update'));
  final staging = Directory(p.join(updDir.path, 'staging'));
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);
  final unzip = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    'Expand-Archive -LiteralPath "$zipPath" -DestinationPath "${staging.path}" -Force',
  ]);
  if (unzip.exitCode != 0) return t.errUnzipFail('${unzip.stderr}');
  if (!await File(p.join(staging.path, 'dst_mod_publisher.exe')).exists()) {
    return t.errZipNoExe;
  }
  final stagedHelper =
      File(p.join(staging.path, 'helper', 'CpSteamHelper.exe'));
  if (!await stagedHelper.exists()) return t.errZipNoHelper;
  final runner = File(p.join(updDir.path, 'apply_helper.exe'));
  try {
    await stagedHelper.copy(runner.path);
  } catch (_) {
    return t.errApplyHelperBusy;
  }
  final installDir = File(Platform.resolvedExecutable).parent.path;
  await Process.start(
      runner.path,
      [
        'apply',
        '$pid',
        staging.path,
        installDir,
        p.join(installDir, 'dst_mod_publisher.exe'),
      ],
      mode: ProcessStartMode.detached);
  exit(0);
}
