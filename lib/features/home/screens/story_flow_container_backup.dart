import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/stories/story_step_layout.dart';
import '../widgets/stories/big_input_field.dart';
import '../widgets/stories/photo_action_button.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';

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
  final TextEditingController _senderNameController = TextEditingController(text: 'Funcionário'); 
  final TextEditingController _initialBalanceController = TextEditingController(text: '150,00'); 
  final TextEditingController _totalRevenueController = TextEditingController();
  final TextEditingController _tefController = TextEditingController();
  final TextEditingController _posController = TextEditingController();
  final TextEditingController _moneyController = TextEditingController();
  final TextEditingController _atmController = TextEditingController();
  final TextEditingController _collectionsController = TextEditingController(); 
  final TextEditingController _transferController = TextEditingController();
  final TextEditingController _depositController = TextEditingController();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na câmera: $e')),
      );
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
    String cleaned = text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0.0;
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
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
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
                  fillColor: Colors.white,
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
               _nextPage();
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56), backgroundColor: AppColors.primary),
            child: const Text('COMEÇAR'),
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
                   color: _balanceMismatch ? AppColors.error.withOpacity(0.1) : AppColors.secondary.withOpacity(0.1),
                   borderRadius: BorderRadius.circular(16),
                   border: Border.all(
                     color: _balanceMismatch ? AppColors.error : AppColors.secondary.withOpacity(0.3),
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
                  child: const Text('PULAR'),
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
                  fillColor: Colors.grey[100],
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                 BoxShadow(
                   color: Colors.black.withOpacity(0.05),
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

  Future<void> _submitReport() async {
    setState(() => _isSending = true);
    try {
       final reportData = {
         'data': _selectedDate.toIso8601String().split('T')[0],
         'filial_id': 'B&B', 
         'user_id': 'mock_user',
         'status': 'pendente',
         'nome_funcionario': _senderNameController.text, 
         
         'saldo_inicial': _parseValue(_initialBalanceController.text),
         'saldo_divergente': _balanceMismatch,
         'receita_dia': _parseValue(_totalRevenueController.text),
         'cartao_tef': _parseValue(_tefController.text),
         'cartao_pos': _parseValue(_posController.text),
         'dinheiro': _parseValue(_moneyController.text),
         'atm': _parseValue(_atmController.text),
         'cobrancas': _parseValue(_collectionsController.text),
         'tev_ted': _parseValue(_transferController.text),
         'deposito': _parseValue(_depositController.text),
         'observacoes': _notesController.text,
         
         'created_at': DateTime.now().toIso8601String(),
       };
       
       await ServiceLocator.repository.salvarRelatorio(reportData);
       
       if (mounted) {
         Navigator.pop(context);
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Relatório enviado com sucesso!'), backgroundColor: AppColors.success),
         );
       }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16, color: isBold ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text('R\$ $value', style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: AppColors.textPrimary)),
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
