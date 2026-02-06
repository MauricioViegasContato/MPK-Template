import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExcelService {
  Future<void> exportMonthlyReport(String filialId, String monthName, List<Map<String, dynamic>> reports) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Sheet1'];
    
    // Header
    sheet.appendRow([
      TextCellValue('Data'),
      TextCellValue('Filial'),
      TextCellValue('Funcionário'),
      TextCellValue('Receita Total'),
      TextCellValue('Dinheiro'),
      TextCellValue('Cartão TEF'),
      TextCellValue('Cartão POS'),
      TextCellValue('ATM'),
      TextCellValue('Cobranças'),
      TextCellValue('TEV/TED'),
      TextCellValue('Depósito'),
      TextCellValue('Saldo Inicial'),
      TextCellValue('Observações'),
      TextCellValue('Status'),
    ]);

    // Data
    for (var report in reports) {
      sheet.appendRow([
        TextCellValue(report['caixa_referente'] ?? ''),
        TextCellValue(report['filial_id'] ?? ''),
        TextCellValue(report['nome_funcionario_original'] ?? ''),
        DoubleCellValue((report['receita_dia'] ?? 0.0).toDouble()),
        DoubleCellValue((report['dinheiro'] ?? 0.0).toDouble()),
        DoubleCellValue((report['cartao_tef'] ?? 0.0).toDouble()),
        DoubleCellValue((report['cartao_pos'] ?? 0.0).toDouble()),
        DoubleCellValue((report['atm'] ?? 0.0).toDouble()),
        DoubleCellValue((report['cobrancas'] ?? 0.0).toDouble()),
        DoubleCellValue((report['tev_ted'] ?? 0.0).toDouble()),
        DoubleCellValue((report['deposito'] ?? 0.0).toDouble()),
        DoubleCellValue((report['saldo_inicial'] ?? 0.0).toDouble()),
        TextCellValue(report['observacoes'] ?? ''),
        TextCellValue(report['status'] ?? 'pendente'),
      ]);
    }

    // Save
    // Save
    print('DEBUG: ExcelService: Iniciando processo de salvamento...');
    try {
      final fileBytes = excel.save();
      print('DEBUG: ExcelService: Bytes gerados: ${fileBytes?.length ?? 0} bytes');
      
      if (fileBytes != null) {
        final directory = await getApplicationDocumentsDirectory();
        print('DEBUG: ExcelService: Diretório de documentos: ${directory.path}');
        
        final sanitizedFilename = 'Relatorio_${filialId}_$monthName'.replaceAll(' ', '_'); 
        final file = File('${directory.path}/$sanitizedFilename.xlsx');
        
        print('DEBUG: ExcelService: Criando arquivo em: ${file.path}');
        file.createSync(recursive: true);
        file.writeAsBytesSync(fileBytes);
          
        print('DEBUG: ExcelService: Arquivo escrito com sucesso. Tamanho: ${file.lengthSync()} bytes');
        
        // Share
        print('DEBUG: ExcelService: Chamando Share.shareXFiles...');
        final result = await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')], 
          text: 'Relatório Excel - $monthName'
        );
        print('DEBUG: ExcelService: Share.shareXFiles completado. Resultado: $result');
      } else {
        print('DEBUG: ExcelService: ERRO CRÍTICO - `excel.save()` retornou null!');
      }
    } catch (e, stack) {
      print('DEBUG: ExcelService: EXCEÇÃO CAPTURADA: $e');
      print('DEBUG: ExcelService: StackTrace: $stack');
    }
  }
}
