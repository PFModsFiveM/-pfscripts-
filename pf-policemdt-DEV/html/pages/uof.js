// Use-of-force, OIS and pursuit reports (batch 21, unit 21B).
//
// The reports of server/personnel_ext.lua (20F). The automatic part (force level, events,
// subjects, pursuit metrics) is computed by the server from the officer's telemetry timeline
// (metadata, not video); the officer writes the narrative. Endpoints:
//   pf_mdt:force:list {state?, officerCid?}       own reports; supervisors (viewPersonnel) every report
//   pf_mdt:force:get {id}                         one report and its review chain
//   pf_mdt:force:draft {kind, minutes | from,to, subjectCid?, custodyId?, officerCid?}
//   pf_mdt:force:update {id, narrative?, subjectCid?, custodyId?}   the narrative autosaves here
//   pf_mdt:force:refresh {id}  pf_mdt:force:submit {id}
//   pf_mdt:force:review {id, decision = approve | return, note}      a supervisor who outranks the officer
//   pf_mdt:force:close {id, note?}                a second supervisor (never the reviewer)
// The server enforces every rule (own report, rank, never about yourself, states); the buttons only
// follow the server's permission answer. Every server string goes into the DOM as text (ctx.h).
(function () {
    'use strict';

    const LEVEL_TEXT = ['no force', 'restraint', 'takedown', 'less-lethal (taser)', 'level 4', 'firearm'];
    const KIND_TEXT = { uof: 'Use of force', pursuit: 'Pursuit', ois: 'Officer-involved shooting' };
    const STATE_TONE = { draft: '', returned: 'warn', submitted: 'accent', reviewed: 'ok', closed: 'ok' };
    const AUTOSAVE_MS = 2000;
    let active = null; // the open editor (flushed when the page is left)

    function words(s) { return String(s == null ? '' : s).replace(/_/g, ' '); }

    function make(ctx) {
        const el = (tag, attrs, ...kids) => ctx.h(tag, attrs || {}, ...kids.flat().filter((k) => k !== null && k !== undefined && k !== false));
        const field = (label, value) => (value === null || value === undefined || value === '') ? null
            : el('div', { class: 'pfx-field' }, el('span', { class: 'pfx-label', text: label }), el('span', { class: 'pfx-value', text: String(value) }));
        const badge = (text, t) => el('span', { class: `pfp-badge ${t || ''}`.trim(), text: words(text) });
        const option = (v, t) => el('option', { value: v, text: t });
        return { el, field, badge, option };
    }

    const page = {
        title: 'Use of Force Reports',
        label: 'Use of Force',
        section: 'department',
        order: 31,
        icon: ['M12 3l8 4v5c0 5-3.5 8-8 9-4.5-1-8-4-8-9V7z'],

        async render(root, ctx) {
            const { el, field, badge, option } = make(ctx);
            const stateIn = el('select', { class: 'pfp-select', 'aria-label': 'State' }, option('', 'Any state'),
                ['draft', 'returned', 'submitted', 'reviewed', 'closed'].map((s) => option(s, s)));
            const officerIn = el('input', { class: 'pfp-input', type: 'text', maxlength: '32', placeholder: 'Officer citizen id', 'aria-label': 'Officer citizen id' });
            const listBox = el('div', { class: 'pfx-listbox' });
            const draftBox = el('div', {});
            const detail = el('div', { class: 'pfx-detail' });
            const listView = el('div', { class: 'pfx-listview' },
                draftBox,
                el('form', { class: 'pfp-toolbar', onSubmit: (e) => { e.preventDefault(); loadList(); } },
                    stateIn, officerIn, el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Search' })),
                listBox);
            detail.hidden = true;
            root.appendChild(el('div', { class: 'pfx-page pfx-uof', onKeydown: (e) => { if (e.key === 'Escape' && !detail.hidden) back(); } },
                el('div', { class: 'pfx-head' }, el('h2', { text: 'Use of force and pursuit reports' }),
                    el('p', { class: 'pfp-muted', text: 'The force level and events come from your telemetry timeline (metadata, not video). You write the narrative; a supervisor reviews it.' })),
                listView, detail));

            const access = await ctx.call('pf_mdt:pages:access', {});
            if (!ctx.alive()) return;
            const can = (access && access.ok && access.can) || {};
            const me = access && access.ok ? access.cid : null;
            const onduty = !!(access && access.ok && access.onduty);
            if (!can.viewPersonnel) officerIn.hidden = true;

            function back() {
                if (active) active.flush();
                active = null;
                detail.hidden = true;
                detail.textContent = '';
                listView.hidden = false;
                loadList();
            }

            function draftForm(prefill) {
                draftBox.textContent = '';
                if (!can.forceReports) return;
                const kind = el('select', { class: 'pfp-select', 'aria-label': 'Kind' }, Object.keys(KIND_TEXT).map((k) => option(k, KIND_TEXT[k])));
                const minutes = el('input', { class: 'pfp-input', type: 'number', min: '1', max: '120', value: '30', 'aria-label': 'Minutes back' });
                const subject = el('input', { class: 'pfp-input', type: 'text', maxlength: '32', placeholder: 'Subject citizen id (optional)', 'aria-label': 'Subject' });
                const officer = el('input', { class: 'pfp-input', type: 'text', maxlength: '32', placeholder: 'Officer (blank = me)', 'aria-label': 'Officer' });
                if (!can.forceReview) officer.hidden = true;
                const btn = el('button', { class: 'pfp-btn primary', type: 'submit', text: 'Draft from telemetry' });
                const win = prefill && prefill.from && prefill.to ? { from: Number(prefill.from), to: Number(prefill.to) } : null;
                if (prefill && prefill.officerCid) officer.value = String(prefill.officerCid);
                draftBox.appendChild(el('section', { class: 'pfp-card', 'aria-label': 'New report' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: 'New report' }),
                        win ? badge(`window ${ctx.time(win.from)} to ${ctx.time(win.to)}`, 'accent') : null),
                    el('form', { class: 'pfp-toolbar', onSubmit: async (e) => {
                        e.preventDefault();
                        if (!onduty) { ctx.toast('Go on duty to draft a report', 'error'); return; }
                        const payload = { kind: kind.value };
                        if (win) { payload.from = win.from; payload.to = win.to; } else payload.minutes = Number(minutes.value);
                        if (subject.value.trim()) payload.subjectCid = subject.value.trim();
                        if (!officer.hidden && officer.value.trim()) payload.officerCid = officer.value.trim();
                        btn.disabled = true;
                        const res = await ctx.call('pf_mdt:force:draft', payload);
                        if (!ctx.alive()) return;
                        btn.disabled = false;
                        if (res && res.ok) {
                            ctx.toast(res.duplicate ? `Report #${res.reportId} already exists for this window` : `Report #${res.reportId} drafted`, 'success');
                            openReport(res.reportId);
                        } else ctx.toast(ctx.errorText(res, 'The report was not drafted'), 'error');
                    } }, kind, win ? null : el('label', { class: 'pfx-check' }, 'Minutes back', minutes), subject, officer, btn)));
            }

            async function loadList() {
                listBox.textContent = '';
                ctx.state(listBox, 'loading', 'Reading reports...');
                const payload = {};
                if (stateIn.value) payload.state = stateIn.value;
                if (!officerIn.hidden && officerIn.value.trim()) payload.officerCid = officerIn.value.trim();
                const res = await ctx.call('pf_mdt:force:list', payload);
                if (!ctx.alive()) return;
                listBox.textContent = '';
                if (!res || !res.ok) { ctx.state(listBox, 'error', ctx.errorText(res, 'Reports could not be read')); return; }
                const rows = Array.isArray(res.list) ? res.list : [];
                if (!rows.length) { ctx.state(listBox, 'empty', 'No reports'); return; }
                listBox.appendChild(el('div', { class: 'pfx-table-wrap' }, el('table', { class: 'pfp-table' },
                    el('thead', {}, el('tr', {}, ['#', 'Kind', 'Officer', 'Subject', 'Force', 'State', 'Updated'].map((h) => el('th', { scope: 'col', text: h })))),
                    el('tbody', {}, rows.map((r) => el('tr', { class: 'pfx-click', tabindex: '0', dataset: { id: String(r.id) },
                        onClick: () => openReport(r.id), onKeydown: (e) => { if (e.key === 'Enter') openReport(r.id); } },
                        el('td', { text: String(r.id) }), el('td', { text: KIND_TEXT[r.kind] || words(r.kind) }),
                        el('td', { text: r.officerName || r.officerCid || '' }), el('td', { text: r.subjectCid || '' }),
                        el('td', { text: LEVEL_TEXT[r.forceLevel] || String(r.forceLevel ?? '') }),
                        el('td', {}, badge(r.state, STATE_TONE[r.state]), r.origin === 'auto' ? badge('auto drafted', '') : null),
                        el('td', { text: ctx.time(r.updatedAt) })))))));
            }

            async function openReport(id) {
                if (active) active.flush();
                active = null;
                listView.hidden = true;
                detail.hidden = false;
                detail.textContent = '';
                ctx.state(detail, 'loading', 'Reading the report...');
                const res = await ctx.call('pf_mdt:force:get', { id });
                if (!ctx.alive()) return;
                detail.textContent = '';
                detail.appendChild(el('button', { class: 'pfp-btn ghost', type: 'button', text: 'Back to the list', onClick: back }));
                if (!res || !res.ok || !res.report) { ctx.state(detail, 'error', ctx.errorText(res, 'The report could not be read')); return; }
                drawReport(res.report, Array.isArray(res.chain) ? res.chain : []);
            }

            function summaryCard(r) {
                const s = r.summary && typeof r.summary === 'object' ? r.summary : null;
                const card = el('section', { class: 'pfp-card', 'aria-label': 'Telemetry summary' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: 'From the telemetry' }), badge('metadata, not video', ''),
                        badge(`telemetry ${r.telemetry || 'unknown'}`, String(r.telemetry || '').indexOf('unavailable') === 0 ? 'bad' : '')));
                if (!s) { card.appendChild(el('p', { class: 'pfp-muted', text: 'No summary' })); return card; }
                const p = s.pursuit || {};
                card.appendChild(el('div', { class: 'pfx-grid' },
                    field('Window', `${ctx.time(r.from)} to ${ctx.time(r.to)}`), field('Rows read', s.rows),
                    field('Highest force', LEVEL_TEXT[s.level] || s.level), field('Subjects seen', (s.subjects || []).join(', ')),
                    field('Weapons', (s.weapons || []).join(', ')), field('Plates', (s.plates || []).join(', ')),
                    r.kind === 'pursuit' || p.distance ? field('Distance (m)', p.distance) : null,
                    p.maxSpeed ? field('Top speed (m/s)', p.maxSpeed) : null, p.avgSpeed ? field('Average speed (m/s)', p.avgSpeed) : null,
                    s.clientReported ? field('Client-reported rows (not counted)', s.clientReported) : null,
                    s.truncated ? field('Note', 'window longer than the rows read') : null));
                const force = Array.isArray(s.force) ? s.force : [];
                if (force.length) {
                    card.appendChild(el('div', { class: 'pfx-table-wrap' }, el('table', { class: 'pfp-table' },
                        el('thead', {}, el('tr', {}, ['Time', 'Event', 'Level', 'Detail', 'Subject'].map((h) => el('th', { scope: 'col', text: h })))),
                        el('tbody', {}, force.map((f) => el('tr', { class: f.clientReported ? 'pfx-client' : '' },
                            el('td', { text: ctx.time(f.at) }), el('td', {}, words(f.kind), f.clientReported ? badge('client reported', 'warn') : null),
                            el('td', { text: LEVEL_TEXT[f.level] || String(f.level ?? '') }), el('td', { text: [f.action, f.weapon].filter(Boolean).join(' ') }),
                            el('td', { text: f.subject || '' })))))));
                }
                if (s.note) card.appendChild(el('p', { class: 'pfp-muted', text: String(s.note) }));
                return card;
            }

            function drawReport(r, chain) {
                const mine = r.officerCid === me;
                const editable = mine && (r.state === 'draft' || r.state === 'returned');
                detail.appendChild(el('section', { class: 'pfp-card', 'aria-label': 'Report' },
                    el('header', { class: 'pfx-card-head' }, el('h3', { text: `${KIND_TEXT[r.kind] || words(r.kind)} #${r.id}` }),
                        badge(r.state, STATE_TONE[r.state]), r.origin === 'auto' ? badge('auto drafted', '') : null),
                    el('div', { class: 'pfx-grid' },
                        field('Officer', r.officerName || r.officerCid), field('Subject', r.subjectCid), field('Custody', r.custodyId),
                        field('Force level', LEVEL_TEXT[r.forceLevel] || r.forceLevel), field('Created', ctx.time(r.createdAt)),
                        field('Submitted', r.submittedAt ? ctx.time(r.submittedAt) : null), field('Reviewer', r.reviewerCid), field('Closed by', r.closedBy))));
                detail.appendChild(summaryCard(r));
                detail.appendChild(narrativeCard(r, editable));
                if (chain.length) {
                    detail.appendChild(el('section', { class: 'pfp-card', 'aria-label': 'Review chain' },
                        el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Review chain' })),
                        el('ul', { class: 'pfx-list' }, chain.map((c) => el('li', {},
                            el('strong', { text: `${words(c.step)} ` }), el('span', { text: `${c.byName || c.byCid || ''} - ${ctx.time(c.at)}` }),
                            c.note ? el('div', { class: 'pfp-muted', text: String(c.note) }) : null)))));
                }
                const sup = supervisorCard(r);
                if (sup) detail.appendChild(sup);
            }

            function narrativeCard(r, editable) {
                const card = el('section', { class: 'pfp-card', 'aria-label': 'Narrative' }, el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Narrative' })));
                if (!editable) {
                    card.appendChild(el('p', { class: 'pfx-prose', text: r.narrative || 'No narrative yet' }));
                    return card;
                }
                const area = el('textarea', { class: 'pfp-textarea', rows: '8', maxlength: '8000', 'aria-label': 'Narrative' });
                area.value = r.narrative || '';
                const status = el('span', { class: 'pfp-muted', role: 'status', text: r.narrative ? 'Saved' : 'Not written yet' });
                const subject = el('input', { class: 'pfp-input', type: 'text', maxlength: '32', placeholder: 'Subject citizen id', 'aria-label': 'Subject' });
                subject.value = r.subjectCid || '';
                const custody = el('input', { class: 'pfp-input', type: 'number', min: '1', placeholder: 'Custody #', 'aria-label': 'Custody number' });
                custody.value = r.custodyId ? String(r.custodyId) : '';
                let timer = null;
                let dirty = false;
                let saving = null;

                async function save() {
                    if (timer) { clearTimeout(timer); timer = null; }
                    if (!dirty) return saving;
                    dirty = false;
                    const payload = { id: r.id, narrative: area.value };
                    status.textContent = 'Saving...';
                    saving = ctx.call('pf_mdt:force:update', payload).then((res) => {
                        if (res && res.ok) status.textContent = `Saved ${new Date().toLocaleTimeString()}`;
                        else { dirty = true; status.textContent = `Not saved: ${ctx.errorText(res, 'error')}`; }
                        return res;
                    });
                    return saving;
                }
                area.addEventListener('input', () => {
                    dirty = true;
                    status.textContent = 'Unsaved changes';
                    if (timer) clearTimeout(timer);
                    timer = setTimeout(save, AUTOSAVE_MS);
                });
                active = { flush: () => { if (dirty) save(); } };

                const saveLinks = el('button', { class: 'pfp-btn', type: 'button', text: 'Save subject and custody', onClick: async () => {
                    const payload = { id: r.id, subjectCid: subject.value.trim() };
                    if (custody.value) payload.custodyId = Number(custody.value);
                    const res = await ctx.call('pf_mdt:force:update', payload);
                    if (!ctx.alive()) return;
                    if (res && res.ok) ctx.toast('Saved', 'success'); else ctx.toast(ctx.errorText(res, 'Not saved'), 'error');
                } });
                const refresh = el('button', { class: 'pfp-btn', type: 'button', text: 'Read the telemetry again', onClick: async () => {
                    const res = await ctx.call('pf_mdt:force:refresh', { id: r.id });
                    if (!ctx.alive()) return;
                    if (res && res.ok) { ctx.toast('Summary updated', 'success'); await save(); openReport(r.id); }
                    else ctx.toast(ctx.errorText(res, 'The telemetry could not be read'), 'error');
                } });
                const submit = el('button', { class: 'pfp-btn primary', type: 'button', text: 'Submit for review', onClick: async () => {
                    submit.disabled = true;
                    dirty = true;
                    const saved = await save();
                    if (!ctx.alive()) return;
                    if (saved && !saved.ok) { submit.disabled = false; return; }
                    const res = await ctx.call('pf_mdt:force:submit', { id: r.id });
                    if (!ctx.alive()) return;
                    submit.disabled = false;
                    if (res && res.ok) { ctx.toast('Submitted for review', 'success'); openReport(r.id); }
                    else ctx.toast(ctx.errorText(res, 'The report was not submitted'), 'error');
                } });
                card.appendChild(el('div', { class: 'pfx-stack' }, area, status,
                    el('div', { class: 'pfp-toolbar' }, subject, custody, saveLinks),
                    el('div', { class: 'pfp-toolbar' }, refresh, submit)));
                return card;
            }

            function supervisorCard(r) {
                const notMine = r.officerCid !== me && r.subjectCid !== me;
                const card = el('section', { class: 'pfp-card', 'aria-label': 'Supervisor' }, el('header', { class: 'pfx-card-head' }, el('h3', { text: 'Supervisor' })));
                const note = el('textarea', { class: 'pfp-textarea', rows: '3', maxlength: '1000', placeholder: 'Note (required to return)', 'aria-label': 'Review note' });
                const act = (endpoint, payload, done) => async (e) => {
                    const b = e && e.currentTarget;
                    if (b) b.disabled = true;
                    const res = await ctx.call(endpoint, Object.assign({ id: r.id, note: note.value }, payload));
                    if (!ctx.alive()) return;
                    if (b) b.disabled = false;
                    if (res && res.ok) { ctx.toast(done, 'success'); openReport(r.id); }
                    else ctx.toast(ctx.errorText(res, 'Refused'), 'error');
                };
                if (r.state === 'submitted' && can.forceReview && notMine && onduty) {
                    card.appendChild(el('div', { class: 'pfx-stack' }, note, el('div', { class: 'pfp-toolbar' },
                        el('button', { class: 'pfp-btn primary', type: 'button', text: 'Approve', onClick: act('pf_mdt:force:review', { decision: 'approve' }, 'Approved') }),
                        el('button', { class: 'pfp-btn danger', type: 'button', text: 'Return to the officer', onClick: act('pf_mdt:force:review', { decision: 'return' }, 'Returned') }))));
                    return card;
                }
                if (r.state === 'reviewed' && can.forceClose && notMine && r.reviewerCid !== me && onduty) {
                    card.appendChild(el('div', { class: 'pfx-stack' }, note, el('div', { class: 'pfp-toolbar' },
                        el('button', { class: 'pfp-btn primary', type: 'button', text: 'Close the report', onClick: act('pf_mdt:force:close', {}, 'Closed') }))));
                    return card;
                }
                return null;
            }

            const p = ctx.params || {};
            draftForm(p.draft || null);
            if (p.id) await openReport(p.id);
            else await loadList();
        },

        unmount() {
            if (active) active.flush();
            active = null;
        },
    };

    if (window.PFMdtPages && typeof window.PFMdtPages.register === 'function') window.PFMdtPages.register('uof', page);
    window.PFMdtExtPages = window.PFMdtExtPages || {};
    window.PFMdtExtPages.uof = page;
})();
