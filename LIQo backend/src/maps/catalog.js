// Placeable mall features. Served to the editor; the editor keeps no copy.
// size = [w, d, h] metres. resize lists the dimensions a user may change and their range.
// blocks: people walk around it. target: can be a navigation destination (POI).

export const CATALOG_VERSION = 1;

export const CATEGORIES = ['access', 'facilities', 'safety', 'services', 'furniture', 'structure', 'generic'];

export const FEATURE_TYPES = Object.freeze({
  entrance: { category: 'access', label: 'Entrance', size: [3, 0.5, 2.5], resize: { w: [1, 20] }, blocks: false, target: true, icon: 'door' },
  exit: { category: 'access', label: 'Exit', size: [2, 0.5, 2.5], resize: { w: [1, 10] }, blocks: false, target: true, icon: 'exit' },
  parking_entrance: { category: 'access', label: 'Parking entrance', size: [4, 1, 3], resize: { w: [2, 12] }, blocks: false, target: true, icon: 'parking' },
  taxi_bay: { category: 'access', label: 'Taxi bay', size: [6, 2.5, 0.1], resize: { w: [3, 30], d: [2, 6] }, blocks: false, target: true, icon: 'taxi' },
  bus_stop: { category: 'access', label: 'Bus stop', size: [4, 1.5, 2.5], resize: { w: [2, 20] }, blocks: false, target: true, icon: 'bus' },

  restroom: { category: 'facilities', label: 'Restroom', size: [1, 1, 2.2], resize: null, blocks: false, target: true, icon: 'wc', props: { gender: ['all', 'male', 'female', 'pwd', 'family'] } },
  prayer_room: { category: 'facilities', label: 'Prayer room', size: [1, 1, 2.2], resize: null, blocks: false, target: true, icon: 'prayer' },
  nursing_room: { category: 'facilities', label: 'Nursing room', size: [1, 1, 2.2], resize: null, blocks: false, target: true, icon: 'baby' },
  water_fountain: { category: 'facilities', label: 'Drinking fountain', size: [0.5, 0.4, 1], resize: null, blocks: true, target: true, icon: 'water' },
  charging_station: { category: 'facilities', label: 'Charging station', size: [0.6, 0.4, 1.2], resize: null, blocks: true, target: true, icon: 'charge' },
  locker: { category: 'facilities', label: 'Lockers', size: [2, 0.5, 1.8], resize: { w: [0.5, 10] }, blocks: true, target: true, icon: 'locker' },
  trash_bin: { category: 'facilities', label: 'Trash bin', size: [0.5, 0.5, 0.9], resize: null, blocks: true, target: false, icon: 'trash' },

  fire_exit: { category: 'safety', label: 'Fire exit', size: [1.2, 0.3, 2.2], resize: { w: [0.8, 3] }, blocks: false, target: true, icon: 'fire_exit' },
  fire_extinguisher: { category: 'safety', label: 'Fire extinguisher', size: [0.3, 0.3, 0.6], resize: null, blocks: false, target: false, icon: 'extinguisher' },
  fire_hose: { category: 'safety', label: 'Fire hose cabinet', size: [0.8, 0.3, 1], resize: null, blocks: false, target: false, icon: 'hose' },
  assembly_point: { category: 'safety', label: 'Assembly point', size: [4, 4, 0.1], resize: { w: [2, 40], d: [2, 40] }, blocks: false, target: true, icon: 'assembly' },
  first_aid: { category: 'safety', label: 'First aid', size: [0.6, 0.3, 0.6], resize: null, blocks: false, target: true, icon: 'first_aid' },
  aed: { category: 'safety', label: 'AED', size: [0.4, 0.2, 0.5], resize: null, blocks: false, target: true, icon: 'aed' },
  security: { category: 'safety', label: 'Security post', size: [1.5, 1.5, 2.2], resize: { w: [1, 4], d: [1, 4] }, blocks: true, target: true, icon: 'security' },

  info_desk: { category: 'services', label: 'Information desk', size: [2.5, 1, 1.1], resize: { w: [1, 8] }, blocks: true, target: true, icon: 'info' },
  customer_service: { category: 'services', label: 'Customer service', size: [3, 1, 1.1], resize: { w: [1, 10] }, blocks: true, target: true, icon: 'service' },
  atm: { category: 'services', label: 'ATM', size: [0.8, 0.6, 1.8], resize: null, blocks: true, target: true, icon: 'atm', props: { bank: 'text' } },
  kiosk: { category: 'services', label: 'Kiosk', size: [2, 2, 2.2], resize: { w: [1, 6], d: [1, 6] }, blocks: true, target: true, icon: 'kiosk' },
  directory_sign: { category: 'services', label: 'Directory sign', size: [0.8, 0.2, 2], resize: null, blocks: true, target: true, icon: 'sign' },
  lost_found: { category: 'services', label: 'Lost and found', size: [1.5, 1, 1.1], resize: null, blocks: true, target: true, icon: 'lost_found' },
  concierge: { category: 'services', label: 'Concierge', size: [2, 1, 1.1], resize: { w: [1, 6] }, blocks: true, target: true, icon: 'concierge' },

  seating: { category: 'furniture', label: 'Seating', size: [1.8, 0.6, 0.45], resize: { w: [0.5, 10], d: [0.4, 3] }, blocks: true, target: false, icon: 'seat' },
  planter: { category: 'furniture', label: 'Planter', size: [1, 1, 0.8], resize: { w: [0.3, 10], d: [0.3, 10] }, blocks: true, target: false, icon: 'plant' },
  fountain: { category: 'furniture', label: 'Fountain', size: [4, 4, 1], resize: { w: [1, 20], d: [1, 20] }, blocks: true, target: true, icon: 'fountain' },
  stage: { category: 'furniture', label: 'Event stage', size: [8, 5, 0.8], resize: { w: [2, 30], d: [2, 20] }, blocks: true, target: true, icon: 'stage' },
  play_area: { category: 'furniture', label: 'Play area', size: [5, 5, 0.1], resize: { w: [2, 30], d: [2, 30] }, blocks: false, target: true, icon: 'play' },

  column: { category: 'structure', label: 'Column', size: [0.8, 0.8, 4], resize: { w: [0.2, 3], d: [0.2, 3] }, blocks: true, target: false, icon: 'column' },
  railing: { category: 'structure', label: 'Railing', size: [4, 0.1, 1.1], resize: { w: [0.5, 50] }, blocks: true, target: false, icon: 'railing' },
  void_guard: { category: 'structure', label: 'Void guard', size: [4, 0.1, 1.1], resize: { w: [0.5, 50] }, blocks: true, target: false, icon: 'railing' },

  generic_box: { category: 'generic', label: 'Generic block', size: [1, 1, 1], resize: { w: [0.1, 50], d: [0.1, 50], h: [0.1, 20] }, blocks: true, target: false, icon: 'box' },
  generic_marker: { category: 'generic', label: 'Marker (point of interest)', size: [0.5, 0.5, 0.5], resize: null, blocks: false, target: true, icon: 'pin' },
});

export const SPACE_TYPES = ['retail', 'food', 'anchor', 'service', 'office', 'storage', 'atrium', 'corridor', 'restroom', 'parking', 'outdoor', 'custom'];

export const WALL_KINDS = ['solid', 'glass', 'partition', 'boundary'];

export const OPENING_KINDS = ['door', 'entrance', 'window', 'gate', 'passage', 'shutter'];

export const CONNECTOR_KINDS = ['stairs', 'escalator', 'elevator', 'ramp', 'moving_walkway', 'bridge', 'walkway', 'vehicle_ramp'];

/** Connector kinds that only move people in one direction (first endpoint → second). */
export const ONE_WAY_CAPABLE = ['escalator', 'moving_walkway', 'ramp', 'vehicle_ramp'];

export function catalogPayload() {
  return {
    version: CATALOG_VERSION,
    categories: CATEGORIES,
    features: FEATURE_TYPES,
    spaceTypes: SPACE_TYPES,
    wallKinds: WALL_KINDS,
    openingKinds: OPENING_KINDS,
    connectorKinds: CONNECTOR_KINDS,
    oneWayCapable: ONE_WAY_CAPABLE,
  };
}
