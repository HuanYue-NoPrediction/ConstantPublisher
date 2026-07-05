import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 发布页草稿 —— 官方工具"失败即清空"的解药:
/// 所有表单字段边写边存,按模组路径隔离,发布成功才清除。
class Draft {
  String version;
  int visibility;
  List<String> tags;
  String changeNote;
  String description; // 兼容旧草稿的单份简介
  String curLang;
  Map<String, String> titles; // 各语言标题
  Map<String, String> descs; // 各语言简介
  DateTime savedAt;

  Draft({
    this.version = '',
    this.visibility = 0,
    List<String>? tags,
    this.changeNote = '',
    this.description = '',
    this.curLang = 'schinese',
    Map<String, String>? titles,
    Map<String, String>? descs,
    DateTime? savedAt,
  })  : tags = tags ?? [],
        titles = titles ?? {},
        descs = descs ?? {},
        savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'version': version,
        'visibility': visibility,
        'tags': tags,
        'changeNote': changeNote,
        'description': description,
        'curLang': curLang,
        'titles': titles,
        'descs': descs,
        'savedAt': savedAt.toIso8601String(),
      };

  factory Draft.fromJson(Map<String, dynamic> j) => Draft(
        version: j['version'] as String? ?? '',
        visibility: (j['visibility'] as num?)?.toInt() ?? 0,
        tags: (j['tags'] as List?)?.cast<String>() ?? [],
        changeNote: j['changeNote'] as String? ?? '',
        description: j['description'] as String? ?? '',
        curLang: j['curLang'] as String? ?? 'schinese',
        titles: (j['titles'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString())) ??
            {},
        descs: (j['descs'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString())) ??
            {},
        savedAt:
            DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class DraftStore {
  // 草稿按「内容文件夹 + 发布目标」双键隔离:同一文件夹发到不同条目(或新建)
  // 各有独立草稿,避免"新建时存的 modinfo 描述"泄漏到"更新条目"的编辑会话。
  static String _key(String modPath, String? targetId) =>
      'draft:$modPath:${targetId ?? 'new'}';

  static Future<Draft?> load(String modPath, String? targetId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(modPath, targetId));
    if (raw == null) return null;
    try {
      return Draft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String modPath, String? targetId, Draft d) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key(modPath, targetId), jsonEncode(d.toJson()));
  }

  static Future<void> clear(String modPath, String? targetId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key(modPath, targetId));
  }
}
