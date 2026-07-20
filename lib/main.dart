import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/gen/app_localizations.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1180, 780),
    minimumSize: Size(920, 620),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'DST Mod Publisher',
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 先读完主题等偏好再画首帧,消除"亮→暗"闪屏;慢活(扫描/拉取)在 init 内部后台进行
  final state = AppState();
  await state.init();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'DST Mod Publisher',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(state.seed, Brightness.light),
      darkTheme: buildTheme(state.seed, Brightness.dark),
      themeMode: state.themeMode,
      locale: state.appLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const Shell(),
    );
  }
}
