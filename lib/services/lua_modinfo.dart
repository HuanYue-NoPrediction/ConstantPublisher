import 'dart:convert';
import 'dart:isolate';

import 'package:lua_dardo/lua.dart';

import 'lua_normalize.dart';

const _prelude = '''
function ChooseTranslationTable(t)
  if type(t) ~= 'table' then return t end
  return t[locale] or t[1]
end
''';

const _blocked = ['os', 'package', 'require', 'dofile', 'loadfile'];

const _keys = [
  'name',
  'author',
  'version',
  'description',
  'api_version_dst',
  'api_version',
];

const _flags = ['client_only_mod', 'server_only_mod', 'all_clients_require_mod'];

Future<Map<String, String>?> evalModinfo(
  List<int> bytes, {
  String folderName = '',
  String locale = 'zh',
  Duration timeout = const Duration(seconds: 3),
}) async {
  final rp = ReceivePort();
  Isolate? iso;
  try {
    iso = await Isolate.spawn(
        _entry, [rp.sendPort, bytes, folderName, locale],
        errorsAreFatal: true);
    final res = await rp.first.timeout(timeout);
    if (res is Map) return res.cast<String, String>();
    return null;
  } catch (_) {
    return null;
  } finally {
    rp.close();
    iso?.kill(priority: Isolate.immediate);
  }
}

void _entry(List<dynamic> args) {
  final send = args[0] as SendPort;
  Map<String, String>? out;
  try {
    out = _run((args[1] as List).cast<int>(), args[2] as String,
        args[3] as String);
  } catch (_) {
    out = null;
  }
  send.send(out);
}

Map<String, String>? _run(List<int> bytes, String folderName, String locale) {
  final source =
      normalizeLua(String.fromCharCodes(bytes.map((b) => b & 0xFF)));
  final ls = LuaState.newState();
  ls.openLibs();
  for (final g in _blocked) {
    ls.pushNil();
    ls.setGlobal(g);
  }
  ls.pushString(folderName);
  ls.setGlobal('folder_name');
  ls.pushString(locale);
  ls.setGlobal('locale');
  if (ls.loadString(_prelude) != ThreadStatus.luaOk) return null;
  if (ls.pCall(0, 0, 0) != ThreadStatus.luaOk) return null;
  if (ls.loadString(source) != ThreadStatus.luaOk) return null;
  if (ls.pCall(0, 0, 0) != ThreadStatus.luaOk) return null;

  final out = <String, String>{};
  for (final k in _keys) {
    final v = _readString(ls, k);
    if (v.isNotEmpty) out[k] = v;
  }
  for (final k in _flags) {
    if (_readBool(ls, k)) out[k] = 'true';
  }

  final missing = [
    for (final k in [..._keys, ..._flags])
      if (!out.containsKey(k)) k,
  ];
  if (missing.isNotEmpty) {
    final stmts = splitTopLevelAssignments(source);
    for (final k in missing) {
      final code = stmts[k];
      if (code == null) continue;
      if (ls.loadString(code) != ThreadStatus.luaOk) continue;
      if (ls.pCall(0, 0, 0) != ThreadStatus.luaOk) continue;
      if (_flags.contains(k)) {
        if (_readBool(ls, k)) out[k] = 'true';
      } else {
        final v = _readString(ls, k);
        if (v.isNotEmpty) out[k] = v;
      }
    }
  }
  return out.isEmpty ? null : out;
}


String _decodeBytes(String s) {
  final units = s.codeUnits;
  for (final u in units) {
    if (u > 0xFF) return s;
  }
  return utf8.decode(units, allowMalformed: true);
}

String _readString(LuaState ls, String key) {
  ls.getGlobal(key);
  var out = '';
  final t = ls.type(-1);
  if (t == LuaType.luaString || t == LuaType.luaNumber) {
    out = _decodeBytes(ls.toStr(-1) ?? '');
  }
  ls.pop(1);
  return out;
}

bool _readBool(LuaState ls, String key) {
  ls.getGlobal(key);
  final t = ls.type(-1);
  final out = t == LuaType.luaBoolean && ls.toBoolean(-1);
  ls.pop(1);
  return out;
}
