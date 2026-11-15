/* Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
 * Port of whip_core/html/js/vehicle-dial.js (the bridge between the client and the 3D rev dial in js/vehicle_hud/), as a
 * classic script on PfHud's router. Free software under the GNU Lesser General Public License 3.0
 * (pf-hud/COPYING.LESSER and COPYING).
 *
 * What it takes: client/dial.lua's updateVehicleDials (15 Hz at most, change-gated), vehicleDialRange (on getting in:
 * the rev range, the kind: car, air or boat, a dial at all, the car's dashboard look) and vehicleHudConfig (units,
 * horizon, style, where pfm-media-map is); client.lua's 'vehicle' (the fuel and nitrous gauges round the dial) and
 * show/hideVehicleHud. It follows #status-hud's own fade (dead, the pause menu, cinematic mode).
 *
 * THE DIAL AND three.js ARE IMPORTED THE FIRST TIME A VEHICLE IS ENTERED, so a player on foot pays nothing.
 * PF: without WebGL (or a failed import, or the player's 'simple' choice) a flat dial (#simpleDial) shows the same
 * numbers. The dashboard looks are pfm-media-map's (html/dash_skins3d.js, loaded as a classic script); without it every
 * car keeps the dial as designed. The layout editor can move and size it (PfHudDial.setLayout). */
