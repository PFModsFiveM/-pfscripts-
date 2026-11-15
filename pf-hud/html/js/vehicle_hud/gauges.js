// Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
// Free software under the GNU Lesser General Public License 3.0 (pf-hud/COPYING.LESSER and COPYING).
// Extra gauges: generic circular stats the framework can add at any time (turbo pressure, boost, coolant, hacking
// progress, weapon cooldown, fuel ... anything). Each one is { id, icon, value 0-1, text?, danger?, dangerLow? }:
// danger is where a red zone at the top starts (0-1, like the dial's redline; turbo, coolant), dangerLow where one at
// the bottom ends (fuel, health, oxygen). A value inside either red zone makes the gauge critical: its icon flashes.
//
// Placement: they orbit the dial on a concentric arc (centres at 1.42R, each 0.26R in radius), 28 deg apart: slot 1
// at the lower-left (-130 deg, as low as the arc goes and stays on screen with the dial this low), each next one above
// the last, up the dial's left side. So 1-5 gauges hug the rim, stay clear of the screen edges and never cover the
// dial. In aircraft mode the airspeed tape takes the left, so the group fans over the top instead (AIR_ORBIT), a little
// further out. Each gauge is a miniature of the dial: the same 270 deg ring, white fill, red zone and tick, the stat's
// icon in the middle and its value in the bottom gap.
import { AIR_ORBIT } from './air.js';

export const ORBIT = 1.42, SAT_R = 0.26, STEP = 28, START = -130, MAX_GAUGES = 5;
const DEG = Math.PI / 180;
const rad = (deg) => (deg - 90) * DEG;                     // canvas angle for a clockwise-from-12 angle
const CAP = 0.711;
const clamp01 = (v) => Math.max(0, Math.min(1, v));

// slot angles (deg clockwise from 12) for n gauges: up the left side from the lower-left, or the aircraft fan
export function slotAngles(n, kind) {
  if (kind === 'air') return Array.from({ length: n }, (_, i) => AIR_ORBIT.centre + (i - (n - 1) / 2) * AIR_ORBIT.step);
  return Array.from({ length: n }, (_, i) => START + i * STEP);
}

// UPSTREAM EDIT (interpolation between updates): each gauge's ring eases toward its
// value instead of jumping, like the needle. the HUD sends the stats at most ten times a second, a turbo's boost about
// that often and fuel far less; a 1/8 s time constant covers a 10 Hz gap and still answers a jump at once. The text
// and the critical flash stay on the true value.
const GAUGE_EASE = 8;

// Springs each gauge to its slot: new ones rise out from behind the ring, removed ones sink back and fade, the rest
// slide round the rim to make room (and round to the fan and back when the kind changes). `value` in each item is the
// eased value the ring draws. Items come out as an angle and distance from the dial's centre.
export class GaugeLayout {
  constructor() { this.items = new Map(); }
  update(gauges, dt, kind = 'car') {
    const shown = gauges.filter((g) => g.on).slice(0, MAX_GAUGES);
    const slots = slotAngles(shown.length, kind), orbit = kind === 'air' ? AIR_ORBIT.orbit : ORBIT;
    shown.forEach((g, i) => {
      let it = this.items.get(g.id);
      if (!it) { it = { a: slots[i], va: 0, o: orbit, vo: 0, show: 0, vs: 0, v: clamp01(Number(g.value) || 0) }; this.items.set(g.id, it); }
      it.ta = slots[i]; it.to = orbit; it.g = g;
    });
    const out = [];
    for (const [id, it] of this.items) {
      const on = shown.includes(it.g);
      if (on) {
        it.va += (90 * (it.ta - it.a) - 13 * it.va) * dt; it.a += it.va * dt;
        it.vo += (90 * (it.to - it.o) - 13 * it.vo) * dt; it.o += it.vo * dt;
      }
      it.vs += (110 * ((on ? 1 : 0) - it.show) - 15 * it.vs) * dt; it.show += it.vs * dt;
      if (!on && it.show < 0.02) { this.items.delete(id); continue; }
      const to = clamp01(Number(it.g.value) || 0);
      it.v += (to - it.v) * (1 - Math.exp(-GAUGE_EASE * dt));
      if (Math.abs(to - it.v) < 5e-4) it.v = to;             // settled: the dial stops redrawing it
      const k = clamp01(it.show);
      out.push({ g: it.g, value: it.v, angle: it.a, show: k, orbit: 1.08 + (it.o - 1.08) * k });
    }
    return out;
  }
}

