import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../l10n/gen/app_localizations.dart';
import '../models/eresult.dart';
import 'steamcmd.dart' show PublishEvent, PublishRequest;

/// Steamworks 引擎:调用随包分发的 CpSteamHelper.exe,
/// 借用正在运行的 Steam 客户端会话发布 —— 零配置、免密码,
/// 与官方 ModUploader 同机制,且支持可靠标签与真实上传进度。
String? helperText(AppLocalizations t, Map<String, dynamic> j) {
  final code = j['code'] as String?;
  if (code == null) return null;
  final arg = j['arg']?.toString() ?? '';
  return switch (code) {
    'create_item' => t.hCreateItem,
    'create_rejected' => t.hCreateRejected,
    'create_timeout' => t.hCreateTimeout,
    'create_fail' => t.hCreateFail,
    'item_created' => t.hItemCreated(arg),
    'legal_note' => t.hLegalNote,
    'upload_content' => t.hUploadContent(arg),
    'update_meta' => t.hUpdateMeta,
    'update_lang_text' => t.hUpdateLangText(arg),
    'tags_warn' => t.hTagsWarn,
    'upload_timeout' => t.hUploadTimeout,
    'submit_fail' => t.hSubmitFail(
        arg,
        ((j['eresult'] as num?)?.toInt() ?? 0) == 2
            ? t.hEresult2Hint
            : ''),
    'no_request' => t.hNoRequest,
    'bad_request' => t.hBadRequest(arg),
    'internal' => t.hInternal(arg),
    'desc_fail' => t.hDescFail(arg),
    'delete_fail' => t.hDeleteFail(arg),
    'steam_connect' => t.hSteamConnect(arg),
    'dll_missing' => t.hDllMissing,
    'init_error' => t.hInitError(arg),
    'query_invalid' => t.hQueryInvalid,
    'query_timeout' => t.hQueryTimeout,
    'query_fail' => t.hQueryFail,
    _ => null,
  };
}

class SteamworksEngine {
  final String helperPath;
  final AppLocalizations t;

  SteamworksEngine({required this.helperPath, required this.t});

  Stream<PublishEvent> publish(PublishRequest req) async* {
    if (!await File(helperPath).exists()) {
      yield PublishEvent(
        error: t.errHelperNotFound(helperPath),
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

    yield PublishEvent(stage: t.stConnectSteam, progress: .12);
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
          final stage = helperText(t, j) ?? (j['stage'] as String? ?? '');
          yield PublishEvent(
              stage: stage, progress: .2, logLine: '[steamworks] $stage');
        case 'log':
          yield PublishEvent(
              logLine:
                  '[steamworks] ${helperText(t, j) ?? j['message']}');
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
            final raw =
                helperText(t, j) ?? (j['error'] as String? ?? t.errUnknown);
            error = er > 0 ? '$raw · ${decodeEResult(er, t)}' : raw;
          }
      }
    }
    for (final line in await errFuture) {
      yield PublishEvent(logLine: '[helper-err] $line');
    }
    final code = await proc.exitCode;

    if (!ok) {
      yield PublishEvent(
          done: true, error: error ?? t.errHelperExit('$code'));
      return;
    }
    if (needsLegal) {
      yield PublishEvent(logLine: t.msgLegalAgreement);
    }
    yield PublishEvent(
        stage: t.stDone, progress: 1, done: true, publishedFileId: newId);
  }
}
