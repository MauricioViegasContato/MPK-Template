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
import '../../manager/screens/gerente_page.dart'; // Just in case
import '../../../core/di/service_locator.dart'; // DI

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Controllers para o formulário
  final TextEditingController _saldoInicialController = TextEditingController();
  final TextEditingController _caixaReferenteController = TextEditingController();
  final TextEditingController _receitaDiaController = TextEditingController();
  final TextEditingController _dinheiroController = TextEditingController();
  final TextEditingController _depositoController = TextEditingController();
  final TextEditingController _cartaoTEFController = TextEditingController();
  final TextEditingController _atmController = TextEditingController();
  final TextEditingController _cartaoPOSController = TextEditingController();
  final TextEditingController _cobrancasController = TextEditingController();
  final TextEditingController _tevTedController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();

  // Controllers para o perfil
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _emailEmpresaController = TextEditingController();

  String _message = '';
  String? _filialId;
  String? _comprovanteReceitaUrl;
  String? _comprovanteDinheiroUrl;
  String? _comprovanteDepositoUrl;

  String? _comprovanteCartaoPOSUrl;
  String? _comprovanteCartaoTEFUrl;
  String? _comprovanteAtmUrl;
  String? _comprovanteCobrancasUrl;
  String? _comprovanteTevTedUrl;
  DateTime _selectedDate = DateTime.now();
  DateTime? _caixaReferenteDate; // Nova variável para a data do caixa referente
  Map<String, dynamic>? _existingReport;
  bool _depositoFeito = false;
  bool _isEditing = false; // Controla se está em modo de edição
  bool _isEdited = false; // Controla se o relatório foi editado

  // Variáveis para controlar mensagens de comprovante
  bool _showComprovanteReceita = false;
  bool _showComprovanteDinheiro = false;
  bool _showComprovanteDeposito = false;

  bool _showComprovanteCartaoPOS = false;
  bool _showComprovanteCartaoTEF = false;
  bool _showComprovanteCobrancas = false;
  bool _showComprovanteTevTed = false;

  // Variáveis para o perfil
  Map<String, dynamic>? _perfilFuncionario;
  bool _isEditingPerfil = false;
  bool _isEditedPerfil = false;

  // Sistema de travamento especial para filiais
  int? _tempoLimiteEnvio; // Vem da tabela users
  bool _isSistemaTravado = false;
  List<DateTime> _diasPendentes = [];

  // Sistema de Chat
  List<Map<String, dynamic>> _mensagens = [];
  TextEditingController _mensagemController = TextEditingController();
  bool _isEnviandoMensagem = false;
  Timer? _chatTimer; // Timer para atualização automática do chat

  // Sistema de Notificações
  Timer? _notificationTimer;
  bool _notificationsEnabled = true;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeApp();
    _initializeNotifications();
    _startNotificationTimer();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notificationTimer?.cancel();
    _chatTimer?.cancel();
    super.dispose();
  }

  // Função para parsear URLs de comprovantes (compatível com dados antigos e novos)
  List<String> _parseComprovantesUrls(dynamic comprovanteData) {
    if (comprovanteData == null || comprovanteData.toString().isEmpty) {
      return [];
    }

    String dataStr = comprovanteData.toString();
    print('DEBUG: Parseando comprovante - Dados originais: $dataStr');

    // Se já é uma lista (formato novo)
    if (dataStr.startsWith('[') && dataStr.endsWith(']')) {
      try {
        // Remove colchetes e aspas, depois divide por vírgula
        dataStr = dataStr.substring(1, dataStr.length - 1);
        final result = dataStr.split(',').map((url) => url.trim().replaceAll('"', '')).where((url) => url.isNotEmpty).toList();
        print('DEBUG: Parseado como lista - Resultado: $result');
        return result;
      } catch (e) {
        print('Erro ao parsear lista de comprovantes: $e');
        return [];
      }
    }

    // Se é string simples separada por vírgula (formato antigo)
    if (dataStr.contains(',')) {
      print('DEBUG: Encontrou vírgulas, analisando...');

      // Se contém vírgulas mas parece ser uma única URL (contém domínio), verifica múltiplas URLs
      if (dataStr.contains('supabase.co') || dataStr.contains('http')) {
        print('DEBUG: Contém domínio, verificando múltiplas URLs...');

        // PRIMEIRO: Verifica se é uma única URL com vírgulas no nome do arquivo
        // Mas só se não contiver múltiplas URLs completas separadas por vírgula
        bool hasMultipleCompleteUrls = false;
        List<String> possibleUrls = dataStr.split(',');
        int completeUrlCount = 0;

        for (String part in possibleUrls) {
          part = part.trim();
          if (part.isNotEmpty && _isValidUrl(part)) {
            completeUrlCount++;
          }
        }

        hasMultipleCompleteUrls = completeUrlCount > 1;
        print('DEBUG: URLs completas encontradas: $completeUrlCount');
        print('DEBUG: Tem múltiplas URLs completas: $hasMultipleCompleteUrls');

        // Se tem múltiplas URLs completas ou não é uma única URL válida, tenta dividir por vírgula
        dataStr.split(',');
        List<String> validUrls = [];

        print('DEBUG: Possíveis URLs encontradas: $possibleUrls');

        for (String part in possibleUrls) {
          part = part.trim();
          if (part.isNotEmpty && _isValidUrl(part)) {
            validUrls.add(part);
            print('DEBUG: URL válida encontrada: $part');
          } else {
            print('DEBUG: URL inválida ignorada: $part');
          }
        }

        print('DEBUG: Total de URLs válidas: ${validUrls.length}');

        // Se encontrou múltiplas URLs válidas, retorna todas
        if (validUrls.length > 1) {
          print('DEBUG: Retornando múltiplas URLs: $validUrls');
          print('DEBUG: ==========================================');
          print('DEBUG: RESULTADO FINAL (múltiplas URLs): $validUrls');
          print('DEBUG: QUANTIDADE: ${validUrls.length}');
          print('DEBUG: ==========================================');
          return validUrls;
        }

        // Se encontrou apenas uma URL válida, retorna ela
        if (validUrls.length == 1) {
          print('DEBUG: Retornando URL única válida: ${validUrls[0]}');
          print('DEBUG: ==========================================');
          print('DEBUG: RESULTADO FINAL (URL única válida): $validUrls');
          print('DEBUG: QUANTIDADE: ${validUrls.length}');
          print('DEBUG: ==========================================');
          return validUrls;
        }

        // Se não encontrou URLs válidas, trata como uma única URL
        print('DEBUG: Tratando como URL única');
        final result = [dataStr.trim()];
        print('DEBUG: ==========================================');
        print('DEBUG: RESULTADO FINAL (URL única fallback): $result');
        print('DEBUG: QUANTIDADE: ${result.length}');
        print('DEBUG: ==========================================');
        return result;
      }

      // Se não for uma URL válida, tenta dividir por vírgula de forma mais inteligente
      print('DEBUG: Tentando divisão inteligente por vírgula...');
      List<String> urls = [];
      List<String> parts = dataStr.split(',');

      for (int i = 0; i < parts.length; i++) {
        String part = parts[i].trim();
        if (part.isEmpty) continue;

        // Se a parte atual parece ser uma URL válida, adiciona
        if (_isValidUrl(part)) {
          urls.add(part);
          print('DEBUG: Adicionada URL válida: $part');
        } else {
          // Se não parece ser uma URL válida, tenta combinar com a próxima parte
          if (i + 1 < parts.length) {
            String combined = part + ',' + parts[i + 1].trim();
            if (_isValidUrl(combined)) {
              urls.add(combined);
              i++; // Pula a próxima parte já que foi combinada
              print('DEBUG: Adicionada URL combinada: $combined');
            } else {
              // Se ainda não é válida, adiciona como está (pode ser parte de uma URL)
              urls.add(part);
              print('DEBUG: Adicionada parte: $part');
            }
          } else {
            urls.add(part);
            print('DEBUG: Adicionada parte final: $part');
          }
        }
      }

      final result = urls.where((url) => url.isNotEmpty).toList();
      print('DEBUG: Resultado final da divisão inteligente: $result');
      print('DEBUG: ==========================================');
      print('DEBUG: RESULTADO FINAL (divisão inteligente): $result');
      print('DEBUG: QUANTIDADE: ${result.length}');
      print('DEBUG: ==========================================');
      return result;
    }

    // Se é uma única URL
    print('DEBUG: Tratando como URL única simples');
    final result = [dataStr.trim()];
    print('DEBUG: ==========================================');
    print('DEBUG: RESULTADO FINAL (URL única simples): $result');
    print('DEBUG: QUANTIDADE: ${result.length}');
    print('DEBUG: ==========================================');
    return result;
  }

  // Função auxiliar para verificar se uma string parece ser uma URL válida
  bool _isValidUrl(String url) {
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

  // CORREÃƒâ€¡ÃƒÆ’O: Adicionar função _parseMoneyValue que foi removida
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

  // Listas para múltiplos comprovantes
  List<String> _comprovanteReceitaUrls = [];
  List<String> _comprovanteDinheiroUrls = [];
  List<String> _comprovanteDepositoUrls = [];
  List<String> _comprovanteCartaoPOSUrls = [];
  List<String> _comprovanteCartaoTEFUrls = [];
  List<String> _comprovanteAtmUrls = [];
  List<String> _comprovanteCobrancasUrls = [];
  List<String> _comprovanteTevTedUrls = [];

  Future<void> _initializeApp() async {
    await _fetchFilialId();
    await _loadReportForDate(_selectedDate);
    await _loadSaldoInicial(_selectedDate);
    await _carregarPerfilFuncionario();
  }

  // =====================================================
  // SISTEMA DE NOTIFICAÃƒâ€¡Ãƒâ€¢ES
  // =====================================================

  // Inicializar plugin de notificações
  Future<void> _initializeNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Quando usuário toca na notificação
          print('Usuário tocou na notificação: ${response.payload}');
        },
      );
      
      // Criar canal de notificação para Android
      const androidChannel = AndroidNotificationChannel(
        'multipark_channel',
        'Multipark Notificações',
        description: 'Notificações importantes do sistema Multipark',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Colors.red,
      );
      
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
      
      print('Ã¢Å“â€¦ Sistema de notificações preparado!');
    } catch (e) {
      print('Ã¢ÂÅ’ Erro ao preparar notificações: $e');
    }
  }

  // Timer para verificar notificações a cada 30 segundos
  void _startNotificationTimer() {
    _notificationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_notificationsEnabled) {
        _checkForNotifications();
      }
    });
  }

  // Verificar se há notificações para mostrar
  Future<void> _checkForNotifications() async {
    try {
      // Verificar mensagens não lidas
      await _checkUnreadMessages();
      
      // Verificar relatórios pendentes
      await _checkPendingReports();
      
      // Verificar comprovantes pendentes
      await _checkPendingReceipts();
      
    } catch (e) {
      print('Erro ao verificar notificações: $e');
    }
  }

  // Verificar mensagens não lidas
  Future<void> _checkUnreadMessages() async {
    if (_filialId == null) return;
    
    try {
      final response = await Supabase.instance.client
          .from('mensagens_chat')
          .select('id')
          .or('and(tipo.eq.funcionario,filial_id.eq.$_filialId),and(tipo.eq.gerente,filial_id.is.null)')
          .not('id', 'in', '(SELECT mensagem_id FROM mensagens_visualizacoes WHERE filial_id = $_filialId)');
      
      final unreadCount = response.length;
      
      if (unreadCount > 0) {
        _showNotification(
          'Nova Mensagem',
          'Você tem $unreadCount mensagem${unreadCount > 1 ? 'ns' : ''} não lida${unreadCount > 1 ? 's' : ''}',
          'chat_notification',
        );
      }
    } catch (e) {
      print('Erro ao verificar mensagens não lidas: $e');
    }
  }

  // Verificar relatórios pendentes (incluindo finais de semana)
  Future<void> _checkPendingReports() async {
    try {
      final today = DateTime.now();
      
      // Verificar se há relatório do dia (incluindo finais de semana)
      final existingReport = await Supabase.instance.client
          .from('relatorios_diarios')
          .select('id')
          .eq('data', today.toIso8601String().split('T')[0])
          .eq('filial_id', _filialId!)
          .maybeSingle();
      
      if (existingReport == null) {
        final isWeekend = today.weekday == DateTime.saturday || today.weekday == DateTime.sunday;
        final diaSemana = isWeekend ? 'final de semana' : 'dia útil';
        
        _showNotification(
          'Relatório Pendente',
          'Relatório do $diaSemana (${formatarData(today)}) ainda não foi preenchido',
          'report_notification',
        );
        
        // Notificação mais urgente para finais de semana
        if (isWeekend) {
          _showNotification(
            'Ã¢Å¡Â Ã¯Â¸Â ATENÃƒâ€¡ÃƒÆ’O - Final de Semana',
            'Relatório do final de semana é OBRIGATÃƒâ€œRIO!',
            'urgent_notification',
          );
        }
      }
    } catch (e) {
      print('Erro ao verificar relatórios: $e');
    }
  }

  // Verificar comprovantes pendentes
  Future<void> _checkPendingReceipts() async {
    try {
      // Verificar se há valores sem comprovante
      final pendingReceipts = await Supabase.instance.client
          .from('relatorios_diarios')
          .select('*')
          .eq('data', DateTime.now().toIso8601String().split('T')[0])
          .eq('filial_id', _filialId!)
          .maybeSingle();
      
      if (pendingReceipts != null) {
        final fields = [
          'dinheiro', 'pix', 'cartao_credito', 'cartao_debito', 
          'elo', 'mastercard', 'visa', 'receita_total'
        ];
        
        for (final field in fields) {
          final value = pendingReceipts[field] ?? 0.0;
          if (value > 0 && (pendingReceipts['comprovante_$field'] == null || pendingReceipts['comprovante_$field'].toString().isEmpty)) {
            _showNotification(
              'Comprovante Pendente',
              'Comprovante obrigatório para $field (R\$ ${value.toStringAsFixed(2)})',
              'receipt_notification',
            );
            break; // Mostrar apenas uma notificação por vez
          }
        }
      }
    } catch (e) {
      print('Erro ao verificar comprovantes: $e');
    }
  }

  // Mostrar notificação real do sistema
  Future<void> _showNotification(String title, String body, String channelId) async {
    try {
      // Mostrar no console para debug
      print('Ã°Å¸â€â€ NOTIFICAÃƒâ€¡ÃƒÆ’O: $title - $body');
      
      // Mostrar notificação real do sistema
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'estacionamento_channel',
            'Notificações Estacionamento',
            channelDescription: 'Notificações do sistema',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
            enableVibration: true,
            playSound: true,
            icon: '@mipmap/ic_launcher',
            color: Colors.red,
            enableLights: true,
            ledColor: Colors.red,
          ),
                      iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
              sound: 'default',
              badgeNumber: 1,
            ),
        ),
      );
    } catch (e) {
      print('Erro ao mostrar notificação: $e');
    }
  }

  Future<void> _carregarPerfilFuncionario() async {
    try {
      // Usar mock ou real
      // final userId = Supabase.instance.client.auth.currentUser?.id;
      final userId = 'user_dummy_id';

      final response = await ServiceLocator.repository.getPerfil(userId);

      setState(() {
        _perfilFuncionario = response;
        _nomeController.text = response?['nome'] ?? '';
        _emailEmpresaController.text = response?['email_empresa'] ?? '';
      });
    } catch (error) {
      print('Perfil não encontrado ou erro ao carregar: $error');
      // Perfil não existe ainda, será criado quando necessário
    }
  }

  Future<void> _salvarPerfil() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Validar campos obrigatórios
      if (_nomeController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nome é obrigatório'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (_perfilFuncionario == null) {
        // Criar novo perfil
        await Supabase.instance.client
            .from('funcionarios_perfil')
            .insert({
          'user_id': userId,
          'nome': _nomeController.text.trim(),
          'email_empresa': _emailEmpresaController.text.trim(),
          'filial': _filialId ?? '',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      } else {
        // Atualizar perfil existente
        await Supabase.instance.client
            .from('funcionarios_perfil')
            .update({
          'nome': _nomeController.text.trim(),
          'email_empresa': _emailEmpresaController.text.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
            .eq('id', _perfilFuncionario!['id']);
      }

      // Recarregar perfil para atualizar estado
      await _carregarPerfilFuncionario();

      setState(() {
        _isEditingPerfil = false;
        _isEditedPerfil = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil salvo com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );

      // Notificar sucesso
      _showNotification(
        'Perfil Atualizado',
        'Seu perfil foi atualizado com sucesso',
        'profile_notification',
      );

    } catch (error) {
      print('Erro ao salvar perfil: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar perfil: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _solicitarAcessoPerfil() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Buscar nome do funcionário
      final userResponse = await Supabase.instance.client
          .from('users')
          .select('nome')
          .eq('id', userId)
          .single();

      await Supabase.instance.client
          .from('solicitacoes_perfil')
          .insert({
        'user_id': userId,
        'funcionario_id': _perfilFuncionario?['id'],
        'tipo_solicitacao': _perfilFuncionario == null ? 'criar' : 'editar',
        'dados_solicitados': {
          'nome': _nomeController.text,
          'email_empresa': _emailEmpresaController.text,
        },
        'status': 'pendente',
        'nome_funcionario': userResponse['nome'] ?? 'N/A',
      });

      setState(() {
        _isEditedPerfil = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitação de acesso enviada! Aguardando aprovação do gerente.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar solicitação: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchFilialId() async {
    try {
      // Usar mock ou real via Service Locator
      // final userId = Supabase.instance.client.auth.currentUser?.id; // Mock repositório pode não precisar de ID real se for mock
      final userId = 'user_id_placeholder'; 
      
      final filialId = await ServiceLocator.repository.getFilialId(userId);

      setState(() {
        _filialId = filialId;
        if (_filialId == null) {
          _message = 'Erro: Filial não encontrada para este usuário.';
        }
      });
    } catch (error) {
      setState(() {
        _message = 'Erro: $error';
      });
    }
  }

  String _toDDMMYYYY(String dateStrYYYYMMDD) {
    if (dateStrYYYYMMDD.isEmpty) {
      return ''; // Retorna vazio se a string de entrada estiver vazia
    }
    try {
      // Tenta fazer o parse da data no formato YYYY-MM-DD
      // Se sua string já estiver consistentemente como YYYY-MM-DD, DateTime.parse funciona.
      // Se puder ter outros formatos ou apenas YYYYMMDD (sem hífens), ajuste o parse.
      final DateTime dateTime = DateTime.parse(dateStrYYYYMMDD);
      // Formata para DD/MM/YYYY
      return "${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}";
    } catch (e) {
      // Se houver erro no parse (formato inesperado), retorna a string original ou uma string de erro
      print("Erro ao converter data para DD/MM/YYYY: $e, Data original: $dateStrYYYYMMDD");
      // Você pode querer retornar a string original ou um formato padrão em caso de erro.
      // Se a data do banco puder vir em formatos diferentes, você precisará de uma lógica de parse mais robusta.
      // Por exemplo, se vier como 'YYYYMMDD' (sem hífens):
      if (dateStrYYYYMMDD.length == 8 && int.tryParse(dateStrYYYYMMDD) != null) {
        final year = dateStrYYYYMMDD.substring(0, 4);
        final month = dateStrYYYYMMDD.substring(4, 6);
        final day = dateStrYYYYMMDD.substring(6, 8);
        return "$day/$month/$year";
      }
      return dateStrYYYYMMDD; // Ou return ''; como fallback
    }
  }

  Future<void> _loadReportForDate(DateTime date) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      String caixaRef = formatDateToYYYYMMDD(date);
      print('DEBUG _loadReportForDate: Buscando relatório para: user_id=' + userId + ', filial_id=' + (_filialId ?? '') + ', caixa_referente=' + caixaRef);

      // Busca apenas pelo caixa_referente (YYYY-MM-DD)
      // MODO MOCK / SERVICE LAYER
      // var response = await Supabase.instance.client...
      
      var response = await ServiceLocator.repository.getRelatorioDiario(
          userId, 
          _filialId ?? 'filial_mock', 
          caixaRef
      );

      print('DEBUG _loadReportForDate: Resultado da busca: ' + response.toString());

      setState(() {
        _existingReport = response;
        _isEditing = false;
        if (response != null) {
          _receitaDiaController.text = response['receita_dia']?.toString() ?? '';
          _saldoInicialController.text = response['saldo_inicial']?.toString() ?? '';
          if (response['caixa_referente'] != null) {
            _caixaReferenteController.text = _toDDMMYYYY(response['caixa_referente'].toString());
          }

          // Carrega a data do caixa referente se existir
          print('DEBUG _loadReportForDate: caixa_referente do banco: ${response['caixa_referente']}');
          if (response['caixa_referente'] != null) {
            try {
              final caixaRef = response['caixa_referente'].toString();
              print('DEBUG _loadReportForDate: caixaRef string: $caixaRef, length: ${caixaRef.length}');

              // Tenta primeiro o formato YYYY-MM-DD
              if (caixaRef.contains('-') && caixaRef.length == 10) {
                _caixaReferenteDate = DateTime.parse(caixaRef);
                print('DEBUG _loadReportForDate: Parseado como YYYY-MM-DD: $_caixaReferenteDate');
              }
              // Tenta o formato DDMMYYYY (8 dígitos)
              else if (caixaRef.length == 8 && int.tryParse(caixaRef) != null) {
                final day = int.parse(caixaRef.substring(0, 2));
                final month = int.parse(caixaRef.substring(2, 4));
                final year = int.parse(caixaRef.substring(4, 8));
                _caixaReferenteDate = DateTime(year, month, day);
                print('DEBUG _loadReportForDate: Parseado como DDMMYYYY: $_caixaReferenteDate');
              }
              // Se não conseguir parsear, mantém null
              else {
                _caixaReferenteDate = null;
                print('DEBUG _loadReportForDate: Formato não reconhecido, mantendo null');
              }
            } catch (e) {
              _caixaReferenteDate = null;
              print('DEBUG _loadReportForDate: Erro ao parsear caixa_referente: $e');
            }
          } else {
            _caixaReferenteDate = null;
            print('DEBUG _loadReportForDate: caixa_referente é null no banco');
          }
          _dinheiroController.text = response['dinheiro']?.toString() ?? '';
          _depositoController.text = response['deposito']?.toString() ?? '';
          _cartaoTEFController.text = response['cartao_tef']?.toString() ?? '';
          _atmController.text = response['atm']?.toString() ?? '';
          _cartaoPOSController.text = response['cartao_pos']?.toString() ?? '';
          _cobrancasController.text = response['cobrancas']?.toString() ?? '';
          _tevTedController.text = response['tev_ted']?.toString() ?? '';
          _observacoesController.text = response['observacoes']?.toString() ?? '';
          _comprovanteReceitaUrl = response['comprovante_receita'];
          _comprovanteDinheiroUrl = response['comprovante_dinheiro'];
          _comprovanteDepositoUrl = response['comprovante_deposito'];

          _comprovanteCartaoPOSUrl = response['comprovante_cartao_pos'];
          _comprovanteCartaoTEFUrl = response['comprovante_cartao_tef'];
          _comprovanteAtmUrl = response['comprovante_atm'];
          _comprovanteCobrancasUrl = response['comprovante_cobrancas'];
          _comprovanteTevTedUrl = response['comprovante_tev_ted'];
          _depositoFeito = response['deposito_feito'] ?? false;
          _isEdited = response['is_edited'] ?? false; // Carrega status de edição

          // ATUALIZAÃƒâ€¡ÃƒÆ’O: Atualizar as listas de comprovantes ao carregar relatório
          _comprovanteReceitaUrls = _parseComprovantesUrls(response['comprovante_receita']);
          _comprovanteDinheiroUrls = _parseComprovantesUrls(response['comprovante_dinheiro']);
          _comprovanteDepositoUrls = _parseComprovantesUrls(response['comprovante_deposito']);
          _comprovanteCartaoPOSUrls = _parseComprovantesUrls(response['comprovante_cartao_pos']);
          _comprovanteCartaoTEFUrls = _parseComprovantesUrls(response['comprovante_cartao_tef']);
          _comprovanteAtmUrls = _parseComprovantesUrls(response['comprovante_atm']);
          _comprovanteCobrancasUrls = _parseComprovantesUrls(response['comprovante_cobrancas']);
          _comprovanteTevTedUrls = _parseComprovantesUrls(response['comprovante_tev_ted']);

        } else {
          // Não limpa o campo de caixa referente quando não encontra relatório
          _receitaDiaController.clear();
          _saldoInicialController.clear();
          // _caixaReferenteController.clear(); // NÃƒÆ’O LIMPA - mantém a data selecionad
          _dinheiroController.clear();
          _depositoController.clear();
          _cartaoTEFController.clear();
          _atmController.clear();
          _cartaoPOSController.clear();
          _cobrancasController.clear();
          _tevTedController.clear();
          _observacoesController.clear();
          _comprovanteReceitaUrl = null;
          _comprovanteDinheiroUrl = null;
          _comprovanteDepositoUrl = null;
          _comprovanteCartaoPOSUrl = null;
          _comprovanteCartaoTEFUrl = null;
          _comprovanteAtmUrl = null;
          _comprovanteCobrancasUrl = null;
          _comprovanteTevTedUrl = null;
          // _caixaReferenteDate = null; // NÃƒÆ’O RESETA - mantém a data selecionada

          // Limpar as listas de comprovantes
          _comprovanteReceitaUrls.clear();
          _comprovanteDinheiroUrls.clear();
          _comprovanteDepositoUrls.clear();
          _comprovanteCartaoPOSUrls.clear();
          _comprovanteCartaoTEFUrls.clear();
          _comprovanteAtmUrls.clear();
          _comprovanteCobrancasUrls.clear();
          _comprovanteTevTedUrls.clear();

          // Reset das variáveis de estado das mensagens de comprovante
          _showComprovanteReceita = false;
          _showComprovanteDinheiro = false;
          _showComprovanteDeposito = false;
          _showComprovanteCartaoPOS = false;
          _showComprovanteCartaoTEF = false;
          _showComprovanteCobrancas = false;
          _showComprovanteTevTed = false;
        }
      });

      // Verificar se o usuário tem uma solicitação aprovada para esta data (APÃƒâ€œS o setState)
      // Verificar se o usuário tem uma solicitação aprovada para esta data (APÓS o setState)
      if (response != null) {
        await _verificarSolicitacaoAprovada(date);
      }
      
      // Verificar sistema de travamento e dias pendentes
      await _verificarSistemaTravamento();
      await _verificarDiasPendentes();
    } catch (error) {
      setState(() {
        _message = 'Erro ao carregar relatório: $error';
      });
    }
  }

  // =====================================================
  // VALIDAÃƒâ€¡ÃƒÆ’O DE COMPROVANTES OBRIGATÃƒâ€œRIOS
  // =====================================================

  // Função para validar se todos os campos obrigatórios têm comprovante
  Future<bool> _validarComprovantesObrigatorios(Map<String, dynamic> dados) async {
    try {
      final campos = [
        'dinheiro', 'pix', 'cartao_credito', 'cartao_debito', 
        'elo', 'mastercard', 'visa'
      ];
      
      for (final campo in campos) {
        final valor = dados[campo] ?? 0.0;
        final comprovante = dados['comprovante_$campo'];
        
        // Se tem valor > 0, comprovante é obrigatório
        if (valor > 0 && (comprovante == null || comprovante.toString().isEmpty)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Comprovante obrigatório para $campo (R\$ ${valor.toStringAsFixed(2)})'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          return false;
        }
      }
      
      // Comprovante de receita total é sempre obrigatório
      final receitaTotal = dados['receita_total'] ?? 0.0;
      final comprovanteReceita = dados['comprovante_receita_total'];
      
      if (comprovanteReceita == null || comprovanteReceita.toString().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comprovante de receita total é obrigatório'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        return false;
      }
      
      return true;
    } catch (e) {
      print('Erro ao validar comprovantes: $e');
      return false;
    }
  }

  // Função para salvar relatório com validação
  Future<void> _salvarRelatorioComValidacao(Map<String, dynamic> dados) async {
    try {
      // Validar comprovantes antes de salvar
      if (!await _validarComprovantesObrigatorios(dados)) {
        return; // Não salvar se validação falhar
      }
      
      // Adicionar data e filial
      dados['data'] = DateTime.now().toIso8601String().split('T')[0];
      dados['filial_id'] = _filialId!;
      dados['created_at'] = DateTime.now().toIso8601String();
      
      // MODO MOCK / SERVICE LAYER
      // Usar a mesma funÃ§Ã£o para salvar ou atualizar (o repositorio decide baseado no ID)
      if (_existingReport != null) {
        dados['id'] = _existingReport!['id']; // Garante que tem ID se for update
      }
      
      await ServiceLocator.repository.salvarRelatorio(dados);
      
      /* LÃ“GICA ORIGINAL (COMENTADA)
      if (existingReport != null) {
        await Supabase.instance.client...update...
      } else {
        await Supabase.instance.client...insert...
      }
      */
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Relatório salvo com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Notificar sucesso
      _showNotification(
        'Relatório Salvo',
        'Relatório do dia foi salvo com sucesso',
        'success_notification',
      );
      
    } catch (e) {
      print('Erro ao salvar relatório: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar relatório: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Função para verificar se o sistema está travado
  Future<void> _verificarSistemaTravamento() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Buscar tempo limite da filial do usuário
      final userResponse = await Supabase.instance.client
          .from('users')
          .select('tempo_limite_envio, filial_id')
          .eq('id', userId)
          .single();

      _tempoLimiteEnvio = userResponse['tempo_limite_envio'] as int?;
      final filialId = userResponse['filial_id'] as String?;

      if (_tempoLimiteEnvio != null && filialId != null) {
        // Verificar se o último relatório é mais antigo que o limite
        final dataLimite = DateTime.now().subtract(Duration(hours: _tempoLimiteEnvio!));
        
        if (_existingReport != null) {
          final dataUltimoRelatorio = DateTime.parse(_existingReport!['created_at']);
          _isSistemaTravado = dataUltimoRelatorio.isBefore(dataLimite);
        } else {
          // Se não há relatório, verificar se há relatórios antigos da filial
          final relatoriosAntigos = await Supabase.instance.client
              .from('relatorios')
              .select('created_at')
              .eq('filial_id', filialId)
              .order('created_at', ascending: false)
              .limit(1);

          if (relatoriosAntigos.isNotEmpty) {
            final dataUltimoRelatorio = DateTime.parse(relatoriosAntigos[0]['created_at']);
            _isSistemaTravado = dataUltimoRelatorio.isBefore(dataLimite);
          }
        }
      }
    } catch (error) {
      print('Erro ao verificar sistema de travamento: $error');
    }
  }

  // Função para verificar dias pendentes (sábado/domingo)
  Future<void> _verificarDiasPendentes() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      _diasPendentes.clear();
      final hoje = DateTime.now();
      
      // Verificar últimos 7 dias
      for (int i = 1; i <= 7; i++) {
        final dataVerificar = hoje.subtract(Duration(days: i));
        
        // Verificar se é sábado (6) ou domingo (7)
        if (dataVerificar.weekday == DateTime.saturday || dataVerificar.weekday == DateTime.sunday) {
          // Verificar se existe relatório para este dia
          final dataStr = dataVerificar.toIso8601String().split('T')[0];
          final relatorio = await Supabase.instance.client
              .from('relatorios')
              .select('id')
              .eq('user_id', userId)
              .eq('caixa_referente', dataStr)
              .maybeSingle();

          if (relatorio == null) {
            _diasPendentes.add(dataVerificar);
          }
        }
      }
    } catch (error) {
      print('Erro ao verificar dias pendentes: $error');
    }
  }

  // Função para abrir formulário de relatório para dia pendente
  Future<void> _abrirRelatorioDiaPendente(DateTime data) async {
    try {
      // Definir a data selecionada
      _selectedDate = data;
      
      // ATUALIZAR o caixa referente para a data selecionada
      _caixaReferenteController.text = '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
      
      // Limpar os controllers de valores (mas manter o caixa referente)
      _saldoInicialController.clear();
      _receitaDiaController.clear();
      _dinheiroController.clear();
      _depositoController.clear();
      _cartaoTEFController.clear();
      _atmController.clear();
      _cartaoPOSController.clear();
      _cobrancasController.clear();
      _tevTedController.clear();
      _observacoesController.clear();
      
      // Carregar relatório existente para esta data (se houver)
      await _loadReportForDate(data);
      
      // Mostrar mensagem informativa
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Formulário aberto para ${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}. Preencha os valores e envie.'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
        ),
      );
      
      // NÃƒÆ’O recarregar dias pendentes aqui para evitar duplicação
      // await _verificarDiasPendentes();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao abrir formulário: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
  Future<void> _marcarComoVisualizada(String mensagemId) async {
    try {
      if (_filialId != null) {
        // Verificar se já foi marcada como visualizada ANTES de tentar inserir
        final response = await Supabase.instance.client
            .from('mensagens_visualizacoes')
            .select('id')
            .eq('mensagem_id', mensagemId)
            .eq('filial_id', _filialId!)
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
              'filial_id': _filialId,
              'visualizado_em': DateTime.now().toIso8601String(),
            });
      }
    } catch (e) {
      // Ignorar erro de duplicação silenciosamente
      if (e.toString().contains('duplicate key')) {
        return; // Já existe, tudo bem
      }
      print('Erro ao marcar como visualizada: $e');
    }
  }

  // Função otimizada para marcar múltiplas mensagens
  Future<void> _marcarMensagensComoVisualizadas(List<String> mensagemIds) async {
    try {
      if (_filialId == null) return;
      
      // Buscar visualizações existentes de uma vez
      final existingViews = await Supabase.instance.client
          .from('mensagens_visualizacoes')
          .select('mensagem_id')
          .eq('filial_id', _filialId!);
      
      // Filtrar apenas as mensagens que queremos verificar
      final existingIds = existingViews
          .where((v) => mensagemIds.contains(v['mensagem_id']))
          .map((v) => v['mensagem_id'] as String)
          .toSet();
      final newIds = mensagemIds.where((id) => !existingIds.contains(id)).toList();
      
      // Inserir apenas as novas visualizações
      if (newIds.isNotEmpty) {
        final visualizacoes = newIds.map((id) => {
          'mensagem_id': id,
          'filial_id': _filialId,
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

  // Funções do Sistema de Chat
  Stream<List<Map<String, dynamic>>> _getMensagensStream() {
    if (_filialId == null) return Stream.value([]);
    return ServiceLocator.repository.getMensagens(_filialId!);
  }

  Future<void> _carregarMensagens() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Funcionário vê mensagens individuais da sua filial + mensagens gerais
      if (_filialId == null) return;
      
      print('DEBUG _carregarMensagens: userId=$userId, filialId=$_filialId');
      
      // Corrigido: usar filtro mais específico para evitar mensagens de outras filiais
      // _filialId é o nome da filial (ex: "B&B", "Foccus", etc.)
      final response = await Supabase.instance.client
          .from('mensagens_chat')
          .select('*')
          .or('and(tipo.eq.funcionario,filial_id.eq.$_filialId),and(tipo.eq.gerente,filial_id.is.null)')
          .order('created_at', ascending: true);

      print('DEBUG _carregarMensagens: Recebidas ${response.length} mensagens da query');
      
      setState(() {
        _mensagens = List<Map<String, dynamic>>.from(response);
      });
    } catch (error) {
      print('Erro ao carregar mensagens: $error');
    }
  }

  Future<void> _enviarMensagem() async {
    if (_mensagemController.text.trim().isEmpty) return;

    try {
      setState(() {
        _isEnviandoMensagem = true;
      });

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null || _filialId == null) return;

      print('DEBUG _enviarMensagem: userId=$userId, filialId=$_filialId, mensagem=${_mensagemController.text.trim()}');

      // Corrigido: _filialId já é o nome da filial (ex: "B&B", "Foccus", etc.)
      // MODO MOCK / SERVICE LAYER
      await ServiceLocator.repository.enviarMensagem(
        _mensagemController.text.trim(),
        _filialId!
      );
      
      /*
      await Supabase.instance.client.from('mensagens_chat').insert({
        'user_id': userId,
        'filial_id': _filialId!, // Este é o nome da filial (ex: "B&B")
        'mensagem': _mensagemController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
        'tipo': 'funcionario',
      });
      */

      print('DEBUG _enviarMensagem: Mensagem enviada com sucesso!');
      _mensagemController.clear();
      await _carregarMensagens();
    } catch (error) {
      print('DEBUG _enviarMensagem: Erro ao enviar mensagem: $error');
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

  void _abrirChat() async {
    try {
      // Mostrar loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Buscar IDs das mensagens que precisam ser marcadas
      final mensagens = await Supabase.instance.client
          .from('mensagens_chat')
          .select('id')
          .or('and(tipo.eq.funcionario,filial_id.eq.$_filialId),and(tipo.eq.gerente,filial_id.is.null)')
          .order('created_at', ascending: false)
          .limit(50); // Limitar a 50 mensagens mais recentes
      
      // Marcar como visualizadas em lote (mais rápido)
      if (mensagens.isNotEmpty) {
        final mensagemIds = mensagens.map((m) => m['id'] as String).toList();
        await _marcarMensagensComoVisualizadas(mensagemIds);
      }
      
      // Fechar loading
      Navigator.of(context).pop();
      
      // Abrir chat após marcar como visualizadas
      showDialog(
        context: context,
        builder: (context) => _buildChatDialog(),
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
        builder: (context) => _buildChatDialog(),
      ).then((_) {
        // Limpar o timer quando o chat for fechado
        _chatTimer?.cancel();
        _chatTimer = null;
      });
    }
  }

  Widget _buildChatDialog() {
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
                    'Chat Individual',
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
                    stream: _getMensagensStream(),
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
                      final isMensagemGeral = mensagem['tipo'] == 'gerente' && mensagem['filial_id'] == null;
                      
                      // Separador de data
                      final dataAtual = DateTime.parse(mensagem['created_at']);
                      final dataAnterior = index > 0 
                          ? DateTime.parse(mensagens[index - 1]['created_at'])
                          : null;
                      
                      return Column(
                        children: [
                          // Separador de data
                          if (dataAnterior == null || !isMesmoDia(dataAtual, dataAnterior))
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Divider(color: Colors.grey[400]),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      formatarData(dataAtual),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(color: Colors.grey[400]),
                                  ),
                                ],
                              ),
                            ),
                          
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
                                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isMensagemGeral ? Colors.red[50] : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if (isMensagemGeral) ...[
                                              Icon(
                                                Icons.broadcast_on_personal,
                                                size: 16,
                                                color: Colors.red[700],
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            if (isMensagemGeral) ...[
                                              Text(
                                                'COMUNICADO GERAL',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red[700],
                                                ),
                                              ),
                                            ] else ...[
                                              FutureBuilder<String>(
                                                future: _buscarNomeUsuario(mensagem['user_id']),
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
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          mensagem['mensagem'] ?? '',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isMensagemGeral ? FontWeight.w500 : FontWeight.normal,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              formatarHora(dataAtual),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (isMensagemGeral) ...[
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
                                            ] else ...[
                                              // Para mensagens individuais, sempre mostrar como vista
                                              Icon(
                                                Icons.done_all,
                                                size: 14,
                                                color: Colors.blue[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Vista',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.blue[600],
                                                ),
                                              ),
                                            ],
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
                    },
                  );
                },
              );
                },
              ),
            ),
            
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
                      onPressed: _isEnviandoMensagem ? null : _enviarMensagem,
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

  void _clearControllers() {
    _receitaDiaController.clear();
    _saldoInicialController.clear();
    _caixaReferenteController.clear();
    _dinheiroController.clear();
    _depositoController.clear();
    _cartaoTEFController.clear();
    _atmController.clear();
    _cartaoPOSController.clear();
    _cobrancasController.clear();
    _tevTedController.clear();
    _observacoesController.clear();
    _comprovanteReceitaUrl = null;
    _comprovanteDinheiroUrl = null;
    _comprovanteDepositoUrl = null;

    _comprovanteCartaoPOSUrl = null;
    _comprovanteCartaoTEFUrl = null;
    _comprovanteAtmUrl = null;
    _comprovanteCobrancasUrl = null;
    _comprovanteTevTedUrl = null;
    // _caixaReferenteDate = null; // NÃƒÆ’O RESETA - mantém a data selecionada

    // CORREÃƒâ€¡ÃƒÆ’O: Limpar as listas de comprovantes
    _comprovanteReceitaUrls.clear();
    _comprovanteDinheiroUrls.clear();
    _comprovanteDepositoUrls.clear();
    _comprovanteCartaoPOSUrls.clear();
    _comprovanteCartaoTEFUrls.clear();
    _comprovanteAtmUrls.clear();
    _comprovanteCobrancasUrls.clear();
    _comprovanteTevTedUrls.clear();

    // Reset das variáveis de estado das mensagens de comprovante
    _showComprovanteReceita = false;
    _showComprovanteDinheiro = false;
    _showComprovanteDeposito = false;
    _showComprovanteCartaoPOS = false;
    _showComprovanteCartaoTEF = false;
    _showComprovanteCobrancas = false;
    _showComprovanteTevTed = false;
  }

  void _solicitarAcesso() async {
    final TextEditingController motivoController = TextEditingController();

    // Verificar se o usuário selecionou uma data no caixa referente
    if (_caixaReferenteDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione primeiro uma data no campo "Caixa Referente"'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Verificar se já existe uma solicitação para esta data
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final dataRelatorio = _caixaReferenteDate!.toIso8601String().split('T')[0];

      final existingSolicitacao = await Supabase.instance.client
          .from('solicitacoes_acesso')
          .select('*')
          .eq('user_id', userId)
          .eq('data_relatorio', dataRelatorio)
          .maybeSingle();

      if (existingSolicitacao != null) {
        String statusText = '';
        Color statusColor = Colors.orange;

        switch (existingSolicitacao['status']) {
          case 'pendente':
            statusText = 'Você já tem uma solicitação pendente para esta data. Aguarde a aprovação do gerente.';
            statusColor = Colors.orange;
            break;
          case 'aprovado':
            statusText = 'Você já tem uma solicitação aprovada para esta data. Você pode editar o relatório!';
            statusColor = Colors.green;
            break;
          case 'rejeitado':
            statusText = 'Sua solicitação anterior foi rejeitada. Você pode solicitar novamente.';
            statusColor = Colors.red;
            break;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(statusText),
            backgroundColor: statusColor,
            duration: const Duration(seconds: 4),
          ),
        );

        // Se foi aprovada, não permite solicitar novamente
        if (existingSolicitacao['status'] == 'aprovado') {
          return;
        }

        // Se foi rejeitada, permite solicitar novamente
        if (existingSolicitacao['status'] == 'rejeitado') {
          // Continua para mostrar o diálogo de nova solicitação
        }

        // Se está pendente, não permite solicitar novamente
        if (existingSolicitacao['status'] == 'pendente') {
          return;
        }
      }
    } catch (error) {
      print('Erro ao verificar solicitação existente: $error');
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solicitar Acesso para Edição'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data do Relatório: ${_caixaReferenteDate!.day.toString().padLeft(2, '0')}/${_caixaReferenteDate!.month.toString().padLeft(2, '0')}/${_caixaReferenteDate!.year}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Motivo da solicitação:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: motivoController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Descreva o motivo da edição...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Após enviar a solicitação, aguarde a aprovação do gerente.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Envie também um e-mail para rb@multipark.com.br informando sobre a solicitação de acesso.',
              style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
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
              if (motivoController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor, informe o motivo da solicitação.')),
                );
                return;
              }

              Navigator.pop(context);
              await _enviarSolicitacao(motivoController.text.trim());
            },
            child: const Text('Enviar Solicitação'),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarSolicitacao(String motivo) async {
    try {
      setState(() {
        _message = 'Enviando solicitação...';
      });

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _message = 'Erro: Usuário não está logado.';
        });
        return;
      }

      // Buscar nome do funcionário
      final userResponse = await Supabase.instance.client
          .from('users')
          .select('nome')
          .eq('id', userId)
          .single();

      final dataRelatorio = _caixaReferenteDate!.toIso8601String().split('T')[0];
      print('DEBUG _enviarSolicitacao: data_relatorio sendo enviada: $dataRelatorio');

      await Supabase.instance.client
          .from('solicitacoes_acesso')
          .insert({
        'user_id': userId,
        'nome_funcionario': userResponse['nome'] ?? 'Funcionário',
        'filial': _filialId ?? '',
        'data_relatorio': dataRelatorio,
        'motivo': motivo,
      });

      setState(() {
        _message = 'Solicitação enviada com sucesso! Aguarde a aprovação do gerente.';
      });
    } catch (error) {
      setState(() {
        _message = 'Erro ao enviar solicitação: $error';
      });
    }
  }

  void _enableEditing() {
    setState(() {
      _isEditing = true;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      // Recarrega os dados originais
      if (_existingReport != null) {
        _receitaDiaController.text = _existingReport!['receita_dia']?.toString() ?? '';
        _saldoInicialController.text = _existingReport!['saldo_inicial']?.toString() ?? '';
        _caixaReferenteController.text = _existingReport!['caixa_referente']?.toString() ?? '';
        _dinheiroController.text = _existingReport!['dinheiro']?.toString() ?? '';
        _depositoController.text = _existingReport!['deposito'] ?? '';
        _cartaoTEFController.text = _existingReport!['cartao_tef']?.toString() ?? '';
        _cartaoPOSController.text = _existingReport!['cartao_pos']?.toString() ?? '';
        _cobrancasController.text = _existingReport!['cobrancas']?.toString() ?? '';
        _tevTedController.text = _existingReport!['tev_ted']?.toString() ?? '';
        _observacoesController.text = _existingReport!['observacoes']?.toString() ?? '';
        _comprovanteReceitaUrl = _existingReport!['comprovante_receita'];
        _comprovanteDinheiroUrl = _existingReport!['comprovante_dinheiro'];
        _comprovanteDepositoUrl = _existingReport!['comprovante_deposito'];

        _comprovanteCartaoPOSUrl = _existingReport!['comprovante_cartao_pos'];
        _comprovanteCartaoTEFUrl = _existingReport!['comprovante_cartao_tef'];
        _comprovanteCobrancasUrl = _existingReport!['comprovante_cobrancas'];
        _comprovanteTevTedUrl = _existingReport!['comprovante_tev_ted'];
        _depositoFeito = _existingReport!['deposito_feito'] ?? false;
      }
    });
  }



  Future<void> _selectCaixaReferenteDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _caixaReferenteDate ?? DateTime.now(),
      firstDate: DateTime(2025, 1, 1), // Apenas 2025 em diante
      lastDate: DateTime.now(), // Não permite datas futuras
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
      print('DEBUG _selectCaixaReferenteDate: Data selecionada: $picked');
      setState(() {
        _caixaReferenteDate = picked;
        _selectedDate = picked; // ATUALIZA a data selecionada para o cálculo do saldo inicial
        // Formata a data para DD/MM/AAAA com barras
        _caixaReferenteController.text = '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
      print('DEBUG _selectCaixaReferenteDate: _caixaReferenteDate definido como: $_caixaReferenteDate');
      print('DEBUG _selectCaixaReferenteDate: _selectedDate atualizado para: $_selectedDate');

      // Carrega o relatório para a data selecionada (com tratamento de erro)
      try {
        await _loadReportForDate(picked);
        await _loadSaldoInicial(picked);
      } catch (error) {
        print('Erro ao carregar relatório para data selecionada: $error');
        // Não cancela o DatePicker, apenas registra o erro
      }
    }
  }

  // Função para sanitizar nomes de arquivos
  String _sanitizeFileName(String originalName, String tipo) {
    // Obter data e hora atual no formato especificado
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    // Obter extensão do arquivo
    final extension = originalName.split('.').last.toLowerCase();

    // Sanitizar o nome original: remover acentos, caracteres especiais e substituir espaços por _
    String sanitizedName = originalName
        .replaceAll(RegExp(r'[áàâãÃƒÂ¤]'), 'a')
        .replaceAll(RegExp(r'[éÃƒÂ¨êÃƒÂ«]'), 'e')
        .replaceAll(RegExp(r'[íÃƒÂ¬ÃƒÂ®ÃƒÂ¯]'), 'i')
        .replaceAll(RegExp(r'[óÃƒÂ²ôõÃƒÂ¶]'), 'o')
        .replaceAll(RegExp(r'[úÃƒÂ¹ÃƒÂ»ÃƒÂ¼]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[ÃƒÂÃƒâ‚¬Ãƒâ€šÃƒÆ’Ãƒâ€ž]'), 'A')
        .replaceAll(RegExp(r'[Ãƒâ€°ÃƒË†ÃƒÅ Ãƒâ€¹]'), 'E')
        .replaceAll(RegExp(r'[ÃƒÂÃƒÅ’ÃƒÅ½ÃƒÂ]'), 'I')
        .replaceAll(RegExp(r'[Ãƒâ€œÃƒâ€™Ãƒâ€Ãƒâ€¢Ãƒâ€“]'), 'O')
        .replaceAll(RegExp(r'[ÃƒÅ¡Ãƒâ„¢Ãƒâ€ºÃƒÅ“]'), 'U')
        .replaceAll(RegExp(r'[Ãƒâ€¡]'), 'C')
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    // Criar nome final com a estrutura: filialId_tipo_data_hora_sanitizedName.extensao
    final finalName = 'filial_${_filialId ?? '000'}_${tipo}_${dateStr}_${timeStr}_${sanitizedName}';

    print('DEBUG _sanitizeFileName: Original: $originalName, Sanitized: $finalName');

    return finalName;
  }
  Future<void> _pickFiles(String tipo) async {
    try {
      setState(() {
        _message = 'Selecionando arquivo...';
      });
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (result == null || result.files.isEmpty) {
        setState(() {
          _message = 'Nenhum arquivo selecionado';
        });
        return;
      }
      for (final file in result.files) {
        // Sanitizar o nome do arquivo antes do upload
        final sanitizedFileName = _sanitizeFileName(file.name, tipo);

        // Melhor tratamento para obter os bytes do arquivo
        Uint8List bytes;
        if (file.bytes != null) {
          bytes = file.bytes!;
        } else if (file.path != null) {
          try {
            bytes = Uint8List.fromList(await File(file.path!).readAsBytes());
          } catch (e) {
            print('Erro ao ler arquivo: $e');
            setState(() {
              _message = 'Erro ao ler arquivo: ${file.name}';
            });
            continue; // Pula este arquivo e continua com o próximo
          }
        } else {
          setState(() {
            _message = 'Erro: Não foi possível acessar o arquivo ${file.name}';
          });
          continue; // Pula este arquivo e continua com o próximo
        }

        final contentType = file.extension == 'pdf' ? 'application/pdf' : 'image/jpeg';

        print('DEBUG _pickFiles: Fazendo upload do arquivo: $sanitizedFileName');

        await Supabase.instance.client.storage
            .from('comprovantes')
            .uploadBinary(
          sanitizedFileName,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
        final url = Supabase.instance.client.storage
            .from('comprovantes')
            .getPublicUrl(sanitizedFileName);
        setState(() {
          switch (tipo) {
            case 'receita_dia':
              _comprovanteReceitaUrls.add(url);
              break;
            case 'dinheiro':
              _comprovanteDinheiroUrls.add(url);
              break;
            case 'deposito':
              _comprovanteDepositoUrls.add(url);
              break;
            case 'cartao_pos':
              _comprovanteCartaoPOSUrls.add(url);
              break;
            case 'cartao_tef':
              _comprovanteCartaoTEFUrls.add(url);
              break;
            case 'cobrancas':
              _comprovanteCobrancasUrls.add(url);
              break;
            case 'tev_ted':
              _comprovanteTevTedUrls.add(url);
              break;
            case 'atm':
              _comprovanteAtmUrls.add(url);
              break;
          }
        });
      }
      setState(() {
        _message = 'Comprovante(s) anexado(s) com sucesso!';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _message = '';
          });
        }
      });
    } catch (error) {
      print('DEBUG _pickFiles: Erro durante upload: $error');
      setState(() {
        _message = 'Erro ao anexar comprovante: $error';
      });
    }
  }

  void _removeComprovante(String tipo, int index) {
    setState(() {
      switch (tipo) {
        case 'receita_dia':
          _comprovanteReceitaUrls.removeAt(index);
          break;
        case 'dinheiro':
          _comprovanteDinheiroUrls.removeAt(index);
          break;
        case 'deposito':
          _comprovanteDepositoUrls.removeAt(index);
          break;
        case 'cartao_pos':
          _comprovanteCartaoPOSUrls.removeAt(index);
          break;
        case 'cartao_tef':
          _comprovanteCartaoTEFUrls.removeAt(index);
          break;
        case 'atm':
          _comprovanteAtmUrls.removeAt(index);
          break;
        case 'cobrancas':
          _comprovanteCobrancasUrls.removeAt(index);
          break;
        case 'tev_ted':
          _comprovanteTevTedUrls.removeAt(index);
          break;
      }
    });
  }

  Future<void> _submitReport() async {
    try {
      // Verificar se o sistema está travado
      if (_isSistemaTravado) {
        setState(() {
          _message = 'Sistema travado! Você precisa enviar relatórios dos dias pendentes primeiro.';
        });
        return;
      }

      // Verificar se há dias pendentes (sábado/domingo)
      if (_diasPendentes.isNotEmpty) {
        setState(() {
          _message = 'Você precisa enviar relatórios dos dias pendentes (sábado/domingo) primeiro!';
        });
        return;
      }

      if (_filialId == null) {
        setState(() {
          _message = 'Erro: Filial não encontrada.';
        });
        return;
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _message = 'Erro: Usuário não está logado.';
        });
        return;
      }

      String _toYYYYMMDD(String dateStrDDMMYYYY) {
        if (dateStrDDMMYYYY.isEmpty) {
          return '';
        }
        try {
          final parts = dateStrDDMMYYYY.split('/');
          if (parts.length == 3) {
            final day = parts[0].padLeft(2, '0');
            final month = parts[1].padLeft(2, '0');
            final year = parts[2];
            if (year.length == 4) { // Garante que o ano tem 4 dígitos
              // Valida se são números válidos antes de tentar criar um DateTime
              int.parse(day);
              int.parse(month);
              int.parse(year);
              return '$year-$month-$day';
            }
          }
          // Se o formato não for DD/MM/YYYY, verifica se já está em YYYY-MM-DD
          if (dateStrDDMMYYYY.contains('-') && dateStrDDMMYYYY.length == 10) {
            DateTime.parse(dateStrDDMMYYYY); // Tenta parsear para validar
            return dateStrDDMMYYYY;
          }
          print('Formato de data inválido para _toYYYYMMDD: $dateStrDDMMYYYY');
          throw Exception('Formato de data inválido: $dateStrDDMMYYYY');
        } catch (e) {
          print('Erro ao converter DD/MM/YYYY para YYYY-MM-DD: $e, Data original: $dateStrDDMMYYYY');
          throw Exception('Erro ao converter data: $dateStrDDMMYYYY');
        }
      }

      // Verifica se já existe relatório para o caixa referente
      String caixaRef;
      try {
        if (_caixaReferenteController.text.isNotEmpty) {
          caixaRef = _toYYYYMMDD(_caixaReferenteController.text);
        } else {
          caixaRef = formatDateToYYYYMMDD(_selectedDate);
        }

        // Validação para evitar string vazia na consulta
        if (caixaRef.isEmpty) {
          setState(() {
            _message = 'Erro: Data do caixa referente inválida.';
          });
          return;
        }
      } catch (error) {
        setState(() {
          _message = 'Erro: Data do caixa referente inválida: $error';
        });
        return;
      }

      print('DEBUG: Verificando relatório existente para caixaRef: $caixaRef');
      print('DEBUG: _existingReport: ${_existingReport != null ? "EXISTE" : "NÃƒÆ’O EXISTE"}');

      final existing = await Supabase.instance.client
          .from('relatorios')
          .select('id')
          .eq('user_id', userId)
          .eq('filial_id', _filialId ?? '')
          .eq('caixa_referente', caixaRef)
          .maybeSingle();

      print('DEBUG: Resultado da busca no banco: $existing');

      if (!_isEditing && existing != null) {
        setState(() {
          _message = 'Já existe um relatório enviado para o dia do caixa referente escolhido!';
        });
        return;
      }

      // Se não está editando e já existe relatório, não permite
      if (!_isEditing && _existingReport != null) {
        setState(() {
          _message = 'Erro: Já existe um relatório para esta data.';
        });
        return;
      }

      // Função auxiliar para validar e converter valores
      double parseValue(String value, String fieldName) {
        print('DEBUG parseValue: Campo: $fieldName, Valor original: "$value"');

        if (value.isEmpty) {
          print('DEBUG parseValue: Valor vazio, retornando 0.0');
          return 0.0;
        }

        // Remove caracteres não numéricos exceto ponto e vírgula
        String cleanValue = value.replaceAll(RegExp(r'[^\d.,]'), '');
        print('DEBUG parseValue: Valor limpo: "$cleanValue"');

        // Se tem vírgula, assume que é separador decimal
        if (cleanValue.contains(',')) {
          // Se tem mais de uma vírgula, remove todas exceto a última
          final parts = cleanValue.split(',');
          print('DEBUG parseValue: Partes separadas por vírgula: $parts');
          if (parts.length > 2) {
            // Remove pontos da parte inteira e adiciona ponto decimal
            final parteInteira = parts.sublist(0, parts.length - 1).join('').replaceAll('.', '');
            cleanValue = parteInteira + '.' + parts.last;
            print('DEBUG parseValue: Múltiplas vírgulas, valor final: "$cleanValue"');
          } else {
            // Remove pontos da parte inteira e substitui vírgula por ponto
            final parteInteira = parts[0].replaceAll('.', '');
            cleanValue = parteInteira + '.' + parts[1];
            print('DEBUG parseValue: Uma vírgula, valor final: "$cleanValue"');
          }
        }

        try {
          final result = double.parse(cleanValue);
          print('DEBUG parseValue: Conversão bem-sucedida: $result');
          return result;
        } catch (e) {
          print('DEBUG parseValue: Erro na conversão: $e');
          throw Exception('Valor inválido para $fieldName: $value');
        }
      }

      // Validação dos campos obrigatórios
      if (_receitaDiaController.text.isEmpty) {
        setState(() {
          _message = 'Erro: O campo Receita do Dia é obrigatório.';
        });
        return;
      }

      // Dentro de _submitReport, logo após a validação de receitaDiaController:
      if (_caixaReferenteController.text.isEmpty) {
        setState(() {
          _message = 'Erro: O campo Caixa Referente é obrigatório.';
        });
        return;
      }

      // CORREÃƒâ€¡ÃƒÆ’O: Validação da lógica de dinheiro vs depósito
      final dinheiroValue = parseValue(_dinheiroController.text, 'Dinheiro');
      final depositoValue = parseValue(_depositoController.text, 'Depósito');

      // Se marcou depósito realizado mas não tem comprovante
      if (_depositoFeito && _comprovanteDepositoUrls.isEmpty) {
        setState(() {
          _message = 'Erro: Ãƒâ€° necessário anexar o comprovante do depósito quando marcado como realizado.';
        });
        return;
      }

      // Se tem valor no depósito mas não marcou como realizado
      if (depositoValue > 0 && !_depositoFeito) {
        setState(() {
          _message = 'Erro: Para lançar valor no depósito, é necessário marcar "Depósito realizado" e anexar comprovante.';
        });
        return;
      }

      // Se marcou depósito realizado mas não tem valor
      if (_depositoFeito && depositoValue <= 0) {
        setState(() {
          _message = 'Erro: Se marcou "Depósito realizado", é necessário informar o valor depositado.';
        });
        return;
      }



      // Validação da data do caixa referente (agora usando calendário, então sempre válida)
      // A validação é feita automaticamente pelo showDatePicker

      String confirmMessage = _isEditing
          ? 'Tem certeza que deseja atualizar o relatório?'
          : 'Tem certeza que deseja enviar o relatório? Não será possível editá-lo.';

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_isEditing ? 'Confirmar Atualização' : 'Confirmar Envio'),
          content: Text(confirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_isEditing ? 'Atualizar' : 'Confirmar'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // Usa a data do caixa referente se disponível, senão usa a data selecionada
      String dateStr;
      if (_caixaReferenteDate != null) {
        dateStr = _caixaReferenteDate!.toIso8601String().split('T')[0];
      } else if (_caixaReferenteController.text.isNotEmpty) {
        dateStr = _toYYYYMMDD(_caixaReferenteController.text);
      } else {
        dateStr = _selectedDate.toIso8601String().split('T')[0];
      }

      // Conversão dos valores com tratamento de erro
      print('DEBUG _submitReport: Saldo inicial controller text: "${_saldoInicialController.text}"');
      print('DEBUG _submitReport: Tentando converter saldo inicial...');
      final Map<String, dynamic> reportData = {
        'saldo_inicial': parseValue(_saldoInicialController.text, 'Saldo Inicial'),
        'caixa_referente': dateStr,
        'receita_dia': parseValue(_receitaDiaController.text, 'Receita do Dia'),
        'dinheiro': parseValue(_dinheiroController.text, 'Dinheiro'),
        'deposito': parseValue(_depositoController.text, 'Depósito'),

        'cartao_tef': parseValue(_cartaoTEFController.text, 'Cartão TEF'),
        'atm': parseValue(_atmController.text, 'ATM'),
        'cartao_pos': parseValue(_cartaoPOSController.text, 'Cartão POS'),
        'cobrancas': parseValue(_cobrancasController.text, 'Cobranças'),
        'tev_ted': parseValue(_tevTedController.text, 'TEV/TED'),
        'observacoes': _observacoesController.text.isEmpty
            ? null
            : _observacoesController.text,
        'user_id': userId,
        'filial_id': _filialId,
        'comprovante_receita': _comprovanteReceitaUrls.isNotEmpty ? _comprovanteReceitaUrls.join(',') : null,
        'comprovante_dinheiro': _comprovanteDinheiroUrls.isNotEmpty ? _comprovanteDinheiroUrls.join(',') : null,
        'comprovante_deposito': _comprovanteDepositoUrls.isNotEmpty ? _comprovanteDepositoUrls.join(',') : null,

        'comprovante_cartao_pos': _comprovanteCartaoPOSUrls.isNotEmpty ? _comprovanteCartaoPOSUrls.join(',') : null,
        'comprovante_cartao_tef': _comprovanteCartaoTEFUrls.isNotEmpty ? _comprovanteCartaoTEFUrls.join(',') : null,
        'comprovante_atm': _comprovanteAtmUrls.isNotEmpty ? _comprovanteAtmUrls.join(',') : null,
        'comprovante_cobrancas': _comprovanteCobrancasUrls.isNotEmpty ? _comprovanteCobrancasUrls.join(',') : null,
        'comprovante_tev_ted': _comprovanteTevTedUrls.isNotEmpty ? _comprovanteTevTedUrls.join(',') : null,
        'deposito_feito': _depositoFeito,
        'is_edited': _isEditing ? true : false, // Marca como editado se estiver editando
        'edited_at': _isEditing ? DateTime.now().toIso8601String() : null, // Data da edição
        'created_at': DateTime.now().toIso8601String(),
      };

      // Calcula o saldo final
      final saldoInicial = reportData['saldo_inicial'] as double;
      final receitaDia = reportData['receita_dia'] as double;
      final dinheiro = reportData['dinheiro'] as double;
      final deposito = reportData['deposito'] as double;

      final cartaoTef = reportData['cartao_tef'] as double;
      final atm = reportData['atm'] as double;
      final cartaoPos = reportData['cartao_pos'] as double;
      final cobrancas = reportData['cobrancas'] as double;
      final tevTed = reportData['tev_ted'] as double;

      // Nova lógica de cálculo: Receita do Dia - (soma de todos os outros valores)
      final totalSaidas = dinheiro + deposito + cartaoTef + atm + cartaoPos + cobrancas + tevTed;
      reportData['saldo_final'] = (saldoInicial + receitaDia) - totalSaidas;

      // =====================================================
      // VALIDAÃƒâ€¡ÃƒÆ’O DE COMPROVANTES OBRIGATÃƒâ€œRIOS
      // =====================================================
      
      // Validar comprovantes para campos com valor > 0
      if (dinheiro > 0 && _comprovanteDinheiroUrls.isEmpty) {
        setState(() {
          _message = 'Erro: Comprovante obrigatório para Dinheiro (R\$ ${dinheiro.toStringAsFixed(2)})';
        });
        return;
      }
      
      if (deposito > 0 && _comprovanteDepositoUrls.isEmpty) {
        setState(() {
          _message = 'Erro: Comprovante obrigatório para Depósito (R\$ ${deposito.toStringAsFixed(2)})';
        });
        return;
      }
      
      if (cartaoTef > 0 && _comprovanteCartaoTEFUrls.isEmpty) {
        setState(() {
          _message = 'Erro: Comprovante obrigatório para Cartão TEF (R\$ ${cartaoTef.toStringAsFixed(2)})';
        });
        return;
      }
      
      if (atm > 0 && _comprovanteAtmUrls.isEmpty) {
        setState(() {
          _message = 'Erro: Comprovante obrigatório para ATM (R\$ ${atm.toStringAsFixed(2)})';
        });
        return;
      }
      
      if (cartaoPos > 0 && _comprovanteCartaoPOSUrls.isEmpty) {
        setState(() {
          _message = 'Erro: Comprovante obrigatório para Cartão POS (R\$ ${cartaoPos.toStringAsFixed(2)})';
        });
        return;
      }
      
      if (cobrancas > 0 && _comprovanteCobrancasUrls.isEmpty) {
        setState(() {
          _message = 'Erro: Comprovante obrigatório para Cobranças (R\$ ${cobrancas.toStringAsFixed(2)})';
        });
        return;
      }
      
      if (tevTed > 0 && _comprovanteTevTedUrls.isEmpty) {
        setState(() {
          _message = 'Erro: Comprovante obrigatório para TEV/TED (R\$ ${tevTed.toStringAsFixed(2)})';
        });
        return;
      }
      
      // Comprovante de receita total é SEMPRE obrigatório
      if (_comprovanteReceitaUrls.isEmpty) {
        setState(() {
          _message = 'Erro: Comprovante de receita total é obrigatório';
        });
        return;
      }

      if (_isEditing && _existingReport != null) {
        // Atualiza relatório existente - mantém a data original
        reportData['created_at'] = _existingReport!['created_at'];
        await Supabase.instance.client
            .from('relatorios')
            .update(reportData)
            .eq('id', _existingReport!['id']);

        setState(() {
          _message = 'Relatório atualizado com sucesso!';
          _isEditing = false;
        });

        // Notificar sucesso
        _showNotification(
          'Relatório Atualizado',
          'Relatório foi atualizado com sucesso',
          'report_notification',
        );

        // Faz a mensagem sumir após 3 segundos
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _message = '';
            });
          }
        });
      } else {
        // Insere novo relatório - usa a data selecionada, não a data atual
        // NÃƒÆ’O sobrescreve created_at!
        await Supabase.instance.client.from('relatorios').insert(reportData);

        setState(() {
          _message = 'Relatório enviado com sucesso!';
        });

        // Notificar sucesso
        _showNotification(
          'Relatório Enviado',
          'Relatório foi enviado com sucesso',
          'report_notification',
        );

        // CORREÃƒâ€¡ÃƒÆ’O: Limpar as listas de comprovantes após envio
        _comprovanteReceitaUrls.clear();
        _comprovanteDinheiroUrls.clear();
        _comprovanteDepositoUrls.clear();
        _comprovanteCartaoPOSUrls.clear();
        _comprovanteCartaoTEFUrls.clear();
        _comprovanteAtmUrls.clear();
        _comprovanteCobrancasUrls.clear();
        _comprovanteTevTedUrls.clear();

        // CORREÃƒâ€¡ÃƒÆ’O: Resetar o estado do depósito realizado
        _depositoFeito = false;

        // CORREÃƒâ€¡ÃƒÆ’O: Limpar também as variáveis de URL individuais
        _comprovanteReceitaUrl = null;
        _comprovanteDinheiroUrl = null;
        _comprovanteDepositoUrl = null;
        _comprovanteCartaoPOSUrl = null;
        _comprovanteCartaoTEFUrl = null;
        _comprovanteAtmUrl = null;
        _comprovanteCobrancasUrl = null;
        _comprovanteTevTedUrl = null;

        // CORREÃƒâ€¡ÃƒÆ’O: Resetar também as variáveis de estado das mensagens de comprovante
        _showComprovanteReceita = false;
        _showComprovanteDinheiro = false;
        _showComprovanteDeposito = false;
        _showComprovanteCartaoPOS = false;
        _showComprovanteCartaoTEF = false;
        _showComprovanteCobrancas = false;
        _showComprovanteTevTed = false;

        // Faz a mensagem sumir após 3 segundos
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _message = '';
            });
          }
        });

        // Recarrega o relatório após um pequeno delay para garantir que a mensagem seja exibida
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _loadReportForDate(_selectedDate);
            _loadSaldoInicial(_selectedDate); // Recarrega também o saldo inicial
            // CORREÃƒâ€¡ÃƒÆ’O: Forçar atualização do estado para refletir mudanças na tela
            setState(() {});
          }
        });
      }
    } catch (error) {
      setState(() {
        _message = 'Erro ao enviar relatório: ${error.toString()}';
      });
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LoginPage(),
        fullscreenDialog: true,
      ),
    );
  }

  String formatDateToYYYYMMDD(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String formatDateToDDMMYYYY(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<double> _getSaldoInicial([DateTime? dataReferencia]) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null || _filialId == null) return 0.0;

      // Usa a data de referência fornecida ou a data atual
      final dataParaCalcular = dataReferencia ?? _selectedDate;
      print('DEBUG _getSaldoInicial: Calculando saldo para data: $dataParaCalcular');
      print('DEBUG _getSaldoInicial: dataReferencia: $dataReferencia');
      print('DEBUG _getSaldoInicial: _selectedDate: $_selectedDate');
      print('DEBUG _getSaldoInicial: dataParaCalcular (DD/MM/AAAA): ${dataParaCalcular.day.toString().padLeft(2, '0')}/${dataParaCalcular.month.toString().padLeft(2, '0')}/${dataParaCalcular.year}');



      // CORREÃƒâ€¡ÃƒÆ’O: Buscar todos os relatórios do usuário/filial, ordenados do mais antigo para o mais recente
      final response = await Supabase.instance.client
          .from('relatorios')
          .select('dinheiro, deposito_feito, deposito, caixa_referente')
          .eq('user_id', userId)
          .eq('filial_id', _filialId ?? '')
          .order('caixa_referente', ascending: true);

      print('DEBUG _getSaldoInicial: Total de relatórios encontrados: ${response?.length ?? 0}');

      // Debug: Mostrar todos os relatórios encontrados
      if (response != null && response is List) {
        print('DEBUG _getSaldoInicial: Relatórios encontrados:');
        for (int i = 0; i < response.length; i++) {
          final rel = response[i];
          print('DEBUG _getSaldoInicial: [${i}] Data: ${rel['caixa_referente']}, Dinheiro: ${rel['dinheiro']}, Depósito: ${rel['deposito']}, Feito: ${rel['deposito_feito']}');
        }
      }

      double saldoAcumulado = 0.0;
      if (response != null && response is List) {
        for (final relatorio in response) {
          final depositoFeito = relatorio['deposito_feito'] ?? false;
          final dinheiro = _parseMoneyValue(relatorio['dinheiro']);
          final valorDeposito = _parseMoneyValue(relatorio['deposito']);
          final caixaReferente = relatorio['caixa_referente'];

          print('DEBUG _getSaldoInicial: Processando relatório de ${caixaReferente} - Dinheiro: ${dinheiro}, Depósito feito: ${depositoFeito}, Valor depósito: ${valorDeposito}');

          // CORREÃƒâ€¡ÃƒÆ’O: Só soma se for de dias anteriores ao selecionado
          if (caixaReferente != null) {
            try {
              final dataRelatorio = DateTime.parse(caixaReferente);
              // Compara apenas as datas (sem considerar hora/minuto/segundo)
              final dataRelatorioSemHora = DateTime(dataRelatorio.year, dataRelatorio.month, dataRelatorio.day);
              final dataParaCalcularSemHora = DateTime(dataParaCalcular.year, dataParaCalcular.month, dataParaCalcular.day);

              if (dataRelatorioSemHora.isAfter(dataParaCalcularSemHora) || dataRelatorioSemHora.isAtSameMomentAs(dataParaCalcularSemHora)) {
                print('DEBUG _getSaldoInicial: Pulando relatório de ${caixaReferente} - é do dia selecionado ou futuro');
                print('DEBUG _getSaldoInicial: Data relatório: ${dataRelatorioSemHora.day.toString().padLeft(2, '0')}/${dataRelatorioSemHora.month.toString().padLeft(2, '0')}/${dataRelatorioSemHora.year}');
                print('DEBUG _getSaldoInicial: Data para calcular: ${dataParaCalcularSemHora.day.toString().padLeft(2, '0')}/${dataParaCalcularSemHora.month.toString().padLeft(2, '0')}/${dataParaCalcularSemHora.year}');
                continue; // Pula relatórios do dia atual ou futuros
              }
              print('DEBUG _getSaldoInicial: Incluindo relatório de ${caixaReferente} - é de dia anterior');
              print('DEBUG _getSaldoInicial: Data relatório: ${dataRelatorioSemHora.day.toString().padLeft(2, '0')}/${dataRelatorioSemHora.month.toString().padLeft(2, '0')}/${dataRelatorioSemHora.year}');
              print('DEBUG _getSaldoInicial: Data para calcular: ${dataParaCalcularSemHora.day.toString().padLeft(2, '0')}/${dataParaCalcularSemHora.month.toString().padLeft(2, '0')}/${dataParaCalcularSemHora.year}');
            } catch (e) {
              print('Erro ao parsear data: $caixaReferente');
              continue;
            }
          }

          // NOVA LÃƒâ€œGICA CORRIGIDA: Considera o valor que sobrou após o depósito
          if (depositoFeito == true || depositoFeito == 1) {
            // Se fez depósito, calcula o que sobrou: (dinheiro + saldo_acumulado) - valor_depositado
            final totalEmCaixa = dinheiro + saldoAcumulado;
            final sobrou = totalEmCaixa - valorDeposito;
            print('DEBUG _getSaldoInicial: Depósito feito em ${caixaReferente}.');
            print('DEBUG _getSaldoInicial: Total em caixa: ${totalEmCaixa} (Dinheiro do dia: ${dinheiro} + Saldo acumulado: ${saldoAcumulado})');
            print('DEBUG _getSaldoInicial: Valor depositado: ${valorDeposito}, Sobrou: ${sobrou}');

            if (sobrou > 0) {
              saldoAcumulado = sobrou; // Atualiza o saldo acumulado com o que sobrou
              print('DEBUG _getSaldoInicial: Ainda sobrou ${sobrou} em caixa após o depósito');
            } else {
              saldoAcumulado = 0;
              print('DEBUG _getSaldoInicial: Todo o dinheiro foi depositado, zerando o saldo');
            }
            // Removido o break para continuar processando os próximos dias
          } else {
            // Se NÃƒÆ’O fez depósito, soma o dinheiro ao acumulado
            saldoAcumulado += dinheiro;
            print('DEBUG _getSaldoInicial: Depósito NÃƒÆ’O feito em ${caixaReferente}. Somando dinheiro do dia: ${dinheiro}, saldo acumulado: ${saldoAcumulado}');
          }
        }
      }
      print('DEBUG _getSaldoInicial: Saldo final calculado: $saldoAcumulado');
      return saldoAcumulado;
    } catch (error) {
      setState(() {
        _message = 'Erro ao buscar saldo inicial: $error';
      });
      return 0.0;
    }
  }

  // Função para verificar se o usuário tem uma solicitação aprovada para edição
  Future<void> _verificarSolicitacaoAprovada(DateTime date) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final dataRelatorio = date.toIso8601String().split('T')[0];

      final response = await Supabase.instance.client
          .from('solicitacoes_acesso')
          .select('*')
          .eq('user_id', userId)
          .eq('data_relatorio', dataRelatorio)
          .eq('status', 'aprovado')
          .maybeSingle();

      if (response != null) {
        print('DEBUG: Solicitação aprovada encontrada para data: $dataRelatorio');
        setState(() {
          _isEditing = true; // Libera a edição
        });

        // Mostra mensagem informativa
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você tem permissão para editar este relatório!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        print('DEBUG: Nenhuma solicitação aprovada encontrada para data: $dataRelatorio');
        setState(() {
          _isEditing = false; // Mantém bloqueado
        });
      }
    } catch (error) {
      print('Erro ao verificar solicitação aprovada: $error');
    }
  }

  Future<void> _loadSaldoInicial([DateTime? dataReferencia]) async {
    print('DEBUG _loadSaldoInicial: dataReferencia: $dataReferencia');
    final saldoInicial = await _getSaldoInicial(dataReferencia);
    print('DEBUG _loadSaldoInicial: saldoInicial calculado: $saldoInicial');
    final formattedValue = _formatCurrency(saldoInicial);
    print('DEBUG _loadSaldoInicial: valor formatado: "$formattedValue"');
    setState(() {
      _saldoInicialController.text = formattedValue;
    });
  }
  @override
  Widget build(BuildContext context) {
    final bool isDataBloqueada = !_isEditing && _existingReport != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.assessment), text: 'Relatório'),
            Tab(icon: Icon(Icons.person), text: 'Perfil'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.message),
            onPressed: _abrirChat,
            tooltip: 'Chat Individual com Gerente',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sair',
          ),
        ],
      ),
      body: TabBarView(
          controller: _tabController,
          children: [
      // ABA 1: RELATÃƒâ€œRIO
      Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FutureBuilder<double>(
                  key: ValueKey(_selectedDate.toIso8601String()), // Reconstroi quando a data muda
                  future: _getSaldoInicial(_selectedDate),
                  builder: (context, snapshot) {
                    return Text(
                      'Saldo Inicial: ${_formatCurrency(snapshot.data ?? 0.0)}',
                      style: const TextStyle(fontSize: 16),
                    );
                  },
                ),

              ],
            ),
            
            // Status do Sistema de Travamento
            if (_isSistemaTravado || _diasPendentes.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isSistemaTravado 
                      ? AppColors.error.withOpacity(0.1) 
                      : AppColors.warning.withOpacity(0.1),
                  border: Border.all(
                    color: _isSistemaTravado 
                        ? AppColors.error.withOpacity(0.5) 
                        : AppColors.warning.withOpacity(0.5),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isSistemaTravado ? Icons.block : Icons.warning,
                          color: _isSistemaTravado ? Colors.red : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isSistemaTravado 
                              ? 'SISTEMA TRAVADO' 
                              : 'DIAS PENDENTES',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _isSistemaTravado ? Colors.red[700] : Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isSistemaTravado)
                      Text(
                        'Sistema travado por ${_tempoLimiteEnvio ?? 0}h sem envio de relatório. '
                        'Entre em contato com o gerente.',
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    if (_diasPendentes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Clique nos dias pendentes para abrir o formulário e preencher:',
                        style: TextStyle(color: Colors.orange[700]),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _diasPendentes.map((data) {
                          return ElevatedButton.icon(
                            onPressed: () => _abrirRelatorioDiaPendente(data),
                            icon: const Icon(Icons.edit_calendar, size: 16),
                            label: Text(
                              '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
            ),
            if (_existingReport != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isEdited ? Icons.edit : Icons.check_circle,
                          color: _isEdited ? Colors.orange : Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isEdited
                                ? 'Relatório editado - Aguardando aprovação do gerente'
                                : '',
                            style: TextStyle(
                              color: _isEdited ? Colors.orange[700] : Colors.green[700],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!_isEditing)
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _solicitarAcesso,
                            icon: const Icon(Icons.lock_open),
                            label: const Text('Solicitar Acesso'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _submitReport,
                            icon: const Icon(Icons.save),
                            label: const Text('Salvar Alterações'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _cancelEditing,
                            icon: const Icon(Icons.cancel),
                            label: const Text('Cancelar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Receitas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _caixaReferenteController,
                            enabled: !isDataBloqueada || _isEditing,
                            decoration: InputDecoration(
                              labelText: 'Caixa referente ao dia:',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.grey[200],
                              hintText: 'Selecione uma data',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _selectCaixaReferenteDate(context);
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Selecionar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    // Mensagem de erro em vermelho se data bloqueada
                    if (isDataBloqueada)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                        child: Text(
                          'Já existe um relatório enviado para esta data!',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _receitaDiaController,
                      enabled: !isDataBloqueada || _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Receita do Dia (R\$)',
                        border: const OutlineInputBorder(),
                        filled: !isDataBloqueada || _isEditing,
                        fillColor: isDataBloqueada && !_isEditing
                            ? Colors.green[50]
                            : Colors.white,
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoneyInputFormatter()],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_existingReport == null || _isEditing)
                                ? () => _showComprovantePicker('receita_dia')
                                : null,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Anexar Comprovante'),
                          ),
                        ),
                      ],
                    ),
                    if (_comprovanteReceitaUrls.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comprovantes (${_comprovanteReceitaUrls.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          Container(
                            height: 120,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _comprovanteReceitaUrls.length,
                              itemBuilder: (context, i) {
                                final url = _comprovanteReceitaUrls[i];
                                final isPdf = url.toLowerCase().endsWith('.pdf');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      GestureDetector(
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
                                      Positioned(
                                        top: -8,
                                        right: -8,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _removeComprovante('receita_dia', i),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Dinheiro',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Image.asset('assets/icons/dinheiro.png', height: 24),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _dinheiroController,
                      enabled: !isDataBloqueada || _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Dinheiro (R\$)',
                        border: const OutlineInputBorder(),
                        filled: !isDataBloqueada || _isEditing,
                        fillColor: isDataBloqueada && !_isEditing
                            ? Colors.green[50]
                            : Colors.white,
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoneyInputFormatter()],
                    ),
                    const SizedBox(height: 8),

                    const SizedBox(height: 8),

                    TextField(
                      controller: _depositoController,
                      enabled: (!isDataBloqueada || _isEditing) && _depositoFeito,
                      decoration: InputDecoration(
                        labelText: 'Depósito (R\$)',
                        hintText: _depositoFeito ? 'Valor depositado' : 'Marque "Depósito realizado" primeiro',
                        border: const OutlineInputBorder(),
                        filled: !isDataBloqueada || _isEditing,
                        fillColor: isDataBloqueada && !_isEditing
                            ? Colors.green[50]
                            : _depositoFeito ? Colors.white : Colors.grey[100],
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoneyInputFormatter()],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_existingReport == null || _isEditing) && _depositoFeito
                                ? () => _showComprovantePicker('deposito')
                                : null,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Anexar Comprovante'),
                          ),
                        ),
                      ],
                    ),
                    if (_comprovanteDepositoUrls.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comprovantes (${_comprovanteDepositoUrls.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          Container(
                            height: 120,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _comprovanteDepositoUrls.length,
                              itemBuilder: (context, i) {
                                final url = _comprovanteDepositoUrls[i];
                                final isPdf = url.toLowerCase().endsWith('.pdf');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      GestureDetector(
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
                                      Positioned(
                                        top: -8,
                                        right: -8,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _removeComprovante('deposito', i),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: _depositoFeito,
                          onChanged: (_existingReport == null || _isEditing)
                              ? (value) {
                            setState(() {
                              _depositoFeito = value ?? false;
                              // CORREÃƒâ€¡ÃƒÆ’O: Limpar campo depósito se desmarcar a caixinha
                              if (!_depositoFeito) {
                                _depositoController.clear();
                                _comprovanteDepositoUrls.clear();
                              }
                            });
                          }
                              : null,
                        ),
                        Text(
                          'Depósito realizado',
                          style: TextStyle(
                            color: (_existingReport != null && !_isEditing)
                                ? Colors.grey[600]
                                : null,
                          ),
                        ),
                      ],
                    ),

                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Cartões',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Image.asset('assets/icons/mastercard.png', height: 24),
                        const SizedBox(width: 4),
                        Image.asset('assets/icons/visa.png', height: 24),
                        const SizedBox(width: 4),
                        Image.asset('assets/icons/elo.png', height: 24),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _cartaoPOSController,
                      enabled: !isDataBloqueada || _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Cartão POS (R\$)',
                        border: const OutlineInputBorder(),
                        filled: !isDataBloqueada || _isEditing,
                        fillColor: isDataBloqueada && !_isEditing
                            ? Colors.green[50]
                            : Colors.white,
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoneyInputFormatter()],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_existingReport == null || _isEditing)
                                ? () => _showComprovantePicker('cartao_pos')
                                : null,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Anexar Comprovante'),
                          ),
                        ),
                      ],
                    ),
                    if (_comprovanteCartaoPOSUrls.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comprovantes (${_comprovanteCartaoPOSUrls.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          Container(
                            height: 120,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _comprovanteCartaoPOSUrls.length,
                              itemBuilder: (context, i) {
                                final url = _comprovanteCartaoPOSUrls[i];
                                final isPdf = url.toLowerCase().endsWith('.pdf');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      GestureDetector(
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
                                      Positioned(
                                        top: -8,
                                        right: -8,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _removeComprovante('cartao_pos', i),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _cartaoTEFController,
                      enabled: !isDataBloqueada || _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Cartão TEF (R\$)',
                        border: const OutlineInputBorder(),
                        filled: !isDataBloqueada || _isEditing,
                        fillColor: isDataBloqueada && !_isEditing
                            ? Colors.green[50]
                            : Colors.white,
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoneyInputFormatter()],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_existingReport == null || _isEditing)
                                ? () => _showComprovantePicker('cartao_tef')
                                : null,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Anexar Comprovante'),
                          ),
                        ),
                      ],
                    ),
                    if (_comprovanteCartaoTEFUrls.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comprovantes (${_comprovanteCartaoTEFUrls.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          Container(
                            height: 120,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _comprovanteCartaoTEFUrls.length,
                              itemBuilder: (context, i) {
                                final url = _comprovanteCartaoTEFUrls[i];
                                final isPdf = url.toLowerCase().endsWith('.pdf');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      GestureDetector(
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
                                      Positioned(
                                        top: -8,
                                        right: -8,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _removeComprovante('cartao_tef', i),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'ATM',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.account_balance, size: 24, color: Colors.blue[700]),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _atmController,
                      enabled: !isDataBloqueada || _isEditing,
                      decoration: InputDecoration(
                        labelText: 'ATM (R\$)',
                        border: const OutlineInputBorder(),
                        filled: !isDataBloqueada || _isEditing,
                        fillColor: isDataBloqueada && !_isEditing
                            ? Colors.green[50]
                            : Colors.white,
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoneyInputFormatter()],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_existingReport == null || _isEditing)
                                ? () => _showComprovantePicker('atm')
                                : null,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Anexar Comprovante'),
                          ),
                        ),
                      ],
                    ),
                    if (_comprovanteAtmUrls.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comprovantes (${_comprovanteAtmUrls.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          Container(
                            height: 120,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _comprovanteAtmUrls.length,
                              itemBuilder: (context, i) {
                                final url = _comprovanteAtmUrls[i];
                                final isPdf = url.toLowerCase().endsWith('.pdf');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      GestureDetector(
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
                                      Positioned(
                                        top: -8,
                                        right: -8,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _removeComprovante('atm', i),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Outros Pagamentos',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Image.asset('assets/icons/cobrancas.png', height: 24),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _cobrancasController,
                      enabled: !isDataBloqueada || _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Cobranças (Boletos) (R\$)',
                        border: const OutlineInputBorder(),
                        filled: !isDataBloqueada || _isEditing,
                        fillColor: isDataBloqueada && !_isEditing
                            ? Colors.green[50]
                            : Colors.white,
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoneyInputFormatter()],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_existingReport == null || _isEditing)
                                ? () => _showComprovantePicker('cobrancas')
                                : null,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Anexar Comprovante'),
                          ),
                        ),
                      ],
                    ),
                    if (_comprovanteCobrancasUrls.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comprovantes (${_comprovanteCobrancasUrls.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          Container(
                            height: 120,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _comprovanteCobrancasUrls.length,
                              itemBuilder: (context, i) {
                                final url = _comprovanteCobrancasUrls[i];
                                final isPdf = url.toLowerCase().endsWith('.pdf');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      GestureDetector(
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
                                      Positioned(
                                        top: -8,
                                        right: -8,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _removeComprovante('cobrancas', i),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _tevTedController,
                      enabled: !isDataBloqueada || _isEditing,
                      decoration: InputDecoration(
                        labelText: 'TEV/TED (R\$)',
                        border: const OutlineInputBorder(),
                        filled: !isDataBloqueada || _isEditing,
                        fillColor: isDataBloqueada && !_isEditing
                            ? Colors.green[50]
                            : Colors.white,
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoneyInputFormatter()],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_existingReport == null || _isEditing)
                                ? () => _showComprovantePicker('tev_ted')
                                : null,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Anexar Comprovante'),
                          ),
                        ),
                      ],
                    ),
                    if (_comprovanteTevTedUrls.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comprovantes (${_comprovanteTevTedUrls.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          Container(
                            height: 120,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _comprovanteTevTedUrls.length,
                              itemBuilder: (context, i) {
                                final url = _comprovanteTevTedUrls[i];
                                final isPdf = url.toLowerCase().endsWith('.pdf');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      GestureDetector(
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
                                      Positioned(
                                        top: -8,
                                        right: -8,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _removeComprovante('tev_ted', i),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Observações',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _observacoesController,
                      enabled: !isDataBloqueada || _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Observações',
                        border: const OutlineInputBorder(),
                        filled: !isDataBloqueada || _isEditing,
                        fillColor: isDataBloqueada && !_isEditing
                            ? Colors.green[50]
                            : Colors.white,
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Botão de envio só aparece se não há relatório existente ou se está editando
            if (_existingReport == null || _isEditing)
              ElevatedButton(
                onPressed: isDataBloqueada && !_isEditing ? null : _submitReport,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: Text(
                  _isEditing ? 'Salvar Alterações' : 'Enviar Relatório',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            // Removida a mensagem de erro para datas diferentes da atual
            // Agora é possível enviar relatórios para datas passadas
            const SizedBox(height: 16),
            Text(
              _message,
              style: TextStyle(
                color: _message.contains('Erro') ? Colors.red : Colors.green,
              ),
            ),
          ],
        ),
      )),

      // ABA 2: PERFIL
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho do perfil
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isEditedPerfil ? Icons.edit : Icons.person,
                          color: _isEditedPerfil ? Colors.orange : Colors.blue,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Perfil do Funcionário',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[800],
                                ),
                              ),
                              if (_isEditedPerfil)
                                Text(
                                  'Perfil editado - Aguardando aprovação do gerente',
                                  style: TextStyle(
                                    color: Colors.orange[700],
                                    fontStyle: FontStyle.italic,
                                    fontSize: 14,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Formulário do perfil
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Informações Pessoais',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Campo Nome
                  TextField(
                    controller: _nomeController,
                    enabled: _isEditingPerfil,
                    decoration: InputDecoration(
                      labelText: 'Nome Completo',
                      hintText: 'Digite seu nome completo',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person),
                      filled: !_isEditingPerfil,
                      fillColor: _isEditingPerfil ? Colors.white : Colors.grey[100],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Campo Email da Empresa
                  TextField(
                    controller: _emailEmpresaController,
                    enabled: _isEditingPerfil,
                    decoration: InputDecoration(
                      labelText: 'Email da Empresa',
                      hintText: 'seu.email@empresa.com',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email),
                      filled: !_isEditingPerfil,
                      fillColor: _isEditingPerfil ? Colors.white : Colors.grey[100],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Botões de ação
                  if (!_isEditingPerfil)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _solicitarAcessoPerfil,
                            icon: const Icon(Icons.lock_open),
                            label: const Text('Solicitar Acesso para Editar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (_isEditingPerfil)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _salvarPerfil,
                            icon: const Icon(Icons.save),
                            label: const Text('Salvar Perfil'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isEditingPerfil = false;
                                _nomeController.text = _perfilFuncionario?['nome'] ?? '';
                                _emailEmpresaController.text = _perfilFuncionario?['email_empresa'] ?? '';
                              });
                            },
                            icon: const Icon(Icons.cancel),
                            label: const Text('Cancelar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      ],
    ),
    );
  }

  String _formatCurrency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  // Função auxiliar para criar campos de texto com estado de edição
  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String imageType,
    bool isNumber = true,
    bool isMultiline = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          enabled: !isDataBloqueada || _isEditing,
          decoration: InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
            filled: !isDataBloqueada || _isEditing,
            fillColor: isDataBloqueada && !_isEditing
                ? Colors.green[50]
                : Colors.white,
          ),
          keyboardType: isNumber
              ? TextInputType.text
              : TextInputType.text,
          maxLines: isMultiline ? 3 : 1,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_existingReport == null || _isEditing)
                    ? () => _pickFiles(imageType)
                    : null,
                icon: const Icon(Icons.attach_file),
                label: const Text('Anexar Comprovante'),
              ),
            ),
          ],
        ),
        if (_getComprovanteUrl(imageType) != null && _getComprovanteUrl(imageType)!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 4),
                const Text('Comprovante enviado!', style: TextStyle(color: Colors.green)),
              ],
            ),
          ),
      ],
    );
  }

  String? _getComprovanteUrl(String tipo) {
    switch (tipo) {
      case 'receita_dia':
        return _comprovanteReceitaUrls.isNotEmpty ? _comprovanteReceitaUrls.join(',') : null;
      case 'dinheiro':
        return _comprovanteDinheiroUrls.isNotEmpty ? _comprovanteDinheiroUrls.join(',') : null;
      case 'deposito':
        return _comprovanteDepositoUrls.isNotEmpty ? _comprovanteDepositoUrls.join(',') : null;
      case 'cartao_pos':
        return _comprovanteCartaoPOSUrls.isNotEmpty ? _comprovanteCartaoPOSUrls.join(',') : null;
      case 'cartao_tef':
        return _comprovanteCartaoTEFUrls.isNotEmpty ? _comprovanteCartaoTEFUrls.join(',') : null;
      case 'cobrancas':
        return _comprovanteCobrancasUrls.isNotEmpty ? _comprovanteCobrancasUrls.join(',') : null;
      case 'tev_ted':
        return _comprovanteTevTedUrls.isNotEmpty ? _comprovanteTevTedUrls.join(',') : null;
      default:
        return null;
    }
  }

  String _getNomeArquivo(String url) {
    // Tenta extrair o nome do arquivo do final da URL
    final uri = Uri.parse(url);
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : url;
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
                        Text('Erro ao carregar imagem'),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showComprovantePicker(String tipo) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Tirar Foto'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(tipo, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Escolher da Galeria'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(tipo, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: Colors.orange),
              title: const Text('Selecionar Arquivo'),
              onTap: () async {
                Navigator.pop(context);
                await _pickFiles(tipo);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(String tipo, ImageSource source) async {
    try {
      setState(() {
        _message = 'Selecionando imagem...';
      });
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (pickedFile == null) {
        setState(() {
          _message = 'Nenhuma imagem selecionada';
        });
        return;
      }

      // Sanitizar o nome do arquivo antes do upload
      final sanitizedFileName = _sanitizeFileName(pickedFile.name, tipo);

      final bytes = await pickedFile.readAsBytes();

      print('DEBUG _pickImage: Fazendo upload da imagem: $sanitizedFileName');

      await Supabase.instance.client.storage
          .from('comprovantes')
          .uploadBinary(
        sanitizedFileName,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );
      final url = Supabase.instance.client.storage
          .from('comprovantes')
          .getPublicUrl(sanitizedFileName);
      setState(() {
        switch (tipo) {
          case 'receita_dia':
            _comprovanteReceitaUrls.add(url);
            break;
          case 'dinheiro':
            _comprovanteDinheiroUrls.add(url);
            break;
          case 'deposito':
            _comprovanteDepositoUrls.add(url);
            break;
          case 'cartao_pos':
            _comprovanteCartaoPOSUrls.add(url);
            break;
          case 'cartao_tef':
            _comprovanteCartaoTEFUrls.add(url);
            break;
          case 'atm':
            _comprovanteAtmUrls.add(url);
            break;
          case 'cobrancas':
            _comprovanteCobrancasUrls.add(url);
            break;
          case 'tev_ted':
            _comprovanteTevTedUrls.add(url);
            break;
        }
        _message = 'Comprovante anexado com sucesso!';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _message = '';
          });
        }
      });
    } catch (error) {
      print('DEBUG _pickImage: Erro durante upload: $error');
      setState(() {
        _message = 'Erro ao anexar comprovante: $error';
      });
    }
  }

  String _toYYYYMMDD(String dateStrDDMMYYYY) {
    if (dateStrDDMMYYYY.isEmpty) {
      return '';
    }
    try {
      final parts = dateStrDDMMYYYY.split('/');
      if (parts.length == 3) {
        final day = parts[0].padLeft(2, '0');
        final month = parts[1].padLeft(2, '0');
        final year = parts[2];
        if (year.length == 4) { // Garante que o ano tem 4 dígitos
          // Valida se são números válidos antes de tentar criar um DateTime
          int.parse(day);
          int.parse(month);
          int.parse(year);
          return '$year-$month-$day';
        }
      }
      // Se o formato não for DD/MM/YYYY, verifica se já está em YYYY-MM-DD
      if (dateStrDDMMYYYY.contains('-') && dateStrDDMMYYYY.length == 10) {
        DateTime.parse(dateStrDDMMYYYY); // Tenta parsear para validar
        return dateStrDDMMYYYY;
      }
      print('Formato de data inválido para _toYYYYMMDD: $dateStrDDMMYYYY');
      return ''; // Retorna string vazia ou lança exceção
    } catch (e) {
      print('Erro ao converter DD/MM/YYYY para YYYY-MM-DD: $e, Data original: $dateStrDDMMYYYY');
      return ''; // Retorna string vazia ou lança exceção
    }
  }

  void _onCaixaReferenteChanged(String value) async {
    try {
      print('DEBUG _onCaixaReferenteChanged: Valor recebido: "$value"');

      // Não faz consulta se o valor estiver vazio ou incompleto
      if (value.isEmpty || value.length < 10) {
        print('DEBUG _onCaixaReferenteChanged: Valor vazio ou incompleto, não fazendo consulta');
        setState(() {
          _existingReport = null;
        });
        return;
      }

      final caixaRef = _toYYYYMMDD(value);
      print('DEBUG _onCaixaReferenteChanged: caixaRef convertido: "$caixaRef"');

      // Não faz consulta se a data for inválida
      if (caixaRef.isEmpty) {
        print('DEBUG _onCaixaReferenteChanged: caixaRef vazio, não fazendo consulta');
        setState(() {
          _existingReport = null;
        });
        return;
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      print('DEBUG _onCaixaReferenteChanged: Fazendo consulta com caixaRef: "$caixaRef"');
      final existing = await Supabase.instance.client
          .from('relatorios')
          .select('id')
          .eq('user_id', userId)
          .eq('filial_id', _filialId ?? '')
          .eq('caixa_referente', caixaRef)
          .maybeSingle();
      print('DEBUG _onCaixaReferenteChanged: Resultado da consulta: $existing');
      setState(() {
        _existingReport = existing;
      });
    } catch (error) {
      print('Erro ao verificar relatório existente: $error');
      setState(() {
        _existingReport = null;
      });
    }
  }

  bool get isDataBloqueada => !_isEditing && _existingReport != null;
}

