// Non-blocking warnings computed on a canonical layout. Each carries the ids to
// select in the editor. Cheap ones only; the editor runs the same list live.

import { polygonArea } from './validator.js';

function bbox(pts) {
  let minX = Infinity;
  let minZ = Infinity;
  let maxX = -Infinity;
  let maxZ = -Infinity;
  for (const [x, z] of pts) {
    if (x < minX) minX = x;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (z > maxZ) maxZ = z;
  }
  return { minX, minZ, maxX, maxZ };
}

function overlaps(a, b) {
  return a.minX < b.maxX && b.minX < a.maxX && a.minZ < b.maxZ && b.minZ < a.maxZ;
}

export function runChecks(layout) {
  const warnings = [];
  const warn = (code, message, ids = []) => warnings.push({ code, message, ids });

  const levelById = new Map();
  for (const b of layout.buildings) for (const l of b.levels) levelById.set(l.id, { b, l });

  for (const b of layout.buildings) {
    for (const l of b.levels) {
      const where = `${b.name} / ${l.name}`;

      if (l.walls.length === 0 && l.spaces.length === 0) warn('empty_level', `${where} has nothing drawn yet.`, [l.id]);

      // Spaces: unnamed, tiny, overlapping (bounding boxes; the editor refines this).
      const boxes = l.spaces.map((s) => ({ s, box: bbox(s.shape.outer), area: polygonArea(s.shape.outer) }));
      for (const { s, area } of boxes) {
        if (!s.name) warn('unnamed_space', `${where}: a ${s.type} space has no name.`, [s.id]);
        if (area < 2) warn('tiny_space', `${where}: "${s.name || s.id}" is smaller than 2 m².`, [s.id]);
      }
      for (let i = 0; i < boxes.length; i += 1) {
        for (let j = i + 1; j < boxes.length; j += 1) {
          if (overlaps(boxes[i].box, boxes[j].box)) {
            warn('overlap', `${where}: "${boxes[i].s.name || boxes[i].s.id}" and "${boxes[j].s.name || boxes[j].s.id}" overlap. Check whether that is intended.`, [boxes[i].s.id, boxes[j].s.id]);
          }
        }
      }

      // Walls without any opening on a level that has walls: people cannot get in.
      if (l.walls.length > 0 && l.openings.length === 0) warn('no_openings', `${where} has walls but no doors or passages.`, [l.id]);

      // Features outside the outline.
      if (l.outline) {
        const box = bbox(l.outline.outer);
        for (const f of l.features) {
          if (f.x < box.minX || f.x > box.maxX || f.z < box.minZ || f.z > box.maxZ) {
            warn('outside', `${where}: ${f.type} "${f.label || f.id}" sits outside the floor outline.`, [f.id]);
          }
        }
      }
    }
  }

  // Reachability across levels through walkable connectors (forwards and backwards).
  const allLevels = [...levelById.keys()];
  if (allLevels.length > 1) {
    const adj = new Map(allLevels.map((id) => [id, new Set()]));
    const rev = new Map(allLevels.map((id) => [id, new Set()]));
    for (const cn of layout.connectors) {
      if (!cn.walkable) continue;
      const lv = cn.endpoints.map((e) => e.level);
      for (let i = 0; i < lv.length; i += 1) {
        for (let j = 0; j < lv.length; j += 1) {
          if (i === j) continue;
          if (cn.oneWay && !(i === 0 && j === 1)) continue;
          adj.get(lv[i])?.add(lv[j]);
          rev.get(lv[j])?.add(lv[i]);
        }
      }
    }
    const entranceLevel =
      allLevels.find((id) => {
        const { l } = levelById.get(id);
        return l.features.some((f) => f.type === 'entrance') || l.openings.some((o) => o.kind === 'entrance');
      }) ?? allLevels[0];
    const flood = (graph) => {
      const seen = new Set([entranceLevel]);
      const stack = [entranceLevel];
      while (stack.length) {
        const cur = stack.pop();
        for (const n of graph.get(cur) ?? []) if (!seen.has(n)) {
          seen.add(n);
          stack.push(n);
        }
      }
      return seen;
    };
    const reach = flood(adj);
    const back = flood(rev);
    for (const id of allLevels) {
      const { b, l } = levelById.get(id);
      if (!reach.has(id)) warn('unreachable', `${b.name} / ${l.name} cannot be reached from the entrance level. Add stairs, an escalator, an elevator or a ramp.`, [l.id]);
      else if (!back.has(id)) warn('no_way_back', `${b.name} / ${l.name} can be reached but not left (only one-way connectors lead there).`, [l.id]);
    }
  }

  return warnings;
}
