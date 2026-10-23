// The walkway network of one level (Round 21, P1-08): the centre lines of the
// passable area (thinned with Zhang–Suen, which keeps loops around kiosks and
// columns), short spurs pruned, chains simplified to straight runs, long runs
// split so no edge is longer than 10 m. Pure and deterministic.
import { simplifyLine } from './raster.js';

const MAX_EDGE = 10;
const SIMPLIFY = 0.25;

// 8 neighbours in Zhang–Suen order: P2 (N), P3 (NE), P4 (E), P5 (SE), P6 (S), P7 (SW), P8 (W), P9 (NW).
const DI = [0, 1, 1, 1, 0, -1, -1, -1];
const DJ = [-1, -1, 0, 1, 1, 1, 0, -1];

function thin(grid, mask) {
  const { gw, gh, size } = grid;
  const fg = new Uint8Array(mask);
  const nb = (c, k) => {
    const i = (c % gw) + DI[k];
    const j = Math.floor(c / gw) + DJ[k];
    return i < 0 || j < 0 || i >= gw || j >= gh ? 0 : fg[j * gw + i];
  };
  const stamp = new Int32Array(size).fill(-1);
  let frontier = [];
  for (let c = 0; c < size; c++) {
    if (!fg[c]) continue;
    for (let k = 0; k < 8; k++) {
      if (!nb(c, k)) {
        frontier.push(c);
        break;
      }
    }
  }
  let quiet = 0;
  let step = 0;
  let round = 0;
  while (quiet < 2) {
    round += 1;
    const del = [];
    for (const c of frontier) {
      if (!fg[c]) continue;
      const p = [];
      for (let k = 0; k < 8; k++) p.push(nb(c, k));
      let b = 0;
      for (const v of p) b += v;
      if (b < 2 || b > 6) continue;
      let a = 0;
      for (let k = 0; k < 8; k++) if (!p[k] && p[(k + 1) % 8]) a += 1;
      if (a !== 1) continue;
      const [p2, , p4, , p6, , p8] = p;
      if (step === 0 ? p2 * p4 * p6 || p4 * p6 * p8 : p2 * p4 * p8 || p2 * p6 * p8) continue;
      del.push(c);
    }
    for (const c of del) fg[c] = 0;
    quiet = del.length ? 0 : quiet + 1;
    step = 1 - step;
    // Next frontier: what is left of this one, plus the neighbours of deleted cells.
    const next = [];
    for (const c of frontier) {
      if (fg[c] && stamp[c] !== round) {
        stamp[c] = round;
        next.push(c);
      }
    }
    for (const c of del) {
      for (let k = 0; k < 8; k++) {
        const i = (c % gw) + DI[k];
        const j = Math.floor(c / gw) + DJ[k];
        if (i < 0 || j < 0 || i >= gw || j >= gh) continue;
        const x = j * gw + i;
        if (fg[x] && stamp[x] !== round) {
          stamp[x] = round;
          next.push(x);
        }
      }
    }
    next.sort((x, y) => x - y);
    frontier = next;
  }
  return fg;
}

/**
 * The network of a level from its area (area.js): nodes [{x, z}], edges
 * [{a, b, w, chain}], and for every skeleton cell the chain it belongs to
 * (cellChain), with each chain's edges (chainEdges), for attaching points.
 */
