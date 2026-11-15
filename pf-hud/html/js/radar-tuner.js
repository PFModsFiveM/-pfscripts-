/* Copyright (c) 2026 Whippy, from WHIP, LGPL-3.0; modified for PF.
 * Port of whip_core/html/js/radar-debug.js (the UI half of the radar tuner, /radartuner here), as a classic script on
 * PfHud's router. Free software under the GNU Lesser General Public License 3.0 (pf-hud/COPYING.LESSER and COPYING).
 *
 * A slider and an editable number for every value the minimap exposes, each change posted straight to the client
 * (client/radar_tuner.lua, which clamps them). PF: a Save button (this player's tuning, kept), and the controller works
 * through pfm-ui's pad.js (D-pad moves between controls, left/right moves a slider, B closes). */
(function (root) {
    "use strict";
    const doc = root.document;
    const PfHud = root.PfHud;
    const rootEl = doc.getElementById("radar-tuner");
    const bodyEl = doc.getElementById("rd-body");
    const optsEl = doc.getElementById("rd-opts");
    if (!rootEl) return;

    let state = { components: [], opts: {} };

    const RANGE = {
        posX:   { min: -1.0, max: 1.0, step: 0.0005 },
        posY:   { min: -1.0, max: 1.0, step: 0.0005 },
        sizeX:  { min: 0.01, max: 1.5, step: 0.0005 },
        sizeY:  { min: 0.01, max: 1.5, step: 0.0005 },
        corner: { min: 0.0, max: 3.0, step: 0.01 },
    };
    const ALIGN_X = ["L", "R", "C", "I"];
    const ALIGN_Y = ["T", "B", "C", "I"];

    const rgb = (c) => (Array.isArray(c) ? `rgb(${c[0] | 0},${c[1] | 0},${c[2] | 0})` : "rgba(255,255,255,0.4)");
    const clamp = (v, r) => Math.max(r.min, Math.min(r.max, v));

    function push(comp, rebuild) {
        PfHud.post("radarTunerSet", {
            key: comp.key, posX: comp.posX, posY: comp.posY, sizeX: comp.sizeX, sizeY: comp.sizeY,
            alignX: comp.alignX, alignY: comp.alignY, corner: comp.corner, rebuild: rebuild !== false,
        });
    }

    function fieldRow(comp, field) {
        const r = RANGE[field];
        const row = doc.createElement("div");
        row.className = "rd-row";
        const label = doc.createElement("label");
        label.textContent = field;
        row.appendChild(label);
        const slider = doc.createElement("input");
        slider.type = "range";
        slider.min = r.min; slider.max = r.max; slider.step = r.step;
        slider.value = comp[field];
        row.appendChild(slider);
        const num = doc.createElement("input");
        num.type = "number";
        num.step = r.step;
        num.value = Number(comp[field]).toFixed(4);
        row.appendChild(num);
        // `input` streams values without a rebuild; `change` (released) rebuilds
        slider.addEventListener("input", () => {
            comp[field] = parseFloat(slider.value);
            num.value = comp[field].toFixed(4);
            push(comp, false);
        });
        slider.addEventListener("change", () => push(comp, true));
        num.addEventListener("change", () => {
            const v = parseFloat(num.value);
            if (Number.isNaN(v)) { num.value = Number(comp[field]).toFixed(4); return; }
            comp[field] = clamp(v, r);   // the client clamps too
            num.value = comp[field].toFixed(4);
            slider.value = comp[field];
            push(comp, true);
        });
        return row;
    }

    function alignRow(comp) {
        const wrap = doc.createElement("div");
        wrap.className = "rd-aligns";
        [["alignX", ALIGN_X], ["alignY", ALIGN_Y]].forEach(([field, options]) => {
            const sel = doc.createElement("select");
            options.forEach((o) => {
                const opt = doc.createElement("option");
                opt.value = o;
                opt.textContent = `${field === "alignX" ? "X" : "Y"}: ${o}`;
                if (comp[field] === o) opt.selected = true;
                sel.appendChild(opt);
            });
            sel.addEventListener("change", () => { comp[field] = sel.value; push(comp, true); });
            wrap.appendChild(sel);
        });
        return wrap;
    }

    function componentCard(comp) {
        const card = doc.createElement("div");
        card.className = "rd-comp" + (comp.managed ? "" : " rd-extra");
        const head = doc.createElement("div");
        head.className = "rd-comp-head";
        const swatch = doc.createElement("span");
        swatch.className = "rd-swatch";
        swatch.style.background = rgb(comp.colour);
        head.appendChild(swatch);
        const name = doc.createElement("span");
        name.className = "rd-comp-name";
        name.textContent = comp.label;
        head.appendChild(name);
        const outline = doc.createElement("button");
        outline.type = "button";
        outline.className = "rd-toggle" + (comp.outline ? " on" : "");
        outline.textContent = "box";
        outline.addEventListener("click", () => {
            comp.outline = !comp.outline;
            outline.classList.toggle("on", comp.outline);
            PfHud.post("radarTunerOutline", { key: comp.key, on: comp.outline });
        });
        head.appendChild(outline);
        card.appendChild(head);
        if (comp.note) {
            const note = doc.createElement("p");
            note.className = "rd-note";
            note.textContent = comp.note;
            card.appendChild(note);
        }
        (Array.isArray(comp.fields) ? comp.fields : ["posX", "posY", "sizeX", "sizeY"])
            .filter((f) => RANGE[f]).forEach((f) => card.appendChild(fieldRow(comp, f)));
        if (!comp.noAlign) card.appendChild(alignRow(comp));
        return card;
    }

    function optToggle(labelText, name, isOn, valueWhenOn, valueWhenOff) {
        const b = doc.createElement("button");
        b.type = "button";
        b.className = "rd-toggle" + (isOn ? " on" : "");
        b.textContent = labelText;
        b.addEventListener("click", () => {
            const nowOn = !b.classList.contains("on");
            b.classList.toggle("on", nowOn);
            PfHud.post("radarTunerOpt", { name, value: nowOn ? valueWhenOn : valueWhenOff });
        });
        return b;
    }

    function buildOpts(o) {
        optsEl.innerHTML = "";
        optsEl.appendChild(optToggle("outlines", "showOutlines", o.showOutlines !== false, true, false));
        optsEl.appendChild(optToggle("bigmap", "bigmapOn", !!o.bigmapOn, true, false));
        optsEl.appendChild(optToggle("hide bars", "hideBars", o.hideBars !== false, true, false));
        optsEl.appendChild(optToggle("frame over the HUD", "frameOver", !!o.frameOver, true, false));
        const SHAPES = ["rounded", "square", "circle", false];
        const shapeBtn = doc.createElement("button");
        shapeBtn.type = "button";
        shapeBtn.className = "rd-toggle on";
        const shapeLabel = (v) => "mask: " + (v ? v : "game");
        shapeBtn.textContent = shapeLabel(o.maskShape);
        shapeBtn.addEventListener("click", () => {
            const i = SHAPES.indexOf(state.opts.maskShape);
            const next = SHAPES[(i + 1) % SHAPES.length];
            state.opts.maskShape = next;
            shapeBtn.textContent = shapeLabel(next);
            PfHud.post("radarTunerOpt", { name: "maskShape", value: next });
        });
        optsEl.appendChild(shapeBtn);
        [["radarZoom", "zoom", 0, 1400, 10], ["clipType", "clip", -1, 3, 1]].forEach(([name, label, min, max, step]) => {
            const row = doc.createElement("div");
            row.className = "rd-row";
            row.style.gridColumn = "1 / -1";
            row.style.width = "100%";
            const l = doc.createElement("label");
            l.textContent = label;
            row.appendChild(l);
            const s = doc.createElement("input");
            s.type = "range"; s.min = min; s.max = max; s.step = step;
            s.value = o[name] !== undefined ? o[name] : min;
            row.appendChild(s);
            const n = doc.createElement("input");
            n.type = "number"; n.step = step;
            n.value = s.value;
            row.appendChild(n);
            const send = (v) => {
                v = Math.max(min, Math.min(max, v));
                state.opts[name] = v;
                PfHud.post("radarTunerOpt", { name, value: v });
            };
            s.addEventListener("input", () => { n.value = s.value; });
            s.addEventListener("change", () => send(parseFloat(s.value)));
            n.addEventListener("change", () => { s.value = n.value; send(parseFloat(n.value)); });
            optsEl.appendChild(row);
        });
    }

    function render(data) {
        state = data && typeof data === "object" ? data : { components: [], opts: {} };
        if (!state.opts) state.opts = {};
        buildOpts(state.opts);
        bodyEl.innerHTML = "";
        (Array.isArray(state.components) ? state.components : []).forEach((c) => bodyEl.appendChild(componentCard(c)));
    }

    function open(data) {
        render(data);
        rootEl.classList.remove("rd-hidden");
        if (root.PfmPad) root.PfmPad.focusables(rootEl.querySelector(".rd-panel"), { onBack: closeAndTell, autoFocus: true });
    }

    function close() {
        rootEl.classList.add("rd-hidden");
        if (root.PfmPad) root.PfmPad.clear();
    }

    function closeAndTell() {
        close();
        PfHud.post("radarTunerClose", {});
    }

    doc.getElementById("rd-close").addEventListener("click", closeAndTell);
    doc.getElementById("rd-save").addEventListener("click", () => PfHud.post("radarTunerSave", {}));
    doc.getElementById("rd-print").addEventListener("click", () => PfHud.post("radarTunerPrint", {}));
    // back to the shipped values (and the saved tuning forgotten), the point a session started from
    doc.getElementById("rd-reset").addEventListener("click", () => PfHud.post("radarTunerReset", { mode: "forget" }));
    // GTA's own frontend.xml values: a diagnostic
    doc.getElementById("rd-vanilla").addEventListener("click", () => PfHud.post("radarTunerReset", { mode: "stock" }));

    doc.addEventListener("keydown", (e) => {
        if (e.key === "Escape" && !rootEl.classList.contains("rd-hidden")) closeAndTell();
    });

    PfHud.on("radarTunerOpen", (d) => open(d.data));
    PfHud.on("radarTunerClose", () => close());

    root.PfHudTuner = { open, close, state: () => state };
})(window);
