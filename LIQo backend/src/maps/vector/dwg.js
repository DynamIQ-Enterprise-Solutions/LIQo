// DWG floor plans (Round 16, owner decision: ODA File Converter on our server).
// DWG is AutoCAD's closed format, so the converter turns it into a DXF in a
// temporary folder, and the DXF reader takes it from there. The converter runs
// without a shell, with a time limit, and its folder is always removed.

import { execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { config } from '../../config.js';

export class DwgError extends Error {}

const TIMEOUT_MS = 3 * 60_000;

/** DWG files start with "AC10" and two more digits (the version). */
export function looksLikeDwg(buf) {
  return buf.length > 6 && /^AC10\d\d/.test(buf.subarray(0, 6).toString('latin1'));
}

export function dwgSupported() {
  return Boolean(config.oda.converter);
}

/** DWG bytes → DXF bytes, through ODA File Converter. */
export async function dwgToDxf(buffer) {
  if (!dwgSupported()) throw new DwgError('DWG support is not installed on the server yet. Save the drawing as DXF or PDF in AutoCAD and upload that.');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'liqo-dwg-'));
  const inDir = path.join(dir, 'in');
  const outDir = path.join(dir, 'out');
  fs.mkdirSync(inDir);
  fs.mkdirSync(outDir);
  try {
    fs.writeFileSync(path.join(inDir, 'plan.dwg'), buffer);
    // ODAFileConverter <input folder> <output folder> <version> <type> <recurse> <audit> [filter]
    const args = [inDir, outDir, 'ACAD2018', 'DXF', '0', '1', '*.DWG'];
    // A .js converter (the tests' stand-in) runs through Node; the real one is an executable.
    const [cmd, argv] = /\.m?js$/i.test(config.oda.converter) ? [process.execPath, [config.oda.converter, ...args]] : [config.oda.converter, args];
    await new Promise((resolve, reject) => {
      execFile(cmd, argv, { timeout: TIMEOUT_MS, windowsHide: true, maxBuffer: 4 * 1024 * 1024 }, (err) => {
        if (err?.killed) reject(new DwgError('Converting the DWG took too long. Save it as DXF in AutoCAD and upload that.'));
        else if (err && err.code === 'ENOENT') reject(new DwgError('The DWG converter was not found on the server. Ask a superadmin to check ODA_FILE_CONVERTER.'));
        else resolve();
      });
    });
    const out = fs.readdirSync(outDir).find((f) => f.toLowerCase().endsWith('.dxf'));
    if (!out) throw new DwgError('The DWG could not be converted. It may be damaged, or from a newer AutoCAD than the converter knows. Save it as DXF and upload that.');
    return fs.readFileSync(path.join(outDir, out));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
