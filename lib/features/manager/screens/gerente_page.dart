import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as sfxlsio;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/screens/login_page.dart';
import '../../../shared/utils/formatters.dart';
import '../../home/screens/home_page.dart';
import '../../../core/di/service_locator.dart'; // DI

class GerentePage extends StatefulWidget {
  const GerentePage({super.key});

  @override
  State<GerentePage> createState() => _GerentePageState();
}
class _GerentePageState extends State<GerentePage> with SingleTickerProviderStateMixin {
  final List<String> filiais = [
    'B&B', 'Foccus', 'Buena', 'Connect', 'New World',
    'New Business', 'JK', 'BT',
  ];

  Map<String, List<Map<String, dynamic>>> _relatoriosPorFilial = {};
  String _message = '';
  DateTime? _dataInicial;
  DateTime? _dataFinal;
  bool _isDarkMode = false;
  String _selectedFilial = '';

  late TabController _tabController;
  List<Map<String, dynamic>> _solicitacoes = [];
  int _selectedMenuIndex = 0;
  bool _isDrawerOpen = false;
  String _selectedSubMenu = '';
  bool _showSubMenu = false;
  String _searchQuery = '';

  // Variáveis para calculadora de cartões
  double totalCartoes = 0.0;
  double total = 0.0;
  double diferenca = 0.0;
  bool cartoesExportado = false;

  // Variáveis de estado persistentes para calculadora de cartões
  TextEditingController? _cartoesValorBrutoRedeController;
  TextEditingController? _cartoesPixRedeController;
  TextEditingController? _cartoesValorBrutoController;
  TextEditingController? _cartoesPixController;
  double? _cartoesValorBrutoRede;
  double? _cartoesPixRede;
  double? _cartoesValorBruto;
  double? _cartoesPix;
  double? _cartoesTotal;

  // Variáveis de estado persistentes para calculadoras de taxas
  TextEditingController? _redeValorBrutoController;
  TextEditingController? _redeValorLiquidoController;
  TextEditingController? _redeTaxaController;
  double? _redeValorBruto;
  double? _redeValorLiquido;
  double? _redeTaxa;
  double? _redeTotal;

  TextEditingController? _sipagValorBrutoController;
  TextEditingController? _sipagValorLiquidoController;
  TextEditingController? _sipagTaxaController;
  double? _sipagValorBruto;
  double? _sipagValorLiquido;
  double? _sipagTaxa;
  double? _sipagTotal;

  // Variáveis para despesas (novo campo)
  TextEditingController? _despesasController;
  double? _despesas;
  
  // Variáveis separadas para cada calculadora
  double? _taxaComDespesasRede;
  double? _taxaComDespesasSipag;

  // Sistema de travamento especial para filiais
  int? _tempoLimiteEnvio; // Vem da tabela users
  bool _isSistemaTravado = false;
  List<DateTime> _diasPendentes = [];

  // Sistema de Chat
  List<Map<String, dynamic>> _mensagens = [];
  TextEditingController _mensagemController = TextEditingController();
  bool _isEnviandoMensagem = false;
  Timer? _chatTimer; // Timer para atualização automática do chat

  // Helpers
  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  
  bool get isEndOfMonth {
    final now = DateTime.now();
    return now.day == DateTime(now.year, now.month + 1, 0).day;
  }



  // Funções do Chat para o Gerente
  Stream<List<Map<String, dynamic>>> _getMensagensGerenteStream() {
    // Gerente vê apenas mensagens gerais na tela inicial
    return Supabase.instance.client
        .from('mensagens_chat')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .map((event) {
          return event
              .map((e) => Map<String, dynamic>.from(e))
              .where((mensagem) => mensagem['tipo'] == 'gerente')
              .toList();
        });
  }

  Future<void> _carregarMensagensGerente() async {
    try {
      final response = await Supabase.instance.client
          .from('mensagens_chat')
          .select('*, users(nome, filial_id)')
          .order('created_at', ascending: true);

      setState(() {
        _mensagens = List<Map<String, dynamic>>.from(response);
      });
    } catch (error) {
      print('Erro ao carregar mensagens: $error');
    }
  }

