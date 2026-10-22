// The 3D map preview (Round 17, US-036): a three.js scene beside the 2D editor.
// Preview only: editing stays in 2D. Drag to turn, wheel to zoom, right-drag to
// slide; resetView() frames the map again. Without WebGL a flat outline preview
// is drawn instead, with a note (US-036 fallback). Everything is served from the
// app (three.js 0.186.1, MIT, in ./three).

import * as THREE from './three/three.module.js';
import { OrbitControls } from './three/OrbitControls.js';
import { buildModel } from './model.js';

const RISE_MS = 900;

function reducedMotion() {
  return typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
}

function webglAvailable() {
  try {
    const c = document.createElement('canvas');
    return Boolean(c.getContext('webgl2') || c.getContext('webgl'));
  } catch {
    return false;
  }
}

/** A name label as a sprite with a soft pill behind the text. */
function labelSprite(text, color, background, opacity) {
  const pad = 18;
  const font = '600 44px Manrope, system-ui, sans-serif';
  const probe = document.createElement('canvas').getContext('2d');
  probe.font = font;
  const w = Math.ceil(probe.measureText(text).width) + pad * 2;
  const h = 72;
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = background;
  ctx.globalAlpha = 0.82;
  const r = 20;
  ctx.beginPath();
  ctx.moveTo(r, 0);
  ctx.arcTo(w, 0, w, h, r);
  ctx.arcTo(w, h, 0, h, r);
  ctx.arcTo(0, h, 0, 0, r);
  ctx.arcTo(0, 0, w, 0, r);
  ctx.fill();
  ctx.globalAlpha = 1;
  ctx.font = font;
  ctx.fillStyle = color;
  ctx.textBaseline = 'middle';
  ctx.fillText(text, pad, h / 2 + 2);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, opacity, depthWrite: false });
  const sprite = new THREE.Sprite(mat);
  const scale = 0.022;
  sprite.scale.set(w * scale, h * scale, 1);
  sprite.renderOrder = 10;
  return sprite;
}

function disposeTree(obj) {
  obj.traverse((o) => {
    o.geometry?.dispose?.();
    const mats = Array.isArray(o.material) ? o.material : o.material ? [o.material] : [];
    for (const m of mats) {
      m.map?.dispose?.();
      m.dispose?.();
    }
  });
}

class Preview {
  constructor(host) {
    this.host = host;
    this.groups = new Map(); // level id → { key, group }
    this.linkGroup = null;
    this.last = null;
    this.rising = [];
    this.framed = false;
    this.needsRender = true;

    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    // Round 18 (nicer 3D): filmic tone, so light falls off softly instead of clipping.
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    this.renderer.domElement.style.display = 'block';
    this.renderer.domElement.style.width = '100%';
    this.renderer.domElement.style.height = '100%';
    host.appendChild(this.renderer.domElement);

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(38, 1, 0.1, 5000);
    this.camera.position.set(40, 40, 60);

    this.hemi = new THREE.HemisphereLight(0xffffff, 0x9a9aa6, 1.25);
    this.scene.add(this.hemi);
    // A soft fill from the other side keeps the shaded faces readable.
    this.fill = new THREE.DirectionalLight(0xfff4ea, 0.45);
    this.fill.position.set(-1, 0.8, -0.6);
    this.scene.add(this.fill);
    this.sun = new THREE.DirectionalLight(0xffffff, 1.5);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(2048, 2048);
    this.sun.shadow.radius = 4;
    this.scene.add(this.sun);
    this.scene.add(this.sun.target);
    this.ground = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.ShadowMaterial({ opacity: 0.14 }));
    this.ground.rotation.x = -Math.PI / 2;
    this.ground.receiveShadow = true;
    this.scene.add(this.ground);

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = !reducedMotion();
    this.controls.dampingFactor = 0.08;
    this.controls.maxPolarAngle = Math.PI * 0.495;
    this.controls.screenSpacePanning = true;
    this.controls.addEventListener('change', () => (this.needsRender = true));

