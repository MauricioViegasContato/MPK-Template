import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class PdfService {
  Future<void> exportMonthlyReport(String filialId, String monthName, List<Map<String, dynamic>> reports) async {
    final pdf = pw.Document();
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Relatório Mensal - $filialId', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text(monthName, style: const pw.TextStyle(fontSize: 18)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              context: context,
              headers: ['Data', 'Func.', 'Receita', 'Dinheiro', 'TEF/POS', 'Status'],
              data: reports.map((r) {
                 final tef = (r['cartao_tef'] ?? 0.0) as num;
                 final pos = (r['cartao_pos'] ?? 0.0) as num;
                 return [
                   _formatDate(r['caixa_referente']),
                   r['nome_funcionario_original'] ?? '-',
                   currency.format(r['receita_dia'] ?? 0),
                   currency.format(r['dinheiro'] ?? 0),
                   currency.format(tef + pos),
                   r['status'] ?? 'pendente',
                 ];
              }).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellAlignment: pw.Alignment.center,
              cellStyle: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Totais do Mês:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            _buildTotals(reports, currency),
          ];
        },
      ),
    );

    // Save & Share
    print('DEBUG: PdfService: Salvando arquivo PDF...');
    final bytes = await pdf.save();
    final directory = await getApplicationDocumentsDirectory();
    final sanitizedFilename = 'Relatorio_PDF_${filialId}_$monthName'.replaceAll(' ', '_');
    final file = File('${directory.path}/$sanitizedFilename.pdf');
    await file.writeAsBytes(bytes);
    print('DEBUG: PdfService: Arquivo salvo em ${file.path}');

    print('DEBUG: PdfService: Iniciando compartilhamento...');
    await Share.shareXFiles([XFile(file.path)], text: 'Relatório PDF - $filialId - $monthName');
    print('DEBUG: PdfService: Compartilhamento acionado.');
  }

  pw.Widget _buildTotals(List<Map<String, dynamic>> reports, NumberFormat currency) {
    double totalReceita = 0;
    double totalDinheiro = 0;
    
    for (var r in reports) {
      totalReceita += (r['receita_dia'] ?? 0.0) as num;
      totalDinheiro += (r['dinheiro'] ?? 0.0) as num;
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Receita Total: ${currency.format(totalReceita)}'),
        pw.Text('Dinheiro Total: ${currency.format(totalDinheiro)}'),
      ]
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}';
    } catch (_) {
      return dateStr;
    }
  }
  Future<void> exportSingleReport(Map<String, dynamic> report) async {
    final pdf = pw.Document();
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    final filial = report['filial_id'] ?? 'Filial';
    final dateStr = _formatDate(report['caixa_referente']);
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Relatório Diário - $filial', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Ref: $dateStr', style: const pw.TextStyle(fontSize: 16)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              
              // Status
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  children: [
                    pw.Text('Status: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text((report['status'] ?? 'pendente').toString().toUpperCase()),
                    pw.Spacer(),
                    pw.Text('Enviado por: ${report['nome_funcionario_original'] ?? 'N/D'}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              
              // Financials
              pw.Text('Resumo Financeiro', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              _buildRow('Saldo Inicial', report['saldo_inicial'], currency),
              pw.Divider(),
              _buildRow('Receita Total', report['receita_dia'], currency, isBold: true),
              pw.Divider(),
              _buildRow('Dinheiro', report['dinheiro'], currency),
              _buildRow('Cartão TEF', report['cartao_tef'], currency),
              _buildRow('Cartão POS', report['cartao_pos'], currency),
              _buildRow('Depósito', report['deposito'], currency),
              
              pw.SizedBox(height: 20),
              
              if (report['observacoes'] != null && report['observacoes'].toString().isNotEmpty) ...[
                pw.Text('Observações:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Paragraph(text: report['observacoes']),
              ]
            ],
          );
        },
      ),
    );

    // Save & Share
    final bytes = await pdf.save();
    final directory = await getApplicationDocumentsDirectory();
    final sanitizedFilename = 'Relatorio_Diario_${filial}_${dateStr.replaceAll('/', '-')}_${DateTime.now().millisecondsSinceEpoch}'.replaceAll(' ', '_');
    final file = File('${directory.path}/$sanitizedFilename.pdf');
    await file.writeAsBytes(bytes);
    
    await Share.shareXFiles([XFile(file.path)], text: 'Relatório Diário - $filial - $dateStr');
  }

  pw.Widget _buildRow(String label, dynamic value, NumberFormat fmt, {bool isBold = false}) {
    final style = isBold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : const pw.TextStyle();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(fmt.format(value ?? 0.0), style: style),
        ],
      ),
    );
  }
}
