import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/vpn_provider.dart';
import 'views/auth/login_page.dart';
import 'views/home/home_page.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(460, 720),
    minimumSize: Size(400, 600),
    center: true,
    title: 'UUVPN PRO',
    backgroundColor: Color(0xFF0A0E1A),
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => VpnProvider(),
      child: const UuVpnApp(),
    ),
  );
}

class UuVpnApp extends StatelessWidget {
  const UuVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UUVPN PRO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Consumer<VpnProvider>(
        builder: (_, vpn, __) => vpn.isLoggedIn ? const HomePage() : const LoginPage(),
      ),
    );
  }
}
