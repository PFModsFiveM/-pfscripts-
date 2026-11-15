// Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
// Free software under the GNU Lesser General Public License 3.0 (pf-hud/COPYING.LESSER and COPYING).
// The vehicle HUD (3D dial), for embedding: createVehicleHud(canvas) returns an API the host page calls directly.
// No listeners, no fade, no globals: the host owns visibility, fading and when to call resize(). (pf-hud's js/vehicle-dial.js
// bridges its NUI messages to it.)
//
//   const hud = createVehicleHud(canvas)        canvas: position: fixed, at body level; the dial places itself
//   hud.show() / hud.hide()                       start / stop rendering (hide stops at once; fade first if wanted)
//   hud.setState({ ...partial state })            see README: rpm, maxRpm, redline, speed, units, gear, handbrake,
//                                                 engine, lights, locked, damage; aircraft: kind 'air', pitch, roll,
//                                                 altitude, gearState; boats: kind 'boat', power, anchored,
//                                                 gear 'F' / 'N' / 'R'
//   hud.setGauge({ id, icon, value, text?, danger?, dangerLow?, order? }) / hud.removeGauge(id)
//   hud.setConfig({ scale?, right?, bottom?, attitude?, skins? })   size (1 = reference), dial centre from the corner
//                                                 in dial radii, the aircraft attitude indicator: 'ball' (3D) or 'flat',
//                                                 and skins: false for the dial as designed on every car
//   UPSTREAM EDIT:setState({ skin }) — a dial-art id from skins3d.js (the car's own GTA dashboard look),
//                                                 or false / null for the dial as designed
//   hud.resize()                                  after the window changes size
//   hud.dispose()                                 frees the WebGL context and GPU memory
//
// Updates at 10-30 Hz are plenty: rpm and speed are smoothed here, and the dial's lean (acceleration), shift kick
// (gear changes) and limiter judder (rpm held at the top of the range) are worked out here too. In aircraft mode pitch,
// roll and altitude are smoothed the same way (roll the short way round through +-180); on a boat the power.
import { Hud3D } from './hud3d.js';
import { GaugeLayout } from './gauges.js';
import { BOX, MIN_RANGE, MAX_RANGE, FONT_FAMILY, defaultRedline, limiterDip } from './dial.js';
import { angleDiff } from './air.js';
// PF: the dial skins (sampled from GTA's dashboard art) are not shipped here: pfm-media-map's html/dash_skins3d.js
// sets window.PfDashSkins and js/vehicle-dial.js hands it over with setSkinData. Without it every car keeps the
// dial as designed.
let SKINS = {}, SKIN_ALIAS = {};

// the bundled Roboto subset, registered once under its own family name
const FONT_FILES = [['normal', './fonts/roboto-hud.woff2'], ['italic', './fonts/roboto-hud-italic.woff2']];
let fontsReady = null;
function loadFonts() {
  if (!fontsReady) {
    fontsReady = Promise.all(FONT_FILES.map(([style, file]) => {
      const face = new FontFace(FONT_FAMILY, `url(${new URL(file, import.meta.url)})`, { style, weight: '500 900' });
      document.fonts.add(face);
      return face.load();
    })).catch(() => {});                                  // without them the dial falls back to Roboto / Arial
  }
  return fontsReady;
}

