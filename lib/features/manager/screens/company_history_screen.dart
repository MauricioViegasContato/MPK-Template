import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../services/notification_service.dart';
import '../widgets/feed_card.dart';
import '../widgets/history_feed_card.dart';
import '../../../../core/services/excel_service.dart'; // Import added
import '../../../../core/services/pdf_service.dart';  // Import added

class CompanyHistoryScreen extends StatefulWidget {
  final String filialId;

  const CompanyHistoryScreen({super.key, required this.filialId});

  @override
  State<CompanyHistoryScreen> createState() => _CompanyHistoryScreenState();
}

class _CompanyHistoryScreenState extends State<CompanyHistoryScreen> {
  DateTime? _selectedMonth;
  bool _isLoading = true; // Restored
  Map<String, List<Map<String, dynamic>>> _groupedReports = {}; // Restored

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async { // function start to match context
    setState(() => _isLoading = true);
    // Fetch reports specifically for this company
    final allReports = await ServiceLocator.repository.getRelatoriosGerente(widget.filialId);
    
    // Sort by Date Descending
    allReports.sort((a, b) {
       final dateA = a['caixa_referente'] as String? ?? '';
       final dateB = b['caixa_referente'] as String? ?? '';
       return dateB.compareTo(dateA);
    });

    // Group by Month
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var report in allReports) {
      final date = DateTime.parse(report['caixa_referente']);
      
      // Filter if month selected
      if (_selectedMonth != null) {
        if (date.month != _selectedMonth!.month || date.year != _selectedMonth!.year) {
           continue; 
        }
      }

      final monthKey = DateFormat('MMMM yyyy', 'pt_BR').format(date); // Ex: "Outubro 2023"
      
      if (!grouped.containsKey(monthKey)) {
        grouped[monthKey] = [];
      }
      grouped[monthKey]!.add(report);
    }

    if (mounted) {
      setState(() {
        _groupedReports = grouped;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context, 
      initialDate: _selectedMonth ?? now, 
      firstDate: DateTime(2020), 
      lastDate: now,
      helpText: 'Selecione o Mês/Ano',
      locale: const Locale('pt', 'BR'),
      initialDatePickerMode: DatePickerMode.year, // Encourage Year/Month selection
    );
    
    if (picked != null) {
      setState(() {
        _selectedMonth = picked;
      });
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Capitalize Title
    final title = widget.filialId;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Text('Histórico de Fechamentos', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        actions: [
          if (_selectedMonth != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() => _selectedMonth = null);
                _loadHistory();
              },
            ),
          IconButton(
            icon: Icon(_selectedMonth == null ? Icons.filter_alt_outlined : Icons.filter_alt),
            onPressed: _pickMonth,
            tooltip: 'Filtrar por Mês',
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _groupedReports.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.event_busy, size: 64, color: AppColors.secondary),
                   const SizedBox(height: 16),
                   Text(
                     _selectedMonth != null 
                       ? 'Nenhum relatório em ${DateFormat('MMMM/yy', 'pt_BR').format(_selectedMonth!)}'
                       : 'Nenhum histórico encontrado.',
                     style: const TextStyle(color: AppColors.textSecondary),
                   ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _groupedReports.length,
              itemBuilder: (context, index) {
                final monthKey = _groupedReports.keys.elementAt(index);
                final monthReports = _groupedReports[monthKey]!;

                return Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     // Month Header
                     Padding(
                       padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
                       child: Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                           Text(
                             monthKey.toUpperCase(),
                             style: const TextStyle(
                               color: AppColors.textSecondary,
                               fontWeight: FontWeight.bold,
                               fontSize: 14,
                               letterSpacing: 1.2
                             ),
                           ),
                           Row(
                             children: [
                               IconButton(
                                 icon: const Icon(Icons.table_view, size: 24, color: Colors.green),
                                  onPressed: () async {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Gerando Excel... Aguarde.')),
                                    );
                                    try {
                                       print('DEBUG: Solicitando exportação Excel...');
                                       await ExcelService().exportMonthlyReport(
                                         widget.filialId, 
                                         monthKey, 
                                         monthReports
                                       );
                                       if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Pronto! Escolha onde salvar o Excel.')),
                                          );
                                       }
                                    } catch (e) {
                                       print('DEBUG: EXCEL ERROR: $e');
                                       if (context.mounted) {
                                         ScaffoldMessenger.of(context).showSnackBar(
                                           SnackBar(content: Text('Erro ao exportar Excel: $e'))
                                         );
                                       }
                                    }
                                  },
                                 tooltip: 'Exportar Excel',
                               ),
                               IconButton(
                                 icon: const Icon(Icons.picture_as_pdf, size: 24, color: AppColors.primary),
                                 onPressed: () async {
                                    try {
                                       await PdfService().exportMonthlyReport(
                                         widget.filialId, 
                                         monthKey, 
                                         monthReports
                                       );
                                    } catch (e) {
                                       if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Erro ao exportar PDF: $e'))
                                          );
                                       }
                                    }
                                 },
                                 tooltip: 'Exportar PDF',
                               ),
                             ],
                           ),
                         ],
                       ),
                     ),
                     // Reports List
                     ...monthReports.map((report) => HistoryFeedCard(
                        report: report,
                        onRefresh: _loadHistory, // Enable refresh on return
                     )),
                   ],
                );
              },
            ),
    );
  }
}
