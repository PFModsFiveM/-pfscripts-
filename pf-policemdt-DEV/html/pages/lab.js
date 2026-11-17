// Crime lab queue (batch 21, unit 21B).
//
// Evidence held at a lab with its lab jobs, as pfm-policejob holds them (18D), through
// server/pages_ext.lua:
//   pf_mdt:lab:queue    evidence at a lab (server-paged, newest first) with each item's jobs
//   pf_mdt:lab:submit   request tests on evidence that is at the lab (one job per test; the lab
//                       refuses tests the kind does not take, and a running test is not doubled)
//   pf_mdt:lab:release  release a ready result: only a lab technician (pf-government qualification)
//   pf_mdt:evidence:get one item, when another page opens the lab for it
// Results come from the server's analysis only. A ready result is shown to lab technicians; other
// officers see it once it is released. Every server string goes into the DOM as text (ctx.h).
(function () {
    'use strict';

    // Config.Evidence.Lab.Accepts of pfm-policejob (the lab checks again)
    const ACCEPTS = {
        dna: ['blood', 'dna_swab'], prints: ['fingerprint'], ballistics: ['casing', 'projectile', 'weapon'], tox: ['blood'],
        drug_id: ['drug', 'item'], gsr: ['gsr_kit'], trace: ['weapon', 'item', 'document'],
    };
    const TEST_LABEL = { dna: 'DNA', prints: 'Fingerprints', ballistics: 'Ballistics', tox: 'Toxicology', drug_id: 'Drug ID', gsr: 'GSR', trace: 'Trace' };
    const JOB_TONE = { queued: '', processing: 'warn', ready: 'accent', released: 'ok', failed: 'bad' };

    function words(s) { return String(s == null ? '' : s).replace(/_/g, ' '); }
    function testsFor(kind) { return Object.keys(ACCEPTS).filter((t) => ACCEPTS[t].indexOf(kind) !== -1); }

    function make(ctx) {
        const el = (tag, attrs, ...kids) => ctx.h(tag, attrs || {}, ...kids.flat().filter((k) => k !== null && k !== undefined && k !== false));
        const badge = (text, t) => el('span', { class: `pfp-badge ${t || ''}`.trim(), text: words(text) });
        return { el, badge };
    }

    const page = {
        title: 'Crime Lab',
        label: 'Crime Lab',
        section: 'records',
        order: 42,
        icon: ['M9 3h6', 'M10 3v6l-5 9a2 2 0 0 0 2 3h10a2 2 0 0 0 2-3l-5-9V3'],

        async render(root, ctx) {
            const { el, badge } = make(ctx);
            let access = null;
            let cursor = null;

            const stateIn = el('select', { class: 'pfp-select', 'aria-label': 'Show' },
                el('option', { value: '', text: 'Everything at the lab' }), el('option', { value: 'at_lab', text: 'Waiting for analysis' }),
                el('option', { value: 'analysed', text: 'Analysed' }));
            const focusBox = el('div', { class: 'pfx-focus' });
            const listBox = el('div', { class: 'pfx-cards' });
            const more = el('button', { class: 'pfp-btn', type: 'button', text: 'Load more', onClick: () => load(true) });
            more.hidden = true;
            root.appendChild(el('div', { class: 'pfx-page pfx-lab' },
                el('div', { class: 'pfx-head' }, el('h2', { text: 'Crime lab' }),
                    el('p', { class: 'pfp-muted', text: 'Hand evidence in at the lab first (Evidence Chain page). Results come only from the lab\'s analysis; a lab technician releases them.' })),
                el('form', { class: 'pfp-toolbar', onSubmit: (e) => { e.preventDefault(); load(false); } }, stateIn,
                    el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Refresh' })),
                focusBox, listBox, more));

            access = await ctx.call('pf_mdt:pages:access', {});
            if (!ctx.alive()) return;
            const can = (access && access.ok && access.can) || {};
            const onduty = !!(access && access.ok && access.onduty);

            async function load(append) {
                if (!append) { cursor = null; listBox.textContent = ''; ctx.state(listBox, 'loading', 'Reading the lab queue...'); }
                const payload = { state: stateIn.value };
                if (append && cursor) payload.after = cursor;
                more.disabled = true;
                const res = await ctx.call('pf_mdt:lab:queue', payload);
                if (!ctx.alive()) return;
                more.disabled = false;
                if (!append) listBox.textContent = '';
                if (!res || !res.ok) {
                    if (append) ctx.toast(ctx.errorText(res, 'The lab queue could not be read'), 'error');
                    else ctx.state(listBox, 'error', ctx.errorText(res, 'The lab queue could not be read'));
                    return;
                }
                const rows = Array.isArray(res.list) ? res.list : [];
                if (!append && !rows.length) ctx.state(listBox, 'empty', 'Nothing is at the lab');
                rows.forEach((it) => listBox.appendChild(itemCard(it, it.labs, it.labsError)));
                cursor = res.next || null;
                more.hidden = !cursor;
            }

            function itemCard(it, labs, labsError) {
                const card = el('section', { class: 'pfp-card', 'aria-label': `Evidence ${it.tag || it.id}`, dataset: { id: String(it.id) } },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: `${it.tag || it.id} ${it.label || ''}`.trim() }),
                        badge(it.kind, ''), badge(it.state, it.state === 'analysed' ? 'ok' : ''),
                        el('button', { class: 'pfp-btn sm ghost', type: 'button', text: 'Chain of custody', onClick: () => ctx.open('evidencecoc', { id: it.id }) })));
                if (labsError) card.appendChild(el('p', { class: 'pfx-error', text: labsError }));
                const jobs = Array.isArray(labs) ? labs : [];
                if (jobs.length) {
                    card.appendChild(el('div', { class: 'pfx-table-wrap' }, el('table', { class: 'pfp-table' },
                        el('thead', {}, el('tr', {}, ['Job', 'Test', 'State', 'Requested', 'Ready', 'Result', ''].map((h) => el('th', { scope: 'col', text: h })))),
                        el('tbody', {}, jobs.map((j) => el('tr', {},
                            el('td', { text: String(j.id) }), el('td', { text: TEST_LABEL[j.test] || words(j.test) }),
                            el('td', {}, badge(j.state, JOB_TONE[j.state])),
                            el('td', { text: `${ctx.time(j.requestedAt)}${j.requestedBy ? ` by ${j.requestedBy}` : ''}` }),
                            el('td', { text: j.releasedAt ? `released ${ctx.time(j.releasedAt)}` : ctx.time(j.eta) }),
                            el('td', {}, resultView(j)),
                            el('td', {}, j.state === 'ready' && can.labTech && onduty
                                ? el('button', { class: 'pfp-btn sm primary', type: 'button', text: 'Release', onClick: (e) => release(j, e.currentTarget) }) : null)))))));
                } else if (!labsError) {
                    card.appendChild(el('p', { class: 'pfp-muted', text: 'No tests requested yet' }));
                }
                if (it.state === 'at_lab' || it.state === 'analysed') card.appendChild(submitForm(it));
                return card;
            }

            function resultView(j) {
                const r = j.result;
                if (!r) return el('span', { class: 'pfp-muted', text: j.state === 'ready' ? 'awaiting review' : '' });
                const parts = [el('div', { text: String(r.summary || words(r.outcome || '')) })];
                if (r.unreviewed) parts.push(badge('released without review', 'warn'));
                if (Array.isArray(r.candidates) && r.candidates.length) parts.push(el('div', { class: 'pfp-muted', text: `Candidates: ${r.candidates.map((c) => (c && (c.name || c.cid)) || c).join(', ')}` }));
                else if (r.candidateCount) parts.push(el('div', { class: 'pfp-muted', text: `${r.candidateCount} consistent reference samples` }));
                if (r.randomMatch) parts.push(el('div', { class: 'pfp-muted', text: String(r.randomMatch) }));
                if (Array.isArray(r.notes)) r.notes.slice(0, 4).forEach((n) => parts.push(el('div', { class: 'pfp-muted', text: String(n) })));
                return el('div', {}, parts);
            }

            function submitForm(it) {
                const tests = testsFor(it.kind);
                if (!tests.length) return el('p', { class: 'pfp-muted', text: 'The lab runs no tests on this kind of evidence' });
                if (!(can.evidenceHandle && onduty)) return el('p', { class: 'pfp-muted', text: onduty ? 'Your rank cannot request tests.' : 'Go on duty to request tests.' });
                const boxes = tests.map((t) => el('input', { type: 'checkbox', value: t, 'aria-label': TEST_LABEL[t] }));
                const btn = el('button', { class: 'pfp-btn primary sm', type: 'submit', text: 'Request tests' });
                return el('form', { class: 'pfp-toolbar', onSubmit: async (e) => {
                    e.preventDefault();
                    const chosen = boxes.filter((b) => b.checked).map((b) => b.value);
                    if (!chosen.length) { ctx.toast('Pick at least one test', 'error'); return; }
                    btn.disabled = true;
                    const res = await ctx.call('pf_mdt:lab:submit', { id: it.id, tests: chosen });
                    if (!ctx.alive()) return;
                    btn.disabled = false;
                    if (res && res.ok) { ctx.toast(res.duplicate ? 'Those tests are already running' : `Requested; ready about ${ctx.time(res.eta)}`, 'success'); load(false); }
                    else ctx.toast(ctx.errorText(res, 'The lab refused the request'), 'error');
                } }, boxes.map((b, i) => el('label', { class: 'pfx-check' }, b, TEST_LABEL[tests[i]])), btn);
            }

            async function release(job, button) {
                if (button) button.disabled = true;
                const res = await ctx.call('pf_mdt:lab:release', { jobId: job.id });
                if (!ctx.alive()) return;
                if (res && res.ok) { ctx.toast('Result released', 'success'); load(false); }
                else { if (button) button.disabled = false; ctx.toast(ctx.errorText(res, 'The result was not released'), 'error'); }
            }

            const p = ctx.params || {};
            if (p.id) {
                ctx.state(focusBox, 'loading', 'Reading the evidence...');
                const one = await ctx.call('pf_mdt:evidence:get', { id: p.id });
                if (!ctx.alive()) return;
                focusBox.textContent = '';
                if (one && one.ok && one.item) focusBox.appendChild(itemCard(one.item, one.labs, null));
                else ctx.state(focusBox, 'error', ctx.errorText(one, 'The evidence could not be read'));
            }
            await load(false);
        },
    };

    if (window.PFMdtPages && typeof window.PFMdtPages.register === 'function') window.PFMdtPages.register('lab', page);
    window.PFMdtExtPages = window.PFMdtExtPages || {};
    window.PFMdtExtPages.lab = page;
})();
