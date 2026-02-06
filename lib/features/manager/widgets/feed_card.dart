import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import 'package:intl/intl.dart';
import '../screens/report_details_screen.dart';

class FeedCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback? onRefresh;
  final VoidCallback? onTap; // Custom action
  final String buttonLabel; // Ignored in new design, kept for compatibility

  const FeedCard({
    super.key, 
    required this.report, 
    this.onRefresh,
    this.onTap,
    this.buttonLabel = 'Ver Detalhes',
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    // Extract data
    final filial = report['filial_id'] ?? 'Filial Desconhecida';
    // User requested "created_at" for the date display "Último envio"
    final rawDate = report['created_at'] ?? DateTime.now().toIso8601String();
    final dateObj = DateTime.parse(rawDate);
    final formattedDate = DateFormat('dd/MM - HH:mm', 'pt_BR').format(dateObj);

    final receita = report['receita_dia'] ?? 0.0;
    final status = report['status'] ?? 'pendente';
    final isPendente = status == 'pendente';

      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        color: Theme.of(context).cardTheme.color, // Use theme card color
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: () async {
            if (onTap != null) {
              onTap!();
            } else {
              // Default behavior
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ReportDetailsScreen(report: report),
                ),
              );
              if (result == true && onRefresh != null) {
                onRefresh!();
              }
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER: Icon + Name/Date + Status
                Row(
                  children: [
                    // Icon Container
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.storefront, color: Colors.red, size: 20),
                    ),
                    const SizedBox(width: 12),
                    
                    // Name & Date
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            filial,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyLarge?.color, // Theme text
                            ),
                          ),
                          Text(
                            'Último envio: $formattedDate',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).textTheme.bodyMedium?.color, // Theme text
                            ),
                          ),
                        ],
                      ),
                    ),

                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPendente ? AppColors.warning.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isPendente ? AppColors.warning : AppColors.success),
                        ),
                        child: Text(
                          isPendente ? 'PENDENTE' : 'RECEBIDO',
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
                
                // DIVIDER
                Divider(color: Theme.of(context).dividerColor, height: 1),
                
                const SizedBox(height: 16),

                // REVENUE + CHEVRON
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Receita do Dia',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currencyFormat.format(receita),
                          style: TextStyle(
                            fontSize: 20, 
                            fontWeight: FontWeight.bold, 
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ],
                    ),
                    Icon(Icons.chevron_right, color: Theme.of(context).iconTheme.color?.withOpacity(0.5) ?? Colors.grey),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
