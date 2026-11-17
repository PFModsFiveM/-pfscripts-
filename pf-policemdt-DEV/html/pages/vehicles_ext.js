// Plate check, ALPR history, plate flags and the impound lot (batch 21A).
// Server: pfm-policejob police:server:runPlate (owner, licence, MDT + field flags, BOLOs, open impound
// record) and police:GetImpoundedVehicles (cars in the police impound with their impound record);
// this resource's pf_mdt:getVehicleProfile (activity: ALPR reads and hits, flag and BOLO changes),
// pf_mdt:vehicles:setFlag | clearFlag and pf_mdt:audit:list. A seized car is released at the impound
// lot (the server checks the officer stands there), so this page shows the hold, not a release button.
(function () {
    'use strict';
    if (!window.PFMdtPages) return;

    const ACTIVITY_TEXT = { alpr_hit: 'ALPR hit', alpr_read: 'ALPR read', flag_set: 'Flag set', flag_cleared: 'Flag cleared', bolo: 'BOLO',
        bolo_cleared: 'BOLO cleared', strike: 'Strike', impound: 'Impound', traffic_stop: 'Traffic stop', citation: 'Citation' };
    const IMPOUND_KIND = { depot: 'Depot', impound: 'Impound', seizure: 'Seizure' };
    let state = null;

    function render(root, ctx) {
        const { h, ui } = ctx;
        state = { ctx, tab: 'plate', impounds: null, filter: '' };
        state.body = h('div', { class: 'pfp-card' });
        state.bar = h('div', { class: 'pfp-tabs', role: 'tablist' });
        root.appendChild(h('div', { class: 'pfp-head' },
            h('div', null, h('h2', null, 'Plates and impound'), h('div', { class: 'pfp-sub' }, 'Plate check, ALPR history, flags and the impound lot'))));
        root.appendChild(state.bar);
        root.appendChild(state.body);
        drawTabs();
        if (ctx.params && ctx.params.plate) runPlate(String(ctx.params.plate));
        else drawPlateTab();
    }

    function drawTabs() {
        const s = state;
        const { h } = s.ctx;
        s.bar.textContent = '';
        for (const [k, l] of [['plate', 'Plate check'], ['impound', 'Impound lot']]) {
            s.bar.appendChild(h('button', { type: 'button', class: 'pfp-tab' + (s.tab === k ? ' active' : ''), role: 'tab', 'aria-selected': s.tab === k ? 'true' : 'false', dataset: { tab: k },
                onClick: () => { s.tab = k; drawTabs(); if (k === 'plate') drawPlateTab(); else drawImpoundTab(); } }, l));
        }
    }

    function drawPlateTab(result) {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        s.body.textContent = '';
        const plate = ui.input({ placeholder: 'Plate', maxlength: 8, 'aria-label': 'Plate', value: (result && result.plate) || '' });
        plate.addEventListener('keydown', (e) => { if (e.key === 'Enter') runPlate(plate.value); });
        s.body.appendChild(h('div', { class: 'pfp-toolbar' }, plate, ui.btn('Run plate', 'primary', () => runPlate(plate.value))));
        s.resultEl = h('div', { 'aria-live': 'polite' });
        s.body.appendChild(s.resultEl);
        if (!result) ctx.state(s.resultEl, 'empty', 'Run a plate to see its owner, flags, BOLOs, impound record and ALPR history.');
        plate.focus();
    }

    async function runPlate(raw) {
        const s = state;
        const { ctx } = s;
        const plateText = String(raw || '').trim().toUpperCase();
        if (s.tab !== 'plate') { s.tab = 'plate'; drawTabs(); }
        drawPlateTab({ plate: plateText });
        if (!plateText) { ctx.state(s.resultEl, 'error', 'Type a plate.'); return; }
        ctx.state(s.resultEl, 'loading', 'Checking the plate...');
        const [check, profile] = await Promise.all([
            ctx.call('police:server:runPlate', plateText),
            ctx.call('pf_mdt:getVehicleProfile', { plate: plateText }),
        ]);
        if (!ctx.alive() || state !== s) return;
        drawResult(plateText, check, profile);
    }

    function drawResult(plate, check, profile) {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        const el = s.resultEl;
        el.textContent = '';
        if (!check.ok) el.appendChild(h('div', { class: 'pfp-state pfp-state-error' }, `Plate check: ${ctx.errorText(check)}`));
        else {
            const o = check.owner;
            const lic = o && o.licence ? `${o.licence.driver}${o.licence.government === true ? ' (state licence held)' : (o.licence.government === false ? ' (no state licence)' : '')}` : '';
            el.appendChild(h('h3', null, check.plate || plate));
            el.appendChild(ui.kv([
                ['Owner', o ? h('button', { type: 'button', class: 'pfp-link', onClick: () => { try { router.openCitizenProfile(o.citizenid); } catch (_) {} } }, `${o.name || 'unknown'} (${o.citizenid})`) : 'No registered owner'],
                ['Model', check.model || ''], ['Driver licence', lic]]));
            const flags = h('div', { class: 'pfp-toolbar' });
            for (const f of Array.isArray(check.flags) ? check.flags : []) flags.appendChild(ui.badge(String(f), f === 'STOLEN' || f === 'DANGEROUS' ? 'bad' : 'warn'));
            if (check.fieldFlag) flags.appendChild(ui.badge(`Field: ${check.fieldFlag}`, 'warn'));
            if (!flags.childNodes.length) flags.appendChild(check.flagsUnavailable ? ui.badge('MDT flags unavailable right now', 'bad') : ui.badge('No flags', 'ok'));
            el.appendChild(h('h4', null, 'Flags'));
            el.appendChild(flags);
            const bolos = Array.isArray(check.bolos) ? check.bolos : [];
            if (bolos.length) {
                el.appendChild(h('h4', null, 'Active BOLOs'));
                el.appendChild(h('div', { class: 'pfp-toolbar' }, bolos.map((id) => h('button', { type: 'button', class: 'pfp-link', onClick: () => ctx.open('bolos', { boloId: Number(id) }) }, `BOLO #${id}`))));
            }
            if (check.impound) {
                const imp = check.impound;
                el.appendChild(h('h4', null, 'Impound'));
                el.appendChild(ui.kv([['Kind', IMPOUND_KIND[imp.kind] || imp.kind], ['State', imp.state], ['Reason', imp.reason],
                    ['Held until', imp.holdUntil ? ctx.time(imp.holdUntil) : ''], ['Case', imp.caseRef], ['Since', imp.createdAt ? ctx.time(imp.createdAt) : '']]));
            }
        }
        // flags (this MDT's list) and the BOLO shortcut
        const err = ui.formError();
        const flagsCfg = (window.mdtConfig && Array.isArray(window.mdtConfig.vehicleFlags) && window.mdtConfig.vehicleFlags.length)
            ? window.mdtConfig.vehicleFlags : ['BOLO', 'DANGEROUS', 'STOLEN', 'IMPOUNDED', 'SEIZED'];
        const tools = h('div', { class: 'pfp-toolbar' });
        if (ctx.can('vehicleRecords')) {
            const sel = ui.select([['', 'Set flag...']].concat(flagsCfg.map((f) => [String(f), String(f)])), '', { 'aria-label': 'Flag' });
            tools.appendChild(sel);
            tools.appendChild(ui.btn('Set flag', 'sm', async () => {
                if (!sel.value) return;
                const r = await ctx.call('pf_mdt:vehicles:setFlag', { plate, flag: sel.value });
                if (!ctx.alive()) return;
                if (!r.ok) { err.textContent = ctx.errorText(r); return; }
                ctx.toast(`${plate}: ${sel.value}`, 'success');
                runPlate(plate);
            }));
            tools.appendChild(ui.btn('Clear flag', 'sm ghost', async () => {
                const r = await ctx.call('pf_mdt:vehicles:clearFlag', { plate });
                if (!ctx.alive()) return;
                if (!r.ok) { err.textContent = ctx.errorText(r); return; }
                ctx.toast(`${plate}: flag cleared`, 'success');
                runPlate(plate);
            }));
        }
        if (ctx.can('bolos')) tools.appendChild(ui.btn('New BOLO for this plate', 'sm ghost', () => ctx.open('bolos', { create: { plate } })));
        if (ctx.can('viewAudit')) tools.appendChild(ui.btn('Record audit', 'sm ghost', () => showAudit(plate)));
        el.appendChild(tools);
        el.appendChild(err);
        s.auditEl = h('div');
        el.appendChild(s.auditEl);

        el.appendChild(h('h4', null, 'ALPR and record history'));
        if (!profile || !profile.ok) { el.appendChild(h('div', { class: 'pfp-state pfp-state-error' }, ctx.errorText(profile, 'History could not be loaded.'))); return; }
        if (profile.lastSeenAt) el.appendChild(h('div', { class: 'pfp-note' }, `Last seen by ALPR ${ctx.time(profile.lastSeenAt)}${profile.lastSeenLocation ? ` at ${profile.lastSeenLocation}` : ''}`));
        const acts = Array.isArray(profile.activity) ? profile.activity : [];
        if (!acts.length) { el.appendChild(h('div', { class: 'pfp-state' }, 'No reads or record changes for this plate.')); return; }
        const t = h('table', { class: 'pfp-table' }, h('thead', null, h('tr', null, h('th', null, 'When'), h('th', null, 'What'), h('th', null, 'Where'), h('th', null, 'By'), h('th', null, 'Ref'))));
        const tb = h('tbody');
        for (const a of acts) {
            tb.appendChild(h('tr', { dataset: { type: String(a.type || '') } }, h('td', null, ctx.time(a.timestamp || a.createdAt)), h('td', null, ACTIVITY_TEXT[a.type] || String(a.type || '')),
                h('td', null, a.location || ''), h('td', null, a.officerName || ''), h('td', null, a.referenceId || '')));
        }
        t.appendChild(tb);
        el.appendChild(t);
    }

    async function showAudit(plate) {
        const s = state;
        const { ctx } = s;
        const { h } = ctx;
        ctx.state(s.auditEl, 'loading');
        const res = await ctx.call('pf_mdt:audit:list', { entity: 'vehicle', entityId: plate, limit: 50 });
        if (!ctx.alive() || state !== s) return;
        if (!res.ok) { ctx.state(s.auditEl, 'error', ctx.errorText(res)); return; }
        const list = Array.isArray(res.list) ? res.list : [];
        s.auditEl.textContent = '';
        if (!list.length) { ctx.state(s.auditEl, 'empty', 'No audit rows.'); return; }
        const t = h('table', { class: 'pfp-table' }, h('thead', null, h('tr', null, h('th', null, 'When'), h('th', null, 'Action'), h('th', null, 'By'), h('th', null, 'Detail'))));
        const tb = h('tbody');
        for (const a of list) tb.appendChild(h('tr', null, h('td', null, ctx.time(a.at)), h('td', null, a.action || ''), h('td', null, `${a.by_cid || ''}${a.by_job ? ` (${a.by_job})` : ''}`), h('td', { class: 'pfp-muted' }, a.detail || '')));
        t.appendChild(tb);
        s.auditEl.appendChild(t);
    }

    async function drawImpoundTab() {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        s.body.textContent = '';
        const filter = ui.input({ placeholder: 'Filter by plate, owner or reason', 'aria-label': 'Filter impounded vehicles', value: s.filter });
        const listEl = h('div', { 'aria-live': 'polite' });
        s.body.appendChild(h('div', { class: 'pfp-toolbar' }, filter, ui.btn('Refresh', 'sm ghost', () => { s.impounds = null; drawImpoundTab(); })));
        s.body.appendChild(h('div', { class: 'pfp-note' }, 'A seized vehicle is released at the impound lot; a hold can only be lifted early by a supervisor there.'));
        s.body.appendChild(listEl);
        const draw = () => {
            listEl.textContent = '';
            const q = s.filter.toLowerCase();
            const rows = (s.impounds || []).filter((v) => !q || [v.plate, v.citizenid, v.impound && v.impound.reason].some((x) => String(x || '').toLowerCase().includes(q)));
            if (!rows.length) { ctx.state(listEl, 'empty', s.impounds && s.impounds.length ? 'No vehicle matches.' : 'The impound lot is empty.'); return; }
            const t = h('table', { class: 'pfp-table' }, h('thead', null, h('tr', null, h('th', null, 'Plate'), h('th', null, 'Model'), h('th', null, 'Owner'), h('th', null, 'Kind'), h('th', null, 'Reason'), h('th', null, 'Held until'), h('th', null, 'Case'))));
            const tb = h('tbody');
            for (const v of rows) {
                const imp = v.impound || {};
                tb.appendChild(h('tr', { dataset: { plate: String(v.plate || '') } },
                    h('td', null, h('button', { type: 'button', class: 'pfp-link', onClick: () => runPlate(v.plate) }, String(v.plate || ''))),
                    h('td', null, String(v.vehicle || '')), h('td', null, String(v.citizenid || '')), h('td', null, IMPOUND_KIND[imp.kind] || imp.kind || 'not recorded'),
                    h('td', null, imp.reason || ''), h('td', null, imp.holdUntil ? ctx.time(imp.holdUntil) : ''), h('td', null, imp.caseRef || '')));
            }
            t.appendChild(tb);
            listEl.appendChild(t);
        };
        filter.addEventListener('input', ui.debounce(() => { s.filter = filter.value.trim(); draw(); }, 200));
        if (!s.impounds) {
            ctx.state(listEl, 'loading');
            const res = await ctx.call('police:GetImpoundedVehicles', {});
            if (!ctx.alive() || state !== s || s.tab !== 'impound') return;
            if (!res.ok) { ctx.state(listEl, 'error', ctx.errorText(res, 'The impound list could not be loaded.')); return; }
            s.impounds = Array.isArray(res.data) ? res.data : [];
        }
        draw();
    }

    window.PFMdtPages.register('vehicles_ext', {
        title: 'Plates and impound',
        label: 'Plates / Impound',
        section: 'records',
        order: 10,
        icon: ['M3 13l2-6h14l2 6v5H3z', 'M7 18v2', 'M17 18v2', 'M3 13h18'],
        render,
        unmount() { state = null; },
    });
})();
