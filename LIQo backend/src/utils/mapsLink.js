// A branch's location from a pasted Google Maps link (Round 21, owner decision
// 2026-10-23): full links are read as they are; short maps.app.goo.gl /
// goo.gl/maps links are followed once on the server (no other hosts, short
// timeout). The pin and the place's name are read from the link; the name is
// shown back to the admin to confirm. The numbers stay off the screens.

const SHORT_HOSTS = new Set(['maps.app.goo.gl', 'goo.gl']);
const isGoogleHost = (h) => /(^|\.)google\.[a-z.]{2,6}$/.test(h);

/** The fetch used to follow short links; tests replace it. */
let fetchImpl = (url, init) => fetch(url, init);
export function setFetchForTests(fn) {
  fetchImpl = fn ?? ((url, init) => fetch(url, init));
}

export class MapsLinkError extends Error {}

function parseUrl(text) {
  let u;
  try {
    u = new URL(String(text).trim());
  } catch {
    throw new MapsLinkError('Paste the whole Google Maps link (it starts with https://).');
  }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') throw new MapsLinkError('Paste the whole Google Maps link (it starts with https://).');
  return u;
}

const inRange = (lat, lng) => Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
const round6 = (v) => Math.round(v * 1e6) / 1e6;

/** Reads the pin and place name from a full Google Maps URL, or null when it has no pin. */
export function readGoogleMapsUrl(u) {
  const href = decodeURIComponent(u.href);
  // The place's own pin (!3d<lat>!4d<lng>) wins over the view centre (@lat,lng).
  const candidates = [
    /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/,
    /@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/,
  ];
  let lat = null;
  let lng = null;
  for (const re of candidates) {
    const m = re.exec(href);
    if (m && inRange(Number(m[1]), Number(m[2]))) {
      lat = Number(m[1]);
      lng = Number(m[2]);
      break;
    }
  }
  if (lat == null) {
    for (const key of ['q', 'query', 'll', 'destination']) {
      const m = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(u.searchParams.get(key) ?? '');
      if (m && inRange(Number(m[1]), Number(m[2]))) {
        lat = Number(m[1]);
        lng = Number(m[2]);
        break;
      }
    }
  }
  if (lat == null) return null;
  const place = /\/maps\/place\/([^/@]+)/.exec(u.pathname);
  let placeName = place ? decodeURIComponent(place[1].replace(/\+/g, ' ')).trim() : null;
  if (!placeName) {
    const q = u.searchParams.get('q') ?? u.searchParams.get('query');
    if (q && !/^\s*-?\d/.test(q)) placeName = q.trim();
  }
  return { latitude: round6(lat), longitude: round6(lng), placeName: placeName ? placeName.slice(0, 200) : null };
}

/**
 * Resolves a pasted link to { mapsLink, latitude, longitude, placeName }.
 * Throws MapsLinkError with a plain message when it is not a usable Google Maps link.
 */
export async function resolveMapsLink(text) {
  const u = parseUrl(text);
  const host = u.hostname.toLowerCase();
  let target = u;
  if (SHORT_HOSTS.has(host)) {
    if (host === 'goo.gl' && !u.pathname.startsWith('/maps')) throw new MapsLinkError('That is not a Google Maps link.');
    let res;
    try {
      res = await fetchImpl(u.href, { method: 'GET', redirect: 'manual', signal: AbortSignal.timeout(5000) });
    } catch {
      throw new MapsLinkError('Google Maps did not answer. Try again, or paste the full link from the address bar.');
    }
    const location = res.headers.get('location');
    if (!location) throw new MapsLinkError('That short link does not lead to a place. Paste the full link from the address bar.');
    target = parseUrl(new URL(location, u.href).href);
    if (!isGoogleHost(target.hostname.toLowerCase())) throw new MapsLinkError('That short link does not lead to Google Maps.');
  } else if (!isGoogleHost(host)) {
    throw new MapsLinkError('That is not a Google Maps link.');
  }
  const found = readGoogleMapsUrl(target);
  if (!found) throw new MapsLinkError('That link has no pin. In Google Maps, open the place itself, then copy its link.');
  return { mapsLink: u.href.slice(0, 500), ...found };
}
