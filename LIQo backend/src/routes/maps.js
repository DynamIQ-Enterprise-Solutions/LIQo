import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import { minutesSinceLast } from '../repos/audit.js';

/** Autosave fires every few seconds; the audit log gets one entry per editing stretch. */
const EDIT_AUDIT_GAP_MINUTES = 10;
import * as maps from '../repos/maps.js';
import * as branches from '../repos/branches.js';
import * as stores from '../repos/stores.js';
import * as outages from '../repos/outages.js';
import * as shopper from '../repos/shopper.js';
import * as options from '../repos/options.js';
import * as packages from '../repos/packages.js';
import { packageFiles } from '../storage/files.js';
import { buildShopperPackage, stampPackage, FORMAT_VERSION } from '../maps/shopper/build.js';
import { phIso } from '../utils/dates.js';
import { resolveScope, assertBranchInScope } from '../utils/scope.js';
import { catalogPayload } from '../maps/catalog.js';
import { validateLayout, blankLayout, spaceIndex, countSpaces, publishable, reattachBackdrops } from '../maps/validator.js';
import { backdropsRouter } from './backdrops.js';
import { runChecks } from '../maps/checks.js';
import { regenerateIds } from '../maps/ids.js';

export const mapsRouter = Router();

// Uploaded floor plans and conversion live under /maps/:branchId/backdrops.
mapsRouter.use('/:branchId/backdrops', backdropsRouter);

const EDITORS = ['mall_admin'];

/** Store ↔ space links whose space no longer exists in the layout. Never blocks; always shown. */
function danglingLinkWarnings(layout, links) {
  if (!layout) return [];
  const keys = new Set(spaceIndex(layout).map((s) => s.key));
  const bad = links.filter((l) => !keys.has(l.spaceKey));
  return bad.map((l) => ({
    code: 'dangling_link',
    message: `Store "${l.storeName}" is linked to space ${l.spaceKey}, which no longer exists on the map. Relink it under Stores & spaces.`,
    ids: [],
  }));
}

/** Round 21: out-of-service marks whose connector is not in the newly published map are cleared, and audited. */
async function clearGoneOutages(req, res, branchId, layout) {
  const gone = await outages.clearMissing(branchId, (layout.connectors ?? []).map((c) => c.id));
  if (gone.length) await recordAudit(req, res, { action: 'connector_marks_cleared', entityType: 'branch', entityId: branchId, details: { connectorIds: gone, reason: 'not on the published map' } });
}

async function branchInScope(req, branchId) {
  const id = Number(branchId);
  const branch = await branches.findById(id);
  if (!branch) throw new AppError(404, 'Branch not found.');
  // Mall owners also reach their inactive branches, read-only (owner decision 2026-10-22);
  // the wider scope only applies to owners, who cannot write maps.
  assertBranchInScope(await resolveScope(req.user, { includeInactive: true }), id);
  return branch;
}

async function requireLock(req, branchId) {
  if (!(await maps.holdsLock(branchId, req.user.id))) {
    const current = await maps.findByBranch(branchId);
    const holder = current?.lock?.userName;
    throw new AppError(423, holder ? `${holder} is editing this map. Try again when they are done.` : 'Open the editor first to lock the map.');
  }
}

/**
 * Round 21 (P1-08): the shopper package for a layout about to be published,
 * with the gate's problems and warnings (docs/shopper-package-format.md §4).
 */
async function shopperBuild(branch, layout, map) {
  const [stores, labels] = await Promise.all([shopper.storesOf([branch.id]), options.list({ branchId: branch.id, kind: 'floor_label', includeInactive: false })]);
  const links = stores.flatMap((st) => st.spaceIds.map((spaceKey) => ({ spaceKey, storeId: st.id, storeName: st.name })));
  const appCategories = Object.fromEntries(stores.map((st) => [st.id, st.category]));
  let previous = null;
  if (map?.publishedVersion != null) {
    const bytes = packageFiles.read(branch.id, map.publishedVersion);
    if (bytes) {
      try {
        previous = { places: JSON.parse(bytes.toString('utf8')).places ?? [] };
      } catch {
        previous = null;
      }
    }
  }
  return buildShopperPackage({ layout: publishable(layout), links, appCategories, floorLabels: labels.map((o) => o.name), branchId: branch.id, branchName: branch.name, mallName: branch.mallName, previous });
}

