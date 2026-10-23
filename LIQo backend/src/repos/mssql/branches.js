import { query, sql } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';
import { parseHours, hoursText } from '../../utils/hours.js';

const COLS = `b.id, b.mall_id, m.name AS mall_name, b.name, b.logo_url, b.address, b.latitude, b.longitude,
  b.opening_hours, b.hours_json, b.maps_link, b.place_name, b.contact_phone, b.contact_email, b.is_active, b.created_at, b.updated_at`;

export function toPublic(row) {
  return {
    id: row.id,
    mallId: row.mall_id,
    mallName: row.mall_name,
    name: row.name,
    logoUrl: row.logo_url,
    address: row.address,
    latitude: row.latitude == null ? null : Number(row.latitude),
    longitude: row.longitude == null ? null : Number(row.longitude),
    openingHours: row.opening_hours,
    hours: parseHours(row.hours_json),
    mapsLink: row.maps_link ?? null,
    placeName: row.place_name ?? null,
    contactPhone: row.contact_phone,
    contactEmail: row.contact_email,
    isActive: !!row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function list({ search, status, mallId, offset, pageSize, sortColumn, sortOrder, scopeBranchIds }) {
  const where = [];
  const params = { offset: { type: sql.Int, value: offset }, limit: { type: sql.Int, value: pageSize } };
  if (search) {
    where.push('(b.name LIKE @search OR m.name LIKE @search OR b.address LIKE @search)');
    params.search = `%${search}%`;
  }
  if (status === 'active') where.push('b.is_active = 1');
  if (status === 'inactive') where.push('b.is_active = 0');
  if (mallId) {
    where.push('b.mall_id = @mallId');
    params.mallId = { type: sql.Int, value: mallId };
  }
  if (scopeBranchIds) {
    const { clause, params: p } = inList('b.id', scopeBranchIds, 's');
    where.push(clause);
    Object.assign(params, p);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const from = 'FROM branches b JOIN malls m ON m.id = b.mall_id';

  const total = (await query(`SELECT COUNT(*) AS n ${from} ${whereSql}`, params)).recordset[0].n;
  const rows = (
    await query(
      `SELECT ${COLS} ${from} ${whereSql}
        ORDER BY ${sortColumn} ${sortOrder}
       OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`,
      params,
    )
  ).recordset;
  return { items: rows.map(toPublic), totalCount: total };
}

export async function findById(id) {
  const r = await query(`SELECT ${COLS} FROM branches b JOIN malls m ON m.id = b.mall_id WHERE b.id = @id`, {
    id: { type: sql.Int, value: id },
  });
  return r.recordset[0] ? toPublic(r.recordset[0]) : null;
}

function fieldParams(f) {
  return {
    name: f.name,
    logo: f.logoUrl ?? null,
    address: f.address ?? null,
    lat: f.latitude == null ? null : { type: sql.Decimal(9, 6), value: f.latitude },
    lng: f.longitude == null ? null : { type: sql.Decimal(9, 6), value: f.longitude },
    hours: f.openingHours ?? null,
    phone: f.contactPhone ?? null,
    email: f.contactEmail ?? null,
  };
}

export async function create(fields, createdBy) {
  const r = await query(
    `INSERT INTO branches (mall_id, name, logo_url, address, latitude, longitude, opening_hours, contact_phone, contact_email, created_by)
     OUTPUT inserted.id
     VALUES (@mallId, @name, @logo, @address, @lat, @lng, @hours, @phone, @email, @by)`,
    { ...fieldParams(fields), mallId: { type: sql.Int, value: fields.mallId }, by: { type: sql.Int, value: createdBy } },
  );
  return findById(r.recordset[0].id);
}

export async function update(id, fields) {
  await query(
    `UPDATE branches
        SET name = @name, logo_url = @logo, address = @address, latitude = @lat, longitude = @lng,
            opening_hours = @hours, contact_phone = @phone, contact_email = @email, updated_at = SYSDATETIME()
      WHERE id = @id`,
    { ...fieldParams(fields), id: { type: sql.Int, value: id } },
  );
  return findById(id);
}

/** Edit only the information fields (not the name or mall). Used by supervisors and mall admins. */
export async function updateInfo(id, fields) {
  const current = await findById(id);
  return update(id, { ...current, ...fields, name: current.name });
}

export async function setActive(id, active) {
  await query(`UPDATE branches SET is_active = @a, updated_at = SYSDATETIME() WHERE id = @id`, {
    id: { type: sql.Int, value: id },
    a: { type: sql.Bit, value: active },
  });
  return findById(id);
}

/** What a deactivation would hide: active stores, their owners, and the branch's mall admins. */
export async function impact(id) {
  const r = await query(
    `SELECT (SELECT COUNT(*) FROM stores s WHERE s.branch_id = @id AND s.is_active = 1) AS stores,
            (SELECT COUNT(DISTINCT soa.user_id) FROM store_owner_assignments soa JOIN stores s ON s.id = soa.store_id WHERE s.branch_id = @id) AS storeOwners,
            (SELECT COUNT(*) FROM mall_admin_assignments ma WHERE ma.branch_id = @id) AS mallAdmins`,
    { id: { type: sql.Int, value: id } },
  );
  return r.recordset[0];
}

// ---- Round 21: hours and the location from a Google Maps link ----

export async function setHours(id, hours) {
  await query('UPDATE branches SET hours_json = @h, updated_at = SYSDATETIME() WHERE id = @id', {
    id: { type: sql.Int, value: id },
    h: { type: sql.NVarChar(sql.MAX), value: hoursText(hours) },
  });
  return findById(id);
}

/** Sets (or clears, with nulls) the Maps link, its place name and the pin. */
export async function setLocation(id, { mapsLink, placeName, latitude, longitude }) {
  await query(
    `UPDATE branches SET maps_link = @link, place_name = @place, latitude = @lat, longitude = @lng, updated_at = SYSDATETIME() WHERE id = @id`,
    {
      id: { type: sql.Int, value: id },
      link: mapsLink ?? null,
      place: placeName ?? null,
      lat: latitude == null ? null : { type: sql.Decimal(9, 6), value: latitude },
      lng: longitude == null ? null : { type: sql.Decimal(9, 6), value: longitude },
    },
  );
  return findById(id);
}
