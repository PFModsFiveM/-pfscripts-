// Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
// Free software under the GNU Lesser General Public License 3.0 (pf-hud/COPYING.LESSER and COPYING).
// Boat mode (state.kind === 'boat'): the dial keeps its look, but its scale reads engine power instead of revs:
// 0% at idle to 100% at full revs, which land exactly at the end of the scale, with no red zone (full power is where
// a boat runs, not a danger). The shift reads F / N / R and the lock light shows the anchor. State: power (0 idle ..
// 1 full; derived from rpm when not sent), anchored (bool), gear 'F' / 'N' / 'R'.

// the power scale, in the shape revScale() gives the dial: numerals every 20%, ticks every 2%, no red zone
export const POWER_SCALE = Object.freeze({
  max: 100, redline: 101, step: 20, minor: 2, mid: 10, ticks: 51, power: true,
  labels: [0, 20, 40, 60, 80, 100].map((v) => ({ v, text: String(v) })),
});
