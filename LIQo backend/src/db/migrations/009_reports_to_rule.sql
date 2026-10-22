-- Round 14 (owner decisions 2026-10-22): a mall admin's superior is no longer
-- picked by hand. It is the owner of their branch, else the mall's whole-mall
-- owner (the one linked first; inactive owners skipped), else none. The app
-- recomputes it after every change (src/utils/ownership.js); this applies the
-- rule once to the data already there.
UPDATE u SET reports_to = rt.owner_id, updated_at = SYSDATETIME()
  FROM users u
  OUTER APPLY (
    SELECT TOP 1 x.owner_id FROM (
      -- The owner of the admin's own branch first...
      SELECT sa.user_id AS owner_id, 0 AS pri, sa.assigned_at, sa.id
        FROM mall_admin_assignments ma
        JOIN supervisor_assignments sa ON sa.branch_id = ma.branch_id
        JOIN users o ON o.id = sa.user_id AND o.role = 'supervisor' AND o.is_active = 1
       WHERE ma.user_id = u.id
      UNION ALL
      -- ...otherwise the mall's whole-mall owner.
      SELECT sa.user_id, 1, sa.assigned_at, sa.id
        FROM mall_admin_assignments ma
        JOIN branches b ON b.id = ma.branch_id
        JOIN supervisor_assignments sa ON sa.mall_id = b.mall_id
        JOIN users o ON o.id = sa.user_id AND o.role = 'supervisor' AND o.is_active = 1
       WHERE ma.user_id = u.id
    ) x
    ORDER BY x.pri, x.assigned_at, x.id
  ) rt
  WHERE u.role = 'mall_admin' AND ISNULL(u.reports_to, -1) <> ISNULL(rt.owner_id, -1);
