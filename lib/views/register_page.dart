import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_theme.dart';
import '../../providers/vpn_provider.dart';
import '../widgets/glass_card.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _pass1Controller = TextEditingController();
  final _pass2Controller = TextEditingController();
  final _inviteCodeController = TextEditingController();
  
  bool _obscureText1 = true;
  bool _obscureText2 = true;
  bool _isLoading = false;
  int _countdownSeconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _pass1Controller.dispose();
    _pass2Controller.dispose();
    _inviteCodeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdownSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _countdownSeconds = 0);
      } else {
        if (mounted) setState(() => _countdownSeconds--);
      }
    });
  }

  void _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效邮箱地址')),
      );
      return;
    }
    
    final vpn = context.read<VpnProvider>();
    _startCountdown();
    final success = await vpn.sendVerifyCode(email);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '🎉 验证码已成功发送至邮箱' : '验证码发送失败，请稍后重试'),
          backgroundColor: success ? AppTheme.successGreen : AppTheme.errorRed,
        ),
      );
    }
  }

  void _register() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final pass1 = _pass1Controller.text.trim();
    final pass2 = _pass2Controller.text.trim();
    final inviteCode = _inviteCodeController.text.trim();

    if (email.isEmpty || pass1.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写完整的注册信息')),
      );
      return;
    }
    if (pass1.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码长度不得少于 8 位')),
      );
      return;
    }
    if (pass1 != pass2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两次输入的密码不一致')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final vpn = context.read<VpnProvider>();
    final result = await vpn.register(
      email,
      pass1,
      code,
      inviteCode: inviteCode.isNotEmpty ? inviteCode : null,
    );
    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 注册成功！已为您自动绑定账号'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? '注册失败'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('创建 XBoard 账号'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '欢迎加入 UUVPN',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '注册并同步全节点订阅，开启无界网络加速',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 24),

                    // 邮箱
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '邮箱账号',
                        hintText: 'your_name@domain.com',
                        prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryCyan),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 验证码
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: '邮箱验证码 (可选)',
                              hintText: '123456',
                              prefixIcon: Icon(Icons.verified_user_outlined, color: AppTheme.primaryCyan),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _countdownSeconds > 0 ? null : _sendCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.darkSurface,
                              foregroundColor: AppTheme.primaryCyan,
                              elevation: 0,
                              side: const BorderSide(color: AppTheme.primaryCyan),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            child: Text(
                              _countdownSeconds > 0
                                  ? '(${_countdownSeconds}s) 重新发送'
                                  : '获取验证码',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 密码
                    TextField(
                      controller: _pass1Controller,
                      obscureText: _obscureText1,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: '设置密码 (最少 8 位)',
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryCyan),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText1 ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: AppTheme.textMuted,
                          ),
                          onPressed: () => setState(() => _obscureText1 = !_obscureText1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 确认密码
                    TextField(
                      controller: _pass2Controller,
                      obscureText: _obscureText2,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: '确认密码',
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_clock_outlined, color: AppTheme.primaryCyan),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText2 ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: AppTheme.textMuted,
                          ),
                          onPressed: () => setState(() => _obscureText2 = !_obscureText2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 邀请码
                    TextField(
                      controller: _inviteCodeController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '邀请码 (选填)',
                        hintText: '填入邀请码可享专属优惠',
                        prefixIcon: Icon(Icons.card_giftcard_rounded, color: AppTheme.primaryCyan),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 提交注册按钮
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                              )
                            : const Text(
                                '完成注册并登录',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

