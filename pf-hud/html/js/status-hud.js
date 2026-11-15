/* Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
 * Port of whip_core/html/js/status-hud.js and capsule.js (the gauges and the capsule's stats/notify modes), as a classic
 * script on PfHud's router. Free software under the GNU Lesser General Public License 3.0 (pf-hud/COPYING.LESSER and
 * COPYING).
 *
 * PF changes: no chat composer (the capsule's notify mode carries the HUD's money changes); `flag` gauges (the seatbelt
 * and cruise control: shown in a vehicle, red when unbuckled, the accent while cruise holds the speed); `criticalAbove`
 * (stress: high is the warning); `idleAbove` (the idle fade and the minimal style); the row can be placed in the corner
 * or anywhere (the layout editor) instead of under the map's frame. */
(function (root) {
    "use strict";
    const doc = root.document;
    const PfHud = root.PfHud;

    const statusHud = doc.getElementById("status-hud");
    const statusHudStats = doc.getElementById("statusHudStats");
    const statusHudWrapper = doc.getElementById("statusHudWrapper");
    const container = doc.getElementById("statusHudContainer");
    const capsuleBubble = doc.getElementById("capsuleBubble");
    const capsuleIcon = capsuleBubble ? capsuleBubble.querySelector(".sh-icon") : null;
    const capsuleText = doc.getElementById("capsuleNotifyText");

    // Arc geometry: 270° arc on an r=18 circle
    const SH_ARC = 84.82;
    const SH_CIRC = 113.1;

    const _hudRegistry = {};

    // ---- colours ----

    const DEFAULT_STAT_COLOR = "#ffffff";
    function statColor(hex) {
        return (typeof hex === "string" && /^#?[0-9a-fA-F]{6}$/.test(hex))
            ? (hex.charAt(0) === "#" ? hex : "#" + hex)
            : DEFAULT_STAT_COLOR;
    }
    function hexToRgb(hex) {
        hex = statColor(hex).replace("#", "");
        return { r: parseInt(hex.substring(0, 2), 16), g: parseInt(hex.substring(2, 4), 16), b: parseInt(hex.substring(4, 6), 16) };
    }
    function applyStatColor(el, hex) {
        hex = statColor(hex);
        const c = hexToRgb(hex);
        el.style.setProperty("--stat-color", hex);
        el.style.setProperty("--stat-glow", `rgba(${c.r}, ${c.g}, ${c.b}, 0.45)`);
        el.style.setProperty("--stat-haze", `rgba(${c.r}, ${c.g}, ${c.b}, 0.15)`);
    }

    // An icon is an SVG path (letters, digits and path punctuation only): anything else is not drawn.
    const PATH_OK = /^[\sMmZzLlHhVvCcSsQqTtAa0-9eE+\-.,|]*$/;
    const safePath = (p) => (typeof p === "string" && PATH_OK.test(p) ? p : "");

    function buildCriticalIconSvg(pathData) {
        const paths = safePath(pathData).split("|");
        let svg = '<svg viewBox="0 0 24 24">';
        svg += `<path fill="currentColor" d="${paths[0]}"/>`;
        const widths = [1.1, 0.8, 0.8, 0.8, 0.7, 0.7, 0.6];
        const opacities = [0.65, 0.55, 0.55, 0.55, 0.5, 0.5, 0.45];
        for (let i = 1; i < paths.length; i++) {
            const w = widths[Math.min(i - 1, widths.length - 1)];
            const o = opacities[Math.min(i - 1, opacities.length - 1)];
            svg += `<path fill="none" stroke="rgba(0,0,0,${o})" stroke-width="${w}" stroke-linecap="round" d="${paths[i]}"/>`;
        }
        return svg + "</svg>";
    }

    // ---- building a gauge ----

    function buildStatElement(el, config) {
        if (config.hideWhenEmpty) el.classList.add("hide-when-empty");
        if (config.showAboveZero) el.classList.add("show-above-zero");
        if (config.showBelowFull) el.classList.add("show-below-full");
        if (config.glide) el.classList.add("glide");
        if (config.showWhenPresent) el.classList.add("show-when-present");
        if (config.iconCritical) el.classList.add("has-critical-icon");
        if (config.type === "flag") el.classList.add("flag");
        const icon = safePath(config.icon);
        el.innerHTML = `
            <svg class="sh-ring" viewBox="0 0 48 48">
                <circle class="sh-track" cx="24" cy="24" r="18"/>
                <circle class="sh-arc" cx="24" cy="24" r="18"/>
            </svg>
            <div class="sh-disc"><div class="sh-fill"></div></div>
            <div class="sh-icon sh-icon-normal">
                <svg viewBox="0 0 24 24"><path fill="currentColor" d="${icon}"/></svg>
            </div>
            ${config.iconCritical ? `<div class="sh-icon sh-icon-critical">${buildCriticalIconSvg(config.iconCritical)}</div>` : ""}
            ${config.iconRadio ? `<div class="sh-icon sh-icon-radio"><svg viewBox="0 0 24 24"><path fill="currentColor" d="${safePath(config.iconRadio)}"/></svg></div>` : ""}
        `;
    }

    function registerHudStats(stats) {
        if (!statusHudStats || !Array.isArray(stats)) return;
        statusHudStats.innerHTML = "";
        for (const key in _hudRegistry) delete _hudRegistry[key];
        stats.forEach((config, index) => {
            if (!config || typeof config.name !== "string") return;
            const el = doc.createElement("div");
            el.className = "sh-stat";
            el.dataset.stat = config.name;
            el.style.animationDelay = (0.08 + index * 0.06) + "s";
            buildStatElement(el, config);
            applyStatColor(el, config.color);
            statusHudStats.appendChild(el);
            _hudRegistry[config.name] = { el, arc: el.querySelector(".sh-arc"), fill: el.querySelector(".sh-fill"), config };
        });
        applyVoiceTalking();
        _lastLayout = null;
        layoutUnderFrame();
    }

    // ---- the voice gauge, lit while talking (orange, a radio, on the radio) ----

    let _voiceTalking = false;
    let _voiceMode = null;
    function applyVoiceTalking() {
        const reg = _hudRegistry.voice;
        if (!reg) return;
        reg.el.classList.toggle("talking", _voiceTalking);
        reg.el.classList.toggle("radio", _voiceTalking && _voiceMode === "radio");
    }
    function setVoiceTalking(on, mode) {
        _voiceTalking = !!on;
        _voiceMode = mode === "radio" ? "radio" : null;
        applyVoiceTalking();
    }

    // ---- one gauge's level ----

    function updateStat(name, percent) {
        const reg = _hudRegistry[name];
        if (!reg) return;
        percent = Math.max(0, Math.min(100, percent));
        const el = reg.el;
        const config = reg.config;

        reg.arc.style.strokeDasharray = (SH_ARC * (percent / 100)) + " " + SH_CIRC;

        if (config.glide && percent !== reg.glideAt) {
            const now = root.performance ? root.performance.now() : Date.now();
            if (reg.glideAt !== undefined) {
                const since = now - reg.glideTime;
                const gap = since > 0 && since < 2500 ? since : (reg.glideGap || 1000);
                reg.glideGap = reg.glideGap ? reg.glideGap * 0.6 + gap * 0.4 : gap;
                el.style.setProperty("--sh-glide", Math.round(Math.max(150, Math.min(2000, reg.glideGap))) + "ms");
            }
            reg.glideAt = percent;
            reg.glideTime = now;
        }
        if (reg.fill) reg.fill.style.height = percent + "%";
        el.style.setProperty("--sh-p", percent);
        el.classList.toggle("empty", percent <= 0);

        if (config.showAboveZero) el.classList.toggle("visible", percent > 0);
        if (config.showBelowFull) el.classList.toggle("visible", percent < 100);

        let critical;
        if (typeof config.criticalAbove === "number") critical = percent >= config.criticalAbove;
        else critical = !config.noCritical && percent > 0 && percent < 20;
        el.classList.toggle("critical", critical);
        if (config.heartbeat) el.classList.toggle("heartbeat", critical);

        el.classList.toggle("idle", typeof config.idleAbove === "number" && percent >= config.idleAbove);
    }

    /** A flag gauge (the seatbelt, cruise): shown while `present`, full; red when off (warnWhenOff), the accent when on
     *  (accentWhenOn), or only while on (onlyWhenOn). */
    function updateFlag(name, present, on) {
        const reg = _hudRegistry[name];
        if (!reg) return;
        const c = reg.config, el = reg.el;
        const show = !!present && (!c.onlyWhenOn || !!on);
        el.classList.toggle("visible", show);
        updateStat(name, 100);
        el.classList.toggle("flag-warn", show && !!c.warnWhenOff && !on);
        el.classList.toggle("flag-accent", show && !!c.accentWhenOn && !!on);
    }

    // ---- the stat-change interrupt (a big move brings a gauge back while the capsule holds a notification) ----

    const _lastShown = {};
    const INTERRUPT_MS = 2500;
    const _interruptTimers = {};

    function interrupt(name) {
        const reg = _hudRegistry[name];
        if (!reg) return;
        reg.el.classList.add("interrupting");
        if (_interruptTimers[name]) clearTimeout(_interruptTimers[name]);
        _interruptTimers[name] = setTimeout(() => {
            reg.el.classList.remove("interrupting");
            _interruptTimers[name] = null;
        }, INTERRUPT_MS);
    }

    function percentOf(config, value) {
        const max = typeof config.max === "number" && config.max > 0 ? config.max : 100;
        if (config.type === "vital" && max === 200) return Math.max(0, Math.min(100, value - 100));
        return Math.max(0, Math.min(100, (value / max) * 100));
    }

    const last = {};

    function updateStatusHud(data) {
        if (!statusHud || !data) return;
        if (typeof data.inVehicle === "boolean") last.inVehicle = data.inVehicle;
        if (typeof data.seatbelt === "boolean") last.seatbelt = data.seatbelt;
        if (typeof data.cruise === "boolean") last.cruise = data.cruise;
        if (typeof data.beltable === "boolean") last.beltable = data.beltable;
        const showing = _mode === "stats";
        for (const name in _hudRegistry) {
            const config = _hudRegistry[name].config;
            if (config.type === "flag") {
                // presentKey: a second condition (the seatbelt only in a vehicle that has belts)
                const present = last.inVehicle && (!config.presentKey || last[config.presentKey] !== false);
                updateFlag(name, present, last[name]);
                continue;
            }
            const value = data[name];
            if (typeof value !== "number") continue;
            const percent = percentOf(config, value);
            updateStat(name, percent);
            if (showing) {
                _lastShown[name] = percent;
            } else if (config.interruptDelta > 0) {
                const seen = _lastShown[name];
                if (seen !== undefined && Math.abs(percent - seen) >= config.interruptDelta) {
                    interrupt(name);
                    _lastShown[name] = percent;
                }
            }
        }
    }

    // ---- show / hide, skin ----

    function showStatusHud() { if (statusHud) statusHud.classList.add("visible"); }
    function hideStatusHud() { if (statusHud) statusHud.classList.remove("visible"); }

    function setHudSkin(skin) {
        if (!statusHud) return;
        statusHud.classList.toggle("skin-black", skin !== "classic");
        statusHud.classList.toggle("minimal", skin === "minimal");
        _lastLayout = null;
        layoutUnderFrame();
    }

    // ---- the capsule: stats, or a notification ----

    let _mode = "stats";
    const queue = [];
    let notifyTimer = null;

    function setCapsuleMode(mode) {
        if (!container) return;
        if (mode !== "notify") mode = "stats";
        if (mode === _mode) return;
        const snap = !!statusHud && root.getComputedStyle && parseFloat(root.getComputedStyle(statusHud).opacity) < 0.02;
        if (snap) container.classList.add("cap-snap");
        if (_mode === "stats" && mode !== "stats") container.style.minWidth = container.offsetWidth + "px";
        else if (mode === "stats") container.style.minWidth = "";
        container.classList.remove("mode-stats", "mode-notify");
        container.classList.add("mode-" + mode);
        _mode = mode;
        if (snap) { void container.offsetWidth; container.classList.remove("cap-snap"); }
        if (mode === "stats") nextNotification();
    }

    const NOTIFY_COLORS = { success: "var(--ui-success)", error: "var(--ui-error)", info: "var(--ui-info)", warning: "var(--ui-warning)" };
    const NOTIFY_GLYPHS = {
        success: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5.6 12.6l4.3 4.2 8.5-9.3"/></svg>',
        error: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 6.5l11 11"/><path d="M17.5 6.5l-11 11"/></svg>',
        info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="6.9" r="1.75" fill="currentColor" stroke="none"/><path d="M12 11.2v6.9"/></svg>',
        warning: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5.9v6.9"/><circle cx="12" cy="17.1" r="1.75" fill="currentColor" stroke="none"/></svg>',
        // PF: a banknote and a bank, for the money changes
        cash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linejoin="round"><rect x="2.5" y="6.5" width="19" height="11" rx="1.5"/><circle cx="12" cy="12" r="2.6"/></svg>',
        bank: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9.5 12 4l9 5.5"/><path d="M5.5 10.5v7M10 10.5v7M14 10.5v7M18.5 10.5v7"/><path d="M3.5 20h17"/></svg>',
    };
    const STALE_MS = 8000;

    /** A notification in the capsule: { type, glyph, html|text, duration }. Waits for the capsule (one at a time);
     *  dropped when the HUD is hidden or it has waited too long. */
    function notify(n) {
        if (!container || !n) return false;
        if (!statusHud || !statusHud.classList.contains("visible")) return false;
        queue.push(Object.assign({ at: Date.now() }, n));
        if (_mode === "stats") nextNotification();
        return true;
    }

    function nextNotification() {
        if (_mode !== "stats" || notifyTimer) return;
        while (queue.length) {
            const n = queue.shift();
            if (Date.now() - n.at > STALE_MS) continue;
            if (capsuleIcon) capsuleIcon.innerHTML = NOTIFY_GLYPHS[n.glyph] || NOTIFY_GLYPHS[n.type] || NOTIFY_GLYPHS.info;
            if (capsuleBubble) capsuleBubble.style.setProperty("--cap-bubble-color", NOTIFY_COLORS[n.type] || NOTIFY_COLORS.info);
            if (capsuleText) {
                if (typeof n.html === "string") capsuleText.innerHTML = n.html;
                else capsuleText.textContent = String(n.text || "");
            }
            setCapsuleMode("notify");
            notifyTimer = setTimeout(() => {
                notifyTimer = null;
                setCapsuleMode("stats");
            }, n.duration || 3000);
            return;
        }
    }

    // ---- placement: under the map's frame (WHIP), the corner, or the player's own spot ----
    //
    // Under the frame: client/skin.lua sends the frame's outside edge (hudFrameBox). Laid out as slots, at least
    // ROW_SLOTS of them, so the first gauge always sits in the same place; worked out from the stylesheets' own sizes
    // (getBoundingClientRect inside a zoomed element answers in unzoomed coordinates on CEF 103).

    let _frameBox = null;
    let _placement = { mode: "map" };
    const DISC_INSET = 1.5;
    const ROW_SLOTS = 5;
    let _lastLayout = "";

    function cssPx(el, name) {
        return parseFloat(root.getComputedStyle(el).getPropertyValue(name)) || 0;
    }

    function baseGauges() {
        let n = 0;
        for (const el of statusHudStats.children) {
            if (!el.classList.contains("show-above-zero") && !el.classList.contains("show-when-present")
                && !el.classList.contains("show-below-full")) n++;
        }
        return Math.max(1, n);
    }

    function clearPlacement() {
        statusHudWrapper.style.left = "";
        statusHudWrapper.style.bottom = "";
        statusHudWrapper.style.top = "";
        statusHudWrapper.style.transform = "";
        statusHudWrapper.style.transformOrigin = "";
        statusHud.style.removeProperty("--hb-gap");
    }

    function layoutUnderFrame() {
        if (!statusHud || !statusHudWrapper || !container || !statusHudStats) return;
        const p = _placement;
        if (p.mode === "custom") {
            const key = "custom " + p.x + " " + p.y + " " + p.scale;
            if (key === _lastLayout) return;
            _lastLayout = key;
            clearPlacement();
            statusHudWrapper.style.left = p.x + "%";
            statusHudWrapper.style.top = p.y + "%";
            statusHudWrapper.style.bottom = "auto";
            statusHudWrapper.style.transform = `scale(${p.scale || 1})`;
            statusHudWrapper.style.transformOrigin = "top left";
            return;
        }
        if (!_frameBox || p.mode !== "map" || !statusHud.classList.contains("skin-black")) {
            if (_lastLayout !== "") { _lastLayout = ""; clearPlacement(); }
            return;
        }
        const zoom = parseFloat(root.getComputedStyle(statusHud).zoom) || 1;
        const W = root.innerWidth, H = root.innerHeight;
        const ring = cssPx(statusHud, "--sh-ring-size") || 67;
        const padX = cssPx(statusHud, "--sh-capsule-pad-x");
        const padY = cssPx(statusHud, "--sh-capsule-pad-y");
        const border = parseFloat(root.getComputedStyle(container).borderLeftWidth) || 0;
        const disc = ring - 2 * DISC_INSET;
        const base = baseGauges();
        const width = (_frameBox.right - _frameBox.left) * W / zoom;
        const fill = (k) => k > 1 ? Math.max(2, Math.min(24, (width - k * disc) / (k - 1))) : 0;
        const slots = Math.max(ROW_SLOTS, base);
        const gap = fill(slots);
        const rowWidth = slots * disc + (slots - 1) * gap;
        const left = _frameBox.left * W / zoom + (width - rowWidth) / 2 - (border + padX + DISC_INSET);
        const discTop = _frameBox.bottom * H + gap * zoom;
        const capTop = discTop - (border + padY + DISC_INSET) * zoom;
        const capHeight = ring + 2 * padY + 2 * border;
        const bottom = (H - capTop) / zoom - capHeight;
        const key = left.toFixed(2) + " " + bottom.toFixed(2) + " " + gap.toFixed(2);
        if (key === _lastLayout) return;
        _lastLayout = key;
        statusHudWrapper.style.top = "";
        statusHudWrapper.style.transform = "";
        statusHud.style.setProperty("--hb-gap", (gap - 2 * DISC_INSET) + "px");
        statusHudWrapper.style.left = left + "px";
        statusHudWrapper.style.bottom = bottom + "px";
    }

    root.addEventListener("resize", () => { _lastLayout = null; layoutUnderFrame(); });

    // ---- router ----

    PfHud.on("registerHudStats", (d) => registerHudStats(d.stats));
    PfHud.on("showStatusHud", () => showStatusHud());
    PfHud.on("hideStatusHud", () => hideStatusHud());
    PfHud.on("setHudSkin", (d) => setHudSkin(d.skin));
    PfHud.on("hudFrameBox", (d) => {
        if (typeof d.left === "number" && typeof d.right === "number" && typeof d.bottom === "number") {
            _frameBox = { left: d.left, right: d.right, bottom: d.bottom, top: d.top };
            _lastLayout = null;
            layoutUnderFrame();
        }
    });
    PfHud.on("updateStatusHud", (d) => updateStatusHud(d));
    PfHud.on("setVoiceTalking", (d) => setVoiceTalking(d.talking, d.mode));

    root.PfHudStatus = {
        notify,
        capsuleMode: () => _mode,
        frameBox: () => _frameBox,
        /** { mode: 'map' | 'corner' | 'custom', x, y, scale } */
        setPlacement(p) {
            _placement = p && typeof p === "object" ? p : { mode: "map" };
            _lastLayout = null;
            layoutUnderFrame();
        },
        registered: () => Object.keys(_hudRegistry),
        update: updateStatusHud,
        setSkin: setHudSkin,
    };
})(window);