// UPSTREAM EDIT:the skins' fonts (skins3d.js SKIN_FONTS), open-licence Google Fonts cut to the characters
// the dial draws (0-9, A-Z, a-z, . , % ° : + - / and space). Each is registered under its exact family name and
// loaded at once, so hud3d.js setSkin's font load finds it and a car's first skin is not drawn in Roboto first. An
// "italic 700" a skin's extra gauges ask for and a family has no face for is synthesised by the browser, as is
// Michroma's 700. Times New Roman is the system's; Peyote's skin is the dial's own Roboto.
const SKIN_FONT_FILES = [
  ['Archivo Narrow', 'normal', 400, 'skin-archivo-narrow-400'],
  ['Arimo', 'normal', 500, 'skin-arimo-500'], ['Arimo', 'normal', 700, 'skin-arimo-700'], ['Arimo', 'italic', 700, 'skin-arimo-700i'],
  ['Barlow', 'normal', 400, 'skin-barlow-400'], ['Barlow', 'normal', 500, 'skin-barlow-500'],
  ['Barlow Condensed', 'normal', 500, 'skin-barlow-condensed-500'],
  ['Michroma', 'normal', 400, 'skin-michroma-400'],
  ['Orbitron', 'normal', 700, 'skin-orbitron-700'],
  ['Rajdhani', 'normal', 700, 'skin-rajdhani-700'],
  ['Russo One', 'normal', 400, 'skin-russo-one-400'],
  ['Saira', 'normal', 500, 'skin-saira-500'], ['Saira', 'normal', 600, 'skin-saira-600'], ['Saira', 'normal', 700, 'skin-saira-700'],
  ['Saira', 'italic', 500, 'skin-saira-500i'],
  ['Saira Condensed', 'normal', 600, 'skin-saira-condensed-600'], ['Saira Condensed', 'normal', 700, 'skin-saira-condensed-700'],
  ['Saira Semi Condensed', 'normal', 400, 'skin-saira-semi-condensed-400'], ['Saira Semi Condensed', 'normal', 500, 'skin-saira-semi-condensed-500'],
];
let skinFontsAdded = false;
function loadSkinFonts() {
  if (skinFontsAdded) return;
  skinFontsAdded = true;
  for (const [family, style, weight, file] of SKIN_FONT_FILES) {
    const face = new FontFace(family, `url(${new URL(`./fonts/${file}.woff2`, import.meta.url)})`, { style, weight: String(weight) });
    document.fonts.add(face);
    face.load().catch(() => {});                          // a face that fails: that skin's text falls back to Roboto
  }
}

/** A skin id (skins3d.js SKIN_OF's, or a merged one SKIN_ALIAS names) to its skin, or null: the dial as designed. */
const skinOf = (id) => (typeof id === 'string' && id !== '' ? SKINS[SKIN_ALIAS[id] || id] || null : null);

const approach = (v, to, rate, dt) => v + (to - v) * (1 - Math.exp(-rate * dt));
const gearRank = (g) => (g === 'R' ? -1 : g === 'N' ? 0 : Number(g));

