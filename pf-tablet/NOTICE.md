# pf-tablet: licence notice for the ported styles

Part of pf-tablet's look is ported from the styles of WHIP's `whip_core` resource, by Whippy:

    Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.

Those files are free software under the GNU Lesser General Public License 3.0 (`COPYING.LESSER`),
which builds on the GNU General Public License 3.0 (`COPYING`). Each keeps the notice above in its
header. The shared values they read (colours, radii, fonts, motion) are pfm-ui's `html/tokens.css`
(a PF resource, itself a port of WHIP's `base.css`).

| pf-tablet file | follows (whip_core) | changes for PF |
|---|---|---|
| html/style.css (the "PF look" layer at its end) | base.css values; the house panels of inventory.css; ui.css OBJECTIVES (the scoreboard card) | applied over PF's own tablet shell; the rest of style.css is PF's own |
| html/scoreboard.css | ui.css OBJECTIVES (the objective card) | PF's ids |

Everything else in pf-tablet keeps its own licence. pf-tablet is not WHIP, is not made by WHIP's author
and does not use WHIP's name. The fonts the page shows (Barlow, Bricolage Grotesque) are bundled by
pfm-ui under the SIL Open Font License 1.1.
