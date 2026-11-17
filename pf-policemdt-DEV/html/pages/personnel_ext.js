// Personnel: performance reviews, qualifications and internal affairs (batch 21, unit 21B).
//
// server/personnel_ext.lua (20F) endpoints:
//   pf_mdt:reviews:list {officerCid?}            own reviews; another officer's with viewPersonnel
//   pf_mdt:personnel:qualifications {officerCid?} pf-government's view (granted, implied, expiry)
//   pf_mdt:reviews:create {officerCid, period, scores, notes}   supervisors, lower ranks only
//   pf_mdt:ia:file {officerCid?, officerName?, category, summary, incidentRef?, complainantCid?, nonce}
//   pf_mdt:ia:list {state?, officerCid?}  pf_mdt:ia:get {id}  pf_mdt:ia:assign {id, investigatorCid?}
//   pf_mdt:ia:note {id, note}  pf_mdt:ia:finding {id, finding, outcome}  pf_mdt:ia:close {id, outcome?}
// The officer named in a complaint never sees it: the server leaves it out of every answer to them,
// and this page shows only what the server returns. Tabs follow the server's permission answer
// (pf_mdt:pages:access); the server checks every call again. Server strings go in as text (ctx.h).
(function () {
    'use strict';

    const SCORES = ['conduct', 'knowledge', 'reports', 'teamwork', 'initiative'];
    const CATEGORIES = ['conduct', 'force', 'discourtesy', 'misconduct', 'corruption', 'other'];
    const IA_STATES = ['received', 'investigating', 'sustained', 'not_sustained', 'closed'];
    const IA_TONE = { received: 'warn', investigating: 'accent', sustained: 'bad', not_sustained: 'ok', closed: '' };

    function words(s) { return String(s == null ? '' : s).replace(/_/g, ' '); }
    function nonce() { return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`; }
    function period() { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`; }

    function make(ctx) {
        const el = (tag, attrs, ...kids) => ctx.h(tag, attrs || {}, ...kids.flat().filter((k) => k !== null && k !== undefined && k !== false));
        const field = (label, value) => (value === null || value === undefined || value === '') ? null
            : el('div', { class: 'pfx-field' }, el('span', { class: 'pfx-label', text: label }), el('span', { class: 'pfx-value', text: String(value) }));
        const badge = (text, t) => el('span', { class: `pfp-badge ${t || ''}`.trim(), text: words(text) });
        const option = (v, t) => el('option', { value: v, text: t });
        return { el, field, badge, option };
    }

    const page = {
        title: 'Personnel & Internal Affairs',
        label: 'Personnel',
        section: 'department',
        order: 32,
        icon: ['M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z', 'M4 21c0-4 4-6 8-6s8 2 8 6'],

        async render(root, ctx) {
            const { el, field, badge, option } = make(ctx);
            const tabs = el('div', { class: 'pfp-tabs', role: 'tablist' });
            const body = el('div', { class: 'pfx-tabbody', role: 'tabpanel' });
            root.appendChild(el('div', { class: 'pfx-page pfx-personnel' },
                el('div', { class: 'pfx-head' }, el('h2', { text: 'Personnel' })), tabs, body));
            ctx.state(body, 'loading', 'Reading your permissions...');

            const access = await ctx.call('pf_mdt:pages:access', {});
            if (!ctx.alive()) return;
            body.textContent = '';
            if (!access || !access.ok) { ctx.state(body, 'error', ctx.errorText(access, 'Personnel records are not available')); return; }
            const can = access.can || {};
            const onduty = !!access.onduty;

            // officers for the pickers (names next to ids); a failed list leaves plain id inputs
            const officers = el('datalist', { id: `pfxOfficers${Date.now()}` });
            root.appendChild(officers);
            ctx.call('pf_mdt:officers:list', {}).then((res) => {
                if (!ctx.alive() || !res || !Array.isArray(res.officers)) return;
                res.officers.slice(0, 300).forEach((o) => officers.appendChild(el('option', { value: String(o.citizenid || ''), text: String(o.name || '') })));
            });
            const officerInput = (placeholder) => el('input', { class: 'pfp-input', type: 'text', maxlength: '32', list: officers.id, placeholder, 'aria-label': placeholder });

            const TABS = [
                { id: 'record', label: can.viewPersonnel ? 'Officer record' : 'My record', show: true, draw: drawRecord },
                { id: 'review', label: 'Write a review', show: !!can.perfReview, draw: drawReviewForm },
                { id: 'ia', label: 'Internal affairs', show: !!can.iaManage, draw: drawIa },
                { id: 'complaint', label: 'Take a complaint', show: !!can.iaIntake, draw: drawComplaintForm },
            ].filter((t) => t.show);
            TABS.forEach((t, i) => tabs.appendChild(el('button', { class: 'pfp-tab', type: 'button', role: 'tab', 'aria-selected': i === 0 ? 'true' : 'false',
                dataset: { tab: t.id }, text: t.label, onClick: () => select(t.id) })));

            function select(id) {
                tabs.querySelectorAll('[role="tab"]').forEach((b) => {
                    b.setAttribute('aria-selected', b.dataset.tab === id ? 'true' : 'false');
                    b.classList.toggle('active', b.dataset.tab === id);
                });
                body.textContent = '';
                const t = TABS.find((x) => x.id === id);
                if (t) t.draw();
            }

            // ── own / another officer's record ──
            function drawRecord() {
                const who = officerInput('Officer citizen id (blank = me)');
                const out = el('div', {});
                const form = el('form', { class: 'pfp-toolbar', onSubmit: (e) => { e.preventDefault(); load(); } }, who,
                    el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Show' }));
                if (!can.viewPersonnel) form.hidden = true;
                body.appendChild(el('div', {}, form, out));
                async function load() {
                    out.textContent = '';
                    ctx.state(out, 'loading', 'Reading the record...');
                    const payload = who.value.trim() ? { officerCid: who.value.trim() } : {};
                    const [reviews, quals] = await Promise.all([ctx.call('pf_mdt:reviews:list', payload), ctx.call('pf_mdt:personnel:qualifications', payload)]);
                    if (!ctx.alive()) return;
                    out.textContent = '';
                    const qCard = el('section', { class: 'pfp-card', 'aria-label': 'Qualifications' }, el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Qualifications' }),
                        quals && quals.dept ? badge(quals.dept, '') : null));
                    if (!quals || !quals.ok) qCard.appendChild(el('p', { class: 'pfx-error', text: ctx.errorText(quals, 'Department records are not available') }));
                    else if (!Array.isArray(quals.list) || !quals.list.length) qCard.appendChild(el('p', { class: 'pfp-muted', text: 'No qualifications on record' }));
                    else qCard.appendChild(el('ul', { class: 'pfx-list' }, quals.list.map((q) => el('li', {},
                        el('strong', { text: `${q.label || q.qual} ` }), badge(q.has ? 'held' : (q.state || 'not held'), q.has ? 'ok' : 'warn'),
                        q.source ? el('span', { class: 'pfp-muted', text: ` ${words(q.source)}` }) : null,
                        q.expiresAt ? el('span', { class: 'pfp-muted', text: ` expires ${ctx.time(q.expiresAt)}` }) : null,
                        q.reason ? el('span', { class: 'pfp-muted', text: ` (${words(q.reason)})` }) : null))));
                    const rCard = el('section', { class: 'pfp-card', 'aria-label': 'Performance reviews' }, el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Performance reviews' })));
                    if (!reviews || !reviews.ok) rCard.appendChild(el('p', { class: 'pfx-error', text: ctx.errorText(reviews, 'Reviews could not be read') }));
                    else if (!Array.isArray(reviews.list) || !reviews.list.length) rCard.appendChild(el('p', { class: 'pfp-muted', text: 'No reviews yet' }));
                    else reviews.list.forEach((v) => rCard.appendChild(el('div', { class: 'pfx-sub' },
                        el('strong', { text: `${v.period} - ${v.reviewerName || v.reviewerCid || ''}` }), el('span', { class: 'pfp-muted', text: ` ${ctx.time(v.at)}` }),
                        el('div', { class: 'pfx-row' }, SCORES.filter((k) => v.scores && v.scores[k] != null).map((k) => badge(`${k} ${v.scores[k]}/5`, ''))),
                        v.notes ? el('p', { class: 'pfx-prose', text: String(v.notes) }) : null)));
                    out.appendChild(qCard);
                    out.appendChild(rCard);
                }
                load();
            }

            // ── performance review ──
            function drawReviewForm() {
                const who = officerInput('Officer citizen id');
                const per = el('input', { class: 'pfp-input', type: 'text', maxlength: '7', value: period(), placeholder: 'YYYY-MM or YYYY-Qn', 'aria-label': 'Period' });
                const selects = SCORES.map((k) => el('select', { class: 'pfp-select', 'aria-label': k, dataset: { score: k } }, option('', `${k}: -`),
                    [1, 2, 3, 4, 5].map((n) => option(String(n), `${k}: ${n}`))));
                const notes = el('textarea', { class: 'pfp-textarea', rows: '5', maxlength: '4000', placeholder: 'Notes', 'aria-label': 'Notes' });
                const btn = el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Save review' });
                body.appendChild(el('form', { class: 'pfp-card pfx-stack', onSubmit: async (e) => {
                    e.preventDefault();
                    if (!onduty) { ctx.toast('Go on duty to write a review', 'error'); return; }
                    const scores = {};
                    selects.forEach((s) => { if (s.value) scores[s.dataset.score] = Number(s.value); });
                    btn.disabled = true;
                    const res = await ctx.call('pf_mdt:reviews:create', { officerCid: who.value.trim(), period: per.value.trim(), scores, notes: notes.value });
                    if (!ctx.alive()) return;
                    btn.disabled = false;
                    if (res && res.ok) { ctx.toast('Review saved', 'success'); notes.value = ''; selects.forEach((s) => { s.value = ''; }); }
                    else ctx.toast(ctx.errorText(res, 'The review was not saved'), 'error');
                } }, el('p', { class: 'pfp-muted', text: 'You review officers of a lower rank, once per period.' }),
                el('div', { class: 'pfp-toolbar' }, who, per), el('div', { class: 'pfp-toolbar' }, selects), notes, btn));
            }

            // ── walk-in complaint ──
            function drawComplaintForm() {
                const officer = officerInput('Officer citizen id (if known)');
                const officerName = el('input', { class: 'pfp-input', type: 'text', maxlength: '128', placeholder: 'Officer name or callsign', 'aria-label': 'Officer name' });
                const complainant = el('input', { class: 'pfp-input', type: 'text', maxlength: '32', placeholder: 'Complainant citizen id (optional)', 'aria-label': 'Complainant' });
                const cat = el('select', { class: 'pfp-select', 'aria-label': 'Category' }, CATEGORIES.map((c) => option(c, c)));
                const ref = el('input', { class: 'pfp-input', type: 'text', maxlength: '64', placeholder: 'Incident or report reference', 'aria-label': 'Reference' });
                const summary = el('textarea', { class: 'pfp-textarea', rows: '6', maxlength: '4000', placeholder: 'What happened (at least 10 characters)', 'aria-label': 'Summary' });
                const btn = el('button', { class: 'pfp-btn primary', type: 'submit', text: 'File the complaint' });
                let key = nonce(); // one key per complaint: a double submit finds the first one
                body.appendChild(el('form', { class: 'pfp-card pfx-stack', onSubmit: async (e) => {
                    e.preventDefault();
                    const payload = { category: cat.value, summary: summary.value, nonce: key };
                    if (officer.value.trim()) payload.officerCid = officer.value.trim();
                    if (officerName.value.trim()) payload.officerName = officerName.value.trim();
                    if (complainant.value.trim()) payload.complainantCid = complainant.value.trim();
                    if (ref.value.trim()) payload.incidentRef = ref.value.trim();
                    btn.disabled = true;
                    const res = await ctx.call('pf_mdt:ia:file', payload);
                    if (!ctx.alive()) return;
                    btn.disabled = false;
                    if (res && res.ok) {
                        ctx.toast(`Complaint #${res.complaintId} filed with internal affairs`, 'success');
                        [officer, officerName, complainant, ref, summary].forEach((i) => { i.value = ''; });
                        key = nonce();
                    } else ctx.toast(ctx.errorText(res, 'The complaint was not filed'), 'error');
                } }, el('p', { class: 'pfp-muted', text: 'A complaint about yourself must be taken by another officer.' }),
                el('div', { class: 'pfp-toolbar' }, officer, officerName), el('div', { class: 'pfp-toolbar' }, complainant, cat, ref), summary, btn));
            }

            // ── internal affairs ──
            function drawIa() {
                const stateIn = el('select', { class: 'pfp-select', 'aria-label': 'State' }, option('', 'Any state'), IA_STATES.map((s) => option(s, words(s))));
                const who = officerInput('Officer citizen id');
                const listBox = el('div', { class: 'pfx-listbox' });
                const detail = el('div', { class: 'pfx-detail' });
                const listView = el('div', {}, el('form', { class: 'pfp-toolbar', onSubmit: (e) => { e.preventDefault(); load(); } }, stateIn, who,
                    el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Search' })), listBox);
                detail.hidden = true;
                body.appendChild(el('div', { onKeydown: (e) => { if (e.key === 'Escape' && !detail.hidden) back(); } }, listView, detail));

                function back() { detail.hidden = true; detail.textContent = ''; listView.hidden = false; load(); }

                async function load() {
                    listBox.textContent = '';
                    ctx.state(listBox, 'loading', 'Reading complaints...');
                    const payload = {};
                    if (stateIn.value) payload.state = stateIn.value;
                    if (who.value.trim()) payload.officerCid = who.value.trim();
                    const res = await ctx.call('pf_mdt:ia:list', payload);
                    if (!ctx.alive()) return;
                    listBox.textContent = '';
                    if (!res || !res.ok) { ctx.state(listBox, 'error', ctx.errorText(res, 'Complaints could not be read')); return; }
                    const rows = Array.isArray(res.list) ? res.list : [];
                    if (!rows.length) { ctx.state(listBox, 'empty', 'No complaints'); return; }
                    listBox.appendChild(el('div', { class: 'pfx-table-wrap' }, el('table', { class: 'pfp-table' },
                        el('thead', {}, el('tr', {}, ['#', 'Officer', 'Category', 'Channel', 'State', 'Investigator', 'Received'].map((h) => el('th', { scope: 'col', text: h })))),
                        el('tbody', {}, rows.map((c) => el('tr', { class: 'pfx-click', tabindex: '0', dataset: { id: String(c.id) },
                            onClick: () => open(c.id), onKeydown: (e) => { if (e.key === 'Enter') open(c.id); } },
                            el('td', { text: String(c.id) }), el('td', { text: c.officerName || c.officerCid || 'unknown' }), el('td', { text: words(c.category) }),
                            el('td', { text: words(c.channel) }), el('td', {}, badge(c.state, IA_TONE[c.state])), el('td', { text: c.investigatorCid || '' }),
                            el('td', { text: ctx.time(c.createdAt) })))))));
                }

                async function open(id) {
                    listView.hidden = true;
                    detail.hidden = false;
                    detail.textContent = '';
                    ctx.state(detail, 'loading', 'Reading the complaint...');
                    const res = await ctx.call('pf_mdt:ia:get', { id });
                    if (!ctx.alive()) return;
                    detail.textContent = '';
                    detail.appendChild(el('button', { class: 'pfp-btn ghost', type: 'button', text: 'Back to the list', onClick: back }));
                    if (!res || !res.ok || !res.complaint) { ctx.state(detail, 'error', ctx.errorText(res, 'The complaint could not be read')); return; }
                    const c = res.complaint;
                    detail.appendChild(el('section', { class: 'pfp-card', 'aria-label': 'Complaint' },
                        el('header', { class: 'pfx-card-head' }, el('h3', { text: `Complaint #${c.id}` }), badge(c.state, IA_TONE[c.state]), badge(c.category, '')),
                        el('div', { class: 'pfx-grid' }, field('Officer', c.officerName || c.officerCid), field('Officer id', c.officerCid),
                            field('Complainant', c.complainantName || c.complainantCid), field('Channel', words(c.channel)), field('Taken by', c.takenBy),
                            field('Reference', c.incidentRef), field('Investigator', c.investigatorCid), field('Outcome', c.outcome),
                            field('Received', ctx.time(c.createdAt)), field('Updated', ctx.time(c.updatedAt))),
                        el('p', { class: 'pfx-prose', text: c.summary || '' })));
                    const events = Array.isArray(res.events) ? res.events : [];
                    detail.appendChild(el('section', { class: 'pfp-card', 'aria-label': 'Investigation log' }, el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Investigation log' })),
                        events.length ? el('ul', { class: 'pfx-list' }, events.map((v) => el('li', {}, el('strong', { text: `${words(v.action)} ` }),
                            el('span', { class: 'pfp-muted', text: `${v.byCid || ''} - ${ctx.time(v.at)}` }), v.note ? el('div', { text: String(v.note) }) : null)))
                            : el('p', { class: 'pfp-muted', text: 'Nothing logged yet' })));
                    if (onduty) detail.appendChild(actions(c));
                }

                function actions(c) {
                    const card = el('section', { class: 'pfp-card pfx-stack', 'aria-label': 'Actions' }, el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Actions' })));
                    const run = (endpoint, payload, done) => async (e) => {
                        const b = e && e.currentTarget;
                        if (b) b.disabled = true;
                        const res = await ctx.call(endpoint, Object.assign({ id: c.id }, payload()));
                        if (!ctx.alive()) return;
                        if (b) b.disabled = false;
                        if (res && res.ok) { ctx.toast(done, 'success'); open(c.id); }
                        else ctx.toast(ctx.errorText(res, 'Refused'), 'error');
                    };
                    if (c.state === 'received' || c.state === 'investigating') {
                        const inv = officerInput('Investigator (blank = me)');
                        card.appendChild(el('div', { class: 'pfp-toolbar' }, inv, el('button', { class: 'pfp-btn', type: 'button', text: c.state === 'received' ? 'Assign' : 'Reassign',
                            onClick: run('pf_mdt:ia:assign', () => (inv.value.trim() ? { investigatorCid: inv.value.trim() } : {}), 'Assigned') })));
                    }
                    if (c.state === 'investigating') {
                        const note = el('textarea', { class: 'pfp-textarea', rows: '3', maxlength: '1000', placeholder: 'Investigator note', 'aria-label': 'Note' });
                        card.appendChild(el('div', { class: 'pfx-stack' }, note, el('button', { class: 'pfp-btn', type: 'button', text: 'Add note',
                            onClick: run('pf_mdt:ia:note', () => ({ note: note.value }), 'Note added') })));
                        const outcome = el('input', { class: 'pfp-input', type: 'text', maxlength: '255', placeholder: 'Outcome', 'aria-label': 'Outcome' });
                        card.appendChild(el('div', { class: 'pfp-toolbar' }, outcome,
                            el('button', { class: 'pfp-btn danger', type: 'button', text: 'Sustained', onClick: run('pf_mdt:ia:finding', () => ({ finding: 'sustained', outcome: outcome.value }), 'Finding recorded') }),
                            el('button', { class: 'pfp-btn', type: 'button', text: 'Not sustained', onClick: run('pf_mdt:ia:finding', () => ({ finding: 'not_sustained', outcome: outcome.value }), 'Finding recorded') })));
                    }
                    if (c.state === 'received' || c.state === 'sustained' || c.state === 'not_sustained') {
                        const why = el('input', { class: 'pfp-input', type: 'text', maxlength: '255', placeholder: c.state === 'received' ? 'Why it is dismissed (required)' : 'Closing outcome (optional)', 'aria-label': 'Closing outcome' });
                        card.appendChild(el('div', { class: 'pfp-toolbar' }, why, el('button', { class: 'pfp-btn', type: 'button', text: c.state === 'received' ? 'Dismiss' : 'Close',
                            onClick: run('pf_mdt:ia:close', () => (why.value.trim() ? { outcome: why.value.trim() } : {}), 'Closed') })));
                    }
                    return card;
                }

                load();
            }

            if (TABS.length) select(TABS[0].id);
        },
    };

    if (window.PFMdtPages && typeof window.PFMdtPages.register === 'function') window.PFMdtPages.register('personnel', page);
    window.PFMdtExtPages = window.PFMdtExtPages || {};
    window.PFMdtExtPages.personnel = page;
})();
