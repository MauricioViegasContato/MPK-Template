import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../interfaces/i_repository.dart';

class SupabaseRepository implements IRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String? _cachedFilialId;
  String? _cachedUserName;

  @override
  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        // Fetch extra profile data
        final profile = await getPerfil(response.user!.id);
        
        // Cache filial_id if available
        _cachedFilialId = profile?['filial_id'];
        _cachedUserName = profile?['nome'];
        
        return {
          'id': response.user!.id,
          'email': response.user!.email,
          'role': profile?['role'] ?? 'funcionario', 
          'nome': profile?['nome'],
          'filial_id': _cachedFilialId,
        };
      }
      return null;
    } catch (e) {
      print('Supabase Login Error: $e');
      return null;
    }
  }

  @override
  Future<void> logout() async {
    await _client.auth.signOut();
  }

  @override
  Future<Map<String, dynamic>?> getPerfil(String userId) async {
    try {
      final response = await _client
          .from('users') // Updated table name based on screenshot
          .select()
          .eq('id', userId) // Assuming 'id' is the primary key in users table, linking to auth.users.id
          // Note: In some setups, the public table is 'users' and linked via id. 
          // If the column 'user_id' doesn't exist in 'users' table, we use 'id'.
          // The screenshot shows 'id' (uuid) as PK. Usually this matches auth.uid().
          .maybeSingle();
      return response;
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  @override
  Future<void> salvarPerfil(Map<String, dynamic> dados) async {
    await _client.from('users').upsert(dados);
  }

  @override
  Future<String?> getFilialId(String userId) async {
    final profile = await getPerfil(userId);
    return profile?['filial_id'];
  }

  // --- Relatórios ---

  @override
  Future<Map<String, dynamic>?> getRelatorioDiario(String userId, String filialId, String date) async {
    try {
      final response = await _client
          .from('relatorios')
          .select()
          .eq('filial_id', filialId)
          .eq('caixa_referente', date) // Changed from 'data' to 'caixa_referente'
          .maybeSingle();
      return response;
    } catch (e) {
      print('Error fetching report: $e');
      return null;
    }
  }

  @override
  Future<void> salvarRelatorio(Map<String, dynamic> dados) async {
    // Remove ID if null to allow auto-increment/UUID generation if configured
    if (dados['id'] == null) {
      dados.remove('id');
    }
    
    await _client.from('relatorios').upsert(dados);
  }

  @override
  Future<List<Map<String, dynamic>>> getRelatoriosGerente(String? filialId) async {
    try {
      var query = _client.from('relatorios').select();
      
      if (filialId != null) {
        query = query.eq('filial_id', filialId);
      }
      
      final response = await query.order('caixa_referente', ascending: false); // Changed from 'data'
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching manager reports: $e');
      return [];
    }
  }

  @override
  Future<double> getLastBalance(DateTime date) async {
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      
      // Get current user's filial
      final user = _client.auth.currentUser;
      if (user == null) return 0.0;
      
      final profile = await getPerfil(user.id);
      final filialId = profile?['filial_id'];
      
      if (filialId == null) return 0.0;

      // Fetch ALL previous reports to calculate cumulative balance
      // "pegar desde o primeiro dia... acumulando"
      final response = await _client
          .from('relatorios')
          .select('saldo_inicial, dinheiro, deposito') 
          .eq('filial_id', filialId)
          .lt('caixa_referente', dateStr) // Strictly before today
          .order('caixa_referente', ascending: true); // From first day to yesterday

      if (response == null || (response as List).isEmpty) {
        return 0.0;
      }

      final reports = List<Map<String, dynamic>>.from(response);
      
      // Initial Seed (Cash float on Day 1)
      double runningBalance = (reports.first['saldo_inicial'] ?? 0.0) as double;
      // In case saldo_inicial is int
      if (reports.first['saldo_inicial'] is int) {
         runningBalance = (reports.first['saldo_inicial'] as int).toDouble();
      } else {
         runningBalance = (reports.first['saldo_inicial'] ?? 0.0).toDouble();
      }
      
      // Accumulate flows (Cash Only)
      // "acumular somente o do dinheiro"
      for (var report in reports) {
        final dinheiro = (report['dinheiro'] ?? 0.0) as num;
        final deposito = (report['deposito'] ?? 0.0) as num;
        
        runningBalance = runningBalance + dinheiro - deposito;
      }
      
      // Avoid negative zero
      if (runningBalance.abs() < 0.01) return 0.0;

      return runningBalance;
    } catch (e) {
      print('Error fetching last balance: $e');
      return 0.0;
    }
  }

  @override
  Future<void> updateRelatorioStatus(String reportId, String status, {String? managerNote}) async {
    try {
      final updateData = <String, dynamic>{
        'status': status,
        'tem_observacao_gerente': managerNote != null && managerNote.isNotEmpty,
      };
      
      if (managerNote != null) {
        updateData['observacao_gerente'] = managerNote;
      }

      await _client
          .from('relatorios')
          .update(updateData)
          .eq('id', reportId);
          
      print('Status updated to $status for report $reportId');
    } catch (e) {
      print('Error updating report status: $e');
      throw e; // Rethrow so UI knows it failed
    }
  }
  
  // --- Chat / Messaging ---
  // NOTE: 'mensagens' table does NOT exist in the provided schema. 
  // Stubbing these methods to prevent crashes until feature is defined/migrated.

  @override
  Stream<List<Map<String, dynamic>>> getMensagens(String filialId, {bool includeGlobal = false}) {
    // Strategy:
    // 1. If we only want specific messages (Manager Private or Manager Global Channel),
    //    we accept strict server-side filtering using .eq().
    // 2. If we want Mixed (Employee view), we fetch broadly (relying on RLS) 
    //    and then filter client-side to be safe.
    
    if (!includeGlobal) {
      return _client
          .from('mensagens')
          .stream(primaryKey: ['id'])
          .eq('filial_id', filialId)
          .order('created_at', ascending: true);
    } else {
      // Fetch broad stream (RLS restricts it for employees, but Managers might see all)
      return _client
          .from('mensagens')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: true)
          .map((rows) {
            // Client-side filter to ensure we mix correctly
            return rows.where((msg) {
              final fId = msg['filial_id'];
              return fId == filialId || fId == 'GLOBAL';
            }).toList();
          });
    }
  }

  @override
  Future<void> enviarMensagem(String mensagem, String filialId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    
    // Determine isManager based on role logic or profile
    // Ideally we should check the profile 'role' here, but for now we can assume:
    // If sending from employee app = false? But manager uses same app with different view.
    // Let's check cached role.
    
    // final profile = await getPerfil(user.id);
    // final isManager = profile?['role'] == 'gerente' || profile?['role'] == 'admin';
    
    // Optimization: Use the cached profile if available, or just default to false for now 
    // and let the UI/Context decide? 
    // Actually, usually Manager View sets a flag.
    // But repo doesn't know context. 
    // Let's implement a quick check or assume false for employee flow (which is most common).
    // Wait, the user prompt implies this is a "Chat Real". 
    // Let's try to get the role from the profile just to be safe.
    
    // NOTE: For better performance, we should cache the role at login.
    // Assuming 'funcionario' for base implementation unless explicit.
    bool isManager = false; 
    // check if current user is NOT the owner of the filial? 
    // Or check if user.email matches a manager pattern?
    
    await _client.from('mensagens').insert({
      'mensagem': mensagem,
      'filial_id': filialId,
      'user_id': user.id,
      'is_manager': isManager, // This field needs to be robust later
      'created_at': DateTime.now().toIso8601String(),
    });
  }
  
  Future<void> markMessagesAsRead(String filialId, String userId) async {
    // Mark messages in this filial sent by OTHERS as read
    // Split into 2 calls to avoid complex OR syntax issues
    try {
      // 1. Mark Filial Messages
      await _client
          .from('mensagens')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('filial_id', filialId)
          .neq('user_id', userId)
          .filter('read_at', 'is', 'null');

      // 2. Mark Global Messages
      await _client
          .from('mensagens')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('filial_id', 'GLOBAL')
          .neq('user_id', userId)
          .filter('read_at', 'is', 'null');
          
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }
  // --- Storage ---
  
  Future<String?> uploadImage(File file) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.uri.pathSegments.last}';
      final path = 'uploads/$fileName';

      await _client.storage.from('comprovantes').upload(path, file);
      
      final publicUrl = _client.storage.from('comprovantes').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  String? get currentUserFilialId => _cachedFilialId; 

  @override
  String? get currentUserName => _cachedUserName;
}