/** A refusal listing what shoppers could not walk to, each with the editor ids to select. */
function unwalkable(problems) {
  const err = new AppError(400, `Shoppers couldn't use this map yet: ${problems.length} problem${problems.length === 1 ? '' : 's'} to fix before publishing.`);
  err.extra = { problems: problems.map((p) => p.message), problemDetails: problems };
  return err;
}

/** Saves the package of a published version and records it; a failure leaves the previous package served and is reported. */
async function savePackage(req, branchId, version, built) {
  try {
    const stamped = stampPackage(built.package, { version, publishedAt: phIso(new Date()) });
    if (!packageFiles.has(branchId, version)) packageFiles.write(branchId, version, stamped.json);
    await packages.record({ branchId, version, formatVersion: FORMAT_VERSION, checksum: stamped.checksum, sizeBytes: stamped.sizeBytes });
    return { checksum: stamped.checksum, sizeBytes: stamped.sizeBytes };
  } catch (err) {
    console.error(`shopper package of branch ${branchId} version ${version} not saved: ${err.message}`);
    return { error: 'The map is published, but its copy for the shopper app could not be saved. Phones keep the previous version; publish again to retry.' };
  }
}

/** Dry runs are cached per draft version and store links, so the Publish step can ask often. */
const checkCache = new Map();

function invalid(problems) {
  const err = new AppError(400, `The map has ${problems.length} problem${problems.length === 1 ? '' : 's'}. Fix them and save again.`);
  err.extra = { problems };
  return err;
}

mapsRouter.get('/catalog', (req, res) => res.json(catalogPayload()));

/** Branches the caller may see, each with its map status. */
mapsRouter.get('/', async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user, { includeInactive: true });
    res.json({ items: await maps.statusForBranches(scope.all ? null : scope.branchIds) });
  } catch (err) {
    next(err);
  }
});

mapsRouter.get('/:branchId', async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    // Sent with or without a map: the editor shows "Create map" only when this is true.
    const canEdit = req.user.role === 'superadmin' || EDITORS.includes(req.user.role);
    const map = await maps.findByBranch(branch.id);
    if (!map) return res.json({ branch, map: null, canEdit });
    const links = await stores.spaceLinksForBranch(branch.id);
    if (!canEdit) {
      // Viewers (mall owners) get the published map only: no draft, lock, versions or checks.
      return res.json({
        branch,
        map: { id: map.id, publishedVersion: map.publishedVersion ?? null, publishedAt: map.publishedAt ?? null, draftVersion: 0 },
        versions: [],
        storeLinks: links,
        warnings: [],
        canEdit,
      });
    }
    const versions = await maps.versions(map.id);
    const warnings = map.draft ? runChecks(validateLayout(map.draft).layout ?? map.draft) : [];
    warnings.push(...danglingLinkWarnings(map.draft, links));
    res.json({
      branch,
      map: { ...map, lock: map.lock ? { ...map.lock, mine: map.lock.userId === req.user.id } : null },
      versions,
      storeLinks: links,
      warnings,
      canEdit,
    });
  } catch (err) {
    next(err);
  }
});

const createSchema = z.object({
  buildingName: z.string().trim().min(1).max(80).default('Main building'),
  levelName: z.string().trim().min(1).max(60).default('Ground floor'),
  width: z.number().min(5).max(2000).default(100),
  depth: z.number().min(5).max(2000).default(60),
  // false: start without a floor outline; it comes from the uploaded plan (Round 17).
  outline: z.boolean().default(true),
});

mapsRouter.post('/:branchId', requireRole(...EDITORS), validate(createSchema), async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    if (await maps.findByBranch(branch.id)) throw new AppError(409, 'This branch already has a map.');
    const { layout, problems } = validateLayout(blankLayout(req.body));
    if (problems.length) throw invalid(problems);
    const map = await maps.create(branch.id, JSON.stringify(layout), req.user.id);
    await recordAudit(req, res, { action: 'map_created', entityType: 'map', entityId: map.id, details: { branchId: branch.id } });
    res.status(201).json({ map });
  } catch (err) {
    next(err);
  }
});

// ---- Lock ----

mapsRouter.post('/:branchId/lock', requireRole(...EDITORS), async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    const expiresAt = await maps.acquireLock(branch.id, req.user.id);
    if (!expiresAt) {
      const current = await maps.findByBranch(branch.id);
      if (!current) throw new AppError(404, 'This branch has no map yet.');
      throw new AppError(423, `${current.lock?.userName ?? 'Someone else'} is editing this map. You can view it but not edit.`);
    }
    res.json({ lock: { userId: req.user.id, expiresAt, mine: true, minutes: maps.LOCK_MINUTES } });
  } catch (err) {
    next(err);
  }
});

