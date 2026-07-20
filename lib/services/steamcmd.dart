import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../l10n/gen/app_localizations.dart';
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

/// 一种语言的标题+简介。
class LangEntry {
  final String lang; // Steam 语言码,如 schinese / english
  final String title;
  final String desc;
  const LangEntry(this.lang, this.title, this.desc);
  Map<String, dynamic> toJson() =>
      {'Language': lang, 'Title': title, 'Description': desc};
}

class PublishRequest {
  final int appId;
  final String? publishedFileId; // null/空 = 首次发布
  final String contentFolder;
  final String? previewFile;
  final String title; // 主语言标题(steamcmd 路径与回退用)
  final String description; // 主语言 BBCode
  final String changeNote;
  final int visibility;
  final List<String> tags; // steamcmd 路径不支持;Steamworks 引擎走 SetItemTags
  final String version; // 写入 UGC metadata,供跨机器绑定时读回工坊版本
  final List<LangEntry> languages; // 多语言;第一条带内容上传
  final bool updateContent;
  final bool updateText;
  final bool updatePreview;
  final bool updateTags;
  final bool updateVisibility;

  const PublishRequest({
    required this.appId,
    required this.publishedFileId,
    required this.contentFolder,
    required this.previewFile,
    required this.title,
    required this.description,
    required this.changeNote,
    required this.visibility,
    this.tags = const [],
    this.version = '',
    this.languages = const [],
    this.updateContent = true,
    this.updateText = true,
    this.updatePreview = true,
    this.updateTags = true,
    this.updateVisibility = true,
  });
}

String _vdfEscape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String buildVdf(PublishRequest r) {
  final b = StringBuffer()
    ..writeln('"workshopitem"')
    ..writeln('{')
    ..writeln('  "appid" "${r.appId}"')
    ..writeln('  "publishedfileid" "${r.publishedFileId ?? ''}"');
  if (r.updateContent) {
    b.writeln('  "contentfolder" "${_vdfEscape(r.contentFolder)}"');
  }
  if (r.updatePreview && r.previewFile != null) {
    b.writeln('  "previewfile" "${_vdfEscape(r.previewFile!)}"');
  }
  if (r.updateVisibility) {
    b.writeln('  "visibility" "${r.visibility}"');
  }
  if (r.updateText) {
    b
      ..writeln('  "title" "${_vdfEscape(r.title)}"')
      ..writeln('  "description" "${_vdfEscape(r.description)}"');
  }
  b
    ..writeln('  "changenote" "${_vdfEscape(r.changeNote)}"')
    ..writeln('}');
  return b.toString();
}

class SteamcmdEngine {
  final String steamcmdPath;
  final String username;
  final AppLocalizations t;

  SteamcmdEngine(
      {required this.steamcmdPath, required this.username, required this.t});

  /// 跑一次 workshop_build_item。凭据依赖 steamcmd 的本机缓存
  /// (首次需要在终端里交互登录一次通过 Steam Guard)。
  Stream<PublishEvent> publish(PublishRequest req) async* {
    if (!await File(steamcmdPath).exists()) {
      yield PublishEvent(error: t.errSteamcmdNotFound, done: true);
      return;
    }

    yield PublishEvent(stage: t.stWriteVdf, progress: .05);
    final vdfFile = File(p.join(
        Directory.systemTemp.path, 'dst_mod_publisher', 'item.vdf'));
    await vdfFile.parent.create(recursive: true);
    await vdfFile.writeAsString(buildVdf(req));

    yield PublishEvent(stage: t.stStartSteamcmd, progress: .1);
    final proc = await Process.start(steamcmdPath, [
      '+login', username,
      '+workshop_build_item', vdfFile.path,
      '+quit',
    ]);
    // 立即关闭子进程 stdin:交互式提示(密码/Steam Guard)会直接 EOF 失败退出,
    // 走下面的错误分支,而不是让应用无限等待一个看不见的输入框
    await proc.stdin.close();
    // stderr 必须与 stdout 并发排空,否则管道缓冲区写满时 steamcmd 会被阻塞,双方死锁
    final errLinesFuture = proc.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .toList();

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
    // stderr 一并写进日志(启动后已并发排空)
    for (final line in await errLinesFuture) {
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
      yield PublishEvent(
        done: true,
        error: t.errSteamGuard,
      );
      return;
    }
    if (eresult != null && eresult != 1) {
      yield PublishEvent(done: true, error: decodeEResult(eresult, t));
      return;
    }
    if (code != 0 && newId == null) {
      yield PublishEvent(done: true, error: t.errSteamcmdExit('$code'));
      return;
    }
    yield PublishEvent(
        stage: t.stDone, progress: 1, done: true, publishedFileId: newId);
  }
}
