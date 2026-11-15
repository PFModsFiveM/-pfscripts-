// Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
// Free software under the GNU Lesser General Public License 3.0 (pf-hud/COPYING.LESSER and COPYING).
// What both dials share (and all the 3D dial needs besides gauges.js and three.js): the layout box, the status
// lights, the rev scale and the speed / gear formatting. No state of its own: everything reads the vehicle state
// object (see the README's state contract).
// the NUI bundles its Roboto subset under its own family name (registered by hud.js), so it can never clash with a
// host page's fonts; anywhere else Roboto (or a system face) takes over
export const FONT_FAMILY = 'pf-hud-roboto';
export const FONT = `"${FONT_FAMILY}", Roboto, "Helvetica Neue", Arial, sans-serif`;
const CAP = 0.711;                                              // Roboto cap height / em

import { POWER_SCALE } from './boat.js';

// layout box (shared by both HUDs), dial centre at (1.9R, 1.9R): room to the left for the extra gauges up the dial's
// left side (five at most, see gauges.js), up for their fan over the top in aircraft mode, and right for the altitude
// tape (see air.js)
export const BOX = { w: 3.37, h: 3.15, cx: 1.9, cy: 1.9 };

// status lights on an arc below the centre: angle (deg clockwise from 12) and radius (dial radii)
// UPSTREAM EDIT: the third light is the engine (on / off), in the handbrake's P's place.
export const ICONS = [
  { id: 'lock', a: 150.9, r: 0.778 }, { id: 'lights', a: 170.7, r: 0.787 },
  { id: 'engine', a: 189.6, r: 0.785 }, { id: 'warn', a: 210.5, r: 0.776 },
];
// status light styles (shared constants: no allocation per frame). k = short key for caches and change checks.
const style = (k, css, hex, glow, variant) => Object.freeze({ k, css, hex, glow, variant });
const ST = {
  lightsOff: style('a', 'rgba(255,255,255,0.42)', 0x5d626b, false, 'low'),
  lightsLow: style('b', 'rgb(60,214,110)', 0x3cd66e, false, 'low'),
  lightsHigh: style('c', 'rgb(70,140,255)', 0x468cff, true, 'high'),
  lit: style('g', 'rgba(255,255,255,0.95)', 0xffffff, false),
  parkOff: style('h', 'rgba(255,255,255,0.42)', 0x5d626b, false),
  warnOn: style('i', 'rgb(255,96,80)', 0xff6050, true), warnOff: style('j', 'rgba(255,96,80,0.5)', 0xa33a30, false),
  warnIdle: style('k', 'rgba(255,255,255,0.55)', 0x6a6f78, false),
  gearDown: style('l', 'rgb(60,214,110)', 0x3cd66e, false), gearMoving: style('m', 'rgb(255,96,80)', 0xff6050, true),
};

// the first light is the lock in a car, the landing gear in the air (s.kind 'air') and the anchor on a boat ('boat')
export const iconId = (s, id) => (id !== 'lock' ? id : s.kind === 'air' ? 'gear' : s.kind === 'boat' ? 'anchor' : id);

// colour of each status light. Lock: lit when the vehicle is locked, grey when unlocked. Headlights: grey off, green
// low beam, blue high beam (the usual tell-tale colours). Engine: lit while it runs, grey when off. Warning: flashes on
// engine damage.
export function indicatorStyle(s, id) {
  const flash = Math.sin(s.t * 9) > 0;
  if (id === 'lights') return s.lights === 'high' ? ST.lightsHigh : s.lights === 'low' ? ST.lightsLow : ST.lightsOff;
  if (id === 'lock') return s.locked ? ST.lit : ST.parkOff;
  if (id === 'engine') return s.engine ? ST.lit : ST.parkOff;
  // landing gear: green when down, red while it moves, grey when up (or the aircraft has none)
  if (id === 'gear') return s.gearState === 'down' ? ST.gearDown : s.gearState === 'moving' ? ST.gearMoving : ST.parkOff;
  if (id === 'anchor') return s.anchored ? ST.lit : ST.parkOff;          // lit while the anchor is down
  return s.damage ? (flash ? ST.warnOn : ST.warnOff) : ST.warnIdle;
}

