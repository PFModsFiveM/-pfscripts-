// Citations and fines (batch 21A): the MDT fines and sentences of one citizen
// (server/sentencing.lua pf_mdt:getCitizenSentences: fine, paid state, jail time, bail, the open
// incarceration from pf-justice) with the citation paper print (NUI printCitationPaper: the server
// checks the printer distance and makes the paper). Citizens are found with the server-paged
// pf_mdt:searchCitizens. Field traffic citations are pf-justice orders; the MDT server has no
// endpoint that lists them yet, so this page does not pretend to show them.
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
