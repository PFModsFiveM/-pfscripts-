/* PF HUD — vanilla JS (theme engine + split clusters + layout editor) */

const DEFAULT_THEME = { primary: "#111217", secondary: "#1c1e26", accent: "#5b9dff", text: "#eceef2", opacity: 0.92 };
const DEFAULT_BOXES = { speedo: true, status: true, compass: true, icons: true, money: true };

let settings = {
    hudStyle: "rings",
    accent: "#5b9dff",
    scale: 1.0,
    idleFade: true,
    showCompass: true,
    compassOnFoot: false,
    showStreets: true,
    minimapShape: "rounded",
    minimapOnFoot: false,
    speedUnit: "mph",
    showMoney: true,
    cinematicMode: false,
    showLogo: true,
    theme: { ...DEFAULT_THEME },
    boxes: { ...DEFAULT_BOXES },
    layout: { status: null, speedo: null, vehicleIcons: null, nitro: null, compass: null, money: null },
};
let currency = "$";
let editMode = false;

const el = (id) => document.getElementById(id);
const post = (event, data) =>
    fetch(`https://pf-hud/${event}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(data ?? {}),
    });

const hexToRgba = (hex, a) => {
    const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || "#111217");
    if (!m) return `rgba(17,18,23,${a})`;
    return `rgba(${parseInt(m[1], 16)},${parseInt(m[2], 16)},${parseInt(m[3], 16)},${a})`;
};

const applyTheme = () => {
    const t = { ...DEFAULT_THEME, ...(settings.theme || {}) };
    const r = document.documentElement.style;
    r.setProperty("--accent", t.accent);
    r.setProperty("--glass", hexToRgba(t.primary, t.opacity));
    r.setProperty("--glass-soft", hexToRgba(t.primary, Math.max(0, t.opacity - 0.2)));
    r.setProperty("--fg", t.text);
    r.setProperty("--fg-dim", hexToRgba(t.text, 0.6));
    r.setProperty("--scale", settings.scale);
    settings.accent = t.accent;
};

const applyBoxes = () => {
    const b = { ...DEFAULT_BOXES, ...(settings.boxes || {}) };
    el("speedo").classList.toggle("no-box", !b.speedo);
    el("status").classList.toggle("no-box", !b.status);
    el("compass").classList.toggle("no-box", !b.compass);
    el("vehicleIcons").classList.toggle("no-box", !b.icons);
    el("nitro").classList.toggle("no-box", !b.icons);
    el("money").classList.toggle("no-box", !b.money);
};

/* ── layout engine ───────────────────────────────────────────────── */
const CLUSTERS = ["status", "speedo", "vehicleIcons", "nitro", "compass", "money"];

const applyLayout = () => {
    for (const k of CLUSTERS) {
        const node = el(k);
        const pos = settings.layout && settings.layout[k];
        if (pos && typeof pos.x === "number") {
            node.style.left = pos.x + "%";
            node.style.top = pos.y + "%";
            node.style.right = "auto";
            node.style.bottom = "auto";
            const s = (pos.scale || 1) * settings.scale;
            node.style.transform = `scale(${s})`;
            node.style.transformOrigin = "top left";
        } else {
            node.style.left = "";
            node.style.top = "";
            node.style.right = "";
            node.style.bottom = "";
            node.style.transform = "";
            node.style.transformOrigin = "";
        }
    }
};

/* ── status cluster ──────────────────────────────────────────────── */
const STATUS_DEFS = [
    { key: "health", icon: "favorite", color: "#ff5d5d", fadeAt: 101 },
    { key: "armor", icon: "shield", color: "#5b9dff", fadeAt: 1 },
    { key: "hunger", icon: "lunch_dining", color: "#ffb547", fadeAt: 95 },
    { key: "thirst", icon: "water_drop", color: "#2fd4c4", fadeAt: 95 },
    { key: "stress", icon: "psychology", color: "#b05bff", fadeAt: 1, invert: true },
    { key: "oxygen", icon: "bubble_chart", color: "#7ecbff", fadeAt: 101, hideAt: -1 },
];

const RING_R = 19;
const RING_C = 2 * Math.PI * RING_R;
let statusBuilt = null;

const buildStatus = () => {
    const wrap = el("status");
    wrap.innerHTML = "";
    if (settings.hudStyle === "bars") {
        for (const def of STATUS_DEFS) {
            const d = document.createElement("div");
            d.className = "sbar boxed";
            d.id = `st-${def.key}`;
            d.innerHTML = `
                <div class="sbar-label"><span>${def.key}</span><span id="st-${def.key}-val"></span></div>
                <div class="sbar-track"><div class="sbar-fill" id="st-${def.key}-fill" style="background:${def.color}"></div></div>`;
            wrap.appendChild(d);
        }
    } else {
        for (const def of STATUS_DEFS) {
            const d = document.createElement("div");
            d.className = "ring";
            d.id = `st-${def.key}`;
            d.innerHTML = `
                <svg viewBox="0 0 44 44">
                    <circle class="track" cx="22" cy="22" r="${RING_R}"></circle>
                    <circle class="bar" id="st-${def.key}-fill" cx="22" cy="22" r="${RING_R}"
                        stroke="${def.color}" stroke-dasharray="${RING_C}" stroke-dashoffset="0"></circle>
                </svg>
                <span class="material-icons-round">${def.icon}</span>`;
            wrap.appendChild(d);
        }
    }
    statusBuilt = settings.hudStyle;
    applyBoxes();
};

const setStatusValue = (def, value) => {
    const box = el(`st-${def.key}`);
    const fill = el(`st-${def.key}-fill`);
    if (!box || !fill) return;

    if (def.hideAt !== undefined && value === def.hideAt && !editMode) {
        box.classList.add("hidden");
        return;
    }
    box.classList.remove("hidden");

    const pct = Math.max(0, Math.min(100, value));
    if (settings.hudStyle === "bars") {
        fill.style.width = pct + "%";
        const valEl = el(`st-${def.key}-val`);
        if (valEl) valEl.textContent = Math.round(pct);
    } else {
        fill.style.strokeDashoffset = RING_C * (1 - pct / 100);
    }

    const idle = def.invert ? pct <= def.fadeAt - 1 : pct >= def.fadeAt;
    if (editMode) {
        box.classList.remove("hidden", "faded");
    } else if (settings.hudStyle === "minimal") {
        box.classList.toggle("hidden", idle);
    } else if (settings.idleFade) {
        box.classList.toggle("faded", idle);
    } else {
        box.classList.remove("faded");
    }

    const critical = def.invert ? pct >= 85 : (def.key === "health" ? pct <= 20 && pct > 0 : pct <= 10);
    box.classList.toggle("pulse", critical && def.key !== "armor" && !editMode);
};

const updateStatus = (d) => {
    const wrap = el("status");
    if (!d.show && !editMode) {
        wrap.classList.add("hidden");
        return;
    }
    wrap.classList.remove("hidden");
    if (statusBuilt !== settings.hudStyle) buildStatus();

    setStatusValue(STATUS_DEFS[0], d.health);
    setStatusValue(STATUS_DEFS[1], d.armor);
    setStatusValue(STATUS_DEFS[2], d.hunger);
    setStatusValue(STATUS_DEFS[3], d.thirst);
    setStatusValue(STATUS_DEFS[4], d.stress);
    setStatusValue(STATUS_DEFS[5], d.oxygen);
};

/* ── vehicle (three independent elements) ────────────────────────── */
const updateVehicle = (d) => {
    const speedo = el("speedo");
    const icons = el("vehicleIcons");
    const nitroEl = el("nitro");

    if (!d.show && !editMode) {
        speedo.classList.add("hidden");
        icons.classList.add("hidden");
        nitroEl.classList.add("hidden");
        return;
    }
    speedo.classList.remove("hidden");
    icons.classList.remove("hidden");

    el("speed").textContent = d.speed;
    el("speed-unit").textContent = d.unit === "kmh" ? "KM/H" : "MPH";

    const fuelFill = el("fuel-fill");
    fuelFill.style.width = Math.max(0, Math.min(100, d.fuel)) + "%";
    fuelFill.classList.toggle("low", d.lowFuel);

    const belt = el("icon-belt");
    belt.className = "veh-icon boxed " + (d.seatbelt ? "ok" : "bad");

    const engine = el("icon-engine");
    engine.className = "veh-icon boxed " + (d.engine < 25 ? "bad" : d.engine < 50 ? "warn" : "");
    engine.classList.toggle("hidden", d.engine >= 50 && !editMode);

    if (d.nitro > 0 || d.nitroActive || editMode) {
        nitroEl.classList.remove("hidden");
        el("icon-nitro").classList.toggle("nitro-active", d.nitroActive);
        el("nitro-fill").style.width = Math.max(0, Math.min(100, d.nitro)) + "%";
    } else {
        nitroEl.classList.add("hidden");
    }
    applyBoxes();
};

/* ── compass ─────────────────────────────────────────────────────── */
const updateCompass = (d) => {
    const c = el("compass");
    if (!d.show && !editMode) {
        c.classList.add("hidden");
        return;
    }
    c.classList.remove("hidden");
    el("compass-dir").textContent = d.direction;
    el("compass-deg").textContent = d.heading + "°";
    el("compass-street").textContent = d.street || "";
};

/* ── minimap frame + iFruit logo ─────────────────────────────────── */
let lastAnchor = null;

const IFRUIT_IMG = `<img src="ifruit.png" alt="" draggable="false" style="width:100%;height:100%;object-fit:contain;display:block" />`;

const updateMinimapFrame = (d) => {
    if (d) lastAnchor = d;
    d = lastAnchor;
    const f = el("minimap-frame");
    const logo = el("minimap-logo");
    if (!d || !d.anchor) {
        f.classList.add("hidden");
        logo.classList.add("hidden");
        return;
    }
    const w = window.innerWidth, h = window.innerHeight;
    f.className = d.shape;
    f.style.left = d.anchor.x * w - 3 + "px";
    f.style.top = d.anchor.y * h - 3 + "px";
    f.style.width = d.anchor.w * w + 6 + "px";
    f.style.height = d.anchor.h * h + 6 + "px";
    f.classList.remove("hidden");

    if (settings.showLogo !== false) {
        if (!logo.innerHTML) logo.innerHTML = IFRUIT_IMG;
        logo.style.left = d.anchor.x * w + 10 + "px";
        logo.style.top = d.anchor.y * h + 8 + "px";
        logo.classList.remove("hidden");
    } else {
        logo.classList.add("hidden");
    }

    // default status spot sits just above the minimap (unless custom layout)
    if (!(settings.layout && settings.layout.status)) {
        const status = el("status");
        status.style.left = d.anchor.x * w + "px";
        status.style.bottom = (1 - d.anchor.y) * h + 10 + "px";
        status.style.top = "auto";
    }
};

/* ── money ───────────────────────────────────────────────────────── */
const fmt = new Intl.NumberFormat("en-US");

const pushMoneyPill = (icon, amountText, deltaText, deltaClass) => {
    const wrap = el("money");
    const pill = document.createElement("div");
    pill.className = "money-pill boxed";
    pill.innerHTML = `
        <span class="material-icons-round">${icon}</span>
        <span class="money-amount">${amountText}</span>
        ${deltaText ? `<span class="money-delta ${deltaClass}">${deltaText}</span>` : ""}`;
    wrap.appendChild(pill);
    applyBoxes();
    if (!(settings.boxes && settings.boxes.money === false)) pill.classList.remove("no-box");
    setTimeout(() => {
        pill.classList.add("out");
        setTimeout(() => pill.remove(), 350);
    }, 3500);
};

const onMoney = (d) => {
    const icon = d.type === "bank" ? "account_balance" : "payments";
    const balance = d.type === "bank" ? d.bank : d.cash;
    const amountText = balance != null ? currency + fmt.format(balance) : "";
    const deltaText = (d.minus ? "-" : "+") + currency + fmt.format(d.amount);
    pushMoneyPill(icon, amountText, deltaText, d.minus ? "minus" : "plus");
};

const onAccount = (d) => {
    const icon = d.account === "bank" ? "account_balance" : "payments";
    pushMoneyPill(icon, currency + fmt.format(d.amount), null, null);
};

/* ── cinematic ───────────────────────────────────────────────────── */
const setCinematic = (active) => {
    el("cine-top").classList.toggle("cine-active", active);
    el("cine-bottom").classList.toggle("cine-active", active);
};

/* ── layout edit mode ────────────────────────────────────────────── */
let dragState = null;

const enterEditMode = () => {
    editMode = true;
    el("menu-backdrop").classList.add("hidden");
    post("editMode");
    document.body.classList.add("editing");
    el("edit-bar").classList.remove("hidden");

    updateStatus({ show: true, health: 76, armor: 45, hunger: 80, thirst: 65, stress: 30, oxygen: 100 });
    updateVehicle({ show: true, speed: 88, unit: settings.speedUnit, fuel: 60, lowFuel: false, engine: 40, seatbelt: true, nitroActive: false, nitro: 55 });
    updateCompass({ show: true, direction: "NW", heading: 312, street: "Vespucci Blvd" });
    pushMoneyPill("payments", currency + "3,200", "+" + currency + "750", "plus");

    for (const k of CLUSTERS) {
        const node = el(k);
        node.classList.add("editable");
        node.dataset.cluster = k;
    }
};

const exitEditMode = (save) => {
    editMode = false;
    document.body.classList.remove("editing");
    el("edit-bar").classList.add("hidden");
    for (const k of CLUSTERS) el(k).classList.remove("editable");
    if (save) post("saveSettings", settings);
    post("closeMenu");
    applyLayout();
    updateMinimapFrame();
};

document.addEventListener("pointerdown", (e) => {
    if (!editMode) return;
    const target = e.target.closest(".editable");
    if (!target) return;
    const rect = target.getBoundingClientRect();
    dragState = { k: target.dataset.cluster, node: target, dx: e.clientX - rect.left, dy: e.clientY - rect.top };
    e.preventDefault();
});

document.addEventListener("pointermove", (e) => {
    if (!editMode || !dragState) return;
    const x = ((e.clientX - dragState.dx) / window.innerWidth) * 100;
    const y = ((e.clientY - dragState.dy) / window.innerHeight) * 100;
    if (!settings.layout) settings.layout = {};
    const prev = settings.layout[dragState.k] || { scale: 1 };
    settings.layout[dragState.k] = { x: Math.max(0, Math.min(97, x)), y: Math.max(0, Math.min(97, y)), scale: prev.scale || 1 };
    applyLayout();
});

document.addEventListener("pointerup", () => (dragState = null));

document.addEventListener("wheel", (e) => {
    if (!editMode) return;
    const target = e.target.closest(".editable");
    if (!target) return;
    const k = target.dataset.cluster;
    if (!settings.layout) settings.layout = {};
    const pos = settings.layout[k] || { x: null, y: null, scale: 1 };
    pos.scale = Math.max(0.6, Math.min(1.8, (pos.scale || 1) + (e.deltaY < 0 ? 0.05 : -0.05)));
    if (pos.x == null) {
        const rect = target.getBoundingClientRect();
        pos.x = (rect.left / window.innerWidth) * 100;
        pos.y = (rect.top / window.innerHeight) * 100;
    }
    settings.layout[k] = pos;
    applyLayout();
});

/* ── settings menu ───────────────────────────────────────────────── */
let draft = null;

const segment = (obj, key, options, labels) => {
    const wrap = document.createElement("div");
    wrap.className = "segment";
    options.forEach((opt, i) => {
        const b = document.createElement("button");
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
};

const toggle = (obj, key) => {
    const s = document.createElement("div");
    s.className = "switch" + (obj[key] !== false ? " on" : "");
    s.addEventListener("click", () => {
        obj[key] = obj[key] === false;
        s.classList.toggle("on", obj[key] !== false);
    });
    return s;
};

const toggleStrict = (obj, key) => {
    const s = document.createElement("div");
    s.className = "switch" + (obj[key] ? " on" : "");
    s.addEventListener("click", () => {
        obj[key] = !obj[key];
        s.classList.toggle("on", obj[key]);
    });
    return s;
};

const colorInput = (obj, key) => {
    const i = document.createElement("input");
    i.type = "color";
    i.className = "color-pick";
    i.value = obj[key];
    i.addEventListener("input", () => (obj[key] = i.value));
    return i;
};

const row = (label, control) => {
    const r = document.createElement("div");
    r.className = "menu-row";
    const span = document.createElement("span");
    span.textContent = label;
    r.appendChild(span);
    r.appendChild(control);
    return r;
};

const section = (label) => {
    const s = document.createElement("div");
    s.className = "menu-section";
    s.textContent = label;
    return s;
};

const buildMenu = () => {
    draft = JSON.parse(JSON.stringify(settings));
    if (!draft.theme) draft.theme = { ...DEFAULT_THEME };
    if (!draft.boxes) draft.boxes = { ...DEFAULT_BOXES };
    const body = el("menu-body");
    body.innerHTML = "";

    body.appendChild(section("Theme — applies to all interfaces"));
    body.appendChild(row("Accent", colorInput(draft.theme, "accent")));
    body.appendChild(row("Panel color", colorInput(draft.theme, "primary")));
    body.appendChild(row("Fields / rows", colorInput(draft.theme, "secondary")));
    body.appendChild(row("Text color", colorInput(draft.theme, "text")));
    const op = document.createElement("input");
    op.type = "range"; op.min = "0.5"; op.max = "1"; op.step = "0.02"; op.value = draft.theme.opacity;
    op.addEventListener("input", () => (draft.theme.opacity = parseFloat(op.value)));
    body.appendChild(row("Panel opacity", op));
    const resetTheme = document.createElement("button");
    resetTheme.className = "menu-mini-btn";
    resetTheme.textContent = "Reset theme";
    resetTheme.addEventListener("click", () => {
        draft.theme = { ...DEFAULT_THEME };
        buildMenuKeepScroll();
    });
    body.appendChild(row("", resetTheme));

    body.appendChild(section("Appearance"));
    body.appendChild(row("HUD style", segment(draft, "hudStyle", ["rings", "bars", "minimal"], ["Rings", "Bars", "Minimal"])));
    const slider = document.createElement("input");
    slider.type = "range"; slider.min = "0.8"; slider.max = "1.3"; slider.step = "0.05"; slider.value = draft.scale;
    slider.addEventListener("input", () => (draft.scale = parseFloat(slider.value)));
    body.appendChild(row("HUD scale", slider));
    body.appendChild(row("Fade full statuses", toggleStrict(draft, "idleFade")));

    body.appendChild(section("Backgrounds — per element"));
    body.appendChild(row("Speedometer box", toggle(draft.boxes, "speedo")));
    body.appendChild(row("Status box (bars style)", toggle(draft.boxes, "status")));
    body.appendChild(row("Compass box", toggle(draft.boxes, "compass")));
    body.appendChild(row("Vehicle icon boxes", toggle(draft.boxes, "icons")));
    body.appendChild(row("Money box", toggle(draft.boxes, "money")));

    body.appendChild(section("Layout"));
    const editBtn = document.createElement("button");
    editBtn.className = "menu-mini-btn";
    editBtn.textContent = "Edit layout (drag + scroll)";
    editBtn.addEventListener("click", () => {
        settings = draft;
        applyTheme();
        applyBoxes();
        buildStatus();
        enterEditMode();
    });
    body.appendChild(row("Move & resize", editBtn));
    const resetBtn = document.createElement("button");
    resetBtn.className = "menu-mini-btn";
    resetBtn.textContent = "Reset positions";
    resetBtn.addEventListener("click", () => {
        draft.layout = { status: null, speedo: null, vehicleIcons: null, nitro: null, compass: null, money: null };
    });
    body.appendChild(row("", resetBtn));

    body.appendChild(section("Minimap"));
    body.appendChild(row("Shape", segment(draft, "minimapShape", ["rounded", "square", "circle"], ["Rounded", "Square", "Circle"])));
    body.appendChild(row("Show on foot", toggleStrict(draft, "minimapOnFoot")));
    body.appendChild(row("iFruit logo", toggle(draft, "showLogo")));

    body.appendChild(section("Compass"));
    body.appendChild(row("Show compass", toggleStrict(draft, "showCompass")));
    body.appendChild(row("Compass on foot", toggleStrict(draft, "compassOnFoot")));
    body.appendChild(row("Street names", toggleStrict(draft, "showStreets")));

    body.appendChild(section("Vehicle"));
    body.appendChild(row("Speed unit", segment(draft, "speedUnit", ["mph", "kmh"], ["MPH", "KM/H"])));

    body.appendChild(section("Other"));
    body.appendChild(row("Money popups", toggleStrict(draft, "showMoney")));
    body.appendChild(row("Cinematic mode", toggleStrict(draft, "cinematicMode")));
};

const buildMenuKeepScroll = () => {
    const scroll = el("menu-body").scrollTop;
    const d = draft;
    buildMenu();
    draft = d;
    el("menu-body").scrollTop = scroll;
};

const openMenu = () => {
    buildMenu();
    el("menu-backdrop").classList.remove("hidden");
};

const closeMenu = () => {
    el("menu-backdrop").classList.add("hidden");
    post("closeMenu");
};

el("menu-close").addEventListener("click", closeMenu);
el("menu-save").addEventListener("click", () => {
    settings = draft;
    applyTheme();
    applyBoxes();
    buildStatus();
    applyLayout();
    updateMinimapFrame();
    post("saveSettings", settings);
    el("menu-backdrop").classList.add("hidden");
    post("closeMenu");
});

el("edit-done").addEventListener("click", () => exitEditMode(true));
el("edit-cancel").addEventListener("click", () => exitEditMode(false));

document.addEventListener("keyup", (e) => {
    if (e.key !== "Escape") return;
    if (editMode) return exitEditMode(true);
    if (!el("menu-backdrop").classList.contains("hidden")) closeMenu();
});

/* ── message router ──────────────────────────────────────────────── */
window.addEventListener("message", (event) => {
    const d = event.data;
    switch (d.action) {
        case "status": return updateStatus(d);
        case "vehicle": return updateVehicle(d);
        case "compass": return updateCompass(d);
        case "minimap": return updateMinimapFrame(d);
        case "money": return settings.showMoney && onMoney(d);
        case "account": return settings.showMoney && onAccount(d);
        case "cinematic": return setCinematic(d.active);
        case "openMenu":
            if (d.settings) { settings = { ...settings, ...d.settings }; applyTheme(); applyBoxes(); }
            return openMenu();
        case "settings":
            if (d.settings) settings = { ...settings, ...d.settings };
            if (d.currency) currency = d.currency;
            applyTheme();
            applyBoxes();
            buildStatus();
            applyLayout();
            updateMinimapFrame();
            return;
    }
});

window.addEventListener("resize", () => updateMinimapFrame());

applyTheme();
applyBoxes();
buildStatus();
