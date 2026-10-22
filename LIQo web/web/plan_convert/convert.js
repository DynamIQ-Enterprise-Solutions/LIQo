// Round 16: turns plan pictures the server does not take (TIFF, WebP, BMP, GIF,
// HEIC) into a PNG in the browser, before upload. Everything here is served
// from this folder; nothing is loaded from outside.
//   WebP, BMP, GIF: the browser decodes them itself (the first frame of a GIF).
//   TIFF: UTIF.js (MIT) with pako (MIT).
//   HEIC: libheif-js (LGPL-3.0, unmodified; licence texts beside it).

const here = new URL('./', import.meta.url);

// The server's limits for a plan picture.
const MAX_SIDE = 10000;
const MAX_PIXELS = 50000000;

function loadScript(name) {
  return new Promise((resolve, reject) => {
    const src = new URL(name, here).href;
    if (document.querySelector(`script[data-plan-convert="${name}"]`)) return resolve();
    const s = document.createElement('script');
    s.src = src;
    s.async = true;
    s.dataset.planConvert = name;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error(`could not load ${name}`));
    document.head.appendChild(s);
  });
}

/** A canvas holding the picture, shrunk to the server's limits when needed. */
function fitCanvas(width, height) {
  let scale = Math.min(1, MAX_SIDE / Math.max(width, height));
  if (width * height * scale * scale > MAX_PIXELS) scale = Math.sqrt(MAX_PIXELS / (width * height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.floor(width * scale));
  canvas.height = Math.max(1, Math.floor(height * scale));
  const ctx = canvas.getContext('2d');
  // Paper white under transparent parts.
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  return { canvas, ctx, scale };
}

function pngOf(canvas) {
  return new Promise((resolve, reject) => {
    canvas.toBlob(async (blob) => {
      if (!blob) return reject(new Error('The picture could not be turned into a PNG.'));
      resolve(new Uint8Array(await blob.arrayBuffer()));
    }, 'image/png');
  });
}

/** Raw RGBA pixels → PNG, through a full-size canvas then the fitted one. */
async function rgbaToPng(rgba, width, height) {
  const full = document.createElement('canvas');
  full.width = width;
  full.height = height;
  full.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(rgba.buffer, rgba.byteOffset, width * height * 4), width, height), 0, 0);
  const { canvas, ctx } = fitCanvas(width, height);
  ctx.drawImage(full, 0, 0, canvas.width, canvas.height);
  return pngOf(canvas);
}

async function viaBrowser(bytes, type) {
  const bitmap = await createImageBitmap(new Blob([bytes], { type }));
  const { canvas, ctx } = fitCanvas(bitmap.width, bitmap.height);
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close?.();
  return pngOf(canvas);
}

async function viaUtif(bytes) {
  await loadScript('pako.min.js');
  await loadScript('UTIF.js');
  const UTIF = self.UTIF;
  const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const ifds = UTIF.decode(buf);
  if (!ifds.length) throw new Error('This TIFF has no picture in it.');
  // The largest page is the plan (TIFFs often carry a small preview too).
  let best = null;
  for (const ifd of ifds) {
    UTIF.decodeImage(buf, ifd);
    if (ifd.width && ifd.height && (!best || ifd.width * ifd.height > best.width * best.height)) best = ifd;
  }
  if (!best) throw new Error('This TIFF could not be read.');
  return rgbaToPng(UTIF.toRGBA8(best), best.width, best.height);
}

let heif = null;
async function viaLibheif(bytes) {
  if (!heif) {
    const mod = await import(new URL('libheif.esm.js', here).href);
    let lib = mod.default();
    if (lib && typeof lib.then === 'function') lib = await lib;
    heif = lib;
  }
  const images = new heif.HeifDecoder().decode(bytes);
  if (!images?.length) throw new Error('This HEIC photo could not be read.');
  const image = images[0];
  const width = image.get_width();
  const height = image.get_height();
  const out = new ImageData(width, height);
  await new Promise((resolve, reject) => image.display(out, (d) => (d ? resolve() : reject(new Error('This HEIC photo could not be read.')))));
  const { canvas, ctx } = fitCanvas(width, height);
  const full = document.createElement('canvas');
  full.width = width;
  full.height = height;
  full.getContext('2d').putImageData(out, 0, 0);
  ctx.drawImage(full, 0, 0, canvas.width, canvas.height);
  return pngOf(canvas);
}

/** bytes (Uint8Array) of a picture with the given extension → PNG bytes. */
export async function toPng(bytes, ext) {
  switch (String(ext).toLowerCase()) {
    case 'webp':
      return viaBrowser(bytes, 'image/webp');
    case 'bmp':
      return viaBrowser(bytes, 'image/bmp');
    case 'gif':
      return viaBrowser(bytes, 'image/gif');
    case 'tif':
    case 'tiff':
      return viaUtif(bytes);
    case 'heic':
    case 'heif':
      return viaLibheif(bytes);
    default:
      throw new Error(`.${ext} pictures are not supported.`);
  }
}
