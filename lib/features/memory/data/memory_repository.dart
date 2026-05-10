import '../../../../core/services/api_service.dart';

class MemoryRepository {
  final ApiService api;
  MemoryRepository(this.api);

  Future<List<Map<String, dynamic>>> fetchMemories({int limit = 20}) =>
      api.listMemories(limit: limit);
}