export const gaugeCritical = (g) => (g.danger != null && g.value >= g.danger) || (g.dangerLow != null && g.value <= g.dangerLow);

// UPSTREAM EDIT: a gauge's end markers, `ends: ['E', 'F']` (the empty end's, then the full end's, up to 3 characters
// each), or null. With them the gauge shows no value: the markers sit at the arc's two ends in the bottom gap
// instead, as a fuel gauge's E and F. ENDS_X: how far each sits from the centre, in gauge radii.
export const ENDS_X = 0.42;
export function gaugeEnds(g) {
  const e = g && g.ends;
  if (!Array.isArray(e) || e.length !== 2) return null;
  const a = String(e[0] ?? '').slice(0, 3), b = String(e[1] ?? '').slice(0, 3);
  return a || b ? [a, b] : null;
}

// Any other icon string is an SVG path in a 24x24 viewBox (the Material shape a stat registers with, e.g.
// 'M19.77 7.23...'): filled, fitted to the same box. Parsed once per string; anything that isn't a path draws a dot.
const PATH_OK = /^\s*[Mm][\sMmZzLlHhVvCcSsQqTtAa0-9eE+\-.,]*$/;
const PATHS = new Map();
function svgPath(icon) {
  if (PATHS.has(icon)) return PATHS.get(icon);
  let p = null;
  if (typeof icon === 'string' && PATH_OK.test(icon) && typeof Path2D !== 'undefined') {
    try { p = new Path2D(icon); } catch { p = null; }
  }
  if (PATHS.size > 200) PATHS.clear();
  PATHS.set(icon, p);
  return p;
}

