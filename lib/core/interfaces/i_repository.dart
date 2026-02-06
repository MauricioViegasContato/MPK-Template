import 'dart:io';

abstract class IRepository {
  Future<Map<String, dynamic>?> login(String email, String password);
  Future<void> logout();
  
  // Home Page / Relatorios
  Future<Map<String, dynamic>?> getRelatorioDiario(String userId, String filialId, String date);
  Future<void> salvarRelatorio(Map<String, dynamic> dados);
  Future<List<Map<String, dynamic>>> getRelatoriosGerente(String? filialId);
  
  // Perfil
  Future<Map<String, dynamic>?> getPerfil(String userId);
  Future<void> salvarPerfil(Map<String, dynamic> dados);
  
  // Chat
  Stream<List<Map<String, dynamic>>> getMensagens(String filialId, {bool includeGlobal = false});
  Future<void> enviarMensagem(String mensagem, String filialId);
  Future<void> markMessagesAsRead(String filialId, String userId);
  
  // Users/Config
  Future<String?> getFilialId(String userId);

  // Business Logic
  Future<double> getLastBalance(DateTime date);
  Future<void> updateRelatorioStatus(String reportId, String status, {String? managerNote});

  // Storage
  Future<String?> uploadImage(File file);

  // Auth Helpers
  String? get currentUserId;
  String? get currentUserFilialId;
  String? get currentUserName;
}
