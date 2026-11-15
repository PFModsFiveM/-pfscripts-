// Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
// Free software under the GNU Lesser General Public License 3.0 (pf-hud/COPYING.LESSER and COPYING).
// 3D concept of the rev dial (three.js). Same layout and data as the 2D replica and, like it, open and facing the
// viewer straight on: no backing plate, trim or glass over the centre, nothing in front of the numbers. Added in 3D:
// a ring of light blades that rise with the revs, a floating needle, a rolling gear number and glass status jewels.
// Extra gauges orbit it as miniatures of the same dial (see gauges.js). The dial leans under acceleration and braking,
// kicks on shifts and shakes near the limiter. No post-processing: glows are additive meshes that leave the canvas
// alpha untouched, so the canvas can sit transparently over the game later (FiveM NUI).
//
// Cost: no lights or environment map (everything is unlit; the jewel caps carry baked shading); changing numbers are
// quads cut from a glyph atlas, so a new speed rewrites a few vertices instead of re-uploading a texture; the numerals
// and the lower meter's segments are one mesh each; blade transforms are only rewritten when they move; and a frame in which
// nothing moved is not rendered at all.
//
// Aircraft mode (s.kind === 'air', air3d.js): the rev scale, needle, speed and gear give way to an attitude indicator,
// with airspeed and altitude tapes either side; the ring stays as a plain bezel, the lights and gauges stay.
import * as THREE from 'three';
import { BOX, ICONS, FONT, drawIcon, indicatorStyle, indicatorLit, iconId, dialScale, dialValue, displaySpeed, gearLabel } from './dial.js';
import { SAT_R, drawGlyph, gaugeCritical, gaugeEnds, ENDS_X } from './gauges.js';
import { Air3D } from './air3d.js';

const DEG = Math.PI / 180;
const polar = (a, r, z = 0, out = new THREE.Vector3()) => out.set(Math.sin(a * DEG) * r, Math.cos(a * DEG) * r, z);
const GEARS = ['R', 'N', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
const BOAT_GEARS = ['R', 'N', 'F'];                           // a boat's shift: reverse, neutral, forward
const Z_AXIS = new THREE.Vector3(0, 0, 1);
const VERT_P = 'varying vec2 vP; void main(){ vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }';
// half the size of the square frame centred on the dial that the canvas box is cut from (see resize)
const EXTENT = Math.max(BOX.cx, BOX.w - BOX.cx, BOX.cy, BOX.h - BOX.cy);
const SPEED_SIZE = 0.40, SPEED_BASE = -0.185;                  // speed digits: font size and baseline (dial units); v10b: was 0.26875 / -0.06875
// UPSTREAM EDITS:
// - at the limiter the outer light pipe flashes red and white, this long (s) each;
const LIMITER_FLASH = 0.15;
// - a lit tick blade near the needle gets a dark edge, so it still reads as a line on the bright sweep behind it
//   (white on near-white, the blades from ~3k below the needle up looked unlit). The edge is the blade's own box made
//   wider, drawn under it: it leans and foreshortens with the blade. Its width each side, in dial units, at the
//   needle; it falls away with the sweep's own trail.
const BLADE_EDGE = 0.006;
// The glow (option C of the glow test, dev/glow_test.html): in daylight the see-through dial washed out, white on a bright scene. The sweep now lights only
// the blades' band and out to the ring (`inner`, dial radii; the numerals sit on the dark face), bright for a short
// tail behind the needle (`decay`) and faint further back (`base`); the needle's glow is softer; a smoked backing
// (`smoke`, opacity) under the dial and under every extra gauge keeps the white readable over any scene.
// v10: the gear sits on the hub's light ring; bigger numerals (quad half-height) and status jewels
const GEAR_Y = -0.503, NUMERAL_H = 0.12, NUMERAL_R = 0.69, JEWEL = 1.4;
// v10b: unit label scale / baseline; numerals keep NUM_GAP inside the major ticks' inner end (TICK_IN), measured on their ink
const UNIT_K = 1.35, UNIT_BASE = 0.165, TICK_IN = 0.765, NUM_GAP = 0.03;
const GLOW = Object.freeze({ inner: 0.76, base: 0.06, peak: 0.6, decay: 2.2, needle: 0.4, smoke: 0.62 });

// Skins: a theme over the same dial, e.g. a car's own GTA dashboard (skins3d.js). A skin sets colours,
// fonts and the needle's profile only; the layout, rev scale, blades, status lights, extra gauges and motion stay the
// dial's own. Colours are CSS hex; fonts are a family (null: the dial's Roboto) plus CSS style/weight prefixes.
// DEFAULT_SKIN is the dial as designed. Hud3D.setSkin(skin) takes any subset of it.
export const DEFAULT_SKIN = Object.freeze({
  id: 'pf', name: 'pf',
  face: '#05070a', faceAlpha: GLOW.smoke,                   // the backing disc under the dial and each extra gauge
  family: null, numeralFont: 'italic 700', speedFont: '900', unitFont: '500', gearFont: 'italic 500', speedFit: 1,
  numeral: '#ffffff', numeralOff: '#8d929b', numeralRed: '#ff6a7e', numeralRedOff: '#e8394f', numeralBack: '#3a3e46',
  tick: '#ffffff', tickOld: '#9aa0a8', tickOff: '#30333a', red: '#ff3a4f', redOff: '#5c1119',
  pipe: '#ffffff', pipeOff: '#333840', pipeRed: '#ff3d52', pipeRedOff: '#990f1c',
  sweep: '#e6f2ff', sweepRed: '#ff2942', redFloor: '#ff1229',
  hub: '#ffffff', speed: '#ffffff', unit: '#ffffff', gear: '#ffffff',
  // the floating blade: half-width w0 at r 0.5 and w1 at the shoulder, then a point `tip` long (0: a flat end) at r 0.965
  needle: Object.freeze({ colour: '#ffffff', glow: '#ffffff', glowRed: '#ff5566', w0: 0.019, w1: 0.0045, tip: 0.01 }),
});
const normSkin = (k) => ({ ...DEFAULT_SKIN, ...(k || {}), needle: { ...DEFAULT_SKIN.needle, ...((k && k.needle) || {}) } });
const hexInt = (h) => parseInt(String(h).slice(1, 7), 16);
// shader colours are written as display (sRGB) values, so they skip three's colour management
const vec3 = (h) => { const n = hexInt(h); return new THREE.Vector3(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255); };
const stackOf = (family) => (family ? `"${family}", ${FONT}` : FONT);
const SPEED_W = 0.72;                                         // widest "888" the hub takes (dial units); wider fonts shrink
// UPSTREAM EDIT: every lowercase letter too (was s x m h k), so a stat's unit (psi, bar, °C, mph) is drawn from the
// atlas rather than falling back to a canvas texture per gauge
const GAUGE_CHARS = '0123456789.,%°:+-/ abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

// the needle blade for a skin's profile (see DEFAULT_SKIN.needle)
function needleGeometry(n) {
  const sh = new THREE.Shape(), rT = 0.965 - n.tip;
  sh.moveTo(-n.w0, 0.5); sh.lineTo(-n.w1, rT);
  if (n.tip > 0) sh.lineTo(0, 0.965);
  sh.lineTo(n.w1, rT); sh.lineTo(n.w0, 0.5); sh.closePath();
  return new THREE.ExtrudeGeometry(sh, { depth: 0.016, bevelEnabled: true, bevelSize: 0.003, bevelThickness: 0.003, bevelSegments: 1 });
}

class Arc3 extends THREE.Curve {
  constructor(r, a0, a1, z) { super(); this.r = r; this.a0 = a0; this.a1 = a1; this.z = z; }
  getPoint(t, out = new THREE.Vector3()) {
    const a = (this.a0 + (this.a1 - this.a0) * t) * DEG;
    return out.set(Math.sin(a) * this.r, Math.cos(a) * this.r, this.z);
  }
}

// additive light that leaves destination alpha alone (shows as light over whatever is behind the canvas)
function additive(m) {
  m.transparent = true; m.depthWrite = false;
  m.blending = THREE.CustomBlending;
  m.blendSrc = THREE.SrcAlphaFactor; m.blendDst = THREE.OneFactor;
  m.blendSrcAlpha = THREE.ZeroFactor; m.blendDstAlpha = THREE.OneFactor;
  return m;
}

function canvasTex(w, h, draw) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const ctx = c.getContext('2d');
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = 4;
  tex.redraw = (...a) => { ctx.clearRect(0, 0, w, h); draw(ctx, w, h, ...a); tex.needsUpdate = true; };
  tex.redraw();
  return tex;
}