// UPSTREAM EDIT: built-in icons drawn from a filled 24x24 path, as a stat's own icon is (over the
// line drawings they replace):
//   coolant  the car's coolant warning light: Material Design Icons' "coolant-temperature" (Pictogrammers, Apache 2.0)
//   turbo    Material Design Icons' "car-turbocharger" (Apache 2.0): the same drawing js/glyphs.js gives every turbo
//            button upstream
//   nitro    drawn upstream: a filled nitrous bottle, valve on top, with a lightning bolt cut out of it (the bolt is
//            wound the other way round, so the fill leaves it empty)
const GLYPH_PATHS = new Map([
  ['turbo', 'M22 13V15H18.32C18.75 14.09 19 13.08 19 12C19 8.14 15.86 5 12 5H2V3H12C16.97 3 21 7.03 21 12C21 12.34 20.97 12.67 20.94 13H22M12 19C8.14 19 5 15.86 5 12C5 10.93 5.25 9.91 5.69 9H2V11H3.06C3.03 11.33 3 11.66 3 12C3 16.97 7.03 21 12 21H22V19H12M16.86 12.2C15.93 12.94 14.72 12.47 14 12.05V12C16.79 10.31 15.39 7.89 15.39 7.89S14.33 6.04 14.61 7.89C14.78 9.07 13.76 9.88 13.04 10.3L13 10.28C12.93 7 10.13 7 10.13 7S8 7 9.74 7.69C10.85 8.13 11.04 9.42 11.05 10.25L11 10.28C8.14 8.7 6.74 11.12 6.74 11.12S5.67 12.97 7.14 11.8C8.07 11.07 9.28 11.54 10 11.95V12C7.21 13.7 8.61 16.12 8.61 16.12S9.67 17.97 9.4 16.11C9.22 14.94 10.25 14.13 10.97 13.7L11 13.73C11.07 17 13.87 17 13.87 17S16 17 14.26 16.31C13.15 15.87 12.96 14.58 12.95 13.75L13 13.73C15.86 15.31 17.26 12.88 17.26 12.88S18.33 11.04 16.86 12.2Z'],
  ['nitro', 'M9.5 8H14.5A2.5 2.5 0 0 1 17 10.5V19.5A2.5 2.5 0 0 1 14.5 22H9.5A2.5 2.5 0 0 1 7 19.5V10.5A2.5 2.5 0 0 1 9.5 8Z M10.5 5H13.5V8H10.5Z M8.5 2H15.5A1 1 0 0 1 15.5 4H8.5A1 1 0 0 1 8.5 2Z M11.2 4H12.8V5H11.2Z M13.2 10.6L9.8 15.8H12L10.8 20L14.2 14.2H12.1Z'],
  ['coolant', 'M11.5,1A1.5,1.5 0 0,0 10,2.5V14.5C9.37,14.97 9,15.71 9,16.5A2.5,2.5 0 0,0 11.5,19A2.5,2.5 0 0,0 14,16.5C14,15.71 13.63,15 13,14.5V13H17V11H13V9H17V7H13V5H17V3H13V2.5A1.5,1.5 0 0,0 11.5,1M0,15V17C0.67,17 0.79,17.21 1.29,17.71C1.79,18.21 2.67,19 4,19C5.33,19 6.21,18.21 6.71,17.71C6.82,17.59 6.91,17.5 7,17.41V15.16C6.21,15.42 5.65,15.93 5.29,16.29C4.79,16.79 4.67,17 4,17C3.33,17 3.21,16.79 2.71,16.29C2.21,15.79 1.33,15 0,15M16,15V17C16.67,17 16.79,17.21 17.29,17.71C17.79,18.21 18.67,19 20,19C21.33,19 22.21,18.21 22.71,17.71C23.21,17.21 23.33,17 24,17V15C22.67,15 21.79,15.79 21.29,16.29C20.79,16.79 20.67,17 20,17C19.33,17 19.21,16.79 18.71,16.29C18.21,15.79 17.33,15 16,15M8,20C6.67,20 5.79,20.79 5.29,21.29C4.79,21.79 4.67,22 4,22C3.33,22 3.21,21.79 2.71,21.29C2.35,20.93 1.79,20.42 1,20.16V22.41C1.09,22.5 1.18,22.59 1.29,22.71C1.79,23.21 2.67,24 4,24C5.33,24 6.21,23.21 6.71,22.71C7.21,22.21 7.33,22 8,22C8.67,22 8.79,22.21 9.29,22.71C9.73,23.14 10.44,23.8 11.5,23.96C11.66,24 11.83,24 12,24C13.33,24 14.21,23.21 14.71,22.71C15.21,22.21 15.33,22 16,22C16.67,22 16.79,22.21 17.29,22.71C17.79,23.21 18.67,24 20,24C21.33,24 22.21,23.21 22.71,22.71C22.82,22.59 22.91,22.5 23,22.41V20.16C22.21,20.42 21.65,20.93 21.29,21.29C20.79,21.79 20.67,22 20,22C19.33,22 19.21,21.79 18.71,21.29C18.21,20.79 17.33,20 16,20C14.67,20 13.79,20.79 13.29,21.29C12.79,21.79 12.67,22 12,22C11.78,22 11.63,21.97 11.5,21.92C11.22,21.82 11.05,21.63 10.71,21.29C10.21,20.79 9.33,20 8,20Z'],
]);

