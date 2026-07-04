import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/eresult.dart';

/// 发布过程中的事件流:阶段、日志行、结果。
class PublishEvent {
  final String? stage;
  final double? progress; // 0~1
  final String? logLine;
  final bool done;
  final String? error;
  final String? publishedFileId;

  const PublishEvent({
    this.stage,
    this.progress,
    this.logLine,
    this.done = false,
    this.error,
    this.publishedFileId,
  });
}

class PublishRequest {
  final int appId;
  final String? publishedFileId; // null/空 = 首次发布
  final String contentFolder;
  final String? previewFile;
  final String title;
  final String description; // BBCode
  final String changeNote;
  final int visibility;

  const PublishRequest({
    required this.appId,
    required this.publishedFileId,
    required this.contentFolder,
    required this.previewFile,
    required this.title,
    required this.description,
    required this.changeNote,
    required this.visibility,
  });
}

String _vdfEscape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String buildVdf(PublishRequest r) {
  final b = StringBuffer()
    ..writeln('"workshopitem"')
    ..writeln('{')
    ..writeln('  "appid" "${r.appId}"')
    ..writeln('  "publishedfileid" "${r.publishedFileId ?? ''}"')
    ..writeln('  "contentfolder" "${_vdfEscape(r.contentFolder)}"');
  if (r.previewFile != null) {
    b.writeln('  "previewfile" "${_vdfEscape(r.previewFile!)}"');
  }
  b
    ..writeln('  "visibility" "${r.visibility}"')
    ..writeln('  "title" "${_vdfEscape(r.title)}"')
    ..writeln('  "description" "${_vdfEscape(r.description)}"')
    ..writeln('  "changenote" "${_vdfEscape(r.changeNote)}"')
    ..writeln('}');
  return b.toString();
}

class SteamcmdEngine {
  final String steamcmdPath;
  final String username;

  SteamcmdEngine({required this.steamcmdPath, required this.username});

  /// 跑一次 workshop_build_item。凭据依赖 steamcmd 的本机缓存
  /// (首次需要在终端里交互登录一次通过 Steam Guard)。
  Stream<PublishEvent> publish(PublishRequest req) async* {
    if (!await File(steamcmdPath).exists()) {
      yield const PublishEvent(
          error: '找不到 steamcmd.exe —— 到设置页指定路径', done: true);
      return;
    }

    yield const PublishEvent(stage: '写入 VDF', progress: .05);
    final vdfFile = File(p.join(
        Directory.systemTemp.path, 'constant_publisher', 'item.vdf'));
    await vdfFile.parent.create(recursive: true);
    await vdfFile.writeAsString(buildVdf(req));

    yield const PublishEvent(stage: '启动 steamcmd', progress: .1);
    final proc = await Process.start(steamcmdPath, [
      '+login', username,
      '+workshop_build_item', vdfFile.path,
      '+quit',
    ]);

    String? newId;
    var sawGuard = false;
    int? eresult;

    await for (final line in proc.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())) {
      yield PublishEvent(logLine: line);
      if (line.contains('Steam Guard')) sawGuard = true;
      if (line.contains('Uploading')) {
        yield const PublishEvent(stage: 'UploadingContent', progress: .6);
      }
      final idm =
          RegExp(r'PublishedFileID?\s*[: ]\s*(\d+)', caseSensitive: false)
              .firstMatch(line);
      if (idm != null) newId = idm.group(1);
      final erm = RegExp(r'\(EResult (\d+)').firstMatch(line);
      if (erm != null) eresult = int.parse(erm.group(1)!);
      if (line.contains('FAILED') && eresult == null) {
        eresult = 2;
      }
    }
    // stderr 一并写进日志
    await for (final line in proc.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())) {
      yield PublishEvent(logLine: '[err] $line');
    }

    final code = await proc.exitCode;

    // 成功时 steamcmd 会把新 id 写回 VDF —— 首选真相源
    try {
      final back = await vdfFile.readAsString();
      final m =
          RegExp(r'"publishedfileid"\s+"(\d+)"').firstMatch(back);
      if (m != null && m.group(1)!.isNotEmpty && m.group(1) != '0') {
        newId = m.group(1);
      }
    } catch (_) {}

    if (sawGuard) {
      yield const PublishEvent(
        done: true,
        error: '需要 Steam Guard 验证:请先在终端手动运行一次\n'
            'steamcmd +login <账号> 完成验证(本机缓存后不再需要)',
      );
      return;
    }
    if (eresult != null && eresult != 1) {
      yield PublishEvent(done: true, error: decodeEResult(eresult));
      return;
    }
    if (code != 0 && newId == null) {
      yield PublishEvent(done: true, error: 'steamcmd 退出码 $code,查看日志');
      return;
    }
    yield PublishEvent(
        stage: '完成', progress: 1, done: true, publishedFileId: newId);
  }
}
