# pf-scoreboard: licence notice for the ported styles

Part of pf-scoreboard's look is ported from the styles of WHIP's `whip_core` resource, by Whippy:

    Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.

Those files are free software under the GNU Lesser General Public License 3.0 (`COPYING.LESSER`),
which builds on the GNU General Public License 3.0 (`COPYING`). Each keeps the notice above in its
header. The shared values they read (colours, radii, fonts, motion) are pfm-ui's `html/tokens.css`
(a PF resource, itself a port of WHIP's `base.css`).

| pf-scoreboard file | follows (whip_core) | changes for PF |
|---|---|---|
| html/scoreboard.css | ui.css OBJECTIVES (the objective card) | PF's ids |

Everything else in pf-scoreboard keeps its own licence. pf-scoreboard is not WHIP, is not made by WHIP's author
and does not use WHIP's name. The fonts the page shows (Barlow, Bricolage Grotesque) are bundled by
pfm-ui under the SIL Open Font License 1.1.
