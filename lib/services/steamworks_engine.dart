import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/eresult.dart';
import 'steamcmd.dart' show PublishEvent, PublishRequest;

/// Steamworks 引擎:调用随包分发的 CpSteamHelper.exe,
/// 借用正在运行的 Steam 客户端会话发布 —— 零配置、免密码,
/// 与官方 ModUploader 同机制,且支持可靠标签与真实上传进度。
class SteamworksEngine {
  final String helperPath;

  SteamworksEngine({required this.helperPath});

  Stream<PublishEvent> publish(PublishRequest req) async* {
    if (!await File(helperPath).exists()) {
      yield PublishEvent(
        error: '找不到 Steamworks 助手:$helperPath\n'
            '请使用完整发行包;开发模式下先运行 dotnet publish helper',
        done: true,
      );
      return;
    }

    final reqFile = File(p.join(
        Directory.systemTemp.path, 'dst_mod_publisher', 'request.json'));
    await reqFile.parent.create(recursive: true);
    await reqFile.writeAsString(jsonEncode({
      'appId': req.appId,
      'publishedFileId': int.tryParse(req.publishedFileId ?? '') ?? 0,
      'contentFolder': req.contentFolder,
      'previewFile': req.previewFile,
      'title': req.title,
      'description': req.description,
      'changeNote': req.changeNote,
      'visibility': req.visibility,
      'tags': req.tags,
      'version': req.version,
      'languages': req.languages.map((e) => e.toJson()).toList(),
      'updateContent': req.updateContent,
      'updateText': req.updateText,
      'updatePreview': req.updatePreview,
      'updateTags': req.updateTags,
      'updateVisibility': req.updateVisibility,
    }));

    yield const PublishEvent(stage: '连接 Steam 客户端', progress: .12);
    final proc = await Process.start(helperPath, [reqFile.path]);
    await proc.stdin.close();
    final errFuture = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();

    String? newId;
    String? error;
    var ok = false;
    var needsLegal = false;

    await for (final line in proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      Map<String, dynamic> j;
      try {
        j = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        yield PublishEvent(logLine: '[helper] $line');
        continue;
      }
      switch (j['event']) {
        case 'stage':
          final stage = j['stage'] as String? ?? '';
          yield PublishEvent(
              stage: stage, progress: .2, logLine: '[steamworks] $stage');
        case 'log':
          yield PublishEvent(logLine: '[steamworks] ${j['message']}');
        case 'progress':
          final done = (j['done'] as num?)?.toDouble() ?? 0;
          final total = (j['total'] as num?)?.toDouble() ?? 0;
          final frac = total > 0 ? (done / total) : 0.0;
          yield PublishEvent(
            stage:
                '${j['status']} · ${(done / 1048576).toStringAsFixed(1)}/${(total / 1048576).toStringAsFixed(1)} MB',
            progress: .2 + frac * .75,
          );
        case 'result':
          ok = j['ok'] == true;
          newId = j['publishedFileId']?.toString();
          needsLegal = j['needsLegalAgreement'] == true;
          if (!ok) {
            final er = (j['eresult'] as num?)?.toInt() ?? 0;
            final raw = j['error'] as String? ?? '未知错误';
            error = er > 0 ? '$raw · ${decodeEResult(er)}' : raw;
          }
      }
    }
    for (final line in await errFuture) {
      yield PublishEvent(logLine: '[helper-err] $line');
    }
    final code = await proc.exitCode;

    if (!ok) {
      yield PublishEvent(done: true, error: error ?? '助手异常退出(exit $code)');
      return;
    }
    if (needsLegal) {
      yield const PublishEvent(
          logLine:
              '⚠ 需在 Steam 接受创意工坊法律协议后条目才对他人可见:steamcommunity.com/sharedfiles/workshoplegalagreement');
    }
    yield PublishEvent(
        stage: '完成', progress: 1, done: true, publishedFileId: newId);
  }
}
