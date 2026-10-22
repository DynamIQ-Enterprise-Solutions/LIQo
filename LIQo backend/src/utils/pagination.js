// Shared paging + sorting for list endpoints.

export function parsePaging(queryParams, { sortMap, defaultSort }) {
  const page = Math.max(1, Number(queryParams.page) || 1);
  const pageSize = Math.min(100, Math.max(1, Number(queryParams.pageSize) || 20));
  const search = (queryParams.search || '').trim();

  // sortBy is checked against an allow-list so it can never be raw SQL.
  const sortColumn = sortMap[queryParams.sortBy] || sortMap[defaultSort] || defaultSort;
  const sortOrder = String(queryParams.sortOrder).toLowerCase() === 'desc' ? 'DESC' : 'ASC';

  return { page, pageSize, offset: (page - 1) * pageSize, search, sortColumn, sortOrder };
}

export function pageEnvelope(items, totalCount, page, pageSize) {
  return { items, totalCount, page, pageSize };
}
