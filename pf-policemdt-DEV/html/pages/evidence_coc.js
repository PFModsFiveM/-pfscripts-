// Evidence with chain of custody and integrity (batch 21, unit 21B).
//
// The evidence pfm-policejob holds (15D/18D), read through server/pages_ext.lua:
//   pf_mdt:evidence:list      server-paged list (case, kind, state, "held by me"; "Load more" uses
//                             the server's cursor)
//   pf_mdt:evidence:get       one item: details, integrity score and flags, the custody chain, lab jobs
//   pf_mdt:evidence:transfer  hand the bag in at a lab, a locker or a court. pfm-policejob decides:
//                             the officer must hold it and stand at the destination (server position)
// Integrity is computed by the server from the chain (seal breaks, gaps, missing bags); the page
// only shows it. The legacy photo evidence of incidents stays on the "Evidence" page.
// Every server string goes into the DOM as text (ctx.h).
(function () {
    'use strict';

    const KINDS = ['casing', 'projectile', 'blood', 'fingerprint', 'dna_swab', 'gsr_kit', 'drug', 'weapon', 'item', 'document', 'photo', 'vehicle', 'digital'];
    const STATES = ['collected', 'sealed', 'in_transit', 'stored', 'at_lab', 'analysed', 'in_court', 'released', 'destroyed'];
    const FLAG_TEXT = {
        seal_broken: 'seal broken outside a lab or court', gap: 'gap in the chain', contaminated: 'collected without gloves',
        missing: 'bag missing', unverified_chain: 'registered late: chain before that unverified',
    };

    function words(s) { return String(s == null ? '' : s).replace(/_/g, ' '); }
    function tone(score) { const n = Number(score); return n >= 80 ? 'ok' : (n >= 50 ? 'warn' : 'bad'); }

    function make(ctx) {
        const el = (tag, attrs, ...kids) => ctx.h(tag, attrs || {}, ...kids.flat().filter((k) => k !== null && k !== undefined && k !== false));
        const field = (label, value) => (value === null || value === undefined || value === '') ? null
            : el('div', { class: 'pfx-field' }, el('span', { class: 'pfx-label', text: label }), el('span', { class: 'pfx-value', text: String(value) }));
        const badge = (text, t) => el('span', { class: `pfp-badge ${t || ''}`.trim(), text: words(text) });
        const option = (v, t) => el('option', { value: v, text: t });
        return { el, field, badge, option };
    }

    // "player:ABC123" -> "officer ABC123", "lab:main" -> "lab main"
    function holderText(h) {
        if (!h) return '';
        const ref = String(h.ref || '');
        const m = /^([a-z]+):(.+)$/.exec(ref);
        if (!m) return words(h.kind || ref);
        if (m[1] === 'player') return `officer ${m[2]}`;
        if (m[1] === 'inv') return `locker ${m[2]}`;
        return `${m[1]} ${m[2]}`;
    }

    const page = {
        title: 'Evidence Chain of Custody',
        label: 'Evidence Chain',
        section: 'records',
        order: 41,
        icon: ['M6 3h12v18H6z', 'M9 7h6', 'M9 11h6', 'M9 15h3'],

        async render(root, ctx) {
            const { el, field, badge, option } = make(ctx);
            let access = null;
            let cursor = null;
            let filters = {};

            const caseIn = el('input', { class: 'pfp-input', type: 'number', min: '1', placeholder: 'Case #', 'aria-label': 'Case number' });
            const kindIn = el('select', { class: 'pfp-select', 'aria-label': 'Kind' }, option('', 'Any kind'), KINDS.map((k) => option(k, words(k))));
            const stateIn = el('select', { class: 'pfp-select', 'aria-label': 'State' }, option('', 'Any state'), STATES.map((s) => option(s, words(s))));
            const mineIn = el('input', { type: 'checkbox', 'aria-label': 'Held by me' });
            const listBox = el('div', { class: 'pfx-listbox' });
            const more = el('button', { class: 'pfp-btn', type: 'button', text: 'Load more', onClick: () => load(true) });
            more.hidden = true;
            const detail = el('div', { class: 'pfx-detail' });
            const listView = el('div', { class: 'pfx-listview' },
                el('form', { class: 'pfp-toolbar', onSubmit: (e) => { e.preventDefault(); load(false); } },
                    caseIn, kindIn, stateIn, el('label', { class: 'pfx-check' }, mineIn, 'Held by me'),
                    el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Search' })),
                listBox, more);
            root.appendChild(el('div', { class: 'pfx-page pfx-evidence', onKeydown: (e) => { if (e.key === 'Escape' && !detail.hidden) back(); } },
                el('div', { class: 'pfx-head' }, el('h2', { text: 'Evidence chain of custody' }),
                    el('p', { class: 'pfp-muted', text: 'Every hand-over is recorded by the server. Integrity drops with seal breaks, gaps and missing bags.' })),
                listView, detail));
            detail.hidden = true;

            function back() { detail.hidden = true; listView.hidden = false; detail.textContent = ''; }

            async function load(append) {
                if (!append) {
                    cursor = null;
                    filters = { caseId: caseIn.value.trim(), kind: kindIn.value, state: stateIn.value, mine: mineIn.checked === true };
                    listBox.textContent = '';
                    ctx.state(listBox, 'loading', 'Reading evidence...');
                }
                const payload = Object.assign({}, filters);
                if (append && cursor) payload.after = cursor;
                more.disabled = true;
                const res = await ctx.call('pf_mdt:evidence:list', payload);
                if (!ctx.alive()) return;
                more.disabled = false;
                if (!append) listBox.textContent = '';
                if (!res || !res.ok) { if (!append) ctx.state(listBox, 'error', ctx.errorText(res, 'Evidence could not be read')); else ctx.toast(ctx.errorText(res, 'Evidence could not be read'), 'error'); return; }
                const rows = Array.isArray(res.list) ? res.list : [];
                if (!append && !rows.length) ctx.state(listBox, 'empty', 'No evidence matches');
                let table = listBox.querySelector('tbody');
                if (!table && rows.length) {
                    const t = el('table', { class: 'pfp-table' },
                        el('thead', {}, el('tr', {}, ['Tag', 'Item', 'State', 'Held by', 'Integrity', 'Collected'].map((h) => el('th', { scope: 'col', text: h })))),
                        el('tbody', {}));
                    listBox.appendChild(el('div', { class: 'pfx-table-wrap' }, t));
                    table = t.querySelector('tbody');
                }
                rows.forEach((it) => table.appendChild(el('tr', { class: 'pfx-click', tabindex: '0', dataset: { id: String(it.id) },
                    onClick: () => openItem(it.id), onKeydown: (e) => { if (e.key === 'Enter') openItem(it.id); } },
                    el('td', { text: String(it.tag || it.id) }), el('td', { text: `${it.label || ''} (${words(it.kind)})` }),
                    el('td', {}, badge(it.state, ''), it.sealed ? badge('sealed', 'ok') : null),
                    el('td', { text: holderText(it.holder) }), el('td', {}, badge(String(it.integrity ?? '?'), tone(it.integrity))),
                    el('td', { text: ctx.time(it.collectedAt) }))));
                cursor = res.next || null;
                more.hidden = !cursor;
            }

            async function openItem(id) {
                listView.hidden = true;
                detail.hidden = false;
                detail.textContent = '';
                ctx.state(detail, 'loading', 'Reading the evidence record...');
                if (!access) access = await ctx.call('pf_mdt:pages:access', {});
                const res = await ctx.call('pf_mdt:evidence:get', { id });
                if (!ctx.alive()) return;
                detail.textContent = '';
                detail.appendChild(el('button', { class: 'pfp-btn ghost', type: 'button', text: 'Back to the list', onClick: back }));
                if (!res || !res.ok || !res.item) { ctx.state(detail, 'error', ctx.errorText(res, 'The evidence could not be read')); return; }
                drawItem(res);
                const first = detail.querySelector('button');
                if (first) first.focus();
            }

            function drawItem(res) {
                const it = res.item;
                const integ = res.integrity || {};
                const attrs = it.attrs && typeof it.attrs === 'object' ? it.attrs : {};
                detail.appendChild(el('section', { class: 'pfp-card', 'aria-label': 'Evidence' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: `${it.tag || it.id} ${it.label || ''}`.trim() }),
                        badge(it.state, ''), it.sealed ? badge('sealed', 'ok') : badge('unsealed', 'warn')),
                    el('div', { class: 'pfx-grid' },
                        field('Kind', words(it.kind)), field('Held by', holderText(it.holder)), field('Collected', ctx.time(it.collectedAt)),
                        field('Collected by', it.collectedBy), field('Method', words(it.method)), field('Quality', it.quality),
                        field('Scene', it.scene && it.scene.label), field('Identification', words(it.identification)),
                        Object.keys(attrs).filter((k) => k !== 'url' && k !== 'body').slice(0, 12).map((k) => field(words(k), typeof attrs[k] === 'object' ? JSON.stringify(attrs[k]) : attrs[k]))),
                    Array.isArray(it.caseRefs) && it.caseRefs.length ? el('div', { class: 'pfx-sub' }, el('span', { class: 'pfx-label', text: 'Linked to' }),
                        it.caseRefs.map((r) => r.type === 'case'
                            ? el('button', { class: 'pfp-btn sm', type: 'button', text: `Case #${r.id}`, onClick: () => ctx.open('cases', { id: Number(r.id) }) })
                            : badge(`${r.type} ${r.id}`, ''))) : null));

                detail.appendChild(el('section', { class: 'pfp-card', 'aria-label': 'Integrity' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Integrity' }), badge(`${integ.score ?? it.integrity ?? '?'} / 100`, tone(integ.score ?? it.integrity))),
                    Array.isArray(integ.flags) && integ.flags.length
                        ? el('ul', { class: 'pfx-list' }, integ.flags.map((f) => el('li', { text: FLAG_TEXT[f] || words(f) })))
                        : el('p', { class: 'pfp-muted', text: 'No integrity findings' })));

                const chain = Array.isArray(res.custody) ? res.custody : [];
                detail.appendChild(el('section', { class: 'pfp-card', 'aria-label': 'Chain of custody' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Chain of custody' }),
                        res.custodyTotal > chain.length ? el('span', { class: 'pfp-muted', text: `latest ${chain.length} of ${res.custodyTotal}` }) : null),
                    chain.length ? el('div', { class: 'pfx-table-wrap' }, el('table', { class: 'pfp-table' },
                        el('thead', {}, el('tr', {}, ['When', 'Event', 'From', 'To', 'By', 'Note'].map((h) => el('th', { scope: 'col', text: h })))),
                        el('tbody', {}, chain.map((c) => el('tr', {},
                            el('td', { text: ctx.time(c.at) }), el('td', { text: words(c.event) }), el('td', { text: c.from || '' }), el('td', { text: c.to || '' }),
                            el('td', { text: `${c.actor || ''}${c.actorJob ? ` (${c.actorJob})` : ''}` }), el('td', { text: c.note || '' }))))))
                        : el('p', { class: 'pfp-muted', text: 'No custody events' })));

                const labs = Array.isArray(res.labs) ? res.labs : [];
                detail.appendChild(el('section', { class: 'pfp-card', 'aria-label': 'Lab jobs' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Lab' }),
                        el('button', { class: 'pfp-btn sm', type: 'button', text: 'Open the lab queue', onClick: () => ctx.open('lab', { id: it.id }) })),
                    labs.length ? el('ul', { class: 'pfx-list' }, labs.map((j) => el('li', {},
                        el('strong', { text: `${words(j.test)} ` }), badge(j.state, j.state === 'released' ? 'ok' : ''),
                        el('span', { class: 'pfp-muted', text: j.state === 'queued' || j.state === 'processing' ? ` ready about ${ctx.time(j.eta)}` : '' }),
                        j.result && j.result.summary ? el('div', { text: String(j.result.summary) }) : null)))
                        : el('p', { class: 'pfp-muted', text: 'No lab work requested' })));

                if (it.state !== 'released' && it.state !== 'destroyed') detail.appendChild(transferCard(it));
            }

            function transferCard(it) {
                const card = el('section', { class: 'pfp-card', 'aria-label': 'Hand over' }, el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Hand over' })));
                const may = access && access.ok && access.can && access.can.evidenceHandle && access.onduty;
                if (!may) { card.appendChild(el('p', { class: 'pfp-muted', text: access && access.ok && !access.onduty ? 'Go on duty to move evidence.' : 'Your rank cannot move evidence.' })); return card; }
                const dest = el('select', { class: 'pfp-select', 'aria-label': 'Destination' }, option('lab', 'Crime lab'), option('locker', 'Evidence locker'), option('court', 'Court'));
                const ref = el('input', { class: 'pfp-input', type: 'text', maxlength: '48', placeholder: 'Lab id (main)', 'aria-label': 'Destination id' });
                const note = el('input', { class: 'pfp-input', type: 'text', maxlength: '200', placeholder: 'Note (optional)', 'aria-label': 'Note' });
                const btn = el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Hand over' });
                const hints = { lab: 'Lab id (main)', locker: 'Locker number', court: 'Court case id' };
                dest.addEventListener('change', () => { ref.placeholder = hints[dest.value]; ref.value = ''; });
                card.appendChild(el('p', { class: 'pfp-muted', text: 'You must hold the bag and stand at the lab, locker or court; the server checks both.' }));
                card.appendChild(el('form', { class: 'pfp-toolbar', onSubmit: async (e) => {
                    e.preventDefault();
                    const to = { kind: dest.value };
                    const v = ref.value.trim();
                    if (dest.value === 'lab') to.labId = v || 'main';
                    else if (dest.value === 'locker') to.lockerId = Number(v);
                    else to.caseId = v;
                    btn.disabled = true;
                    const res = await ctx.call('pf_mdt:evidence:transfer', { id: it.id, to, note: note.value });
                    if (!ctx.alive()) return;
                    btn.disabled = false;
                    if (res && res.ok) { ctx.toast(res.duplicate ? 'Already there' : 'Handed over', 'success'); openItem(it.id); }
                    else ctx.toast(ctx.errorText(res, 'The hand-over failed'), 'error');
                } }, dest, ref, note, btn));
                return card;
            }

            const p = ctx.params || {};
            if (p.caseId) caseIn.value = String(p.caseId);
            if (p.id) await openItem(p.id);
            else await load(false);
        },
    };

    if (window.PFMdtPages && typeof window.PFMdtPages.register === 'function') window.PFMdtPages.register('evidencecoc', page);
    window.PFMdtExtPages = window.PFMdtExtPages || {};
    window.PFMdtExtPages.evidencecoc = page;
})();