(function (root) {
    "use strict";
    const doc = root.document;
    const PfHud = root.PfHud;
    const statusHud = doc.getElementById("status-hud");

    // js/vehicle_hud/dial.js BOX: the dial's layout box in dial radii, its centre at (cx, cy)
    const BOX = { w: 3.37, h: 3.15, cx: 1.9, cy: 1.9 };

    let hud = null, canvas = null, loading = null, simple = null;
    let enabled = true, inVehicle = false, hasDial = true, shown = false, hideTimer = 0, editing = false;
    let style = "custom", mediaUrl = null, skinsLoading = null;
    let layout = null;   // { x, y, scale } from the layout editor (percent of the screen), or null
    const onResize = () => { if (hud) hud.resize(); place(); };

    const state = { rpm: 0, maxRpm: 8, redline: null, speed: 0, units: "mph", gear: "N", engine: false, lights: "off",
        locked: false, damage: false, kind: "car", pitch: 0, roll: 0, altitude: 0, gearState: "none", power: 0,
        anchored: false, skin: null };
    const dialConfig = { attitude: "ball", skins: true, scale: 1 };

    const DIAL_RIGHT = { car: 1.242, boat: 1.242, air: 1.671 };
    const dialPlace = (kind) => ({ right: DIAL_RIGHT[kind] || DIAL_RIGHT.car });
    let rawRpm = 0;
    let idleRpm = null;
    const gauges = new Map();

    // ---- the numbers ----

    const LIMITER_RAW = 0.99, IDLE_AT = 0.113;
    function toThousands(raw, max, idle) {
        if (!(raw > 0)) return 0;
        if (raw >= LIMITER_RAW) return max;
        const low = typeof idle === "number" && idle >= 0 && idle < max ? idle : max * IDLE_AT;
        return low + (Math.max(raw, 0.2) - 0.2) / (LIMITER_RAW - 0.2) * (max - low);
    }
    function toPower(raw) {
        if (!(raw > 0)) return 0;
        if (raw >= LIMITER_RAW) return 1;
        return Math.max(0, Math.min(1, (raw - 0.2) / 0.8));
    }

    function setState(partial) {
        Object.assign(state, partial);
        if (hud) hud.setState(partial);
        if (simple) paintSimple();
    }

    // ---- where it sits ----

    /** The dial's footprint in window pixels (with the layout's move): its box, and its radius. */
    function footprint() {
        const W = root.innerWidth, H = root.innerHeight;
        const k = layout && layout.scale ? layout.scale : 1;
        const R = Math.max(30, Math.floor(Math.min(0.1257 * H, 0.2 * W) * k));
        const cx = W - (DIAL_RIGHT[state.kind] || DIAL_RIGHT.car) * R, cy = H - 1.35 * R;
        let l = cx - BOX.cx * R, t = cy - BOX.cy * R;
        let dx = 0, dy = 0;
        if (layout && typeof layout.x === "number") {
            dx = layout.x / 100 * W - l;
            dy = layout.y / 100 * H - t;
        }
        return { R, cx: cx + dx, cy: cy + dy, l: l + dx, t: t + dy, w: BOX.w * R, h: BOX.h * R, dx, dy };
    }

    function place() {
        const f = footprint();
        const s = doc.documentElement.style;
        s.setProperty("--dial-dx", Math.round(f.dx) + "px");
        s.setProperty("--dial-dy", Math.round(f.dy) + "px");
        if (simple) {
            simple.style.left = (f.cx - f.dx - f.R) + "px";
            simple.style.top = (f.cy - f.dy - f.R) + "px";
            simple.style.width = simple.style.height = (2 * f.R) + "px";
        }
    }

    // ---- the gauges round the dial: fuel and nitrous (client.lua's 'vehicle') ----

    function setGauge(g) {
        const was = gauges.get(g.id);
        if (was && was.value === g.value && was.text === g.text) return;
        gauges.set(g.id, g);
        if (hud) hud.setGauge(g);
    }
    function removeGauge(id) {
        if (!gauges.has(id)) return;
        gauges.delete(id);
        if (hud) hud.removeGauge(id);
    }

    let lastVehicle = null;
    function paintVehicle(d) {
        lastVehicle = d;
        const fuel = Math.max(0, Math.min(100, Number(d.fuel) || 0));
        setGauge({ id: "fuel", icon: "fuel", order: 1, value: Math.round(fuel) / 100, text: Math.round(fuel) + "%",
            ends: ["E", "F"], dangerLow: 0.2 });
        const nitro = Math.max(0, Math.min(100, Number(d.nitro) || 0));
        if (nitro > 0 || d.nitroActive) {
            setGauge({ id: "nitro", icon: "nitro", order: 2, value: nitro / 100, text: Math.round(nitro) + "%", dangerLow: 0.2 });
        } else removeGauge("nitro");
        if (simple) paintSimple();
    }

    // ---- the flat dial ----

    function buildSimple() {
        if (simple) return simple;
        simple = doc.createElement("div");
        simple.id = "simpleDial";
        simple.innerHTML = '<div class="sd-rim"></div><div class="sd-speed">0</div><div class="sd-unit">mph</div>'
            + '<div class="sd-gear">N</div><div class="sd-lights"><b class="lock"></b><b class="beam"></b><b class="eng"></b>'
            + '<b class="warn"></b></div><div class="sd-fuel"><i></i></div>';
        doc.body.appendChild(simple);
        place();
        paintSimple();
        return simple;
    }

    function paintSimple() {
        if (!simple) return;
        const kmh = state.units === "kmh";
        const shownSpeed = Math.round((Number(state.speed) || 0) * (kmh ? 1 : 0.621371));
        const q = (sel) => simple.querySelector(sel);
        q(".sd-speed").textContent = String(shownSpeed);
        let unit = kmh ? "km/h" : "mph", share = 0, gear = String(state.gear == null ? "N" : state.gear);
        if (state.kind === "air") { unit = "alt " + Math.round((Number(state.altitude) || 0) * 3.28084) + " ft"; gear = ""; share = 0; }
        else if (state.kind === "boat") share = Number(state.power) || 0;
        else share = state.maxRpm > 0 ? Math.min(1, (Number(state.rpm) || 0) / state.maxRpm) : 0;
        q(".sd-unit").textContent = unit;
        q(".sd-gear").textContent = gear;
        simple.style.setProperty("--sd-rpm", share.toFixed(3));
        simple.classList.toggle("limiter", state.kind === "car" && share >= 0.99);
        const lights = q(".sd-lights").children;
        lights[0].classList.toggle("on", state.kind === "air" ? state.gearState === "down" : state.kind === "boat" ? !!state.anchored : !!state.locked);
        lights[1].classList.toggle("on", state.lights !== "off");
        lights[1].classList.toggle("high", state.lights === "high");
        lights[2].classList.toggle("on", !!state.engine);
        lights[3].classList.toggle("on", !!state.damage);
        const fuel = lastVehicle ? Math.max(0, Math.min(100, Number(lastVehicle.fuel) || 0)) : 100;
        simple.style.setProperty("--sd-fuel", fuel + "%");
        simple.classList.toggle("low-fuel", !!(lastVehicle && lastVehicle.lowFuel));
    }

    // ---- loading ----

    function webglOk() {
        try {
            const c = doc.createElement("canvas");
            return !!(c.getContext && (c.getContext("webgl2") || c.getContext("webgl")));
        } catch (e) {
            return false;
        }
    }

    /** The 3D dial, or the flat one: answers which ('3d' | 'simple'). */
    function load() {
        if (style === "simple" || (!hud && !webglOk())) return Promise.resolve(useSimple());
        if (!loading) {
            let p;
            try { p = import("./vehicle_hud/hud.js"); } catch (e) { p = Promise.reject(e); }
            loading = p.then((mod) => {
                canvas = doc.createElement("canvas");
                canvas.id = "vehicleDial";
                doc.body.appendChild(canvas);
                hud = mod.createVehicleHud(canvas);
                hud.setConfig({ ...dialConfig, ...dialPlace(state.kind), scale: layout && layout.scale ? layout.scale : 1 });
                hud.setState({ ...state, rpm: toThousands(rawRpm, state.maxRpm, idleRpm) });
                for (const g of gauges.values()) hud.setGauge(g);
                if (root.PfDashSkins) hud.setSkinData(root.PfDashSkins);
                root.addEventListener("resize", onResize);
                if (!enabled) unload();
                return "3d";
            }).catch((e) => {
                console.error("[pf-hud] the 3D dial could not load, using the flat one:", e && e.message ? e.message : e);
                loading = Promise.resolve(useSimple());
                return "simple";
            });
        }
        return loading;
    }

    function useSimple() {
        buildSimple();
        return "simple";
    }

    function unload() {
        if (hud) {
            hud.dispose();
            canvas.remove();
            root.removeEventListener("resize", onResize);
        }
        hud = null; canvas = null; loading = null; shown = false;
        if (simple) { simple.remove(); simple = null; }
    }

    /** pfm-media-map's dashboard looks, once (a classic script setting window.PfDashSkins). */
    function loadSkins() {
        if (root.PfDashSkins) { if (hud) hud.setSkinData(root.PfDashSkins); return; }
        if (skinsLoading || !mediaUrl || style !== "custom") return;
        skinsLoading = true;
        const s = doc.createElement("script");
        s.src = mediaUrl + "html/dash_skins3d.js";
        s.onload = () => { if (hud && root.PfDashSkins) hud.setSkinData(root.PfDashSkins); };
        s.onerror = () => { skinsLoading = false; s.remove(); };
        doc.head.appendChild(s);
    }

    function hudShown() {
        return !!statusHud && statusHud.classList.contains("visible");
    }

    function update() {
        const want = editing || (enabled && inVehicle && hasDial && hudShown());
        if (want === shown) return;
        shown = want;
        clearTimeout(hideTimer);
        if (want) {
            load().then((which) => {
                if (!shown) return;
                if (which === "simple") {
                    if (simple) { place(); paintSimple(); simple.classList.add("on"); }
                } else if (hud) {
                    hud.show();
                    canvas.classList.add("on");
                }
            });
        } else {
            if (canvas) canvas.classList.remove("on");
            if (simple) simple.classList.remove("on");
            hideTimer = setTimeout(() => {
                if (shown) return;
                if (!enabled) unload();
                else if (hud) hud.hide();
            }, 400);
        }
    }

    if (statusHud && root.MutationObserver) {
        new root.MutationObserver(update).observe(statusHud, { attributes: true, attributeFilter: ["class"] });
    }

    // ---- messages ----

    PfHud.on("showVehicleHud", () => { inVehicle = true; update(); });
    PfHud.on("hideVehicleHud", () => { inVehicle = false; hasDial = false; update(); });

    PfHud.on("vehicleHudConfig", (d) => {
        if (!d) return;
        if (d.units === "kmh" || d.units === "mph") setState({ units: d.units });
        if ((d.attitude === "ball" || d.attitude === "flat") && d.attitude !== dialConfig.attitude) {
            dialConfig.attitude = d.attitude;
            if (hud) hud.setConfig({ attitude: d.attitude });
        }
        if (typeof d.skins === "boolean" && d.skins !== dialConfig.skins) {
            dialConfig.skins = d.skins;
            if (hud) hud.setConfig({ skins: d.skins });
        }
        mediaUrl = typeof d.media === "string" && /^https?:\/\/[^"'<>\s]+\/$/.test(d.media) ? d.media : null;
        const nextStyle = ["custom", "pf", "simple", "none"].indexOf(d.style) >= 0 ? d.style : style;
        const wasSimpleChoice = style === "simple";
        style = nextStyle;
        enabled = style !== "none";
        if (style !== "simple" && wasSimpleChoice && simple) { simple.remove(); simple = null; loading = null; shown = false; }
        if (style === "simple" && hud) unload();
        if (!enabled && !shown) unload();
        loadSkins();
        update();
    });

    PfHud.on("vehicleDialRange", (d) => {
        if (!d) return;
        hasDial = d.dial !== false;
        const maxRpm = Number(d.maxRpm) || 8;
        idleRpm = typeof d.idle === "number" ? d.idle : null;
        const kind = d.kind === "air" || d.kind === "boat" ? d.kind : "car";
        setState({ kind, maxRpm, redline: typeof d.redline === "number" ? d.redline : null,
            rpm: toThousands(rawRpm, maxRpm, idleRpm), skin: typeof d.skin === "string" ? d.skin : null });
        if (hud) hud.setConfig(dialPlace(kind));
        place();
        update();
    });

    PfHud.on("updateVehicleDials", (d) => {
        if (!d) return;
        rawRpm = Number(d.rpm) || 0;
        const p = {
            rpm: toThousands(rawRpm, state.maxRpm, idleRpm), speed: Number(d.speed) || 0, gear: d.gear == null ? "N" : d.gear,
            engine: d.eng === true, lights: d.lights || "off", locked: d.locked === true, damage: d.dmg === true,
            launch: d.launch === true,
        };
        if (state.kind === "air") {
            p.pitch = Number(d.pitch) || 0; p.roll = Number(d.roll) || 0; p.altitude = Number(d.alt) || 0;
            p.gearState = d.gearState || "none";
        } else if (state.kind === "boat") {
            p.power = d.freeRev === true ? 1 : toPower(rawRpm); p.anchored = d.anchored === true;
        }
        setState(p);
    });

    PfHud.on("vehicle", (d) => {
        if (!d) return;
        if (d.show === false) return;
        paintVehicle(d);
    });

    root.addEventListener("resize", place);

    root.PfHudDial = {
        footprint,
        /** { x, y, scale } (percent of the screen and a size), or null for the corner */
        setLayout(l) {
            layout = l && typeof l === "object" && typeof l.x === "number" ? { x: l.x, y: l.y, scale: l.scale || 1 } : null;
            const k = layout ? layout.scale : 1;
            doc.documentElement.style.setProperty("--dial-scale", "1");
            if (hud) hud.setConfig({ scale: k });
            place();
        },
        /** the layout editor shows the dial with sample numbers */
        setEditing(on) {
            editing = !!on;
            if (editing) {
                setState({ rpm: toThousands(0.55, state.maxRpm, idleRpm), speed: 88, gear: 3, engine: true, lights: "low" });
                paintVehicle({ fuel: 60, nitro: 55 });
            }
            update();
        },
        state: () => Object.assign({}, state),
        mode: () => (hud ? "3d" : simple ? "simple" : "none"),
        shown: () => shown,
    };
})(window);
