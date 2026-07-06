import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/mod.dart';

/// 默认忽略规则 —— 官方工具"整包全传"痛点的解药。
const List<String> kDefaultIgnore = [
  '.git', '.svn', '.vscode', '.idea',
  'exported',
  '*.psd', '*.aseprite', '*.xcf',
  '*.zip', '*.rar', '*.7z',
  '*.bak', '*.tmp',
  '*.exe', '*.dll', '*.pdb', // 工坊会拒收可执行文件

  'Thumbs.db', 'desktop.ini',
  'dstpub.json', '.modignore',
  'mod.manifest',
];

class StagedEntry {
  final String rel; // 相对模组根目录的路径,用 / 分隔
  final int size;
  final bool skipped;
  final String? reason; // '默认忽略' / '.modignore'

  const StagedEntry(this.rel, this.size, this.skipped, this.reason);
}

class StagePlan {
  final List<StagedEntry> entries;
  StagePlan(this.entries);

  List<StagedEntry> get kept => entries.where((e) => !e.skipped).toList();
  List<StagedEntry> get dropped => entries.where((e) => e.skipped).toList();
  int get totalSize => kept.fold(0, (a, e) => a + e.size);

  /// 仅作参考线:SteamPipe 工坊没有固定体积硬上限,
  /// 100MB 是老 Steam Cloud 通道的历史限制;超过只提示,不拦截。
  static const int sizeReference = 100 * 1024 * 1024;
  bool get overLimit => totalSize > sizeReference;
}

/// 简易 glob:'*' 通配任意字符;模式匹配路径本身或其任一父目录段。
bool _match(String rel, String pattern) {
  final re = RegExp(
    '^${RegExp.escape(pattern).replaceAll(r'\*', '[^/]*')}\$',
    caseSensitive: false,
  );
  if (re.hasMatch(rel)) return true;
  final segments = rel.split('/');
  for (var i = 0; i < segments.length; i++) {
    if (re.hasMatch(segments[i])) return true;
    if (re.hasMatch(segments.sublist(0, i + 1).join('/'))) return true;
  }
  return false;
}

/// 读取 .modignore(每行一条,# 开头为注释)。
Future<List<String>> loadModIgnore(Mod mod) async {
  final f = File(p.join(mod.path, '.modignore'));
  if (!await f.exists()) return [];
  return (await f.readAsLines())
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
}

/// 扫描模组目录,给出"将上传/将忽略"清单(dry-run 直接展示这个)。
Future<StagePlan> planStage(Mod mod) async {
  final custom = [...await loadModIgnore(mod), ...mod.pub.ignore];
  final entries = <StagedEntry>[];

  await for (final ent in mod.dir.list(recursive: true, followLinks: false)) {
    if (ent is! File) continue;
    final rel = p.relative(ent.path, from: mod.path).replaceAll('\\', '/');
    // 官方规则:以 . 开头的目录不上传 —— 保留该行为
    final hiddenDir = rel.split('/').any((s) => s.startsWith('.') && s != '.modignore');
    String? reason;
    if (mod.pub.keep.any((pat) => _match(rel, pat))) {
      reason = null; // keep 白名单:强制保留,压过一切忽略规则
    } else if (hiddenDir || kDefaultIgnore.any((pat) => _match(rel, pat))) {
      reason = '默认忽略';
    } else if (custom.any((pat) => _match(rel, pat))) {
      reason = '.modignore';
    }
    final size = await ent.length();
    entries.add(StagedEntry(rel, size, reason != null, reason));
  }
  entries.sort((a, b) => a.rel.compareTo(b.rel));
  return StagePlan(entries);
}

/// 把清洗后的副本复制到临时目录,返回该目录 —— steamcmd 的 contentfolder 指向它,
/// 这样无论官方还是我们,永远不会把私有文件传上工坊。
Future<Directory> materialize(Mod mod, StagePlan plan) async {
  final staging = Directory(
      p.join(Directory.systemTemp.path, 'dst_mod_publisher', mod.folderName));
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);

  for (final e in plan.kept) {
    final src = File(p.join(mod.path, e.rel));
    final dst = File(p.join(staging.path, e.rel));
    await dst.parent.create(recursive: true);
    await src.copy(dst.path);
  }
  if (mod.pub.appId == 322330) {
    await _writeModManifest(staging, plan.kept.map((e) => e.rel));
  }
  return staging;
}

int _sdbm(String s) {
  var h = 0;
  for (final b in utf8.encode(s)) {
    h = (h * 65599 + b) & 0xFFFFFFFF;
  }
  return h;
}

Uint8List _u32le(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

Future<void> _writeModManifest(
    Directory staging, Iterable<String> rels) async {
  final hashes = [
    for (final r in rels)
      if (r.toLowerCase() != 'mod.manifest') _sdbm(r.toLowerCase()),
  ];
  final b = BytesBuilder()
    ..add(ascii.encode('MNFS'))
    ..add(_u32le(1))
    ..add(_u32le(hashes.length));
  for (final h in hashes) {
    b.add(_u32le(h));
  }
  await File(p.join(staging.path, 'mod.manifest')).writeAsBytes(b.toBytes());
}
