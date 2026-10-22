three.js 0.186.1 (MIT), bundled for the 3D map preview (Round 17, US-036).
OrbitControls.js imports ./three.module.js instead of the bare "three" specifier,
so no import map is needed. Nothing is loaded from outside.
