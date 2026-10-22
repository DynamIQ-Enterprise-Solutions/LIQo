/// The list envelope every paged endpoint returns.
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  final List<T> items;
  final int totalCount;
  final int page;
  final int pageSize;

  int get pageCount => totalCount == 0 ? 1 : ((totalCount - 1) ~/ pageSize) + 1;

  factory PagedResult.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) parse) => PagedResult(
        items: (j['items'] as List<dynamic>).map((e) => parse(e as Map<String, dynamic>)).toList(),
        totalCount: j['totalCount'] as int,
        page: j['page'] as int,
        pageSize: j['pageSize'] as int,
      );
}

/// What a list asks the server for.
class ListQuery {
  const ListQuery({this.page = 1, this.pageSize = 20, this.search = '', this.filters = const {}});

  final int page;
  final int pageSize;
  final String search;
  final Map<String, String> filters;

  Map<String, dynamic> toParams() => {
        'page': page,
        'pageSize': pageSize,
        if (search.isNotEmpty) 'search': search,
        for (final e in filters.entries)
          if (e.value.isNotEmpty) e.key: e.value,
      };

  ListQuery copyWith({int? page, int? pageSize, String? search, Map<String, String>? filters}) => ListQuery(
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
        search: search ?? this.search,
        filters: filters ?? this.filters,
      );
}

class LookupItem {
  const LookupItem({required this.id, required this.label, this.isActive = true});

  final int id;
  final String label;
  final bool isActive;

  factory LookupItem.fromJson(Map<String, dynamic> j) =>
      LookupItem(id: j['id'] as int, label: j['label'] as String, isActive: j['isActive'] as bool? ?? true);
}