    this.resize = this.resize.bind(this);
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(host);
    this.resize();
    this.loop = this.loop.bind(this);
    this.frame = requestAnimationFrame(this.loop);
  }

  resize() {
    const w = Math.max(1, this.host.clientWidth);
    const h = Math.max(1, this.host.clientHeight);
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.needsRender = true;
  }

  loop(now) {
    this.frame = requestAnimationFrame(this.loop);
    if (this.controls.update()) this.needsRender = true;
    if (this.rising.length) {
      this.needsRender = true;
      const done = [];
      for (const r of this.rising) {
        const t = Math.min(1, (now - r.start) / RISE_MS);
        const e = 1 - Math.pow(1 - t, 3);
        r.mesh.scale.y = Math.max(0.001, e);
        r.mesh.position.y = r.base + (r.height * e) / 2;
        if (t >= 1) done.push(r);
      }
      this.rising = this.rising.filter((r) => !done.includes(r));
    }
    if (this.needsRender) {
      this.renderer.render(this.scene, this.camera);
      this.needsRender = false;
    }
  }

  /** What a box is made of: glass is clear and glossy, frames satin, walls matte. */
  boxMaterial(b) {
    if (b.material === 'glass') {
      return new THREE.MeshPhysicalMaterial({ color: b.color, roughness: 0.08, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.1, transparent: true, opacity: Math.min(b.opacity, 0.32), depthWrite: false });
    }
    if (b.material === 'frame') {
      return new THREE.MeshStandardMaterial({ color: b.color, roughness: 0.45, metalness: 0.35, transparent: b.opacity < 1, opacity: b.opacity, depthWrite: b.opacity >= 1 });
    }
    return new THREE.MeshStandardMaterial({ color: b.color, roughness: 0.86, metalness: 0.02, transparent: b.opacity < 1, opacity: b.opacity, depthWrite: b.opacity >= 1 });
  }

  levelGroup(level, colors, animate) {
    const group = new THREE.Group();
    const boxGeo = new THREE.BoxGeometry(1, 1, 1);
    // Thin edge lines on solid walls keep the shapes crisp from far away.
    const edgeGeo = new THREE.EdgesGeometry(boxGeo);
    const edgeMat = new THREE.LineBasicMaterial({ color: colors.wallEdge ?? '#000000', transparent: true, opacity: 0.22 });
    for (const b of level.boxes) {
      const mesh = new THREE.Mesh(boxGeo, this.boxMaterial(b));
      mesh.scale.set(b.sx, b.sy, b.sz);
      mesh.position.set(b.x, b.y, b.z);
      mesh.rotation.y = b.rotY;
      mesh.castShadow = b.opacity >= 1 && b.material !== 'glass';
      mesh.receiveShadow = b.material !== 'glass';
      if (b.material === 'wall' && b.opacity >= 1) mesh.add(new THREE.LineSegments(edgeGeo, edgeMat));
      group.add(mesh);
      if (animate && b.rise) {
        const base = b.y - b.sy / 2;
        mesh.scale.y = 0.001;
        mesh.position.y = base;
        this.rising.push({ mesh, base, height: b.sy, start: performance.now() });
      }
    }
    for (const f of level.floors) {
      const shape = new THREE.Shape(f.points.map(([x, z]) => new THREE.Vector2(x, -z)));
      for (const h of f.holes ?? []) if (h.length >= 3) shape.holes.push(new THREE.Path(h.map(([x, z]) => new THREE.Vector2(x, -z))));
      const geo = new THREE.ShapeGeometry(shape);
      // Corridors and atria a little glossy (a polished mall floor), rooms matte.
      const gloss = f.finish === 'gloss';
      const mat = new THREE.MeshStandardMaterial({ color: f.color, roughness: gloss ? 0.32 : 0.95, metalness: gloss ? 0.06 : 0, transparent: f.opacity < 1, opacity: f.opacity, side: THREE.DoubleSide, depthWrite: f.opacity >= 1, polygonOffset: true, polygonOffsetFactor: f.slab ? 1 : -1 });
      const mesh = new THREE.Mesh(geo, mat);
      mesh.rotation.x = -Math.PI / 2;
      mesh.position.y = f.y;
      mesh.receiveShadow = true;
      group.add(mesh);
      // A fine edge line around each room.
      if (f.edge && f.points.length >= 3) {
        const pts = [...f.points, f.points[0]].map(([x, z]) => new THREE.Vector3(x, f.y + 0.01, z));
        group.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), new THREE.LineBasicMaterial({ color: f.edge, transparent: true, opacity: 0.55 * f.opacity })));
      }
    }
    for (const l of level.labels) {
      const s = labelSprite(l.text, l.color, colors.labelBg ?? '#ffffff', l.opacity);
      s.position.set(l.x, l.y, l.z);
      group.add(s);
    }
    return group;
  }

  update(json) {
    let input;
    try {
      input = JSON.parse(json);
    } catch {
      return;
    }
    const colors = input.colors ?? {};
    this.scene.background = new THREE.Color(colors.background ?? '#f4f5f7');
    const model = buildModel(input);
    const animate = !reducedMotion();
    const seen = new Set();
    for (const level of model.levels) {
      seen.add(level.id);
      const old = this.groups.get(level.id);
      if (old && old.key === level.key) continue;
      if (old) {
        this.scene.remove(old.group);
        disposeTree(old.group);
      }
      // Proposal pieces rise only when the proposal itself is new.
      const group = this.levelGroup(level, colors, animate && input.proposalKey !== this.lastProposal);
      this.scene.add(group);
      this.groups.set(level.id, { key: level.key, group });
    }
    this.lastProposal = input.proposalKey;
    for (const [id, g] of this.groups) {
      if (seen.has(id)) continue;
      this.scene.remove(g.group);
      disposeTree(g.group);
      this.groups.delete(id);
    }
    if (this.linkGroup) {
      this.scene.remove(this.linkGroup);
      disposeTree(this.linkGroup);
    }
    this.linkGroup = new THREE.Group();
    for (const l of model.links) {
      const geo = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(...l.a), new THREE.Vector3(...l.b)]);
      this.linkGroup.add(new THREE.Line(geo, new THREE.LineBasicMaterial({ color: l.color, transparent: true, opacity: Math.max(0.35, l.opacity) })));
    }
    this.scene.add(this.linkGroup);
    this.bounds = model.bounds;
    this.placeLightAndGround();
    if (!this.framed) {
      this.resetView();
      this.framed = true;
    }
    this.needsRender = true;
  }

  placeLightAndGround() {
    const { min, max } = this.bounds;
    const cx = (min[0] + max[0]) / 2;
    const cz = (min[2] + max[2]) / 2;
    const size = Math.max(max[0] - min[0], max[2] - min[2], 10);
    this.ground.position.set(cx, Math.min(0, min[1]) - 0.01, cz);
    this.ground.scale.set(size * 3, size * 3, 1);
    this.sun.position.set(cx + size * 0.6, size * 1.2, cz + size * 0.8);
    this.sun.target.position.set(cx, 0, cz);
    const cam = this.sun.shadow.camera;
    cam.left = -size;
    cam.right = size;
    cam.top = size;
    cam.bottom = -size;
    cam.near = 0.5;
    cam.far = size * 4;
    cam.updateProjectionMatrix();
  }

  resetView() {
    if (!this.bounds) return;
    const { min, max } = this.bounds;
    const centre = new THREE.Vector3((min[0] + max[0]) / 2, (min[1] + max[1]) / 2, (min[2] + max[2]) / 2);
    const size = Math.max(max[0] - min[0], max[2] - min[2], (max[1] - min[1]) * 2, 10);
    const dist = size / (2 * Math.tan((this.camera.fov * Math.PI) / 360)) * 1.15;
    this.controls.target.copy(centre);
    this.camera.position.set(centre.x + dist * 0.55, centre.y + dist * 0.62, centre.z + dist * 0.75);
    this.camera.near = Math.max(0.05, dist / 500);
    this.camera.far = dist * 20;
    this.camera.updateProjectionMatrix();
    this.controls.update();
    this.needsRender = true;
  }

  dispose() {
    cancelAnimationFrame(this.frame);
    this.observer.disconnect();
    this.controls.dispose();
    for (const g of this.groups.values()) disposeTree(g.group);
    if (this.linkGroup) disposeTree(this.linkGroup);
    this.renderer.dispose();
    this.renderer.domElement.remove();
  }
}