export function skeleton(area) {
  const { grid, passable, d2 } = area;
  const { gw, gh, size, cell } = grid;
  const skel = thin(grid, passable);
  const neighbours = (c) => {
    const out = [];
    for (let k = 0; k < 8; k++) {
      const i = (c % gw) + DI[k];
      const j = Math.floor(c / gw) + DJ[k];
      if (i < 0 || j < 0 || i >= gw || j >= gh) continue;
      const x = j * gw + i;
      if (skel[x]) out.push(x);
    }
    return out;
  };

  // Node cells: ends and junctions; adjacent junction cells form one cluster (one node).
  const deg = new Uint8Array(size);
  const cells = [];
  for (let c = 0; c < size; c++) {
    if (!skel[c]) continue;
    cells.push(c);
    deg[c] = neighbours(c).length;
  }
  const cluster = new Int32Array(size).fill(-1);
  const clusters = [];
  for (const c of cells) {
    if (deg[c] === 2 || cluster[c] >= 0) continue;
    const id = clusters.length;
    const members = [];
    const stack = [c];
    cluster[c] = id;
    while (stack.length) {
      const x = stack.pop();
      members.push(x);
      for (const y of neighbours(x)) {
        if (deg[y] !== 2 && cluster[y] < 0) {
          cluster[y] = id;
          stack.push(y);
        }
      }
    }
    members.sort((a, b) => a - b);
    clusters.push(members);
  }
  const centre = (c) => [grid.cx(c % gw), grid.cz(Math.floor(c / gw))];
  const clusterPoint = (members) => {
    let x = 0;
    let z = 0;
    for (const m of members) {
      const [a, b] = centre(m);
      x += a;
      z += b;
    }
    return [x / members.length, z / members.length];
  };

  // Chains between clusters, walking along cells with two neighbours.
  const chains = [];
  const used = new Uint8Array(size);
  /**
   * Follows the cells from [first] (a neighbour of cluster [from]) to the next
   * cluster. Returns { a, b, cells } with the cells between the two clusters,
   * or null for a stub that only touches its own cluster.
   */
  const trace = (from, first) => {
    const path = [first];
    used[first] = 1;
    let prev = -1;
    let cur = first;
    for (;;) {
      const around = neighbours(cur).filter((y) => y !== prev);
      // Reaching a cluster ends the chain (not straight back into the start on the first step).
      const end = around.find((y) => cluster[y] >= 0 && !(cluster[y] === from && path.length === 1));
      if (end !== undefined) return { a: from, b: cluster[end], cells: path };
      const step = around.find((y) => cluster[y] < 0 && !used[y]);
      if (step === undefined) {
        if (path.length <= 2) return null;
        // A dead end the degree count missed: it becomes an end node of its own.
        const id = clusters.length;
        const last = path.pop();
        clusters.push([last]);
        cluster[last] = id;
        return { a: from, b: id, cells: path };
      }
      prev = cur;
      cur = step;
      used[cur] = 1;
      path.push(cur);
    }
  };
  for (let id = 0; id < clusters.length; id++) {
    for (const m of clusters[id]) {
      for (const y of neighbours(m)) {
        if (cluster[y] >= 0 || used[y]) continue;
        const ch = trace(id, y);
        if (ch) chains.push(ch);
      }
    }
  }
  // Loops with no junction at all (a ring around a column): a node at their first cell.
  for (const c of cells) {
    if (used[c] || cluster[c] >= 0) continue;
    const id = clusters.length;
    clusters.push([c]);
    cluster[c] = id;
    const y = neighbours(c).find((x) => !used[x] && cluster[x] < 0);
    if (y === undefined) continue;
    const ch = trace(id, y);
    if (ch) chains.push(ch);
  }

  // Prune short spurs (a dead end shorter than ~1.5 m, or than the walkway is wide), twice.
  const clearAt = (members) => Math.sqrt(Math.max(...members.map((m) => d2[m]))) * cell;
  let live = chains.map((c) => ({ ...c, alive: true }));
  for (let pass = 0; pass < 2; pass++) {
    const count = new Map();
    for (const ch of live) {
      if (!ch.alive) continue;
      count.set(ch.a, (count.get(ch.a) ?? 0) + 1);
      count.set(ch.b, (count.get(ch.b) ?? 0) + 1);
    }
    for (const ch of live) {
      if (!ch.alive || ch.a === ch.b) continue;
      const ends = [ch.a, ch.b].filter((x) => (count.get(x) ?? 0) === 1);
      if (ends.length !== 1) continue;
      const other = ends[0] === ch.a ? ch.b : ch.a;
      if ((count.get(other) ?? 0) < 3) continue;
      const len = (ch.cells.length + 1) * cell;
      if (len < Math.max(1.0, 1.5 * clearAt(clusters[other]))) {
        ch.alive = false;
        count.set(ch.a, count.get(ch.a) - 1);
        count.set(ch.b, count.get(ch.b) - 1);
      }
    }
    live = live.filter((c) => c.alive);
  }

  // Nodes: the clusters still in use; then each chain becomes simplified straight runs.
  const nodes = [];
  const nodeOf = new Map();
  const nodeFor = (cid) => {
    if (!nodeOf.has(cid)) {
      const [x, z] = clusterPoint(clusters[cid]);
      nodeOf.set(cid, nodes.length);
      nodes.push({ x, z });
    }
    return nodeOf.get(cid);
  };
  for (const ch of live) {
    nodeFor(ch.a);
    nodeFor(ch.b);
  }
  // Isolated single-cluster areas (a region whose skeleton is one blob) still get a node.
  clusters.forEach((_, cid) => {
    if (!nodeOf.has(cid) && clusters[cid].length) nodeFor(cid);
  });

  const edges = [];
  const cellChain = new Int32Array(size).fill(-1);
  const chainEdges = [];
  const chainPoints = [];
  live.forEach((ch, chainId) => {
    const a = nodeFor(ch.a);
    const b = nodeFor(ch.b);
    for (const c of ch.cells) cellChain[c] = chainId;
    for (const m of clusters[ch.a]) if (cellChain[m] < 0) cellChain[m] = chainId;
    for (const m of clusters[ch.b]) if (cellChain[m] < 0) cellChain[m] = chainId;
    const pts = [[nodes[a].x, nodes[a].z], ...ch.cells.map(centre), [nodes[b].x, nodes[b].z]];
    const simple = simplifyLine(pts, SIMPLIFY);
    // Split long runs so a start point never snaps to a far node.
    const runs = [simple[0]];
    for (let k = 1; k < simple.length; k++) {
      const [x0, z0] = simple[k - 1];
      const [x1, z1] = simple[k];
      const n = Math.max(1, Math.ceil(Math.hypot(x1 - x0, z1 - z0) / MAX_EDGE));
      for (let s = 1; s <= n; s++) runs.push([x0 + ((x1 - x0) * s) / n, z0 + ((z1 - z0) * s) / n]);
    }
    const clearances = ch.cells.map((c) => Math.sqrt(d2[c]) * cell).sort((x, y) => x - y);
    const median = clearances.length ? clearances[Math.floor(clearances.length / 2)] : clearAt(clusters[ch.a]);
    const w = Math.round(Math.min(30, Math.max(0.6, 2 * median)) * 10) / 10;
    const ids = [a];
    for (let k = 1; k < runs.length - 1; k++) {
      ids.push(nodes.length);
      nodes.push({ x: runs[k][0], z: runs[k][1] });
    }
    ids.push(b);
    const mine = [];
    for (let k = 1; k < ids.length; k++) {
      if (ids[k - 1] === ids[k]) continue;
      mine.push(edges.length);
      edges.push({ a: ids[k - 1], b: ids[k], w, chain: chainId });
    }
    chainEdges.push(mine);
    chainPoints.push(runs);
  });
  return { skel, nodes, edges, cellChain, chainEdges, cells: cells.filter((c) => skel[c]) };
}