// icon glyphs for gauges, drawn in a box of half-size u around (x, y)
export function drawGlyph(ctx, icon, x, y, u, color) {
  ctx.save();
  ctx.translate(x, y);
  ctx.strokeStyle = color; ctx.fillStyle = color;
  ctx.lineWidth = Math.max(1, u * 0.16); ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  const line = (pts) => { ctx.beginPath(); pts.forEach(([px, py], i) => (i ? ctx.lineTo(px * u, py * u) : ctx.moveTo(px * u, py * u))); ctx.stroke(); };
  if (icon === 'hack') {                      // padlock
    // UPSTREAM EDIT: the shackle as the dial's lock light has it (dial.js) — straight legs up out of
    // the body and a full arch, reaching the top of the box as the fuel pump does — not a stub on the body.
    ctx.beginPath(); ctx.roundRect(-0.52 * u, -0.08 * u, 1.04 * u, 0.86 * u, 0.12 * u); ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(-0.32 * u, -0.08 * u); ctx.lineTo(-0.32 * u, -0.4 * u);
    ctx.arc(0, -0.4 * u, 0.32 * u, Math.PI, 0);
    ctx.lineTo(0.32 * u, -0.08 * u);
    ctx.stroke();
    ctx.beginPath(); ctx.arc(0, 0.3 * u, 0.09 * u, 0, Math.PI * 2); ctx.fill();
    line([[0, 0.34], [0, 0.56]]);
  } else if (icon === 'fuel' || icon === 'fuel_left' || icon === 'fuel_right') {   // fuel pump
    // UPSTREAM EDIT: 'fuel_left' / 'fuel_right' (a fuel resource, by the car): the same pump, smaller and to one side, with an
    // arrow to the side of the car its filler is on, as a car's own fuel gauge has.
    const side = icon === 'fuel_left' ? -1 : icon === 'fuel_right' ? 1 : 0;
    ctx.save();
    if (side) {
      const k = 0.84;
      ctx.translate((side < 0 ? 0.2 : -0.16) * u, 0); ctx.scale(k, k); ctx.lineWidth /= k;
    }
    ctx.beginPath(); ctx.rect(-0.62 * u, -0.72 * u, 0.72 * u, 1.38 * u); ctx.stroke();
    ctx.fillRect(-0.48 * u, -0.58 * u, 0.44 * u, 0.36 * u);
    line([[-0.8, 0.68], [0.28, 0.68]]);
    line([[0.1, -0.14], [0.4, -0.14], [0.4, 0.38], [0.66, 0.38], [0.66, -0.36], [0.44, -0.62]]);
    ctx.restore();
    if (side) {                               // the arrow: its tip out to that side, level with the pump's middle
      ctx.beginPath();
      ctx.moveTo(side * 0.95 * u, -0.04 * u);
      ctx.lineTo(side * 0.62 * u, -0.27 * u);
      ctx.lineTo(side * 0.62 * u, 0.19 * u);
      ctx.closePath(); ctx.fill();
    }
  } else if (icon === 'weapon') {             // crosshair
    ctx.beginPath(); ctx.arc(0, 0, 0.56 * u, 0, Math.PI * 2); ctx.stroke();
    line([[0, -0.92], [0, -0.3]]); line([[0, 0.3], [0, 0.92]]); line([[-0.92, 0], [-0.3, 0]]); line([[0.3, 0], [0.92, 0]]);
    ctx.beginPath(); ctx.arc(0, 0, 0.08 * u, 0, Math.PI * 2); ctx.fill();
  } else {
    const path = svgPath(GLYPH_PATHS.get(icon) || icon);
    if (path) {                               // 24x24 viewBox, centred, filling the glyph box (0.92u half-size)
      const k = (1.84 * u) / 24;
      ctx.scale(k, k); ctx.translate(-12, -12); ctx.fill(path);
    } else {                                  // unknown icon: a dot, so a gauge never renders empty
      ctx.beginPath(); ctx.arc(0, 0, 0.3 * u, 0, Math.PI * 2); ctx.fill();
    }
  }
  ctx.restore();
}

