import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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
        return UpdateInfo(version: v, source: '创意工坊', zipPath: zf.path);
      }
    }
  } catch (_) {}
  return null;
}

Future<UpdateInfo?> checkGithubUpdate() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(
        'https://api.github.com/repos/HuanYue-NoPrediction/ConstantPublisher/releases/latest'));
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
            source: 'GitHub',
            downloadUrl: m['browser_download_url'] as String?);
      }
    }
  } catch (_) {
  } finally {
    client.close();
  }
  return null;
}

Future<String?> downloadZip(String url) async {
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
    await res.pipe(out.openWrite());
    return out.path;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Future<String?> applyUpdate(String zipPath) async {
  if (!Platform.isWindows) return '自动更新目前仅支持 Windows';
  final staging = Directory(p.join(
      Directory.systemTemp.path, 'dst_mod_publisher_update', 'staging'));
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);
  final unzip = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    'Expand-Archive -LiteralPath "$zipPath" -DestinationPath "${staging.path}" -Force',
  ]);
  if (unzip.exitCode != 0) return '解压失败:${unzip.stderr}';
  if (!await File(p.join(staging.path, 'dst_mod_publisher.exe')).exists()) {
    return '更新包无效:缺少主程序';
  }
  final installDir = File(Platform.resolvedExecutable).parent.path;
  final bat = File(p.join(
      Directory.systemTemp.path, 'dst_mod_publisher_update', 'apply.bat'));
  await bat.writeAsString('''
@echo off
:wait
tasklist /FI "PID eq $pid" 2>nul | find "$pid" >nul
if not errorlevel 1 (
  timeout /t 1 /nobreak >nul
  goto wait
)
robocopy "${staging.path}" "$installDir" /E /NFL /NDL /NJH /NJS /NP >nul
start "" "${p.join(installDir, 'dst_mod_publisher.exe')}"
rmdir /S /Q "${staging.path}"
del "%~f0"
''');
  await Process.start('cmd', ['/c', 'start', '', '/min', bat.path],
      mode: ProcessStartMode.detached);
  exit(0);
}
