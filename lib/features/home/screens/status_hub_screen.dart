import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../auth/screens/login_page.dart';
import '../../manager/screens/chat_screen.dart';
import 'story_flow_container.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/theme_service.dart';
import '../../../../services/notification_service.dart'; // Added Import

class StatusHubScreen extends StatefulWidget {
  const StatusHubScreen({super.key});

  @override
  State<StatusHubScreen> createState() => _StatusHubScreenState();
}

class _StatusHubScreenState extends State<StatusHubScreen> {
  bool _isReportSent = false;
  bool _isLoading = true;
  StreamSubscription? _chatSubscription;
  final Set<int> _notifiedIds = {};
  
  @override
  void initState() {
    super.initState();
    _checkStatus();
    _setupChatNotifications();
  }
  
  @override
  void dispose() {
    _chatSubscription?.cancel();
    super.dispose();
  }

  void _setupChatNotifications() async {
    final filialId = ServiceLocator.repository.currentUserFilialId;
    final userId = ServiceLocator.repository.currentUserId;
    
    if (filialId == null || userId == null) return;

    // Listen to messages (Global + Private)
    // We only notify if it's a NEW message. 
    // Ideally, we compare timestamps or look for unread ones.
    // For simplicity in this session: we notify on any message that is 'unread' and 'not mine'.
    
    _chatSubscription = ServiceLocator.repository
        .getMensagens(filialId, includeGlobal: true)
        .listen((messages) {
           if (!mounted) return;
           
           // Simple Logic: Find the latest message not from me
           if (messages.isEmpty) return;
           
           final latest = messages.last;
           final isMe = latest['user_id'] == userId;
           final isRead = latest['read_at'] != null;
           
           if (!isMe && !isRead) {
             final msgId = latest['id']?.hashCode ?? 0;
             
             // Check if we already notified this specific message locally
             if (_notifiedIds.contains(msgId)) return;
             
             _notifiedIds.add(msgId);
             
             final text = latest['mensagem'] ?? 'Nova mensagem';
             final isGlobal = latest['filial_id'] == 'GLOBAL';
             
             NotificationService().showLocalNotification(
               id: msgId,
               title: isGlobal ? '📢 Comunicado Geral' : 'Nova Mensagem da Gerência',
               body: text,
             );
           }
        });
  }
  
  Future<void> _checkStatus() async {
    final now = DateTime.now();
    final yesterdayDate = now.subtract(const Duration(days: 1));
    final yesterdayStr = yesterdayDate.toIso8601String().split('T')[0];
    
    // Check report status
    final report = await ServiceLocator.repository.getRelatorioDiario('user_id', 'B&B', yesterdayStr); 
    // Note: 'user_id' and 'B&B' are placeholders? Ideally, the repository method simply ignores them if it uses RLS or internal user ID.
    // wait, getRelatorioDiario in SupabaseRepository uses arguments? Let's check.
    // Yes: getRelatorioDiario(String userId, String filialId, String date).
    // StatusHubScreen should get real IDs.
    
    final realFilialId = ServiceLocator.repository.currentUserFilialId;
    final realUserId = ServiceLocator.repository.currentUserId;

    if (realFilialId == null || realUserId == null) {
         // Loop or wait?
    }
    
    // Re-fetch using real IDs (or best effort if null, repo might handle it)
    final realReport = await ServiceLocator.repository.getRelatorioDiario(realUserId ?? '', realFilialId ?? '', yesterdayStr);

    if (mounted) {
      setState(() {
        _isReportSent = realReport != null;
        _isLoading = false;
        // Format: "23 de Janeiro"
        _yesterdayFormatted = DateFormat("d 'de' MMMM", 'pt_BR').format(yesterdayDate);
      });
    }
  }

  String _yesterdayFormatted = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Visão Geral'),
        centerTitle: true,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor, // Adapts to Dark/Light
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.white, // Forcing white on primary color background
        ),
        actions: [

          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService().themeMode,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                color: Colors.white, // Always white on Red AppBar
                onPressed: () => ThemeService().toggleTheme(),
              );
            },
          ),
          IconButton(
            // Use foregroundColor to adapt to Light (White on Red) or Dark (White on Dark)
            // If explicit color is needed: Theme.of(context).appBarTheme.foregroundColor
            color: Colors.white, // Force Color property
            icon: const Icon(Icons.campaign, color: Colors.white),
            tooltip: 'Avisos Gerais',
            onPressed: () {
               // Global Chat (Read Only)
               Navigator.push(
                 context, 
                 MaterialPageRoute(builder: (c) => const ChatScreen(
                   filialId: 'GLOBAL', 
                   title: '📢 Avisos Gerais',
                   includeGlobal: false, 
                   readOnly: true, // Employee cannot write here
                 ))
               );
            },
          ),
          IconButton(
            color: Colors.white, // Force Color property
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              // Limpar credenciais para evitar auto-login
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('saved_email');
              await prefs.remove('saved_password');
              
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              }
            },
            tooltip: 'Sair',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Date Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                   Container(
                     padding: const EdgeInsets.all(12),
                     decoration: BoxDecoration(
                       color: AppColors.primary.withOpacity(0.1),
                       shape: BoxShape.circle,
                     ),
                     child: const Icon(Icons.calendar_today, color: AppColors.primary),
                   ),
                   const SizedBox(width: 16),
                   Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text(
                         'Fechamento de Ontem',
                         style: Theme.of(context).textTheme.bodyMedium,
                       ),
                       Text(
                         // TODO: Formatar data dinamicamente
                         _yesterdayFormatted, 
                         style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                       ),
                     ],
                   )
                ],
              ),
            ),
            
            const Spacer(),

            // Main Status Indicator
            Center(
              child: Column(
                children: [
                  Icon(
                    _isReportSent ? Icons.check_circle : Icons.pending_actions,
                    size: 80,
                    color: _isReportSent ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isReportSent ? 'Tudo Certo!' : 'Pendente',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: _isReportSent ? AppColors.success : AppColors.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isReportSent 
                        ? 'O relatório de ontem já foi enviado.' 
                        : 'Você ainda não enviou o fechamento de ontem.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Action Button
            if (_isLoading)
               const Center(child: CircularProgressIndicator())
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const StoryFlowContainer()),
                      );
                      _checkStatus(); // Atualizar ao voltar
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('INICIAR FECHAMENTO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  OutlinedButton.icon(
                    onPressed: () {
                       // We need the filialId. For now, assuming user is tied to one.
                       // Ideally, we get it from the profile or repo.
                       final filialId = ServiceLocator.repository.currentUserFilialId ?? 'Minha Filial';
                       // Import ChatScreen first!
                       Navigator.push(
                         context, 
                         MaterialPageRoute(builder: (c) => ChatScreen(
                           filialId: filialId, 
                           title: 'Chat - $filialId',
                           includeGlobal: false, // PRIVATE ONLY
                         ))
                       );
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('CHAT COM GERÊNCIA'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