mapsRouter.post('/:branchId/lock/release', requireRole(...EDITORS), async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    await maps.releaseLock(branch.id, req.user.id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

/** Superadmin only: clear a lock left by a closed or crashed editor. */
mapsRouter.post('/:branchId/lock/force-release', requireRole(), async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    const map = await maps.findByBranch(branch.id);
    if (!map) throw new AppError(404, 'This branch has no map yet.');
    const previousHolder = map.lock?.userName ?? null;
    await maps.forceReleaseLock(branch.id);
    await recordAudit(req, res, { action: 'map_lock_force_released', entityType: 'map', entityId: map.id, details: { branchId: branch.id, previousHolder } });
    res.json({ released: !!map.lock, previousHolder });
  } catch (err) {
    next(err);
  }
});

// ---- Draft ----

const draftSchema = z.object({ layout: z.unknown(), baseVersion: z.number().int().min(0) });

mapsRouter.put('/:branchId/draft', requireRole(...EDITORS), validate(draftSchema), async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    await requireLock(req, branch.id);
    const { layout, problems, publishProblems } = validateLayout(req.body.layout);
    if (problems.length) throw invalid(problems);
    const draftVersion = await maps.saveDraft(branch.id, JSON.stringify(layout), req.body.baseVersion, req.user.id);
    if (draftVersion == null) {
      const current = await maps.findByBranch(branch.id);
      const err = new AppError(409, 'Someone saved a newer draft. Reload the map to continue.');
      err.extra = { code: 'MAP_STALE', draftVersion: current?.draftVersion ?? null };
      throw err;
    }
    // Refresh the lock on every save.
    await maps.acquireLock(branch.id, req.user.id);
    res.locals.audited = true; // never the generic per-request entry for drafts
    const ago = await minutesSinceLast({ action: 'map_edited', actorId: req.user.id, entityType: 'branch', entityId: branch.id });
    if (ago >= EDIT_AUDIT_GAP_MINUTES) {
      await recordAudit(req, res, { action: 'map_edited', entityType: 'branch', entityId: branch.id, details: { branchId: branch.id, draftVersion } });
    }
    res.json({ draftVersion, publishProblems, warnings: runChecks(layout), spaceCount: countSpaces(layout) });
  } catch (err) {
    next(err);
  }
});

// ---- Publish / versions / rollback ----

const publishSchema = z.object({ baseVersion: z.number().int().min(0), note: z.string().trim().max(200).optional() });

/**
 * Round 21: what publishing would say now, without publishing (the easy editor's
 * Publish step and the Issues tab). Nothing is written or audited.
 */
mapsRouter.post('/:branchId/publish-check', requireRole(...EDITORS), async (req, res, next) => {
  try {
    res.locals.audited = true;
    const branch = await branchInScope(req, req.params.branchId);
    const map = await maps.findByBranch(branch.id);
    if (!map?.draft) throw new AppError(404, 'This branch has no draft to publish.');
    const { layout, problems, publishProblems } = validateLayout(map.draft);
    const editorProblems = [...problems, ...publishProblems];
    if (editorProblems.length) return res.json({ ready: false, problems: editorProblems, problemDetails: [], warnings: [] });
    const linksKey = JSON.stringify(await stores.spaceLinksForBranch(branch.id));
    const key = `${branch.id}:${map.draftVersion}:${map.publishedVersion ?? 0}:${linksKey.length}:${linksKey.slice(0, 2000)}`;
    let built = checkCache.get(key);
    if (!built) {
      built = await shopperBuild(branch, layout, map);
      if (checkCache.size > 50) checkCache.clear();
      checkCache.set(key, { problems: built.problems, warnings: built.warnings });
    }
    res.json({ ready: built.problems.length === 0, problems: built.problems.map((p) => p.message), problemDetails: built.problems, warnings: built.warnings });
  } catch (err) {
    next(err);
  }
});