export function createVehicleHud(canvas) {
  const hud = new Hud3D(canvas);
  const layout = new GaugeLayout();
  const state = {
    rpm: 0, maxRpm: 7.5, redline: 6.5, speed: 0, units: 'kmh', gear: 'N', parked: true, handbrake: 0,
    engine: false,                                          // UPSTREAM EDIT:the engine light (was the P)
    lights: 'off', locked: false, damage: false,
    kind: 'car', pitch: 0, roll: 0, altitude: 0, gearState: 'none',          // aircraft mode (kind 'air')
    power: 0, anchored: false,                                                // boat mode (kind 'boat')
    limiter: false, accel: 0, shiftKick: 0, gauges: [], gaugeView: [], t: 0,
    launch: false,                                          // UPSTREAM EDIT:first gear + handbrake (the bounce)
  };
  const target = { rpm: 0, speed: 0, pitch: 0, roll: 0, altitude: 0, power: null };
  let snapAir = true;                                         // on entering an aircraft: start at its attitude
  const cfg = { scale: 1, right: 1.671, bottom: 1.35, skins: true };   // the reference's placement, a little lower
  // UPSTREAM EDIT:the skin asked for (state.skin's id) and the one on the dial (a skins3d.js entry, or null)
  let skinId = null, skinOn = null;
  function applySkin() {
    const k = cfg.skins === false ? null : skinOf(skinId);
    if (k === skinOn) return;
    skinOn = k;
    hud.setSkin(k);
  }
  let running = false, disposed = false, raf = 0, lastFrame = 0, prevSpeed = 0, limiterFor = 0, seq = 0;
  let smoothRpm = 0, dip = 0;                                 // rpm eased toward the updates; dip: the limiter bounce below it
  let bounceFor = 0;                                          // UPSTREAM EDIT:how long the bounce has run
  // UPSTREAM EDIT:how long the revs have been under the limiter zone, and how long that may last before the
  // limiter lets go. GTA's rpm wobbles round the top (or the bounce would not play easing into a donut).
  let limiterOff = 0;
  const LIMITER_RELEASE = 0.25;
  // UPSTREAM EDIT:the bounce follows the NEEDLE, not the flash: it starts the moment the needle reaches the top and
  // stops the moment the revs fall away. Tied to state.limiter it waited out the flash's 0.15 s hold (the needle
  // paused at the top) and its 0.25 s release (it bounced on the way down). In: the revs and the needle at the limiter
  // (atLimit). Out: the revs under BOUNCE_OUT of the top, low enough that GTA's wobble round 99% stays in.
  let atTop = false;
  const BOUNCE_OUT = 0.95;

  // bottom-right, sized like the reference: dial radius 12.57% of the window height (at most 20% of its width)
  function place() {
    const W = innerWidth, H = innerHeight;
    const R = Math.max(30, Math.floor(Math.min(0.1257 * H, 0.2 * W) * cfg.scale));
    hud.resize(R);
    canvas.style.left = W - cfg.right * R - BOX.cx * R + 'px';
    canvas.style.top = H - cfg.bottom * R - BOX.cy * R + 'px';
  }

  function frame(now) {
    if (!running) return;
    const dt = Math.min(0.05, (now - (lastFrame || now)) / 1000); lastFrame = now;
    state.t += dt;
    smoothRpm = approach(smoothRpm, Math.min(target.rpm, state.maxRpm), 18, dt);
    state.speed = approach(state.speed, target.speed, 12, dt);
    if (dt > 0) state.accel = approach(state.accel, (state.speed - prevSpeed) / dt, 6, dt);
    prevSpeed = state.speed;
    state.shiftKick = approach(state.shiftKick, 0, 5, dt);
    if (state.kind === 'air') {
      if (snapAir) { state.pitch = target.pitch; state.roll = target.roll; state.altitude = target.altitude; snapAir = false; }
      state.pitch = approach(state.pitch, target.pitch, 14, dt);
      state.roll += angleDiff(target.roll, state.roll) * (1 - Math.exp(-14 * dt));
      state.roll = ((((state.roll + 180) % 360) + 360) % 360) - 180;
      state.altitude = approach(state.altitude, target.altitude, 10, dt);
    }
    if (state.kind === 'boat') {
      // power: as sent, else from the revs (the feeder's mapping puts idle at 11.3% and the limiter at the top of the range)
      const p = target.power != null ? target.power : (target.rpm / state.maxRpm - 0.113) / (1 - 0.113);
      state.power = approach(state.power, Math.max(0, Math.min(1, p)), 18, dt);
    }
    // the limiter: the revs at the top of the range (the feeder sends the limiter as maxRpm), with the needle already
    // there, for 0.15 s
    const atLimit = state.kind === 'car' && target.rpm >= state.maxRpm * 0.99 && smoothRpm >= state.maxRpm * 0.99;
    // UPSTREAM EDIT:a dip under the zone shorter than LIMITER_RELEASE neither restarts the 0.15 s hold nor
    // lets the limiter go (it was `limiterFor = atLimit ? limiterFor + dt : 0`, reset by any single low reading)
    if (atLimit) { limiterFor += dt; limiterOff = 0; }
    else if ((limiterOff += dt) >= LIMITER_RELEASE) limiterFor = 0;
    state.limiter = limiterFor > 0.15;
    // on it the needle bounces below where it sits (1,000 rpm down and back, 50 ms each way); the dip eases out after
    // UPSTREAM EDIT: the bounce ONLY ON A LAUNCH, first gear with the handbrake held (state.launch, from
    // the feeder, client/dial.lua). Any other time on the limiter the needle shows the revs as they are; the flash and the judder
    // (state.limiter) are unchanged. Timed from when both hold, so the bounce always starts at a dip of 0.
    // UPSTREAM EDIT:while the NEEDLE is at the top (atTop, above), not while the outline flashes.
    if (atLimit) atTop = true;
    else if (state.kind !== 'car' || target.rpm < state.maxRpm * BOUNCE_OUT) atTop = false;
    bounceFor = atTop && state.launch ? bounceFor + dt : 0;
    dip = bounceFor > 0 ? limiterDip(Math.max(0, bounceFor - dt)) : approach(dip, 0, 30, dt);
    state.rpm = Math.max(0, smoothRpm - dip);
    state.gaugeView = layout.update(state.gauges, dt, state.kind);
    hud.render(state, dt);
    raf = requestAnimationFrame(frame);
  }

  const api = {
    show() {
      if (disposed || running) return;
      running = true; lastFrame = 0; hud.force = true;
      raf = requestAnimationFrame(frame);
    },
    hide() { running = false; cancelAnimationFrame(raf); },

    setState(p) {
      if (!p || typeof p !== 'object') return;
      if ('maxRpm' in p) {
        state.maxRpm = Math.max(MIN_RANGE, Math.min(MAX_RANGE, Number(p.maxRpm) || 7.5));
        state.redline = p.redline != null ? Number(p.redline) : +defaultRedline(state.maxRpm).toFixed(2);
      } else if (p.redline != null) state.redline = Number(p.redline);
      if ('rpm' in p) target.rpm = Math.max(0, Number(p.rpm) || 0);
      if ('speed' in p) target.speed = Math.max(0, Number(p.speed) || 0);
      if ('gear' in p) {
        const g = typeof p.gear === 'number' ? String(p.gear) : String(p.gear || 'N');
        const was = gearRank(state.gear), now = gearRank(g);
        if (was > 0 && now > 0 && now !== was) state.shiftKick = now > was ? 1 : -0.6;
        state.gear = g; state.parked = g === 'N';
      }
      for (const k of ['units', 'handbrake', 'engine', 'lights', 'locked', 'damage', 'gearState', 'anchored']) if (k in p) state[k] = p[k];
      if ('launch' in p) state.launch = p.launch === true;   // UPSTREAM EDIT:the bounce's gate
      if ('skin' in p) { skinId = typeof p.skin === 'string' ? p.skin : null; applySkin(); }   // UPSTREAM EDIT
      if ('kind' in p) {
        const k = p.kind === 'air' || p.kind === 'boat' ? p.kind : 'car';
        if (k !== state.kind) { state.kind = k; snapAir = true; }
      }
      for (const k of ['pitch', 'roll', 'altitude']) if (k in p) target[k] = Number(p[k]) || 0;
      if ('power' in p) target.power = p.power == null ? null : Math.max(0, Math.min(1, Number(p.power) || 0));
    },

    // icon: one of the built-in names (turbo, nitro, fuel, fuel_left, fuel_right, coolant, hack, weapon) or an SVG path in a 24x24 viewBox
    setGauge(g) {
      if (!g || g.id == null) return;
      let cur = state.gauges.find((x) => x.id === g.id);
      if (!cur) { cur = { on: true, value: 0, text: '', danger: null, dangerLow: null, order: 100, seq: seq++ }; state.gauges.push(cur); }
      Object.assign(cur, g, { on: true });
      state.gauges.sort((a, b) => (a.order ?? 100) - (b.order ?? 100) || a.seq - b.seq);   // slot order; five shown
    },
    removeGauge(id) { state.gauges = state.gauges.filter((x) => x.id !== id); },   // fades out of its slot

    // UPSTREAM EDIT:`skins` (false: every car on the dial as designed) applied here too
    setConfig(c) { Object.assign(cfg, c || {}); if (cfg.attitude) hud.setAttitude(cfg.attitude); applySkin(); place(); },
    resize: place,

    // PF: the skins' data ({ SKINS, SKIN_ALIAS }), from pfm-media-map; anything else leaves every car on the default dial
    setSkinData(d) {
      SKINS = d && typeof d.SKINS === 'object' && d.SKINS ? d.SKINS : {};
      SKIN_ALIAS = d && typeof d.SKIN_ALIAS === 'object' && d.SKIN_ALIAS ? d.SKIN_ALIAS : {};
      skinOn = undefined; applySkin();
    },

    dispose() {
      api.hide(); disposed = true;
      hud.dispose(); hud.renderer.forceContextLoss();
    },
  };

  place();
  loadFonts().then(() => { if (!disposed) hud.refreshText(); });
  loadSkinFonts();                                            // UPSTREAM EDIT:before any car's skin asks
  return api;
}
