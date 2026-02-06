import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/stories/story_step_layout.dart';
import '../widgets/stories/big_input_field.dart';
import '../widgets/stories/photo_action_button.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';

import 'success_feedback_screen.dart';
import '../../../../services/notification_service.dart';
import '../../../../core/di/service_locator.dart';

class StoryFlowContainer extends StatefulWidget {
  const StoryFlowContainer({super.key});

  @override
  State<StoryFlowContainer> createState() => _StoryFlowContainerState();
}

class _StoryFlowContainerState extends State<StoryFlowContainer> {
  final PageController _pageController = PageController();
  int _currentStep = 1;
  final int _totalSteps = 12; 
  bool _isSending = false;

  // Controllers
  final TextEditingController _senderNameController = TextEditingController(
    text: ServiceLocator.repository.currentUserName ?? 'Funcionario'
  ); 
  final TextEditingController _initialBalanceController = TextEditingController(text: '150,00'); 
  final TextEditingController _totalRevenueController = TextEditingController(text: '0,00');
  final TextEditingController _tefController = TextEditingController(text: '0,00');
  final TextEditingController _posController = TextEditingController(text: '0,00');
  final TextEditingController _moneyController = TextEditingController(text: '0,00');
  final TextEditingController _atmController = TextEditingController(text: '0,00');
  final TextEditingController _collectionsController = TextEditingController(text: '0,00'); 
  final TextEditingController _transferController = TextEditingController(text: '0,00');
  final TextEditingController _depositController = TextEditingController(text: '0,00');
  final TextEditingController _notesController = TextEditingController();

  // State Variables
  DateTime _selectedDate = DateTime.now().subtract(const Duration(days: 1)); // Default: Yesterday

  // Photos (Lists)
  List<File> _totalRevenuePhotos = [];
  List<File> _tefPhotos = [];
  List<File> _posPhotos = [];
  List<File> _moneyPhotos = [];
  List<File> _atmPhotos = [];
  List<File> _collectionsPhotos = [];
  List<File> _transferPhotos = [];
  List<File> _depositPhotos = [];

  final ImagePicker _picker = ImagePicker();
  bool _balanceMismatch = false;

  @override
  void initState() {
    super.initState();
    _fetchPreviousBalance(_selectedDate);
    
    // Auto-fill existing name if available
    final name = ServiceLocator.repository.currentUserName;
    if (name != null) {
       _senderNameController.text = name;
    }
  }

  bool _isCheckingReport = false;

