import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 发布页草稿 —— 官方工具"失败即清空"的解药:
/// 所有表单字段边写边存,按模组路径隔离,发布成功才清除。
class Draft {
  String version;
  String channel;
  int visibility;
  List<String> tags;
  String changeNote;
  String description;
  bool manualChannel;
  DateTime savedAt;

  Draft({
    this.version = '',
    this.channel = 'release',
    this.visibility = 0,
    List<String>? tags,
    this.changeNote = '',
    this.description = '',
    this.manualChannel = false,
    DateTime? savedAt,
  })  : tags = tags ?? [],
        savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'version': version,
        'channel': channel,
        'visibility': visibility,
        'tags': tags,
        'changeNote': changeNote,
        'description': description,
        'manualChannel': manualChannel,
        'savedAt': savedAt.toIso8601String(),
      };

  factory Draft.fromJson(Map<String, dynamic> j) => Draft(
        version: j['version'] as String? ?? '',
        channel: j['channel'] as String? ?? 'release',
        visibility: (j['visibility'] as num?)?.toInt() ?? 0,
        tags: (j['tags'] as List?)?.cast<String>() ?? [],
        changeNote: j['changeNote'] as String? ?? '',
        description: j['description'] as String? ?? '',
        manualChannel: j['manualChannel'] as bool? ?? false,
        savedAt:
            DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class DraftStore {
  static String _key(String modPath) => 'draft:$modPath';

  static Future<Draft?> load(String modPath) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(modPath));
    if (raw == null) return null;
    try {
      return Draft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String modPath, Draft d) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key(modPath), jsonEncode(d.toJson()));
  }

  static Future<void> clear(String modPath) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key(modPath));
  }
}
