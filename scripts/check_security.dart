#!/usr/bin/env dart

import 'dart:io';

void main() {
  print('🔒 Verificando configurações de segurança...\n');
  
  bool allGood = true;
  
  // Verificar se o arquivo secrets.dart existe
  final secretsFile = File('lib/config/secrets.dart');
  if (!secretsFile.existsSync()) {
    print('❌ ERRO: Arquivo lib/config/secrets.dart não encontrado!');
    print('   Execute: cp lib/config/secrets.example.dart lib/config/secrets.dart');
    allGood = false;
  } else {
    print('✅ Arquivo lib/config/secrets.dart encontrado');
    
    // Verificar se contém informações reais
    final content = secretsFile.readAsStringSync();
    if (content.contains('SUA_URL_DO_SUPABASE_AQUI') || 
        content.contains('SUA_CHAVE_ANONIMA_DO_SUPABASE_AQUI')) {
      print('❌ ERRO: Arquivo secrets.dart contém valores de exemplo!');
      print('   Edite o arquivo e adicione suas informações reais');
      allGood = false;
    } else {
      print('✅ Arquivo secrets.dart configurado com informações reais');
    }
  }
  
  // Verificar .gitignore
  final gitignoreFile = File('.gitignore');
  if (!gitignoreFile.existsSync()) {
    print('❌ ERRO: Arquivo .gitignore não encontrado!');
    allGood = false;
  } else {
    final gitignoreContent = gitignoreFile.readAsStringSync();
    final requiredPatterns = [
      'config/secrets.dart',
      'lib/config/secrets.dart',
      'lib/secrets.dart',
      'android/app/google-services.json',
      'android/local.properties'
    ];
    
    bool gitignoreGood = true;
    for (final pattern in requiredPatterns) {
      if (!gitignoreContent.contains(pattern)) {
        print('❌ ERRO: .gitignore não contém: $pattern');
        gitignoreGood = false;
      }
    }
    
    if (gitignoreGood) {
      print('✅ Arquivo .gitignore configurado corretamente');
    } else {
      allGood = false;
    }
  }
  
  // Verificar se secrets.dart está no git
  try {
    final result = Process.runSync('git', ['ls-files', 'lib/config/secrets.dart']);
    if (result.stdout.toString().trim().isNotEmpty) {
      print('❌ ERRO: Arquivo secrets.dart está sendo rastreado pelo Git!');
      print('   Execute: git rm --cached lib/config/secrets.dart');
      allGood = false;
    } else {
      print('✅ Arquivo secrets.dart não está sendo rastreado pelo Git');
    }
  } catch (e) {
    print('⚠️  Não foi possível verificar o status do Git');
  }
  
  print('\n' + '=' * 50);
  
  if (allGood) {
    print('🎉 TUDO CERTO! Seu projeto está configurado de forma segura.');
    print('   Você pode fazer upload para o Git sem problemas.');
  } else {
    print('🚨 PROBLEMAS ENCONTRADOS! Corrija os erros antes de fazer upload.');
    print('   Consulte o README.md para instruções detalhadas.');
  }
  
  print('=' * 50);
}
