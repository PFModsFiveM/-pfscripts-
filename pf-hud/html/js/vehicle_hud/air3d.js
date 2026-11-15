// Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
// Free software under the GNU Lesser General Public License 3.0 (pf-hud/COPYING.LESSER and COPYING).
// Aircraft mode for the 3D dial: the attitude indicator and the two tapes (see air.js for the layout, shared with the
// 2D dial). The attitude is a ball by default, as in a gyro horizon: a sphere painted with sky, ground and the pitch
// ladder turns behind a fixed bank scale and aircraft symbol, so the rungs curve and crowd toward the rim; setStyle
// ('flat') gives the flat disc instead. Everything that moves is a uniform or a rotation: the ladder, the tapes' ticks
// and numbers and the rolling readouts are drawn per pixel from one glyph texture, so a frame in flight uploads nothing.
import * as THREE from 'three';
import { FONT } from './dial.js';
import { ADI, SKY_HI, SKY_LO, GND_HI, GND_LO, BANK, SYMBOL, TAPE, SPEED_TAPE, ALT_TAPE, ROLL_PITCH, STATIC_PITCH, BALL, ballLatitude, CAP, advance, airspeed, altitudeFt, speedColumns, altColumns } from './air.js';

const DEG = Math.PI / 180;
export const f = (x) => (Number.isInteger(x) ? x.toFixed(1) : String(+x.toFixed(6)));   // a GLSL float literal
export const v3 = ([r, g, b]) => `vec3(${f(r)}, ${f(g)}, ${f(b)})`;
export const VERT = 'varying vec2 vP; void main(){ vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }';

// Glyph texture: two rows of cells (row 0 bold for readouts and pitch numbers, row 1 medium for tape numbers and
// captions), each glyph's cap box centred in its cell. Drawn with the dial's font; redrawn when the fonts arrive.
export const CHARS = '0123456789-MPHFTNESW';
const CW = 80, CH = 96, FS = 80;
const CELL = [CW / (FS * CAP), CH / (FS * CAP)];          // a cell, in cap heights
const EM = { M: 0.872, P: 0.631, H: 0.713, F: 0.553, T: 0.611 };   // Roboto capital advances (em)
export function glyphTexture() {
  const c = document.createElement('canvas'); c.width = CHARS.length * CW; c.height = 2 * CH;
  const ctx = c.getContext('2d');
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.NoColorSpace; tex.anisotropy = 4;
  tex.redraw = () => {
    ctx.clearRect(0, 0, c.width, c.height);
    ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic'; ctx.fillStyle = '#fff';
    ['700', '500'].forEach((w, row) => {
      ctx.font = `${w} ${FS}px ${FONT}`;
      [...CHARS].forEach((ch, i) => ctx.fillText(ch, i * CW + CW / 2, row * CH + CH / 2 + (FS * CAP) / 2));
    });
    tex.needsUpdate = true;
  };
  tex.redraw();
  return tex;
}

// shared GLSL: premultiplied "over", antialiased bands and boxes, and a glyph from the texture with explicit gradients
// (so cell edges never pick a wrong mip level)
export const LIB = `
  uniform sampler2D uDig;
  vec4 over(vec4 d, vec3 c, float a) { return vec4(c * a, a) + d * (1.0 - a); }
  float band(float d, float hw, float px) { return 1.0 - smoothstep(hw - 0.5 * px, hw + 0.5 * px, d); }
  float sdBox(vec2 q, vec2 h) { vec2 d = abs(q) - h; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }
  float fill(float sd, float px) { return 1.0 - smoothstep(-0.5 * px, 0.5 * px, sd); }
  // g: glyph index; w: row (0 bold, 1 medium); q: offset from the glyph's centre; cap: cap height (dial units)
  float glyph(float g, float w, vec2 q, float cap, vec2 dx, vec2 dy) {
    vec2 cell = vec2(${f(CELL[0])}, ${f(CELL[1])}) * cap;
    vec2 uv = q / cell + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
    vec2 k = 1.0 / (cell * vec2(${f(CHARS.length)}, 2.0));
    return textureGrad(uDig, vec2((g + uv.x) / ${f(CHARS.length)}, (1.0 - w + uv.y) * 0.5), dx * k, dy * k).a;
  }
  float tri(vec2 q, float ya, float yb, float hb, float px) {      // isosceles: apex (0, ya), base at yb, half-width hb
    float t = (q.y - yb) / (ya - yb);
    float side = abs(q.x) - hb * (1.0 - t);
    return fill(side, px) * smoothstep(-0.5 * px, 0.5 * px, t * abs(ya - yb)) * smoothstep(-0.5 * px, 0.5 * px, (1.0 - t) * abs(ya - yb));
  }
`;