function glowTex() {
  return canvasTex(128, 128, (ctx, w, h) => {
    const g = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
    g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.25, 'rgba(255,255,255,0.45)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  });
}

// top of a status jewel: dark satin disc, lit from the upper left, with a soft rim (baked: no lights needed)
function capTex() {
  return canvasTex(128, 128, (ctx, w, h) => {
    const g = ctx.createRadialGradient(w * 0.38, h * 0.32, w * 0.04, w / 2, h / 2, w / 2);
    g.addColorStop(0, '#22252c'); g.addColorStop(0.55, '#121418'); g.addColorStop(0.86, '#0c0e11'); g.addColorStop(0.95, '#262a31'); g.addColorStop(1, '#0c0e11');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(w / 2, h / 2, w / 2, 0, Math.PI * 2); ctx.fill();
  });
}

const spring = (o, target, k, c, dt) => {           // critically-ish damped spring on {x, v}
  o.v += (k * (target - o.x) - c * o.v) * dt; o.x += o.v * dt; return o.x;
};
const settled = (o, target) => Math.abs(o.v) < 1e-4 && Math.abs(target - o.x) < 1e-4;

// Glyph atlas: each character drawn once into one texture. Text is then a row of quads cut from it, so changing the
// text only moves a few vertices: no canvas redraw, no texture upload.
class GlyphAtlas {
  constructor(font, size, chars, baseline, stack = FONT) {
    Object.assign(this, { font, size, chars: [...chars], baseline, stack });
    const probe = document.createElement('canvas').getContext('2d');
    probe.font = `${font} ${size}px ${stack}`;
    let maxAdv = 0;
    for (const ch of this.chars) maxAdv = Math.max(maxAdv, probe.measureText(ch).width);
    this.pad = Math.ceil(size * 0.22);
    this.cellW = Math.ceil(maxAdv) + 2 * this.pad; this.cellH = Math.ceil(size * 1.45);
    this.anchorY = baseline === 'middle' ? this.cellH / 2 : Math.round(size * 1.08);
    this.cols = Math.ceil(Math.sqrt(this.chars.length)); this.rows = Math.ceil(this.chars.length / this.cols);
    this.glyphs = {};
    this.tex = canvasTex(this.cols * this.cellW, this.rows * this.cellH, (ctx, W, H) => this.paint(ctx, W, H));
  }
  paint(ctx, W, H) {
    ctx.font = `${this.font} ${this.size}px ${this.stack}`; ctx.textAlign = 'left'; ctx.textBaseline = this.baseline; ctx.fillStyle = '#fff';
    this.chars.forEach((ch, i) => {
      const col = i % this.cols, row = Math.floor(i / this.cols);
      ctx.fillText(ch, col * this.cellW + this.pad, row * this.cellH + this.anchorY);
      this.glyphs[ch] = { adv: ctx.measureText(ch).width, u0: (col * this.cellW) / W, u1: ((col + 1) * this.cellW) / W, v0: 1 - ((row + 1) * this.cellH) / H, v1: 1 - (row * this.cellH) / H };
    });
  }
  supports(text) { for (const ch of text) if (!this.glyphs[ch]) return false; return true; }
}

// a centred line of up to max glyphs from an atlas, at font size `size` (world units), anchored on the atlas baseline
class TextQuads {
  constructor(atlas, max, size, material) {
    this.atlas = atlas; this.max = max; this.k = size / atlas.size; this.text = null;
    const g = new THREE.BufferGeometry();
    this.pos = new THREE.BufferAttribute(new Float32Array(max * 12), 3).setUsage(THREE.DynamicDrawUsage);
    this.uv = new THREE.BufferAttribute(new Float32Array(max * 8), 2).setUsage(THREE.DynamicDrawUsage);
    const idx = [];
    for (let i = 0; i < max; i++) idx.push(i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3);
    g.setAttribute('position', this.pos); g.setAttribute('uv', this.uv); g.setIndex(idx);
    this.mesh = new THREE.Mesh(g, material); this.mesh.frustumCulled = false;
  }
  // returns false (and leaves the quads alone) if the atlas lacks a character or the text is too long
  set(text, x = 0, y = 0) {
    if (text === this.text) return true;
    const A = this.atlas, k = this.k;
    if (text.length > this.max || !A.supports(text)) return false;
    let width = 0;
    for (const ch of text) width += A.glyphs[ch].adv;
    let pen = x - (width * k) / 2;
    const P = this.pos.array, U = this.uv.array;
    P.fill(0); U.fill(0);
    let i = 0;
    for (const ch of text) {
      const gl = A.glyphs[ch], l = pen - A.pad * k, r = l + A.cellW * k, top = y + A.anchorY * k, bot = top - A.cellH * k;
      P.set([l, bot, 0, r, bot, 0, r, top, 0, l, top, 0], i * 12);
      U.set([gl.u0, gl.v0, gl.u1, gl.v0, gl.u1, gl.v1, gl.u0, gl.v1], i * 8);
      pen += gl.adv * k; i++;
    }
    this.pos.needsUpdate = true; this.uv.needsUpdate = true; this.text = text;
    return true;
  }
}

// the light pipe along a 270 deg ring: lit up to uLit, red past uRed and below uRedLow (all 0-1 along the arc).
// UPSTREAM EDIT:uFlash 1 turns its white part red (the dial's limiter flash, and a critical gauge's blink).
function pipeMaterial(red, skin = DEFAULT_SKIN) {
  const m = new THREE.ShaderMaterial({
    transparent: true,
    uniforms: { uLit: { value: 0 }, uRed: { value: red }, uRedLow: { value: -1 }, uTime: { value: 0 }, uLimiter: { value: 0 }, uFlash: { value: 0 }, uAlpha: { value: 1 },
      uOn: { value: null }, uOff: { value: null }, uRedOn: { value: null }, uRedOff: { value: null } },
    vertexShader: `varying vec2 vUv; varying vec3 vN; varying vec3 vV;
      void main(){ vUv = uv; vec4 mv = modelViewMatrix * vec4(position, 1.0); vN = normalize(normalMatrix * normal); vV = normalize(-mv.xyz); gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform float uLit, uRed, uRedLow, uTime, uLimiter, uFlash, uAlpha; uniform vec3 uOn, uOff, uRedOn, uRedOff;
      varying vec2 vUv; varying vec3 vN; varying vec3 vV;
      void main(){
        float f = vUv.x; bool red = f > uRed || f < uRedLow; float fres = pow(1.0 - abs(dot(vN, vV)), 2.0);
        vec3 col; float a;
        if (f <= uLit) {
          col = red ? uRedOn : mix(uOn, uRedOn, uFlash);
          col *= 0.72 + 0.7 * exp(-(uLit - f) * 30.0);
          if (red) col *= 1.0 + 0.6 * uLimiter * step(0.0, sin(uTime * 42.0));
          a = 1.0;
        } else { col = red ? uRedOff : uOff; a = red ? 0.95 : 0.6; }
        gl_FragColor = vec4(col + fres * 0.3, a * uAlpha);
      }`,
  });
  pipeSkin(m, skin);
  return m;
}
function pipeSkin(m, k) {
  const u = m.uniforms; u.uOn.value = vec3(k.pipe); u.uOff.value = vec3(k.pipeOff); u.uRedOn.value = vec3(k.pipeRed); u.uRedOff.value = vec3(k.pipeRedOff);
}

// one extra gauge: the dial in miniature (light pipe, sweep, rising blades, tick), icon in the middle, value in the gap
class Gauge3D {
  constructor(parent, atlas, skin = normSkin(null)) {
    const rs = SAT_R;
    this.group = new THREE.Group(); parent.add(this.group);
    this.pipeMat = pipeMaterial(2, skin);
    const pipe = new THREE.Mesh(new THREE.TubeGeometry(new Arc3(0.93 * rs, -135, 135, 0.02), 96, 0.016, 6, false), this.pipeMat);
    pipe.renderOrder = 8;
    this.sweepMat = additive(new THREE.ShaderMaterial({
      uniforms: { uVal: { value: 0 }, uRed: { value: 2 }, uRedLow: { value: -1 }, uRs: { value: rs }, uAlpha: { value: 1 },
        uSw: { value: null }, uSwRed: { value: null }, uFloor: { value: null } },
      vertexShader: VERT_P,
      fragmentShader: `uniform float uVal, uRed, uRedLow, uRs, uAlpha; uniform vec3 uSw, uSwRed, uFloor; varying vec2 vP;
        void main(){
          float r = length(vP) / uRs; float f = (degrees(atan(vP.x, vP.y)) + 135.0) / 270.0;
          if (f < 0.0 || f > 1.0) discard;
          float ramp = clamp((r - 0.45) / 0.41, 0.0, 1.0); ramp *= ramp;
          vec3 col = vec3(0.0);
          bool red = f > uRed || f < uRedLow;
          if (red) col += uFloor * 0.28 * ramp;
          if (f <= uVal) col += (red ? uSwRed : uSw) * ramp * (0.2 + 0.5 * exp(-(uVal - f) * 4.0));
          gl_FragColor = vec4(col * uAlpha, 1.0);
        }`,
    }));
    const sweep = new THREE.Mesh(new THREE.RingGeometry(0.45 * rs, 0.86 * rs, 64, 1), this.sweepMat);
    sweep.position.z = 0.01; sweep.renderOrder = 5;
    this.N = 28;                                            // a blade every 10 deg
    this.bladeMat = new THREE.MeshBasicMaterial({ toneMapped: false, transparent: true });
    this.blades = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), this.bladeMat, this.N);
    this.blades.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.bladeH = new Float32Array(this.N).fill(-1); this.bladeC = new Int32Array(this.N).fill(-1);
    this.bladeQ = []; this.bladeXY = [];
    for (let i = 0; i < this.N; i++) {
      const a = -135 + (270 * i) / (this.N - 1);
      this.bladeQ.push(new THREE.Quaternion().setFromAxisAngle(Z_AXIS, -a * DEG));
      this.bladeXY.push([Math.sin(a * DEG) * 0.78 * rs, Math.cos(a * DEG) * 0.78 * rs]);
      this.blades.setColorAt(i, new THREE.Color(hexInt(skin.tickOff)));
    }
    this.blades.renderOrder = 9;
    const tk = new THREE.Shape();
    tk.moveTo(-0.05 * rs, 0.5 * rs); tk.lineTo(-0.018 * rs, 0.9 * rs); tk.lineTo(0.018 * rs, 0.9 * rs); tk.lineTo(0.05 * rs, 0.5 * rs); tk.closePath();
    this.tickMat = new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false, transparent: true });
    this.tick = new THREE.Mesh(new THREE.ShapeGeometry(tk), this.tickMat); this.tick.position.z = 0.06; this.tick.renderOrder = 20;
    this.iconTex = canvasTex(128, 128, (ctx, w, h, icon) => { if (icon) drawGlyph(ctx, icon, 64, 64, 46, '#fff'); });
    this.iconMat = new THREE.MeshBasicMaterial({ map: this.iconTex, transparent: true, depthWrite: false, toneMapped: false });
    const icon = (new THREE.Mesh(new THREE.PlaneGeometry((128 / 46) * 0.3 * rs, (128 / 46) * 0.3 * rs), this.iconMat));
    icon.position.set(0, 0.03 * rs, 0.04); icon.renderOrder = 15;
    // value text: quads from the shared atlas; anything the atlas can't spell falls back to a canvas texture
    this.textMat = new THREE.MeshBasicMaterial({ map: atlas.tex, transparent: true, depthWrite: false, toneMapped: false });
    this.textQuads = new TextQuads(atlas, 8, 0.3 * rs, this.textMat);
    this.textQuads.mesh.position.set(0, -0.8 * rs - 0.01875 * rs, 0.04); this.textQuads.mesh.renderOrder = 15;
    // UPSTREAM EDIT: the end markers (gaugeEnds: a fuel gauge's E and F), in the same gap and material as the value,
    // shown instead of it
    this.ends = [new TextQuads(atlas, 3, 0.3 * rs, this.textMat), new TextQuads(atlas, 3, 0.3 * rs, this.textMat)];
    for (const q of this.ends) { q.mesh.position.copy(this.textQuads.mesh.position); q.mesh.renderOrder = 15; q.mesh.visible = false; }
    this.endsKey = '';
    this.group.add(pipe, sweep, this.blades, this.tick, icon, this.textQuads.mesh, this.ends[0].mesh, this.ends[1].mesh);
    // the dial's smoked backing (GLOW.smoke) under the gauge too
    this.backMat = new THREE.MeshBasicMaterial({ color: 0x05070a, transparent: true, opacity: 0, depthWrite: false, toneMapped: false });
    const backing = new THREE.Mesh(new THREE.CircleGeometry(1.02 * rs, 48), this.backMat);
    backing.position.z = -0.02; backing.renderOrder = 1; this.group.add(backing);
    this.icon = null; this.text = null; this.fallback = null;
    this._m = new THREE.Matrix4(); this._p = new THREE.Vector3(); this._s = new THREE.Vector3(); this._c = new THREE.Color();
    this.last = {};
    this.setSkin(skin);
  }

  // the dial's skin: blade, pipe, sweep and backing colours, the pointer in the needle's colour, text in its font
  setSkin(skin) {
    this.skin = skin; this.stack = stackOf(skin.family);
    this.cols = { lit: hexInt(skin.tick), off: hexInt(skin.tickOff), red: hexInt(skin.red), redOff: hexInt(skin.redOff) };
    this.bladeC.fill(-1);
    pipeSkin(this.pipeMat, skin);
    const su = this.sweepMat.uniforms; su.uSw.value = vec3(skin.sweep); su.uSwRed.value = vec3(skin.sweepRed); su.uFloor.value = vec3(skin.redFloor);
    this.backMat.color.set(skin.face); this.tickMat.color.set(skin.needle.colour);
    // UPSTREAM EDIT: the icon and value are drawn white and tinted with this; on a light-faced dial (skin.light, the
    // GP1's pale grey) white vanishes, so they take the dial's own speed colour (near-black there). Dark dials: white.
    this.ink = skin.light ? hexInt(skin.speed) : 0xffffff;
    if (this.fallback && this.text) this.fallback.tex.redraw(this.text);
  }

  // the shared value atlas was rebuilt (a new font)
  setAtlas(atlas) {
    this.textQuads.atlas = atlas; this.textQuads.k = (0.3 * SAT_R) / atlas.size;
    for (const q of this.ends) { q.atlas = atlas; q.k = (0.3 * SAT_R) / atlas.size; }   // UPSTREAM EDIT: the end markers
    this.textMat.map = atlas.tex; this.textMat.needsUpdate = true;
    this.refresh();
  }

  // canvas-texture text for strings the atlas can't spell (created on first need)
  fallbackText(text) {
    const rs = SAT_R;
    if (!this.fallback) {
      const tex = canvasTex(256, 96, (ctx, w, h, str) => {
        if (!str) return;
        ctx.font = `italic 700 64px ${this.stack}`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = '#fff';
        ctx.fillText(str, w / 2, h / 2 + 4);
      });
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(1.2 * rs, 0.45 * rs), new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, toneMapped: false }));
      mesh.position.set(0, -0.8 * rs, 0.04); mesh.renderOrder = 15; this.group.add(mesh);
      this.fallback = { tex, mesh };
    }
    this.fallback.tex.redraw(text);
  }

  // returns true when something visible changed
  update(item, t, dt) {
    const { g, angle, show, orbit } = item, rs = SAT_R, L = this.last;
    // UPSTREAM EDIT:item.value is the eased value (GaugeLayout); g.value the true one (text, critical)
    const v = Math.max(0, Math.min(1, item.value ?? g.value)), red = g.danger == null ? 2 : g.danger, low = g.dangerLow == null ? -1 : g.dangerLow;
    const crit = gaugeCritical(g), blink = crit && Math.sin(t * 10) > 0;
    let changed = crit;                                       // a critical gauge flashes: always redraw
    if (L.angle !== angle || L.orbit !== orbit || L.show !== show) {
      polar(angle, orbit, 0.02, this.group.position); this.group.scale.setScalar(0.6 + 0.4 * show);
      L.angle = angle; L.orbit = orbit; L.show = show; changed = true;
    }
    const pu = this.pipeMat.uniforms, su = this.sweepMat.uniforms;
    if (L.v !== v || L.red !== red || L.low !== low) {
      pu.uLit.value = v; pu.uRed.value = red; pu.uRedLow.value = low; su.uVal.value = v; su.uRed.value = red; su.uRedLow.value = low;
      L.v = v; L.red = red; L.low = low; changed = true;
    }
    pu.uAlpha.value = show; su.uAlpha.value = show; this.backMat.opacity = this.skin.faceAlpha * show;   // the backing fades with it
    pu.uTime.value = t; pu.uLimiter.value = crit ? 1 : 0;
    // UPSTREAM EDIT: a critical gauge's ring turns red with its icon and back, as the dial's does at the limiter (uFlash)
    pu.uFlash.value = blink ? 1 : 0;
    const k = 1 - Math.exp(-dt * 16);
    let dirty = false;
    for (let i = 0; i < this.N; i++) {
      const f = i / (this.N - 1), lit = v >= f, inRed = f >= red || f <= low;
      const target = lit ? 0.05 * (0.55 + 0.45 * Math.exp(-(v - f) * 6)) : 0.008;
      const prev = this.bladeH[i], h = prev < 0 ? target : prev + (target - prev) * k;
      const C = this.cols, col = inRed ? (lit ? C.red : C.redOff) : lit ? C.lit : C.off;
      if (Math.abs(h - prev) > 1e-5) {
        this.bladeH[i] = h;
        this._p.set(this.bladeXY[i][0], this.bladeXY[i][1], h / 2 + 0.004); this._s.set(0.012, 0.12 * rs, h);
        this.blades.setMatrixAt(i, this._m.compose(this._p, this.bladeQ[i], this._s)); dirty = true;
      }
      if (col !== this.bladeC[i]) { this.bladeC[i] = col; this.blades.setColorAt(i, this._c.set(col)); this.blades.instanceColor.needsUpdate = true; dirty = true; }
    }
    if (dirty) { this.blades.instanceMatrix.needsUpdate = true; changed = true; }
    this.bladeMat.opacity = show; this.tickMat.opacity = show;
    this.tick.rotation.z = -(-135 + 270 * v) * DEG;
    if (g.icon !== this.icon) { this.icon = g.icon; this.iconTex.redraw(g.icon); changed = true; }
    // UPSTREAM EDIT: end markers (gaugeEnds) take the gap instead of the value
    const ends = gaugeEnds(g), endsKey = ends ? ends.join('\u0000') : '';
    if (endsKey !== this.endsKey) {
      this.endsKey = endsKey; changed = true;
      this.ends.forEach((q, i) => {
        q.text = null;
        q.mesh.visible = !!ends && q.set(ends[i], (i ? 1 : -1) * ENDS_X * rs, 0);
      });
    }
    const shown = ends ? '' : (g.text || '');
    if (shown !== this.text) {
      this.text = shown; changed = true;
      const ok = this.textQuads.set(shown);
      this.textQuads.mesh.visible = ok;
      if (!ok) { this.fallbackText(shown); this.fallback.mesh.visible = true; } else if (this.fallback) this.fallback.mesh.visible = false;
    }
    this.iconMat.color.set(blink ? 0xff6070 : this.ink); this.iconMat.opacity = show * 0.92;   // UPSTREAM EDIT: ink (setSkin)
    const tm = this.fallback?.mesh.visible ? this.fallback.mesh.material : this.textMat;
    tm.color.set(crit ? 0xff6e80 : this.ink); tm.opacity = show * 0.9;
    return changed;
  }

  refresh() { this.icon = null; this.text = null; this.textQuads.text = null; this.endsKey = null; }   // UPSTREAM EDIT: endsKey

  dispose() {
    this.group.removeFromParent();
    this.group.traverse((o) => { o.geometry?.dispose(); if (o.material && o.material.map !== this.textMat.map) o.material.map?.dispose(); o.material?.dispose(); });
    this.iconTex.dispose();
  }
}

