import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import 'package:intl/intl.dart';
import '../screens/report_details_screen.dart';

class HistoryFeedCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback? onRefresh;

  const HistoryFeedCard({
    super.key, 
    required this.report, 
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    // Use caixa_referente logic as requested
    final rawDate = report['caixa_referente'];
    String dateStr = 'Data desconhecida';
    if (rawDate != null) {
      final dateObj = DateTime.parse(rawDate);
      dateStr = DateFormat('dd/MM/yyyy', 'pt_BR').format(dateObj);
    }

    final receita = report['receita_dia'] ?? 0.0;
    final status = report['status'] ?? 'pendente';
    final isPendente = status == 'pendente';
    // If we have 'nome_funcionario_original', show it? 
    // Usually 'Old Style' implies simpler list item or card with 'Ver Detalhes'.

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Header Row: Status & Date
            Row(
              children: [
                 Container(
                   padding: const EdgeInsets.all(8),
                   decoration: BoxDecoration(
                     color: AppColors.primary.withOpacity(0.1),
                     shape: BoxShape.circle,
                   ),
                   child: const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                 ),
                 const SizedBox(width: 12),
                 Expanded(
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text(
                         'Referente: $dateStr',
                         style: TextStyle(
                           fontSize: 15,
                           fontWeight: FontWeight.bold,
                           color: Theme.of(context).textTheme.bodyLarge?.color,
                         ),
                       ),
                     ],
                   ),
                 ),
                 Container(
                   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                   decoration: BoxDecoration(
                     color: isPendente ? AppColors.warning.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(12),
                     border: Border.all(color: isPendente ? AppColors.warning : AppColors.success),
                   ),
                   child: Text(
                     status.toUpperCase(),
                     style: TextStyle(
                       fontSize: 10,
                       fontWeight: FontWeight.bold,
                       color: isPendente ? AppColors.warning : AppColors.success,
                     ),
                   ),
                 ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Financial Big Number
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Receita Total',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
                Text(
                  currencyFormat.format(receita),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Action Button
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                   final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReportDetailsScreen(report: report),
                    ),
                  );
                  if (result == true && onRefresh != null) {
                    onRefresh!();
                  }
                },
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('VER DETALHES'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
