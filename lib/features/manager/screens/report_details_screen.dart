import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl.dart';
import '../../../../services/notification_service.dart';
import '../../../../core/di/service_locator.dart';
import 'chat_screen.dart';
import '../../../../core/services/pdf_service.dart';

class ReportDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> report;

  const ReportDetailsScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final String status = report['status'] ?? 'pendente';
    final bool isPendente = status == 'pendente';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(report['filial_id'] ?? 'Detalhes'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Exportar PDF',
            onPressed: () async {
               // Show loading feedback
               NotificationService().showLocalNotification(
                 id: 201, 
                 title: 'Gerando PDF...', 
                 body: 'Aguarde um momento.'
               );
               
               try {
                  // Import PdfService if needed, but likely via ServiceLocator or direct import
                  // Assuming PdfService is available via import '../core/services/pdf_service.dart'
                  // We need to verify imports first.
                  // For now, let's use the valid logic.
                  await PdfService().exportSingleReport(report);
                  
                  // Service usually shows its own success/error notification or we rely on OS sharing.
               } catch (e) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text('Erro ao gerar PDF: $e')),
                 );
               }
            },
          ),
        ],
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPendente ? AppColors.warning.withOpacity( 0.1) : AppColors.success.withOpacity( 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPendente ? AppColors.warning : AppColors.success,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isPendente ? Icons.pending_actions : Icons.check_circle,
                    color: isPendente ? AppColors.warning : AppColors.success,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPendente ? 'Aprovação Pendente' : 'Aprovado',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isPendente ? AppColors.warning : AppColors.success,
                        ),
                      ),
                      Text(
                        'Referente: ${report['caixa_referente'] != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(report['caixa_referente'])) : ''}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                       Text(
                        'Enviado por: ${report['nome_funcionario_original'] ?? 'N/D'}', // Use original name from report
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                       Text(
                        'Enviado em: ${report['created_at'] != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(report['created_at'])) : ''}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Financial Summary Card
            _buildSection(
              context,
              'Resumo Financeiro',
              Column(
                children: [
                   if (report['saldo_divergente'] == true)
                     Container(
                       margin: const EdgeInsets.only(bottom: 16),
                       padding: const EdgeInsets.all(12),
                       decoration: BoxDecoration(
                         color: AppColors.error.withOpacity( 0.1),
                         borderRadius: BorderRadius.circular(8),
                         border: Border.all(color: AppColors.error),
                       ),
                       child: Row(
                         children: [
                           const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                           const SizedBox(width: 8),
                           Expanded(
                             child: Text(
                               'DIVERGÊNCIA NO SALDO INICIAL!',
                               style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                             ),
                           ),
                         ],
                       ),
                     ),
                  _buildDetailRow(
                    context,
                    'Saldo Inicial', 
                    report['saldo_inicial'], 
                    currencyFormat, 
                    textColor: report['saldo_divergente'] == true ? AppColors.error : null
                  ),
                  const Divider(),
                  _buildDetailRow(context, 'Receita Total', report['receita_dia'], currencyFormat, isBold: true),
                  const Divider(),
                  _buildDetailRow(context, 'Dinheiro', report['dinheiro'], currencyFormat),
                  _buildDetailRow(context, 'Cartão TEF', report['cartao_tef'], currencyFormat),
                  _buildDetailRow(context, 'Cartão POS', report['cartao_pos'], currencyFormat),
                  _buildDetailRow(context, 'ATM', report['atm'], currencyFormat),
                  _buildDetailRow(context, 'Cobranças', report['cobrancas'], currencyFormat),
                  _buildDetailRow(context, 'TEV/TED', report['tev_ted'], currencyFormat),
                  const Divider(),
                  _buildDetailRow(context, 'Depósito', report['deposito'], currencyFormat), // TODO: Link to photo
                  const SizedBox(height: 24),
                  
                  if (report['observacoes'] != null && report['observacoes'].toString().isNotEmpty) ...[
                    const Text('Observações:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(report['observacoes']),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Photos Section
            if (_hasPhotos(report)) ...[
              const SizedBox(height: 24),
              _buildSection(
                context,
                'Comprovantes',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPhotoCategory(context, 'Receita Total', report['comprovante_receita']),
                    _buildPhotoCategory(context, 'Cartão TEF', report['comprovante_cartao_tef']),
                    _buildPhotoCategory(context, 'Cartão POS', report['comprovante_cartao_pos']),
                    _buildPhotoCategory(context, 'ATM', report['comprovante_atm']),
                    _buildPhotoCategory(context, 'Cobranças', report['comprovante_cobrancas']),
                    _buildPhotoCategory(context, 'TEV/TED', report['comprovante_tev_ted']),
                    _buildPhotoCategory(context, 'Depósito', report['comprovante_deposito']),
                  ],
                ),
              ),
            ],
            
             const SizedBox(height: 32),

            // Action Buttons
            if (isPendente) ...[
              ElevatedButton.icon(
                onPressed: () => _approveReport(context),
                icon: const Icon(Icons.check),
                label: const Text('APROVAR FECHAMENTO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _rejectReport(context),
                icon: const Icon(Icons.edit_note),
                label: const Text('SOLICITAR CORREÇÃO'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
            ],
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        filialId: report['filial_id'] ?? 'Filial',
                        title: 'Chat - ${report['filial_id'] ?? 'Filial'}',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Abrir Chat'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity( 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: content,
        ),
      ],
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, dynamic value, NumberFormat format, {bool isBold = false, Color? textColor}) {
    // ... existing implementation
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            fontSize: 16, 
            color: textColor ?? (isBold ? Theme.of(context).textTheme.bodyLarge?.color : Theme.of(context).textTheme.bodyMedium?.color), 
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal
          )),
          Text(
            format.format(value ?? 0.0),
            style: TextStyle(
              fontSize: 18, 
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500, 
              color: textColor ?? Theme.of(context).textTheme.bodyLarge?.color
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectReport(BuildContext context) async {
    final reportId = report['id']?.toString();
    if (reportId == null) return;

    // Optional: Ask for a reason via dialog? For now, direct action.
    try {
      await ServiceLocator.repository.updateRelatorioStatus(reportId, 'corrigir');
      
      if (context.mounted) {
         await NotificationService().showLocalNotification(
            id: 100,
            title: 'Correção Solicitada',
            body: 'Status alterado para correção.'
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _approveReport(BuildContext context) async {
    final reportId = report['id']?.toString();
    if (reportId == null) return;

    try {
      // 1. Atualizar no Repo Real
      await ServiceLocator.repository.updateRelatorioStatus(reportId, 'aprovado');

      if (context.mounted) {
        // 2. Disparar Notificação Local
        await NotificationService().showLocalNotification(
            id: 99,
            title: 'Relatório Aprovado',
            body: 'O fechamento da ${report['filial_id']} foi aprovado.'
        );

        // 3. Voltar com sucesso
        Navigator.pop(context, true);
      }
    }
  catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao aprovar: $e')),
        );
      }
    }
  }
  bool _hasPhotos(Map<String, dynamic> report) {
    return report['comprovante_receita'] != null ||
           report['comprovante_cartao_tef'] != null ||
           report['comprovante_cartao_pos'] != null ||
           report['comprovante_atm'] != null ||
           report['comprovante_cobrancas'] != null ||
           report['comprovante_tev_ted'] != null ||
           report['comprovante_deposito'] != null;
  }

  Widget _buildPhotoCategory(BuildContext context, String title, dynamic urlString) {
    if (urlString == null || urlString.toString().isEmpty) return const SizedBox.shrink();

    final List<String> urls = urlString.toString().split(',');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, left: 16, right: 16, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: urls.map((url) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: InteractiveViewer(
                            child: Image.network(url),
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        url,
                        height: 100,
                        width: 100,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, loadingProgress) {
                           if (loadingProgress == null) return child;
                           return Container(
                             height: 100, width: 100,
                             color: Colors.grey[200],
                             child: const Center(child: CircularProgressIndicator()),
                           );
                        },
                        errorBuilder: (ctx, err, stack) => Container(
                          height: 100, width: 100,
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
