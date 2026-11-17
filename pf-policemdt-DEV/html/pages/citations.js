// Citations and fines (batch 21A): the MDT fines and sentences of one citizen
// (server/sentencing.lua pf_mdt:getCitizenSentences: fine, paid state, jail time, bail, the open
// incarceration from pf-justice) with the citation paper print (NUI printCitationPaper: the server
// checks the printer distance and makes the paper). Citizens are found with the server-paged
// pf_mdt:searchCitizens. Court citations (pf-justice citation orders with their violation, officer and
// contest deadline, plus field citations pf-justice has not taken yet) come from pf_mdt:citations:list
// (server/pages_records.lua), paged by order id.
(function () {
    'use strict';
    if (!window.PFMdtPages) return;

    const TYPE_TEXT = { fine: 'Fine', sentence: 'Sentence', both: 'Fine + sentence' };
    let state = null;

    function render(root, ctx) {
        const { h, ui } = ctx;
        state = { ctx, page: 1, query: '', total: 0, selected: null };
        const search = ui.input({ placeholder: 'Search citizen by name or citizen id', 'aria-label': 'Search citizens' });
        search.addEventListener('input', ui.debounce(() => { state.query = search.value.trim(); state.page = 1; loadCitizens(); }, 300));
        state.listEl = h('div', { class: 'pfp-list', role: 'list' });
        state.pager = h('div', { class: 'pfp-pager' });
        state.detailEl = h('div', { class: 'pfp-card', 'aria-live': 'polite' });
        ctx.state(state.detailEl, 'empty', 'Pick a citizen to see their fines, sentences and citation papers.');
        root.appendChild(h('div', { class: 'pfp-head' }, h('div', null, h('h2', null, 'Citations and fines'), h('div', { class: 'pfp-sub' }, 'MDT fines, sentences, payment state and citation papers'))));
        root.appendChild(h('div', { class: 'pfp-toolbar' }, search));
        root.appendChild(h('div', { class: 'pfp-split' }, h('div', { class: 'pfp-card' }, state.listEl, state.pager), state.detailEl));
        ctx.state(state.listEl, 'empty', 'Search for a citizen.');
        const p = ctx.params || {};
        if (p.citizenId) select(String(p.citizenId), p.name || '');
    }

    async function loadCitizens() {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        if (s.query.length < 2) { ctx.state(s.listEl, 'empty', 'Type at least 2 characters.'); s.pager.textContent = ''; return; }
        ctx.state(s.listEl, 'loading');
        const res = await ctx.call('pf_mdt:searchCitizens', { query: s.query, page: s.page, pageSize: 10 });
        if (!ctx.alive() || state !== s) return;
        if (!res.ok) { ctx.state(s.listEl, 'error', ctx.errorText(res, 'Citizens could not be loaded.')); return; }
        const list = Array.isArray(res.data) ? res.data : [];
        s.total = Number(res.total) || list.length;
        s.listEl.textContent = '';
        if (!list.length) ctx.state(s.listEl, 'empty', 'No citizen matches.');
        for (const c of list) {
            const id = c.citizenId || c.citizenid;
            if (!id) continue;
            s.listEl.appendChild(h('button', { type: 'button', class: 'pfp-row' + (id === s.selected ? ' active' : ''), role: 'listitem', dataset: { citizenId: id }, onClick: () => select(id, c.name) },
                h('span', { class: 'pfp-row-main' }, h('span', { class: 'pfp-row-title' }, c.name || id), h('span', { class: 'pfp-muted' }, id))));
        }
        const pages = Math.max(1, Math.ceil(s.total / 10));
        s.pager.textContent = '';
        s.pager.appendChild(ui.btn('Previous', 'sm', () => { s.page -= 1; loadCitizens(); }, { disabled: s.page <= 1 }));
        s.pager.appendChild(h('span', null, `Page ${s.page} of ${pages}`));
        s.pager.appendChild(ui.btn('Next', 'sm', () => { s.page += 1; loadCitizens(); }, { disabled: s.page >= pages }));
    }

    async function select(citizenId, name) {
        const s = state;
        const { ctx } = s;
        s.selected = citizenId;
        s.listEl.querySelectorAll('.pfp-row').forEach((r) => r.classList.toggle('active', r.dataset.citizenId === citizenId));
        ctx.state(s.detailEl, 'loading');
        const res = await ctx.call('pf_mdt:getCitizenSentences', { citizenId });
        if (!ctx.alive() || state !== s || s.selected !== citizenId) return;
        if (!res.ok) { ctx.state(s.detailEl, 'error', ctx.errorText(res, 'The record could not be loaded.')); return; }
        drawDetail(citizenId, name, res);
    }

    // the open incarceration line (pf-justice answer, or the old jail's)
    function jailLine(aj) {
        const { h, ui } = state.ctx;
        if (!aj) return null;
        if (aj.unknown) return h('div', { class: 'pfp-note' }, 'The custody system did not answer; the jail state is unknown right now.');
        if (aj.releasedOnLogin) return h('div', { class: 'pfp-note' }, 'Released: the sentence ended while the citizen was offline (applied when they logged in).');
        if (!aj.active) return null;
        return h('div', { class: 'pfp-note' }, ui.badge('In custody', 'bad'), ` ${aj.remainingMinutes || 0} min left${aj.facility ? ` at ${aj.facility}` : ''}`,
            aj.bailPending ? ' · bail payment being confirmed' : (Number(aj.bailAmount) > 0 ? ` · bail $${Number(aj.bailAmount).toLocaleString()}` : ''));
    }

    const CIT_STATE_KIND = { paid: 'ok', active: 'bad', pending: 'warn', payment_pending: 'warn', contested: 'warn', dismissed: '', cancelled: '', expired: '' };

    // court citations of the citizen (pf-justice), paged; the first page also lists field citations
    // the court system has not taken yet
    async function loadCitations(citizenId, box, after) {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        if (!after) ctx.state(box, 'loading', 'Reading court citations...');
        const res = await ctx.call('pf_mdt:citations:list', after ? { citizenId, after } : { citizenId });
        if (!ctx.alive() || state !== s || s.selected !== citizenId) return;
        if (!after) box.textContent = '';
        const more = box.querySelector('.pfp-more');
        if (more && more.parentNode) more.parentNode.removeChild(more);
        if (!res.ok) { box.appendChild(h('div', { class: 'pfp-state pfp-state-error' }, ctx.errorText(res, 'Court citations could not be read.'))); return; }
        const pending = Array.isArray(res.pending) ? res.pending : [];
        if (!after && pending.length) {
            box.appendChild(h('div', { class: 'pfp-note' }, 'Issued in the field, not yet taken by the court system (retried automatically):'));
            for (const p of pending) {
                box.appendChild(h('div', { class: 'pfp-row', dataset: { citationUid: p.uid || '' } }, h('span', { class: 'pfp-row-main' },
                    h('span', { class: 'pfp-row-title' }, `${p.violation || p.code || 'Citation'}${p.amount ? ` · $${Number(p.amount).toLocaleString()}` : ''}`),
                    h('span', { class: 'pfp-muted' }, `${p.officerName || p.officerCid || ''} · ${ctx.time(p.createdAt)}${p.error ? ` · ${p.error}` : ''}`)), ui.badge(p.state, p.state === 'failed' ? 'bad' : 'warn')));
            }
        }
        const list = Array.isArray(res.list) ? res.list : [];
        if (!after && !list.length) box.appendChild(h('div', { class: 'pfp-state' }, 'No court citations.'));
        if (list.length) {
            let t = box.querySelector('table.pfp-cit-table');
            if (!t) {
                t = h('table', { class: 'pfp-table pfp-cit-table' }, h('thead', null, h('tr', null, h('th', null, 'Issued'), h('th', null, 'Violation'), h('th', null, 'Amount'),
                    h('th', null, 'State'), h('th', null, 'Officer'), h('th', null, 'Contest until'))), h('tbody'));
                box.appendChild(t);
            }
            const tb = t.querySelector('tbody');
            for (const c of list) {
                const extra = [c.plate ? `plate ${c.plate}` : '', c.speed ? `${c.speed}/${c.limit || '?'} km/h` : ''].filter(Boolean).join(' · ');
                tb.appendChild(h('tr', { dataset: { orderId: String(c.orderId) } }, h('td', null, ctx.time(c.issuedAt)),
                    h('td', null, c.reason || '', extra ? h('div', { class: 'pfp-muted' }, extra) : null),
                    h('td', null, c.amount != null ? `$${Number(c.amount).toLocaleString()}` : '', c.paidAmount ? h('div', { class: 'pfp-muted' }, `paid $${Number(c.paidAmount).toLocaleString()}`) : null),
                    h('td', null, ui.badge(String(c.state || '').replace(/_/g, ' '), CIT_STATE_KIND[c.state])),
                    h('td', null, c.officerName || c.officerCid || ''), h('td', null, c.contestUntil ? ctx.time(c.contestUntil) : '')));
            }
        }
        if (res.next) box.appendChild(ui.btn('Load more', 'sm pfp-more', () => loadCitations(citizenId, box, res.next)));
    }

    function drawDetail(citizenId, name, res) {
        const s = state;
        const { ctx } = s;
        const { h, ui } = ctx;
        const box = s.detailEl;
        box.textContent = '';
        const rows = Array.isArray(res.sentences) ? res.sentences : [];
        const unpaid = rows.filter((r) => Number(r.fineAmount) > 0 && Number(r.fineSuccess) !== 1).reduce((a, r) => a + Number(r.fineAmount || 0), 0);
        box.appendChild(h('div', { class: 'pfp-head' },
            h('div', null, h('h3', null, name || citizenId), h('div', { class: 'pfp-sub' }, citizenId)),
            h('span', { class: 'pfp-toolbar' }, ui.badge(`${rows.length} record${rows.length === 1 ? '' : 's'}`), unpaid > 0 ? ui.badge(`Unpaid $${unpaid.toLocaleString()}`, 'bad') : ui.badge('No unpaid MDT fines', 'ok'))));
        const jl = jailLine(res.activeJail);
        if (jl) box.appendChild(jl);
        box.appendChild(h('div', { class: 'pfp-toolbar' }, ui.btn('Open citizen profile', 'sm ghost', () => { try { router.openCitizenProfile(citizenId); } catch (_) {} })));
        const tabs = h('div', { class: 'pfp-tabs', role: 'tablist' });
        const panel = h('div', { role: 'tabpanel' });
        const show = (k) => {
            s.tab = k;
            tabs.querySelectorAll('.pfp-tab').forEach((b) => { b.classList.toggle('active', b.dataset.tab === k); b.setAttribute('aria-selected', b.dataset.tab === k ? 'true' : 'false'); });
            panel.textContent = '';
            if (k === 'court') loadCitations(citizenId, panel);
            else drawFines(panel, rows);
        };
        for (const [k, l] of [['fines', 'MDT fines and sentences'], ['court', 'Court citations']]) {
            tabs.appendChild(h('button', { type: 'button', class: 'pfp-tab', role: 'tab', dataset: { tab: k }, onClick: () => show(k) }, l));
        }
        box.appendChild(tabs);
        box.appendChild(panel);
        show(s.tab === 'court' ? 'court' : 'fines');
    }

    function drawFines(box, rows) {
        const { ctx } = state;
        const { h, ui } = ctx;
        if (!rows.length) { box.appendChild(h('div', { class: 'pfp-state' }, 'No fines or sentences.')); return; }
        const t = h('table', { class: 'pfp-table' }, h('thead', null, h('tr', null, h('th', null, 'Date'), h('th', null, 'Title'), h('th', null, 'Type'),
            h('th', null, 'Fine'), h('th', null, 'Time'), h('th', null, 'Officer'), h('th'))));
        const tb = h('tbody');
        for (const r of rows) {
            const fine = Number(r.fineAmount || 0);
            const paid = Number(r.fineSuccess) === 1;
            const err = ui.formError();
            const pay = fine > 0 ? ui.badge(paid ? 'Paid' : (r.error ? 'Unpaid' : 'Unpaid / invoiced'), paid ? 'ok' : 'bad') : null;
            const print = fine > 0 && ctx.can('printCitation') ? ui.btn('Print citation', 'sm', () => {
                err.textContent = '';
                // through the client callback: it checks the printer distance first, then the server makes the paper
                sendCallback('printCitationPaper', { sentenceId: Number(r.id) }, (out) => {
                    if (!ctx.alive()) return;
                    if (out && out.success) ctx.toast(`Citation printed (${out.citationUid || 'ready'})`, 'success');
                    else err.textContent = ctx.errorText(out && typeof out.error === 'string' && !/^[a-z_]+$/.test(out.error) ? { message: out.error } : out, 'The citation was not printed.');
                });
            }) : null;
            tb.appendChild(h('tr', { dataset: { sentenceId: String(r.id) } },
                h('td', null, ctx.time(r.createdAt)), h('td', null, r.title || '', r.description ? h('div', { class: 'pfp-muted' }, r.description) : null),
                h('td', null, TYPE_TEXT[String(r.sentenceType || '').toLowerCase()] || String(r.sentenceType || '')),
                h('td', null, fine > 0 ? `$${fine.toLocaleString()} ` : '-', pay),
                h('td', null, Number(r.prisonTime) > 0 ? `${Number(r.prisonTime)} months` : '-', Number(r.bailed) === 1 ? h('div', { class: 'pfp-muted' }, `bailed${r.bailPaidByName ? ' by ' + r.bailPaidByName : ''}`) : null),
                h('td', null, r.officerName || ''), h('td', null, print, err, r.error ? h('div', { class: 'pfp-muted' }, r.error) : null)));
        }
        t.appendChild(tb);
        box.appendChild(t);
    }

    window.PFMdtPages.register('citations', {
        title: 'Citations and fines',
        label: 'Citations',
        section: 'records',
        order: 30,
        icon: ['M6 2h12v20l-3-2-3 2-3-2-3 2z', 'M9 7h6', 'M9 11h6', 'M9 15h3'],
        render,
        unmount() { state = null; },
    });
})();
