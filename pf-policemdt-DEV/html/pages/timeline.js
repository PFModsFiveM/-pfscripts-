// Telemetry timeline (batch 21, unit 21B).
//
// An officer's bodycam / dashcam timeline as pfm-policejob records it (18C): positions, weapon
// drawn, vehicle in/out, radio, and actions the server saw (cuff, taser, shots ...). FiveM has no
// video: this is metadata, not video, and the page says so on every view. Rows marked
// "client reported" rest on a client's report (casings, drone) and are shown apart.
// pf_mdt:timeline:get (server/pages_ext.lua -> GetTimeline with the caller as viewer): an officer
// reads their own timeline; a supervisor reads another officer's (pfm-policejob decides). Pages of
// 100 rows; "Load more" follows the server's cursor. Every server string goes in as text (ctx.h).
(function () {
    'use strict';

    const WINDOWS = [[15, 'last 15 minutes'], [30, 'last 30 minutes'], [60, 'last hour'], [120, 'last 2 hours'], [360, 'last 6 hours']];
    const KIND_TEXT = {
        pos: 'position', weapon_out: 'weapon drawn', weapon_in: 'weapon holstered', shot_hit: 'shot hit (server seen)',
        shot_reported: 'shot reported', cuff: 'cuffed', search: 'searched', frisk: 'frisked', taser: 'taser', vehicle_in: 'entered vehicle',
        vehicle_out: 'left vehicle', radio: 'radio channel', note: 'note', anomaly: 'anomaly', detain: 'detained', escort: 'escort',
        arrest: 'arrest', ziptie: 'zip-tied', release: 'released', use_of_force: 'use of force', k9: 'K9', drone: 'drone',
    };
    const FORCE = { shot_hit: 'bad', taser: 'warn', use_of_force: 'warn', cuff: '', ziptie: '', weapon_out: 'warn' };

    function pad(n) { return String(n).padStart(2, '0'); }
    function localInput(sec) {
        const d = new Date(sec * 1000);
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    // data = { action = 'tackle', weapon = 'WEAPON_PISTOL', target = 'ABC' } -> "action tackle, weapon WEAPON_PISTOL, target ABC"
    function dataText(d) {
        if (!d || typeof d !== 'object') return d == null ? '' : String(d);
        return Object.keys(d).slice(0, 8).map((k) => `${k} ${typeof d[k] === 'object' ? JSON.stringify(d[k]) : d[k]}`).join(', ');
    }

    function make(ctx) {
        const el = (tag, attrs, ...kids) => ctx.h(tag, attrs || {}, ...kids.flat().filter((k) => k !== null && k !== undefined && k !== false));
        const badge = (text, t) => el('span', { class: `pfp-badge ${t || ''}`.trim(), text });
        return { el, badge };
    }

    const page = {
        title: 'Telemetry Timeline',
        label: 'Telemetry',
        section: 'department',
        order: 30,
        icon: ['M3 12h4l3-8 4 16 3-8h4'],

        async render(root, ctx) {
            const { el, badge } = make(ctx);
            let query = null;
            let cursor = null;
            let shown = 0;

            const officerIn = el('input', { class: 'pfp-input', type: 'text', maxlength: '32', placeholder: 'Officer citizen id (blank = me)', 'aria-label': 'Officer citizen id' });
            const winIn = el('select', { class: 'pfp-select', 'aria-label': 'Window' },
                WINDOWS.map(([m, t]) => el('option', { value: String(m), text: t })), el('option', { value: 'custom', text: 'from a start time' }));
            const fromIn = el('input', { class: 'pfp-input', type: 'datetime-local', 'aria-label': 'Start' });
            const lenIn = el('select', { class: 'pfp-select', 'aria-label': 'Length' }, [15, 30, 60, 120, 360].map((m) => el('option', { value: String(m), text: `${m} min` })));
            fromIn.value = localInput(Math.floor(Date.now() / 1000) - 3600);
            fromIn.hidden = true;
            lenIn.hidden = true;
            winIn.value = '30';
            winIn.addEventListener('change', () => { const c = winIn.value === 'custom'; fromIn.hidden = !c; lenIn.hidden = !c; });
            const info = el('div', { class: 'pfx-sub' });
            const listBox = el('div', { class: 'pfx-listbox' });
            const more = el('button', { class: 'pfp-btn', type: 'button', text: 'Load more', onClick: () => load(true) });
            more.hidden = true;
            const draftBtn = el('button', { class: 'pfp-btn', type: 'button', text: 'Draft a use-of-force report from this window', onClick: () => {
                if (query) ctx.open('uof', { draft: { from: query.from, to: query.to, officerCid: query.officerCid || null } });
            } });
            draftBtn.hidden = true;

            root.appendChild(el('div', { class: 'pfx-page pfx-timeline' },
                el('div', { class: 'pfx-head' }, el('h2', { text: 'Telemetry timeline' }),
                    el('div', { class: 'pfx-banner', role: 'note', text: 'Metadata, not video. FiveM records no pictures: these are the positions and actions the server itself saw while a bodycam or dashcam was recording.' })),
                el('form', { class: 'pfp-toolbar', onSubmit: (e) => { e.preventDefault(); load(false); } },
                    officerIn, winIn, fromIn, lenIn, el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Read' })),
                info, listBox, el('div', { class: 'pfp-toolbar' }, more, draftBtn)));

            const access = await ctx.call('pf_mdt:pages:access', {});
            if (!ctx.alive()) return;
            // reading another officer's timeline is for supervisors; pfm-policejob refuses it otherwise
            if (!(access && access.ok && access.can && access.can.timelineOthers)) officerIn.hidden = true;

            function windowNow() {
                const now = Math.floor(Date.now() / 1000);
                if (winIn.value !== 'custom') return { from: now - Number(winIn.value) * 60, to: now };
                const start = Math.floor(new Date(fromIn.value).getTime() / 1000);
                if (!Number.isFinite(start)) return null;
                return { from: start, to: Math.min(now, start + Number(lenIn.value) * 60) };
            }

            async function load(append) {
                if (!append) {
                    const w = windowNow();
                    if (!w || w.to <= w.from) { ctx.toast('Pick a start time in the past', 'error'); return; }
                    query = { from: w.from, to: w.to, officerCid: officerIn.hidden ? '' : officerIn.value.trim() };
                    cursor = null;
                    shown = 0;
                    listBox.textContent = '';
                    info.textContent = '';
                    draftBtn.hidden = true;
                    ctx.state(listBox, 'loading', 'Reading the timeline...');
                }
                const payload = { from: query.from, to: query.to };
                if (query.officerCid) payload.officerCid = query.officerCid;
                if (append && cursor) payload.after = cursor;
                more.disabled = true;
                const res = await ctx.call('pf_mdt:timeline:get', payload);
                if (!ctx.alive()) return;
                more.disabled = false;
                if (!append) listBox.textContent = '';
                if (!res || !res.ok) {
                    if (append) ctx.toast(ctx.errorText(res, 'The timeline could not be read'), 'error');
                    else ctx.state(listBox, 'error', ctx.errorText(res, 'The timeline could not be read'));
                    return;
                }
                if (!append) {
                    info.appendChild(el('span', { class: 'pfp-muted', text: `${res.officerCid || 'me'}: ${ctx.time(res.from)} to ${ctx.time(res.to)}. ${res.note || ''}` }));
                }
                const rows = Array.isArray(res.events) ? res.events : [];
                if (!append && !rows.length) ctx.state(listBox, 'empty', 'No telemetry in this window (no bodycam or dashcam was recording)');
                let body = listBox.querySelector('tbody');
                if (!body && rows.length) {
                    const t = el('table', { class: 'pfp-table' },
                        el('thead', {}, el('tr', {}, ['Time', 'Source', 'Event', 'Details', 'Position'].map((h) => el('th', { scope: 'col', text: h })))),
                        el('tbody', {}));
                    listBox.appendChild(el('div', { class: 'pfx-table-wrap' }, t));
                    body = t.querySelector('tbody');
                }
                rows.forEach((r) => {
                    const c = r.coords;
                    body.appendChild(el('tr', { class: r.clientReported ? 'pfx-client' : '' },
                        el('td', { text: ctx.time(r.at) }), el('td', { text: r.device === 'dash' ? 'dashcam' : (r.device === 'body' ? 'bodycam' : String(r.device || '')) }),
                        el('td', {}, badge(KIND_TEXT[r.kind] || String(r.kind || ''), FORCE[r.kind] || ''), r.clientReported ? badge('client reported', 'warn') : null),
                        el('td', { text: dataText(r.data) }),
                        el('td', { text: c ? `${Math.round(c.x)}, ${Math.round(c.y)}, ${Math.round(c.z)}` : '' })));
                });
                shown += rows.length;
                cursor = res.next || null;
                more.hidden = !cursor;
                draftBtn.hidden = shown === 0;
            }
        },
    };

    if (window.PFMdtPages && typeof window.PFMdtPages.register === 'function') window.PFMdtPages.register('timeline', page);
    window.PFMdtExtPages = window.PFMdtExtPages || {};
    window.PFMdtExtPages.timeline = page;
})();
