import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// modinfo.lua 里解析出的字段(只读,真相源是文件本身)。
class ModInfo {
  final String name;
  final String author;
  final String version;
  final String description;
  final String apiVersion;
  final bool clientOnly;
  final bool serverOnly;

  const ModInfo({
    this.name = '',
    this.author = '',
    this.version = '',
    this.description = '',
    this.apiVersion = '',
    this.clientOnly = false,
    this.serverOnly = false,
  });

  bool get valid => name.isNotEmpty && version.isNotEmpty;

  /// DST 类型标签:官方工具据 modinfo 布尔位生成,决定 mod 需装在客户端还是服务器。
  String get typeTag => clientOnly
      ? 'client_only_mod'
      : serverOnly
          ? 'server_only_mod'
          : 'all_clients_require_mod';

  /// 宽松解析:取 `key =` 之后的第一个字符串字面量,
  /// 兼容饥荒标准双语写法 `key = chinese and "中文" or "English"`
  /// (返回第一个 = 中文那份)以及 `[[长字符串]]`、纯数字。
  static ModInfo parse(String lua) {
    String field(String key) {
      // (?<![\w]) 词边界:找 version 时不会误命中 api_version
      final at = RegExp('(?<![\\w])$key\\s*=').firstMatch(lua);
      if (at == null) return '';
      final rest = lua.substring(at.end);
      final line = rest.split('\n').first;
      // 同行内的第一个引号字符串(条件表达式里的第一个 = 中文值)
      final q = RegExp('"((?:[^"\\\\]|\\\\.)*)"|\'((?:[^\'\\\\]|\\\\.)*)\'')
          .firstMatch(line);
      if (q != null) return q.group(1) ?? q.group(2) ?? '';
      // [[长字符串]] 可跨行,从 key= 之后取第一个
      final long = RegExp('\\[\\[([\\s\\S]*?)\\]\\]').firstMatch(rest);
      if (long != null) return (long.group(1) ?? '').trim();
      final num = RegExp('([0-9][0-9.]*)').firstMatch(line);
      return num?.group(1) ?? '';
    }

    bool flag(String key) =>
        RegExp('$key\\s*=\\s*true', caseSensitive: false).hasMatch(lua);

    return ModInfo(
      name: field('name'),
      author: field('author'),
      version: field('version'),
      description: field('description'),
      apiVersion: field('api_version'),
      clientOnly: flag('client_only_mod'),
      serverOnly: flag('server_only_mod'),
    );
  }
}

/// dstpub.json —— 模组文件夹的内容设置(目标游戏、可见性、标签、忽略规则)。
/// 不再记录"发布到哪个工坊条目":发布目标每次在发布页显式选择。
class DstPub {
  int appId;
  int visibility; // 0 公开 / 1 好友 / 2 私密 / 3 不公开
  List<String> tags;
  List<String> ignore;

  /// 白名单:命中的文件强制保留,优先级高于所有忽略规则
  /// (用途示例:介绍模组里刻意携带工具发行包 zip)。
  List<String> keep;

  DstPub({
    this.appId = 322330,
    this.visibility = 0,
    List<String>? tags,
    List<String>? ignore,
    List<String>? keep,
  })  : tags = tags ?? [],
        ignore = ignore ?? [],
        keep = keep ?? [];

  factory DstPub.fromJson(Map<String, dynamic> j) => DstPub(
        appId: (j['appid'] as num?)?.toInt() ?? 322330,
        visibility: (j['visibility'] as num?)?.toInt() ?? 0,
        tags: (j['tags'] as List?)?.cast<String>() ?? [],
        ignore: (j['ignore'] as List?)?.cast<String>() ?? [],
        keep: (j['keep'] as List?)?.cast<String>() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'appid': appId,
        'visibility': visibility,
        'tags': tags,
        'ignore': ignore,
        'keep': keep,
      };
}

class Mod {
  final Directory dir;
  ModInfo info;
  DstPub pub;

  Mod({required this.dir, required this.info, required this.pub});

  String get path => dir.path;
  String get folderName => p.basename(dir.path);

  File get modinfoFile => File(p.join(dir.path, 'modinfo.lua'));
  File get pubFile => File(p.join(dir.path, 'dstpub.json'));

  /// 工坊封面:jpg/png/gif 均可,同时存在多个时取最近修改的(「更换」后新图生效)。
  File? get preview {
    final cands = [
      for (final n in ['preview.jpg', 'preview.png', 'preview.gif'])
        File(p.join(dir.path, n)),
    ].where((f) => f.existsSync()).toList();
    if (cands.isEmpty) return null;
    cands.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return cands.first;
  }

  static Future<Mod?> load(Directory d) async {
    final mi = File(p.join(d.path, 'modinfo.lua'));
    if (!await mi.exists()) return null;
    final info = ModInfo.parse(await mi.readAsString());
    var pub = DstPub();
    final pf = File(p.join(d.path, 'dstpub.json'));
    if (await pf.exists()) {
      try {
        pub = DstPub.fromJson(
            jsonDecode(await pf.readAsString()) as Map<String, dynamic>);
      } catch (_) {/* 损坏的配置按空处理 */}
    }
    return Mod(dir: d, info: info, pub: pub);
  }

  Future<void> savePub() async {
    const enc = JsonEncoder.withIndent('  ');
    await pubFile.writeAsString(enc.convert(pub.toJson()));
  }

  /// 把新版本号写回 modinfo.lua 的 version 字段。
  Future<void> writeVersion(String v) async {
    var text = await modinfoFile.readAsString();
    text = text.replaceFirst(
      RegExp('version\\s*=\\s*("[^"]*"|\'[^\']*\')'),
      'version = "$v"',
    );
    await modinfoFile.writeAsString(text);
    info = ModInfo.parse(text);
  }
}

/// 版本比较:按 . 和 - 切段,逐段数值比较,非数字段按 0。
int cmpVer(String a, String b) {
  final as = a.split(RegExp(r'[.\-]'));
  final bs = b.split(RegExp(r'[.\-]'));
  final n = as.length > bs.length ? as.length : bs.length;
  for (var i = 0; i < n; i++) {
    final x = i < as.length ? int.tryParse(as[i]) ?? 0 : 0;
    final y = i < bs.length ? int.tryParse(bs[i]) ?? 0 : 0;
    if (x != y) return x - y;
  }
  return 0;
}

/// 末段 +1,保留 -beta 之类后缀:0.9-beta → 0.10-beta。
String bumpVer(String v) {
  final parts = v.split('.');
  final last = parts.last;
  final m = RegExp(r'^(\d+)').firstMatch(last);
  if (m != null) {
    final n = int.parse(m.group(1)!);
    parts[parts.length - 1] = '${n + 1}${last.substring(m.group(1)!.length)}';
    return parts.join('.');
  }
  return '$v.1';
}

/// 自增建议:取「本地版本」与「工坊版本」中较高者 +1,
/// 解决"新建文件夹更新老条目、本地版本号偏低"的场景。
String suggestBump(String local, String? workshop) {
  var base = local.isEmpty ? '0' : local;
  if (workshop != null && workshop.isNotEmpty && cmpVer(workshop, base) >= 0) {
    base = workshop;
  }
  return bumpVer(base);
}

/// 由版本号自动判定发布通道(可被用户手动覆盖)。
String detectChannel(String v) {
  final s = v.toLowerCase();
  if (s.contains('alpha')) return 'alpha';
  if (s.contains('beta') || s.contains('rc') || s.contains('pre')) {
    return 'beta';
  }
  return 'release';
}
