import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/vpn_provider.dart';
import 'views/auth/login_page.dart';
import 'views/home/home_page.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0E1A),
  ));

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
