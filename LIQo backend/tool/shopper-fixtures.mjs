// Writes the published shopper-package fixtures the mobile app's loader test
// reads (Round 21, P1-08; agreed with the mobile session 2026-10-23):
//   LIQo mobile/test/fixtures/published/<name>.json         the package, as served
//   LIQo mobile/test/fixtures/published/<name>.expect.json  what the phone must find
// `node tool/shopper-fixtures.mjs` rewrites them; `--check` only compares (the
// backend test runs that, so a builder change without new fixtures fails).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildShopperPackage, stampPackage } from '../src/maps/shopper/build.js';
import { fixtures, routes } from '../test/support/shopper_layouts.js';

const DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../LIQo mobile/test/fixtures/published');
const PUBLISHED_AT = '2026-10-23T10:00:00+08:00';
const round = (v) => Math.round(v * 1e6) / 1e6;

/** Every fixture: { name: { json, expect } } as text. */
export function buildFixtures() {
  const out = {};
  for (const [name, f] of Object.entries(fixtures())) {
    const r = buildShopperPackage({ layout: f.layout, links: f.links, appCategories: f.appCategories, branchId: 12, branchName: 'Fixture branch', mallName: 'LIQo fixtures' });
    if (r.problems.length) throw new Error(`fixture ${name}: ${r.problems.map((p) => p.message).join('; ')}`);
    const { json } = stampPackage(r.package, { version: 1, publishedAt: PUBLISHED_AT });
    const pkg = JSON.parse(json);
    const from = pkg.exits[0].node;
    const dist = routes(pkg, from);
    const wheel = routes(pkg, from, { avoidThrough: true, minWidth: 1.2 });
    const best = (d, p) => {
      const xs = p.nodes.filter((n) => d.has(n)).map((n) => d.get(n));
      return xs.length ? Math.min(...xs) : null;
    };
    const totals = {};
    for (const p of pkg.places) {
      const t = best(dist, p);
      if (t != null) totals[p.id] = round(t);
    }
    const expect = {
      note: 'Built by LIQo backend/tool/shopper-fixtures.mjs. Routes start at exits[0].node; totals are the cheapest route cost to any of the place nodes (cost when present, else node distance; hops cost as in kit_venue.dart hopCostFor).',
      from,
      nodeCount: pkg.graph.nodes.length,
      reachable: Object.keys(totals).sort(),
      totals,
      oneWay: pkg.graph.edges.filter((e) => e.oneWay).map((e) => [e.a, e.b]),
      wheelchairUnreachable: pkg.places.filter((p) => best(wheel, p) == null && best(dist, p) != null).map((p) => p.id).sort(),
    };
    out[name] = { json, expect: `${JSON.stringify(expect, null, 2)}\n` };
  }
  return out;
}

/** Files that differ from what the builder makes now (empty when all up to date). */
export function staleFixtures() {
  const stale = [];
  for (const [name, f] of Object.entries(buildFixtures())) {
    for (const [file, text] of [[`${name}.json`, f.json], [`${name}.expect.json`, f.expect]]) {
      const p = path.join(DIR, file);
      if (!fs.existsSync(p) || fs.readFileSync(p, 'utf8') !== text) stale.push(file);
    }
  }
  return stale;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--check')) {
    const stale = staleFixtures();
    console.log(stale.length ? `stale: ${stale.join(', ')}` : 'fixtures up to date');
    process.exit(stale.length ? 1 : 0);
  }
  fs.mkdirSync(DIR, { recursive: true });
  for (const [name, f] of Object.entries(buildFixtures())) {
    fs.writeFileSync(path.join(DIR, `${name}.json`), f.json);
    fs.writeFileSync(path.join(DIR, `${name}.expect.json`), f.expect);
    console.log(`wrote ${name}`);
  }
}