function adiShader() {
  const ticks = BANK.ticks.flatMap(([d, long]) => [[d, long], [-d, long]]).map(([d, long]) => {
    const r0 = BANK.r - (long ? BANK.long : BANK.short);
    return `{ vec2 n = vec2(${f(Math.sin(d * DEG))}, ${f(Math.cos(d * DEG))}); float al = dot(p, n), ac = abs(dot(p, vec2(n.y, -n.x)));
      P = over(P, vec3(1.0), band(ac, ${f(BANK.w / 2)}, px) * smoothstep(${f(r0)} - 0.5 * px, ${f(r0)} + 0.5 * px, al) * (1.0 - smoothstep(${f(BANK.r)} - 0.5 * px, ${f(BANK.r)} + 0.5 * px, al))); }`;
  }).join('\n');
  const boxes = SYMBOL.boxes.map(([x, y, w, h]) => `d = min(d, sdBox(p - vec2(${f(x)}, ${f(y)}), vec2(${f(w)}, ${f(h)})));`).join(' ');
  const adv = advance(ADI.label), P = BANK.pointer, I = BANK.index;
  return `uniform float uPitch, uRoll, uAlpha; varying vec2 vP;
    ${LIB}
    void main(){
      vec2 p = vP; float r = length(p);
      vec2 dpx = dFdx(p), dpy = dFdy(p); float px = max(length(dpx), length(dpy));
      float disc = fill(r - ${f(ADI.r)}, px);
      if (disc <= 0.0) discard;
      // the horizon's frame: the roll undone (the display turns the other way), pitch moves the horizon
      float c = cos(uRoll), s = sin(uRoll); mat2 rot = mat2(c, -s, s, c);
      vec2 q = rot * p, dqx = rot * dpx, dqy = rot * dpy;
      float y = q.y + uPitch * ${f(ADI.k)}, deg = y / ${f(ADI.k)};
      vec3 col = y > 0.0 ? mix(${v3(SKY_LO)}, ${v3(SKY_HI)}, smoothstep(0.0, 35.0, deg)) : mix(${v3(GND_HI)}, ${v3(GND_LO)}, smoothstep(0.0, 35.0, -deg));
      vec4 P = vec4(col, 1.0);
      P = over(P, vec3(1.0), band(abs(y), ${f(ADI.line / 2)}, px));
      // pitch ladder: the nearest rung (2.5 deg apart), numbered every 10, faded toward the window's edge
      float win = 1.0 - smoothstep(${f(ADI.fade0)}, ${f(ADI.fade1)}, r);
      if (win > 0.0) {
        float n = floor(deg / ${f(ADI.rung)} + 0.5), L = n * ${f(ADI.rung)};
        if (abs(L) > 0.1 && abs(L) < 90.1) {
          bool ten = mod(n, 4.0) < 0.5;
          float hl = ten ? ${f(ADI.half[2])} : mod(n, 2.0) < 0.5 ? ${f(ADI.half[1])} : ${f(ADI.half[0])};
          float dy = (deg - L) * ${f(ADI.k)};
          P = over(P, vec3(1.0), band(abs(dy), ${f(ADI.line / 2)}, px) * fill(abs(q.x) - hl, px) * win);
          if (ten) {
            float sx = q.x < 0.0 ? -1.0 : 1.0, gc = sx * (hl + 0.03 + ${f(adv)});
            float a = max(glyph(floor(abs(L) / 10.0 + 0.5), 0.0, vec2(q.x - gc + ${f(adv / 2)}, dy), ${f(ADI.label)}, dqx, dqy),
                          glyph(0.0, 0.0, vec2(q.x - gc - ${f(adv / 2)}, dy), ${f(ADI.label)}, dqx, dqy));
            P = over(P, vec3(1.0), a * win);
          }
        }
      }
      // bank pointer: turns with the horizon
      P = over(P, vec3(1.0), tri(q, ${f(P.apex)}, ${f(P.base)}, ${f(P.half)}, px));
      // soft shade toward the ring
      P.rgb *= 1.0 - 0.35 * smoothstep(${f(ADI.rim[0])}, ${f(ADI.rim[1])}, r);
      // bank scale (fixed) and its zero index
      ${ticks}
      P = over(P, vec3(1.0), tri(p, ${f(I.apex)}, ${f(I.base)}, ${f(I.half)}, px));
      // aircraft symbol: black outline, yellow bars
      float d = 1e3; ${boxes}
      P = over(P, vec3(0.0), fill(d - ${f(SYMBOL.outline)}, px));
      P = over(P, ${v3(SYMBOL.fill)}, fill(d, px));
      gl_FragColor = P * disc * uAlpha;
    }`;
}

