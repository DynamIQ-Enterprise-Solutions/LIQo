// Uploaded plan pictures: the real type comes from the bytes, the size from the header.
// (The raster wall detector and its tests were removed in Round 15: the owner
// replaced "Detect" with AI reading, see ai_reading.test.js and floorplan.test.js.)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PNG } from 'pngjs';
import jpeg from 'jpeg-js';
import { decodeImage, imageSize, sniffMime } from '../src/maps/image.js';

function png(w, h) {
  const p = new PNG({ width: w, height: h });
  p.data.fill(255);
  return PNG.sync.write(p);
}

test('sniff and size: PNG', () => {
  const buf = png(2000, 1400);
  assert.equal(sniffMime(buf), 'image/png');
  assert.deepEqual(imageSize(buf, 'image/png'), { width: 2000, height: 1400 });
  const img = decodeImage(buf, 'image/png');
  assert.equal(img.width, 2000);
  assert.equal(img.data.length, 2000 * 1400 * 4);
});

test('sniff and size: JPEG', () => {
  const raw = { width: 320, height: 200, data: Buffer.alloc(320 * 200 * 4, 255) };
  const buf = jpeg.encode(raw, 80).data;
  assert.equal(sniffMime(buf), 'image/jpeg');
  assert.deepEqual(imageSize(buf, 'image/jpeg'), { width: 320, height: 200 });
});

test('anything else is not an image, whatever its name', () => {
  assert.equal(sniffMime(Buffer.from('%PDF-1.7\n')), null);
  assert.equal(sniffMime(Buffer.from('GIF89a')), null);
});