/** Without WebGL: the levels' outlines and walls drawn flat, top-down, with a note. */
class FlatPreview {
  constructor(host) {
    this.host = host;
    this.canvas = document.createElement('canvas');
    this.canvas.style.width = '100%';
    this.canvas.style.height = '100%';
    this.canvas.style.display = 'block';
    host.appendChild(this.canvas);
    this.note = document.createElement('div');
    this.note.textContent = '3D needs WebGL; showing a flat preview.';
    Object.assign(this.note.style, { position: 'absolute', left: '10px', bottom: '10px', font: '12px Manrope, system-ui, sans-serif', opacity: '0.75' });
    host.style.position = 'relative';
    host.appendChild(this.note);
    this.observer = new ResizeObserver(() => this.draw());
    this.observer.observe(host);
  }

  update(json) {
    try {
      this.input = JSON.parse(json);
    } catch {
      return;
    }
    this.draw();
  }

  draw() {
    if (!this.input) return;
    const model = buildModel(this.input);
    const colors = this.input.colors ?? {};
    const w = Math.max(1, this.host.clientWidth);
    const h = Math.max(1, this.host.clientHeight);
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = w * dpr;
    this.canvas.height = h * dpr;
    const ctx = this.canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = colors.background ?? '#f4f5f7';
    ctx.fillRect(0, 0, w, h);
    const { min, max } = model.bounds;
    const s = Math.min((w - 40) / Math.max(1, max[0] - min[0]), (h - 40) / Math.max(1, max[2] - min[2]));
    const X = (x) => 20 + (x - min[0]) * s;
    const Z = (z) => 20 + (z - min[2]) * s;
    for (const level of model.levels) {
      ctx.globalAlpha = level.opacity;
      for (const f of level.floors) {
        ctx.fillStyle = f.color;
        ctx.beginPath();
        f.points.forEach(([x, z], i) => (i ? ctx.lineTo(X(x), Z(z)) : ctx.moveTo(X(x), Z(z))));
        ctx.closePath();
        ctx.fill();
      }
      for (const b of level.boxes) {
        ctx.save();
        ctx.translate(X(b.x), Z(b.z));
        ctx.rotate(-b.rotY);
        ctx.fillStyle = b.color;
        ctx.fillRect((-b.sx * s) / 2, (-b.sz * s) / 2, b.sx * s, Math.max(1, b.sz * s));
        ctx.restore();
      }
    }
    ctx.globalAlpha = 1;
  }

  resetView() {
    this.draw();
  }

  dispose() {
    this.observer.disconnect();
    this.canvas.remove();
    this.note.remove();
  }
}

/** Starts a preview in the host element. */
export function createPreview(host) {
  return webglAvailable() ? new Preview(host) : new FlatPreview(host);
}