mapsRouter.post('/:branchId/publish', requireRole(...EDITORS), validate(publishSchema), async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    const map = await maps.findByBranch(branch.id);
    if (!map?.draft) throw new AppError(404, 'This branch has no draft to publish.');
    const { layout, problems, publishProblems } = validateLayout(map.draft);
    const all = [...problems, ...publishProblems];
    if (all.length) throw invalid(all);
    const built = await shopperBuild(branch, layout, map);
    if (built.problems.length) throw unwalkable(built.problems);
    const result = await maps.publish({
      branchId: branch.id,
      layoutJson: JSON.stringify(publishable(layout)),
      spaceCount: countSpaces(layout),
      baseVersion: req.body.baseVersion,
      userId: req.user.id,
      note: req.body.note ?? null,
    });
    if (result.error === 'stale') {
      const err = new AppError(409, 'The draft changed since you loaded it. Reload and publish again.');
      err.extra = { code: 'MAP_STALE', draftVersion: result.draftVersion };
      throw err;
    }
    const saved = await savePackage(req, branch.id, result.version, built);
    await recordAudit(req, res, { action: 'map_published', entityType: 'map', entityId: map.id, details: { branchId: branch.id, version: result.version, package: saved.error ? 'not saved' : { checksum: saved.checksum, sizeBytes: saved.sizeBytes } } });
    await clearGoneOutages(req, res, branch.id, layout);
    const dangling = danglingLinkWarnings(layout, await stores.spaceLinksForBranch(branch.id));
    res.json({ publishedVersion: result.version, draftVersion: result.draftVersion, warnings: dangling, shopperWarnings: built.warnings, packageError: saved.error ?? null });
  } catch (err) {
    next(err);
  }
});

mapsRouter.get('/:branchId/published', async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    const pub = await maps.publishedLayout(branch.id);
    if (!pub) throw new AppError(404, 'No published map for this branch yet.');
    res.set('Cache-Control', 'private, max-age=60');
    res.json({ branchId: branch.id, ...pub });
  } catch (err) {
    next(err);
  }
});

/** Spaces available for store linking, from the published map (draft as fallback). */
mapsRouter.get('/:branchId/spaces', async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    const pub = await maps.publishedLayout(branch.id);
    const map = pub ? null : await maps.findByBranch(branch.id);
    const layout = pub?.layout ?? map?.draft;
    if (!layout) return res.json({ source: null, spaces: [], links: [] });
    res.json({ source: pub ? 'published' : 'draft', spaces: spaceIndex(layout), links: await stores.spaceLinksForBranch(branch.id) });
  } catch (err) {
    next(err);
  }
});

mapsRouter.get('/:branchId/versions/:version', async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    const map = await maps.findByBranch(branch.id);
    if (!map) throw new AppError(404, 'This branch has no map.');
    const v = await maps.versionLayout(map.id, Number(req.params.version));
    if (!v) throw new AppError(404, 'Version not found.');
    res.json(v);
  } catch (err) {
    next(err);
  }
});

mapsRouter.post('/:branchId/rollback', requireRole(...EDITORS), validate(z.object({ version: z.number().int().min(1) })), async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    await requireLock(req, branch.id);
    const map = await maps.findByBranch(branch.id);
    if (!map) throw new AppError(404, 'This branch has no map.');
    const old = await maps.versionLayout(map.id, req.body.version);
    if (!old) throw new AppError(404, 'Version not found.');
    const { layout, problems, publishProblems } = validateLayout(old.layout);
    const all = [...problems, ...publishProblems];
    if (all.length) throw invalid(all);
    const built = await shopperBuild(branch, layout, map);
    if (built.problems.length) throw unwalkable(built.problems);
    // Republish as a NEW version (never rewind), and make it the current draft again
    // with the tracing backdrops the current draft had on levels that still exist.
    const result = await maps.publish({
      branchId: branch.id,
      layoutJson: JSON.stringify(publishable(layout)),
      spaceCount: countSpaces(layout),
      baseVersion: null,
      userId: req.user.id,
      note: `Rollback to version ${req.body.version}`,
      resetDraftTo: JSON.stringify(reattachBackdrops(structuredClone(layout), map.draft)),
    });
    const saved = await savePackage(req, branch.id, result.version, built);
    await clearGoneOutages(req, res, branch.id, layout);
    await recordAudit(req, res, { action: 'map_rolled_back', entityType: 'map', entityId: map.id, details: { branchId: branch.id, restoredFrom: req.body.version, newVersion: result.version } });
    res.json({ publishedVersion: result.version, draftVersion: result.draftVersion, restoredFrom: req.body.version, shopperWarnings: built.warnings, packageError: saved.error ?? null });
  } catch (err) {
    next(err);
  }
});