export class Hud3D {
  constructor(canvas) {
    this.canvas = canvas;
    const r = (this.renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true, powerPreference: 'high-performance' }));
    r.setClearColor(0x000000, 0);
    r.toneMapping = THREE.NoToneMapping;                     // every material is unlit and sets its final colour itself
    r.outputColorSpace = THREE.SRGBColorSpace;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(26, 1, 0.1, 40);
    this.camera.position.set(0, 0, EXTENT / Math.tan(13 * DEG));
    this.gauges = new Map();
    this.motion = 1;
    this.drag = { yaw: 0, pitch: 0, on: false };
    this.sp = { pitch: { x: 0, v: 0 }, roll: { x: 0, v: 0 }, gear: { x: 4, v: 0 }, dyaw: { x: 0, v: 0 }, dpitch: { x: 0, v: 0 } };
    this.last = {}; this.force = true;
    this.skin = normSkin(null);
    this.build();
    this.applySkin();
  }

  // same box as the 2D canvas: a square frame centred on the dial (so the dial faces the camera straight on) with the
  // canvas cut out of it as a view offset
  resize(R) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = Math.round(BOX.w * R), h = Math.round(BOX.h * R), full = 2 * EXTENT * R;
    this.canvas.style.width = w + 'px'; this.canvas.style.height = h + 'px';
    this.renderer.setPixelRatio(dpr); this.renderer.setSize(w, h, false);
    this.camera.aspect = 1;
    this.camera.setViewOffset(full, full, (EXTENT - BOX.cx) * R, (EXTENT - BOX.cy) * R, w, h);
    this.camera.updateProjectionMatrix();
    this.force = true;
  }

  build() {
    const cluster = (this.cluster = new THREE.Group());
    this.scene.add(cluster);
    const glow = glowTex();
    const carOnly = (this.carOnly = []);

    // static red-zone floor and the sweep curtain (two layers for depth); colour is computed per pixel, so the ring
    // needs few segments
    this.sweepMats = [];
    const ringGeo = new THREE.RingGeometry(0.55, 0.93, 128, 1);
    [[0.012, 1.0], [0.05, 0.45]].forEach(([z, layer], i) => {
      const m = additive(new THREE.ShaderMaterial({
        uniforms: { uRpm: { value: 0 }, uRed: { value: 6.5 }, uMax: { value: 7.5 }, uMinor: { value: 0.1 }, uLayer: { value: layer },
          uSw: { value: null }, uSwRed: { value: null }, uFloor: { value: null } },
        vertexShader: VERT_P,
        fragmentShader: `
          uniform float uRpm, uRed, uMax, uMinor, uLayer; uniform vec3 uSw, uSwRed, uFloor; varying vec2 vP;
          void main(){
            float r = length(vP); float a = degrees(atan(vP.x, vP.y)); float v = (a + 135.0) / 270.0 * uMax;
            if (v < 0.0 || v > uMax) discard;
            float ramp = clamp((r - ${GLOW.inner.toFixed(3)}) / ${(0.93 - GLOW.inner).toFixed(3)}, 0.0, 1.0); ramp = ramp * ramp * (3.0 - 2.0 * ramp);
            vec3 col = vec3(0.0);
            if (v > uRed) col += uFloor * 0.3 * ramp;
            if (v <= uRpm) {
              float trail = exp(-(uRpm - v) * (7.5 / uMax) * ${GLOW.decay.toFixed(3)});
              float grad = 0.88 + 0.12 * smoothstep(0.86, 1.0, abs(fract(v / uMinor) * 2.0 - 1.0));
              vec3 c = v > uRed ? uSwRed : uSw;
              col += c * ramp * (${GLOW.base.toFixed(3)} + ${GLOW.peak.toFixed(3)} * trail) * grad;
            }
            gl_FragColor = vec4(col * uLayer, 1.0);
          }`,
      }));
      const mesh = new THREE.Mesh(ringGeo, m); mesh.position.z = z; mesh.renderOrder = 5 + i;
      this.sweepMats.push(m); cluster.add(mesh); carOnly.push(mesh);
    });

    // smoked backing under the whole dial (GLOW.smoke): the white reads over a bright scene
    const backing = new THREE.Mesh(new THREE.CircleGeometry(1.02, 96),
      new THREE.MeshBasicMaterial({ color: 0x05070a, transparent: true, opacity: GLOW.smoke, depthWrite: false, toneMapped: false }));
    backing.position.z = -0.02; backing.renderOrder = 1; cluster.add(backing); this.backingMat = backing.material;

    // rev light pipe along the outer ring
    this.pipeMat = pipeMaterial(6.5 / 7.5);
    const pipe = new THREE.Mesh(new THREE.TubeGeometry(new Arc3(0.965, -135, 135, 0.03), 220, 0.03, 8, false), this.pipeMat);
    pipe.renderOrder = 8; cluster.add(pipe);

    // tick blades and numerals depend on the rev range: built in buildScale() on the first frame and when it changes
    this._m = new THREE.Matrix4(); this._p = new THREE.Vector3(); this._s = new THREE.Vector3(); this._c = new THREE.Color();
    this.cLit = new THREE.Color(0xffffff); this.cOld = new THREE.Color(0x9aa0a8); this.cOff = new THREE.Color(0x30333a);
    this.cRedOff = new THREE.Color(0x5c1119); this.cRed = new THREE.Color(0xff3a4f);
    this.scaleKey = null;

    // needle: a floating blade + glow
    this.needle = new THREE.Group(); this.needle.position.z = 0.095; cluster.add(this.needle);
    // the blade's profile and colour come from the skin (needleGeometry; set again in applySkin)
    const blade = (this.blade = new THREE.Mesh(needleGeometry(DEFAULT_SKIN.needle), new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false })));
    blade.renderOrder = 20; this.needle.add(blade);
    this.needleGlowMat = additive(new THREE.MeshBasicMaterial({ map: glow, color: 0xffffff, opacity: GLOW.needle, toneMapped: false }));
    const ng = new THREE.Mesh(new THREE.PlaneGeometry(0.16, 0.62), this.needleGlowMat); ng.position.set(0, 0.73, -0.01); ng.renderOrder = 19;
    this.needle.add(ng);

    // hub: open like the 2D dial: only the soft light ring, then the speed with nothing over it
    // v10: the ring opens round the gear, which sits on it at the bottom (GEAR_Y): the gap's half-angle clears the gear
    // ring (0.105) by a little
    const gapA = Math.asin(0.105 / 0.503) + 0.035;
    const ringLight = new THREE.Mesh(new THREE.TorusGeometry(0.503, 0.006, 6, 160, Math.PI * 2 - 2 * gapA), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.8, toneMapped: false }));
    ringLight.rotation.z = -Math.PI / 2 + gapA; this.ringLightMat = ringLight.material;
    ringLight.position.z = 0.012; cluster.add(ringLight); carOnly.push(ringLight, this.needle);
    const ringGlow = (this.ringGlowMat = additive(new THREE.ShaderMaterial({
      uniforms: { uCol: { value: new THREE.Vector3(1, 1, 1) } },
      vertexShader: VERT_P,
      fragmentShader: `uniform vec3 uCol; varying vec2 vP; void main(){ float r = length(vP); float g = r < 0.503 ? exp(-pow((0.503 - r) / 0.008, 2.0)) : exp(-(r - 0.503) / 0.03);
        g *= smoothstep(${(gapA - 0.03).toFixed(4)}, ${(gapA + 0.05).toFixed(4)}, abs(atan(vP.x, -vP.y)));   // opens round the gear
        gl_FragColor = vec4(uCol * (0.42 * g), 1.0); }`,
    })));
    const rg = new THREE.Mesh(new THREE.RingGeometry(0.47, 0.62, 128, 1), ringGlow); rg.position.z = 0.013; rg.renderOrder = 6; cluster.add(rg); carOnly.push(rg);

    // speed: digit quads from an atlas; unit label: a small texture redrawn only when the unit changes
    this.speedAtlas = new GlyphAtlas('900', 160, '0123456789', 'alphabetic');
    this.speedText = new TextQuads(this.speedAtlas, 4, SPEED_SIZE, new THREE.MeshBasicMaterial({ map: this.speedAtlas.tex, transparent: true, depthWrite: false, toneMapped: false }));
    this.speedText.mesh.position.z = 0.075; this.speedText.mesh.renderOrder = 30; cluster.add(this.speedText.mesh);
    // UPSTREAM EDIT: the label at 2.1x, font 0.1125 dial units
    // (was 0.053), on the same baseline (0.190625) so it grows up into the empty hub, away from the digits.
    this.unitTex = canvasTex(512, 128, (ctx, w, h, unit = 'km/h') => {
      ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic'; ctx.globalAlpha = 0.92; ctx.fillStyle = this.skin.unit;
      ctx.font = `${this.skin.unitFont} 72px ${stackOf(this.skin.family)}`; ctx.fillText(unit, w / 2, 88); ctx.globalAlpha = 1;
    });
    // v10b: x UNIT_K (font 0.152), its baseline (texture y 88 of 128) at UNIT_BASE, just above the bigger digits
    const unit = new THREE.Mesh(new THREE.PlaneGeometry(0.8 * UNIT_K, 0.2 * UNIT_K), new THREE.MeshBasicMaterial({ map: this.unitTex, transparent: true, depthWrite: false, toneMapped: false }));
    unit.position.set(0, UNIT_BASE + 0.2 * UNIT_K * (88 / 128 - 0.5), 0.075); unit.renderOrder = 30; cluster.add(unit); carOnly.push(unit, this.speedText.mesh);

    // gear drum in a porthole
    const strip = canvasTex(128, 128 * GEARS.length, (ctx, w, h, list = GEARS) => {
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = '#fff';
      ctx.font = `${this.skin.gearFont} 92px ${stackOf(this.skin.family)}`;   // the 2D gear's face (or the skin's)
      list.forEach((g, i) => ctx.fillText(g, w / 2, i * 128 + 68));
    });
    this.gearList = GEARS;
    strip.wrapT = THREE.RepeatWrapping;
    this.stripTex = strip;
    this.drumMat = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false,
      uniforms: { uTex: { value: strip }, uPos: { value: 4 }, uCells: { value: GEARS.length }, uCol: { value: new THREE.Vector3(1, 1, 1) } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: `uniform sampler2D uTex; uniform float uPos, uCells; uniform vec3 uCol; varying vec2 vUv;
        void main(){
          vec2 p = vUv * 2.0 - 1.0; float d = length(p); if (d > 1.0) discard;
          // one cell spans 0.164 dial units, so the number has its true proportions and the 2D gear's size (cap height
          // 0.084R); the window is 0.2 across. On a change the numbers slide up or down through it like a drum,
          // fading and dimming toward the rim; at rest only the current gear shows.
          float t = uPos + 0.5 - p.y * 0.609;
          vec4 tx = texture2D(uTex, vec2(0.5 + (vUv.x - 0.5) * 1.218, 1.0 - t / uCells));
          float rim = abs(p.y);
          gl_FragColor = vec4(uCol * (1.0 - 0.3 * rim * rim), tx.a * (1.0 - smoothstep(0.55, 1.0, rim)) * smoothstep(1.0, 0.93, d));
        }`,
    });
    const drum = new THREE.Mesh(new THREE.PlaneGeometry(0.2, 0.2), this.drumMat); drum.position.set(0, GEAR_Y, 0.03); drum.renderOrder = 25;
    // flat white circle round the gear, as on the 2D dial (0.0995R, 0.011R line); v10: on the hub ring's line
    const gearRing = new THREE.Mesh(new THREE.RingGeometry(0.094, 0.105, 64), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.85, toneMapped: false }));
    gearRing.position.set(0, GEAR_Y, 0.032); gearRing.renderOrder = 26; this.gearRingMat = gearRing.material;
    cluster.add(drum, gearRing); carOnly.push(drum, gearRing);

    // status jewels: satin cap (baked shading), icon, halo
    const capTop = new THREE.MeshBasicMaterial({ map: capTex(), toneMapped: false });
    const capSide = new THREE.MeshBasicMaterial({ color: 0x0a0b0e, toneMapped: false });
    const capGeo = new THREE.CylinderGeometry(0.068 * JEWEL, 0.074 * JEWEL, 0.03, 40).rotateX(Math.PI / 2);   // v10: x JEWEL
    this.jewels = ICONS.map((j) => {
      const g = new THREE.Group(); polar(j.a, j.r, 0.02, g.position);
      const cap = new THREE.Mesh(capGeo, [capSide, capTop, capSide]);
      const tex = canvasTex(128, 128, (ctx, w, h, variant, id = j.id) => drawIcon(ctx, id, 64, 64, 128 / 0.165, { css: '#fff', glow: false, variant }));
      const iconMat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, toneMapped: false, color: 0x666b74 });
      const icon = new THREE.Mesh(new THREE.PlaneGeometry(0.15 * JEWEL, 0.15 * JEWEL), iconMat); icon.position.z = 0.017; icon.renderOrder = 15;
      const haloMat = additive(new THREE.MeshBasicMaterial({ map: glow, color: 0xffffff, opacity: 0, toneMapped: false }));
      const halo = new THREE.Mesh(new THREE.PlaneGeometry(0.34 * JEWEL, 0.34 * JEWEL), haloMat); halo.position.z = 0.005; halo.renderOrder = 14;
      g.add(cap, icon, halo); this.cluster.add(g);
      return { ...j, g, tex, iconMat, haloMat, lift: { x: 0, v: 0 }, variant: undefined, cur: j.id, hex: -1 };
    });

    // lower meter: four light pipes in the ring's gap, one under each status light, one mesh, lit through vertex colours
    const segGeos = [[141.5, 158.5], [161.5, 178.5], [181.5, 198.5], [201.5, 218.5]].map(([a0, a1]) => new THREE.TubeGeometry(new Arc3(0.972, a0, a1, 0.025), 20, 0.016, 8, false));
    const sPos = [], sIdx = []; this.segRanges = [];
    for (const g of segGeos) {
      const base = sPos.length / 3, p = g.attributes.position.array;
      sPos.push(...p); for (const i of g.index.array) sIdx.push(base + i);
      this.segRanges.push([base, p.length / 3]); g.dispose();
    }
    const segGeo = new THREE.BufferGeometry();
    segGeo.setAttribute('position', new THREE.Float32BufferAttribute(sPos, 3)); segGeo.setIndex(sIdx);
    this.segCol = new THREE.Float32BufferAttribute(new Float32Array((sPos.length / 3) * 4), 4).setUsage(THREE.DynamicDrawUsage);
    segGeo.setAttribute('color', this.segCol);
    cluster.add(new THREE.Mesh(segGeo, new THREE.MeshBasicMaterial({ vertexColors: true, transparent: true, toneMapped: false })));
    this.segLit = -1;

    // shared atlas for the extra gauges' values
    this.gaugeAtlas = new GlyphAtlas('italic 700', 48, GAUGE_CHARS, 'middle');

    // aircraft mode: attitude indicator and tapes (shown instead of the rev dial's parts)
    this.air = new Air3D(cluster); this.air.visible = false; this.isAir = false;
    this.isBoat = false;                                      // boat mode: the power scale and the F / N / R drum
  }

  setBoat(boat) {
    this.isBoat = boat;
    this.gearList = boat ? BOAT_GEARS : GEARS; this.stripTex.redraw(this.gearList);
    this.sp.gear.x = Math.max(0, this.gearList.indexOf('N')); this.sp.gear.v = 0;
    this.drumMat.uniforms.uPos.value = this.sp.gear.x; this.force = true;
  }

  // the attitude indicator: 'ball' (3D gyro horizon, the default) or 'flat' (the 2D dial's disc)
  setAttitude(style) { this.air.setStyle(style); this.force = true; }

  // switch between the rev dial and the aircraft instruments
  setAir(air) {
    this.isAir = air; this.air.visible = air;
    for (const o of this.carOnly) o.visible = !air;
    for (const o of [this.blades, this.edges, this.numMesh]) if (o) o.visible = !air;
    const u = this.pipeMat.uniforms;                          // the ring: a plain bezel in the air
    if (air) { u.uLit.value = 0; u.uRed.value = 2; u.uFlash.value = 0; u.uLimiter.value = 0; }
    else if (this.sc) u.uRed.value = this.sc.redline / this.sc.max;
    this.last.rpm = undefined; this.force = true;
  }

  // Tick blades (one per minor tick, longer at each numeral and half-step, rising as the revs pass them) and the
  // numerals mesh (each numeral four stacked quads reading as extruded type, back layers dark, front lit) for a
  // rev range. Rebuilt only when the range changes.
  buildScale(sc) {
    const angOf = (v) => -135 + (270 * v) / sc.max;
    if (this.blades) { this.blades.removeFromParent(); this.blades.geometry.dispose(); this.blades.material.dispose(); this.blades.dispose(); }
    if (this.edges) { this.edges.removeFromParent(); this.edges.geometry.dispose(); this.edges.material.dispose(); this.edges.dispose(); }
    if (this.numMesh) { this.numMesh.removeFromParent(); this.numMesh.geometry.dispose(); this.numMesh.material.dispose(); this.numTex.dispose(); }
    const N = sc.ticks;
    this.blades = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshBasicMaterial({ toneMapped: false }), N);
    this.blades.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.bladeH = new Float32Array(N).fill(-1); this.bladeC = new Float32Array(N * 3).fill(-1);
    this.bladeInfo = [];
    for (let i = 0; i < N; i++) {
      const v = i * sc.minor, major = i % 10 === 0, mid = i % 5 === 0, a = angOf(v);
      const len = major ? 0.095 : mid ? 0.072 : 0.052, rr = 0.86 - len / 2;
      this.bladeInfo.push({ v, w: major ? 0.022 : 0.011, len, rise: major ? 0.12 : 0.075, red: v >= sc.redline - 1e-6,
        x: Math.sin(a * DEG) * rr, y: Math.cos(a * DEG) * rr, q: new THREE.Quaternion().setFromAxisAngle(Z_AXIS, -a * DEG) });
      this.blades.setColorAt(i, this.cOff);
    }
    this.blades.renderOrder = 9; this.cluster.add(this.blades);
    // UPSTREAM EDIT:the blades' dark edges (BLADE_EDGE). Transparent, so drawn after the sweep it darkens;
    // a little lower than its blade, so the blade (opaque, drawn first) wins the depth test inside it. Hidden (scale 0)
    // until a blade is lit.
    this.edges = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1),
      new THREE.MeshBasicMaterial({ color: 0x0b0c0f, transparent: true, opacity: 0.6, depthWrite: false, toneMapped: false }), N);
    this.edges.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.edgeW = new Float32Array(N).fill(-1);
    const hidden = new THREE.Matrix4().makeScale(0, 0, 0);
    for (let i = 0; i < N; i++) this.edges.setMatrixAt(i, hidden);
    this.edges.renderOrder = 9; this.edges.frustumCulled = false; this.cluster.add(this.edges);

    const labels = sc.labels, cols = 4, rows = Math.ceil(labels.length / cols), CW = 192, CH = 128;
    // the skin's numeral font, smaller if its widest numeral would overflow a cell
    const stack = stackOf(this.skin.family), fit = document.createElement('canvas').getContext('2d');
    fit.font = `${this.skin.numeralFont} 92px ${stack}`;
    const widest = Math.max(1, ...labels.map((l) => fit.measureText(l.text).width));
    const NF = `${this.skin.numeralFont} ${Math.min(92, Math.floor((92 * (CW - 20)) / widest))}px ${stack}`;
    this.numTex = canvasTex(cols * CW, rows * CH, (ctx) => {
      ctx.font = NF; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = '#fff';
      labels.forEach((l, i) => ctx.fillText(l.text, (i % cols) * CW + CW / 2, Math.floor(i / cols) * CH + CH / 2 + 4));
    });
    const numGeo = new THREE.BufferGeometry(), nPos = [], nUv = [], nCol = [], nIdx = [];
    const back = new THREE.Color(hexInt(this.skin.numeralBack)), hy = NUMERAL_H, hx = hy * (CW / CH);
    this.numerals = [];
    // v10b: each numeral's ink box (measured in the atlas font, relative to its quad's centre, dial units) sets its
    // radius: the box's extent toward the ticks along the numeral's direction, then NUM_GAP clear of their inner end
    const mc = document.createElement('canvas').getContext('2d');
    mc.font = NF; mc.textAlign = 'center'; mc.textBaseline = 'middle';
    const kx = (2 * hx) / CW, ky = (2 * hy) / CH;
    const numR = (text, a) => {
      const m = mc.measureText(text), ux = Math.sin(a * DEG), uy = Math.cos(a * DEG);
      if (!m.actualBoundingBoxRight && !m.actualBoundingBoxLeft) return NUMERAL_R;      // no metrics: the plain radius
      const x0 = -m.actualBoundingBoxLeft * kx, x1 = m.actualBoundingBoxRight * kx;
      const yT = (m.actualBoundingBoxAscent - 4) * ky, yB = -(m.actualBoundingBoxDescent + 4) * ky;   // drawn 4 px below the cell's middle
      const ext = Math.max(x0 * ux, x1 * ux) + Math.max(yT * uy, yB * uy);
      return TICK_IN - NUM_GAP - ext;
    };
    labels.forEach((l, i) => {
      const p = polar(angOf(l.v), numR(l.text, angOf(l.v)), 0.03), u0 = (i % cols) / cols, u1 = u0 + 1 / cols, v1 = 1 - Math.floor(i / cols) / rows, v0 = v1 - 1 / rows;
      const start = nPos.length / 3;
      for (let k = 3; k >= 0; k--) {                          // back layers first (they draw first)
        const base = nPos.length / 3, z = p.z - k * 0.007, c = k === 0 ? [1, 1, 1] : [back.r, back.g, back.b];
        nPos.push(p.x - hx, p.y - hy, z, p.x + hx, p.y - hy, z, p.x + hx, p.y + hy, z, p.x - hx, p.y + hy, z);
        nUv.push(u0, v0, u1, v0, u1, v1, u0, v1);
        for (let j = 0; j < 4; j++) nCol.push(...c);
        nIdx.push(base, base + 1, base + 2, base, base + 2, base + 3);
      }
      this.numerals.push({ v: l.v, red: l.v >= sc.redline - 1e-6, start, front: start + 12, lift: { x: 0, v: 0 }, col: -1, liftApplied: 0 });
    });
    this.numPos = new THREE.Float32BufferAttribute(nPos, 3).setUsage(THREE.DynamicDrawUsage);
    this.numCol = new THREE.Float32BufferAttribute(nCol, 3).setUsage(THREE.DynamicDrawUsage);
    numGeo.setAttribute('position', this.numPos); numGeo.setAttribute('uv', new THREE.Float32BufferAttribute(nUv, 2));
    numGeo.setAttribute('color', this.numCol); numGeo.setIndex(nIdx);
    this.numMesh = new THREE.Mesh(numGeo, new THREE.MeshBasicMaterial({ map: this.numTex, vertexColors: true, transparent: true, depthWrite: false, toneMapped: false }));
    this.numMesh.renderOrder = 12; this.numMesh.frustumCulled = false; this.cluster.add(this.numMesh);

    for (const m of this.sweepMats) { m.uniforms.uMax.value = sc.max; m.uniforms.uRed.value = sc.redline; m.uniforms.uMinor.value = sc.minor; }
    this.pipeMat.uniforms.uRed.value = sc.redline / sc.max;
    this.sc = sc; this.last.rpm = undefined;
    if (this.isAir) this.setAir(true);
  }

  refreshText() {
    this.scaleKey = null;                                   // v10b: rebuild the scale so the numerals are placed on the real font's ink
    this.rebuildAtlases();                                  // skins: speed and gauge glyphs re-measured in the current font
    this.stripTex.redraw(this.gearList); this.air.refreshText();
    for (const j of this.jewels) j.tex.redraw(j.variant, j.cur);
    for (const gz of this.gauges.values()) gz.refresh();
    this.speedText.text = null; this.last.unit = null; this.force = true;
  }

  // speed digits and gauge values: glyph atlases in the skin's font. A font wider than Roboto shrinks the speed until
  // "888" fits the hub (SPEED_W), times the skin's own speedFit.
  rebuildAtlases() {
    const k = this.skin, stack = stackOf(k.family), old = [this.speedAtlas, this.gaugeAtlas];
    this.speedAtlas = new GlyphAtlas(k.speedFont, 160, '0123456789', 'alphabetic', stack);
    const w888 = (3 * this.speedAtlas.glyphs['8'].adv * SPEED_SIZE) / 160;
    this.speedText.atlas = this.speedAtlas;
    this.speedText.k = (SPEED_SIZE * Math.min(1, SPEED_W / w888) * k.speedFit) / 160;
    this.speedText.mesh.material.map = this.speedAtlas.tex; this.speedText.mesh.material.needsUpdate = true; this.speedText.text = null;
    this.gaugeAtlas = new GlyphAtlas('italic 700', 48, GAUGE_CHARS, 'middle', stack);
    for (const gz of this.gauges.values()) gz.setAtlas(this.gaugeAtlas);
    for (const a of old) a.tex.dispose();
  }

  // Apply this.skin to everything already built (see DEFAULT_SKIN)
  applySkin() {
    const k = this.skin, n = k.needle;
    this.backingMat.color.set(k.face); this.backingMat.opacity = k.faceAlpha;
    this.cLit.set(k.tick); this.cOld.set(k.tickOld); this.cOff.set(k.tickOff); this.cRed.set(k.red); this.cRedOff.set(k.redOff);
    this.numCols = { lit: hexInt(k.numeral), off: hexInt(k.numeralOff), red: hexInt(k.numeralRed), redOff: hexInt(k.numeralRedOff) };
    for (const m of this.sweepMats) { const u = m.uniforms; u.uSw.value = vec3(k.sweep); u.uSwRed.value = vec3(k.sweepRed); u.uFloor.value = vec3(k.redFloor); }
    pipeSkin(this.pipeMat, k);
    this.blade.geometry.dispose(); this.blade.geometry = needleGeometry(n); this.blade.material.color.set(n.colour);
    this.ringLightMat.color.set(k.hub); this.ringGlowMat.uniforms.uCol.value = vec3(k.hub); this.gearRingMat.color.set(k.hub);
    this.speedText.mesh.material.color.set(k.speed); this.drumMat.uniforms.uCol.value = vec3(k.gear);
    for (const gz of this.gauges.values()) gz.setSkin(k);
    this.bladeC?.fill(-1);
    this.refreshText();                                       // fonts: speed, gauge values, gear, unit, and the scale
    this.last.rpm = undefined; this.force = true;
  }

  // A theme over the dial (DEFAULT_SKIN lists the fields; null: the dial as designed). Returns a promise that settles
  // once the skin's font is loaded and the text redrawn in it (the host page must make the family available).
  setSkin(skin) {
    const k = (this.skin = normSkin(skin));
    this.applySkin();
    if (!k.family || !document.fonts) return Promise.resolve();
    const stack = stackOf(k.family);
    const faces = [k.numeralFont, k.speedFont, k.unitFont, k.gearFont, 'italic 700'];
    return Promise.all(faces.map((f) => document.fonts.load(`${f} 40px ${stack}`).catch(() => {})))
      .then(() => { if (this.skin === k) this.refreshText(); });
  }

  // free everything on the GPU (the host is done with the dial)
  dispose() {
    for (const gz of this.gauges.values()) gz.dispose();
    this.gauges.clear();
    this.scene.traverse((o) => {
      o.geometry?.dispose();
      for (const m of [].concat(o.material || [])) { m.map?.dispose(); m.uniforms?.uTex?.value?.dispose?.(); m.dispose(); }
    });
    this.renderer.dispose();
  }

  dragBy(dx, dy) { this.drag.yaw += dx * 0.008; this.drag.pitch += dy * 0.008; this.drag.yaw = Math.max(-1.2, Math.min(1.2, this.drag.yaw)); this.drag.pitch = Math.max(-0.9, Math.min(0.9, this.drag.pitch)); }
  resetDrag() { this.drag.yaw = 0; this.drag.pitch = 0; }

  // returns false when the frame was skipped (nothing moved)
  render(s, dt) {
    const sc = dialScale(s), key = sc.max + '/' + sc.redline, air = s.kind === 'air';   // revs, or power on a boat
    if (air !== this.isAir) this.setAir(air);
    if ((s.kind === 'boat') !== this.isBoat) this.setBoat(s.kind === 'boat');
    let changed = this.force || (s.limiter && !air);          // the limiter flashes: always redraw
    if (key !== this.scaleKey) { this.scaleKey = key; this.buildScale(sc); changed = true; }
    const t = s.t, rpm = dialValue(s, sc), mo = this.motion, L = this.last;
    const k7 = 7.5 / sc.max;                                  // trails and fades look the same on every scale
    const angOf = (v) => -135 + (270 * v) / sc.max;
    this.force = false;

    if (air) { if (this.air.update(s)) changed = true; } else {
    // dial
    if (L.rpm !== rpm) {
      L.rpm = rpm; changed = true;
      this.needle.rotation.z = -angOf(rpm) * DEG;
      this.needleGlowMat.color.set(rpm > sc.redline ? this.skin.needle.glowRed : this.skin.needle.glow);
      for (const m of this.sweepMats) m.uniforms.uRpm.value = rpm;
      this.pipeMat.uniforms.uLit.value = rpm / sc.max;
    }
    this.pipeMat.uniforms.uTime.value = t; this.pipeMat.uniforms.uLimiter.value = s.limiter ? 1 : 0;
    // UPSTREAM EDIT:at the limiter the pipe's white turns red and back every LIMITER_FLASH, red first
    this.flashT = s.limiter ? (this.flashT || 0) + dt : 0;
    this.pipeMat.uniforms.uFlash.value = s.limiter && Math.floor(this.flashT / LIMITER_FLASH) % 2 === 0 ? 1 : 0;

    const k = 1 - Math.exp(-dt * 16), C = this.bladeC;
    let dirtyM = false, dirtyC = false, dirtyE = false;
    for (let i = 0; i < this.bladeInfo.length; i++) {
      const b = this.bladeInfo[i], lit = rpm >= b.v;
      const target = lit ? b.rise * (0.55 + 0.45 * Math.exp(-(rpm - b.v) * k7 * 0.9)) : 0.012;
      const prev = this.bladeH[i], h = prev < 0 ? target : prev + (target - prev) * k;
      const moved = Math.abs(h - prev) > 1e-5;
      if (moved) {
        this.bladeH[i] = h;
        this._p.set(b.x, b.y, h / 2 + 0.005); this._s.set(b.w, b.len, h);
        this.blades.setMatrixAt(i, this._m.compose(this._p, b.q, this._s)); dirtyM = true;
      }
      // the dark edge (BLADE_EDGE), as wide as the sweep behind the blade is bright: the sweep's trail
      const e = lit ? BLADE_EDGE * Math.exp(-(rpm - b.v) * k7 * GLOW.decay) : 0;
      if (moved || Math.abs(e - this.edgeW[i]) > 1e-5) {
        this.edgeW[i] = e;
        if (e < 2e-4) this._s.set(0, 0, 0);
        else { this._p.set(b.x, b.y, h * 0.45 + 0.005); this._s.set(b.w + 2 * e, b.len + 2 * e, h * 0.9); }
        this.edges.setMatrixAt(i, this._m.compose(this._p, b.q, this._s)); dirtyE = true;
      }
      if (b.red) this._c.copy(lit ? this.cRed : this.cRedOff);
      else if (lit) this._c.lerpColors(this.cOld, this.cLit, Math.exp(-(rpm - b.v) * k7 * 0.7));
      else this._c.copy(this.cOff);
      if (Math.abs(C[i * 3] - this._c.r) > 1e-4 || Math.abs(C[i * 3 + 1] - this._c.g) > 1e-4 || Math.abs(C[i * 3 + 2] - this._c.b) > 1e-4) {
        C[i * 3] = this._c.r; C[i * 3 + 1] = this._c.g; C[i * 3 + 2] = this._c.b;
        this.blades.setColorAt(i, this._c); dirtyC = true;
      }
    }
    if (dirtyM) this.blades.instanceMatrix.needsUpdate = true;
    if (dirtyC) this.blades.instanceColor.needsUpdate = true;
    if (dirtyE) this.edges.instanceMatrix.needsUpdate = true;
    changed ||= dirtyM || dirtyC || dirtyE;

    // numerals: lift and front colour into the shared mesh
    const NP = this.numPos.array, NC = this.numCol.array;
    let numDirty = false;
    for (const n of this.numerals) {
      const lit = rpm >= n.v, target = lit ? 0.035 : 0;
      if (!settled(n.lift, target)) spring(n.lift, target, 160, 18, dt);
      if (Math.abs(n.lift.x - n.liftApplied) > 1e-5) {
        const d = n.lift.x - n.liftApplied; n.liftApplied = n.lift.x;
        for (let vtx = n.start; vtx < n.start + 16; vtx++) NP[vtx * 3 + 2] += d;
        numDirty = true;
      }
      const NK = this.numCols, col = n.red ? (lit ? NK.red : NK.redOff) : lit ? NK.lit : NK.off;
      if (col !== n.col) {
        n.col = col; this._c.set(col);
        for (let vtx = n.front; vtx < n.front + 4; vtx++) { NC[vtx * 3] = this._c.r; NC[vtx * 3 + 1] = this._c.g; NC[vtx * 3 + 2] = this._c.b; }
        this.numCol.needsUpdate = true; changed = true;
      }
    }
    if (numDirty) { this.numPos.needsUpdate = true; changed = true; }

    // speed, unit, gear
    if (this.speedText.set(String(displaySpeed(s)), 0, SPEED_BASE) && L.speed !== this.speedText.text) { L.speed = this.speedText.text; changed = true; }
    if (L.unit !== s.units) { L.unit = s.units; this.unitTex.redraw(s.units === 'mph' ? 'mph' : 'km/h'); changed = true; }
    const gi = Math.max(0, this.gearList.indexOf(gearLabel(s)));
    if (!settled(this.sp.gear, gi)) { this.drumMat.uniforms.uPos.value = spring(this.sp.gear, gi, 120, 11, dt); changed = true; }
    }

    // status jewels
    for (const j of this.jewels) {
      const id = iconId(s, j.id), st = indicatorStyle(s, id);
      if (st.variant !== j.variant || id !== j.cur) { j.variant = st.variant; j.cur = id; j.tex.redraw(st.variant, id); changed = true; }
      const on = (j.on = indicatorLit(st));                              // lit = raised; off/grey = flush
      const lift = on ? 0.022 : 0;
      if (!settled(j.lift, lift)) { j.g.position.z = 0.02 + spring(j.lift, lift, 140, 16, dt); changed = true; }
      if (st.hex !== j.hex) { j.hex = st.hex; j.iconMat.color.set(st.hex); j.haloMat.color.set(st.hex); changed = true; }
      const haloT = st.glow ? 0.85 : on ? 0.12 : 0;
      if (Math.abs(haloT - j.haloMat.opacity) > 1e-3) { j.haloMat.opacity += (haloT - j.haloMat.opacity) * Math.min(1, dt * 18); changed = true; }
    }

    // lower meter: each segment lights with the status light above it, in its colour (a flashing one flashes too)
    let lit = '';
    for (const j of this.jewels) lit += (j.on ? j.hex : -1) + ',';
    if (lit !== this.segLit) {
      this.segLit = lit; const SC = this.segCol.array;
      this.segRanges.forEach(([base, count], i) => {
        const j = this.jewels[i]; this._c.set(j.on ? j.hex : 0x3a3e45); const a = j.on ? 1 : 0.8;
        for (let v = base; v < base + count; v++) { SC[v * 4] = this._c.r; SC[v * 4 + 1] = this._c.g; SC[v * 4 + 2] = this._c.b; SC[v * 4 + 3] = a; }
      });
      this.segCol.needsUpdate = true; changed = true;
    }

    // extra gauges: create, update, retire
    const seen = new Set();
    for (const item of s.gaugeView || []) {
      let gz = this.gauges.get(item.g.id);
      if (!gz) { gz = new Gauge3D(this.cluster, this.gaugeAtlas, this.skin); this.gauges.set(item.g.id, gz); }
      if (gz.update(item, t, dt)) changed = true;
      seen.add(item.g.id);
    }
    for (const [id, gz] of this.gauges) if (!seen.has(id)) { gz.dispose(); this.gauges.delete(id); changed = true; }

    // body motion: lean with acceleration and braking, kick on shifts, engine shake, limiter judder; drag (compare view) to inspect
    const pitchT = (Math.max(-0.09, Math.min(0.09, -s.accel * 0.0032)) + s.shiftKick * 0.035) * mo;
    const rollT = Math.sin(t * 0.7) * 0.012 * Math.min(1, s.speed / 120) * mo;
    spring(this.sp.pitch, pitchT, 70, 9, dt); spring(this.sp.roll, rollT, 40, 8, dt);
    spring(this.sp.dyaw, this.drag.yaw, 50, 12, dt); spring(this.sp.dpitch, this.drag.pitch, 50, 12, dt);
    const lim = s.limiter && !air;
    const amp = (rpm / sc.max) ** 3 * 0.0035, shake = amp > 2e-5 || lim ? mo * (amp * Math.sin(t * 97) + (lim ? 0.008 * Math.sin(t * 61) : 0)) : 0;
    const rx = this.sp.pitch.x + this.sp.dpitch.x + shake, ry = this.sp.dyaw.x, rz = this.sp.roll.x + shake * 0.6;
    if (Math.abs(rx - L.rx) > 1e-6 || Math.abs(ry - L.ry) > 1e-6 || Math.abs(rz - L.rz) > 1e-6 || L.rx === undefined) {
      L.rx = rx; L.ry = ry; L.rz = rz; this.cluster.rotation.set(rx, ry, rz); changed = true;
    }

    if (changed) this.renderer.render(this.scene, this.camera);
    return changed;
  }
}
