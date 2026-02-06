import '../interfaces/i_repository.dart';
import '../services/supabase_repository.dart';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();

  late IRepository _repository;

  factory ServiceLocator() {
    return _instance;
  }

  ServiceLocator._internal() {
    _repository = SupabaseRepository();
  }

  static IRepository get repository => _instance._repository;

  static void setup() {
    _instance._repository = SupabaseRepository(); 
  }
}