// one gauge on the 2D dial's canvas: cx, cy = dial centre, R = dial radius (px); memo keeps this gauge's gradients
// while it sits still (they only change when it moves or resizes)
export function drawGauge2D(ctx, cx, cy, R, item, t, memo = {}) {
  const { g, angle, show, orbit } = item;
  const x = cx + orbit * R * Math.sin(angle * DEG), y = cy - orbit * R * Math.cos(angle * DEG);
  const r = SAT_R * R * (0.6 + 0.4 * show);
  const v = clamp01(item.value ?? g.value), hi = g.danger == null ? 2 : g.danger, lo = g.dangerLow == null ? -1 : g.dangerLow;
  const n0 = Math.max(0, lo), n1 = Math.min(1, hi);           // the normal (white) range between the red zones
  const crit = gaugeCritical(g), blink = crit && Math.sin(t * 10) > 0;
  const A = (f) => -135 + 270 * f;
  const ann = (r0, r1, a0, a1) => {
    ctx.beginPath(); ctx.arc(x, y, r1 * r, rad(a0), rad(a1)); ctx.arc(x, y, r0 * r, rad(a1), rad(a0), true); ctx.closePath();
  };
  if (memo.x !== x || memo.y !== y || memo.r !== r) {
    const ramp = (stops) => {
      const gr = ctx.createRadialGradient(x, y, 0.45 * r, x, y, 0.86 * r);
      for (const [o, c] of stops) gr.addColorStop(o, c);
      return gr;
    };
    memo.x = x; memo.y = y; memo.r = r;
    memo.red = ramp([[0, 'rgba(215,12,40,0)'], [1, 'rgba(215,12,40,0.45)']]);
    memo.lit = ramp([[0, 'rgba(255,255,255,0)'], [1, 'rgba(255,255,255,0.4)']]);
    memo.hot = ramp([[0, 'rgba(255,40,70,0)'], [1, 'rgba(255,60,90,0.45)']]);
  }
  ctx.save();
  ctx.globalAlpha = show;
  // red zone floors + lit sweep, the dial's radial ramp (the lit part glows red where it is inside a red zone)
  const zones = [];
  if (lo >= 0) zones.push([0, lo]);
  if (hi <= 1) zones.push([hi, 1]);
  for (const [z0, z1] of zones) { ann(0.45, 0.86, A(z0), A(z1)); ctx.fillStyle = memo.red; ctx.fill(); }
  if (v > n0) { ann(0.45, 0.86, A(n0), A(Math.min(v, n1))); ctx.fillStyle = memo.lit; ctx.fill(); }
  for (const [z0, z1] of zones) if (v > z0) { ann(0.45, 0.86, A(z0), A(Math.min(v, z1))); ctx.fillStyle = memo.hot; ctx.fill(); }
  // ring: track, red zones, lit part
  ann(0.86, 1, A(n0), A(n1)); ctx.fillStyle = 'rgba(255,255,255,0.19)'; ctx.fill();
  for (const [z0, z1] of zones) { ann(0.86, 1, A(z0), A(z1)); ctx.fillStyle = 'rgba(225,50,72,0.92)'; ctx.fill(); }
  if (v > n0) { ann(0.86, 1, A(n0), A(Math.min(v, n1))); ctx.fillStyle = 'rgba(255,255,255,0.82)'; ctx.fill(); }
  for (const [z0, z1] of zones) if (v > z0) { ann(0.86, 1, A(z0), A(Math.min(v, z1))); ctx.fillStyle = 'rgb(255,92,112)'; ctx.fill(); }
  // tick at the value, the dial's needle in small
  const a = A(v) * DEG, px = Math.cos(a), py = Math.sin(a);
  const p0 = [x + Math.sin(a) * 0.5 * r, y - Math.cos(a) * 0.5 * r], p1 = [x + Math.sin(a) * 0.9 * r, y - Math.cos(a) * 0.9 * r];
  ctx.beginPath();
  ctx.moveTo(p0[0] - px * 0.05 * r, p0[1] - py * 0.05 * r); ctx.lineTo(p1[0] - px * 0.018 * r, p1[1] - py * 0.018 * r);
  ctx.lineTo(p1[0] + px * 0.018 * r, p1[1] + py * 0.018 * r); ctx.lineTo(p0[0] + px * 0.05 * r, p0[1] + py * 0.05 * r);
  ctx.closePath(); ctx.fillStyle = '#fff'; ctx.fill();
  // icon in the middle, value in the bottom gap
  drawGlyph(ctx, g.icon, x, y - 0.03 * r, 0.3 * r, blink ? 'rgb(255,96,110)' : 'rgba(255,255,255,0.92)');
  // UPSTREAM EDIT: `ends` (gaugeEnds) puts a marker at each end of the arc instead of the value, as a fuel gauge's E
  // and F: the empty end's on the left of the gap, the full end's on the right
  const ends = gaugeEnds(g);
  if (ends || g.text) {
    const fs = 0.3 * r;
    ctx.font = `italic 700 ${fs}px Roboto, "Helvetica Neue", Arial, sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = crit ? 'rgb(255,110,128)' : 'rgba(255,255,255,0.9)';
    const base = y + 0.8 * r + (CAP * fs) / 2;
    if (ends) {
      ctx.fillText(ends[0], x - ENDS_X * r, base);
      ctx.fillText(ends[1], x + ENDS_X * r, base);
    } else {
      ctx.fillText(g.text, x, base);
    }
  }
  ctx.restore();
}
