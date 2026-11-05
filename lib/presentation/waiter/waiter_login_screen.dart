library teashop_pos.presentation.waiter.waiter_login_screen;

import 'package:flutter/material.dart';

import '../../client/waiter_api_service.dart';
import '../../core/auth/waiter_auth.dart';
import '../../core/constants/app_constants.dart';
import '../app_mode.dart';
import '../app_theme.dart';
import '../common_widgets.dart';
import '../responsive_helpers.dart';
import 'waiter_screen.dart';

/// Gate screen for the Waiter client. The operator enters the Admin Host IP
/// plus their staff credentials; on success the session is stored in
/// [WaiterAuth] and the [WaiterScreen] is shown.
class WaiterLoginScreen extends StatefulWidget {
  const WaiterLoginScreen({super.key});

  @override
  State<WaiterLoginScreen> createState() => _WaiterLoginScreenState();
}

class _WaiterLoginScreenState extends State<WaiterLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ipCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ipCtrl.text = AppConfig.instance.adminIp;
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ip = _ipCtrl.text.trim();
    AppConfig.instance.adminIp = ip;
    AppConfig.instance.resetApi();

    setState(() {
      _loading = true;
      _error = null;
    });

    final healthy = await AppConfig.instance.api.checkHealth();
    if (!healthy) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot reach admin host at $ip:${AppConstants.serverPort}. '
            'Make sure the admin server is running.';
        _loading = false;
      });
      return;
    }

    try {
      final result = await AppConfig.instance.api
          .login(_userCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      if (result.success) {
        WaiterAuth.instance.startSession(
          username: result.username,
          displayName: result.displayName,
          permissions: result.permissions,
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WaiterScreen()),
        );
      } else {
        setState(() {
          _error = result.errorMessage ?? 'Login failed.';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Login failed: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        colors: const [
          Color(0xFF1B5E20),
          Color(0xFF2E7D32),
          Color(0xFF5D4037),
          Color(0xFFF5F0EA),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassCard(
                  opacity: 0.92,
                  blur: 18,
                  radius: 24,
                  elevation: 12,
                  padding: const EdgeInsets.all(28),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.15)),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _logo(),
                        const SizedBox(height: 20),
                        const Text('Waiter Login',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppColors.onSurface)),
                        const SizedBox(height: 6),
                        const Text('Sign in with your staff account',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: AppColors.muted)),
                        const SizedBox(height: 24),
                        appTextField(
                          context: context,
                          label: 'Admin Host IP',
                          controller: _ipCtrl,
                          prefixIcon: Icons.dns,
                          keyboardType: TextInputType.number,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter the admin host IP'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        appTextField(
                          context: context,
                          label: 'Username',
                          controller: _userCtrl,
                          prefixIcon: Icons.person,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter username'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon:
                                Icon(Icons.lock_outline, size: 20),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter password'
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.error, fontSize: 13),
                              textAlign: TextAlign.center),
                        ],
                        const SizedBox(height: 20),
                        appButton(
                            label: 'Sign In',
                            loading: _loading,
                            onPressed: _submit),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceCream,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: AppColors.muted),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Ask your admin for staff credentials. '
                                  'Demo: waiter / waiter123',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.muted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('← Back to role selection'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Center(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.success, AppColors.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.point_of_sale,
            color: Colors.white, size: 38),
      ),
    );
  }
}
