import '../l10n/gen/app_localizations.dart';

String decodeEResult(int code, AppLocalizations t) {
  final text = switch (code) {
    1 => t.er1,
    2 => t.er2,
    3 => t.er3,
    5 => t.er5,
    6 => t.er6,
    8 => t.er8,
    9 => t.er9,
    10 => t.er10,
    15 => t.er15,
    16 => t.er16,
    20 => t.er20,
    25 => t.er25,
    33 => t.er33,
    50 => t.er50,
    84 => t.er84,
    _ => t.erUnknown('$code'),
  };
  return 'EResult $code = $text';
}
