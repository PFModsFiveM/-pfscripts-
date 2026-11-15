// Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
// Free software under the GNU Lesser General Public License 3.0 (pf-hud/COPYING.LESSER and COPYING).
// Aircraft mode (state.kind === 'air'): the dial keeps its ring, bottom tab, lower meter, status lights and extra
// gauges, but its inside becomes an attitude indicator and two tapes flank it, as on an aircraft's primary flight
// display: airspeed on the left (mph), altitude on the right (feet). Both HUDs draw from the numbers here.
// Units: dial radii (R), y up, angles in degrees. State: pitch (nose up +), roll (right wing down +), altitude (metres
// above sea level), speed (km/h, as for cars).

// attitude indicator: a sky/ground disc filling the ring, horizon moved by pitch and turned by roll
export const ADI = {
  r: 0.928,                       // the ring's inner edge
  k: 0.03,                        // dial radii per degree of pitch: the ladder window shows about +-20 deg
  fade0: 0.5, fade1: 0.64,        // the ladder fades out between these radii (real ADIs clip it to the middle)
  rung: 2.5,                      // a rung every 2.5 deg: short; every 5: medium; every 10: long and numbered
  half: [0.06, 0.12, 0.24],       // half-lengths of short / medium / long rungs
  line: 0.007,                    // rung and horizon width
  label: 0.062,                   // pitch numbers' cap height
  rim: [0.8, 0.928],              // a soft shade toward the ring, so the disc sits inside it
};
export const SKY_HI = [0.09, 0.3, 0.62], SKY_LO = [0.27, 0.57, 0.9];       // linear-ish 0-1 RGB, deep / at the horizon
export const GND_HI = [0.56, 0.36, 0.17], GND_LO = [0.29, 0.18, 0.08];     // at the horizon / deep

// bank scale: fixed ticks on the upper arc; a fixed index at the top, and a pointer that turns with the sky
export const BANK = {
  r: 0.86,                        // outer end of every tick
  ticks: [[10, 0], [20, 0], [30, 1], [45, 0], [60, 1]],   // [deg, long], both sides
  long: 0.075, short: 0.045, w: 0.012,
  index: { apex: 0.795, base: 0.865, half: 0.04 },        // fixed, points down at the scale's zero
  pointer: { apex: 0.785, base: 0.72, half: 0.036 },      // turns with the horizon, points up
};

// 3D dial only: the attitude as a ball, like a gyro horizon's. The sky/ground sphere turns behind the window, its
// front standing out of the dial face; the bank scale and aircraft symbol stay fixed in front of it. The ball turns
// faster than the aircraft near level (gain), so the ladder reads about as large as on the flat display, but pitch 90
// still brings the pole to the front.
export const BALL = { r: 1.01, front: 0.22, gain: 1.7, fade: [0.55, 0.8] };   // fade: ladder by how squarely the ball faces you
export const ballLatitude = (pitch) => Math.atan(BALL.gain * Math.tan((Math.max(-89.99, Math.min(89.99, pitch)) * Math.PI) / 180));

// aircraft symbol (fixed): two L-shaped wing bars and a centre square, yellow with a black outline
export const SYMBOL = {
  boxes: [[-0.29, 0, 0.13, 0.016], [-0.176, -0.036, 0.016, 0.052], [0.29, 0, 0.13, 0.016], [0.176, -0.036, 0.016, 0.052], [0, 0, 0.022, 0.022]],
  outline: 0.008, fill: [1, 0.82, 0.12],
};

// tapes: black strips either side of the ring; values scroll past a fixed readout box at mid-height
export const TAPE = {
  x: 1.24, hw: 0.18, hh: 0.7,     // centre (left tape at -x), half-width, half-height
  fade: 0.12,                     // ticks and numbers fade over this much at either end
  bg: 0.55,                       // background opacity
  tick: [0.04, 0.07], tickW: 0.008,
  label: 0.07,                    // tape numbers' cap height
  caption: 0.055, captionY: -0.8, // "MPH" / "FT" under each tape
  box: { hw: 0.2, hh: 0.1, notch: 0.05, notchH: 0.05, border: 0.007, tall: 0.17 },
};
// drum spacing: the rolling windows show a little of the digits either side; a fixed column's next digit sits a whole
// box height away, so it only comes into view while the column rolls over
export const ROLL_PITCH = 1.3, STATIC_PITCH = () => 2 * TAPE.box.hh;
export const SPEED_TAPE = { perR: 50, label: 10, minor: 5, min: 0, cap: 0.11, digits: 3, caption: 'MPH' };
export const ALT_TAPE = { perR: 500, label: 100, minor: 20, min: 0, cap: 0.095, small: 0.072, caption: 'FT' };

// gauge orbit in aircraft mode: a fan over the top, clear of the tapes
export const AIR_ORBIT = { orbit: 1.58, step: 25, centre: 0 };

// Roboto digit advance (em) and cap height (em): glyph pitch along a row
export const ADV = 0.562, CAP = 0.711;
export const advance = (cap) => (ADV / CAP) * cap;

export const airspeed = (s) => Math.max(0, (s.speed || 0) * 0.621371);           // km/h -> mph
export const altitudeFt = (s) => Math.max(0, (s.altitude || 0) * 3.28084);       // metres -> feet (sea level and up)

// Rolling readouts. A column's value c is continuous: its digit is c mod 10, and between two whole values the drum
// shows both, part-way through the roll. The lowest column turns with the value itself; each higher one only turns
// while the one below rolls over (9 -> 0), as on an odometer.
export function speedColumns(v) {
  const cols = [v];
  for (let j = 1, p = 10; j < SPEED_TAPE.digits; j++, p *= 10) cols.push(Math.floor(v / p) + Math.min(1, Math.max(0, (v % p) - (p - 1))));
  return cols;                                       // [ones, tens, hundreds]
}
// altitude: the last two digits are one drum in 20 ft steps (00 20 40 60 80); hundreds and up roll over during the
// last 20 ft before each change
export function altColumns(v) {
  const small = v / 20, big = [];
  for (const p of [100, 1000, 10000]) big.push(Math.floor(v / p) + Math.min(1, Math.max(0, ((v % p) - (p - 20)) / 20)));
  return { small, big };                             // big: [hundreds, thousands, ten-thousands]
}

// shortest signed difference between two angles (deg)
export const angleDiff = (a, b) => ((((a - b) % 360) + 540) % 360) - 180;
