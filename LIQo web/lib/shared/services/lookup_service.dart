import '../../core/api_client.dart';
import '../models/paged.dart';

/// Server-side search for pickers. Never loads a whole table.
class LookupService {
  LookupService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<PagedResult<LookupItem>> search(
    String name, {
    String query = '',
    int page = 1,
    int pageSize = 20,
    int? parentId,
    bool includeInactive = false,
  }) async {
    final r = await _client.dio.get('/lookups/$name', queryParameters: {
      'page': page,
      'pageSize': pageSize,
      if (query.isNotEmpty) 'search': query,
      if (parentId != null) 'parentId': parentId,
      if (includeInactive) 'includeInactive': 'true',
    });
    return PagedResult.fromJson(r.data as Map<String, dynamic>, LookupItem.fromJson);
  }
}
