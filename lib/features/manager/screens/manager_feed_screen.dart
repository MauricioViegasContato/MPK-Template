import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/service_locator.dart';
import '../../auth/screens/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Will create this widget next
import 'package:intl/intl.dart';
import '../../../../services/notification_service.dart';
import '../widgets/feed_card.dart';
import 'chat_screen.dart';
import 'company_history_screen.dart';
import '../../../../core/services/theme_service.dart';

class ManagerFeedScreen extends StatefulWidget {
  const ManagerFeedScreen({super.key});

  @override
  State<ManagerFeedScreen> createState() => _ManagerFeedScreenState();
}

class _ManagerFeedScreenState extends State<ManagerFeedScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    setState(() => _isLoading = true);
    try {
      final data = await ServiceLocator.repository.getRelatoriosGerente(null);
      if (mounted) {
        setState(() {
          _reports = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NotificationService().showLocalNotification(
          id: 900,
          title: 'Erro de Carregamento',
          body: 'Não foi possível carregar o feed: $e',
        );
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_email');
    await prefs.remove('saved_password');
    
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Visão Geral'),
        centerTitle: false,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService().themeMode,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                color: Colors.white,
                onPressed: () => ThemeService().toggleTheme(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            color: Colors.white,
            onPressed: _loadFeed,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            color: Colors.white,
            onPressed: () => _logout(),
          ),
          IconButton(
            icon: const Icon(Icons.campaign), 
            color: Colors.white,
            tooltip: 'Comunicado Geral',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatScreen(
                    filialId: 'GLOBAL', 
                    title: '📢 Comunicado Geral'
                  ),
                ),
              );
            },
          ),
        ],
      ),
      // Removed Dummy Export Button
      floatingActionButton: null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.store_mall_directory_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhuma empresa cadastrada',
                        style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _getUniqueCompanies().length,
                  itemBuilder: (context, index) {
                    final companyId = _getUniqueCompanies()[index];
                    final latestReport = _getLatestReportFor(companyId);

                    return _buildCompanyCard(companyId, latestReport);
                  },
                ),
    );
  }

  // Helpers
  List<String> _getUniqueCompanies() {
    return _reports.map((r) => r['filial_id'] as String).toSet().toList();
  }

  Map<String, dynamic> _getLatestReportFor(String companyId) {
    final companyReports = _reports.where((r) => r['filial_id'] == companyId).toList();
    // Sort Descending (Safe)
    companyReports.sort((a, b) {
       final dateA = a['caixa_referente'] as String? ?? '';
       final dateB = b['caixa_referente'] as String? ?? '';
       return dateB.compareTo(dateA);
    });
    return companyReports.first;
  }

  Widget _buildCompanyCard(String companyId, Map<String, dynamic> report) {
    // IMPORTANT: We are delegating UI to FeedCard widget for consistency and cleaner code.
    // FeedCard handles the 'onRefresh' callback internally.
    return FeedCard(
      report: report,
      buttonLabel: 'Acessar Filial',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CompanyHistoryScreen(
              filialId: companyId,
            ),
          ),
        ).then((_) {
          // Refresh feed when coming back (in case status changed in history)
          _loadFeed(); 
        });
      },
      onRefresh: _loadFeed,
    );
  }

  Widget _buildStatusBadge(String status) {
    final isPendente = status == 'pendente';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPendente ? AppColors.warning.withOpacity( 0.2) : AppColors.success.withOpacity( 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isPendente ? 'Pendente' : 'Aprovado',
        style: TextStyle(
          color: isPendente ? AppColors.warning : AppColors.success,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