// the ball: sky, ground, horizon and ladder painted on a sphere (ball frame: y to the sky pole, z to the front at
// level flight). A rung for pitch L sits at latitude atan(gain tan L); rung lengths and numbers are measured along the
// surface, so they keep their size and curve with the ball. Shaded as a satin sphere lit from the upper left.
function ballShader() {
  const adv = advance(ADI.label), G = BALL.gain, RB = BALL.r;
  return {
    // the mesh is a fixed dome; the paint turns: uRotT takes a point on the dome into the ball's own frame
    vertexShader: `uniform mat3 uRotT; varying vec3 vPos; varying vec3 vN;
      void main(){ vPos = uRotT * position; vN = normalize(normalMatrix * normal); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `varying vec3 vPos; varying vec3 vN;
    ${LIB}
    void main(){
      vec3 n = normalize(vPos);
      float b = asin(clamp(n.y, -1.0, 1.0)), lon = atan(n.x, n.z);
      vec2 su = vec2(lon * ${f(RB)} * cos(b), b * ${f(RB)});          // surface coordinates, dial units
      vec2 dsx = dFdx(su), dsy = dFdy(su); float px = max(length(dsx), length(dsy));
      float deg = degrees(atan(tan(clamp(b, -1.5707, 1.5707)) / ${f(G)}));   // the pitch this latitude stands for
      vec3 col = b > 0.0 ? mix(${v3(SKY_LO)}, ${v3(SKY_HI)}, smoothstep(0.0, 35.0, deg)) : mix(${v3(GND_HI)}, ${v3(GND_LO)}, smoothstep(0.0, 35.0, -deg));
      vec4 P = vec4(col, 1.0);
      P = over(P, vec3(1.0), band(abs(su.y), ${f(ADI.line / 2)}, px));
      // the ladder fades out toward the rim (where the ball turns away), as the flat disc's does past its window
      float facing = normalize(vN).z, win = smoothstep(${f(BALL.fade[0])}, ${f(BALL.fade[1])}, facing);
      float nr = floor(deg / ${f(ADI.rung)} + 0.5), L = nr * ${f(ADI.rung)};
      if (win > 0.0 && abs(L) > 0.1 && abs(L) < 90.1) {
        bool ten = mod(nr, 4.0) < 0.5;
        float hl = ten ? ${f(ADI.half[2])} : mod(nr, 2.0) < 0.5 ? ${f(ADI.half[1])} : ${f(ADI.half[0])};
        float v = (b - atan(${f(G)} * tan(radians(L)))) * ${f(RB)}, u = su.x;
        P = over(P, vec3(1.0), band(abs(v), ${f(ADI.line / 2)}, px) * fill(abs(u) - hl, px) * win);
        if (ten) {
          float sx = u < 0.0 ? -1.0 : 1.0, gc = sx * (hl + 0.03 + ${f(adv)});
          float a = max(glyph(floor(abs(L) / 10.0 + 0.5), 0.0, vec2(u - gc + ${f(adv / 2)}, v), ${f(ADI.label)}, dsx, dsy),
                        glyph(0.0, 0.0, vec2(u - gc - ${f(adv / 2)}, v), ${f(ADI.label)}, dsx, dsy));
          P = over(P, vec3(1.0), a * win);
        }
      }
      // satin shading: a soft light from the upper left, darker toward the rim, a faint broad sheen (kept low so it
      // never hides the ladder)
      vec3 N = normalize(vN), Lt = normalize(vec3(-0.45, 0.55, 0.7));
      float diff = max(dot(N, Lt), 0.0), rim = 1.0 - max(N.z, 0.0);
      float sheen = pow(max(dot(N, normalize(Lt + vec3(0.0, 0.0, 1.0))), 0.0), 24.0);
      vec3 c = P.rgb * (0.66 + 0.42 * diff) * (1.0 - 0.5 * rim * rim) + 0.07 * sheen;
      gl_FragColor = vec4(c, 1.0);
    }`,
  };
}

// in front of the ball, fixed: the bank scale and its zero index; and the bank pointer, which turns with the roll
function faceShader() {
  const ticks = BANK.ticks.flatMap(([d, long]) => [[d, long], [-d, long]]).map(([d, long]) => {
    const r0 = BANK.r - (long ? BANK.long : BANK.short);
    return `{ vec2 n = vec2(${f(Math.sin(d * DEG))}, ${f(Math.cos(d * DEG))}); float al = dot(p, n), ac = abs(dot(p, vec2(n.y, -n.x)));
      P = over(P, vec3(1.0), band(ac, ${f(BANK.w / 2)}, px) * smoothstep(${f(r0)} - 0.5 * px, ${f(r0)} + 0.5 * px, al) * (1.0 - smoothstep(${f(BANK.r)} - 0.5 * px, ${f(BANK.r)} + 0.5 * px, al))); }`;
  }).join('\n');
  const Pt = BANK.pointer, I = BANK.index;
  return `uniform float uRoll, uAlpha; varying vec2 vP;
    ${LIB}
    void main(){
      vec2 p = vP; vec2 dpx = dFdx(p), dpy = dFdy(p); float px = max(length(dpx), length(dpy));
      vec4 P = vec4(0.0);
      ${ticks}
      P = over(P, vec3(1.0), tri(p, ${f(I.apex)}, ${f(I.base)}, ${f(I.half)}, px));
      float c = cos(uRoll), s = sin(uRoll); vec2 q = mat2(c, -s, s, c) * p;
      P = over(P, vec3(1.0), tri(q, ${f(Pt.apex)}, ${f(Pt.base)}, ${f(Pt.half)}, px));
      if (P.a < 0.002) discard;
      gl_FragColor = P * uAlpha;
    }`;
}

function symbolShader() {
  const boxes = SYMBOL.boxes.map(([x, y, w, h]) => `d = min(d, sdBox(p - vec2(${f(x)}, ${f(y)}), vec2(${f(w)}, ${f(h)})));`).join(' ');
  return `uniform float uAlpha; varying vec2 vP;
    ${LIB}
    void main(){
      vec2 p = vP; float px = max(length(dFdx(p)), length(dFdy(p)));
      float d = 1e3; ${boxes}
      vec4 P = over(vec4(0.0), vec3(0.0), fill(d - ${f(SYMBOL.outline)}, px));
      P = over(P, ${v3(SYMBOL.fill)}, fill(d, px));
      if (P.a < 0.002) discard;
      gl_FragColor = P * uAlpha;
    }`;
}

// one tape, side -1 (airspeed, left) or 1 (altitude, right); local coordinates centred on the tape
function tapeShader(side) {
  const T = TAPE, B = T.box, spec = side < 0 ? SPEED_TAPE : ALT_TAPE, speed = side < 0;
  const inner = -side * T.hw, advL = advance(T.label);
  const xrL = speed ? inner - (T.tick[1] + 0.025) : T.hw - 0.03;            // right end of the tape numbers
  const cap = speed ? SPEED_TAPE.cap : ALT_TAPE.small, adv = advance(cap);
  const xr = B.hw - 0.025, rollL = xr - (speed ? 1 : 2) * adv - 0.012, rollR = xr + 0.012;
  const edge = -side * B.hw, tip = -side * (B.hw + B.notch);
  // caption letters: centres and glyph indices
  let pen = 0; const cw = spec.caption.split('').map((ch) => EM[ch] / CAP * T.caption);
  const total = cw.reduce((a, b) => a + b, 0);
  const caption = spec.caption.split('').map((ch, i) => {
    const x = -total / 2 + pen + cw[i] / 2; pen += cw[i];
    return `a = max(a, glyph(${f(CHARS.indexOf(ch))}, 1.0, vec2(p.x - ${f(x)}, p.y - ${f(T.captionY)}), ${f(T.caption)}, dpx, dpy));`;
  }).join(' ');
  // notch: a triangle on the inner edge, as the max of its three edges' signed distances
  const nx = side < 0 ? 1 : -1;            // the notch points this way
  const notch = `{ vec2 a0 = vec2(${f(edge)}, ${f(B.notchH)}), a1 = vec2(${f(tip)}, 0.0), a2 = vec2(${f(edge)}, ${f(-B.notchH)});
      vec2 e0 = normalize(a1 - a0), e1 = normalize(a2 - a1);
      float d0 = ${f(nx)} * (e0.x * (p.y - a0.y) - e0.y * (p.x - a0.x)), d1 = ${f(nx)} * (e1.x * (p.y - a1.y) - e1.y * (p.x - a1.x)), d2 = ${f(-nx)} * (p.x - ${f(edge)});
      sd = min(sd, max(max(d0, d1), d2)); }`;
  const capB = ALT_TAPE.cap, advB = advance(capB);
  const digits = speed ? `
      // speed: three columns; the ones digit rolls in the tall window
      float j = floor((${f(xr)} - p.x) / ${f(adv)});
      if (j >= 0.0 && j < 3.0) {
        float c = j < 0.5 ? uCols.x : j < 1.5 ? uCols.y : uCols.z, lead = j < 0.5 ? 0.0 : j < 1.5 ? 10.0 : 100.0;
        float wh = j < 0.5 ? ${f(B.tall)} : ${f(B.hh)}, pitch = j < 0.5 ? ${f(ROLL_PITCH * cap)} : ${f(STATIC_PITCH())};
        float kf = c + p.y / pitch, k = floor(kf + 0.5), dg = mod(k, 10.0);
        if (abs(p.y) < wh - ${f(B.border)} && !(lead > 0.0 && uVal < lead && dg < 0.5))
          a = glyph(dg, 0.0, vec2(p.x - (${f(xr)} - (j + 0.5) * ${f(adv)}), (kf - k) * pitch), ${f(cap)}, dpx, dpy);
      }` : `
      // altitude: the last two digits roll in 20 ft steps in the tall window; hundreds and up as an odometer
      if (p.x > ${f(xr - 2 * adv)} && p.x < ${f(xr)} && abs(p.y) < ${f(B.tall - B.border)}) {
        float kf = uSmall + p.y / ${f(ROLL_PITCH * cap)}, k = floor(kf + 0.5), tens = mod(k, 5.0) * 2.0;
        bool first = p.x < ${f(xr - adv)};
        a = glyph(first ? tens : 0.0, 0.0, vec2(p.x - (first ? ${f(xr - 1.5 * adv)} : ${f(xr - 0.5 * adv)}), (kf - k) * ${f(ROLL_PITCH * cap)}), ${f(cap)}, dpx, dpy);
      }
      float j = floor((${f(rollL - 0.008)} - p.x) / ${f(advB)});
      if (j >= 0.0 && j < 3.0 && abs(p.y) < ${f(B.hh - B.border)}) {
        float c = j < 0.5 ? uCols.x : j < 1.5 ? uCols.y : uCols.z, lead = j < 0.5 ? 100.0 : j < 1.5 ? 1000.0 : 10000.0;
        float kf = c + p.y / ${f(STATIC_PITCH())}, k = floor(kf + 0.5), dg = mod(k, 10.0);
        if (!(uVal < lead && dg < 0.5))
          a = max(a, glyph(dg, 0.0, vec2(p.x - (${f(rollL - 0.008)} - (j + 0.5) * ${f(advB)}), (kf - k) * ${f(STATIC_PITCH())}), ${f(capB)}, dpx, dpy));
      }`;
  return `uniform float uVal, uSmall, uAlpha; uniform vec3 uCols; varying vec2 vP;
    ${LIB}
    void main(){
      vec2 p = vP; vec2 dpx = dFdx(p), dpy = dFdy(p); float px = max(length(dpx), length(dpy));
      vec4 P = vec4(0.0);
      float inTape = fill(sdBox(p, vec2(${f(T.hw)}, ${f(T.hh)})), px);
      P = over(P, vec3(0.0), inTape * ${f(T.bg)});
      float fade = clamp((${f(T.hh)} - abs(p.y)) / ${f(T.fade)}, 0.0, 1.0) * inTape;
      float v = uVal + p.y * ${f(spec.perR)};
      // ticks: every minor step, longer at each number; on the edge facing the ring
      float n = floor(v / ${f(spec.minor)} + 0.5), tv = n * ${f(spec.minor)};
      if (tv > ${f(spec.min)} - 0.001) {
        float len = mod(n, ${f(spec.label / spec.minor)}) < 0.5 ? ${f(T.tick[1])} : ${f(T.tick[0])};
        float x0 = ${side < 0 ? `${f(inner)} - len` : f(inner)}, x1 = x0 + len;
        float a = band(abs(v - tv) / ${f(spec.perR)}, ${f(T.tickW / 2)}, px) * fill(x0 - p.x, px) * fill(p.x - x1, px);
        P = over(P, vec3(1.0), a * fade);
      }
      // numbers, right-aligned
      float m = floor(v / ${f(spec.label)} + 0.5), lb = m * ${f(spec.label)};
      if (lb > ${f(spec.min)} - 0.001) {
        float j = floor((${f(xrL)} - p.x) / ${f(advL)});
        float nd = lb < 9.5 ? 1.0 : lb < 99.5 ? 2.0 : lb < 999.5 ? 3.0 : lb < 9999.5 ? 4.0 : 5.0;
        if (j >= 0.0 && j < nd) {
          float p10 = j < 0.5 ? 1.0 : j < 1.5 ? 10.0 : j < 2.5 ? 100.0 : j < 3.5 ? 1000.0 : 10000.0;
          float dg = mod(floor(lb / p10 + 0.001), 10.0);
          P = over(P, vec3(1.0), glyph(dg, 1.0, vec2(p.x - (${f(xrL)} - (j + 0.5) * ${f(advL)}), (v - lb) / ${f(spec.perR)}), ${f(T.label)}, dpx, dpy) * fade);
        }
      }
      // caption under the tape
      float a = 0.0; ${caption}
      P = over(P, vec3(1.0), a * 0.75);
      // readout box: main box, the taller rolling window, the notch; white edge, black inside
      float sd = sdBox(p, vec2(${f(B.hw)}, ${f(B.hh)}));
      sd = min(sd, sdBox(p - vec2(${f((rollL + rollR) / 2)}, 0.0), vec2(${f((rollR - rollL) / 2)}, ${f(B.tall)})));
      ${notch}
      P = over(P, vec3(0.9), fill(sd, px));
      P = over(P, vec3(0.0), fill(sd + ${f(B.border)}, px));
      a = 0.0;
      ${digits}
      P = over(P, vec3(1.0), a * fill(sd + ${f(B.border)}, px));
      gl_FragColor = P * uAlpha;
    }`;
}

export class Air3D {
  constructor(parent) {
    this.dig = glyphTexture();
    const mat = (fragmentShader, uniforms) => new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader, transparent: true, depthWrite: false, premultipliedAlpha: true,
      uniforms: { uDig: { value: this.dig }, uAlpha: { value: 1 }, ...uniforms },
    });
    this.group = new THREE.Group(); parent.add(this.group);
    // flat attitude disc
    this.adiMat = mat(adiShader(), { uPitch: { value: 0 }, uRoll: { value: 0 } });
    const adi = (this.flat = new THREE.Mesh(new THREE.PlaneGeometry(2 * ADI.r + 0.02, 2 * ADI.r + 0.02), this.adiMat));
    adi.position.z = 0; adi.renderOrder = 1;
    // attitude ball: as in the instrument, only its front shows: a fixed dome (the cap of the sphere that fits the
    // case) whose paint turns with pitch and roll, in a dark case; the fixed face (bank scale, index, pointer) and the
    // symbol sit in front
    this.ballGroup = new THREE.Group();
    const bs = ballShader(), depth = 0.45, zc = BALL.front - BALL.r;
    const cap = Math.acos((-depth - zc) / BALL.r);          // the dome's rim meets the case's back edge
    this.ballMat = new THREE.ShaderMaterial({ vertexShader: bs.vertexShader, fragmentShader: bs.fragmentShader,
      uniforms: { uDig: { value: this.dig }, uRotT: { value: new THREE.Matrix3() } } });
    this.ball = new THREE.Mesh(new THREE.SphereGeometry(BALL.r, 96, 40, 0, Math.PI * 2, 0, cap).rotateX(Math.PI / 2), this.ballMat);
    this.ball.position.z = zc;
    this._e = new THREE.Euler(0, 0, 0, 'ZXY'); this._m4 = new THREE.Matrix4();
    const caseMesh = new THREE.Mesh(new THREE.CylinderGeometry(0.955, 0.955, depth, 96, 1, true).rotateX(Math.PI / 2),
      new THREE.MeshBasicMaterial({ color: 0x0a0b0e, side: THREE.DoubleSide, toneMapped: false }));
    caseMesh.position.z = -depth / 2;
    this.faceMat = mat(faceShader(), { uRoll: { value: 0 } });
    const face = new THREE.Mesh(new THREE.RingGeometry(0.68, 0.9, 96, 1), this.faceMat);
    face.position.z = 0.03; face.renderOrder = 3;
    const sym = new THREE.Mesh(new THREE.PlaneGeometry(0.92, 0.24), mat(symbolShader(), {}));
    sym.position.set(0, 0, BALL.front + 0.04); sym.renderOrder = 4;
    this.ballGroup.add(this.ball, caseMesh, face, sym);
    this.style = 'ball'; adi.visible = false;
    this.tapes = [-1, 1].map((side) => {
      const m = mat(tapeShader(side), { uVal: { value: 0 }, uSmall: { value: 0 }, uCols: { value: new THREE.Vector3() } });
      const w = 2 * (TAPE.box.hw + TAPE.box.notch) + 0.04, h = 2 * Math.max(TAPE.hh, -TAPE.captionY + TAPE.caption) + 0.04;
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, h), m);
      mesh.position.set(side * TAPE.x, 0, 0.01); mesh.renderOrder = 2;
      return { side, m, mesh };
    });
    this.group.add(adi, this.ballGroup, ...this.tapes.map((t) => t.mesh));
    this.last = {};
  }

  set visible(v) { this.group.visible = v; }

  // 'ball' (a 3D gyro horizon) or 'flat' (the 2D dial's disc)
  setStyle(style) {
    this.style = style === 'flat' ? 'flat' : 'ball';
    this.flat.visible = this.style === 'flat'; this.ballGroup.visible = this.style === 'ball';
    this.last = {};
  }

  refreshText() { this.dig.redraw(); this.last = {}; }

  // returns true when something visible changed
  update(s) {
    const L = this.last, pitch = s.pitch || 0, roll = (s.roll || 0) * DEG, spd = airspeed(s), alt = altitudeFt(s);
    let changed = false;
    if (L.pitch !== pitch || L.roll !== roll) {
      this.adiMat.uniforms.uPitch.value = pitch; this.adiMat.uniforms.uRoll.value = roll;
      // the ball turns Rz(roll) Rx(latitude): the paint's frame is that rotation's transpose
      this._m4.makeRotationFromEuler(this._e.set(ballLatitude(pitch), 0, roll));
      this.ballMat.uniforms.uRotT.value.setFromMatrix4(this._m4).transpose();
      this.faceMat.uniforms.uRoll.value = roll;
      L.pitch = pitch; L.roll = roll; changed = true;
    }
    if (L.spd !== spd) {
      const u = this.tapes[0].m.uniforms, c = speedColumns(spd);
      u.uVal.value = spd; u.uCols.value.set(c[0], c[1], c[2]); L.spd = spd; changed = true;
    }
    if (L.alt !== alt) {
      const u = this.tapes[1].m.uniforms, { small, big } = altColumns(alt);
      u.uVal.value = alt; u.uSmall.value = small; u.uCols.value.set(big[0], big[1], big[2]); L.alt = alt; changed = true;
    }
    return changed;
  }
}
