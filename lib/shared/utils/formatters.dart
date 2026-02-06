import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// FunÃ§Ãµes auxiliares copiadas de main.dart
// Formatter para campo de data DD/MM/AAAA
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    // Remove todos os caracteres não numéricos
    final text = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Limita a 8 dígitos (DDMMAAAA)
    if (text.length > 8) {
      return oldValue;
    }

    // Adiciona as barras conforme o usuário digita
    String formatted = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 2 || i == 4) {
        formatted += '/';
      }
      formatted += text[i];
    }

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Funções auxiliares para o chat
bool isMesmoDia(DateTime data1, DateTime data2) {
  return data1.year == data2.year && 
         data1.month == data2.month && 
         data1.day == data2.day;
}

String formatarData(DateTime data) {
  final hoje = DateTime.now();
  final ontem = hoje.subtract(const Duration(days: 1));
  
  if (isMesmoDia(data, hoje)) {
    return 'Hoje';
  } else if (isMesmoDia(data, ontem)) {
    return 'Ontem';
  } else {
    // Formato: "15 de Janeiro" (em português)
    final meses = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    return '${data.day} de ${meses[data.month - 1]}';
  }
}

String formatarHora(DateTime data) {
  return '${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
}

// Formatter para campos monetários (aceita vírgula e ponto)
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    // Remove caracteres não permitidos (mantém apenas números, vírgula e ponto)
    final text = newValue.text.replaceAll(RegExp(r'[^\d.,]'), '');

    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Permite apenas uma vírgula ou ponto por vez
    final commaCount = text.split(',').length - 1;
    final dotCount = text.split('.').length - 1;

    if (commaCount > 1 || dotCount > 1) {
      return oldValue;
    }

    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