// a status light is lit (raised, and its segment in the ring's gap below lights in its colour) unless it's grey
export const indicatorLit = (st) => st.hex !== 0x5d626b && st.hex !== 0x6a6f78;

// Rev range: a vehicle's top of scale (2-20, thousands of rpm) and redline (by default the reference's proportion,
// 6.5 of 7.5). revScale gives the numeral step (at most 11 numerals, whole thousands from 4k up), the tick spacing and
// the numerals. Cached: the dials ask every frame.
export const MIN_RANGE = 2, MAX_RANGE = 20, REF_MAX = 7.5, REF_REDLINE = 6.5;
const SCALES = new Map();
export function revScale(max, redline) {
  const key = max + '/' + redline;
  let sc = SCALES.get(key);
  if (sc) return sc;
  const step = max <= 3.5 ? 0.5 : max <= 10.5 ? 1 : 2;
  const minor = step / 10;
  const labels = [];
  for (let i = 0; i * step <= max + 1e-9; i++) {
    const v = +(i * step).toFixed(2);
    labels.push({ v, text: Number.isInteger(v) ? String(v) : v.toFixed(1) });
  }
  sc = { max, redline, step, minor, mid: step / 2, labels, ticks: Math.floor(max / minor + 1e-9) + 1 };
  SCALES.set(key, sc);
  return sc;
}

// the dial's scale and the value its needle shows: revs (thousands) in a car, power (0-100%) on a boat
export const dialScale = (s) => (s.kind === 'boat' ? POWER_SCALE : revScale(s.maxRpm, s.redline));
export const dialValue = (s, sc) => Math.max(0, Math.min(sc.max, sc.power ? (s.power || 0) * 100 : s.rpm));

// Limiter bounce: once the needle is ON the limiter, it swings smoothly (a cosine ease) LIMITER_DROP
// (thousand rpm) down and back, LIMITER_STEP seconds each way, starting from where it sits. limiterDip(heldFor): how far
// below its own position to draw the needle, heldFor seconds into the bounce (0 at the start, so engaging never moves
// it). Hosts ease the dip back to 0 when the limiter lets go, so the needle never snaps up either.
export const LIMITER_DROP = 1.0, LIMITER_STEP = 0.05;
export const limiterDip = (heldFor) => (LIMITER_DROP * (1 - Math.cos((Math.PI * heldFor) / LIMITER_STEP))) / 2;

export const defaultRedline = (max) => Math.round(((max * REF_REDLINE) / REF_MAX) / (max <= 3.5 ? 0.05 : max <= 10.5 ? 0.1 : 0.2)) * (max <= 3.5 ? 0.05 : max <= 10.5 ? 0.1 : 0.2);

// speed arrives in km/h; units 'kmh' | 'mph'
export function displaySpeed(s) {
  return Math.round(s.units === 'mph' ? s.speed * 0.621371 : s.speed);
}

// gear: a number, 'R' or 'N'; a parked vehicle shows N
export function gearLabel(s) {
  return s.parked ? 'N' : String(s.gear);
}

// The engine light's symbol: the dashboard engine block, Material Design Icons' "engine" (Pictogrammers, Apache 2.0),
// in its 24x24 viewBox. Parsed on first use (UPSTREAM EDIT).
const ENGINE_D = 'M7,4V6H10V8H7L5,10V13H3V10H1V18H3V15H5V18H8L10,20H18V16H20V19H23V9H20V12H18V8H12V6H15V4H7Z';
let enginePath = null;

