import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../home/screens/home_page.dart';
import '../../manager/screens/gerente_page.dart';
import '../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../home/screens/status_hub_screen.dart'; // App 2.0 Entry Point (Funcionario)
import '../../manager/screens/manager_feed_screen.dart'; // App 2.0 Entry Point (Gerente)
import '../../../core/di/service_locator.dart';
import '../../../../core/services/theme_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _message = '';
  bool _isAutoLogging = false;

  @override
  void initState() {
    super.initState();
    _loadSavedLogin();
  }

  Future<void> _loadSavedLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email');
      final savedPassword = prefs.getString('saved_password');

      if (savedEmail != null && savedPassword != null) {
        setState(() {
          _emailController.text = savedEmail;
          _passwordController.text = savedPassword;
          _isAutoLogging = true;
        });
        
        // Aguardar um pouco para garantir que a UI está pronta
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Auto-login automático
        await _autoLogin(savedEmail, savedPassword);
        
        if (mounted) {
          setState(() {
            _isAutoLogging = false;
          });
        }
      }
    } catch (error) {
      print('❌ Erro ao carregar credenciais salvas: $error');
      if (mounted) setState(() => _isAutoLogging = false);
    }
  }

  Future<void> _autoLogin(String email, String password) async {
    try {
      final user = await ServiceLocator.repository.login(email, password);

      if (user != null) {
         final role = user['role'] as String?;

         if (mounted) {
          if (role == 'gerente') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ManagerFeedScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const StatusHubScreen()),
            );
          }
        }
      }
    } catch (error) {
      print('Auto-login falhou: $error');
    }
  }

  // Função de teste de conectividade
  Future<void> _testarConectividade() async {
    try {
      // Teste simples de ping
      final startTime = DateTime.now();
      await Supabase.instance.client
          .from('users')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 2));
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Conectividade OK! (${duration.inMilliseconds}ms)'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro de conectividade: ${error.toString().split(':').first}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_email', _emailController.text);
    await prefs.setString('saved_password', _passwordController.text);
  }

  Future<void> _signIn() async {
    try {
      setState(() {
        _message = 'Autenticando...';
      });

      final user = await ServiceLocator.repository.login(
        _emailController.text,
        _passwordController.text,
      );

      if (user != null) {
        await _saveLogin();

        setState(() {
          _message = 'Login bem-sucedido!';
        });

        final role = user['role'] as String?;

        if (mounted) {
          if (role == 'gerente') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ManagerFeedScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const StatusHubScreen()),
            );
          }
        }
      } else {
        setState(() {
          _message = 'Falha no login. Verifique suas credenciais.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Erro: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService().themeMode,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                color: isDark ? Colors.white : AppColors.textPrimary,
                onPressed: () => ThemeService().toggleTheme(),
              );
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo / Brand Section
                    Image.asset(
                      'assets/images/Logo3.png',
                      height: 120,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppStrings.loginWelcome,
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.loginSignTo,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Login Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email Corporativo',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _passwordController,
                              decoration: const InputDecoration(
                                labelText: 'Senha',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              obscureText: true,
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton(
                              onPressed: _signIn,
                              child: const Text('ACESSAR PAINEL'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Footer / Extra Actions
                    const SizedBox(height: 32),

                    
                    if (_message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _message.contains('Erro') || _message.contains('Falha')
                                ? AppColors.error.withOpacity(0.1)
                                : AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _message,
                            style: TextStyle(
                              color: _message.contains('Erro') || _message.contains('Falha')
                                  ? AppColors.error
                                  : AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          
          if (_isAutoLogging)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Entrando automaticamente...',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
