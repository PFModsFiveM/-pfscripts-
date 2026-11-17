// Warrants v2 (batch 21A): replaces the old 'warrant' page. Server: server/records_ext.lua
// (pf_mdt:warrants:create | review | setStatus | listFor) and the paged pf_mdt:searchWarrants /
// pf_mdt_dispatch:server:GetWarrantDetails reads of server/main.lua.
// An officer REQUESTS a warrant: the id, the expiry and the suspect's name come from the server and the
// warrant starts pending approval (a judge review through pf-justice, or a supervisor when no judge
// review was filed). Served links the suspect's custody; recall removes it. The page never makes an id.
(function () {
    'use strict';
    if (!window.PFMdtPages) return;

    const TYPES = [['arrest', 'Arrest'], ['search', 'Search'], ['bench', 'Bench']];
    const STATUS_KIND = { pending: 'warn', active: 'bad', served: 'ok', removed: '', expired: '', denied: '' };
    const APPROVAL_TEXT = {
        pending_approval: 'Waiting for approval', needs_info: 'More information requested', approved: 'Approved',
        denied: 'Denied', legacy: 'Issued before approvals',
    };
    const APPROVAL_KIND = { pending_approval: 'warn', needs_info: 'warn', approved: 'ok', denied: 'bad', legacy: '' };
    const PAGE_SIZE = 15;
    const label = (s) => String(s || '').replace(/_/g, ' ');
    const chargeText = (c) => (c && typeof c === 'object') ? (c.name || c.label || c.code || '') : String(c ?? '');

    let state = null;

    function render(root, ctx) {
        const { h, ui } = ctx;
        state = { ctx, root, page: 1, total: 0, list: [], query: '', selected: null };
        const search = ui.input({ placeholder: 'Search suspect name or warrant id', 'aria-label': 'Search warrants' });
        search.addEventListener('input', ui.debounce(() => { state.query = search.value.trim(); state.page = 1; load(); }, 300));
        state.listEl = h('div', { class: 'pfp-list', role: 'list' });
        state.pager = h('div', { class: 'pfp-pager' });
        state.detailEl = h('div', { class: 'pfp-card', 'aria-live': 'polite' });
        state.formSlot = h('div');
        ctx.state(state.detailEl, 'empty', 'Pick a warrant.');
        root.appendChild(h('div', { class: 'pfp-head' },
            h('div', null, h('h2', null, 'Warrants'), h('div', { class: 'pfp-sub' }, 'Requests, approvals, service and recall')),
            ctx.can('createWarrant') ? ui.btn('+ Request warrant', 'primary', () => openRequest()) : null));
        root.appendChild(h('div', { class: 'pfp-toolbar' }, search));
        root.appendChild(state.formSlot);
        root.appendChild(h('div', { class: 'pfp-split' }, h('div', { class: 'pfp-card' }, state.listEl, state.pager), state.detailEl));
        load();
        const p = ctx.params || {};
        if (p.warrantId) select(String(p.warrantId));
        if (p.request) openRequest(p.request);
    }

    async function load() {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        ctx.state(s.listEl, 'loading');
        const res = await ctx.call('pf_mdt:searchWarrants', { query: s.query, page: s.page, pageSize: PAGE_SIZE });
        if (!ctx.alive() || state !== s) return;
        if (!res.ok) { ctx.state(s.listEl, 'error', ctx.errorText(res, 'Warrants could not be loaded.')); return; }
        s.list = Array.isArray(res.data) ? res.data : [];
        s.total = Number(res.total) || 0;
        s.listEl.textContent = '';
        if (!s.list.length) ctx.state(s.listEl, 'empty', s.query ? 'No warrant matches.' : 'No warrants.');
        for (const w of s.list) {
            s.listEl.appendChild(h('button', { type: 'button', class: 'pfp-row' + (w.warrantId === s.selected ? ' active' : ''), role: 'listitem', dataset: { warrantId: w.warrantId },
                onClick: () => select(w.warrantId) },
                h('span', { class: 'pfp-row-main' },
                    h('span', { class: 'pfp-row-title' }, `${w.suspectName || 'Unknown'}`),
                    h('span', { class: 'pfp-muted' }, `${w.warrantId} · ${label(w.type)} · expires ${ctx.time(w.expiresAt)}`)),
                h('span', { class: 'pfp-toolbar' }, ui.badge(label(w.status), STATUS_KIND[w.status]),
                    w.approvalState && w.approvalState !== 'legacy' ? ui.badge(APPROVAL_TEXT[w.approvalState] || label(w.approvalState), APPROVAL_KIND[w.approvalState]) : null)));
        }
        const pages = Math.max(1, Math.ceil(s.total / PAGE_SIZE));
        s.pager.textContent = '';
        s.pager.appendChild(ui.btn('Previous', 'sm', () => { s.page -= 1; load(); }, { disabled: s.page <= 1 }));
        s.pager.appendChild(h('span', null, `Page ${s.page} of ${pages} (${s.total})`));
        s.pager.appendChild(ui.btn('Next', 'sm', () => { s.page += 1; load(); }, { disabled: s.page >= pages }));
    }

    async function select(warrantId) {
        const s = state;
        const { ctx } = s;
        s.selected = warrantId;
        s.listEl.querySelectorAll('.pfp-row').forEach((r) => r.classList.toggle('active', r.dataset.warrantId === warrantId));
        ctx.state(s.detailEl, 'loading');
        const res = await ctx.call('pf_mdt_dispatch:server:GetWarrantDetails', warrantId);
        if (!ctx.alive() || state !== s || s.selected !== warrantId) return;
        if (!res.ok || !res.id) { ctx.state(s.detailEl, 'error', res.error === 'no_response' ? 'Warrant not found.' : ctx.errorText(res)); return; }
        drawDetail(res);
    }

    async function act(endpoint, payload, errEl, okText) {
        const s = state;
        const { ctx } = s;
        errEl.textContent = '';
        const res = await ctx.call(endpoint, payload);
        if (!ctx.alive() || state !== s) return res;
        if (!res.ok) { errEl.textContent = ctx.errorText(res); ctx.toast(errEl.textContent, 'error'); return res; }
        ctx.toast(okText, 'success');
        load();
        if (s.selected) select(s.selected);
        return res;
    }

    function drawDetail(w) {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        const box = s.detailEl;
        box.textContent = '';
        const id = String(w.id);
        const approval = w.approvalState || 'legacy';
        box.appendChild(h('div', { class: 'pfp-head' },
            h('div', null, h('h3', null, w.title || `${label(w.type)} warrant`), h('div', { class: 'pfp-sub' }, id)),
            h('span', { class: 'pfp-toolbar' }, ui.badge(label(w.status), STATUS_KIND[w.status]), ui.badge(APPROVAL_TEXT[approval] || label(approval), APPROVAL_KIND[approval]))));
        const suspect = w.suspectCitizenId
            ? h('button', { type: 'button', class: 'pfp-link', onClick: () => { try { router.openCitizenProfile(w.suspectCitizenId); } catch (_) {} } }, `${w.suspectName || ''} (${w.suspectCitizenId})`)
            : (w.suspectName || 'Unknown');
        box.appendChild(ui.kv([['Type', label(w.type)], ['Suspect', suspect], ['Address', w.address], ['Requested by', w.issuedBy],
            ['Requested', ctx.time(w.createdAt)], ['Expires', ctx.time(w.expiresAt)], ['Decided by', w.approvedBy ? String(w.approvedBy).replace(/^(\w+):.*/, '$1') : ''],
            ['Judge review', w.reviewId ? `#${w.reviewId}` : ''], ['Served custody', w.servedCustodyId ? `#${w.servedCustodyId}` : '']]));
        const charges = (Array.isArray(w.charges) ? w.charges : []).map(chargeText).filter(Boolean);
        if (charges.length) { box.appendChild(h('h4', null, 'Charges')); box.appendChild(h('div', { class: 'pfp-toolbar' }, charges.map((c) => ui.badge(c)))); }
        box.appendChild(h('h4', null, 'Affidavit'));
        box.appendChild(h('div', { class: 'pfp-pre' }, w.narrative || 'No affidavit.'));

        const err = ui.formError();
        const actions = h('div', { class: 'pfp-toolbar' });
        const pendingDecision = w.status === 'pending' && (approval === 'pending_approval' || approval === 'needs_info');
        if (pendingDecision && w.reviewId) {
            box.appendChild(h('div', { class: 'pfp-note' }, `A judge reviews this warrant (review #${w.reviewId}); the court decides it.`));
        } else if (pendingDecision && ctx.can('warrantApprove')) {
            const note = ui.input({ placeholder: 'Decision note', maxlength: 255, 'aria-label': 'Decision note' });
            actions.appendChild(note);
            actions.appendChild(ui.btn('Approve', 'ok sm', () => act('pf_mdt:warrants:review', { warrantId: id, decision: 'approve', note: note.value }, err, 'Warrant approved')));
            actions.appendChild(ui.btn('Deny', 'danger sm', () => act('pf_mdt:warrants:review', { warrantId: id, decision: 'deny', note: note.value }, err, 'Warrant denied')));
        } else if (pendingDecision) {
            box.appendChild(h('div', { class: 'pfp-note' }, 'Waiting for a supervisor or a judge to decide.'));
        }
        const servable = w.status === 'active' && (approval === 'approved' || approval === 'legacy');
        if (servable && ctx.can('serveWarrant')) {
            const custody = ui.input({ placeholder: 'Custody # (optional)', maxlength: 12, inputmode: 'numeric', 'aria-label': 'Custody number' });
            actions.appendChild(custody);
            actions.appendChild(ui.btn('Mark served', 'primary sm', () => {
                const payload = { warrantId: id, status: 'served' };
                if (custody.value.trim()) payload.custodyId = Number(custody.value.trim());
                act('pf_mdt:warrants:setStatus', payload, err, 'Warrant served');
            }));
        }
        if ((w.status === 'active' || w.status === 'pending') && ctx.can('deleteWarrant')) {
            actions.appendChild(ui.btn('Recall', 'danger sm', async () => {
                if (!(await ctx.confirm(`Recall warrant ${id}?`))) return;
                act('pf_mdt:warrants:setStatus', { warrantId: id, status: 'removed' }, err, 'Warrant recalled');
            }));
        }
        if (ctx.can('caseEdit')) {
            const caseId = ui.input({ placeholder: 'Case #', maxlength: 10, inputmode: 'numeric', 'aria-label': 'Case number' });
            actions.appendChild(caseId);
            actions.appendChild(ui.btn('Add to case', 'sm ghost', () => act('pf_mdt:cases:link', { caseId: Number(caseId.value), refType: 'warrant', refId: id }, err, 'Linked to the case')));
        }
        box.appendChild(actions);
        box.appendChild(err);
    }

    async function openRequest(prefill) {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        prefill = prefill && typeof prefill === 'object' ? prefill : {};
        s.formSlot.textContent = '';
        const type = ui.select(TYPES, prefill.type || 'arrest', { 'aria-label': 'Warrant type' });
        const cid = ui.input({ placeholder: 'Suspect citizen id', maxlength: 64, value: prefill.citizenId || '' });
        const find = ui.input({ placeholder: 'Find by name', maxlength: 64 });
        const results = h('div', { class: 'pfp-toolbar' });
        const address = ui.input({ placeholder: 'Address (search warrants)', maxlength: 128 });
        const title = ui.input({ placeholder: 'Title', maxlength: 255 });
        const days = ui.input({ type: 'number', min: 1, max: 30, placeholder: 'Days (default by type)' });
        const narrative = ui.textarea({ placeholder: 'Affidavit: what supports the warrant', maxlength: 8000 });
        const chargeBox = h('div', { class: 'pfp-grid' }, h('div', { class: 'pfp-muted' }, 'Loading charges...'));
        const err = ui.formError();
        const close = () => { s.formSlot.textContent = ''; };
        find.addEventListener('input', ui.debounce(async () => {
            const q = find.value.trim();
            results.textContent = '';
            if (q.length < 2) return;
            const res = await ctx.call('pf_mdt:searchCitizens', { query: q, page: 1, pageSize: 6 });
            if (!ctx.alive()) return;
            const list = Array.isArray(res.data) ? res.data : [];
            if (!list.length) results.appendChild(h('span', { class: 'pfp-muted' }, res.ok ? 'No match.' : ctx.errorText(res)));
            for (const c of list) {
                const id = c.citizenId || c.citizenid;
                if (!id) continue;
                results.appendChild(ui.btn(`${c.name || id} (${id})`, 'sm ghost', () => { cid.value = id; results.textContent = ''; }));
            }
        }, 300));
        const send = ui.btn('Send request', 'primary', async () => {
            err.textContent = '';
            const payload = { type: type.value, suspectCitizenId: cid.value.trim(), address: address.value.trim(), title: title.value.trim(), narrative: narrative.value,
                charges: Array.from(chargeBox.querySelectorAll('input[type=checkbox]:checked')).map((i) => i.value) };
            if (days.value) payload.expiryDays = Number(days.value);
            const res = await ctx.call('pf_mdt:warrants:create', payload);
            if (!ctx.alive() || state !== s) return;
            if (!res.ok) { err.textContent = ctx.errorText(res); return; }
            ctx.toast(`Warrant ${res.warrantId} requested: waiting for approval`, 'success');
            close();
            load();
            if (res.warrantId) select(String(res.warrantId));
        });
        s.formSlot.appendChild(ui.escCloses(h('div', { class: 'pfp-card' }, h('h3', null, 'Request a warrant'),
            h('div', { class: 'pfp-note' }, 'The server gives the warrant its number and expiry; it stays pending until a judge or a supervisor approves it.'),
            h('div', { class: 'pfp-form' }, ui.field('Type', type), ui.field('Suspect citizen id', cid), ui.field('Find citizen', find), ui.field('Address', address),
                ui.field('Title', title), ui.field('Valid for (days)', days), ui.field('Affidavit', narrative, true)),
            results, h('h4', null, 'Charges'), chargeBox,
            h('div', { class: 'pfp-toolbar' }, send, ui.btn('Cancel', 'ghost', close), err)), close));
        cid.focus();
        const res = await ctx.call('pf_mdt:getAllCharges', {});
        if (!ctx.alive() || state !== s) return;
        chargeBox.textContent = '';
        const rows = Array.isArray(res.data) ? res.data : [];
        if (!rows.length) chargeBox.appendChild(h('div', { class: 'pfp-muted' }, res.ok ? 'No charges in the criminal code.' : ctx.errorText(res)));
        for (const c of rows) {
            if (!c || !c.name) continue;
            chargeBox.appendChild(h('label', { class: 'pfp-muted' }, h('input', { type: 'checkbox', value: c.name }), ` ${c.code || ''} ${c.name}`));
        }
    }

    window.PFMdtPages.register('warrant', {
        title: 'Warrants',
        label: 'Warrants',
        section: 'records',
        render,
        unmount() { state = null; },
        onMessage(data) {
            // the dashboard's warrant list opens a warrant here
            if (data && data.action === 'selectWarrant' && data.warrant && state) select(String(data.warrant.warrantId || data.warrant.id || ''));
            if (data && data.action === 'warrantChanged' && state) load();
        },
    });
})();