// status light glyphs inside a 0.069R circle (warning: a bare triangle, as in the reference)
export function drawIcon(ctx, id, x, y, R, st) {
  ctx.save();
  ctx.translate(x, y);
  ctx.strokeStyle = st.css; ctx.fillStyle = st.css;
  ctx.lineWidth = 0.0095 * R; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
  if (st.glow) { ctx.shadowColor = st.css; ctx.shadowBlur = 0.06 * R; }
  const r = 0.069 * R;
  ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic';
  const ring = () => { ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.stroke(); };
  const line = (pts) => { ctx.beginPath(); pts.forEach(([px, py], i) => (i ? ctx.lineTo(px * r, py * r) : ctx.moveTo(px * r, py * r))); ctx.stroke(); };
  if (id === 'lights') {                       // headlamp: beams slant down for low beam, run level for high beam
    ring();
    ctx.lineWidth = 0.008 * R;
    ctx.beginPath(); ctx.moveTo(0.02 * r, -0.4 * r); ctx.bezierCurveTo(0.62 * r, -0.4 * r, 0.62 * r, 0.4 * r, 0.02 * r, 0.4 * r); ctx.closePath(); ctx.stroke();
    const dy = st.variant === 'high' ? 0 : 0.16;
    for (const by of [-0.27, 0, 0.27]) line([[-0.12, by], [-0.6, by + dy]]);
  } else if (id === 'lock') {                  // padlock
    // UPSTREAM EDIT: the shackle is straight legs up out of the body and a full arch over them, as tall as the body is, the whole lock filling the ring as the
    // headlamp and the engine do.
    ring();
    ctx.lineWidth = 0.008 * R;
    ctx.beginPath(); ctx.roundRect(-0.36 * r, -0.02 * r, 0.72 * r, 0.5 * r, 0.08 * r); ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(-0.22 * r, -0.02 * r); ctx.lineTo(-0.22 * r, -0.3 * r);
    ctx.arc(0, -0.3 * r, 0.22 * r, Math.PI, 0);
    ctx.lineTo(0.22 * r, -0.02 * r);
    ctx.stroke();
    ctx.beginPath(); ctx.arc(0, 0.19 * r, 0.065 * r, 0, Math.PI * 2); ctx.fill();
    line([[0, 0.21], [0, 0.34]]);
  } else if (id === 'engine') {               // engine block, filled, 1.1r wide (its corners stay inside the ring)
    ring();
    if (!enginePath && typeof Path2D !== 'undefined') enginePath = new Path2D(ENGINE_D);
    if (enginePath) {
      const k = (1.1 * r) / 22;
      ctx.scale(k, k); ctx.translate(-12, -12); ctx.fill(enginePath);
    }
  } else if (id === 'gear') {                 // landing gear: a wheel on its leg
    ring();
    ctx.lineWidth = 0.0085 * R;
    line([[0, -0.5], [0, 0.06]]); line([[-0.3, -0.5], [0.3, -0.5]]); line([[0, -0.22], [0.26, -0.44]]);
    ctx.beginPath(); ctx.arc(0, 0.27 * r, 0.21 * r, 0, Math.PI * 2); ctx.stroke();
    ctx.beginPath(); ctx.arc(0, 0.27 * r, 0.06 * r, 0, Math.PI * 2); ctx.fill();
  } else if (id === 'anchor') {               // anchor: ring, shank, stock, arms with flukes
    ring();
    ctx.lineWidth = 0.0085 * R;
    ctx.beginPath(); ctx.arc(0, -0.5 * r, 0.1 * r, 0, Math.PI * 2); ctx.stroke();
    line([[0, -0.4], [0, 0.52]]); line([[-0.24, -0.22], [0.24, -0.22]]);
    ctx.beginPath(); ctx.arc(0, 0.06 * r, 0.46 * r, 0.22 * Math.PI, 0.78 * Math.PI); ctx.stroke();
    line([[0.36, 0.2], [0.42, 0.42], [0.2, 0.36]]); line([[-0.36, 0.2], [-0.42, 0.42], [-0.2, 0.36]]);
  } else if (id === 'park') {
    ring();
    const fs = 0.088 * R;
    ctx.font = `700 ${fs}px ${FONT}`;
    ctx.fillText('P', 0.003 * R, (CAP * fs) / 2);
  } else {
    const h = 0.112 * R, w = 0.13 * R;
    ctx.beginPath(); ctx.moveTo(0, -h * 0.6); ctx.lineTo(w / 2, h * 0.4); ctx.lineTo(-w / 2, h * 0.4); ctx.closePath(); ctx.stroke();
    ctx.lineWidth = 0.012 * R;
    ctx.beginPath(); ctx.moveTo(0, -h * 0.24); ctx.lineTo(0, h * 0.08); ctx.stroke();
    ctx.beginPath(); ctx.arc(0, h * 0.24, 0.0065 * R, 0, Math.PI * 2); ctx.fill();
  }
  ctx.restore();
}
