// BOLO board (batch 21A): server/records_ext.lua pf_mdt:bolos:list | create | clear.
// Active BOLOs (people and vehicles) with description, last seen, danger and expiry. A vehicle BOLO
// feeds the plate flags the ALPR reads (GetPlateFlags 'BOLO'). The author clears their own BOLO; a
// rank with clearAnyBolo clears any (the server decides; the page only offers the button).
// The server pushes pf_mdt:client:boloChanged to on-duty officers; the page then re-reads the list.
(function () {
    'use strict';
    if (!window.PFMdtPages) return;

    let state = null;

    function render(root, ctx) {
        const { h, ui } = ctx;
        state = { ctx, kind: '', list: [], focus: Number(ctx.params && ctx.params.boloId) || null };
        const kind = ui.select([['', 'People and vehicles'], ['person', 'People'], ['vehicle', 'Vehicles']], '', { 'aria-label': 'BOLO kind' });
        kind.addEventListener('change', () => { state.kind = kind.value; load(); });
        state.formSlot = h('div');
        state.listEl = h('div', { class: 'pfp-list', role: 'list', 'aria-live': 'polite' });
        root.appendChild(h('div', { class: 'pfp-head' },
            h('div', null, h('h2', null, 'BOLO board'), h('div', { class: 'pfp-sub' }, 'Be on the lookout: active people and vehicles')),
            ctx.can('bolos') ? ui.btn('+ New BOLO', 'primary', () => openCreate()) : null));
        root.appendChild(h('div', { class: 'pfp-toolbar' }, kind, ui.btn('Refresh', 'sm ghost', () => load())));
        root.appendChild(state.formSlot);
        root.appendChild(h('div', { class: 'pfp-card' }, state.listEl));
        load();
        const p = ctx.params || {};
        if (p.create) openCreate(p.create);
    }

    async function load() {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        ctx.state(s.listEl, 'loading');
        const payload = s.kind ? { kind: s.kind } : {};
        const res = await ctx.call('pf_mdt:bolos:list', payload);
        if (!ctx.alive() || state !== s) return;
        if (!res.ok) { ctx.state(s.listEl, 'error', ctx.errorText(res, 'The BOLO board could not be loaded.')); return; }
        s.list = Array.isArray(res.list) ? res.list : [];
        s.listEl.textContent = '';
        if (!s.list.length) { ctx.state(s.listEl, 'empty', 'No active BOLOs.'); return; }
        const me = ctx.user.citizenid;
        for (const b of s.list) {
            const err = ui.formError();
            const reason = ui.input({ placeholder: 'Reason', maxlength: 255, 'aria-label': 'Clear reason' });
            const mayClear = ctx.can('bolos') && (b.byCid === me || ctx.can('clearAnyBolo'));
            const subject = b.kind === 'vehicle'
                ? h('button', { type: 'button', class: 'pfp-link', onClick: () => ctx.open('vehicles_ext', { plate: b.plate }) }, `Vehicle ${b.plate || ''}`)
                : (b.citizenid ? h('button', { type: 'button', class: 'pfp-link', onClick: () => { try { router.openCitizenProfile(b.citizenid); } catch (_) {} } }, `Person ${b.citizenid}`) : 'Person (unidentified)');
            const card = h('div', { class: 'pfp-card', role: 'listitem', dataset: { boloId: b.id } },
                h('div', { class: 'pfp-head' }, h('strong', null, `BOLO #${b.id} · `, subject),
                    h('span', { class: 'pfp-toolbar' }, b.danger ? ui.badge('Danger', 'bad') : null, ui.badge(b.kind === 'vehicle' ? 'Vehicle' : 'Person', 'accent'))),
                h('div', { class: 'pfp-pre' }, b.description || ''),
                h('div', { class: 'pfp-muted' }, `Last seen: ${b.lastSeen || 'unknown'} · created ${ctx.time(b.createdAt)} · expires ${ctx.time(b.expiresAt)}`),
                b.caseId ? h('div', null, h('button', { type: 'button', class: 'pfp-link', onClick: () => ctx.open('cases', { caseId: b.caseId }) }, `Case #${b.caseId}`)) : null,
                mayClear ? h('div', { class: 'pfp-toolbar' }, reason, ui.btn('Clear', 'sm danger', async () => {
                    err.textContent = '';
                    const r = await ctx.call('pf_mdt:bolos:clear', { id: b.id, reason: reason.value });
                    if (!ctx.alive() || state !== s) return;
                    if (!r.ok) { err.textContent = ctx.errorText(r); return; }
                    ctx.toast(`BOLO #${b.id} cleared`, 'success');
                    load();
                })) : null, err);
            if (s.focus === b.id) card.classList.add('active');
            s.listEl.appendChild(card);
        }
    }

    function openCreate(prefill) {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        prefill = prefill && typeof prefill === 'object' ? prefill : {};
        s.formSlot.textContent = '';
        const kind = ui.select([['person', 'Person'], ['vehicle', 'Vehicle']], prefill.plate ? 'vehicle' : 'person', { 'aria-label': 'Kind' });
        const cid = ui.input({ placeholder: 'Citizen id (optional)', maxlength: 64, value: prefill.citizenId || '' });
        const plate = ui.input({ placeholder: 'Plate', maxlength: 8, value: prefill.plate || '' });
        const description = ui.textarea({ placeholder: 'Description: who or what, clothing, colour, direction', maxlength: 500 });
        const lastSeen = ui.input({ placeholder: 'Last seen (place, time)', maxlength: 255 });
        const hours = ui.input({ type: 'number', min: 1, max: 168, placeholder: 'Hours (default 24)' });
        const caseId = ui.input({ placeholder: 'Case # (optional)', maxlength: 10, inputmode: 'numeric', value: prefill.caseId || '' });
        const danger = h('input', { type: 'checkbox' });
        const err = ui.formError();
        const close = () => { s.formSlot.textContent = ''; };
        const sync = () => { cid.disabled = kind.value !== 'person'; plate.disabled = kind.value !== 'vehicle'; };
        kind.addEventListener('change', sync);
        sync();
        const send = ui.btn('Broadcast BOLO', 'primary', async () => {
            err.textContent = '';
            const payload = { kind: kind.value, description: description.value, lastSeen: lastSeen.value, danger: danger.checked };
            if (kind.value === 'vehicle') payload.plate = plate.value; else if (cid.value.trim()) payload.citizenid = cid.value.trim();
            if (hours.value) payload.hours = Number(hours.value);
            if (caseId.value.trim()) payload.caseId = Number(caseId.value.trim());
            const res = await ctx.call('pf_mdt:bolos:create', payload);
            if (!ctx.alive() || state !== s) return;
            if (!res.ok) { err.textContent = ctx.errorText(res); return; }
            ctx.toast(`BOLO #${res.id} broadcast to on-duty units`, 'success');
            close();
            load();
        });
        s.formSlot.appendChild(ui.escCloses(h('div', { class: 'pfp-card' }, h('h3', null, 'New BOLO'),
            h('div', { class: 'pfp-form' }, ui.field('Kind', kind), ui.field('Citizen id', cid), ui.field('Plate', plate), ui.field('Last seen', lastSeen),
                ui.field('Hours', hours), ui.field('Case #', caseId), h('label', { class: 'pfp-field' }, 'Armed / dangerous', danger), ui.field('Description', description, true)),
            h('div', { class: 'pfp-toolbar' }, send, ui.btn('Cancel', 'ghost', close), err)), close));
        description.focus();
    }

    window.PFMdtPages.register('bolos', {
        title: 'BOLO board',
        label: 'BOLOs',
        section: 'records',
        order: 20,
        icon: ['M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20z', 'M12 8v5', 'M12 16h.01'],
        render,
        unmount() { state = null; },
        onMessage(data) { if (data && data.action === 'boloChanged' && state) load(); },
    });
})();
