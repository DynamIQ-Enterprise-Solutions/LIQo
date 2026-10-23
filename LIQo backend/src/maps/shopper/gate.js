// The publish gate (Round 21, P1-08; docs/shopper-package-format.md §4): what
// shoppers could not walk to blocks publishing, in plain words; what they had
// saved and would lose only warns. Works on the finished graph.

/**
 * @param g {nodes, edges} final graph (indices); edges {a, b, oneWay, through}
 * @param ctx {
 *   seeds: node indices, levels: [{lv, name}], levelProblems: [{code, message, ids}],
 *   stopProblems: [...], rooms: [{who, ids, lv, doors: [node], links: [roomKey], checked}],
 *   previous, places, unconnected: [{message, ids}]
 * }
 */
export function gate(g, ctx) {
  const n = g.nodes.length;
  const fwd = Array.from({ length: n }, () => []);
  const back = Array.from({ length: n }, () => []);
  for (const e of g.edges) {
    if (e.through != null) continue;
    fwd[e.a].push(e.b);
    back[e.b].push(e.a);
    if (!e.oneWay) {
      fwd[e.b].push(e.a);
      back[e.a].push(e.b);
    }
  }
  const flood = (adj) => {
    const seen = new Uint8Array(n);
    const stack = [];
    for (const s of ctx.seeds) {
      if (s >= 0 && !seen[s]) {
        seen[s] = 1;
        stack.push(s);
      }
    }
    while (stack.length) {
      const c = stack.pop();
      for (const y of adj[c]) {
        if (!seen[y]) {
          seen[y] = 1;
          stack.push(y);
        }
      }
    }
    return seen;
  };
  const reached = flood(fwd);
  const back2 = flood(back);

  const problems = [...ctx.levelProblems];
  const warnings = [];

  // Levels nobody reaches (their own place problems are not repeated).
  const deadLevels = new Set();
  for (const l of ctx.levels) {
    const mine = g.nodes.map((nd, i) => (nd.lv === l.lv ? i : -1)).filter((i) => i >= 0);
    if (!mine.length || !ctx.seeds.length) continue;
    if (!mine.some((i) => reached[i]) && !ctx.levelProblems.some((p) => p.lv === l.lv)) {
      deadLevels.add(l.lv);
      problems.push({ code: 'level_unreachable', message: `${l.name} can't be reached from an entrance: add stairs, an escalator or a lift that leads there`, ids: l.ids, lv: l.lv });
    }
  }
  problems.push(...ctx.stopProblems);

  // Rooms: reached through a door, or through another room that is reached.
  const rooms = ctx.rooms;
  const ok = rooms.map((r) => r.doors.some((d) => reached[d]));
  for (let changed = true; changed; ) {
    changed = false;
    rooms.forEach((r, i) => {
      if (ok[i]) return;
      if (r.links.some((k) => ok[k])) {
        ok[i] = true;
        changed = true;
      }
    });
  }
  rooms.forEach((r, i) => {
    if (!r.checked || deadLevels.has(r.lv) || !ctx.seeds.length) return;
    if (!r.doors.length) {
      problems.push({ code: 'unreachable', message: `${r.who} can't be reached: it has no door to a corridor`, ids: r.ids, lv: r.lv });
    } else if (!ok[i]) {
      const viaRooms = r.links.length > 0 && r.doors.every((d) => r.linkDoors.includes(d));
      problems.push({
        code: 'unreachable',
        message: viaRooms ? `${r.who} can't be reached: its only door leads into another room that can't be reached` : `${r.who} can't be reached: the corridor outside it doesn't lead to an entrance`,
        ids: r.ids,
        lv: r.lv,
      });
    } else if (r.doors.some((d) => reached[d]) && !r.doors.some((d) => reached[d] && back2[d])) {
      warnings.push({ code: 'no_way_back', message: `${r.who} can be reached but there's no way back to an entrance. Check one-way escalators.`, ids: r.ids });
    }
  });
  warnings.push(...ctx.unconnected);

  // Places shoppers may have saved that this version drops.
  if (ctx.previous?.places?.length) {
    const ids = new Set(ctx.places.map((p) => p.id));
    const stores = new Set(ctx.places.map((p) => p.storeId).filter((x) => x != null));
    const gone = ctx.previous.places.filter((p) => !(p.storeId != null ? stores.has(p.storeId) : ids.has(p.id)));
    if (gone.length) {
      const names = gone.map((p) => p.name || p.id);
      const shown = names.slice(0, 5);
      const list = shown.length === 1 ? shown[0] : `${shown.slice(0, -1).join(', ')} and ${shown[shown.length - 1]}`;
      const more = names.length > 5 ? `, and ${names.length - 5} more` : '';
      warnings.push({
        code: 'places_gone',
        message: `${gone.length} ${gone.length === 1 ? 'place' : 'places'} shoppers may have saved will be gone: ${list}${more}`,
        ids: [],
      });
    }
  }

  problems.sort((a, b) => (a.lv ?? -1) - (b.lv ?? -1) || a.code.localeCompare(b.code) || a.message.localeCompare(b.message));
  const capped = problems.length > 50 ? [...problems.slice(0, 49), { code: 'more', message: `…and ${problems.length - 49} more`, ids: [] }] : problems;
  return { problems: capped.map(({ lv, ...p }) => p), warnings };
}
