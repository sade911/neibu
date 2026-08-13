import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../../constants/app_theme.dart';
import '../../constants/ali_icons.dart';
import '../../providers/vpn_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/desktop_title_bar.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  bool _rememberPassword = false;
  bool _agreedToPrivacy = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final vpn = context.read<VpnProvider>();
    _emailController = TextEditingController(text: vpn.user?.email ?? '');
    _passwordController = TextEditingController();


    _loadSavedInfo();
  }

  void _loadSavedInfo() async {
    final vpn = context.read<VpnProvider>();
    final isRemember = await vpn.isRememberPassword();
    if (isRemember) {
      final credentials = await vpn.loadCredentials();
      if (credentials['email'] != null && credentials['email']!.isNotEmpty) {
        setState(() {
          _rememberPassword = true;
          _emailController.text = credentials['email']!;
          _passwordController.text = credentials['password'] ?? '';
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  void _doLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 请输入完整的邮箱和密码')),
      );
      return;
    }

    if (!_agreedToPrivacy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 请勾选同意隐私政策与服务条款')),
      );
      return;
    }

    final vpn = context.read<VpnProvider>();



    final success = await vpn.login(email, password);

    if (success) {
      if (_rememberPassword) {
        await vpn.saveCredentials(email, password);
      } else {
        await vpn.clearCredentials();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 登录成功，正在加载订阅节点...')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 登录失败，请检查账号密码或服务器地址')),
        );
      }
    }
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: const Row(
          children: [
            Icon(AliIcons.shield, color: AppTheme.primaryCyan),
            SizedBox(width: 8),
            Text(
              '隐私政策与服务协议',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('版本更新日期：2026年', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                SizedBox(height: 16),
                Text('一、隐私声明', style: TextStyle(color: AppTheme.primaryCyan, fontSize: 14, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  '1. 本客户端严格遵守无日志原则，不记录或监控您的通信内容与访问历史。\n'
                  '2. 仅保留用于账户计费与订阅校验的基本账号数据。',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
                ),
                SizedBox(height: 16),
                Text('二、安全防护', style: TextStyle(color: AppTheme.primaryCyan, fontSize: 14, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  '所有身份验证与请求数据均使用 256 位 TLS 强加密通道传输，本地密码安全托管。',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('已知晓', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();

    return Scaffold(
      appBar: const DesktopTitleBar(title: 'UUVPN PRO'),
      body: Container(
        decoration: const BoxDecoration(
          color: AppTheme.darkBg,
          image: DecorationImage(
            image: NetworkImage('https://images.unsplash.com/photo-1550745165-9bc0b252726f?w=800&auto=format&fit=crop'),
            fit: BoxFit.cover,
            opacity: 0.04,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo 科技感光环
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryCyan.withValues(alpha: 0.4),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      AliIcons.vpn,
                      size: 46,
                      color: const Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'UUVPN PRO',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '全协议极速安全加速代理引擎',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 登录表单 GlassCard
                  GlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '账号登录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 18),

                        // 邮箱
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: '邮箱账号',
                            hintText: 'your_name@domain.com',
                            prefixIcon: Icon(AliIcons.email, color: AppTheme.primaryCyan),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 密码
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: '密码',
                            hintText: '••••••••',
                            prefixIcon: const Icon(AliIcons.lock, color: AppTheme.primaryCyan),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? AliIcons.visibilityOff : AliIcons.visibility,
                                color: AppTheme.textMuted,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // 记住密码 & 忘记密码
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => _rememberPassword = !_rememberPassword),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: Checkbox(
                                      value: _rememberPassword,
                                      onChanged: (v) => setState(() => _rememberPassword = v ?? false),
                                      activeColor: AppTheme.primaryCyan,
                                      checkColor: Colors.black,
                                      side: const BorderSide(color: AppTheme.textMuted),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('记住密码', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                                );
                              },
                              child: const Text(
                                '忘记密码？',
                                style: TextStyle(color: AppTheme.primaryCyan, fontSize: 13),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // 隐私条款勾选
                        GestureDetector(
                          onTap: () => setState(() => _agreedToPrivacy = !_agreedToPrivacy),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: Checkbox(
                                  value: _agreedToPrivacy,
                                  onChanged: (v) => setState(() => _agreedToPrivacy = v ?? false),
                                  activeColor: AppTheme.primaryCyan,
                                  checkColor: Colors.black,
                                  side: const BorderSide(color: AppTheme.textMuted),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                    children: [
                                      const TextSpan(text: '阅读并同意 '),
                                      TextSpan(
                                        text: '《隐私政策与服务协议》',
                                        style: const TextStyle(color: AppTheme.primaryCyan),
                                        recognizer: TapGestureRecognizer()..onTap = _showPrivacyDialog,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // 提交登录按钮
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: (vpn.isLoading || !_agreedToPrivacy)
                                ? null
                                : () async {
                                    final email = _emailController.text.trim();
                                    final password = _passwordController.text.trim();

                                    if (email.isEmpty || password.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('请输入完整的邮箱与密码')),
                                      );
                                      return;
                                    }

                                    final success = await vpn.login(email, password);

                                    if (success && _rememberPassword) {
                                      await vpn.saveCredentials(email, password);
                                    } else if (!_rememberPassword) {
                                      await vpn.clearCredentials();
                                    }

                                    if (context.mounted) {
                                      if (success) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('🎉 账号同步成功！节点与订阅信息已加载'),
                                            backgroundColor: AppTheme.successGreen,
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('登录失败，请检查账号密码或后端 URL'),
                                            backgroundColor: AppTheme.errorRed,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _agreedToPrivacy ? AppTheme.primaryCyan : Colors.white12,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                              ),
                            ),
                            child: vpn.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                                  )
                                : const Text(
                                    '登录',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('还没有账号？', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RegisterPage()),
                          );
                        },
                        child: const Text(
                          '免费注册',
                          style: TextStyle(
                            color: AppTheme.primaryCyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