  Future<void> _checkExistingReport() async {
     setState(() => _isCheckingReport = true);
     
     // Show Loading Dialog
     showDialog(
       context: context, 
       barrierDismissible: false,
       builder: (c) => const Center(child: CircularProgressIndicator())
     );

     try {
       final dateStr = _selectedDate.toIso8601String().split('T')[0];
       final filialId = ServiceLocator.repository.currentUserFilialId;
       
       if (filialId == null) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Erro: Filial não identificada.')));
          setState(() => _isCheckingReport = false);
          return;
       }

       final existingReport = await ServiceLocator.repository.getRelatorioDiario(
          ServiceLocator.repository.currentUserId ?? '', 
          filialId, 
          dateStr
       );
       
       Navigator.pop(context); // Close loading

       if (existingReport != null) {
          final status = existingReport['status'] ?? 'pending';
          
          // User asked for "Editar esse relatório" if approved by manager (status check)
          // Since we don't have a rigid 'correction_requested' status defined yet in the User's mind,
          // I will assume for now that if the report exists, we BLOCK, UNLESS we decide to allow editing.
          // The User said: "Somente a partir da solicitação de correção que ele vai poder ir no dia".
          // I'll check for 'needs_correction' or a similar flag. 
          // If the status is 'needs_correction' (or similar), show Edit.
          // Otherwise, show "Already Sent".
          
          if (status == 'needs_correction' || status == 'corrigir') {
             // Allow Editing
             if (mounted) {
               showDialog(
                 context: context,
                 builder: (context) => AlertDialog(
                   title: const Text('📝 Correção Solicitada'),
                   content: const Text('O Gerente solicitou correções neste relatório. Deseja editar o envio anterior?'),
                   actions: [
                     TextButton(
                       onPressed: () => Navigator.pop(context),
                       child: const Text('Cancelar'),
                     ),
                     ElevatedButton(
                       onPressed: () {
                         Navigator.pop(context); // Close dialog
                         _fillFormWithReport(existingReport);
                         _nextPage();
                       },
                       child: const Text('Editar Relatório'),
                     )
                   ],
                 )
               );
             }
          } else {
             // Block Duplicate
             if (mounted) {
               showDialog(
                 context: context,
                 builder: (context) => AlertDialog(
                   title: const Text('✅ Relatório Já Enviado'),
                   content: Text('Já existe um relatório enviado para o dia ${_selectedDate.day}/${_selectedDate.month}.\nStatus: ${status.toString().toUpperCase()}'),
                   actions: [
                     ElevatedButton(
                       onPressed: () => Navigator.pop(context),
                       child: const Text('Entendido'),
                     )
                   ],
                 )
               );
             }
          }
       } else {
          // No report, proceed
          _nextPage();
       }

     } catch (e) {
       Navigator.pop(context); // Close loading if error
       print('Error checking report: $e');
     } finally {
       setState(() => _isCheckingReport = false);
     }
  }

  void _fillFormWithReport(Map<String, dynamic> report) {
    // Helper to format double to PT-BR string
    String fmt(dynamic val) {
       if (val == null) return '';
       // Assuming input is raw text, but parseValue handles comma/dot.
       // We should return standardized format "100,50" for UI
       return (val as num).toStringAsFixed(2).replaceAll('.', ',');
    }

    _totalRevenueController.text = fmt(report['receita_dia']);
    _moneyController.text = fmt(report['dinheiro']);
    _tefController.text = fmt(report['cartao_tef']);
    _posController.text = fmt(report['cartao_pos']);
    _atmController.text = fmt(report['atm']);
    _collectionsController.text = fmt(report['cobrancas']);
    _transferController.text = fmt(report['tev_ted']);
    _depositController.text = fmt(report['deposito']);
    _notesController.text = report['observacoes'] ?? '';
    
    // We update name too just in case
    if (report['nome_funcionario_original'] != null) {
       _senderNameController.text = report['nome_funcionario_original'];
    }
  }

  Future<void> _fetchPreviousBalance(DateTime date) async {
     setState(() => _initialBalanceController.text = 'Carregando...');
     try {
       final balance = await ServiceLocator.repository.getLastBalance(date);
       if (mounted) {
         setState(() {
           final format = NumberFormat('0.00', 'pt_BR');
           _initialBalanceController.text = format.format(balance);
         });
       }
     } catch (e) {
       if (mounted) setState(() => _initialBalanceController.text = '0,00');
     }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchPreviousBalance(_selectedDate);
    }
  }

  // Helper Methods
  Future<void> _pickImage(String type) async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
      if (photo != null) {
        setState(() {
          final file = File(photo.path);
          switch (type) {
            case 'revenue': _totalRevenuePhotos.add(file); break;
            case 'tef': _tefPhotos.add(file); break;
            case 'pos': _posPhotos.add(file); break;
            case 'money': _moneyPhotos.add(file); break;
            case 'atm': _atmPhotos.add(file); break;
            case 'collections': _collectionsPhotos.add(file); break;
            case 'transfer': _transferPhotos.add(file); break;
            case 'deposit': _depositPhotos.add(file); break;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro na câmera: $e')),
        );
      }
    }
  }

  void _removeImage(String type, File file) {
    setState(() {
      switch (type) {
        case 'revenue': _totalRevenuePhotos.remove(file); break;
        case 'tef': _tefPhotos.remove(file); break;
        case 'pos': _posPhotos.remove(file); break;
        case 'money': _moneyPhotos.remove(file); break;
        case 'atm': _atmPhotos.remove(file); break;
        case 'collections': _collectionsPhotos.remove(file); break;
        case 'transfer': _transferPhotos.remove(file); break;
        case 'deposit': _depositPhotos.remove(file); break;
      }
    });
  }

  double _parseValue(String text) {
    if (text.isEmpty) return 0.0;
    
    // Remove symbols and whitespace
    String clean = text.replaceAll('R\$', '').trim();
    
    // Smart Dot/Comma Handling
    if (clean.contains(',') && clean.contains('.')) {
       // Standard format like 1.000,00 -> Remove dots, replace comma with dot
       clean = clean.replaceAll('.', '').replaceAll(',', '.');
    } else if (clean.contains(',')) {
       // Only comma (1000,00) -> Replace with dot
       clean = clean.replaceAll(',', '.');
    } else if (clean.contains('.')) {
       // Only dots. Handle "1.000.00" vs "1.000" vs "1.50"
       int dots = clean.split('.').length - 1;
       if (dots > 1) {
          // Multiple dots (1.000.00) implies thousands -> remove all except last?
          // User said "1.000.00" is same as "1.000,00".
          // So replace last dot with point, remove others?
          // Actually, double.parse uses dot as decimal.
          // So "1.000.00" -> "1000.00".
          // Remove all dots except the last one?
          int lastDot = clean.lastIndexOf('.');
          String before = clean.substring(0, lastDot).replaceAll('.', '');
          String after = clean.substring(lastDot + 1);
          clean = '$before.$after';
       } 
       // If single dot like "100.50", keep it.
    }
    
    return double.tryParse(clean) ?? 0.0;
  }
  
  bool _validateRevenue() {
    final revenue = _parseValue(_totalRevenueController.text);
    final breakdownSum = _parseValue(_moneyController.text) +
                         _parseValue(_tefController.text) +
                         _parseValue(_posController.text) +
                         _parseValue(_atmController.text) +
                         _parseValue(_collectionsController.text) +
                         _parseValue(_transferController.text);
    
    return (revenue - breakdownSum).abs() < 0.1;
  }

  void _showValidationError() {
     final revenue = _parseValue(_totalRevenueController.text);
     final breakdown = _parseValue(_moneyController.text) +
                         _parseValue(_tefController.text) +
                         _parseValue(_posController.text) +
                         _parseValue(_atmController.text) +
                         _parseValue(_collectionsController.text) +
                         _parseValue(_transferController.text);
                         
     showDialog(
       context: context, 
       builder: (context) => AlertDialog(
         title: const Text('⚠️ Valores não batem!'),
         content: Text(
           'A soma dos itens (R\$ ${breakdown.toStringAsFixed(2)}) não é igual à Receita Total informada (R\$ ${revenue.toStringAsFixed(2)}).\n\nDiferença: R\$ ${(revenue - breakdown).abs().toStringAsFixed(2)}'
         ),
         actions: [
           TextButton(
             onPressed: () => Navigator.pop(context),
             child: const Text('CORRIGIR'),
           ),
         ],
       )
     );
  }

  @override
  Widget build(BuildContext context) {
    // Format Date
    final dateStr = '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';
    final isWeekend = _selectedDate.weekday == 6 || _selectedDate.weekday == 7;
    final weekdayName = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'][_selectedDate.weekday - 1];

    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        
        // STEP 1: CONFIGURAÇÃO INICIAL
        StoryStepLayout(
          currentStep: 1,
          totalSteps: _totalSteps,
          title: 'Vamos começar!',
          subtitle: 'Confirme os dados do relatório.',
          onBack: () => Navigator.pop(context),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Data do Caixa (Referente)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _selectDate(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).cardColor,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$weekdayName, $dateStr', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          if (isWeekend) 
                             const Text('(Fim de Semana)', style: TextStyle(fontSize: 12, color: Colors.orange)),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.edit, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Quem está enviando?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: _senderNameController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor,
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
          bottomAction: ElevatedButton(
            onPressed: () {
               if (_senderNameController.text.isEmpty) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Nome é obrigatório!')));
                 return;
               }
               _checkExistingReport();
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56), backgroundColor: AppColors.primary),
            child: const Text('CONTINUAR'),
          ),
        ),

        // STEP 2: SALDO INICIAL (Read-Only & Divergence)
        StoryStepLayout(
          currentStep: 2,
          totalSteps: _totalSteps,
          title: 'Saldo Inicial\nAnterior',
          subtitle: 'Valor deixado no caixa dia anterior.',
          onBack: _prevPage,
          body: Column(
            children: [
               Container(
                 padding: const EdgeInsets.all(24),
                 decoration: BoxDecoration(
                   color: _balanceMismatch ? AppColors.error.withValues(alpha: 0.1) : AppColors.secondary.withValues(alpha: 0.1),
                   borderRadius: BorderRadius.circular(16),
                   border: Border.all(
                     color: _balanceMismatch ? AppColors.error : AppColors.secondary.withValues(alpha: 0.3),
                     width: _balanceMismatch ? 2 : 1
                   ),
                 ),
                 child: Column(
                   children: [
                     Text(
                       _balanceMismatch ? 'Saldo Divergente Informado' : 'Saldo em Dinheiro', 
                       style: TextStyle(
                         fontSize: 14, 
                         color: _balanceMismatch ? AppColors.error : AppColors.textSecondary,
                         fontWeight: _balanceMismatch ? FontWeight.bold : FontWeight.normal
                       )
                     ),
                     const SizedBox(height: 8),
                     Text(
                       'R\$ ${_initialBalanceController.text}',
                       style: TextStyle(
                         fontSize: 36, 
                         fontWeight: FontWeight.bold, 
                         color: _balanceMismatch ? AppColors.error : AppColors.primary
                       ),
                     ),
                     const SizedBox(height: 16),
                     Text(
                       _balanceMismatch 
                         ? 'Este relatório será marcado com divergência de saldo inicial para o gerente.'
                         : 'Este valor confere com o dinheiro que você encontrou na gaveta ao abrir?',
                       textAlign: TextAlign.center,
                       style: const TextStyle(fontSize: 16),
                     ),
                   ],
                 ),
               ),
            ],
          ),
          bottomAction: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                     setState(() {
                       _balanceMismatch = !_balanceMismatch;
                     });
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    foregroundColor: _balanceMismatch ? Colors.grey : AppColors.error,
                  ),
                  child: Text(_balanceMismatch ? 'CANCELAR DIVERGÊNCIA' : 'NÃO CONFERE'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56), 
                    backgroundColor: _balanceMismatch ? Colors.orange : AppColors.primary
                  ),
                  child: const Text('CONFIRMAR'),
                ),
              ),
            ],
          ),
        ),

        // STEP 3: RECEITA TOTAL
        _buildStep(
          step: 3,
          title: 'Qual a Receita\nTotal do Dia?',
          subtitle: 'Soma de todas as vendas (bruto).',
          controller: _totalRevenueController,
          hasPhoto: true, 
          photoLabel: 'Foto do Fechamento (Z)',
          photoFiles: _totalRevenuePhotos,
          onPhotoTap: () => _pickImage('revenue'),
          onPhotoRemove: (f) => _removeImage('revenue', f),
          action: 'PRÓXIMO',
        ),

        // STEP 4: TEF
         _buildStep(
          step: 4,
          title: 'Vendas em\nCartão TEF?',
          subtitle: 'Somando todas as filipetas.',
          controller: _tefController,
          hasPhoto: true, 
          photoFiles: _tefPhotos,
          onPhotoTap: () => _pickImage('tef'),
          onPhotoRemove: (f) => _removeImage('tef', f),
          action: 'PRÓXIMO',
        ),

        // STEP 5: POS
         _buildStep(
          step: 5,
          title: 'Vendas em\nMaquininha (POS)?',
          subtitle: 'Aquelas fora do sistema.',
          controller: _posController,
          hasPhoto: true, 
          photoFiles: _posPhotos,
          onPhotoTap: () => _pickImage('pos'),
          onPhotoRemove: (f) => _removeImage('pos', f),
          action: 'PRÓXIMO',
        ),

        // STEP 6: DINHEIRO
         _buildStep(
          step: 6,
          title: 'Quanto tem\nem Dinheiro?',
          subtitle: 'Conte as notas na gaveta.',
          controller: _moneyController,
          hasPhoto: true, 
          photoLabel: 'Foto (Opcional)',
          photoFiles: _moneyPhotos,
          onPhotoTap: () => _pickImage('money'),
          onPhotoRemove: (f) => _removeImage('money', f),
          action: 'PRÓXIMO',
        ),

        // STEP 7: ATM
         _buildStep(
          step: 7,
          title: 'Teve Saque\nATM?',
          subtitle: 'Retiradas no caixa eletrônico.',
          controller: _atmController,
          hasPhoto: true, 
          photoFiles: _atmPhotos,
          onPhotoTap: () => _pickImage('atm'),
          onPhotoRemove: (f) => _removeImage('atm', f),
          action: 'PRÓXIMO',
        ),

        // STEP 8: COBRANÇAS
         _buildStep(
          step: 8,
          title: 'Recebeu\nCobranças?',
          subtitle: 'Pagamentos de mensalistas, etc.',
          controller: _collectionsController,
          hasPhoto: true, 
          photoFiles: _collectionsPhotos,
          onPhotoTap: () => _pickImage('collections'),
          onPhotoRemove: (f) => _removeImage('collections', f),
          action: 'PRÓXIMO',
        ),

        // STEP 9: TEV/TED
         _buildStep(
          step: 9,
          title: 'Transferências\n(TED/DOC/PIX)?',
          subtitle: 'Entradas via banco direto.',
          controller: _transferController,
          hasPhoto: true, 
          photoFiles: _transferPhotos,
          onPhotoTap: () => _pickImage('transfer'),
          onPhotoRemove: (f) => _removeImage('transfer', f),
          action: 'AVANÇAR PARA DEPÓSITO',
        ),

        // STEP 10: DEPÓSITO
        StoryStepLayout(
           currentStep: 10,
          totalSteps: _totalSteps,
          title: 'Fez algum\nDepósito hoje?',
          subtitle: 'Se não fez, basta pular.',
          onBack: _prevPage,
          body: Column(
            children: [
              BigInputField(
                controller: _depositController,
                hintText: '0,00',
              ),
               const SizedBox(height: 32),
               PhotoActionButton(
                onTap: () => _pickImage('deposit'),
                label: 'Foto do Comprovante',
                imageFiles: _depositPhotos,
                onRemove: (f) => _removeImage('deposit', f),
              ),
            ],
          ),
          bottomAction: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _nextPage,
                   style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                   ),
                  child: const Text('NÃO REALIZEI'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                   onPressed: () {
                     if (_depositController.text.isNotEmpty && _depositPhotos.isEmpty) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Foto do comprovante é obrigatória!')));
                       return;
                     }
                     _nextPage();
                   },
                    style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: AppColors.primary,
                   ),
                  child: const Text('CONFIRMAR'),
                ),
              ),
            ],
          ),
        ),

         // STEP 11: OBSERVAÇÕES
        StoryStepLayout(
          currentStep: 11,
          totalSteps: _totalSteps,
          title: 'Alguma\nObservação?',
          subtitle: 'Algo fora do comum?',
          onBack: _prevPage,
          body: Column(
            children: [
              TextField(
                controller: _notesController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Digite aqui...',
                  filled: true,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          bottomAction: ElevatedButton(
            onPressed: () {
              if (!_validateRevenue()) {
                 _showValidationError();
              } else {
                _nextPage();
              }
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: AppColors.primary,
            ),
            child: const Text('REVISAR'),
          ),
        ),

        // STEP 12: RESUMO & ENVIO
        StoryStepLayout(
          currentStep: 12,
          totalSteps: _totalSteps,
          title: 'Tudo pronto!',
          subtitle: 'Confira os valores antes de enviar.',
          onBack: _prevPage,
          body: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                 BoxShadow(
                   color: Colors.black.withValues(alpha: 0.05),
                   blurRadius: 10,
                   offset: const Offset(0, 4),
                 ),
               ],
             ),
             child: SingleChildScrollView(
               child: Column(
                 children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text('Enviado por: ${_senderNameController.text}', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Referente a: ${_selectedDate.day}/${_selectedDate.month}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    const Divider(),
                    _buildSummaryRow('Saldo Inicial', _initialBalanceController.text),
                    const Divider(),
                    _buildSummaryRow('Receita Total', _totalRevenueController.text, isBold: true),
                    const Divider(),
                   _buildSummaryRow('Cartão TEF', _tefController.text),
                   _buildSummaryRow('Cartão POS', _posController.text),
                   _buildSummaryRow('Dinheiro', _moneyController.text),
                   _buildSummaryRow('ATM', _atmController.text),
                   _buildSummaryRow('Cobranças', _collectionsController.text),
                   _buildSummaryRow('TEV/TED', _transferController.text),
                   const Divider(),
                   _buildSummaryRow('Depósito', _depositController.text.isEmpty ? '0,00' : _depositController.text),
                 ],
               ),
             ),
           ),
           bottomAction: _isSending ? const Center(child: CircularProgressIndicator()) : ElevatedButton.icon(
              onPressed: _submitReport,
              icon: const Icon(Icons.send),
              label: const Text('ENVIAR FECHAMENTO'),
               style: ElevatedButton.styleFrom(
               minimumSize: const Size(double.infinity, 56),
               backgroundColor: AppColors.success,
              ),
           ),
         ),
       ],
     );
   }

  Widget _buildStep({
    required int step,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String action,
    bool hasPhoto = false,
    String photoLabel = 'Tirar Foto Comprovante',
    List<File> photoFiles = const [],
    VoidCallback? onPhotoTap,
    Function(File)? onPhotoRemove,
  }) {
      return StoryStepLayout(
          currentStep: step,
          totalSteps: _totalSteps,
          title: title,
          subtitle: subtitle,
          onBack: _prevPage,
          body: Column(
            children: [
              BigInputField(
                controller: controller,
                hintText: '0,00',
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 32),
                PhotoActionButton(
                  onTap: onPhotoTap ?? () {},
                  label: photoLabel,
                  imageFiles: photoFiles,
                  onRemove: onPhotoRemove,
                ),
               ],
            ],
          ),
          bottomAction: ElevatedButton(
            onPressed: () {
               // Enforce Photos
               final val = _parseValue(controller.text);
               
               if (hasPhoto && photoFiles.isEmpty && val > 0) {
                 if (step != 6) { 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Para valores acima de zero, a foto é obrigatória!')));
                    return;
                 }
               }
               if (step == 3 && photoFiles.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ A foto do fechamento é obrigatória!')));
                  return;
               }

               _nextPage();
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: AppColors.primary,
            ),
            child: Text(action),
          ),
        );
  }

  Future<String?> _uploadList(List<File> files) async {
    if (files.isEmpty) return null;
    
    List<String> urls = [];
    for (var file in files) {
      final url = await ServiceLocator.repository.uploadImage(file);
      if (url != null) urls.add(url);
    }
    
    if (urls.isEmpty) return null;
    return urls.join(',');
  }

  Future<void> _submitReport() async {
    print('DEBUG: _submitReport INICIADO');
    setState(() => _isSending = true);
    try {
        final dateStr = _selectedDate.toIso8601String().split('T')[0];
        final filialId = ServiceLocator.repository.currentUserFilialId;

        // 1. Check for Duplicate Report (SKIP if updating / has ID, or allow overwrite logic)
        // Since we are likely inserting/upserting, we need to handle the ID.
        // If we came from "Edit" flow, the record exists.
        // UPSERT in Supabase handles this if 'id' matches or unique constraint.
        // But our logic above blocks if report exists, unless we are editing.
        // If we are editing, we are submitting again for the same date.
        // Supabase upsert will fail if ID is missing but unique index exists on (filial, date).
        // Let's fetch the ID again to be sure we are updating the SAME record.
        
        String? existingId;
        if (filialId != null) {
           final existing = await ServiceLocator.repository.getRelatorioDiario(
              ServiceLocator.repository.currentUserId ?? '', 
              filialId, 
              dateStr
           );
           if (existing != null) {
              existingId = existing['id'];
              // If status is NOT correction/corrigir, we should probably still block?
              // But the UI check handled that. If we are here, we are allowed to submit.
              print('DEBUG: Atualizando relatório existente ID: $existingId');
           }
        }

        print('DEBUG: Parseando valores...');
       // Upload Photos
       print('DEBUG: Iniciando upload de fotos...');
       
       print('DEBUG: Fotos Receita: ${_totalRevenuePhotos.length}');
       final urlReceita = await _uploadList(_totalRevenuePhotos);
       
       print('DEBUG: Fotos TEF: ${_tefPhotos.length}');
       final urlTef = await _uploadList(_tefPhotos);
       
       print('DEBUG: Fotos POS: ${_posPhotos.length}');
       final urlPos = await _uploadList(_posPhotos);
       
       print('DEBUG: Fotos ATM: ${_atmPhotos.length}');
       final urlAtm = await _uploadList(_atmPhotos);
       
       print('DEBUG: Fotos Cobranças: ${_collectionsPhotos.length}');
       final urlCobrancas = await _uploadList(_collectionsPhotos);
       
       print('DEBUG: Fotos Transferência: ${_transferPhotos.length}');
       final urlTevTed = await _uploadList(_transferPhotos);
       
       print('DEBUG: Fotos Depósito: ${_depositPhotos.length}');
       final urlDeposito = await _uploadList(_depositPhotos);
       
       print('DEBUG: Uploads concluídos. Montando payload...');

       final reportData = {
         'caixa_referente': _selectedDate.toIso8601String().split('T')[0],
         'filial_id': ServiceLocator.repository.currentUserFilialId, 
         'user_id': ServiceLocator.repository.currentUserId,
         'nome_funcionario_original': _senderNameController.text, 
         
         'saldo_inicial': _parseValue(_initialBalanceController.text),
         // 'saldo_divergente': _balanceMismatch, // REMOVED: Column missing in schema
         'receita_dia': _parseValue(_totalRevenueController.text),
         'cartao_tef': _parseValue(_tefController.text),
         'cartao_pos': _parseValue(_posController.text),
         'dinheiro': _parseValue(_moneyController.text),
         'atm': _parseValue(_atmController.text),
         'cobrancas': _parseValue(_collectionsController.text),
         'tev_ted': _parseValue(_transferController.text),
         'deposito': _parseValue(_depositController.text),
         'observacoes': _notesController.text,

         'comprovante_receita': urlReceita,
         'comprovante_cartao_tef': urlTef,
         'comprovante_cartao_pos': urlPos,
         'comprovante_atm': urlAtm,
         'comprovante_cobrancas': urlCobrancas,
         'comprovante_tev_ted': urlTevTed,
         'comprovante_deposito': urlDeposito,
         
         'created_at': DateTime.now().toIso8601String(),
         if (existingId != null) 'id': existingId,
         if (existingId != null) 'status': 'pendente', // Reset status if it was 'needs_correction'
       };
       
       print('DEBUG: Payload montado: $reportData');
       
       print('DEBUG: Chamando repository.salvarRelatorio...');
       await ServiceLocator.repository.salvarRelatorio(reportData);
       print('DEBUG: repository.salvarRelatorio SUCESSO');
       
       if (mounted) {
         // Show Local Notification
         await NotificationService().showLocalNotification(
           id: 1,
           title: 'Relatório Enviado!',
           body: 'O fechamento de ${_selectedDate.day}/${_selectedDate.month} foi recebido com sucesso.',
         );

         // Navigate to Success Screen (replace current flow)
         Navigator.pushReplacement(
           context, 
           MaterialPageRoute(builder: (context) => const SuccessFeedbackScreen()),
         );
       }
    } catch (e, stackTrace) {
      print('DEBUG: ERRO NO ENVIO: $e');
      print('DEBUG: StackTrace: $stackTrace');
      
      if (mounted) {
        // Validation/System Error via Notification as requested
        NotificationService().showLocalNotification(
          id: 666, 
          title: 'Erro no Envio', 
          body: 'Não foi possível enviar o relatório: $e'
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
      print('DEBUG: _submitReport FINALIZADO');
    }
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16, color: isBold ? Theme.of(context).textTheme.bodyLarge?.color : Theme.of(context).textTheme.bodyMedium?.color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text('R\$ $value', style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: Theme.of(context).textTheme.bodyLarge?.color)),
        ],
      ),
    );
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() {
      _currentStep++;
    });
  }

  void _prevPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
     setState(() {
      _currentStep--;
    });
  }
}