mapsRouter.post('/:branchId/copy', requireRole(...EDITORS), validate(z.object({ targetBranchId: z.number().int().positive(), overwrite: z.boolean().optional() })), async (req, res, next) => {
  try {
    const source = await branchInScope(req, req.params.branchId);
    const target = await branchInScope(req, req.body.targetBranchId);
    if (source.id === target.id) throw new AppError(400, 'Choose a different branch to copy to.');
    const map = await maps.findByBranch(source.id);
    const pub = await maps.publishedLayout(source.id);
    const layoutIn = pub?.layout ?? map?.draft;
    if (!layoutIn) throw new AppError(404, 'The source branch has no map to copy.');

    const fresh = regenerateIds(layoutIn);
    const { layout, problems } = validateLayout(fresh);
    if (problems.length) throw invalid(problems);
    const json = JSON.stringify(layout);

    const existing = await maps.findByBranch(target.id);
    if (existing) {
      if (!req.body.overwrite) throw new AppError(409, 'The target branch already has a map. Confirm to replace its draft.');
      if (existing.lock && existing.lock.userId !== req.user.id) throw new AppError(423, `${existing.lock.userName} is editing the target map.`);
      await maps.acquireLock(target.id, req.user.id);
      await maps.saveDraft(target.id, json, existing.draftVersion, req.user.id);
      await maps.releaseLock(target.id, req.user.id);
    } else {
      await maps.create(target.id, json, req.user.id);
    }
    // Store ↔ space links are never copied; the target branch links its own stores.
    await recordAudit(req, res, { action: 'map_copied', entityType: 'map', entityId: map?.id ?? null, details: { from: source.id, to: target.id } });
    res.status(201).json({ targetBranchId: target.id, map: await maps.findByBranch(target.id) });
  } catch (err) {
    next(err);
  }
});

mapsRouter.delete('/:branchId', requireRole('superadmin'), async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    await maps.remove(branch.id);
    await packages.removeBranch(branch.id);
    packageFiles.removeBranch(branch.id);
    await recordAudit(req, res, { action: 'map_deleted', entityType: 'map', entityId: null, details: { branchId: branch.id } });
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

// ---- Round 21: lifts, escalators and stairs out of service (owner decisions 2026-10-23).
// Kept apart from map versions, keyed by branch and connector id; reaches phones
// through /api/shopper/branches/:id/live. Mall admins mark and clear. ----

const SHOPPER_CONNECTORS = new Set(['elevator', 'escalator', 'stairs', 'ramp', 'moving_walkway', 'walkway', 'bridge']);

/** The published map's connectors shoppers use, with their out-of-service state. */
async function connectorRows(branchId) {
  const pub = await maps.publishedLayout(branchId);
  const levelName = new Map();
  for (const b of pub?.layout?.buildings ?? []) for (const l of b.levels ?? []) levelName.set(l.id, l.name);
  const marks = new Map((await outages.list(branchId)).map((m) => [m.connectorId, m]));
  const rows = (pub?.layout?.connectors ?? [])
    .filter((c) => SHOPPER_CONNECTORS.has(c.kind) && c.walkable !== false)
    .map((c) => ({
      id: c.id,
      kind: c.kind,
      name: c.name || null,
      levels: [...new Set((c.endpoints ?? []).map((e) => levelName.get(e.level)).filter(Boolean))],
      outOfService: marks.has(c.id),
      since: marks.get(c.id)?.since ?? null,
      markedByName: marks.get(c.id)?.markedByName ?? null,
    }))
    .sort((a, b) => String(a.name ?? a.id).localeCompare(String(b.name ?? b.id)));
  return { published: !!pub, rows };
}

mapsRouter.get('/:branchId/connectors', async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    const { published, rows } = await connectorRows(branch.id);
    res.json({ published, items: rows });
  } catch (err) {
    next(err);
  }
});

mapsRouter.put('/:branchId/connectors/:connectorId/out-of-service', requireRole(...EDITORS), validate(z.object({ out: z.boolean() })), async (req, res, next) => {
  try {
    const branch = await branchInScope(req, req.params.branchId);
    const { rows } = await connectorRows(branch.id);
    const row = rows.find((r) => r.id === req.params.connectorId);
    if (!row) throw new AppError(404, 'That lift, escalator or stairs is not on the published map.');
    const changed = req.body.out ? await outages.mark(branch.id, row.id, req.user.id) : await outages.clear(branch.id, row.id);
    if (changed) {
      await recordAudit(req, res, {
        action: req.body.out ? 'connector_out_of_service' : 'connector_back_in_service',
        entityType: 'branch',
        entityId: branch.id,
        details: { connectorId: row.id, kind: row.kind, name: row.name },
      });
    } else {
      res.locals.audited = true; // nothing changed
    }
    res.json({ items: (await connectorRows(branch.id)).rows });
  } catch (err) {
    next(err);
  }
});
