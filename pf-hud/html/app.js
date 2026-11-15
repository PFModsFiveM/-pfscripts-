/* pf-hud: the page's shell (classic script, loaded last). The settings and the global theme, the compass, money in
 * the capsule, cinematic bars, the map logo, the settings menu and the layout editor. The gauges (js/status-hud.js),
 * the dial (js/vehicle-dial.js) and the radar tuner (js/radar-tuner.js) are WHIP's, ported. */
(function (root) {
    "use strict";
    const doc = root.document;
    const PfHud = root.PfHud;
    const Status = root.PfHudStatus;
    const Dial = root.PfHudDial;

    const DEFAULT_THEME = { primary: "#111217", secondary: "#1c1e26", accent: "#5b9dff", text: "#eceef2", opacity: 0.92 };
    const DEFAULT_BOXES = { speedo: true, status: false, compass: true, icons: true, money: true };
    const CLUSTERS = ["status", "dial", "compass"];
    const emptyLayout = () => ({ status: null, dial: null, compass: null, money: null });

    let settings = {
        hudStyle: "black",
        statusLayout: "map",
        accent: "#5b9dff",
        scale: 1.0,
        idleFade: true,
        showCompass: true,
        compassOnFoot: false,
        showStreets: true,
        minimapStyle: "frame",
        minimapShape: "rounded",
        mapBackground: 100,
        minimapOnFoot: false,
        minimapInVehicle: true,
        speedUnit: "mph",
        dialStyle: "custom",
        dialHorizon: "ball",
        showMoney: true,
        cinematicMode: false,
        showLogo: false,
        theme: { ...DEFAULT_THEME },
        boxes: { ...DEFAULT_BOXES },
        layout: emptyLayout(),
    };
    let currency = "$";
    let prefsFromUi = false;
    let editMode = false;

    const el = (id) => doc.getElementById(id);
    const post = (event, data) => PfHud.post(event, data);

    // ── theme and scale ──────────────────────────────────────────────

    const hexToRgba = (hex, a) => {
        const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || "#111217");
        if (!m) return `rgba(17,18,23,${a})`;
        return `rgba(${parseInt(m[1], 16)},${parseInt(m[2], 16)},${parseInt(m[3], 16)},${a})`;
    };

    function applyTheme() {
        const t = { ...DEFAULT_THEME, ...(settings.theme || {}) };
        const r = doc.documentElement.style;
        r.setProperty("--ui-accent", t.accent);
        r.setProperty("--ui-info", t.accent);
        r.setProperty("--ui-accent-glow", hexToRgba(t.accent, 0.2));
        r.setProperty("--ui-accent-subtle", hexToRgba(t.accent, 0.07));
        r.setProperty("--ui-accent-light", hexToRgba(t.accent, 0.15));
        r.setProperty("--ui-accent-medium", hexToRgba(t.accent, 0.3));
        r.setProperty("--hud-scale", String(Math.max(0.6, Math.min(1.6, Number(settings.scale) || 1))));
        settings.accent = t.accent;
    }

    // WHIP's resolution scaling: designed at 1440p
    function applyScreenScale() {
        doc.documentElement.style.setProperty("--ui-scale", String((root.innerHeight || 1080) / 1440));
    }

    // ── applying every setting ───────────────────────────────────────

    function applyLayout() {
        const L = settings.layout || {};
        const st = L.status;
        if (st && typeof st.x === "number") Status.setPlacement({ mode: "custom", x: st.x, y: st.y, scale: st.scale || 1 });
        else Status.setPlacement({ mode: settings.statusLayout === "corner" ? "corner" : "map" });
        Dial.setLayout(L.dial && typeof L.dial.x === "number" ? L.dial : null);
        const c = el("compass");
        const cp = L.compass;
        if (cp && typeof cp.x === "number") {
            c.classList.add("custom");
            c.style.left = cp.x + "%";
            c.style.top = cp.y + "%";
            c.style.transform = `scale(${cp.scale || 1})`;
            c.style.transformOrigin = "top left";
        } else {
            c.classList.remove("custom");
            c.style.left = c.style.top = c.style.transform = c.style.transformOrigin = "";
        }
        placeDialProxy();
    }

    function applyAll() {
        applyTheme();
        const sh = el("status-hud");
        Status.setSkin(settings.hudStyle === "classic" ? "classic" : settings.hudStyle === "minimal" ? "minimal" : "black");
        sh.classList.toggle("idle-fade", settings.idleFade !== false && settings.hudStyle !== "minimal");
        const boxes = { ...DEFAULT_BOXES, ...(settings.boxes || {}) };
        sh.classList.toggle("boxed", boxes.status === true);
        el("compass").classList.toggle("no-box", boxes.compass === false);
        applyLayout();
        placeLogo();
        setCinematic(!!settings.cinematicMode);
    }

    // ── compass ──────────────────────────────────────────────────────

    function updateCompass(d) {
        const c = el("compass");
        if (!d.show && !editMode) { c.classList.add("hidden"); return; }
        c.classList.remove("hidden");
        if (d.direction) el("compass-dir").textContent = d.direction;
        if (typeof d.heading === "number") el("compass-deg").textContent = d.heading + "°";
        el("compass-street").textContent = d.street || "";
        c.classList.toggle("no-street", !d.street);
    }

    // ── the iFruit logo over the map's corner ────────────────────────

    let frame = null;
    function placeLogo() {
        const logo = el("minimap-logo");
        const show = settings.showLogo === true && frame && typeof frame.mapLeft === "number"
            && settings.minimapStyle !== "native" && !settings.cinematicMode;
        if (!show) { logo.classList.add("hidden"); return; }
        const W = root.innerWidth, H = root.innerHeight;
        logo.style.left = (frame.mapLeft * W + 0.008 * H) + "px";
        logo.style.top = (frame.mapTop * H + 0.008 * H) + "px";
        logo.classList.remove("hidden");
    }

    // ── money, in the capsule ────────────────────────────────────────

    const fmt = new Intl.NumberFormat("en-US");
    const esc = (s) => String(s).replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
    const money = (n) => esc(currency) + fmt.format(Math.abs(Number(n) || 0));

    function onMoney(d) {
        const bank = d.type === "bank";
        const balance = bank ? d.bank : d.cash;
        const html = `<span class="${d.minus ? "cap-minus" : "cap-plus"}">${d.minus ? "−" : "+"}${money(d.amount)}</span>`
            + (balance != null ? `<span class="cap-balance">${bank ? "Bank" : "Cash"} ${money(balance)}</span>` : "");
        Status.notify({ type: d.minus ? "error" : "success", glyph: bank ? "bank" : "cash", html });
    }

    function onAccount(d) {
        const bank = d.account === "bank";
        Status.notify({ type: "info", glyph: bank ? "bank" : "cash", html: `${bank ? "Bank" : "Cash"} ${money(d.amount)}` });
    }

    // ── cinematic ────────────────────────────────────────────────────

    function setCinematic(active) {
        el("cine-top").classList.toggle("cine-active", active);
        el("cine-bottom").classList.toggle("cine-active", active);
        placeLogo();
    }

    // ── layout edit mode (mouse, or the pad through pfm-ui's pad.js) ──

    const nodeOf = (k) => (k === "status" ? el("statusHudWrapper") : k === "dial" ? el("dial-proxy") : el("compass"));
    let dragState = null;
    let selected = 0;
    let layoutBefore = null;
    const padOff = [];

    function placeDialProxy() {
        const p = el("dial-proxy");
        if (!editMode) { p.classList.add("hidden"); return; }
        const f = Dial.footprint();
        p.style.left = (f.cx - f.R) + "px";
        p.style.top = (f.cy - f.R) + "px";
        p.style.width = p.style.height = 2 * f.R + "px";
        p.classList.remove("hidden");
    }

    /** An element's spot as the layout keeps it (top-left, percent of the screen), from where it is now. */
    function currentSpot(k) {
        const L = settings.layout || (settings.layout = emptyLayout());
        if (L[k] && typeof L[k].x === "number") return L[k];
        const W = root.innerWidth, H = root.innerHeight;
        if (k === "dial") {
            const f = Dial.footprint();
            return { x: f.l / W * 100, y: f.t / H * 100, scale: 1 };
        }
        const r = nodeOf(k).getBoundingClientRect();
        return { x: r.left / W * 100, y: r.top / H * 100, scale: 1 };
    }

    function setSpot(k, spot) {
        if (!settings.layout) settings.layout = emptyLayout();
        settings.layout[k] = {
            x: Math.max(0, Math.min(97, spot.x)),
            y: Math.max(0, Math.min(97, spot.y)),
            scale: Math.max(0.6, Math.min(1.8, spot.scale || 1)),
        };
        applyLayout();
    }

    function markSelected() {
        CLUSTERS.forEach((k, i) => nodeOf(k).classList.toggle("selected", i === selected));
    }

    function enterEditMode() {
        editMode = true;
        layoutBefore = JSON.parse(JSON.stringify(settings.layout || emptyLayout()));
        el("menu-backdrop").classList.add("hidden");
        post("editMode");
        doc.body.classList.add("editing");
        el("edit-bar").classList.remove("hidden");
        el("status-hud").classList.add("visible");
        Status.update({ voice: 50, health: 76, armour: 45, hunger: 80, thirst: 65, stress: 30, oxygen: 100,
            inVehicle: true, seatbelt: true, cruise: true });
        updateCompass({ show: true, direction: "NW", heading: 312, street: "Vespucci Blvd" });
        Dial.setEditing(true);
        CLUSTERS.forEach((k) => { const n = nodeOf(k); n.classList.add("editable"); n.dataset.cluster = k; });
        placeDialProxy();
        selected = 0;
        markSelected();
        if (root.PfmPad) {
            root.PfmPad.clear();
            const nudge = (dx, dy) => () => { const s = currentSpot(CLUSTERS[selected]); setSpot(CLUSTERS[selected], { x: s.x + dx, y: s.y + dy, scale: s.scale }); };
            const size = (d) => () => { const s = currentSpot(CLUSTERS[selected]); setSpot(CLUSTERS[selected], { x: s.x, y: s.y, scale: (s.scale || 1) + d }); };
            const pick = (d) => () => { selected = (selected + d + CLUSTERS.length) % CLUSTERS.length; markSelected(); };
            padOff.push(root.PfmPad.on("up", nudge(0, -0.5)), root.PfmPad.on("down", nudge(0, 0.5)),
                root.PfmPad.on("left", nudge(-0.5, 0)), root.PfmPad.on("right", nudge(0.5, 0)),
                root.PfmPad.on("tabPrev", pick(-1)), root.PfmPad.on("tabNext", pick(1)),
                root.PfmPad.on("triggerLeft", size(-0.05)), root.PfmPad.on("triggerRight", size(0.05)),
                root.PfmPad.on("select", () => exitEditMode(true)), root.PfmPad.on("back", () => exitEditMode(false)));
        }
    }

    function exitEditMode(save) {
        if (!editMode) return;
        editMode = false;
        while (padOff.length) { const off = padOff.pop(); if (typeof off === "function") off(); }
        doc.body.classList.remove("editing");
        el("edit-bar").classList.add("hidden");
        CLUSTERS.forEach((k) => nodeOf(k).classList.remove("editable", "selected"));
        Dial.setEditing(false);
        if (!save && layoutBefore) settings.layout = layoutBefore;
        applyAll();
        if (save) post("saveSettings", settings);
        post("closeMenu");
    }

    doc.addEventListener("pointerdown", (e) => {
        if (!editMode) return;
        const target = e.target.closest && e.target.closest(".editable");
        if (!target) return;
        const k = target.dataset.cluster;
        selected = CLUSTERS.indexOf(k);
        markSelected();
        dragState = { k, sx: e.clientX, sy: e.clientY, start: { ...currentSpot(k) } };
        e.preventDefault();
    });
    doc.addEventListener("pointermove", (e) => {
        if (!editMode || !dragState) return;
        const W = root.innerWidth, H = root.innerHeight;
        const s = dragState.start;
        setSpot(dragState.k, { x: s.x + (e.clientX - dragState.sx) / W * 100, y: s.y + (e.clientY - dragState.sy) / H * 100, scale: s.scale });
    });
    doc.addEventListener("pointerup", () => { dragState = null; });
    doc.addEventListener("wheel", (e) => {
        if (!editMode) return;
        const target = e.target.closest && e.target.closest(".editable");
        if (!target) return;
        const k = target.dataset.cluster;
        const s = currentSpot(k);
        setSpot(k, { x: s.x, y: s.y, scale: (s.scale || 1) + (e.deltaY < 0 ? 0.05 : -0.05) });
    }, { passive: true });

    // ── the settings menu ────────────────────────────────────────────

    let draft = null;

    function segment(obj, key, options, labels) {
        const wrap = doc.createElement("div");
        wrap.className = "segment";
        options.forEach((opt, i) => {
            const b = doc.createElement("button");
            b.type = "button";
            b.textContent = labels ? labels[i] : opt;
            b.classList.toggle("active", obj[key] === opt);
            b.addEventListener("click", () => {
                obj[key] = opt;
                wrap.querySelectorAll("button").forEach((x) => x.classList.remove("active"));
                b.classList.add("active");
            });
            wrap.appendChild(b);
        });
        return wrap;
    }

    // `strict`: the value is on only when exactly true (else: on unless exactly false)
    function toggle(obj, key, strict) {
        const isOn = () => (strict ? obj[key] === true : obj[key] !== false);
        const s = doc.createElement("div");
        s.className = "switch" + (isOn() ? " on" : "");
        s.dataset.pad = "";
        s.tabIndex = 0;
        s.addEventListener("click", () => { obj[key] = !isOn(); s.classList.toggle("on", isOn()); });
        return s;
    }

    function colorInput(obj, key) {
        const i = doc.createElement("input");
        i.type = "color";
        i.className = "color-pick";
        i.value = obj[key];
        i.addEventListener("input", () => { obj[key] = i.value; });
        return i;
    }

    function range(obj, key, min, max, step) {
        const i = doc.createElement("input");
        i.type = "range"; i.min = min; i.max = max; i.step = step; i.value = obj[key];
        i.addEventListener("input", () => { obj[key] = parseFloat(i.value); });
        return i;
    }

    function button(text, fn) {
        const b = doc.createElement("button");
        b.type = "button";
        b.className = "menu-mini-btn";
        b.textContent = text;
        b.addEventListener("click", fn);
        return b;
    }

    function row(label, control) {
        const r = doc.createElement("div");
        r.className = "menu-row";
        const span = doc.createElement("span");
        span.textContent = label;
        r.appendChild(span);
        r.appendChild(control);
        return r;
    }

    function section(label) {
        const s = doc.createElement("div");
        s.className = "menu-section";
        s.textContent = label;
        return s;
    }

    function buildMenu() {
        draft = JSON.parse(JSON.stringify(settings));
        if (!draft.theme) draft.theme = { ...DEFAULT_THEME };
        if (!draft.boxes) draft.boxes = { ...DEFAULT_BOXES };
        const body = el("menu-body");
        body.innerHTML = "";
        el("menu-note").classList.toggle("hidden", !prefsFromUi);

        body.appendChild(section("Theme: every PF interface"));
        body.appendChild(row("Accent", colorInput(draft.theme, "accent")));
        body.appendChild(row("Panel colour", colorInput(draft.theme, "primary")));
        body.appendChild(row("Fields / rows", colorInput(draft.theme, "secondary")));
        body.appendChild(row("Text colour", colorInput(draft.theme, "text")));
        body.appendChild(row("Panel opacity", range(draft.theme, "opacity", 0.5, 1, 0.02)));
        body.appendChild(row("", button("Reset theme", () => { draft.theme = { ...DEFAULT_THEME }; rebuildKeepScroll(); })));

        body.appendChild(section("Gauges"));
        body.appendChild(row("Style", segment(draft, "hudStyle", ["black", "classic", "minimal"], ["Black", "Classic", "Minimal"])));
        body.appendChild(row("Position", segment(draft, "statusLayout", ["map", "corner"], ["Under the map", "Corner"])));
        body.appendChild(row("HUD size", range(draft, "scale", 0.8, 1.3, 0.05)));
        body.appendChild(row("Fade full gauges", toggle(draft, "idleFade", true)));
        body.appendChild(row("Capsule behind the gauges", toggle(draft.boxes, "status", true)));

        body.appendChild(section("Minimap"));
        body.appendChild(row("Look", segment(draft, "minimapStyle", ["frame", "dark", "native"], ["Framed", "Dark", "GTA"])));
        body.appendChild(row("Shape", segment(draft, "minimapShape", ["rounded", "square", "circle"], ["Rounded", "Square", "Circle"])));
        body.appendChild(row("Map background", range(draft, "mapBackground", 0, 100, 5)));
        body.appendChild(row("Show on foot", toggle(draft, "minimapOnFoot", true)));
        body.appendChild(row("Show in a vehicle", toggle(draft, "minimapInVehicle")));
        body.appendChild(row("iFruit logo", toggle(draft, "showLogo", true)));

        body.appendChild(section("Vehicle"));
        body.appendChild(row("Dial", segment(draft, "dialStyle", ["custom", "pf", "simple", "none"], ["Car's own", "PF", "Flat", "None"])));
        body.appendChild(row("Aircraft horizon", segment(draft, "dialHorizon", ["ball", "flat"], ["3D ball", "Flat"])));
        body.appendChild(row("Speed unit", segment(draft, "speedUnit", ["mph", "kmh"], ["MPH", "KM/H"])));

        body.appendChild(section("Compass"));
        body.appendChild(row("Show compass", toggle(draft, "showCompass", true)));
        body.appendChild(row("Compass on foot", toggle(draft, "compassOnFoot", true)));
        body.appendChild(row("Street names", toggle(draft, "showStreets", true)));
        body.appendChild(row("Compass capsule", toggle(draft.boxes, "compass")));

        body.appendChild(section("Layout"));
        body.appendChild(row("Move and resize", button("Edit layout", () => {
            settings = draft;
            applyAll();
            enterEditMode();
        })));
        body.appendChild(row("", button("Reset positions", () => { draft.layout = emptyLayout(); })));

        body.appendChild(section("Other"));
        body.appendChild(row("Money changes", toggle(draft, "showMoney", true)));
        body.appendChild(row("Cinematic mode", toggle(draft, "cinematicMode", true)));
    }

    function rebuildKeepScroll() {
        const scroll = el("menu-body").scrollTop;
        const d = draft;
        buildMenu();
        draft = d;
        el("menu-body").scrollTop = scroll;
    }

    function openMenu() {
        buildMenu();
        el("menu-backdrop").classList.remove("hidden");
        if (root.PfmPad) root.PfmPad.focusables(el("menu"), { onBack: closeMenu, autoFocus: true, wrap: true });
    }

    function closeMenu() {
        el("menu-backdrop").classList.add("hidden");
        if (root.PfmPad) root.PfmPad.clear();
        post("closeMenu");
    }

    el("menu-close").addEventListener("click", closeMenu);
    el("menu-save").addEventListener("click", () => {
        settings = draft;
        applyAll();
        post("saveSettings", settings);
        el("menu-backdrop").classList.add("hidden");
        if (root.PfmPad) root.PfmPad.clear();
        post("closeMenu");
    });
    el("edit-done").addEventListener("click", () => exitEditMode(true));
    el("edit-cancel").addEventListener("click", () => exitEditMode(false));

    doc.addEventListener("keyup", (e) => {
        if (e.key !== "Escape") return;
        if (editMode) return exitEditMode(true);
        if (!el("menu-backdrop").classList.contains("hidden")) closeMenu();
    });

    // ── messages ─────────────────────────────────────────────────────

    function mergeSettings(s) {
        if (!s || typeof s !== "object") return;
        settings = { ...settings, ...s };
        if (!settings.layout || typeof settings.layout !== "object") settings.layout = emptyLayout();
    }

    PfHud.on("compass", updateCompass);
    PfHud.on("money", (d) => { if (settings.showMoney) onMoney(d); });
    PfHud.on("account", (d) => { if (settings.showMoney) onAccount(d); });
    PfHud.on("cinematic", (d) => setCinematic(!!d.active));
    PfHud.on("hudFrameBox", (d) => { frame = d; placeLogo(); });
    PfHud.on("openMenu", (d) => {
        mergeSettings(d.settings);
        if (typeof d.prefsFromUi === "boolean") prefsFromUi = d.prefsFromUi;
        applyAll();
        openMenu();
    });
    PfHud.on("settings", (d) => {
        mergeSettings(d.settings);
        if (typeof d.currency === "string") currency = d.currency;
        if (typeof d.prefsFromUi === "boolean") prefsFromUi = d.prefsFromUi;
        applyAll();
    });

    root.addEventListener("resize", () => { applyScreenScale(); placeLogo(); placeDialProxy(); });

    applyScreenScale();
    applyAll();

    root.PfHudApp = { settings: () => settings, enterEditMode, exitEditMode, openMenu, closeMenu, editing: () => editMode };

    // the page is up: the client sends everything again (a page that reloaded mid-session)
    post("ready", {});
})(window);