  // Função para enviar mensagem geral para todas as filiais
  Future<void> _enviarMensagemGeral() async {
    if (_mensagemController.text.trim().isEmpty) return;

    try {
      setState(() {
        _isEnviandoMensagem = true;
      });

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      print('DEBUG _enviarMensagemGeral: userId=$userId, mensagem=${_mensagemController.text.trim()}');
      
      // Enviar mensagem geral (para todas as filiais)
      await Supabase.instance.client.from('mensagens_chat').insert({
        'user_id': userId,
        'filial_id': null, // null = mensagem geral para todas as filiais
        'mensagem': _mensagemController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
        'tipo': 'gerente', // Usar tipo válido (gerente envia para todas as filiais)
      });

      print('DEBUG _enviarMensagemGeral: Mensagem geral enviada com sucesso!');

      _mensagemController.clear();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar mensagem geral: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isEnviandoMensagem = false;
      });
    }
  }

  Future<void> _enviarMensagemGerente() async {
    if (_mensagemController.text.trim().isEmpty) return;

    try {
      setState(() {
        _isEnviandoMensagem = true;
      });

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      print('DEBUG _enviarMensagemGerente: userId=$userId, mensagem=${_mensagemController.text.trim()}');

      await Supabase.instance.client.from('mensagens_chat').insert({
        'user_id': userId,
        'filial_id': null, // Gerente não tem filial específica (mensagem geral)
        'mensagem': _mensagemController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
        'tipo': 'gerente',
      });

      _mensagemController.clear();
      await _carregarMensagensGerente();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar mensagem: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isEnviandoMensagem = false;
      });
    }
  }

  Future<void> _enviarMensagemIndividualFilial(String filialNome) async {
    if (_mensagemController.text.trim().isEmpty) return;

    try {
      setState(() {
        _isEnviandoMensagem = true;
      });

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      print('DEBUG _enviarMensagemIndividualFilial: userId=$userId, filialNome=$filialNome, mensagem=${_mensagemController.text.trim()}');

      // Corrigido: filialNome é o nome da filial (ex: "B&B", "Foccus", etc.)
      await Supabase.instance.client.from('mensagens_chat').insert({
        'user_id': userId,
        'filial_id': filialNome, // Este é o nome da filial (ex: "B&B")
        'mensagem': _mensagemController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
        'tipo': 'funcionario', // Tipo funcionário para mensagens individuais
      });

      _mensagemController.clear();
    } catch (error) {
      print('Erro ao enviar mensagem individual: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar mensagem: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isEnviandoMensagem = false;
      });
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

  // Função para buscar nome do usuário de forma assíncrona
  Future<String> _buscarNomeUsuario(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('nome')
          .eq('id', userId)
          .single();
      return response['nome'] ?? 'Usuário';
    } catch (e) {
      return 'Usuário';
    }
  }

  // Função otimizada para marcar mensagens como visualizadas
  Future<void> _marcarComoVisualizada(String mensagemId, String filialId) async {
    try {
      // Verificar se já foi marcada como visualizada ANTES de tentar inserir
      final response = await Supabase.instance.client
          .from('mensagens_visualizacoes')
          .select('id')
          .eq('mensagem_id', mensagemId)
          .eq('filial_id', filialId)
          .maybeSingle();
      
      // Se já existe, não precisa inserir novamente
      if (response != null) {
        return; // Já foi marcada, sair sem fazer nada
      }
      
      // Só inserir se não existir
      await Supabase.instance.client
          .from('mensagens_visualizacoes')
          .insert({
            'mensagem_id': mensagemId,
            'filial_id': filialId,
            'visualizado_em': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      // Ignorar erro de duplicação silenciosamente
      if (e.toString().contains('duplicate key')) {
        return; // Já existe, tudo bem
      }
      print('Erro ao marcar como visualizada: $e');
    }
  }

  // Função otimizada para marcar múltiplas mensagens
  Future<void> _marcarMensagensComoVisualizadas(List<String> mensagemIds, String filialId) async {
    try {
      // Buscar visualizações existentes de uma vez
      final existingViews = await Supabase.instance.client
          .from('mensagens_visualizacoes')
          .select('mensagem_id')
          .eq('filial_id', filialId);
      
      // Filtrar apenas as mensagens que queremos verificar
      final existingIds = existingViews
          .where((v) => mensagemIds.contains(v['mensagem_id']))
          .map((v) => v['mensagem_id'] as String)
          .toSet();
      
      // Filtrar apenas mensagens que ainda não foram visualizadas
      final newIds = mensagemIds.where((id) => !existingIds.contains(id)).toList();
      
      // Inserir apenas as novas visualizações
      if (newIds.isNotEmpty) {
        final visualizacoes = newIds.map((id) => {
          'mensagem_id': id,
          'filial_id': filialId,
          'visualizado_em': DateTime.now().toIso8601String(),
        }).toList();
        
        await Supabase.instance.client
            .from('mensagens_visualizacoes')
            .insert(visualizacoes);
      }
    } catch (e) {
      print('Erro ao marcar mensagens como visualizadas: $e');
    }
  }

  // Função para verificar status de visualização (para mensagens gerais)
  Future<Map<String, dynamic>> _verificarStatusVisualizacao(String mensagemId) async {
    try {
      // Buscar todas as filiais únicas
      final filiais = await Supabase.instance.client
          .from('users')
          .select('filial_id')
          .neq('filial_id', '')
          .not('filial_id', 'is', null);
      
      final filiaisUnicas = filiais.map((f) => f['filial_id']).toSet().toList();
      
      // Buscar visualizações desta mensagem
      final visualizacoes = await Supabase.instance.client
          .from('mensagens_visualizacoes')
          .select('filial_id')
          .eq('mensagem_id', mensagemId);
      
      final filiaisVisualizaram = visualizacoes.map((v) => v['filial_id']).toSet();
      
      return {
        'todasVisualizaram': filiaisUnicas.every((f) => filiaisVisualizaram.contains(f)),
        'filiaisVisualizaram': filiaisVisualizaram.length,
        'totalFiliais': filiaisUnicas.length,
      };
    } catch (e) {
      return {
        'todasVisualizaram': false,
        'filiaisVisualizaram': 0,
        'totalFiliais': 0,
      };
    }
  }

  // Stream para mensagens individuais de uma filial específica (para o gerente)
  Stream<List<Map<String, dynamic>>> _getMensagensFilialStream(String filialNome) {
    return Supabase.instance.client
        .from('mensagens_chat')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .map((event) {
          // Filtrar apenas mensagens da filial específica com tipo funcionario
          return event
              .map((e) => Map<String, dynamic>.from(e))
              .where((mensagem) {
                final tipo = mensagem['tipo'];
                final filialIdMensagem = mensagem['filial_id'];
                return tipo == 'funcionario' && filialIdMensagem == filialNome;
              })
              .toList();
        });
  }



  void _abrirChatGerente() {
    showDialog(
      context: context,
      builder: (context) => _buildChatDialogGerente(),
    ).then((_) {
      // Limpar o timer quando o chat for fechado
      _chatTimer?.cancel();
      _chatTimer = null;
    });
  }

  void _abrirChatIndividualFilial(String filialNome) async {
    try {
      // Mostrar loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Buscar IDs das mensagens da filial específica
      final mensagens = await Supabase.instance.client
          .from('mensagens_chat')
          .select('id')
          .eq('tipo', 'funcionario')
          .eq('filial_id', filialNome)
          .order('created_at', ascending: false)
          .limit(50);
      
      // Marcar como visualizadas em lote
      if (mensagens.isNotEmpty) {
        final mensagemIds = mensagens.map((m) => m['id'] as String).toList();
        await _marcarMensagensComoVisualizadas(mensagemIds, filialNome);
      }
      
      // Fechar loading
      Navigator.of(context).pop();
      
      // Abrir chat após marcar como visualizadas
      showDialog(
        context: context,
        builder: (context) => _buildChatDialogIndividualFilial(filialNome),
      ).then((_) {
        // Limpar o timer quando o chat for fechado
        _chatTimer?.cancel();
        _chatTimer = null;
      });
    } catch (e) {
      // Fechar loading em caso de erro
      Navigator.of(context).pop();
      print('Erro ao marcar mensagens como visualizadas: $e');
      
      // Abrir chat mesmo com erro
      showDialog(
        context: context,
        builder: (context) => _buildChatDialogIndividualFilial(filialNome),
      ).then((_) {
        // Limpar o timer quando o chat for fechado
        _chatTimer?.cancel();
        _chatTimer = null;
      });
    }
  }

  Widget _buildChatDialogIndividualFilial(String filialNome) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header do Chat Individual - Cor básica com toque de vermelho
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[800], // Cor base cinza escuro
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.red[400]!, // Toque de vermelho na borda inferior
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.message, color: Colors.red[400]), // ÃƒÂcone vermelho
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chat Individual - $filialNome',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Lista de Mensagens
            Expanded(
              child: StatefulBuilder(
                builder: (context, setStateChat) {
                  // Iniciar timer de atualização automática quando o chat abrir
                  if (_chatTimer == null) {
                    _chatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                      setStateChat(() {
                        // Forçar reconstrução da UI a cada segundo
                      });
                    });
                  }

                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _getMensagensFilialStream(filialNome),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Erro: ${snapshot.error}'),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final mensagens = snapshot.data!;

                      if (mensagens.isEmpty) {
                        return const Center(
                          child: Text(
                            'Nenhuma mensagem ainda.\nInicie uma conversa!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: mensagens.length,
                        itemBuilder: (context, index) {
                          final mensagem = mensagens[index];
                          final isMinhaMensagem = mensagem['user_id'] == Supabase.instance.client.auth.currentUser?.id;
                          final userId = mensagem['user_id'];
                          
                          // Separador de data
                          final dataAtual = DateTime.parse(mensagem['created_at']);
                          final mensagemAnterior = index > 0 ? mensagens[index - 1] : null;
                          final dataAnterior = mensagemAnterior != null
                              ? DateTime.parse(mensagemAnterior['created_at'])
                              : null;

                          final precisaSeparador = dataAnterior == null ||
                              !isMesmoDia(dataAtual, dataAnterior);

                          return Column(
                            children: [
                              // Separador de data
                              if (precisaSeparador) ...[
                                Container(
                                  margin: const EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        formatarData(dataAtual),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              
                              // Mensagem
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  mainAxisAlignment: isMinhaMensagem
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  children: [
                                    // Mensagens de outros usuários
                                    if (!isMinhaMensagem) ...[
                                      Container(
                                        constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            FutureBuilder<String>(
                                              future: _buscarNomeUsuario(userId),
                                              builder: (context, snapshot) {
                                                return Text(
                                                  snapshot.data ?? 'Usuário...',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.grey[700],
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              mensagem['mensagem'] ?? '',
                                              style: const TextStyle(
                                                color: Colors.black87,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  formatarHora(dataAtual),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Para mensagens individuais, verificar se a filial visualizou
                                                FutureBuilder<Map<String, dynamic>>(
                                                  future: _verificarStatusVisualizacao(mensagem['id']),
                                                  builder: (context, snapshot) {
                                                    final todasVisualizaram = snapshot.data?['todasVisualizaram'] ?? false;
                                                    
                                                    return Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.done_all,
                                                          size: 14,
                                                          color: todasVisualizaram ? Colors.blue[600] : Colors.grey[400],
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          todasVisualizaram ? 'Vista' : 'Enviado',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: todasVisualizaram ? Colors.blue[600] : Colors.grey[400],
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else ...[
                                      Container(
                                        constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.red[400],
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Você',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white70,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              mensagem['mensagem'] ?? '',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  formatarHora(dataAtual),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons.done_all,
                                                  size: 14,
                                                  color: Colors.white70,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Vista',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          );
                        }, // FIM DO ITEMBUILDER
                      ); // FIM DO LISTVIEW.BUILDER
                    }, // FIM DO BUILDER DO STREAMBUILDER
                  ); // FIM DO STREAMBUILDER
                }, // FIM DO BUILDER DO STATEFULBUILDER
              ), // FIM DO STATEFULBUILDER
            ), // FIM DO EXPANDED

            // Campo de entrada de mensagem
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  top: BorderSide(
                    color: Colors.grey[300]!,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mensagemController,
                      decoration: InputDecoration(
                        hintText: 'Digite sua mensagem...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red[400], // Botão vermelho
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: IconButton(
                      onPressed: _isEnviandoMensagem ? null : () => _enviarMensagemIndividualFilial(filialNome),
                      icon: _isEnviandoMensagem
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Chat do Gerente
  Widget _buildChatDialogGerente() {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header do Chat - Cor básica com toque de vermelho
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[800], // Cor base cinza escuro
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.red[400]!, // Toque de vermelho na borda inferior
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.chat, color: Colors.red[400]), // ÃƒÂcone vermelho
                  const SizedBox(width: 8),
                  const Text(
                    'Chat com Filiais',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            
            // Header do Chat Geral
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red[50], // Fundo vermelho claro
              child: Row(
                children: [
                  Icon(Icons.broadcast_on_personal, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Comunicados para Todas as Filiais',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[700],
                    ),
                  ),
                ],
              ),
            ),
            
            // Lista de mensagens gerais
            Expanded(
              child: _buildChatGeral(),
            ),
            
            // Campo de Mensagem
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  top: BorderSide(
                    color: Colors.grey[300]!,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mensagemController,
                      decoration: InputDecoration(
                        hintText: 'Digite um comunicado para todas as filiais...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _enviarMensagemGeral(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red[400], // Botão vermelho
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: IconButton(
                      onPressed: _isEnviandoMensagem ? null : _enviarMensagemGeral,
                      icon: _isEnviandoMensagem
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget para Chat Geral
  Widget _buildChatGeral() {
    return StatefulBuilder(
      builder: (context, setStateChat) {
        // Iniciar timer de atualização automática quando o chat abrir
        if (_chatTimer == null) {
          _chatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            setStateChat(() {
              // Forçar reconstrução da UI a cada segundo
            });
          });
        }
        
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getMensagensGerenteStream(),
          builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final mensagens = snapshot.data!;
              
        if (mensagens.isEmpty) {
          return const Center(
            child: Text(
              'Nenhuma mensagem geral ainda.\nInicie uma conversa!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: mensagens.length,
          itemBuilder: (context, index) {
            final mensagem = mensagens[index];
            final isMinhaMensagem = mensagem['user_id'] == Supabase.instance.client.auth.currentUser?.id;
            final dataMensagem = DateTime.parse(mensagem['created_at']);
            
            // Adicionar separador de data se necessário
            final mensagemAnterior = index > 0 ? mensagens[index - 1] : null;
            final dataAnterior = mensagemAnterior != null 
                ? DateTime.parse(mensagemAnterior['created_at']) 
                : null;
            
            final precisaSeparador = dataAnterior == null || 
                !isMesmoDia(dataMensagem, dataAnterior);
            
            return Column(
              children: [
                // Separador de data
                if (precisaSeparador) ...[
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Colors.grey[400],
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            formatarData(dataMensagem),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Colors.grey[400],
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Mensagem
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: isMinhaMensagem 
                        ? MainAxisAlignment.end 
                        : MainAxisAlignment.start,
                    children: [
                      if (!isMinhaMensagem) ...[
                        Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.6,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50], // Fundo vermelho claro para mensagens do gerente
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'GERAL',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red[700],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.broadcast_on_personal,
                                    size: 14,
                                    color: Colors.red[700],
                                  ),
                                  const Spacer(),
                                  Text(
                                    formatarHora(dataMensagem),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mensagem['mensagem'] ?? '',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.red[800],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'De: ${mensagem['users']?['nome'] ?? 'Usuário'}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red[600],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Para mensagens gerais, verificar se todas as filiais visualizaram
                                  FutureBuilder<Map<String, dynamic>>(
                                    future: _verificarStatusVisualizacao(mensagem['id']),
                                    builder: (context, snapshot) {
                                      final todasVisualizaram = snapshot.data?['todasVisualizaram'] ?? false;
                                      final filiaisVisualizaram = snapshot.data?['filiaisVisualizaram'] ?? 0;
                                      final totalFiliais = snapshot.data?['totalFiliais'] ?? 0;
                                      
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.done_all,
                                            size: 14,
                                            color: todasVisualizaram ? Colors.blue[600] : Colors.grey[400],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            todasVisualizaram ? 'Vista por todas' : 'Vista por $filiaisVisualizaram/$totalFiliais',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: todasVisualizaram ? Colors.blue[600] : Colors.grey[400],
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.6,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[200], // Fundo cinza para minhas mensagens
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Você (GERAL)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    formatarHora(dataMensagem),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mensagem['mensagem'] ?? '',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Para mensagens gerais, verificar se todas as filiais visualizaram
                                  FutureBuilder<Map<String, dynamic>>(
                                    future: _verificarStatusVisualizacao(mensagem['id']),
                                    builder: (context, snapshot) {
                                      final todasVisualizaram = snapshot.data?['todasVisualizaram'] ?? false;
                                      final filiaisVisualizaram = snapshot.data?['filiaisVisualizaram'] ?? 0;
                                      final totalFiliais = snapshot.data?['totalFiliais'] ?? 0;
                                      
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.done_all,
                                            size: 14,
                                            color: todasVisualizaram ? Colors.blue[600] : Colors.grey[400],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            todasVisualizaram ? 'Vista por todas' : 'Vista por $filiaisVisualizaram/$totalFiliais',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: todasVisualizaram ? Colors.blue[600] : Colors.grey[400],
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
      },
    );
  }

  // Função para parsear URLs de comprovantes na tela do Gerente (compatível com dados antigos e novos)
  List<String> _parseComprovantesUrlsGerente(dynamic comprovanteData) {
    print('DEBUG GERENTE: ==========================================');
    print('DEBUG GERENTE: INICIANDO PARSE DE COMPROVANTE');
    print('DEBUG GERENTE: Dados originais: $comprovanteData');
    print('DEBUG GERENTE: Tipo dos dados: ${comprovanteData.runtimeType}');

    if (comprovanteData == null || comprovanteData.toString().isEmpty) {
      print('DEBUG GERENTE: Dados nulos ou vazios, retornando lista vazia');
      return [];
    }

    String dataStr = comprovanteData.toString();
    print('DEBUG GERENTE: String convertida: $dataStr');
    print('DEBUG GERENTE: Comprimento da string: ${dataStr.length}');

    // Se já é uma lista (formato novo)
    if (dataStr.startsWith('[') && dataStr.endsWith(']')) {
      try {
        // Remove colchetes e aspas, depois divide por vírgula
        dataStr = dataStr.substring(1, dataStr.length - 1);
        final result = dataStr.split(',').map((url) => url.trim().replaceAll('"', '')).where((url) => url.isNotEmpty).toList();
        print('DEBUG GERENTE: Parseado como lista - Resultado: $result');
        print('DEBUG GERENTE: ==========================================');
        print('DEBUG GERENTE: RESULTADO FINAL (lista): $result');
        print('DEBUG GERENTE: QUANTIDADE: ${result.length}');
        print('DEBUG GERENTE: ==========================================');
        return result;
      } catch (e) {
        print('Erro ao parsear lista de comprovantes: $e');
        return [];
      }
    }

    // Se é string simples separada por vírgula (formato antigo)
    if (dataStr.contains(',')) {
      print('DEBUG GERENTE: Encontrou vírgulas, analisando...');

      // Se contém vírgulas mas parece ser uma única URL (contém domínio), verifica múltiplas URLs
      if (dataStr.contains('supabase.co') || dataStr.contains('http')) {
        print('DEBUG GERENTE: Contém domínio, verificando múltiplas URLs...');

        // PRIMEIRO: Verifica se é uma única URL com vírgulas no nome do arquivo
        // Mas só se não contiver múltiplas URLs completas separadas por vírgula
        bool hasMultipleCompleteUrls = false;
        List<String> possibleUrls = dataStr.split(',');
        int completeUrlCount = 0;

        for (String part in possibleUrls) {
          part = part.trim();
          if (part.isNotEmpty && _isValidUrlGerente(part)) {
            completeUrlCount++;
          }
        }

        hasMultipleCompleteUrls = completeUrlCount > 1;
        print('DEBUG GERENTE: URLs completas encontradas: $completeUrlCount');
        print('DEBUG GERENTE: Tem múltiplas URLs completas: $hasMultipleCompleteUrls');

        // Se tem múltiplas URLs completas ou não é uma única URL válida, tenta dividir por vírgula
        dataStr.split(',');
        List<String> validUrls = [];

        print('DEBUG GERENTE: Possíveis URLs encontradas: $possibleUrls');

        for (String part in possibleUrls) {
          part = part.trim();
          if (part.isNotEmpty && _isValidUrlGerente(part)) {
            validUrls.add(part);
            print('DEBUG GERENTE: URL válida encontrada: $part');
          } else {
            print('DEBUG GERENTE: URL inválida ignorada: $part');
          }
        }

        print('DEBUG GERENTE: Total de URLs válidas: ${validUrls.length}');

        // Se encontrou múltiplas URLs válidas, retorna todas
        if (validUrls.length > 1) {
          print('DEBUG GERENTE: Retornando múltiplas URLs: $validUrls');
          print('DEBUG GERENTE: ==========================================');
          print('DEBUG GERENTE: RESULTADO FINAL (múltiplas URLs): $validUrls');
          print('DEBUG GERENTE: QUANTIDADE: ${validUrls.length}');
          print('DEBUG GERENTE: ==========================================');
          return validUrls;
        }

        // Se encontrou apenas uma URL válida, retorna ela
        if (validUrls.length == 1) {
          print('DEBUG GERENTE: Retornando URL única válida: ${validUrls[0]}');
          print('DEBUG GERENTE: ==========================================');
          print('DEBUG GERENTE: RESULTADO FINAL (URL única válida): $validUrls');
          print('DEBUG GERENTE: QUANTIDADE: ${validUrls.length}');
          print('DEBUG GERENTE: ==========================================');
          return validUrls;
        }

        // Se não encontrou URLs válidas, trata como uma única URL
        print('DEBUG GERENTE: Tratando como URL única');
        final result = [dataStr.trim()];
        print('DEBUG GERENTE: ==========================================');
        print('DEBUG GERENTE: RESULTADO FINAL (URL única fallback): $result');
        print('DEBUG GERENTE: QUANTIDADE: ${result.length}');
        print('DEBUG GERENTE: ==========================================');
        return result;
      }

      // Se não for uma URL válida, tenta dividir por vírgula
      print('DEBUG GERENTE: Tentando divisão inteligente por vírgula...');
      List<String> urls = [];
      List<String> parts = dataStr.split(',');

      for (int i = 0; i < parts.length; i++) {
        String part = parts[i].trim();
        if (part.isEmpty) continue;

        // Se a parte atual parece ser uma URL válida, adiciona
        if (_isValidUrlGerente(part)) {
          urls.add(part);
          print('DEBUG GERENTE: Adicionada URL válida: $part');
        } else {
          // Se não parece ser uma URL válida, tenta combinar com a próxima parte
          if (i + 1 < parts.length) {
            String combined = part + ',' + parts[i + 1].trim();
            if (_isValidUrlGerente(combined)) {
              urls.add(combined);
              i++; // Pula a próxima parte já que foi combinada
              print('DEBUG GERENTE: Adicionada URL combinada: $combined');
            } else {
              // Se ainda não é válida, adiciona como está (pode ser parte de uma URL)
              urls.add(part);
              print('DEBUG GERENTE: Adicionada parte: $part');
            }
          } else {
            urls.add(part);
            print('DEBUG GERENTE: Adicionada parte final: $part');
          }
        }
      }

      final result = urls.where((url) => url.isNotEmpty).toList();
      print('DEBUG GERENTE: Resultado final da divisão inteligente: $result');
      print('DEBUG GERENTE: ==========================================');
      print('DEBUG GERENTE: RESULTADO FINAL (divisão inteligente): $result');
      print('DEBUG GERENTE: QUANTIDADE: ${result.length}');
      print('DEBUG GERENTE: ==========================================');
      return result;
    }

    // Se é uma única URL
    print('DEBUG GERENTE: Tratando como URL única simples');
    final finalResult = [dataStr.trim()];
    print('DEBUG GERENTE: ==========================================');
    print('DEBUG GERENTE: RESULTADO FINAL: $finalResult');
    print('DEBUG GERENTE: QUANTIDADE: ${finalResult.length}');
    print('DEBUG GERENTE: ==========================================');
    return finalResult;
  }

  // Função auxiliar para verificar se uma string parece ser uma URL válida
  bool _isValidUrlGerente(String url) {
    url = url.trim();

    // Verifica se começa com http/https
    if (!url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('file://')) {
      return false;
    }

    // Verifica se tem domínio
    if (!url.contains('supabase.co') && !url.contains('http')) {
      return false;
    }

    // Verifica se tem extensão de arquivo
    if (!url.contains('.pdf') && !url.contains('.png') && !url.contains('.jpg') && !url.contains('.jpeg')) {
      return false;
    }

    return true;
  }

  double _parseMoneyValue(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      try {
        // Remove o símbolo da moeda e espaços
        final cleanValue = value.replaceAll('R\$', '').replaceAll(' ', '');
        // Substitui vírgula por ponto
        return double.parse(cleanValue.replaceAll(',', '.'));
      } catch (e) {
        print('Erro ao parsear valor: $value');
        return 0.0;
      }
    }
    return 0.0;
  }

  String _toDDMMYYYY(String input) {
    if (input.contains('-')) {
      final parts = input.split('-');
      if (parts.length == 3) {
        return '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
      }
    }
    try {
      final dt = DateTime.parse(input);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch(e) {
      return input;
    }
  }

  String _toYYYYMMDD(String input) {
    if (input.contains('/')) {
      final parts = input.split('/');
      if (parts.length == 3) {
        return '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
      }
    }
    return input;
  }

  int _hexToInt(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    return int.parse(hex, radix: 16);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // 3 abas: Relatórios, Taxas, Cartões
    _relatoriosPorFilial = {for (var filial in filiais) filial: []};
    _fetchRelatorios();
    // _fetchSolicitacoes(); // REMOVED: Tables 'solicitacoes_acesso' and 'solicitacoes_perfil' deleted.
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchSolicitacoes() async {
    try {
      // Calcular data de 3 dias atrás
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));

      // Buscar solicitações de relatórios
      final responseRelatorios = await Supabase.instance.client
          .from('solicitacoes_acesso')
          .select('*')
          .gte('created_at', threeDaysAgo.toIso8601String())
          .order('data_relatorio', ascending: false);

      // Buscar solicitações de perfil
      final responsePerfil = await Supabase.instance.client
          .from('solicitacoes_perfil')
          .select('*')
          .gte('created_at', threeDaysAgo.toIso8601String())
          .order('created_at', ascending: false);

      // Combinar as duas listas e adicionar campo 'tipo' para identificação
      final solicitacoesRelatorios = (responseRelatorios as List).map((s) => <String, dynamic>{
        ...s as Map<String, dynamic>,
        'tipo': 'relatorio',
      }).toList();

      final solicitacoesPerfil = (responsePerfil as List).map((s) => <String, dynamic>{
        ...s as Map<String, dynamic>,
        'tipo': 'perfil',
      }).toList();

      setState(() {
        _solicitacoes = [...solicitacoesRelatorios, ...solicitacoesPerfil];
      });
    } catch (error) {
      // Se as tabelas não existirem ainda, não mostra erro
      setState(() {
        _solicitacoes = [];
      });
    }
  }

  Future<void> _subscribeToNotifications() async {
    // Implementação futura para inscrição em tópicos específicos
    print('Ã°Å¸â€â€ Inscrição em notificações configurada');
  }

  String _getFileNameFromUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    final parts = url.split('/');
    return parts.last;
  }

  void _showComprovante(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Comprovante'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () async {
                    // Abre o comprovante no navegador
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  tooltip: 'Abrir no navegador',
                ),
              ],
            ),
            Flexible(
              child: url.toLowerCase().endsWith('.pdf')
                  ? Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  label: const Text('Abrir PDF'),
                  onPressed: () async {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
              )
                  : InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(
                  url,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Erro ao carregar imagem',
                          style: TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            // Abre o comprovante no navegador
                            final uri = Uri.parse(url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            }
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Abrir no navegador'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            )],
        ),
      ),
    );
  }

  // Função para mostrar seleção de mês para exportação PDF
  Future<void> _showMesExportacaoPDF(String filial) async {
    final now = DateTime.now();
    int selectedMonth = now.month;
    int selectedYear = now.year;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecionar Mês para Exportação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Selecione o mês que deseja exportar:'),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: selectedMonth,
              decoration: const InputDecoration(
                labelText: 'Mês',
                border: OutlineInputBorder(),
              ),
              items: [
                for (int i = 1; i <= 12; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(DateFormat('MMMM', 'pt_BR').format(DateTime(2024, i))),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  selectedMonth = value;
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: selectedYear,
              decoration: const InputDecoration(
                labelText: 'Ano',
                border: OutlineInputBorder(),
              ),
              items: [
                for (int i = 2024; i <= now.year; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(i.toString()),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  selectedYear = value;
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _exportarRelatoriosMensalFilialPDF(filial, selectedMonth, selectedYear);
            },
            child: const Text('Exportar'),
          ),
        ],
      ),
    );
  }

  // Função para exportar para PDF (PRETO E BRANCO, SEM TABELA)
  Future<void> _exportarRelatoriosMensalFilialPDF(String filial, int mes, int ano) async {
    print('DEBUG PDF: Iniciando exportação para $filial - $mes/$ano');
    final pdf = pw.Document();
    final now = DateTime.now();

    // Filtrar relatórios pelo mês e ano selecionados
    print('DEBUG PDF: Total de relatórios na filial $filial: ${(_relatoriosPorFilial[filial] ?? []).length}');
    final relatorios = (_relatoriosPorFilial[filial] ?? []).where((r) {
      final data = r['caixa_referente'];
      print('DEBUG PDF: Verificando relatório com data: $data');
      if (data != null && data.length >= 7) {
        try {
          final anoRelatorio = int.parse(data.substring(0, 4));
          final mesRelatorio = int.parse(data.substring(5, 7));
          final match = anoRelatorio == ano && mesRelatorio == mes;
          print('DEBUG PDF: Ano: $anoRelatorio, Mês: $mesRelatorio, Match: $match');
          return match;
        } catch (e) {
          print('DEBUG PDF: Erro ao parsear data: $e');
          return false;
        }
      }
      return false;
    }).toList();
    print('DEBUG PDF: Relatórios filtrados: ${relatorios.length}');

    // Ordena por data crescente
    relatorios.sort((a, b) => (a['caixa_referente'] ?? '').compareTo(b['caixa_referente'] ?? ''));
    print('DEBUG PDF: Relatórios ordenados: ${relatorios.length}');

    // Cabeçalho das colunas
    final headers = [
      'Data',
      'Receita',
      'Dinheiro',
      'Depósito',
      'POS',
      'TEF',
      'ATM',
      'Cobranças',
      'TEV/TED',
      'Total',
    ];

    // Dados das linhas
    print('DEBUG PDF: Processando dados das linhas...');
    final dataRows = relatorios.map((r) {
      try {
        final receita = _parseMoneyValue(r['receita_dia']);
        final dinheiro = _parseMoneyValue(r['dinheiro']);
        final deposito = _parseMoneyValue(r['deposito']);
        final cartaoPos = _parseMoneyValue(r['cartao_pos']);
        final cartaoTef = _parseMoneyValue(r['cartao_tef']);
        final atm = _parseMoneyValue(r['atm']);
        final cobrancas = _parseMoneyValue(r['cobrancas']);
        final tevTed = _parseMoneyValue(r['tev_ted']);
        final total = dinheiro + deposito + cartaoPos + cartaoTef + atm + cobrancas + tevTed;
        return [
          _toDDMMYYYY(r['caixa_referente']),
          _currencyFormat.format(receita),
          _currencyFormat.format(dinheiro),
          _currencyFormat.format(deposito),
          _currencyFormat.format(cartaoPos),
          _currencyFormat.format(cartaoTef),
          _currencyFormat.format(atm),
          _currencyFormat.format(cobrancas),
          _currencyFormat.format(tevTed),
          _currencyFormat.format(total),
        ];
      } catch (e) {
        print('DEBUG PDF: Erro ao processar linha: $e');
        return [
          _toDDMMYYYY(r['caixa_referente']),
          '0,00',
          '0,00',
          '0,00',
          '0,00',
          '0,00',
          '0,00',
          '0,00',
          '0,00',
          '0,00',
        ];
      }
    }).toList();
    print('DEBUG PDF: Linhas processadas: ${dataRows.length}');

    // Totais para cada campo
    print('DEBUG PDF: Calculando totais...');
    double totalReceita = 0;
    double totalDinheiro = 0;
    double totalDeposito = 0;
    double totalPos = 0;
    double totalTef = 0;
    double totalAtm = 0;
    double totalCobrancas = 0;
    double totalTevTed = 0;
    double totalGeral = 0;

    for (var r in relatorios) {
      try {
        final receita = _parseMoneyValue(r['receita_dia']);
        final dinheiro = _parseMoneyValue(r['dinheiro']);
        final deposito = _parseMoneyValue(r['deposito']);
        final cartaoPos = _parseMoneyValue(r['cartao_pos']);
        final cartaoTef = _parseMoneyValue(r['cartao_tef']);
        final atm = _parseMoneyValue(r['atm']);
        final cobrancas = _parseMoneyValue(r['cobrancas']);
        final tevTed = _parseMoneyValue(r['tev_ted']);
        final total = dinheiro + deposito + cartaoPos + cartaoTef + atm + cobrancas + tevTed;

        totalReceita += receita;
        totalDinheiro += dinheiro;
        totalDeposito += deposito;
        totalPos += cartaoPos;
        totalTef += cartaoTef;
        totalAtm += atm;
        totalCobrancas += cobrancas;
        totalTevTed += tevTed;
        totalGeral += total;
      } catch (e) {
        print('DEBUG PDF: Erro ao calcular totais: $e');
      }
    }
    print('DEBUG PDF: Totais calculados - Receita: $totalReceita, Dinheiro: $totalDinheiro, Total Geral: $totalGeral');

    print('DEBUG PDF: Criando página do PDF...');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('Relatório Detalhado', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Divider(height: 20),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Filial: $filial', style: pw.TextStyle(fontSize: 10)),
                    pw.Text('Mês: ${DateFormat('MMMM/yyyy', 'pt_BR').format(DateTime(ano, mes))}', style: pw.TextStyle(fontSize: 10)),
                  ]
              ),
              pw.SizedBox(height: 8),
              pw.Text('Funcionário: ${relatorios.isNotEmpty ? (relatorios.first['nome_funcionario'] ?? 'N/A') : 'N/A'}', style: pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.left),
              pw.SizedBox(height: 20),
            ]
        ),
        build: (pw.Context context) {
          return [
            // Cabeçalho das colunas
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: headers.asMap().entries.map((entry) {
                final i = entry.key;
                final h = entry.value;
                double flex = 1.2;
                if (h == 'Data') flex = 0.8;
                return pw.Expanded(
                  flex: flex.round(),
                  child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                );
              }).toList(),
            ),
            pw.SizedBox(height: 4),
            // Linhas de dados
            ...dataRows.map((row) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: row.asMap().entries.map((entry) {
                  final i = entry.key;
                  final cell = entry.value;
                  double flex = 1.2;
                  if (headers[i] == 'Data') flex = 0.8;
                  return pw.Expanded(
                    flex: flex.round(),
                    child: pw.Text(
                      cell,
                      style: pw.TextStyle(fontSize: 8),
                      textAlign: pw.TextAlign.left,
                    ),
                  );
                }).toList(),
              ),
            )),
            pw.SizedBox(height: 18),
            // Linha de totais
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text('TOTAIS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(_currencyFormat.format(totalReceita), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.left),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(_currencyFormat.format(totalDinheiro), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.left),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(_currencyFormat.format(totalDeposito), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.left),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(_currencyFormat.format(totalPos), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.left),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(_currencyFormat.format(totalTef), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.left),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(_currencyFormat.format(totalAtm), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.left),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(_currencyFormat.format(totalCobrancas), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.left),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(_currencyFormat.format(totalTevTed), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.left),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(_currencyFormat.format(totalGeral), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.left),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );
    print('DEBUG PDF: PDF criado, salvando...');
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    print('DEBUG PDF: PDF salvo com sucesso!');
  }
  @override
  Widget build(BuildContext context) {
    final ThemeData gerenteTheme = _isDarkMode
        ? ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF181818),
      cardColor: const Color(0xFF232323),
      colorScheme: ThemeData.dark().colorScheme.copyWith(
        primary: Colors.red,
        secondary: Colors.redAccent,
        surface: const Color(0xFF232323),
        background: const Color(0xFF181818),
        onSurface: Colors.white,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    )
        : ThemeData.light().copyWith(
      scaffoldBackgroundColor: Colors.white,
      cardColor: Colors.white,
      colorScheme: ThemeData.light().colorScheme.copyWith(
        primary: Colors.red,
        secondary: Colors.redAccent,
        surface: Colors.white,
        background: Colors.white,
        onSurface: Colors.black,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      ),
    );



    return Theme(
      data: gerenteTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel do Gerente'),
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              setState(() {
                _isDrawerOpen = !_isDrawerOpen;
              });
            },
          ),
          actions: [
            IconButton(
              icon: Icon(_isDarkMode ? Icons.wb_sunny : Icons.nightlight_round),
              onPressed: () {
                setState(() {
                  _isDarkMode = !_isDarkMode;
                });
              },
              tooltip: _isDarkMode ? 'Modo Claro' : 'Modo Escuro',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                if (_tabController.index == 0) {
                  _fetchRelatorios();
                } else {
                  _fetchSolicitacoes();
                }
              },
              tooltip: 'Atualizar',
            ),
            
            // Botão de Chat - Muda comportamento baseado no contexto
            IconButton(
              icon: Icon(_selectedMenuIndex == 1 && _selectedSubMenu.isNotEmpty 
                  ? Icons.message  // Chat individual dentro de filial
                  : Icons.chat),   // Chat geral na tela inicial
              onPressed: _selectedMenuIndex == 1 && _selectedSubMenu.isNotEmpty
                  ? () => _abrirChatIndividualFilial(_selectedSubMenu)  // Chat individual
                  : _abrirChatGerente,  // Chat geral
              tooltip: _selectedMenuIndex == 1 && _selectedSubMenu.isNotEmpty
                  ? 'Chat Individual - $_selectedSubMenu'
                  : 'Chat com Filiais',
            ),

            // Botão de logout provisório
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _signOut,
              tooltip: 'Logout',
            ),
          ],
        ),
        body: Stack(
          children: [
            // Conteúdo principal
            _buildMainContent(),
            // Drawer lateral animado
            if (_isDrawerOpen)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Row(
                    children: [
                      // Fundo escuro FORÃƒâ€¡ADO - não depende do tema
                      Container(
                        width: MediaQuery.of(context).size.width * 0.7,
                        height: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 300, minWidth: 250),
                        color: _isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              color: Colors.transparent,
                              child: Row(
                                children: [
                                  Text(
                                    'Menu',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: _isDarkMode ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: Icon(Icons.close, color: _isDarkMode ? Colors.white : Colors.black),
                                    onPressed: () {
                                      setState(() {
                                        _isDrawerOpen = false;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Divider(color: _isDarkMode ? Colors.grey[700] : Colors.grey[300]),
                            ListTile(
                              leading: Icon(Icons.home, color: _selectedMenuIndex == 0 ? Colors.red : (_isDarkMode ? Colors.white : Colors.black)),
                              title: Text('Início', style: TextStyle(color: _selectedMenuIndex == 0 ? Colors.red : (_isDarkMode ? Colors.white : Colors.black))),
                              selected: _selectedMenuIndex == 0,
                              onTap: () {
                                setState(() {
                                  _selectedMenuIndex = 0;
                                  _showSubMenu = false;
                                  _selectedSubMenu = '';
                                  _isDrawerOpen = false;
                                });
                              },
                            ),
                            ListTile(
                              leading: Icon(Icons.assessment, color: _selectedMenuIndex == 1 ? Colors.red : (_isDarkMode ? Colors.white : Colors.black)),
                              title: Text('Relatórios', style: TextStyle(color: _selectedMenuIndex == 1 ? Colors.red : (_isDarkMode ? Colors.white : Colors.black))),
                              trailing: Icon(_showSubMenu ? Icons.expand_less : Icons.expand_more, color: _isDarkMode ? Colors.white : Colors.black),
                              selected: _selectedMenuIndex == 1,
                              onTap: () {
                                setState(() {
                                  if (_selectedMenuIndex == 1) {
                                    _showSubMenu = !_showSubMenu;
                                  } else {
                                    _selectedMenuIndex = 1;
                                    _showSubMenu = true;
                                  }
                                });
                              },
                            ),
                            if (_showSubMenu && _selectedMenuIndex == 1)
                              ...filiais.map((filial) => ListTile(
                                leading: const SizedBox(width: 32),
                                title: Text(
                                  filial,
                                  style: TextStyle(
                                    color: _selectedSubMenu == filial ? Colors.red : (_isDarkMode ? Colors.white : Colors.black),
                                    fontWeight: _selectedSubMenu == filial ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                selected: _selectedSubMenu == filial,
                                onTap: () {
                                  setState(() {
                                    _selectedSubMenu = filial;
                                    _isDrawerOpen = false;
                                  });
                                },
                              )),
                            ListTile(
                              leading: Icon(Icons.notifications, color: _selectedMenuIndex == 2 ? Colors.red : (_isDarkMode ? Colors.white : Colors.black)),
                              title: Text('Solicitações', style: TextStyle(color: _selectedMenuIndex == 2 ? Colors.red : (_isDarkMode ? Colors.white : Colors.black))),
                              selected: _selectedMenuIndex == 2,
                              onTap: () {
                                setState(() {
                                  _selectedMenuIndex = 2;
                                  _showSubMenu = false;
                                  _selectedSubMenu = '';
                                  _isDrawerOpen = false;
                                });
                              },
                            ),

                          ],
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isDrawerOpen = false;
                            });
                          },
                          child: Container(
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedMenuIndex) {
      case 0: // Início - Últimos relatórios de todas as filiais
        return Padding(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
          child: Column(
            children: [
              const Text(
                'Últimos Relatórios',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.02),
              

              
              // Campo de busca
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar por funcionário, filial ou data',
                  prefixIcon: Icon(Icons.search),
                ),
                keyboardType: TextInputType.text,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.02),
              
              // Lista de relatórios (cards modernos)
              Expanded(
                child: _buildRelatoriosList(),
              ),
            ],
          ),
        );
      case 1: // Relatórios - Submenu de filiais
        if (_selectedSubMenu.isNotEmpty) {
          return DefaultTabController(
            length: 3,
            child: Column(
              children: [
                // Header com botão voltar e título
                Padding(
                  padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () {
                              setState(() {
                                _selectedSubMenu = '';
                              });
                            },
                          ),
                          Flexible(
                            child: Text(
                              '$_selectedSubMenu',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  await _exportarExcelFilialSyncfusion(_selectedSubMenu);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Excel de $_selectedSubMenu exportado com sucesso!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Erro ao exportar: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.table_view, color: Colors.white),
                              label: const Text('Exportar para Excel'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await _showMesExportacaoPDF(_selectedSubMenu);
                              },
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text('Exportar para PDF'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // TabBar
                TabBar(
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.assessment),
                      text: 'Relatórios',
                    ),
                    Tab(
                      icon: Icon(Icons.payment),
                      text: 'Taxas',
                    ),
                    Tab(
                      icon: Icon(Icons.credit_card),
                      text: 'Cartões',
                    ),
                  ],
                ),
                // TabBarView
                Expanded(
                  child: TabBarView(
                    children: [
                      // Aba Relatórios
                      Padding(
                        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
                        child: Column(
                          children: [
                            // Filtros modernos
                            Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _selectDateRange,
                                    icon: const Icon(Icons.date_range),
                                    label: Text(_dataInicial != null && _dataFinal != null
                                        ? '${_dataInicial!.day.toString().padLeft(2, '0')}/${_dataInicial!.month.toString().padLeft(2, '0')}/${_dataInicial!.year} - ${_dataFinal!.day.toString().padLeft(2, '0')}/${_dataFinal!.month.toString().padLeft(2, '0')}/${_dataFinal!.year}'
                                        : 'Período'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _clearDateFilter,
                                    icon: const Icon(Icons.clear),
                                    label: const Text('Limpar filtro de data'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            // Campo de busca
                            TextField(
                              decoration: const InputDecoration(
                                hintText: 'Buscar por data',
                                prefixIcon: Icon(Icons.search),
                              ),
                              keyboardType: TextInputType.text,
                              inputFormatters: [
                                // Permite qualquer caractere, incluindo "/"
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value;
                                });
                              },
                            ),

                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            // Lista de relatórios da filial selecionada
                            Expanded(
                              child: _buildRelatoriosList(filialEspecifica: _selectedSubMenu),
                            ),
                          ],
                        ),
                      ),
                      // Aba Taxas (Rede + SIPAG)
                      Padding(
                        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
                        child: _buildTaxasCalculator(),
                      ),
                      // Aba SIPAG (original)
                      Padding(
                        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
                        child: _buildSipagCalculator(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assessment, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Selecione uma filial no menu lateral',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }
      case 2: // Solicitações
        return Padding(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
          child: Column(
            children: [
              const Text(
                'Solicitações',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.02),
              // TabBar para duas categorias de solicitações
              Container(
                decoration: BoxDecoration(
                  color: _isDarkMode ? Colors.grey[800] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: _isDarkMode ? Colors.white : Colors.black,
                  unselectedLabelColor: _isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  indicator: BoxDecoration(
                    color: _isDarkMode ? Colors.blue[600] : Colors.blue[400],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  tabs: const [
                    Tab(icon: Icon(Icons.assessment), text: 'Relatórios'),
                    Tab(icon: Icon(Icons.person), text: 'Perfil'),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.02),
              // Conteúdo das abas
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // ABA 1: Solicitações de Relatórios
                    _buildSolicitacoesRelatoriosList(),
                    // ABA 2: Solicitações de Perfil
                    _buildSolicitacoesPerfilList(),
                  ],
                ),
              ),
            ],
          ),
        );
      default:
        return const Center(child: Text('Selecione uma opção no menu'));
    }
  }

  Widget _buildSolicitacoesRelatoriosList() {
    // Filtra apenas solicitações de relatórios
    final solicitacoesRelatorios = _solicitacoes.where((s) => s['tipo'] == 'relatorio').toList();

    if (solicitacoesRelatorios.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assessment_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Nenhuma solicitação de relatório pendente',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      itemCount: solicitacoesRelatorios.length,
      itemBuilder: (context, index) {
        final solicitacao = solicitacoesRelatorios[index];
        return Padding(
          padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height * 0.008, horizontal: 2),
          child: Card(
            margin: EdgeInsets.zero,
            color: solicitacao['status'] == 'pendente'
                ? (_isDarkMode ? Colors.orange[900] : Colors.orange[50])
                : null,
            shape: solicitacao['status'] == 'pendente'
                ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.orange, width: 2),
            )
                : null,
            child: Padding(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.025),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Solicitação de ${solicitacao['tipo_solicitacao']} - ${solicitacao['filial'] ?? 'N/A'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: solicitacao['status'] == 'pendente' ? Colors.orange :
                          solicitacao['status'] == 'aprovada' ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          solicitacao['status']?.toString().toUpperCase() ?? 'N/A',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Funcionário: ${solicitacao['nome_funcionario'] ?? 'N/A'}'),
                  Text('Data: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(solicitacao['created_at']))}'),
                  if (solicitacao['observacoes'] != null && solicitacao['observacoes'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Observações: ${solicitacao['observacoes']}',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (solicitacao['status'] == 'pendente')
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _aprovarSolicitacao(solicitacao['id']),
                            icon: const Icon(Icons.check, color: Colors.white),
                            label: const Text('Aprovar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _rejeitarSolicitacao(solicitacao['id']),
                            icon: const Icon(Icons.close, color: Colors.white),
                            label: const Text('Rejeitar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSolicitacoesPerfilList() {
    // Filtra apenas solicitações de perfil
    final solicitacoesPerfil = _solicitacoes.where((s) => s['tipo'] == 'perfil').toList();

    if (solicitacoesPerfil.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Nenhuma solicitação de perfil pendente',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      itemCount: solicitacoesPerfil.length,
      itemBuilder: (context, index) {
        final solicitacao = solicitacoesPerfil[index];
        return Padding(
          padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height * 0.008, horizontal: 2),
          child: Card(
            margin: EdgeInsets.zero,
            color: solicitacao['status'] == 'pendente'
                ? (_isDarkMode ? Colors.blue[900] : Colors.blue[50])
                : null,
            shape: solicitacao['status'] == 'pendente'
                ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.blue, width: 2),
            )
                : null,
            child: Padding(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.025),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Solicitação de ${solicitacao['tipo_solicitacao']} de Perfil',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
            Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                          color: solicitacao['status'] == 'pendente' ? Colors.blue :
                          solicitacao['status'] == 'aprovada' ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          solicitacao['status']?.toString().toUpperCase() ?? 'N/A',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                  ),
                ),
              ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Funcionário: ${solicitacao['nome_funcionario'] ?? 'N/A'}'),
                  Text('Data: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(solicitacao['created_at']))}'),
                  if (solicitacao['dados_solicitados'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                          Text('Dados solicitados:', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Nome: ${solicitacao['dados_solicitados']['nome'] ?? 'N/A'}'),
                          Text('Email: ${solicitacao['dados_solicitados']['email_empresa'] ?? 'N/A'}'),
                        ],
                      ),
                    ),
                  if (solicitacao['observacoes'] != null && solicitacao['observacoes'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Observações: ${solicitacao['observacoes']}',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (solicitacao['status'] == 'pendente')
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _aprovarSolicitacaoPerfil(solicitacao['id'], 'aprovada'),
                            icon: const Icon(Icons.check, color: Colors.white),
                            label: const Text('Aprovar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _rejeitarSolicitacaoPerfil(solicitacao['id'], 'rejeitada'),
                    icon: const Icon(Icons.close, color: Colors.white),
                            label: const Text('Rejeitar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _aprovarSolicitacaoPerfil(String solicitacaoId, String status) async {
    try {
      await Supabase.instance.client
          .from('solicitacoes_perfil')
          .update({
        'status': status,
        'data_resposta': DateTime.now().toIso8601String(),
        'aprovado_por': Supabase.instance.client.auth.currentUser?.id,
      })
          .eq('id', solicitacaoId);

      // Recarregar solicitações
      await _fetchSolicitacoes();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Solicitação ${status == 'aprovada' ? 'aprovada' : 'rejeitada'} com sucesso!'),
          backgroundColor: status == 'aprovada' ? Colors.green : Colors.red,
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao processar solicitação: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejeitarSolicitacaoPerfil(String solicitacaoId, String status) async {
    await _aprovarSolicitacaoPerfil(solicitacaoId, status);
  }

  Widget _buildRelatoriosList({String? filialEspecifica}) {
    // Filtra relatórios por busca e filial
    List<Map<String, dynamic>> allReports = [];

    if (filialEspecifica != null) {
      // Se uma filial específica foi selecionada, mostra apenas relatórios dela
      allReports.addAll(_relatoriosPorFilial[filialEspecifica] ?? []);
    } else {
      // Para a tela Início, mostra apenas o último relatório de cada filial
      for (var filial in filiais) {
        final relatoriosFilial = _relatoriosPorFilial[filial] ?? [];
        if (relatoriosFilial.isNotEmpty) {
          // Pega o relatório mais recente da filial
          relatoriosFilial.sort((a, b) => b['created_at'].compareTo(a['created_at']));
          allReports.add(relatoriosFilial.first);
        }
      }
    }
    if (_searchQuery.isNotEmpty) {
      allReports = allReports.where((r) {
        final funcionario = (r['nome_funcionario'] ?? '').toString().toLowerCase();
        final filial = (r['filial_id'] ?? '').toString().toLowerCase();
        final caixaReferente = (r['caixa_referente'] ?? '').toString();
        final dataCriacao = (r['created_at'] ?? '').toString();
        final query = _searchQuery.toLowerCase().trim();

        // Busca por funcionário
        if (funcionario.contains(query)) return true;

        // Busca por filial (apenas se não estiver em uma filial específica)
        if (filialEspecifica == null && filial.contains(query)) return true;

        // Busca por caixa referente (formato YYYY-MM-DD)
        if (caixaReferente.contains(query)) return true;

        // Busca por data de criação (formato ISO)
        if (dataCriacao.contains(query)) return true;

        // Busca por data formatada (DD/MM/YYYY)
        try {
          final dataFormatada = _toDDMMYYYY(caixaReferente);
          if (dataFormatada.contains(query)) return true;
        } catch (e) {
          // Ignora erros de formatação
        }

        return false;
      }).toList();
    }
    allReports.sort((a, b) => b['created_at'].compareTo(a['created_at']));
    if (allReports.isEmpty) {
      if (filialEspecifica != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.assessment_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Nenhum relatório encontrado para $filialEspecifica',
                style: const TextStyle(fontSize: 18, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      } else {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assessment_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Nenhum relatório encontrado para o período.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      itemCount: allReports.length,
      itemBuilder: (context, index) {
        final relatorio = allReports[index];
        return Padding(
          padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height * 0.008, horizontal: 2),
          child: Card(
            margin: EdgeInsets.zero,
            color: (relatorio['tem_observacao_gerente'] == true)
                ? (_isDarkMode ? Colors.red[900] : Colors.red[50])
                : null,
            shape: (relatorio['tem_observacao_gerente'] == true)
                ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.red, width: 2),
            )
                : null,
            child: Padding(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.025),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
            Expanded(
                        child: Text(
                          relatorio['filial_id'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (relatorio['is_edited'] == true)
                        Row(
                          children: [
                            const Icon(Icons.edit, color: Colors.orange, size: 18),
                            const SizedBox(width: 4),
                            Text('Editado', style: TextStyle(color: Colors.orange[700], fontSize: 12)),
                          ],
                        ),
                      if (relatorio['tem_observacao_gerente'] == true)
                        Row(
                          children: [
                            Icon(Icons.warning, color: _isDarkMode ? Colors.red[300] : Colors.red, size: 18),
                            const SizedBox(width: 4),
                            Text('Observação', style: TextStyle(
                                color: _isDarkMode ? Colors.red[300] : Colors.red[700],
                                fontSize: 12
                            )),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<String>(
                    future: _getNome(relatorio['user_id']),
                builder: (context, snapshot) {
                      return Text(
                        'Funcionário: ${snapshot.data ?? 'Carregando...'}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      );
                    },
                  ),
                  Text('Data: ${_formatDate(relatorio['created_at'])}'),
                  Text('Caixa Ref.: ${_toDDMMYYYY(relatorio['caixa_referente'] ?? '')}'),
                  Text('Valor: ${_formatCurrency(_parseMoneyValue(relatorio['receita_dia']))}'),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: IconButton(
                          icon: const Icon(Icons.receipt_long),
                          tooltip: 'Ver Detalhes',
                          onPressed: () {
                            _showReportDetails(context, relatorio);
                          },
                        ),
                      ),
                      Flexible(
                        child: IconButton(
                          icon: const Icon(Icons.image),
                          tooltip: 'Ver Comprovantes',
                          onPressed: () {
                            _showComprovantesDialog(context, relatorio);
                          },
                        ),
                      ),
                      Flexible(
                        child: IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Adicionar Observação',
                          onPressed: () {
                            _adicionarObservacaoGerente(context, relatorio);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showComprovantesDialog(BuildContext context, Map<String, dynamic> relatorio) {
    print('DEBUG GERENTE: Iniciando _showComprovantesDialog');
    print('DEBUG GERENTE: Relatório completo: $relatorio');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comprovantes'),
        content: Container(
          width: double.maxFinite,
          height: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var tipo in [
                  'comprovante_receita',
                  'comprovante_dinheiro',
                  'comprovante_deposito',
                  'comprovante_cartao_pos',
                  'comprovante_cartao_tef',
                  'comprovante_cobrancas',
                  'comprovante_tev_ted',
                ])
                  if (relatorio[tipo] != null && relatorio[tipo].toString().isNotEmpty)
                    Builder(
                      builder: (context) {
                        print('DEBUG GERENTE: Processando tipo: $tipo');
                        print('DEBUG GERENTE: Dados brutos: ${relatorio[tipo]}');

                        final urls = _parseComprovantesUrlsGerente(relatorio[tipo]);
                        print('DEBUG GERENTE: URLs parseadas para $tipo: $urls');
                        print('DEBUG GERENTE: Quantidade de URLs: ${urls.length}');

                        if (urls.isEmpty) {
                          print('DEBUG GERENTE: URLs vazias para $tipo, retornando SizedBox.shrink()');
                          return const SizedBox.shrink();
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                tipo.replaceAll('comprovante_', '').toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 120,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: urls.length,
                                itemBuilder: (context, index) {
                                  final url = urls[index];
                                  final isPdf = url.toLowerCase().endsWith('.pdf');
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: GestureDetector(
                                      onTap: () => _showComprovante(context, url),
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey[300]!),
                                          borderRadius: BorderRadius.circular(8),
                                          color: Colors.grey[100],
                                        ),
                                        child: isPdf
                                            ? const Center(child: Icon(Icons.picture_as_pdf, color: Colors.red, size: 32))
                                            : ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(url, fit: BoxFit.cover),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),
                if ([
                  'comprovante_receita',
                  'comprovante_dinheiro',
                  'comprovante_deposito',
                  'comprovante_cartao_pos',
                  'comprovante_cartao_tef',
                  'comprovante_cobrancas',
                  'comprovante_tev_ted',
                ].every((tipo) => relatorio[tipo] == null || relatorio[tipo].toString().isEmpty))
                  const Text('Nenhum comprovante enviado.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    final date = DateTime.parse(isoDate);
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }

  String _formatDateOnly(String isoDate) {
    if (isoDate.isEmpty) return '';
    final date = DateTime.parse(isoDate);
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  Future<String> _getNome(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('nome')
          .eq('id', userId)
          .single();
      return response['nome'] ?? 'Funcionário';
    } catch (error) {
      return 'Funcionário';
    }
  }

  Future<void> _signOut() async {
    // Limpar credenciais salvas para permitir trocar de conta
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_email');
    await prefs.remove('saved_password');
    
    // Fazer logout do Supabase
    await Supabase.instance.client.auth.signOut();
    
    // Voltar para a tela de login
    // Voltar para a tela de login
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }
  Future<void> _fetchRelatorios() async {
    if (!mounted) return;

    try {
      setState(() {
        _message = 'Carregando relatórios...';
      });

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _message = 'Erro: Usuário não está logado.';
        });
        return;
      }

      // Buscar todos os usuários para mapear user_id -> nome
      final usersResponse = await Supabase.instance.client
          .from('users')
          .select('id, nome, filial_id');
      final Map<String, String> userIdToNome = {};
      for (var user in usersResponse) {
        userIdToNome[user['id']] = user['nome'] ?? '';
      }

      // Buscar relatórios por filial
      for (var filial in filiais) {
        if (!mounted) return;

        // Use ServiceLocator/Repository instead of direct Supabase
        var response = await ServiceLocator.repository.getRelatoriosGerente(filial);
        
        // Filter by date if needed (Repository might handle this later, but for mock doing here is fine or in mock)
        if (_dataInicial != null && _dataFinal != null) {
           final dataInicialStr = _dataInicial!.toIso8601String().split('T')[0];
           final dataFinalStr = _dataFinal!.toIso8601String().split('T')[0];
           
           response = response.where((r) {
             final data = r['data'] ?? r['caixa_referente']; // Handle both keys
             if (data == null) return false;
             return data.compareTo(dataInicialStr) >= 0 && data.compareTo(dataFinalStr) <= 0;
           }).toList();
        }

        // Preencher nome_funcionario e filial (Simulado ou Real)
        final List<Map<String, dynamic>> relatoriosComNome = response.map((r) {
           // Mapear user_id se possível, ou usar placeholder
          // r['nome_funcionario'] = userIdToNome[r['user_id']] ?? 'Funcionário'; // Requires user list fetch
          r['nome_funcionario'] = r['nome_funcionario'] ?? 'Funcionário Mock';
          r['filial'] = filial;
          
          // Ensure keys match what GerentePage expects
          r['caixa_referente'] = r['data']; 
          r['observacao_gerente'] = r['observacao_gerente'];
          r['status'] = r['status'] ?? 'pendente';
          
          return r;
        }).toList();

        if (mounted) {
          setState(() {
            _relatoriosPorFilial[filial] = relatoriosComNome;
          });
        }
      }

      if (mounted) {
        setState(() {
          _message = 'Relatórios carregados com sucesso!';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Erro ao carregar relatórios: $error';
        });
      }
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025), // Permitir visualizar desde 2025
      lastDate: DateTime.now(),
      initialDateRange: _dataInicial != null && _dataFinal != null
          ? DateTimeRange(start: _dataInicial!, end: _dataFinal!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.red,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dataInicial = picked.start;
        _dataFinal = picked.end;
      });
      await _fetchRelatorios();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _dataInicial = null;
      _dataFinal = null;
    });
    _fetchRelatorios();
  }

  num _calculateTotal(List<Map<String, dynamic>> relatorios) {
    num total = 0;
    for (var relatorio in relatorios) {
      final cartaoTef = _parseMoneyValue(relatorio['cartao_tef']);
      final cartaoPos = _parseMoneyValue(relatorio['cartao_pos']);
      final cobrancas = _parseMoneyValue(relatorio['cobrancas']);
      final tevTed = _parseMoneyValue(relatorio['tev_ted']);
      total += cartaoTef + cartaoPos + cobrancas + tevTed;
    }
    return total;
  }

  Widget _buildSolicitacoesList() {
    if (_solicitacoes.isEmpty) {
                    return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_open, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Nenhuma solicitação de acesso',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'As solicitações aparecerão aqui quando os funcionários solicitarem acesso para editar relatórios.',
                        textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
                        ),
          ],
                      ),
                    );
                  }
                  
                  return ListView.builder(
      itemCount: _solicitacoes.length,
                    itemBuilder: (context, index) {
        final solicitacao = _solicitacoes[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(solicitacao['status'] ?? 'pendente'),
              child: Icon(
                _getStatusIcon(solicitacao['status'] ?? 'pendente'),
                color: Colors.white,
              ),
            ),
            title: Text(
              'Solicitação de ${solicitacao['nome_funcionario'] ?? 'Funcionário'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filial: ${solicitacao['filial'] ?? ''}'),
                Text('Data do Relatório: ${_formatDateOnly(solicitacao['data_relatorio'] ?? '')}'),
                Text('Motivo: ${solicitacao['motivo'] ?? ''}'),
                Text('Status: ${_getStatusText(solicitacao['status'] ?? 'pendente')}'),
              ],
            ),
            trailing: solicitacao['status'] == 'pendente'
                ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _aprovarSolicitacao(solicitacao['id']),
                  tooltip: 'Aprovar',
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _rejeitarSolicitacao(solicitacao['id']),
                  tooltip: 'Rejeitar',
                ),
              ],
            )
                : null,
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'aprovado':
        return Colors.green;
      case 'rejeitado':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'aprovado':
        return Icons.check;
      case 'rejeitado':
        return Icons.close;
      default:
        return Icons.schedule;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'aprovado':
        return 'Aprovado';
      case 'rejeitado':
        return 'Rejeitado';
      default:
        return 'Pendente';
    }
  }

  Future<void> _aprovarSolicitacao(String id) async {
    try {
      await Supabase.instance.client
          .from('solicitacoes_acesso')
          .update({'status': 'aprovado'})
          .eq('id', id);

      _fetchSolicitacoes();
      setState(() {
        _message = 'Solicitação aprovada com sucesso!';
      });
    } catch (error) {
      setState(() {
        _message = 'Erro ao aprovar solicitação: $error';
      });
    }
  }

  Future<void> _rejeitarSolicitacao(String id) async {
    try {
      await Supabase.instance.client
          .from('solicitacoes_acesso')
          .update({'status': 'rejeitado'})
          .eq('id', id);

      _fetchSolicitacoes();
      setState(() {
        _message = 'Solicitação rejeitada.';
      });
    } catch (error) {
      setState(() {
        _message = 'Erro ao rejeitar solicitação: $error';
      });
    }
  }

  String _formatCurrency(num value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  // Função para adicionar observação do gerente
  Future<void> _adicionarObservacaoGerente(BuildContext context, Map<String, dynamic> relatorio) async {
    final TextEditingController observacaoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar Observação do Gerente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
                        children: [
            TextField(
              controller: observacaoController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observação',
                hintText: 'Digite sua observação sobre este relatório...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (observacaoController.text.trim().isNotEmpty) {
                try {
                  await _salvarObservacaoGerente(relatorio['id'].toString(), observacaoController.text.trim());

                  if (mounted) {
                    // Fecha apenas o diálogo de observação
                    Navigator.pop(context);

                    // Mostra confirmação com instruções
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Observação salva! Use o botão de atualizar para ver o destaque.'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 4),
                        action: SnackBarAction(
                          label: 'Atualizar',
                          textColor: Colors.white,
                          onPressed: () async {
                            if (mounted) {
                              await _fetchRelatorios();
                            }
                          },
                        ),
                      ),
                    );
                  }
                } catch (error) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao salvar observação: $error'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor, digite uma observação'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // Função para salvar observação do gerente no banco
  Future<void> _salvarObservacaoGerente(String relatorioId, String observacao) async {
    try {
      final idInt = int.parse(relatorioId);

      await Supabase.instance.client
          .from('relatorios')
          .update({
        'observacao_gerente': observacao,
        'tem_observacao_gerente': true,
      })
          .eq('id', idInt);
    } catch (error) {
      rethrow;
    }
  }

  void _showReportDetails(BuildContext context, Map<String, dynamic> relatorio) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalhes do Relatório'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
              Text('Filial: ${relatorio['filial_id'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              FutureBuilder<String>(
                future: _getNome(relatorio['user_id']),
                builder: (context, snapshot) {
                  return Text('Funcionário: ${snapshot.data ?? 'Carregando...'}');
                },
              ),
              Text('Data: ${_formatDate(relatorio['created_at'])}'),
              const SizedBox(height: 8),
              Text('Saldo Inicial: ${_formatCurrency(_parseMoneyValue(relatorio['saldo_inicial']))}', style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text('Receita do Dia: ${_formatCurrency(_parseMoneyValue(relatorio['receita_dia']))}', style: const TextStyle(fontWeight: FontWeight.w500)),
              if (relatorio['caixa_referente'] != null && relatorio['caixa_referente'].toString().isNotEmpty)
                Text('Caixa referente: ${_toDDMMYYYY(relatorio['caixa_referente'])}'),
              Text('Dinheiro: ${_formatCurrency(_parseMoneyValue(relatorio['dinheiro']))}'),
              Text('Depósito: ${_formatCurrency(_parseMoneyValue(relatorio['deposito']))}'),
              Text('Cartão POS: ${_formatCurrency(_parseMoneyValue(relatorio['cartao_pos']))}'),
              Text('Cartão TEF: ${_formatCurrency(_parseMoneyValue(relatorio['cartao_tef']))}'),
              Text('ATM: ${_formatCurrency(_parseMoneyValue(relatorio['atm']))}'),
              Text('Cobranças: ${_formatCurrency(_parseMoneyValue(relatorio['cobrancas']))}'),
              Text('TEV/TED: ${_formatCurrency(_parseMoneyValue(relatorio['tev_ted']))}'),
              if (relatorio['observacoes'] != null && relatorio['observacoes'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('Observações: ${relatorio['observacoes']}'),
                ),
              if (relatorio['observacao_gerente'] != null && relatorio['observacao_gerente'].toString().isNotEmpty)
                                  Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Observação do Gerente:',
                                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red[700],
                        ),
                      ),
                      Text(
                        relatorio['observacao_gerente'],
                        style: TextStyle(
                          color: Colors.red[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                'Depósito realizado: ${(relatorio['deposito_feito'] == true || relatorio['deposito_feito'] == 1 || relatorio['deposito_feito'] == 'true') ? 'Sim' : 'Não'}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: (relatorio['deposito_feito'] == true || relatorio['deposito_feito'] == 1 || relatorio['deposito_feito'] == 'true') ? Colors.black : Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final dinheiro = _parseMoneyValue(relatorio['dinheiro']);
                  final cartaoPos = _parseMoneyValue(relatorio['cartao_pos']);
                  final cartaoTef = _parseMoneyValue(relatorio['cartao_tef']);
                  final atm = _parseMoneyValue(relatorio['atm']);
                  final cobrancas = _parseMoneyValue(relatorio['cobrancas']);
                  final tevTed = _parseMoneyValue(relatorio['tev_ted']);
                  final total = dinheiro + cartaoPos + cartaoTef + atm + cobrancas + tevTed;
                  return Text('Total: ${_formatCurrency(total)}', style: const TextStyle(fontWeight: FontWeight.bold));
                },
                                  ),
                                ],
                              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  // 3. Função para construir a calculadora SIPAG
  Widget _buildSipagCalculator() {
    // Usar variáveis de estado persistentes para evitar perda de dados
    if (_cartoesValorBrutoRedeController == null) _cartoesValorBrutoRedeController = TextEditingController();
    if (_cartoesPixRedeController == null) _cartoesPixRedeController = TextEditingController();
    if (_cartoesValorBrutoController == null) _cartoesValorBrutoController = TextEditingController();
    if (_cartoesPixController == null) _cartoesPixController = TextEditingController();

    // Inicializar os campos com valores existentes se disponíveis
    if (_cartoesValorBrutoRedeController!.text.isEmpty && _cartoesValorBrutoRede != null) {
      _cartoesValorBrutoRedeController!.text = _cartoesValorBrutoRede.toString();
    }
    if (_cartoesPixRedeController!.text.isEmpty && _cartoesPixRede != null) {
      _cartoesPixRedeController!.text = _cartoesPixRede.toString();
    }
    if (_cartoesValorBrutoController!.text.isEmpty && _cartoesValorBruto != null) {
      _cartoesValorBrutoController!.text = _cartoesValorBruto.toString();
    }
    if (_cartoesPixController!.text.isEmpty && _cartoesPix != null) {
      _cartoesPixController!.text = _cartoesPix.toString();
    }

    double valorBrutoRede = _cartoesValorBrutoRede ?? 0.0;
    double pixRede = _cartoesPixRede ?? 0.0;
    double valorBruto = _cartoesValorBruto ?? 0.0;
    double pix = _cartoesPix ?? 0.0;
    double total = _cartoesTotal ?? 0.0;
    double totalCartoes = 0.0; // Total de cartões (POS + TEF)
    double diferenca = 0.0;
    String filial = _selectedSubMenu.isNotEmpty ? _selectedSubMenu : filiais.first;
    bool cartoesExportado = false;

    Future<double> _fetchTotalCartoes(String filial) async {
      try {
        // Buscar total de cartões POS e TEF da filial apenas do mês atual
        final relatorios = _relatoriosPorFilial[filial] ?? [];
        double totalPos = 0.0;
        double totalTef = 0.0;
        double totalAtm = 0.0;
        final now = DateTime.now();
        final currentMonth = now.month;
        final currentYear = now.year;

        for (var relatorio in relatorios) {
          final data = relatorio['caixa_referente'];
          if (data != null && data.length >= 7) {
            try {
              final anoRelatorio = int.parse(data.substring(0, 4));
              final mesRelatorio = int.parse(data.substring(5, 7));

              // Só inclui se for do mês atual
              if (anoRelatorio == currentYear && mesRelatorio == currentMonth) {
                totalPos += _parseMoneyValue(relatorio['cartao_pos']);
                totalTef += _parseMoneyValue(relatorio['cartao_tef']);
                totalAtm += _parseMoneyValue(relatorio['atm']);
              }
            } catch (e) {
              // Ignora erros de parsing
            }
          }
        }

        return totalPos + totalTef + totalAtm;
      } catch (e) {
        print('Erro ao buscar total de cartões: $e');
        return 0.0;
      }
    }

    return StatefulBuilder(
      builder: (context, setState) {
        void calcularTotal() {
          valorBrutoRede = double.tryParse(_cartoesValorBrutoRedeController!.text.replaceAll(',', '.')) ?? 0.0;
          pixRede = double.tryParse(_cartoesPixRedeController!.text.replaceAll(',', '.')) ?? 0.0;
          valorBruto = double.tryParse(_cartoesValorBrutoController!.text.replaceAll(',', '.')) ?? 0.0;
          pix = double.tryParse(_cartoesPixController!.text.replaceAll(',', '.')) ?? 0.0;
          this.total = valorBrutoRede + pixRede + valorBruto + pix;
          this.diferenca = this.totalCartoes > 0 ? this.total - this.totalCartoes : 0.0;

          // Atualizar variáveis de estado persistentes
          _cartoesValorBrutoRede = valorBrutoRede;
          _cartoesPixRede = pixRede;
          _cartoesValorBruto = valorBruto;
          _cartoesPix = pix;
          _cartoesTotal = this.total;

          setState(() {});
        }

        void exportarCartoes() async {
          _showMesExportacaoCartoes(filial);
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cartões', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    onPressed: () => _showHistoricoTaxas('Cartões'),
                    icon: const Icon(Icons.history),
                    label: const Text('Histórico'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Card único para todos os valores
                                  Container(
                padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey[800] 
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[600]! 
                        : Colors.grey[300]!,
                  ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                    const Text(
                      'Valores e Totais',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    
                    // Seção Rede
                    const Text(
                      'Valores Rede',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
              TextField(
                controller: _cartoesValorBrutoRedeController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Valor Bruto Rede',
                  prefixIcon: Icon(Icons.credit_card),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => calcularTotal(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cartoesPixRedeController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'PIX Rede',
                  prefixIcon: Icon(Icons.pix),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => calcularTotal(),
              ),
                    
                    const SizedBox(height: 20),
                    
                    // Seção SIPAG
                    const Text(
                      'Valores SIPAG',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
              TextField(
                controller: _cartoesValorBrutoController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Valor Bruto SIPAG',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => calcularTotal(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cartoesPixController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'PIX SIPAG',
                  prefixIcon: Icon(Icons.pix),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => calcularTotal(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
                                        Row(
                                          children: [
                  const Text('Total:', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                                            Text(
                    _currencyFormat.format(this.total),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (this.isEndOfMonth || this.cartoesExportado)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Total Cartões:', style: TextStyle(fontSize: 18)),
                                              const SizedBox(width: 8),
                        Text(
                          _currencyFormat.format(this.totalCartoes),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Diferença:', style: TextStyle(fontSize: 18, color: Colors.deepOrange)),
                        const SizedBox(width: 8),
                                            Text(
                          _currencyFormat.format(this.diferenca),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                        ),
                      ],
                                            ),
                                          ],
                                        ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: exportarCartoes,
                  icon: const Icon(Icons.upload),
                  label: const Text('Exportar Total Cartões'),
                ),
              ),
              const SizedBox(height: 32),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _cartoesValorBrutoRedeController!.clear();
                        _cartoesPixRedeController!.clear();
                        _cartoesValorBrutoController!.clear();
                        _cartoesPixController!.clear();
                        setState(() {
                          valorBrutoRede = 0.0;
                          pixRede = 0.0;
                          valorBruto = 0.0;
                          pix = 0.0;
                          this.total = 0.0;
                          this.totalCartoes = 0.0;
                          this.diferenca = 0.0;
                          this.cartoesExportado = false;

                          // Limpar também as variáveis de estado persistentes
                          _cartoesValorBrutoRede = 0.0;
                          _cartoesPixRede = 0.0;
                          _cartoesValorBruto = 0.0;
                          _cartoesPix = 0.0;
                          _cartoesTotal = 0.0;
                        });
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Limpar'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _salvarTaxaSipag(
                        valorBrutoRede,
                        pixRede,
                        valorBruto,
                        pix,
                        this.total,
                        filial,
                      ),
                      icon: const Icon(Icons.save),
                      label: const Text('Salvar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                                            ),
                                          ),
                                        ],
              ),
            ],
          ),
        );
      },
    );
  }

  // Função para construir a calculadora de Taxas (Rede + SIPAG)
  Widget _buildTaxasCalculator() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Text('Taxas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // TabBar para Rede e SIPAG
          TabBar(
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(
                icon: Icon(Icons.credit_card),
                text: 'Rede',
              ),
              Tab(
                icon: Icon(Icons.credit_card),
                text: 'SIPAG',
              ),
            ],
          ),
          // TabBarView
          Flexible(
            child: TabBarView(
              children: [
                // Aba Rede
                SingleChildScrollView(child: _buildRedeCalculator()),
                // Aba SIPAG
                SingleChildScrollView(child: _buildSipagTaxasCalculator()),
              ],
            ),
          ),
        ],
      ),
    );
  }
  // Calculadora Rede
  Widget _buildRedeCalculator() {
    // Usar variáveis de estado persistentes para evitar perda de dados
    if (_redeValorBrutoController == null) _redeValorBrutoController = TextEditingController();
    if (_redeValorLiquidoController == null) _redeValorLiquidoController = TextEditingController();
    if (_redeTaxaController == null) _redeTaxaController = TextEditingController();
    if (_despesasController == null) _despesasController = TextEditingController();

    // Inicializar os campos com valores existentes se disponíveis
    if (_redeValorBrutoController!.text.isEmpty && _redeValorBruto != null) {
      _redeValorBrutoController!.text = _redeValorBruto.toString();
    }
    if (_redeValorLiquidoController!.text.isEmpty && _redeValorLiquido != null) {
      _redeValorLiquidoController!.text = _redeValorLiquido.toString();
    }
    if (_redeTaxaController!.text.isEmpty && _redeTaxa != null) {
      _redeTaxaController!.text = _redeTaxa.toString();
    }

    double valorBruto = _redeValorBruto ?? 0.0;
    double valorLiquido = _redeValorLiquido ?? 0.0;
    double taxa = _redeTaxa ?? 0.0;
    double total = _redeTotal ?? 0.0;

    return StatefulBuilder(
      builder: (context, setState) {
        void calcularTotal() {
          valorBruto = double.tryParse(_redeValorBrutoController!.text.replaceAll(',', '.')) ?? 0.0;
          valorLiquido = double.tryParse(_redeValorLiquidoController!.text.replaceAll(',', '.')) ?? 0.0;
          taxa = double.tryParse(_redeTaxaController!.text.replaceAll(',', '.')) ?? 0.0;
          total = valorBruto - valorLiquido;

          // Atualizar variáveis de estado persistentes
          _redeValorBruto = valorBruto;
          _redeValorLiquido = valorLiquido;
          _redeTaxa = taxa;
          _redeTotal = total;

          setState(() {});
        }

        void calcularTaxaAutomatica() {
          valorBruto = double.tryParse(_redeValorBrutoController!.text.replaceAll(',', '.')) ?? 0.0;
          valorLiquido = double.tryParse(_redeValorLiquidoController!.text.replaceAll(',', '.')) ?? 0.0;
          if (valorBruto > 0 && valorLiquido > 0) {
            taxa = ((valorBruto - valorLiquido) / valorBruto) * 100;
            _redeTaxaController!.text = taxa.toStringAsFixed(2);
          }
          total = valorBruto - valorLiquido;

          // Atualizar variáveis de estado persistentes
          _redeValorBruto = valorBruto;
          _redeValorLiquido = valorLiquido;
          _redeTaxa = taxa;
          _redeTotal = total;

          setState(() {});
        }

        void calcularTaxaComDespesas() {
          double despesas = double.tryParse(_despesasController!.text.replaceAll(',', '.')) ?? 0.0;
          if (valorBruto > 0) {
            // Taxa com despesas = ((Valor Bruto - Valor Líquido - Despesas) / Valor Bruto) * 100
            // Mesma lógica da taxa normal, mas subtraindo as despesas
            _taxaComDespesasRede = ((valorBruto - (valorLiquido - despesas)) / valorBruto) * 100;
            _despesas = despesas;
          }
          setState(() {});
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                                          children: [
                  const Text('Rede', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _showHistoricoTaxas('Rede'),
                    icon: const Icon(Icons.history),
                    label: const Text('Histórico'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
                            // Card único para Valores e Taxa
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey[800] 
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[600]! 
                        : Colors.grey[300]!,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Valores e Taxa',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    
                    // Campo Valor Bruto
              TextField(
                controller: _redeValorBrutoController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                        labelText: 'Valor Bruto (R\$)',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => calcularTaxaAutomatica(),
              ),
              const SizedBox(height: 16),
                    
                    // Campo Valor Líquido
              TextField(
                controller: _redeValorLiquidoController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                        labelText: 'Valor Líquido (R\$)',
                  prefixIcon: Icon(Icons.account_balance_wallet),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => calcularTaxaAutomatica(),
              ),
              const SizedBox(height: 16),
                    
                    // Campo Taxa (não editável)
                    Row(
                      children: [
                        const Text(
                          'Taxa: ',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                                            Text(
                          '${taxa.toStringAsFixed(2)}%',
                                              style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text(
                    _currencyFormat.format(total),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Seção de Despesas
                                  Container(
                padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey[800] 
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[600]! 
                        : Colors.grey[300]!,
                  ),
                                    ),
                                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                    const Text(
                      'Despesas',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _despesasController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Valor das Despesas',
                        prefixIcon: Icon(Icons.money_off),
                        border: OutlineInputBorder(),
                        hintText: '0,00',
                      ),
                      onChanged: (_) => calcularTaxaComDespesas(),
                    ),
                    const SizedBox(height: 16),
                                        Row(
                                          children: [
                        const Text('Taxa com Despesas:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                                            Text(
                          '${_taxaComDespesasRede?.toStringAsFixed(2) ?? '0.00'}%',
                                              style: TextStyle(
                            fontSize: 18,
                                                fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Botões em layout responsivo
              Column(
                children: [
                  // Primeira linha de botões
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _redeValorBrutoController!.clear();
                            _redeValorLiquidoController!.clear();
                            _redeTaxaController!.clear();
                            _despesasController!.clear();
                            setState(() {
                              valorBruto = 0.0;
                              valorLiquido = 0.0;
                              total = 0.0;
                              taxa = 0.0;

                              // Limpar também as variáveis de estado persistentes
                              _redeValorBruto = 0.0;
                              _redeValorLiquido = 0.0;
                              _redeTaxa = 0.0;
                              _redeTotal = 0.0;
                              _despesas = 0.0;
                              _taxaComDespesasRede = 0.0;
                            });
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text('Limpar'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                        ),
                      ),

                    ],
                  ),
                  const SizedBox(height: 12),
                  // Segunda linha - botão Salvar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _salvarTaxa('Rede', valorBruto, valorLiquido, taxa, total);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Taxa salva com sucesso!')),
                        );
                        // Não limpa os campos após salvar - mantém os valores para referência
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Salvar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // Calculadora SIPAG para Taxas
  Widget _buildSipagTaxasCalculator() {
    // Usar variáveis de estado persistentes para evitar perda de dados
    if (_sipagValorBrutoController == null) _sipagValorBrutoController = TextEditingController();
    if (_sipagValorLiquidoController == null) _sipagValorLiquidoController = TextEditingController();
    if (_sipagTaxaController == null) _sipagTaxaController = TextEditingController();
    if (_despesasController == null) _despesasController = TextEditingController();

    // Inicializar os campos com valores existentes se disponíveis
    if (_sipagValorBrutoController!.text.isEmpty && _sipagValorBruto != null) {
      _sipagValorBrutoController!.text = _sipagValorBruto.toString();
    }
    if (_sipagValorLiquidoController!.text.isEmpty && _sipagValorLiquido != null) {
      _sipagValorLiquidoController!.text = _sipagValorLiquido.toString();
    }
    if (_sipagTaxaController!.text.isEmpty && _sipagTaxa != null) {
      _sipagTaxaController!.text = _sipagTaxa.toString();
    }

    double valorBruto = _sipagValorBruto ?? 0.0;
    double valorLiquido = _sipagValorLiquido ?? 0.0;
    double taxa = _sipagTaxa ?? 0.0;
    double total = _sipagTotal ?? 0.0;

    return StatefulBuilder(
      builder: (context, setState) {
        void calcularTotal() {
          valorBruto = double.tryParse(_sipagValorBrutoController!.text.replaceAll(',', '.')) ?? 0.0;
          valorLiquido = double.tryParse(_sipagValorLiquidoController!.text.replaceAll(',', '.')) ?? 0.0;
          taxa = double.tryParse(_sipagTaxaController!.text.replaceAll(',', '.')) ?? 0.0;
          total = valorBruto - valorLiquido;

          // Atualizar variáveis de estado persistentes
          _sipagValorBruto = valorBruto;
          _sipagValorLiquido = valorLiquido;
          _sipagTaxa = taxa;
          _sipagTotal = total;

          setState(() {});
        }

        void calcularTaxaAutomatica() {
          valorBruto = double.tryParse(_sipagValorBrutoController!.text.replaceAll(',', '.')) ?? 0.0;
          valorLiquido = double.tryParse(_sipagValorLiquidoController!.text.replaceAll(',', '.')) ?? 0.0;
          if (valorBruto > 0 && valorLiquido > 0) {
            taxa = ((valorBruto - valorLiquido) / valorBruto) * 100;
            _sipagTaxaController!.text = taxa.toStringAsFixed(2);
          }
          total = valorBruto - valorLiquido;

          // Atualizar variáveis de estado persistentes
          _sipagValorBruto = valorBruto;
          _sipagValorLiquido = valorLiquido;
          _sipagTaxa = taxa;
          _sipagTotal = total;

          setState(() {});
        }

        void calcularTaxaComDespesas() {
          double despesas = double.tryParse(_despesasController!.text.replaceAll(',', '.')) ?? 0.0;
          if (valorBruto > 0) {
            // Taxa com despesas = ((Valor Bruto - Valor Líquido - Despesas) / Valor Bruto) * 100
            // Mesma lógica da taxa normal, mas subtraindo as despesas
            _taxaComDespesasSipag = ((valorBruto - (valorLiquido - despesas)) / valorBruto) * 100;
            _despesas = despesas;
          }
          setState(() {});
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('SIPAG', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                            const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () => _showHistoricoTaxas('SIPAG'),
                      icon: const Icon(Icons.history),
                      label: const Text('Histórico'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Card único para Valores e Taxa
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[800] 
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[600]! 
                          : Colors.grey[300]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Valores e Taxa',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      
                      // Campo Valor Bruto
                TextField(
                  controller: _sipagValorBrutoController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                          labelText: 'Valor Bruto (R\$)',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => calcularTaxaAutomatica(),
                ),
                const SizedBox(height: 16),
                      
                      // Campo Valor Líquido
                TextField(
                  controller: _sipagValorLiquidoController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                          labelText: 'Valor Líquido (R\$)',
                    prefixIcon: Icon(Icons.account_balance_wallet),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => calcularTaxaAutomatica(),
                ),
                const SizedBox(height: 16),
                      
                      // Campo Taxa (não editável)
                      Row(
                        children: [
                          const Text(
                            'Taxa: ',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                                            Text(
                            '${taxa.toStringAsFixed(2)}%',
                                              style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                                              ),
                                            ),
                                          ],
                                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                                        Text(
                      _currencyFormat.format(total),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Seção de Despesas
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[800] 
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[600]! 
                          : Colors.grey[300]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Despesas',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _despesasController,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Valor das Despesas',
                          prefixIcon: Icon(Icons.money_off),
                          border: OutlineInputBorder(),
                          hintText: '0,00',
                        ),
                        onChanged: (_) => calcularTaxaComDespesas(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                                          children: [
                          const Text('Taxa com Despesas:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                                            Text(
                            '${_taxaComDespesasSipag?.toStringAsFixed(2) ?? '0.00'}%',
                                              style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                const SizedBox(height: 32),
                // Botões em layout responsivo
                Column(
                  children: [
                    // Primeira linha de botões
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _sipagValorBrutoController!.clear();
                              _sipagValorLiquidoController!.clear();
                              _sipagTaxaController!.clear();
                              _despesasController!.clear();
                              setState(() {
                                valorBruto = 0.0;
                                valorLiquido = 0.0;
                                total = 0.0;
                                taxa = 0.0;

                                // Limpar também as variáveis de estado persistentes
                                _sipagValorBruto = 0.0;
                                _sipagValorLiquido = 0.0;
                                _sipagTaxa = 0.0;
                                _sipagTotal = 0.0;
                                _despesas = 0.0;
                                _taxaComDespesasSipag = 0.0;
                              });
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('Limpar'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                          ),
                        ),

                      ],
                    ),
                    const SizedBox(height: 12),
                    // Segunda linha - botão Salvar
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await _salvarTaxa('SIPAG', valorBruto, valorLiquido, taxa, total);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Taxa salva com sucesso!')),
                          );
                          // Não limpa os campos após salvar - mantém os valores para referência
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('Salvar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Função para exportar para Excel (todas as filiais)
  Future<void> _exportarExcelRelatorios() async {
    try {
      final excel = ex.Excel.createExcel();
      final ex.Sheet sheet = excel['Relatórios'];

      // Cabeçalho
      sheet.appendRow([
        ex.TextCellValue('Funcionário'),
        ex.TextCellValue('Filial'),
        ex.TextCellValue('Data'),
        ex.TextCellValue('Receita'),
        ex.TextCellValue('Dinheiro'),
        ex.TextCellValue('Depósito'),
        ex.TextCellValue('POS'),
        ex.TextCellValue('TEF'),
        ex.TextCellValue('Cobranças'),
        ex.TextCellValue('TEV/TED'),
        ex.TextCellValue('Total'),
      ]);

      // Dados
      print('=== DEBUG EXCEL ===');
      print('Filiais: $filiais');
      print('_relatoriosPorFilial keys: ${_relatoriosPorFilial.keys}');

      for (var filial in filiais) {
        final relatorios = _relatoriosPorFilial[filial] ?? [];
        print('Filial $filial: ${relatorios.length} relatórios');

        for (var r in relatorios) {
          final receita = _parseMoneyValue(r['receita_dia']);
          final dinheiro = _parseMoneyValue(r['dinheiro']);
          final deposito = _parseMoneyValue(r['deposito']);
          final cartaoPos = _parseMoneyValue(r['cartao_pos']);
          final cartaoTef = _parseMoneyValue(r['cartao_tef']);
          final cobrancas = _parseMoneyValue(r['cobrancas']);
          final tevTed = _parseMoneyValue(r['tev_ted']);
          final total = dinheiro + deposito + cartaoPos + cartaoTef + cobrancas + tevTed;
          sheet.appendRow([
            ex.TextCellValue(r['nome_funcionario'] ?? ''),
            ex.TextCellValue(r['filial'] ?? ''),
            ex.TextCellValue(r['caixa_referente'] != null ? _toDDMMYYYY(r['caixa_referente']) : ''),
            ex.TextCellValue(receita.toStringAsFixed(2)),
            ex.TextCellValue(dinheiro.toStringAsFixed(2)),
            ex.TextCellValue(deposito.toStringAsFixed(2)),
            ex.TextCellValue(cartaoPos.toStringAsFixed(2)),
            ex.TextCellValue(cartaoTef.toStringAsFixed(2)),
            ex.TextCellValue(cobrancas.toStringAsFixed(2)),
            ex.TextCellValue(tevTed.toStringAsFixed(2)),
            ex.TextCellValue(total.toStringAsFixed(2)),
          ]);
        }
      }

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        try {
          final directory = await getApplicationDocumentsDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName = 'relatorios_$timestamp.xlsx';
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(fileBytes, flush: true);

          // No emulador, vai direto para compartilhamento
          try {
            await Share.shareXFiles([XFile(file.path)], text: 'Relatórios Excel');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Excel compartilhado com sucesso!'),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 3),
              ),
            );
          } catch (shareError) {
            print('Erro ao compartilhar: $shareError');
            // Se não conseguir compartilhar, tenta abrir (para dispositivo real)
            try {
              await OpenFile.open(file.path);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Excel exportado e aberto com sucesso!'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            } catch (e) {
              // Se não conseguir abrir, mostra o caminho
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Arquivo salvo em: ${file.path}'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
        } catch (e) {
          // Fallback para diretório temporário
          final tempDir = Directory.systemTemp;
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName = 'relatorios_$timestamp.xlsx';
          final file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(fileBytes, flush: true);

          // Tenta compartilhar mesmo no fallback
          try {
            await Share.shareXFiles([XFile(file.path)], text: 'Relatórios Excel');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Excel compartilhado com sucesso!'),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 3),
              ),
            );
          } catch (shareError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Arquivo salvo em: ${file.path}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } catch (e) {
      throw Exception('Erro ao gerar Excel: $e');
    }
  }

  // Função para criar linha livre no PDF - simétrica
  pw.Widget _buildPdfRow(String label, String value) {
    return pw.Container(
      width: double.infinity,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.normal),
            ),
          ),
          pw.Expanded(
            flex: 1,
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.normal),
              textAlign: pw.TextAlign.right,
                            ),
                          ),
                        ],
      ),
    );
  }



  // Função para exportar para Excel (filial específica)
  Future<void> _exportarExcelFilial(String filial) async {
    try {
      final excel = ex.Excel.createExcel();
      final ex.Sheet sheet = excel['Relatórios'];

      // Estilos
      final headerStyle = ex.CellStyle(
        backgroundColorHex: ex.ExcelColor.fromHexString('#444444'),
        fontColorHex: ex.ExcelColor.fromHexString('#FFFFFF'),
        bold: true,
        horizontalAlign: ex.HorizontalAlign.Center,
        verticalAlign: ex.VerticalAlign.Center,
      );
      final groupStyle = ex.CellStyle(
        backgroundColorHex: ex.ExcelColor.fromHexString('#888888'),
        fontColorHex: ex.ExcelColor.fromHexString('#FFFFFF'),
        bold: true,
        horizontalAlign: ex.HorizontalAlign.Center,
        verticalAlign: ex.VerticalAlign.Center,
      );
      final totalStyle = ex.CellStyle(
        backgroundColorHex: ex.ExcelColor.fromHexString('#DDDDDD'),
        fontColorHex: ex.ExcelColor.fromHexString('#000000'),
        bold: true,
        horizontalAlign: ex.HorizontalAlign.Right,
        verticalAlign: ex.VerticalAlign.Center,
      );
      final normalStyle = ex.CellStyle(
        horizontalAlign: ex.HorizontalAlign.Center,
        verticalAlign: ex.VerticalAlign.Center,
      );

      // Cabeçalho agrupado (2 linhas)
      // Primeira linha: agrupamentos
      sheet.appendRow([
        ex.TextCellValue('DIA'),
        ex.TextCellValue('FATURAMENTO'), ex.TextCellValue(''),
        ex.TextCellValue('DEPÃƒâ€œSITOS'), ex.TextCellValue(''),
        ex.TextCellValue('CARTÃƒâ€¢ES'), ex.TextCellValue(''),
        ex.TextCellValue('OUTROS'), ex.TextCellValue(''),
        ex.TextCellValue('TOTAL'),
        ex.TextCellValue('OBSERVAÃƒâ€¡ÃƒÆ’O'),
      ]);
      // Segunda linha: campos
      sheet.appendRow([
        ex.TextCellValue('Data'),
        ex.TextCellValue('Receita'),
        ex.TextCellValue('Dinheiro'),
        ex.TextCellValue('Depósito'),
        ex.TextCellValue('POS'),
        ex.TextCellValue('TEF'),
        ex.TextCellValue('Cobranças'),
        ex.TextCellValue('TEV/TED'),
        ex.TextCellValue('Total'),
        ex.TextCellValue('Observação'),
      ]);

      // Mesclar células para agrupamentos
      sheet.merge(ex.CellIndex.indexByString("A1"), ex.CellIndex.indexByString("A2")); // DIA
      sheet.merge(ex.CellIndex.indexByString("B1"), ex.CellIndex.indexByString("C1")); // FATURAMENTO
      sheet.merge(ex.CellIndex.indexByString("D1"), ex.CellIndex.indexByString("E1")); // DEPÃƒâ€œSITOS
      sheet.merge(ex.CellIndex.indexByString("F1"), ex.CellIndex.indexByString("G1")); // CARTÃƒâ€¢ES
      sheet.merge(ex.CellIndex.indexByString("H1"), ex.CellIndex.indexByString("I1")); // OUTROS
      // J1: TOTAL, K1: OBSERVAÃƒâ€¡ÃƒÆ’O (não mescla)

      // Aplicar estilos ao cabeçalho
      for (var col = 0; col <= 9; col++) {
        sheet.updateCell(ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0), sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).value, cellStyle: groupStyle);
        sheet.updateCell(ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1), sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1)).value, cellStyle: headerStyle);
      }

      // Dados
      final relatorios = _relatoriosPorFilial[filial] ?? [];
      // Mapear por dia
      Map<int, Map<String, dynamic>> relatoriosPorDia = {};
      for (var r in relatorios) {
        final data = r['caixa_referente'];
        if (data != null && data.length >= 10) {
          final dia = int.tryParse(data.substring(8, 10)) ?? 0;
          relatoriosPorDia[dia] = r;
        }
      }
      // Descobrir mês/ano
      int ano = DateTime.now().year;
      int mes = DateTime.now().month;
      if (relatorios.isNotEmpty) {
        final data = relatorios.first['caixa_referente'];
        if (data != null && data.length >= 7) {
          ano = int.tryParse(data.substring(0, 4)) ?? ano;
          mes = int.tryParse(data.substring(5, 7)) ?? mes;
        }
      }
      final diasNoMes = DateUtils.getDaysInMonth(ano, mes);
      double totalReceita = 0;
      double totalDinheiro = 0;
      double totalDeposito = 0;
      double totalPos = 0;
      double totalTef = 0;
      double totalCobrancas = 0;
      double totalTevTed = 0;
      double totalGeral = 0;
      for (int dia = 1; dia <= diasNoMes; dia++) {
        final r = relatoriosPorDia[dia];
        final dataStr = dia.toString().padLeft(2, '0') + '/' + mes.toString().padLeft(2, '0') + '/' + ano.toString();
        final receita = r != null ? _parseMoneyValue(r['receita_dia']) : 0.0;
        final dinheiro = r != null ? _parseMoneyValue(r['dinheiro']) : 0.0;
        final deposito = r != null ? _parseMoneyValue(r['deposito']) : 0.0;
        final cartaoPos = r != null ? _parseMoneyValue(r['cartao_pos']) : 0.0;
        final cartaoTef = r != null ? _parseMoneyValue(r['cartao_tef']) : 0.0;
        final cobranca = r != null ? _parseMoneyValue(r['cobrancas']) : 0.0;
        final tevTed = r != null ? _parseMoneyValue(r['tev_ted']) : 0.0;
        final total = receita + dinheiro + deposito + cartaoPos + cartaoTef + cobranca + tevTed;
        totalReceita += receita;
        totalDinheiro += dinheiro;
        totalDeposito += deposito;
        totalPos += cartaoPos;
        totalTef += cartaoTef;
        totalCobrancas += cobranca;
        totalTevTed += tevTed;
        totalGeral += total;
        final observacao = r != null ? (r['observacoes'] ?? '') : '';
        sheet.appendRow([
          ex.TextCellValue(dataStr),
          ex.DoubleCellValue(receita),
          ex.DoubleCellValue(dinheiro),
          ex.DoubleCellValue(deposito),
          ex.DoubleCellValue(cartaoPos),
          ex.DoubleCellValue(cartaoTef),
          ex.DoubleCellValue(cobranca),
          ex.DoubleCellValue(tevTed),
          ex.DoubleCellValue(total),
          ex.TextCellValue(observacao)
        ]);
        // Aplicar estilo normal
        for (var col = 0; col <= 9; col++) {
          sheet.updateCell(ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1), sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1)).value, cellStyle: normalStyle);
        }
      }

      // Linha de totais
      sheet.appendRow([
        ex.TextCellValue('TOTAIS'),
        ex.DoubleCellValue(totalReceita),
        ex.DoubleCellValue(totalDinheiro),
        ex.DoubleCellValue(totalDeposito),
        ex.DoubleCellValue(totalPos),
        ex.DoubleCellValue(totalTef),
        ex.DoubleCellValue(totalCobrancas),
        ex.DoubleCellValue(totalTevTed),
        ex.DoubleCellValue(totalGeral),
        ex.TextCellValue('')
      ]);
      for (var col = 0; col <= 9; col++) {
        sheet.updateCell(ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1), sheet.cell(ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sheet.maxRows - 1)).value, cellStyle: totalStyle);
      }

      // Ajustar largura das colunas principais
      // sheet.setColWidth(0, 14); // Data
      // sheet.setColWidth(1, 16); // Receita
      // sheet.setColWidth(2, 16); // Dinheiro
      // sheet.setColWidth(3, 16); // Depósito
      // sheet.setColWidth(4, 16); // POS
      // sheet.setColWidth(5, 16); // TEF
      // sheet.setColWidth(6, 16); // Cobranças
      // sheet.setColWidth(7, 16); // TEV/TED
      // sheet.setColWidth(8, 16); // Total
      // sheet.setColWidth(9, 32); // Observação

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        try {
          final directory = await getApplicationDocumentsDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName = 'relatorios_${filial}_$timestamp.xlsx';
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(fileBytes, flush: true);

          // Compartilhar ou abrir
          try {
            await Share.shareXFiles([XFile(file.path)], text: 'Relatórios Excel');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Excel compartilhado com sucesso!'),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 3),
              ),
            );
          } catch (shareError) {
            try {
              await OpenFile.open(file.path);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Excel exportado e aberto com sucesso!'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Arquivo salvo em: ${file.path}'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
        } catch (e) {
          final tempDir = Directory.systemTemp;
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName = 'relatorios_${filial}_$timestamp.xlsx';
          final file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(fileBytes, flush: true);
          try {
            await Share.shareXFiles([XFile(file.path)], text: 'Relatórios Excel');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Excel compartilhado com sucesso!'),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 3),
              ),
            );
          } catch (shareError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Arquivo salvo em: ${file.path}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } catch (e) {
      throw Exception('Erro ao gerar Excel: $e');
    }
  }

  // Função para salvar taxa SIPAG no histórico
  Future<void> _salvarTaxaSipag(
      double valorBrutoRede,
      double pixRede,
      double valorBruto,
      double pix,
      double total,
      String filial,
      ) async {
    try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro: Usuário não está logado')),
        );
        return;
      }

      // Mostrar seletor de mês primeiro
      final DateTime? selectedMonth = await showDialog<DateTime>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Selecionar Mês para Salvar Cartões'),
          content: Container(
            width: 350,
            height: 500,
            child: Column(
              children: [
                const Text('Escolha o mês e ano para salvar os cartões:'),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: 24, // 2 anos (atual + anterior)
                    itemBuilder: (context, index) {
                      final year = DateTime.now().year - (index ~/ 12);
                      final month = (index % 12) + 1;
                      final monthName = _getMonthName(month);
                      return ListTile(
                        title: Text('$monthName/$year'),
                        subtitle: Text(year == DateTime.now().year ? 'Ano atual' : 'Ano anterior'),
                        onTap: () {
                          Navigator.pop(context, DateTime(year, month, 1));
                    },
                  );
                },
              ),
            ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

      if (selectedMonth == null) return;

      // Salvar com a data do mês selecionado
      final dataParaSalvar = DateTime(selectedMonth.year, selectedMonth.month, 15, 12, 0, 0); // Meio do mês

      await Supabase.instance.client.from('historico_taxas').insert({
        'user_id': userId,
        'tipo': 'sipag',
        'valor_bruto': valorBrutoRede,
        'valor_liquido': pixRede,
        'taxa': valorBruto,
        'total': total,
        'filial': filial,
        'created_at': dataParaSalvar.toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cartões salvos com sucesso em ${_getMonthName(selectedMonth.month)}/${selectedMonth.year}!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar cartões: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Função para salvar taxa no histórico
  Future<void> _salvarTaxa(String tipo, double valorBruto, double valorLiquido, double taxa, double total) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Mostrar seletor de mês primeiro
      final DateTime? selectedMonth = await showDialog<DateTime>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Selecionar Mês para Salvar Taxa $tipo'),
          content: Container(
            width: 350,
            height: 500,
            child: Column(
              children: [
                const Text('Escolha o mês e ano para salvar a taxa:'),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: 24, // 2 anos (atual + anterior)
                    itemBuilder: (context, index) {
                      final year = DateTime.now().year - (index ~/ 12);
                      final month = (index % 12) + 1;
                      final monthName = _getMonthName(month);
                      return ListTile(
                        title: Text('$monthName/$year'),
                        subtitle: Text(year == DateTime.now().year ? 'Ano atual' : 'Ano anterior'),
                        onTap: () {
                          Navigator.pop(context, DateTime(year, month, 1));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

      if (selectedMonth == null) return;

      // Salvar com a data do mês selecionado
      final dataParaSalvar = DateTime(selectedMonth.year, selectedMonth.month, 15, 12, 0, 0); // Meio do mês

      await Supabase.instance.client
          .from('historico_taxas')
          .insert({
        'user_id': userId,
        'tipo': tipo, // 'Rede' ou 'SIPAG'
        'valor_bruto': valorBruto,
        'valor_liquido': valorLiquido,
        'taxa': taxa,
        'total': total,
        'filial': _selectedSubMenu.isNotEmpty ? _selectedSubMenu : '',
        'created_at': dataParaSalvar.toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Taxa $tipo salva no histórico de ${_getMonthName(selectedMonth.month)}/${selectedMonth.year}!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      print('Erro ao salvar taxa: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar taxa: $error')),
      );
    }
  }

  // Função para limpar comprovantes corrompidos
  Future<void> _limparComprovantesCorrompidos() async {
    try {
      final relatorios = _relatoriosPorFilial[_selectedSubMenu] ?? [];
      if (relatorios.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum relatório encontrado')),
        );
        return;
      }

      int relatoriosCorrigidos = 0;
      int comprovantesCorrigidos = 0;

      for (var relatorio in relatorios) {
        bool relatorioModificado = false;
        Map<String, dynamic> dadosAtualizados = {};

        for (var tipo in [
          'comprovante_receita',
          'comprovante_dinheiro',
          'comprovante_deposito',
          'comprovante_cartao_pos',
          'comprovante_cartao_tef',
          'comprovante_cobrancas',
          'comprovante_tev_ted',
        ]) {
          final dadosOriginais = relatorio[tipo];
          if (dadosOriginais != null && dadosOriginais.toString().isNotEmpty) {
            final urlsParseadas = _parseComprovantesUrlsGerente(dadosOriginais);

            // Filtra apenas URLs válidas
            final urlsValidas = urlsParseadas.where((url) => _isValidUrlGerente(url)).toList();

            if (urlsValidas.isNotEmpty) {
              dadosAtualizados[tipo] = urlsValidas.join(',');
              comprovantesCorrigidos += urlsValidas.length;
              relatorioModificado = true;
            } else {
              // Se não conseguiu parsear URLs válidas, limpa o campo
              dadosAtualizados[tipo] = null;
              relatorioModificado = true;
            }
          }
        }

        // Atualiza o relatório no banco se foi modificado
        if (relatorioModificado) {
          try {
            await Supabase.instance.client
                .from('relatorios')
                .update(dadosAtualizados)
                .eq('id', relatorio['id']);

            relatoriosCorrigidos++;
          } catch (e) {
            print('Erro ao atualizar relatório ${relatorio['id']}: $e');
          }
        }
      }

      // Recarrega os relatórios
      await _fetchRelatorios();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Correção concluída! $relatoriosCorrigidos relatórios corrigidos, $comprovantesCorrigidos comprovantes processados'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao limpar comprovantes: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Função para testar comprovantes existentes
  Future<void> _testarComprovantesExistentes() async {
    try {
      print('DEBUG GERENTE: Iniciando _testarComprovantesExistentes');
      print('DEBUG GERENTE: Filial selecionada: $_selectedSubMenu');

      final relatorios = _relatoriosPorFilial[_selectedSubMenu] ?? [];
      print('DEBUG GERENTE: Total de relatórios encontrados: ${relatorios.length}');

      if (relatorios.isEmpty) {
        print('DEBUG GERENTE: Nenhum relatório encontrado');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nenhum relatório encontrado para testar')),
        );
        return;
      }

      // Pega o primeiro relatório que tenha comprovantes
      Map<String, dynamic>? relatorioComComprovantes;
      int relatorioIndex = 0;

      for (var relatorio in relatorios) {
        print('DEBUG GERENTE: Analisando relatório $relatorioIndex');
        print('DEBUG GERENTE: Data do relatório: ${relatorio['caixa_referente']}');

        for (var tipo in [
          'comprovante_receita',
          'comprovante_dinheiro',
          'comprovante_deposito',
          'comprovante_cartao_pos',
          'comprovante_cartao_tef',
          'comprovante_cobrancas',
          'comprovante_tev_ted',
        ]) {
          if (relatorio[tipo] != null && relatorio[tipo]
              .toString()
              .isNotEmpty) {
            print('DEBUG GERENTE: Encontrou comprovante do tipo $tipo no relatório $relatorioIndex');
            print('DEBUG GERENTE: Dados do comprovante: ${relatorio[tipo]}');
            relatorioComComprovantes = relatorio;
            break;
          }
        }
        if (relatorioComComprovantes != null) break;
        relatorioIndex++;
      }

      if (relatorioComComprovantes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nenhum relatório com comprovantes encontrado')),
        );
        return;
      }

      // Mostra os comprovantes do relatório encontrado
      _showComprovantesDialog(context, relatorioComComprovantes);

      // Mostra informações de debug
      showDialog(
        context: context,
        builder: (context) =>
            AlertDialog(
              title: const Text('Debug - Comprovantes'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                children: [
                    Text('Data: ${_toDDMMYYYY(
                        relatorioComComprovantes?['caixa_referente'] ??
                            '')}'),
                    Text(
                        'Funcionário: ${relatorioComComprovantes?['nome_funcionario'] ??
                            'N/A'}'),
                    const SizedBox(height: 16),
                    const Text('Comprovantes encontrados:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    for (var tipo in [
                      'comprovante_receita',
                      'comprovante_dinheiro',
                      'comprovante_deposito',
                      'comprovante_cartao_pos',
                      'comprovante_cartao_tef',
                      'comprovante_cobrancas',
                      'comprovante_tev_ted',
                    ])
                      if (relatorioComComprovantes?[tipo] != null &&
                          relatorioComComprovantes![tipo]
                              .toString()
                              .isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${tipo.replaceAll('comprovante_', '')}:',
                                style: const TextStyle(fontWeight: FontWeight
                                    .bold)),
                            Text(
                                'Dados brutos: ${relatorioComComprovantes![tipo]}'),
                            Text(
                                'URLs parseadas: ${_parseComprovantesUrlsGerente(
                                    relatorioComComprovantes![tipo])
                                    .length}'),
                            const SizedBox(height: 8),
                          ],
                        ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao testar comprovantes: $error')),
      );
    }
  }

  // Função para mostrar seleção de mês para exportar cartões
  Future<void> _showMesExportacaoCartoes(String filial) async {
    int selectedMonth = DateTime.now().month;
    int selectedYear = DateTime.now().year;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecionar Mês para Exportar Cartões'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: selectedMonth,
              decoration: const InputDecoration(labelText: 'Mês'),
              items: [
                {'value': 1, 'label': 'Janeiro'},
                {'value': 2, 'label': 'Fevereiro'},
                {'value': 3, 'label': 'Março'},
                {'value': 4, 'label': 'Abril'},
                {'value': 5, 'label': 'Maio'},
                {'value': 6, 'label': 'Junho'},
                {'value': 7, 'label': 'Julho'},
                {'value': 8, 'label': 'Agosto'},
                {'value': 9, 'label': 'Setembro'},
                {'value': 10, 'label': 'Outubro'},
                {'value': 11, 'label': 'Novembro'},
                {'value': 12, 'label': 'Dezembro'},
              ].map((item) => DropdownMenuItem(
                value: item['value'] as int,
                child: Text(item['label'] as String),
              )).toList(),
              onChanged: (value) {
                selectedMonth = value!;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: selectedYear,
              decoration: const InputDecoration(labelText: 'Ano'),
              items: [
                {'value': 2025, 'label': '2025'},
                {'value': 2026, 'label': '2026'},
              ].map((item) => DropdownMenuItem(
                value: item['value'] as int,
                child: Text(item['label'] as String),
              )).toList(),
              onChanged: (value) {
                selectedYear = value!;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _exportarCartoesMes(filial, selectedMonth, selectedYear);
            },
            child: const Text('Exportar'),
          ),
        ],
      ),
    );
  }

  // Função para exportar cartões do mês selecionado
  Future<void> _exportarCartoesMes(String filial, int mes, int ano) async {
    try {
      final totalCartoes = await _fetchTotalCartoesMes(filial, mes, ano);

      // Atualizar o estado da calculadora de cartões
      setState(() {
        // Atualizar as variáveis da calculadora
        this.totalCartoes = totalCartoes;
        this.diferenca = this.total - totalCartoes;
        this.cartoesExportado = true;
        print('DEBUG: totalCartoes = ${this.totalCartoes}');
        print('DEBUG: diferenca = ${this.diferenca}');
        print('DEBUG: cartoesExportado = ${this.cartoesExportado}');
        print('DEBUG: isEndOfMonth = ${this.isEndOfMonth}');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Total Cartões de ${_getMonthName(mes)}/$ano carregado!')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar cartões: $error')),
      );
    }
  }

  // Função para buscar total de cartões do mês selecionado
  Future<double> _fetchTotalCartoesMes(String filial, int mes, int ano) async {
    try {
      final startDate = DateTime(ano, mes, 1);
      final endDate = DateTime(ano, mes + 1, 0);

      final response = await Supabase.instance.client
          .from('relatorios')
          .select('cartao_pos, cartao_tef, atm')
          .eq('filial_id', filial)
          .gte('caixa_referente', startDate.toIso8601String())
          .lte('caixa_referente', endDate.toIso8601String());

      double total = 0.0;
      for (var relatorio in response) {
        total += _parseMoneyValue(relatorio['cartao_pos']) + _parseMoneyValue(relatorio['cartao_tef']) + _parseMoneyValue(relatorio['atm']);
      }
      return total;
    } catch (error) {
      print('Erro ao buscar total de cartões: $error');
      return 0.0;
    }
  }

  // Função para obter nome do mês
  String _getMonthName(int month) {
    const months = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    return months[month - 1];
  }

  // Função para mostrar histórico de taxas
  Future<void> _showHistoricoTaxas(String tipo) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Mostrar seletor de mês primeiro
      final DateTime? selectedMonth = await showDialog<DateTime>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Selecionar Mês - $tipo'),
          content: Container(
            width: 350,
            height: 500,
            child: Column(
              children: [
                const Text('Escolha o mês e ano para visualizar o histórico:'),
                const SizedBox(height: 20),
                  Expanded(
                  child: ListView.builder(
                    itemCount: 24, // 2 anos (atual + anterior)
                    itemBuilder: (context, index) {
                      final year = DateTime.now().year - (index ~/ 12);
                      final month = (index % 12) + 1;
                      final monthName = _getMonthName(month);
                      return ListTile(
                        title: Text('$monthName/$year'),
                        subtitle: Text(year == DateTime.now().year ? 'Ano atual' : 'Ano anterior'),
                        onTap: () {
                          Navigator.pop(context, DateTime(year, month, 1));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

      if (selectedMonth == null) return;

      // Buscar histórico filtrado por filial e mês
      final startDate = DateTime(selectedMonth.year, selectedMonth.month, 1);
      final endDate = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);

      final response = await Supabase.instance.client
          .from('historico_taxas')
          .select('*')
          .eq('tipo', tipo)
          .eq('user_id', userId)
          .eq('filial', _selectedSubMenu.isNotEmpty ? _selectedSubMenu : '') // Filtrar por filial
          .gte('created_at', startDate.toIso8601String())
          .lte('created_at', endDate.toIso8601String())
          .order('created_at', ascending: false)
          .limit(200);

      if (response.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nenhum histórico encontrado para $tipo em ${_getMonthName(selectedMonth.month)}/${selectedMonth.year}')),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) =>
            AlertDialog(
              title: Text('Histórico de Taxas - $tipo\n${_getMonthName(selectedMonth.month)}/${selectedMonth.year}'),
              content: Container(
                width: double.maxFinite,
                height: 600,
                child: Column(
                  children: [
                    // Cabeçalho com informações da filial
                  Container(
                      padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.business, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'Filial: ${_selectedSubMenu.isNotEmpty ? _selectedSubMenu : "Não selecionada"}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Lista de histórico
                    Expanded(
                      child: ListView.builder(
                        itemCount: response.length,
                        itemBuilder: (context, index) {
                          final item = response[index];
                          return ListTile(
                            title: Text('${_currencyFormat.format(item['total'])}'),
                            subtitle: Text(
                              'Bruto: ${_currencyFormat.format(
                                  item['valor_bruto'])} | '
                                  'Líquido: ${_currencyFormat.format(
                                  item['valor_liquido'])} | '
                                  'Taxa: ${item['taxa'].toStringAsFixed(2)}%',
                            ),
                            trailing: Text(
                              DateFormat('dd/MM/yyyy HH:mm').format(
                                  DateTime.parse(item['created_at'])),
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            ),
      );
    } catch (error) {
      print('Erro ao buscar histórico: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao buscar histórico: $error')),
      );
    }
  }
  // Função de exportação de Excel profissional usando Syncfusion
  Future<void> _exportarExcelFilialSyncfusion(String filial) async {
    final workbook = sfxlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Relatórios';

    try {
      // Cabeçalho duplo
      sheet.getRangeByName('A1').setText('DIA');
      sheet.getRangeByName('B1').setText('FATURAMENTO');
      sheet.getRangeByName('D1').setText('DEPÃƒâ€œSITOS');
      sheet.getRangeByName('F1').setText('CARTÃƒâ€¢ES');
      sheet.getRangeByName('H1').setText('OUTROS');
      sheet.getRangeByName('I1').setText('TOTAL');
      sheet.getRangeByName('J1').setText('OBSERVAÃƒâ€¡ÃƒÆ’O');

      // Mesclar agrupamentos
      sheet.getRangeByName('B1:C1').merge();
      sheet.getRangeByName('D1:E1').merge();
      sheet.getRangeByName('F1:G1').merge();
      sheet.getRangeByName('H1:I1').merge();
      sheet
          .getRangeByName('J1:J1')
          .merge(); // Observação não precisa mesclar, mas mantém consistência

      // Segunda linha: campos
      final campos = [
        'Data',
        'Receita',
        'Dinheiro',
        'Depósito',
        'POS',
        'TEF',
        'Cobranças',
        'TEV/TED',
        'Total',
        'Observação'
      ];
      for (int i = 0; i < campos.length; i++) {
        sheet.getRangeByIndex(2, i + 1).setText(campos[i]);
      }

      // Estilos do cabeçalho
      final headerStyle = workbook.styles.add('headerStyle');
      headerStyle.bold = true;
      headerStyle.backColor = '#222222'; // Preto/cinza escuro
      headerStyle.fontColor = '#FFFFFF';
      headerStyle.hAlign = sfxlsio.HAlignType.center;
      headerStyle.vAlign = sfxlsio.VAlignType.center;
      headerStyle.fontSize = 12;

      final groupStyle = workbook.styles.add('groupStyle');
      groupStyle.bold = true;
      groupStyle.backColor = '#222222'; // Preto/cinza escuro
      groupStyle.fontColor = '#FFFFFF';
      groupStyle.hAlign = sfxlsio.HAlignType.center;
      groupStyle.vAlign = sfxlsio.VAlignType.center;
      groupStyle.fontSize = 13;

      // Estilo dos totais
      final totalStyle = workbook.styles.add('totalStyle');
      totalStyle.bold = true;
      totalStyle.backColor = '#DDDDDD'; // Cinza claro
      totalStyle.fontColor = '#000000';
      totalStyle.hAlign = sfxlsio.HAlignType.right;
      totalStyle.vAlign = sfxlsio.VAlignType.center;
      totalStyle.fontSize = 12;

      // Estilo dos dados (direita)
      final rightStyle = workbook.styles.add('rightStyle');
      rightStyle.hAlign = sfxlsio.HAlignType.right;
      rightStyle.vAlign = sfxlsio.VAlignType.center;
      rightStyle.fontSize = 11;

      // Estilo para datas e observações (esquerda)
      final leftStyle = workbook.styles.add('leftStyle');
      leftStyle.hAlign = sfxlsio.HAlignType.left;
      leftStyle.vAlign = sfxlsio.VAlignType.center;
      leftStyle.fontSize = 11;

      // Aplicar estilos
      sheet
          .getRangeByName('A1:J1')
          .cellStyle = groupStyle;
      sheet
          .getRangeByName('A2:J2')
          .cellStyle = headerStyle;
      sheet
          .getRangeByName('A1:J1')
          .rowHeight = 28;
      sheet
          .getRangeByName('A2:J2')
          .rowHeight = 24;

      // Dados
      final relatorios = _relatoriosPorFilial[filial] ?? [];
      Map<int, Map<String, dynamic>> relatoriosPorDia = {};
      for (var r in relatorios) {
        final data = r['caixa_referente'];
        if (data != null && data.length >= 10) {
          final dia = int.tryParse(data.substring(8, 10)) ?? 0;
          relatoriosPorDia[dia] = r;
        }
      }
      int ano = DateTime
          .now()
          .year;
      int mes = DateTime
          .now()
          .month;
      if (relatorios.isNotEmpty) {
        final data = relatorios.first['caixa_referente'];
        if (data != null && data.length >= 7) {
          ano = int.tryParse(data.substring(0, 4)) ?? ano;
          mes = int.tryParse(data.substring(5, 7)) ?? mes;
        }
      }
      final diasNoMes = DateUtils.getDaysInMonth(ano, mes);
      double totalReceita = 0;
      double totalDinheiro = 0;
      double totalDeposito = 0;
      double totalPos = 0;
      double totalTef = 0;
      double totalCobrancas = 0;
      double totalTevTed = 0;
      double totalGeral = 0;
      for (int dia = 1; dia <= diasNoMes; dia++) {
        final r = relatoriosPorDia[dia];
        final dataStr = dia.toString().padLeft(2, '0') + '/' +
            mes.toString().padLeft(2, '0') + '/' + ano.toString();
        final receita = r != null ? _parseMoneyValue(r['receita_dia']) : 0.0;
        final dinheiro = r != null ? _parseMoneyValue(r['dinheiro']) : 0.0;
        final deposito = r != null ? _parseMoneyValue(r['deposito']) : 0.0;
        final cartaoPos = r != null ? _parseMoneyValue(r['cartao_pos']) : 0.0;
        final cartaoTef = r != null ? _parseMoneyValue(r['cartao_tef']) : 0.0;
        final cobranca = r != null ? _parseMoneyValue(r['cobrancas']) : 0.0;
        final tevTed = r != null ? _parseMoneyValue(r['tev_ted']) : 0.0;
        final total = receita + dinheiro + deposito + cartaoPos + cartaoTef +
            cobranca + tevTed;
        totalReceita += receita;
        totalDinheiro += dinheiro;
        totalDeposito += deposito;
        totalPos += cartaoPos;
        totalTef += cartaoTef;
        totalCobrancas += cobranca;
        totalTevTed += tevTed;
        totalGeral += total;
        final observacao = r != null ? (r['observacoes'] ?? '') : '';
        final row = 2 + dia;
        sheet.getRangeByIndex(row, 1).setText(dataStr);
        sheet
            .getRangeByIndex(row, 1)
            .cellStyle = leftStyle;
        sheet.getRangeByIndex(row, 2).setNumber(receita);
        sheet
            .getRangeByIndex(row, 2)
            .cellStyle = rightStyle;
        sheet.getRangeByIndex(row, 3).setNumber(dinheiro);
        sheet
            .getRangeByIndex(row, 3)
            .cellStyle = rightStyle;
        sheet.getRangeByIndex(row, 4).setNumber(deposito);
        sheet
            .getRangeByIndex(row, 4)
            .cellStyle = rightStyle;
        sheet.getRangeByIndex(row, 5).setNumber(cartaoPos);
        sheet
            .getRangeByIndex(row, 5)
            .cellStyle = rightStyle;
        sheet.getRangeByIndex(row, 6).setNumber(cartaoTef);
        sheet
            .getRangeByIndex(row, 6)
            .cellStyle = rightStyle;
        sheet.getRangeByIndex(row, 7).setNumber(cobranca);
        sheet
            .getRangeByIndex(row, 7)
            .cellStyle = rightStyle;
        sheet.getRangeByIndex(row, 8).setNumber(tevTed);
        sheet
            .getRangeByIndex(row, 8)
            .cellStyle = rightStyle;
        sheet.getRangeByIndex(row, 9).setNumber(total);
        sheet
            .getRangeByIndex(row, 9)
            .cellStyle = rightStyle;
        sheet.getRangeByIndex(row, 10).setText(observacao);
        sheet
            .getRangeByIndex(row, 10)
            .cellStyle = leftStyle;
        sheet
            .getRangeByIndex(row, 1, row, 10)
            .rowHeight = 22;
      }
      // Linha de totais
      final totalRow = 2 + diasNoMes + 1;
      sheet.getRangeByIndex(totalRow, 1).setText('TOTAIS');
      sheet
          .getRangeByIndex(totalRow, 1)
          .cellStyle = totalStyle;
      sheet.getRangeByIndex(totalRow, 2).setNumber(totalReceita);
      sheet
          .getRangeByIndex(totalRow, 2)
          .cellStyle = totalStyle;
      sheet.getRangeByIndex(totalRow, 3).setNumber(totalDinheiro);
      sheet
          .getRangeByIndex(totalRow, 3)
          .cellStyle = totalStyle;
      sheet.getRangeByIndex(totalRow, 4).setNumber(totalDeposito);
      sheet
          .getRangeByIndex(totalRow, 4)
          .cellStyle = totalStyle;
      sheet.getRangeByIndex(totalRow, 5).setNumber(totalPos);
      sheet
          .getRangeByIndex(totalRow, 5)
          .cellStyle = totalStyle;
      sheet.getRangeByIndex(totalRow, 6).setNumber(totalTef);
      sheet
          .getRangeByIndex(totalRow, 6)
          .cellStyle = totalStyle;
      sheet.getRangeByIndex(totalRow, 7).setNumber(totalCobrancas);
      sheet
          .getRangeByIndex(totalRow, 7)
          .cellStyle = totalStyle;
      sheet.getRangeByIndex(totalRow, 8).setNumber(totalTevTed);
      sheet
          .getRangeByIndex(totalRow, 8)
          .cellStyle = totalStyle;
      sheet.getRangeByIndex(totalRow, 9).setNumber(totalGeral);
      sheet
          .getRangeByIndex(totalRow, 9)
          .cellStyle = totalStyle;
      sheet.getRangeByIndex(totalRow, 10).setText('');
      sheet
          .getRangeByIndex(totalRow, 10)
          .cellStyle = totalStyle;
      sheet
          .getRangeByIndex(totalRow, 1, totalRow, 10)
          .rowHeight = 26;

      // Adicionar linhas extras para deixar quadrado
      int linhasExtras = 40 - (diasNoMes + 3); // 3 = cabeçalho + totais
      for (int i = 0; i < linhasExtras; i++) {
        final row = totalRow + 1 + i;
        for (int col = 1; col <= 10; col++) {
          sheet.getRangeByIndex(row, col).setText('');
          sheet
              .getRangeByIndex(row, col)
              .cellStyle = rightStyle;
          sheet
              .getRangeByIndex(row, col)
              .rowHeight = 22;
        }
      }

      // Ajustar largura das colunas (em caracteres aproximados)
      sheet
          .getRangeByIndex(1, 1)
          .columnWidth = 13; // Data
      sheet
          .getRangeByIndex(1, 2)
          .columnWidth = 16; // Receita
      sheet
          .getRangeByIndex(1, 3)
          .columnWidth = 16; // Dinheiro
      sheet
          .getRangeByIndex(1, 4)
          .columnWidth = 16; // Depósito
      sheet
          .getRangeByIndex(1, 5)
          .columnWidth = 16; // POS
      sheet
          .getRangeByIndex(1, 6)
          .columnWidth = 16; // TEF
      sheet
          .getRangeByIndex(1, 7)
          .columnWidth = 16; // Cobranças
      sheet
          .getRangeByIndex(1, 8)
          .columnWidth = 16; // TEV/TED
      sheet
          .getRangeByIndex(1, 9)
          .columnWidth = 18; // Total
      sheet
          .getRangeByIndex(1, 10)
          .columnWidth = 36; // Observação

      // Salvar arquivo
      File? file;
      try {
        final List<int> bytes = workbook.saveAsStream();
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime
            .now()
            .millisecondsSinceEpoch;
        final fileName = 'relatorios_${filial}_syncfusion_$timestamp.xlsx';
        file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        workbook.dispose();
      } catch (e) {
        workbook.dispose();
        throw Exception('Erro ao salvar Excel: $e');
      }

      // Abrir ou compartilhar
      if (file != null) {
        try {
          // Obter dados do usuário atual
          final user = Supabase.instance.client.auth.currentUser;
          final userResponse = await Supabase.instance.client
              .from('users')
              .select('nome, role, email')
              .eq('id', user?.id as Object)
              .maybeSingle();

          final nomeUsuario = userResponse?['nome'] ?? 'Usuário';
          final cargoUsuario = userResponse?['role'] ?? 'Funcionário';
          final emailUsuario = userResponse?['email'] ?? '';

          // Formatar mês/ano
          final mesAno = DateFormat('MMMM/yyyy', 'pt_BR').format(DateTime(ano, mes));

          // Criar mensagem personalizada
          final assunto = 'Relatório Financeiro Ã¢â‚¬â€œ $filial Ã¢â‚¬â€œ $mesAno';
          final corpo = '''Prezados,

Encaminho em anexo a planilha de Excel com o relatório financeiro referente à $filial, no período de $mesAno.

O documento contém os principais dados consolidados para análise.

Caso tenham dúvidas ou precisem de informações complementares, estou à disposição para esclarecimentos.

Atenciosamente,
$nomeUsuario
$cargoUsuario${emailUsuario.isNotEmpty ? '\n$emailUsuario' : ''}''';

          await Share.shareXFiles(
              [XFile(file.path)],
              text: corpo,
              subject: assunto
          );
        } catch (e) {
          await OpenFile.open(file.path);
        }
      }
    } catch (e) {
      workbook.dispose();
      throw Exception('Erro ao gerar Excel: $e');
    }
  }
}


// Nova tela da Calculadora SIPAG
class SipagCalculatorPage extends StatefulWidget {
  const SipagCalculatorPage({super.key});

  @override
  State<SipagCalculatorPage> createState() => _SipagCalculatorPageState();
}

class _SipagCalculatorPageState extends State<SipagCalculatorPage> {
  final TextEditingController _valorBrutoController = TextEditingController();
  final TextEditingController _pixController = TextEditingController();
  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  final List<String> filiais = [
    'B&B',
    'Foccus',
    'Buena',
    'Connect',
    'New World',
    'New Business',
    'JK',
    'BT',
  ];

  String _selectedFilial = '';
  double valorBruto = 0.0;
  double pix = 0.0;
  double total = 0.0;
  double totalTef = 0.0;
  double diferenca = 0.0;
  bool tefExportado = false;

  @override
  void initState() {
    super.initState();
    _selectedFilial = filiais.first;
  }

  Future<double> _fetchTotalTef(String filial) async {
    // Aqui você pode buscar do Supabase ou outra fonte
    await Future.delayed(const Duration(milliseconds: 300));
    return 12345.67; // Valor fictício
  }

  void calcularTotal() {
    valorBruto = double.tryParse(_valorBrutoController.text.replaceAll(',', '.')) ?? 0.0;
    pix = double.tryParse(_pixController.text.replaceAll(',', '.')) ?? 0.0;
    total = valorBruto + pix;
    diferenca = totalTef > 0 ? total - totalTef : 0.0;
    setState(() {});
  }

  void exportarTEF() async {
    totalTef = await _fetchTotalTef(_selectedFilial);
    diferenca = total - totalTef;
    tefExportado = true;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Total Cartão TEF exportado!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SIPAG'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seletor de Filial
            DropdownButtonFormField<String>(
              value: _selectedFilial,
              decoration: const InputDecoration(
                labelText: 'Filial',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
              items: filiais.map((filial) => DropdownMenuItem(
                value: filial,
                child: Text(filial),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedFilial = value!;
                  tefExportado = false;
                  totalTef = 0.0;
                  diferenca = 0.0;
                });
              },
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.03),
            TextField(
              controller: _valorBrutoController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor Bruto',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => calcularTotal(),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.02),
            TextField(
              controller: _pixController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'PIX',
                prefixIcon: Icon(Icons.pix),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => calcularTotal(),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.03),
            Row(
              children: [
                const Text('Total:', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  _currencyFormat.format(total),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.03),
            if (tefExportado)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Total Cartão TEF:', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(
                        _currencyFormat.format(totalTef),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ],
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  Row(
                    children: [
                      const Text('Diferença:', style: TextStyle(fontSize: 18, color: Colors.deepOrange)),
                      const SizedBox(width: 8),
                      Text(
                        _currencyFormat.format(diferenca),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                      ),
                    ],
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Cartão TEF disponível apenas no final do mês.', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: exportarTEF,
                      icon: const Icon(Icons.upload),
                      label: const Text('Exportar Total TEF'),
                    ),
                  ),
                ],
              ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.04),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _valorBrutoController.clear();
                      _pixController.clear();
                      setState(() {
                        valorBruto = 0.0;
                        pix = 0.0;
                        total = 0.0;
                        totalTef = 0.0;
                        diferenca = 0.0;
                        tefExportado = false;
                      });
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Limpar'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // TODO: Implementar salvamento para PDF
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Salvando dados...')),
                      );
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Salvar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  }


