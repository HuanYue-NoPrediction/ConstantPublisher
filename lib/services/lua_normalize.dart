String normalizeLua(String src) {
  final out = StringBuffer();
  var i = 0;
  final n = src.length;
  while (i < n) {
    final c = src[i];

    if (c == '-' && i + 1 < n && src[i + 1] == '-') {
      final lvl = _longBracketLevel(src, i + 2);
      if (lvl >= 0) {
        final end = _longBracketEnd(src, i + 2, lvl);
        out.write(src.substring(i, end));
        i = end;
      } else {
        var j = i;
        while (j < n && src[j] != '\n') {
          j++;
        }
        out.write(src.substring(i, j));
        i = j;
      }
      continue;
    }

    if (c == '"' || c == "'") {
      i = _copyQuoted(src, i, out);
      continue;
    }

    if (c == '[') {
      final lvl = _longBracketLevel(src, i);
      if (lvl >= 0) {
        final end = _longBracketEnd(src, i, lvl);
        out.write(src.substring(i, end));
        i = end;
        continue;
      }
    }

    if (_isDigit(src.codeUnitAt(i)) ||
        (c == '.' && i + 1 < n && _isDigit(src.codeUnitAt(i + 1)))) {
      if (i > 0 && _isNameChar(src.codeUnitAt(i - 1))) {
        out.write(c);
        i++;
        continue;
      }
      i = _copyNumber(src, i, out);
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}

Map<String, String> splitTopLevelAssignments(String src) {
  final out = <String, String>{};
  final bounds = <int>[];
  final names = <String>[];
  var depth = 0;
  var i = 0;
  final n = src.length;
  while (i < n) {
    final c = src[i];

    if (c == '-' && i + 1 < n && src[i + 1] == '-') {
      final lvl = _longBracketLevel(src, i + 2);
      if (lvl >= 0) {
        i = _longBracketEnd(src, i + 2, lvl);
      } else {
        while (i < n && src[i] != '\n') {
          i++;
        }
      }
      continue;
    }
    if (c == '"' || c == "'") {
      final sink = StringBuffer();
      i = _copyQuoted(src, i, sink);
      continue;
    }
    if (c == '[') {
      final lvl = _longBracketLevel(src, i);
      if (lvl >= 0) {
        i = _longBracketEnd(src, i, lvl);
        continue;
      }
    }
    if (c == '(' || c == '{' || c == '[') {
      depth++;
      i++;
      continue;
    }
    if (c == ')' || c == '}' || c == ']') {
      depth--;
      i++;
      continue;
    }

    if (depth == 0 && _isNameStart(src.codeUnitAt(i))) {
      var j = i;
      while (j < n && _isNameChar(src.codeUnitAt(j))) {
        j++;
      }
      final word = src.substring(i, j);
      var k = j;
      while (k < n && (src[k] == ' ' || src[k] == '\t')) {
        k++;
      }
      if (k < n &&
          src[k] == '=' &&
          (k + 1 >= n || src[k + 1] != '=') &&
          !_luaKeywords.contains(word)) {
        bounds.add(i);
        names.add(word);
      }
      i = j;
      continue;
    }
    i++;
  }

  for (var idx = 0; idx < names.length; idx++) {
    final from = bounds[idx];
    final to = idx + 1 < bounds.length ? bounds[idx + 1] : n;
    out[names[idx]] = src.substring(from, to);
  }
  return out;
}

const _luaKeywords = {
  'local',
  'if',
  'then',
  'else',
  'elseif',
  'end',
  'for',
  'while',
  'do',
  'repeat',
  'until',
  'return',
  'function',
  'break',
  'and',
  'or',
  'not',
  'nil',
  'true',
  'false',
  'in',
};

bool _isNameStart(int u) =>
    u == 0x5F || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);

bool _isDigit(int u) => u >= 0x30 && u <= 0x39;

bool _isHexDigit(int u) =>
    _isDigit(u) ||
    (u >= 0x41 && u <= 0x46) ||
    (u >= 0x61 && u <= 0x66);

bool _isNameChar(int u) =>
    u == 0x5F ||
    (u >= 0x41 && u <= 0x5A) ||
    (u >= 0x61 && u <= 0x7A) ||
    _isDigit(u);

int _longBracketLevel(String s, int i) {
  if (i >= s.length || s[i] != '[') return -1;
  var j = i + 1;
  var lvl = 0;
  while (j < s.length && s[j] == '=') {
    lvl++;
    j++;
  }
  return (j < s.length && s[j] == '[') ? lvl : -1;
}

int _longBracketEnd(String s, int i, int lvl) {
  final close = ']${'=' * lvl}]';
  final at = s.indexOf(close, i);
  return at < 0 ? s.length : at + close.length;
}

int _copyQuoted(String s, int i, StringBuffer out) {
  final q = s[i];
  out.write(q);
  var j = i + 1;
  while (j < s.length) {
    final c = s[j];
    if (c == r'\') {
      if (j + 1 >= s.length) {
        out.write(c);
        j++;
        break;
      }
      final u = s.codeUnitAt(j + 1);
      if (_isDigit(u)) {
        var k = j + 1;
        var v = 0;
        var cnt = 0;
        while (k < s.length && cnt < 3 && _isDigit(s.codeUnitAt(k))) {
          v = v * 10 + (s.codeUnitAt(k) - 0x30);
          k++;
          cnt++;
        }
        if (v <= 255) {
          out.write('\\x${v.toRadixString(16).padLeft(2, '0')}');
          j = k;
          continue;
        }
      }
      out.write(s.substring(j, j + 2));
      j += 2;
      continue;
    }
    out.write(c);
    j++;
    if (c == q) break;
  }
  return j;
}

int _copyNumber(String s, int i, StringBuffer out) {
  final n = s.length;
  var j = i;
  if (s[j] == '0' &&
      j + 1 < n &&
      (s[j + 1] == 'x' || s[j + 1] == 'X')) {
    var k = j + 2;
    while (k < n && _isHexDigit(s.codeUnitAt(k))) {
      k++;
    }
    final digits = s.substring(j + 2, k);
    final v = int.tryParse(digits, radix: 16);
    out.write(v == null ? s.substring(j, k) : '$v');
    return k;
  }

  var mantissa = StringBuffer();
  var seenDot = false;
  while (j < n) {
    final u = s.codeUnitAt(j);
    if (_isDigit(u)) {
      mantissa.write(s[j]);
      j++;
      continue;
    }
    if (s[j] == '.' && !seenDot) {
      seenDot = true;
      mantissa.write('.');
      j++;
      continue;
    }
    break;
  }

  var exp = 0;
  var hasExp = false;
  if (j < n && (s[j] == 'e' || s[j] == 'E')) {
    var k = j + 1;
    var sign = 1;
    if (k < n && (s[k] == '+' || s[k] == '-')) {
      if (s[k] == '-') sign = -1;
      k++;
    }
    var digits = StringBuffer();
    while (k < n && _isDigit(s.codeUnitAt(k))) {
      digits.write(s[k]);
      k++;
    }
    if (digits.isNotEmpty) {
      exp = sign * int.parse(digits.toString());
      hasExp = true;
      j = k;
    }
  }

  final text = mantissa.toString();
  if (!hasExp) {
    out.write(text);
    return j;
  }
  out.write(_shiftPoint(text, exp));
  return j;
}

String _shiftPoint(String mantissa, int exp) {
  final dot = mantissa.indexOf('.');
  final intPart = dot < 0 ? mantissa : mantissa.substring(0, dot);
  final fracPart = dot < 0 ? '' : mantissa.substring(dot + 1);
  final digits = '$intPart$fracPart';
  var point = intPart.length + exp;
  String out;
  if (point <= 0) {
    out = '0.${'0' * -point}$digits';
  } else if (point >= digits.length) {
    out = "$digits${'0' * (point - digits.length)}.0";
  } else {
    out = '${digits.substring(0, point)}.${digits.substring(point)}';
  }
  return out;
}
