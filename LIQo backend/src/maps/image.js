// Uploaded floor-plan pictures: type sniffing, header size and decoding to RGBA.
// (Until Round 15 this file also held a raster wall detector; the owner replaced
// it with AI reading, see src/ai/floorplan.js.)

import { PNG } from 'pngjs';
import jpeg from 'jpeg-js';

export function decodeImage(buffer, mime) {
  if (mime === 'image/png') {
    const png = PNG.sync.read(buffer);
    return { width: png.width, height: png.height, data: png.data, channels: 4 };
  }
  if (mime === 'image/jpeg') {
    const j = jpeg.decode(buffer, { useTArray: true, formatAsRGBA: true, maxMemoryUsageInMB: 1024 });
    return { width: j.width, height: j.height, data: j.data, channels: 4 };
  }
  throw new Error(`unsupported image type ${mime}`);
}

/** Reads width/height from the header only (cheap; used at upload). */
export function imageSize(buffer, mime) {
  if (mime === 'image/png') {
    if (buffer.length < 24) throw new Error('not a PNG');
    return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
  }
  if (mime === 'image/jpeg') {
    let i = 2;
    while (i < buffer.length) {
      if (buffer[i] !== 0xff) throw new Error('not a JPEG');
      const marker = buffer[i + 1];
      const len = buffer.readUInt16BE(i + 2);
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
        return { height: buffer.readUInt16BE(i + 5), width: buffer.readUInt16BE(i + 7) };
      }
      i += 2 + len;
    }
    throw new Error('JPEG size not found');
  }
  throw new Error('unsupported image type');
}

/** Sniffs the real type from the first bytes, never from the filename. */
export function sniffMime(buffer) {
  if (buffer.length >= 8 && buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47) return 'image/png';
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'image/jpeg';
  return null;
}
