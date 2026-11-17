// Court (pf-devices module, tablet and computer): the docket, cases, hearings, decisions, filing, warrant
// reviews, court orders and the probation caseload. The server answers who the player is to the court
// (`me`: roles from job, grade and duty) and every action is checked again there; the navigation only
// follows that answer. Forms send a key the server made (`key`), kept until the action went through, so a
// retry after a lost answer never records a decision twice. Every server string is put in as text.
(function () {
    'use strict';

    const ERRORS = {
        no_permission: 'You do not hold the court role for this', not_on_duty: 'Go on duty first', bad_key: 'This form expired; try again',
        invalid_state: 'Not possible in the current state of the case', busy: 'Someone else is changing this right now; try again',
        db_unavailable: 'The court database did not answer; nothing was changed', not_found: 'Not found', key_reused: 'This form was used for something else; open it again',
        rate_limited: 'Too fast; wait a moment', offline: 'The person must be in the city', too_far: 'Stand next to the citizen or meet at a probation office',
        bad_search: 'Search with 2 to 40 letters or digits', conflict: 'Already open', unavailable: 'Not available right now',
        server_error: 'The server could not do that', not_authorized: 'You may not use this app',
    };
    function errText(res) {
        if (!res) return 'No answer from the server';
        if (res.error === 'bad_args' && res.message) return res.message;
        return ERRORS[res.error] || res.message || String(res.error || 'That did not work').replace(/_/g, ' ');
    }
    const pad = (n) => String(n).padStart(2, '0');
    function fmt(ts) {
        if (!ts) return '-';
        const d = new Date(Number(ts) * 1000);
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }
    function inputTime(ts) {
        const d = new Date(Number(ts) * 1000);
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }
    function toUnix(v) { const t = Date.parse(v); return Number.isNaN(t) ? null : Math.floor(t / 1000); }
    const label = (s) => String(s == null ? '' : s).replace(/_/g, ' ');
    const TONE = {
        filed: 'pending', arraignment_scheduled: 'active', arraigned: 'active', plea_guilty: 'warn', plea_not_guilty: 'active', trial_scheduled: 'active',
        trial: 'active', guilty: 'bad', sentencing_scheduled: 'active', sentenced: 'bad', hearing_scheduled: 'active', appeal_pending: 'pending',
        dismissed: 'off', acquitted: 'ok', closed: 'off', scheduled: 'active', held: 'ok', auto: 'info', cancelled: 'off', adjourned: 'warn',
        requested: 'pending', needs_info: 'warn', approved: 'ok', denied: 'bad', active: 'active', pending: 'pending', suspended: 'warn',
        open: 'warn', missed: 'bad', attended: 'ok', ok: 'ok',
    };

    PFApps.register('court', {
        mount(container, ctx) {
            const { h } = ctx;
            const st = { me: null, view: null, caseId: null, cases: { page: 1, q: '', scope: 'open', kind: '', sort: 'filed_desc' },
                docket: { range: 7, state: 'scheduled', courtroom: '' }, warrants: { state: 'requested', page: 1 }, orders: { scope: 'active', page: 1 },
                caseload: { scope: 'mine', page: 1 }, supCid: null };
            const badge = (s) => h('span.ju-st' + (TONE[s] ? '.' + TONE[s] : ''), label(s));
            const clear = (el) => { el.textContent = ''; return el; };
            const nav = h('nav.pf-app-nav', { 'aria-label': 'Court sections' });
            const main = h('div.pf-app-body', { tabindex: '-1' });
            const roleBar = h('div.ju-roles');
            const root = h('div.pf-app.ju-app.ju-court',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '⚖️'), h('div', 'Court', h('div.pf-app-sub', 'San Andreas Superior Court'))), roleBar),
                h('div.pf-app-side', nav, h('div.ju-main', main)));
            container.appendChild(root);
            // Escape leaves a detail view (case, supervision) for its list
            root.addEventListener('keydown', (e) => {
                if (e.key !== 'Escape') return;
                if (st.view === 'case') { e.stopPropagation(); go(st.back || 'cases'); } else if (st.view === 'supervision') { e.stopPropagation(); go('probation'); }
            });

            // one key per form, renewed once the action went through (or the server dropped it)
            function keyed(scope) {
                let key = null;
                return {
                    async get() {
                        if (key) return key;
                        const r = await ctx.rpc('key', { scope });
                        if (!r || !r.ok) throw r || { error: 'server_error' };
                        key = r.key;
                        return key;
                    },
                    settle(res) { if (res && (res.ok || res.error === 'bad_key' || res.error === 'key_reused')) key = null; },
                };
            }
            // a submit button with a busy state; fn returns the server result
            function submitter(btn, errBox, fn) {
                return async (e) => {
                    if (e && e.preventDefault) e.preventDefault();
                    if (btn.disabled) return;
                    btn.disabled = true;
                    clear(errBox);
                    let res;
                    try { res = await fn(); } catch (x) { res = x && x.error ? x : { ok: false, error: 'server_error' }; }
                    btn.disabled = false;
                    if (!res || !res.ok) { errBox.textContent = errText(res); return null; }
                    return res;
                };
            }
            function loading() { return h('div.pf-empty', 'Loading…'); }
            function failed(res, retry) { return h('div.pf-empty', h('div.ju-error', errText(res)), retry ? h('button.pf-btn.sm', { type: 'button', onclick: retry }, 'Try again') : null); }
            function field(text, input) { return h('div.pf-field', h('label', text), input); }
            function select(options, value) {
                const s = h('select.pf-select', options.map(([v, t]) => h('option', { value: v }, t)));
                if (value != null) s.value = value;
                return s;
            }
            function pager(state, load) {
                return h('div.ju-pager',
                    h('button.pf-btn.sm.ghost', { type: 'button', disabled: state.page <= 1, onclick: () => { state.page -= 1; load(); } }, 'Previous'),
                    h('span.pf-small.pf-muted', 'Page ' + state.page),
                    h('button.pf-btn.sm.ghost', { type: 'button', disabled: !state.more, onclick: () => { state.page += 1; load(); } }, 'Next'));
            }
            function pickRow(cells, open) {
                return h('tr.ju-pick', { tabindex: '0', onclick: open, onkeydown: (e) => { if (e.key === 'Enter') open(); } }, cells);
            }

            // ── navigation from the server's answer ──
            const SECTIONS = [
                ['docket', 'Docket', (r) => r.court], ['cases', 'Cases', (r) => r.court], ['file', 'File a case', (r) => r.prosecutor || r.clerk || r.judge],
                ['warrants', 'Warrant reviews', (r) => r.warrants], ['orders', 'Court orders', (r) => r.judge || r.clerk],
                ['probation', 'Probation', (r) => r.probation],
            ];
            function allowed() { const r = (st.me && st.me.roles) || {}; return SECTIONS.filter((s) => s[2](r)); }
            function renderNav() {
                clear(nav);
                allowed().forEach(([id, text]) => nav.appendChild(h('button.pf-nav-item' + (st.view === id || (id === 'cases' && st.view === 'case') || (id === 'probation' && st.view === 'supervision') ? '.active' : ''),
                    { type: 'button', 'data-nav': id, onclick: () => go(id) }, text)));
                clear(roleBar);
                const r = (st.me && st.me.roles) || {};
                ['judge', 'clerk', 'prosecutor', 'defender', 'probation', 'admin'].forEach((k) => { if (r[k]) roleBar.appendChild(h('span.pf-badge.accent', label(k))); });
                if (!r.court && r.warrants && !r.judge) roleBar.appendChild(h('span.pf-badge.warn', 'warrant fallback'));
            }
            function go(view, opts) {
                st.view = view;
                if (opts && opts.caseId) st.caseId = opts.caseId;
                renderNav();
                const fn = VIEWS[view];
                clear(main);
                if (fn) fn(opts || {});
            }

            // ── docket ──
            async function docket() {
                const d = st.docket;
                const now = Math.floor(Date.now() / 1000);
                const range = select([['1', 'Today and tomorrow'], ['7', 'Next 7 days'], ['30', 'Next 30 days']], String(d.range));
                const state = select([['scheduled', 'Scheduled'], ['held', 'Held'], ['auto', 'Passed to the schedule'], ['cancelled', 'Cancelled']], d.state);
                const rooms = select([['', 'All courtrooms']].concat(st.me.courtrooms.map((c) => [c.id, c.label])), d.courtroom);
                const list = h('div', loading());
                const apply = () => { d.range = Number(range.value); d.state = state.value; d.courtroom = rooms.value; docket(); };
                [range, state, rooms].forEach((s) => s.addEventListener('change', apply));
                main.appendChild(h('div.pf-toolbar', range, state, rooms, h('button.pf-btn.sm.ghost', { type: 'button', onclick: docket }, 'Refresh')));
                main.appendChild(list);
                const from = d.state === 'scheduled' ? now - 3600 : now - d.range * 86400;
                const to = d.state === 'scheduled' ? now + d.range * 86400 : now + 3600;
                const res = await ctx.rpc('docket', { from, to, state: d.state, courtroom: d.courtroom || undefined });
                if (st.view !== 'docket') return;
                clear(list);
                if (!res || !res.ok) { list.appendChild(failed(res, docket)); return; }
                if (!res.list.length) { list.appendChild(h('div.pf-empty', 'No hearings in this range.')); return; }
                list.appendChild(h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['When', 'Case', 'Defendant', 'Hearing', 'Courtroom', 'State'].map((t) => h('th', t)))),
                    h('tbody', res.list.map((x) => pickRow([
                        h('td', fmt(x.at)), h('td', x.caseNo || ('#' + x.caseId)), h('td', x.name || x.cid || ''),
                        h('td', label(x.kind)), h('td', x.courtroomLabel || x.courtroom || ''), h('td', badge(x.state)),
                    ], () => { st.back = 'docket'; go('case', { caseId: x.caseId }); }))))));
            }

            // ── cases ──
            async function cases() {
                const c = st.cases;
                const q = h('input.pf-input', { type: 'search', placeholder: 'Case number, citizen id or name', maxlength: '40', value: c.q, 'aria-label': 'Search cases' });
                const scope = select([['open', 'Open'], ['mine', 'My cases'], ['closed', 'Closed'], ['all', 'All']], c.scope);
                const kind = select([['', 'Every kind'], ['criminal', 'Criminal'], ['violation', 'Violation'], ['citation_contest', 'Citation contest'], ['appeal', 'Appeal']], c.kind);
                const sort = select([['filed_desc', 'Newest first'], ['filed_asc', 'Oldest first'], ['case_no', 'Case number']], c.sort);
                const list = h('div', loading());
                const apply = () => { c.q = q.value.trim(); c.scope = scope.value; c.kind = kind.value; c.sort = sort.value; c.page = 1; cases(); };
                [scope, kind, sort].forEach((s) => s.addEventListener('change', apply));
                main.appendChild(h('form.pf-toolbar', { onsubmit: (e) => { e.preventDefault(); apply(); } }, q, h('button.pf-btn.sm', { type: 'submit' }, 'Search'), scope, kind, sort));
                main.appendChild(list);
                const res = await ctx.rpc('cases', { q: c.q || undefined, scope: c.scope, kind: c.kind || undefined, sort: c.sort, page: c.page });
                if (st.view !== 'cases') return;
                clear(list);
                if (!res || !res.ok) { list.appendChild(failed(res, cases)); return; }
                c.more = !!res.more;
                if (!res.list.length) { list.appendChild(h('div.pf-empty', 'No cases match.')); return; }
                list.appendChild(h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['Case', 'Defendant', 'Kind', 'State', 'Filed'].map((t) => h('th', t)))),
                    h('tbody', res.list.map((x) => pickRow([
                        h('td', x.caseNo || ('#' + x.id)), h('td', x.name || x.cid || '', x.name ? h('div.pf-small.pf-muted', x.cid) : null),
                        h('td', label(x.kind)), h('td', badge(x.state)), h('td', fmt(x.filedAt)),
                    ], () => { st.back = 'cases'; go('case', { caseId: x.id }); }))))));
                list.appendChild(pager(c, cases));
            }

            // ── one case ──
            async function caseView() {
                const id = st.caseId;
                main.appendChild(h('div.pf-toolbar', h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => go(st.back || 'cases') }, '← Back'),
                    h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => go('case', { caseId: id }) }, 'Refresh')));
                const box = h('div', loading());
                main.appendChild(box);
                const res = await ctx.rpc('case', { id });
                if (st.view !== 'case' || st.caseId !== id) return;
                clear(box);
                if (!res || !res.ok) { box.appendChild(failed(res, () => go('case', { caseId: id }))); return; }
                const c = res.case;
                const can = res.can || {};
                box.appendChild(h('div.pf-card',
                    h('div.pf-row.between', h('div.pf-strong', c.caseNo || ('Case #' + c.id)), badge(c.state)),
                    h('dl.ju-kv',
                        h('dt', 'Defendant'), h('dd', c.name || c.cid || '', c.name ? ` (${c.cid})` : ''),
                        h('dt', 'Kind'), h('dd', label(c.kind)),
                        h('dt', 'Filed'), h('dd', fmt(c.filedAt), c.filedBy ? ` by ${c.filedBy}` : ''),
                        h('dt', 'Judge'), h('dd', c.judgeName || c.judgeCid || '-'),
                        h('dt', 'Prosecutor'), h('dd', c.prosecutorName || c.prosecutorCid || '-'),
                        h('dt', 'Defender'), h('dd', c.defenderName || c.defenderCid || '-'),
                        c.closedAt ? [h('dt', 'Closed'), h('dd', fmt(c.closedAt))] : null)));
                box.appendChild(h('div.ju-section', 'Charges'));
                const charges = Array.isArray(c.charges) ? c.charges : [];
                box.appendChild(charges.length ? h('ul.pf-list', charges.map((x) => h('li.pf-list-item',
                    [x.code, x.label].filter(Boolean).join(' '), x.count > 1 ? ` ×${x.count}` : '', x.class ? h('span.pf-small.pf-muted', ` (${x.class})`) : null)))
                    : h('div.pf-empty', 'No charges listed.'));
                box.appendChild(h('div.ju-section', 'Hearings'));
                box.appendChild(c.hearings.length ? h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['When', 'Hearing', 'Courtroom', 'State', 'Notes'].map((t) => h('th', t)))),
                    h('tbody', c.hearings.map((x) => h('tr', h('td', fmt(x.at)), h('td', label(x.kind)), h('td', x.courtroomLabel || x.courtroom || ''),
                        h('td', badge(x.state)), h('td.ju-note', x.notes || '')))))) : h('div.pf-empty', 'No hearings yet.'));
                box.appendChild(h('div.ju-section', 'Decisions'));
                box.appendChild(c.decisions.length ? h('ul.pf-list', c.decisions.map((d) => h('li.pf-list-item',
                    h('div.pf-row.between', h('span.pf-strong', label(d.kind)), h('span.pf-small.pf-muted', fmt(d.at) + ' · ' + (d.decidedBy || ''))),
                    h('div.ju-note.pf-small', describeDecision(d)))))
                    : h('div.pf-empty', 'No decisions yet.'));
                if (c.refs && c.refs.length) {
                    box.appendChild(h('div.ju-section', 'Linked records'));
                    box.appendChild(h('div.ju-actions', c.refs.map((r) => h('span.pf-badge', `${label(r.type)} ${r.id}`))));
                }
                if (can.schedule) box.appendChild(scheduleForm(c));
                if (can.decide || can.dismiss || can.appeal) box.appendChild(decisionForm(c, can));
                if (can.courtOrder) {
                    box.appendChild(h('div.ju-actions', { style: { marginTop: '12px' } },
                        h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => go('orders', { issue: { cid: c.cid, caseId: c.id } }) }, 'Issue a court order for this case')));
                }
            }

            function describeDecision(d) {
                const b = d.body || {};
                const parts = [];
                if (b.plea) parts.push('Plea: ' + label(b.plea));
                if (b.verdict) parts.push('Verdict: ' + label(b.verdict));
                if (Array.isArray(b.orders)) parts.push('Orders: ' + b.orders.map((o) => [label(o.kind), o.minutes && `${o.minutes} min`, o.amount && `$${o.amount}`,
                    o.units && `${o.units} units`, o.days && `${o.days} days`].filter(Boolean).join(' ')).join('; '));
                if (b.denied) parts.push('Bail denied');
                else if (b.amount === 0) parts.push('Own recognizance');
                else if (b.amount) parts.push('Bail $' + b.amount);
                if (b.reason) parts.push(b.reason);
                if (b.outcome) parts.push('Appeal: ' + label(b.outcome));
                if (d.orderIds) parts.push('Order ids: ' + d.orderIds);
                if (b.note) parts.push(b.note);
                return parts.join(' · ');
            }

            function scheduleForm(c) {
                const key = keyed('hearing');
                const kind = select(st.me.hearingKinds.map((k) => [k, label(k)]));
                const at = h('input.pf-input', { type: 'datetime-local', value: inputTime(Math.floor(Date.now() / 1000) + 3600), required: true });
                const room = select(st.me.courtrooms.map((r) => [r.id, r.label]));
                const notes = h('textarea.pf-textarea', { rows: '2', maxlength: '1000', placeholder: 'Notes for the parties (optional)' });
                const err = h('div.ju-error', { role: 'alert' });
                const btn = h('button.pf-btn.primary', { type: 'submit' }, 'Schedule hearing');
                const form = h('form.pf-card.ju-form', h('div.ju-section', 'Schedule a hearing'),
                    h('div.pf-row', field('Hearing', kind), field('When', at), field('Courtroom', room)), field('Notes', notes), err, h('div.pf-row', btn));
                form.addEventListener('submit', async (e) => {
                    const res = await submitter(btn, err, async () => {
                        const when = toUnix(at.value);
                        if (!when) return { ok: false, error: 'bad_args', message: 'Pick a date and time' };
                        const r = await ctx.rpc('schedule', { caseId: c.id, kind: kind.value, at: when, courtroom: room.value, notes: notes.value, key: await key.get() });
                        key.settle(r);
                        return r;
                    })(e);
                    if (res) { ctx.notify(res.duplicate ? 'Already scheduled' : 'Hearing scheduled; the parties were told', 'success'); go('case', { caseId: c.id }); }
                });
                return form;
            }

            // one order of a sentence: kind plus the fields that kind needs (the server validates every value)
            function orderLine(remove) {
                const kind = select(st.me.sentenceKinds.map((k) => [k, label(k)]));
                const minutes = h('input.pf-input', { type: 'number', min: '1', step: '1', placeholder: 'Minutes' });
                const amount = h('input.pf-input', { type: 'number', min: '1', step: '1', placeholder: 'Amount ($)' });
                const victim = h('input.pf-input', { maxlength: '64', placeholder: 'Victim citizen id' });
                const units = h('input.pf-input', { type: 'number', min: '1', step: '1', placeholder: 'Units' });
                const days = h('input.pf-input', { type: 'number', min: '1', step: '1', placeholder: 'Days' });
                const facility = h('select.pf-select');
                const checkin = h('input.pf-input', { type: 'number', min: '1', step: '1', placeholder: 'Check in every N days' });
                const noWeapons = h('input', { type: 'checkbox' });
                const noAlcohol = h('input', { type: 'checkbox' });
                const fields = {
                    minutes: field('Minutes', minutes), facility: field('Facility', facility), amount: field('Amount', amount), victim: field('Victim', victim),
                    units: field('Units', units), days: field('Days', days), checkin: field('Check-in', checkin),
                    conds: h('div.pf-row', h('label.pf-small', noWeapons, ' No weapons'), h('label.pf-small', noAlcohol, ' No alcohol')),
                };
                const NEEDS = { jail: ['minutes', 'facility'], prison: ['minutes', 'facility'], fine: ['amount'], restitution: ['amount', 'victim'],
                    community_service: ['units'], probation: ['days', 'checkin', 'conds'], parole: ['days', 'checkin', 'conds'] };
                function show() {
                    Object.values(fields).forEach((f) => { f.style.display = 'none'; });
                    (NEEDS[kind.value] || []).forEach((k) => { fields[k].style.display = ''; });
                    clear(facility);
                    st.me.facilities.filter((f) => f.kinds.indexOf(kind.value) !== -1).forEach((f) => facility.appendChild(h('option', { value: f.id }, f.label)));
                }
                kind.addEventListener('change', show);
                const el = h('div.ju-orderline', field('Order', kind), Object.values(fields),
                    h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => remove(el), 'aria-label': 'Remove this order' }, 'Remove'));
                show();
                el.read = () => {
                    const o = { kind: kind.value };
                    const n = (v) => (v === '' ? undefined : Number(v));
                    if (o.kind === 'jail' || o.kind === 'prison') { o.minutes = n(minutes.value); o.facility = facility.value || undefined; }
                    if (o.kind === 'fine' || o.kind === 'restitution') o.amount = n(amount.value);
                    if (o.kind === 'restitution') o.victimCid = victim.value.trim();
                    if (o.kind === 'community_service') o.units = n(units.value);
                    if (o.kind === 'probation' || o.kind === 'parole') {
                        o.days = n(days.value);
                        const cond = [];
                        if (checkin.value) cond.push({ kind: 'checkin', everyDays: Number(checkin.value) });
                        if (noWeapons.checked) cond.push({ kind: 'no_weapons' });
                        if (noAlcohol.checked) cond.push({ kind: 'no_alcohol' });
                        if (cond.length) o.conditions = cond;
                    }
                    return o;
                };
                return el;
            }

            function decisionForm(c, can) {
                const key = keyed('decision');
                const kinds = [];
                if (can.decide) st.me.decisionKinds.forEach((k) => kinds.push(k));
                else if (can.dismiss) kinds.push('dismissal');
                if (can.appeal && kinds.indexOf('appeal') === -1) kinds.push('appeal');
                const kind = select(kinds.map((k) => [k, label(k)]));
                const plea = select([['not_guilty', 'Not guilty'], ['guilty', 'Guilty']]);
                const verdict = select([['guilty', 'Guilty'], ['acquitted', 'Acquitted']]);
                const outcome = select(can.decide ? [['filed', 'Appeal filed'], ['affirmed', 'Affirmed'], ['reversed', 'Reversed']] : [['filed', 'Appeal filed']]);
                const amount = h('input.pf-input', { type: 'number', min: '0', step: '1', placeholder: '0 = own recognizance' });
                const denied = h('input', { type: 'checkbox' });
                const reason = h('input.pf-input', { maxlength: '200', placeholder: 'Reason' });
                const note = h('textarea.pf-textarea', { rows: '2', maxlength: '1000', placeholder: 'Note (recorded with the decision)' });
                const lines = h('div.pf-stack');
                const removeLine = (el) => el.remove();
                const addLine = h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => { if (lines.children.length < 10) lines.appendChild(orderLine(removeLine)); } }, 'Add order');
                const parts = {
                    plea: field('Plea', plea), verdict: field('Verdict', verdict), outcome: field('Appeal', outcome),
                    bail: h('div.pf-row', field('Bail amount', amount), h('label.pf-small', denied, ' Bail denied (remand)')),
                    sentence: h('div.pf-stack', lines, addLine), release: field('Reason', reason),
                };
                const PART = { plea: 'plea', verdict: 'verdict', appeal: 'outcome', bail: 'bail', sentence: 'sentence', release_order: 'release' };
                function show() {
                    Object.values(parts).forEach((p) => { p.style.display = 'none'; });
                    if (PART[kind.value]) parts[PART[kind.value]].style.display = '';
                    if (kind.value === 'sentence' && !lines.children.length) lines.appendChild(orderLine(removeLine));
                }
                kind.addEventListener('change', show);
                const err = h('div.ju-error', { role: 'alert' });
                const btn = h('button.pf-btn.primary', { type: 'submit' }, 'Record decision');
                const form = h('form.pf-card.ju-form', h('div.ju-section', 'Record a decision'), field('Decision', kind), Object.values(parts), field('Note', note), err, h('div.pf-row', btn));
                show();
                form.addEventListener('submit', async (e) => {
                    const res = await submitter(btn, err, async () => {
                        const d = { kind: kind.value, note: note.value };
                        if (d.kind === 'plea') d.plea = plea.value;
                        if (d.kind === 'verdict') d.verdict = verdict.value;
                        if (d.kind === 'appeal') d.outcome = outcome.value;
                        if (d.kind === 'bail') { d.denied = denied.checked; if (!d.denied) d.amount = amount.value === '' ? undefined : Number(amount.value); }
                        if (d.kind === 'release_order') d.reason = reason.value;
                        if (d.kind === 'sentence') d.orders = Array.from(lines.children).map((l) => l.read());
                        const r = await ctx.rpc('decide', { caseId: c.id, decision: d, key: await key.get() });
                        key.settle(r);
                        return r;
                    })(e);
                    if (res) { ctx.notify(res.duplicate ? 'This decision was already recorded' : 'Decision recorded', 'success'); go('case', { caseId: c.id }); }
                });
                return form;
            }

            // ── file a case ──
            function fileView() {
                const key = keyed('file');
                const cid = h('input.pf-input', { maxlength: '64', placeholder: 'Citizen id', required: true });
                const kind = select([['criminal', 'Criminal'], ['violation', 'Violation'], ['citation_contest', 'Citation contest']]);
                const title = h('input.pf-input', { maxlength: '120', placeholder: 'Short title' });
                const note = h('textarea.pf-textarea', { rows: '3', maxlength: '1000', placeholder: 'Summary for the court' });
                const charges = h('div.pf-stack');
                function chargeLine() {
                    const code = h('input.pf-input', { maxlength: '24', placeholder: 'Code (PC-484)' });
                    const text = h('input.pf-input', { maxlength: '100', placeholder: 'Charge' });
                    const count = h('input.pf-input', { type: 'number', min: '1', max: '99', value: '1' });
                    const cls = select([['', 'Class from the code'], ['infraction', 'Infraction'], ['misdemeanor', 'Misdemeanor'], ['felony', 'Felony']]);
                    const el = h('div.ju-orderline', field('Code', code), field('Charge', text), field('Count', count), field('Class', cls),
                        h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => el.remove() }, 'Remove'));
                    el.read = () => ({ code: code.value.trim() || undefined, label: text.value.trim() || undefined, count: Number(count.value) || 1, class: cls.value || undefined });
                    return el;
                }
                charges.appendChild(chargeLine());
                const err = h('div.ju-error', { role: 'alert' });
                const btn = h('button.pf-btn.primary', { type: 'submit' }, 'File case');
                const form = h('form.pf-card.ju-form', h('div.ju-section', 'File a case'),
                    h('div.ju-hint', 'Police cases arrive from the MDT with their evidence. File here for matters the court opens itself.'),
                    h('div.pf-row', field('Defendant', cid), field('Kind', kind)), field('Title', title),
                    h('div.ju-section', 'Charges'), charges,
                    h('div', h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => { if (charges.children.length < 50) charges.appendChild(chargeLine()); } }, 'Add charge')),
                    field('Summary', note), err, h('div.pf-row', btn));
                form.addEventListener('submit', async (e) => {
                    const res = await submitter(btn, err, async () => {
                        const list = Array.from(charges.children).map((l) => l.read()).filter((x) => x.code || x.label);
                        const r = await ctx.rpc('file', { cid: cid.value.trim(), kind: kind.value, title: title.value, note: note.value, charges: list, key: await key.get() });
                        key.settle(r);
                        return r;
                    })(e);
                    if (res) { ctx.notify(`Case ${res.caseNo || res.caseId} filed`, 'success'); st.back = 'cases'; go('case', { caseId: res.caseId }); }
                });
                main.appendChild(form);
            }

            // ── warrant reviews ──
            async function warrants() {
                const w = st.warrants;
                const judge = st.me.roles.judge;
                const tabs = h('div.pf-toolbar', (judge ? ['requested', 'needs_info', 'approved', 'denied'] : ['requested']).map((s) =>
                    h('button.pf-btn.sm' + (w.state === s ? '.primary' : '.ghost'), { type: 'button', onclick: () => { w.state = s; w.page = 1; warrants(); } }, label(s))));
                clear(main);
                main.appendChild(tabs);
                if (!judge) main.appendChild(h('div.ju-hint', 'No judge has been on duty for a while: you may decide reviews you did not request (warrant fallback).'));
                const list = h('div', loading());
                main.appendChild(list);
                const res = await ctx.rpc('warrants', { state: w.state, page: w.page });
                if (st.view !== 'warrants') return;
                clear(list);
                if (!res || !res.ok) { list.appendChild(failed(res, warrants)); return; }
                w.more = !!res.more;
                if (!res.list.length) { list.appendChild(h('div.pf-empty', 'No warrant reviews here.')); return; }
                res.list.forEach((r) => list.appendChild(reviewCard(r)));
                list.appendChild(pager(w, warrants));
            }
            function reviewCard(r) {
                const card = h('div.pf-card', { style: { marginBottom: '10px' } },
                    h('div.pf-row.between', h('span.pf-strong', `#${r.id} · ${label(r.type)} warrant ${r.warrantId}`), badge(r.state)),
                    h('dl.ju-kv',
                        h('dt', 'Subject'), h('dd', r.targetName || r.targetCid || r.address || '-'),
                        r.address ? [h('dt', 'Address'), h('dd', r.address)] : null,
                        h('dt', 'Requested'), h('dd', fmt(r.requestedAt), ' by ', r.requestedByName || r.requestedBy || ''),
                        r.decidedAt ? [h('dt', 'Decided'), h('dd', fmt(r.decidedAt), ' by ', r.judgeCid || '')] : null,
                        r.note ? [h('dt', 'Note'), h('dd.ju-note', r.note)] : null),
                    h('div.ju-section', 'Affidavit'), h('div.ju-note.pf-small', r.affidavit || '(empty)'));
                if (r.canDecide) {
                    const decision = select([['approve', 'Approve'], ['deny', 'Deny'], ['needs_info', 'Ask for more information']]);
                    const note = h('input.pf-input', { maxlength: '500', placeholder: 'Note (required to deny or ask for more)' });
                    const err = h('div.ju-error', { role: 'alert' });
                    const btn = h('button.pf-btn.primary.sm', { type: 'submit' }, 'Decide');
                    const form = h('form.ju-form', h('div.pf-row', field('Decision', decision), field('Note', note), btn), err);
                    form.addEventListener('submit', async (e) => {
                        const res = await submitter(btn, err, () => ctx.rpc('decideWarrant', { reviewId: r.id, decision: decision.value, note: note.value }))(e);
                        if (res) { ctx.notify(res.notified === false ? `Review ${label(res.state)} (the MDT is told when it is back)` : `Review ${label(res.state)}`, 'success'); warrants(); }
                    });
                    card.appendChild(form);
                }
                return card;
            }

            // ── court orders ──
            async function orders(opts) {
                const o = st.orders;
                const judge = st.me.roles.judge;
                main.appendChild(h('div.pf-toolbar', ['active', 'all'].map((s) =>
                    h('button.pf-btn.sm' + (o.scope === s ? '.primary' : '.ghost'), { type: 'button', onclick: () => { o.scope = s; o.page = 1; go('orders'); } }, s === 'active' ? 'Valid now' : 'All'))));
                if (judge) main.appendChild(issueForm((opts && opts.issue) || {}));
                const list = h('div', loading());
                main.appendChild(list);
                const res = await ctx.rpc('courtOrders', { scope: o.scope, page: o.page });
                if (st.view !== 'orders') return;
                clear(list);
                if (!res || !res.ok) { list.appendChild(failed(res, () => go('orders'))); return; }
                o.more = !!res.more;
                if (!res.list.length) { list.appendChild(h('div.pf-empty', 'No court orders.')); return; }
                list.appendChild(h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['Ref', 'Purpose', 'Person', 'Valid until', 'Detail', ''].map((t) => h('th', t)))),
                    h('tbody', res.list.map((x) => h('tr',
                        h('td', x.ref), h('td', label(x.kind)), h('td', x.name || x.cid || '-'),
                        h('td', x.revokedAt ? badge('revoked') : (x.validUntil ? fmt(x.validUntil) : '-')),
                        h('td.ju-note.pf-small', [x.evidenceIds && x.evidenceIds.length ? 'Evidence ' + x.evidenceIds.join(', ') : '', x.tags && x.tags.length ? 'Tags ' + x.tags.join(', ') : '',
                            x.address || '', x.reason || '', x.note || ''].filter(Boolean).join(' · ')),
                        h('td', judge && !x.revokedAt && x.kind !== 'release' ? revokeButton(x) : null)))))));
                list.appendChild(pager(o, () => go('orders')));
            }
            function revokeButton(x) {
                const reason = h('input.pf-input', { maxlength: '200', placeholder: 'Reason' });
                const err = h('div.ju-error', { role: 'alert' });
                const btn = h('button.pf-btn.sm.danger', { type: 'submit' }, 'Revoke');
                const form = h('form.pf-row', reason, btn, err);
                form.addEventListener('submit', async (e) => {
                    const res = await submitter(btn, err, () => ctx.rpc('revokeOrder', { ref: x.ref, reason: reason.value }))(e);
                    if (res) { ctx.notify(`Court order ${x.ref} revoked`, 'success'); go('orders'); }
                });
                return form;
            }
            function issueForm(pre) {
                const key = keyed('courtorder');
                const kind = select(st.me.courtOrderKinds.map((k) => [k, label(k)]));
                const cid = h('input.pf-input', { maxlength: '64', placeholder: 'Citizen id', value: pre.cid || '' });
                const caseId = h('input.pf-input', { type: 'number', min: '1', placeholder: 'Case #', value: pre.caseId || '' });
                const hours = h('input.pf-input', { type: 'number', min: '1', max: String(st.me.maxOrderHours), placeholder: 'Hours (default 72)' });
                const evidence = h('input.pf-input', { maxlength: '400', placeholder: 'Evidence ids, comma separated' });
                const tags = h('input.pf-input', { maxlength: '400', placeholder: 'Evidence tags, comma separated' });
                const address = h('input.pf-input', { maxlength: '128', placeholder: 'Address (search orders)' });
                const note = h('input.pf-input', { maxlength: '500', placeholder: 'Note' });
                const err = h('div.ju-error', { role: 'alert' });
                const btn = h('button.pf-btn.primary', { type: 'submit' }, 'Issue court order');
                const form = h('form.pf-card.ju-form', { style: { marginBottom: '12px' } }, h('div.ju-section', 'Issue a court order'),
                    h('div.pf-row', field('Purpose', kind), field('Person', cid), field('Case', caseId), field('Valid for', hours)),
                    h('div.pf-row', field('Evidence ids', evidence), field('Evidence tags', tags)), h('div.pf-row', field('Address', address), field('Note', note)), err, h('div.pf-row', btn));
                form.addEventListener('submit', async (e) => {
                    const res = await submitter(btn, err, async () => {
                        const r = await ctx.rpc('issueOrder', { kind: kind.value, cid: cid.value.trim() || undefined, caseId: caseId.value ? Number(caseId.value) : undefined,
                            hours: hours.value ? Number(hours.value) : undefined, evidenceIds: evidence.value.trim() || undefined, tags: tags.value.trim() || undefined,
                            address: address.value || undefined, note: note.value || undefined, key: await key.get() });
                        key.settle(r);
                        return r;
                    })(e);
                    if (res) { ctx.notify(`Court order ${res.ref} issued, valid until ${fmt(res.validUntil)}`, 'success'); go('orders'); }
                });
                return form;
            }

            // ── probation ──
            async function probation() {
                const c = st.caseload;
                const lookup = h('input.pf-input', { maxlength: '64', placeholder: 'Citizen id', 'aria-label': 'Open a supervision by citizen id' });
                main.appendChild(h('form.pf-toolbar', { onsubmit: (e) => { e.preventDefault(); if (lookup.value.trim()) go('supervision', { cid: lookup.value.trim() }); } },
                    ['mine', 'unassigned', 'all'].map((s) => h('button.pf-btn.sm' + (c.scope === s ? '.primary' : '.ghost'), { type: 'button', onclick: () => { c.scope = s; c.page = 1; go('probation'); } }, label(s))),
                    lookup, h('button.pf-btn.sm', { type: 'submit' }, 'Open')));
                const list = h('div', loading());
                main.appendChild(list);
                const res = await ctx.rpc('caseload', { scope: c.scope, page: c.page });
                if (st.view !== 'probation') return;
                clear(list);
                if (!res || !res.ok) { list.appendChild(failed(res, () => go('probation'))); return; }
                c.more = !!res.more;
                if (!res.list.length) { list.appendChild(h('div.pf-empty', 'Nobody on this list.')); return; }
                const now = Date.now() / 1000;
                list.appendChild(h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['Citizen', 'Order', 'State', 'Next check-in', 'Ends', 'Monitor'].map((t) => h('th', t)))),
                    h('tbody', res.list.map((x) => pickRow([
                        h('td', x.name || x.cid, x.name ? h('div.pf-small.pf-muted', x.cid) : null), h('td', `${label(x.kind)} #${x.orderId}`), h('td', badge(x.state)),
                        h('td', x.nextCheckinAt ? fmt(x.nextCheckinAt) : '-', x.nextCheckinAt && x.nextCheckinAt < now ? h('span.ju-st.bad', ' overdue') : null),
                        h('td', fmt(x.endsAt)), h('td', x.monitored ? badge('active') : '-'),
                    ], () => go('supervision', { cid: x.cid })))))));
                list.appendChild(pager(c, () => go('probation')));
            }

            async function supervision(opts) {
                const cid = (opts && opts.cid) || st.supCid;
                st.supCid = cid;
                main.appendChild(h('div.pf-toolbar', h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => go('probation') }, '← Caseload'),
                    h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => go('supervision', { cid }) }, 'Refresh')));
                const box = h('div', loading());
                main.appendChild(box);
                const res = await ctx.rpc('supervision', { cid });
                if (st.view !== 'supervision' || st.supCid !== cid) return;
                clear(box);
                if (!res || !res.ok) { box.appendChild(failed(res, () => go('supervision', { cid }))); return; }
                const s = res.supervision;
                if (!s) { box.appendChild(h('div.pf-empty', `${res.name || cid} has no open probation or parole.`)); return; }
                box.appendChild(h('div.pf-card',
                    h('div.pf-row.between', h('span.pf-strong', `${res.name || cid} · ${label(s.kind)} #${s.orderId}`), badge(s.state)),
                    h('dl.ju-kv', h('dt', 'Ends'), h('dd', fmt(s.endsAt)), h('dt', 'Next check-in'), h('dd', fmt(s.nextCheckinAt)),
                        h('dt', 'Officer'), h('dd', s.officerCid || 'unassigned'), h('dt', 'Monitor'), h('dd', s.monitor ? label(s.monitor.mode) : 'none'))));
                box.appendChild(h('div.ju-section', 'Conditions'));
                const conds = s.conditions || [];
                box.appendChild(conds.length ? h('div.ju-actions', conds.map((c) => h('span.pf-badge', [label(c.kind), c.everyDays && `every ${c.everyDays} d`,
                    c.from && `${c.from}-${c.to}`, typeof c.zone === 'string' && c.zone].filter(Boolean).join(' ')))) : h('div.pf-empty', 'No conditions.'));
                const events = (title, list, render) => {
                    box.appendChild(h('div.ju-section', title));
                    box.appendChild(list && list.length ? h('ul.pf-list', list.map(render)) : h('div.pf-empty', 'None.'));
                };
                events('Appointments', s.appointments, (a) => h('li.pf-list-item', h('div.pf-row.between', h('span', fmt(a.dueAt), ' · ', (a.detail && a.detail.location) || ''), badge(a.state)),
                    a.detail && a.detail.note ? h('div.pf-small.ju-note', a.detail.note) : null));
                events('Check-ins', s.checkins, (a) => h('li.pf-list-item', fmt(a.doneAt || a.at), ' · ', label(a.detail && a.detail.where), a.detail && a.detail.location ? ` (${a.detail.location})` : ''));
                events('Violation reports', s.violations, (v) => h('li.pf-list-item', h('div.pf-row.between', h('span.pf-strong', (v.detail && v.detail.label) || 'Violation'), badge(v.state)),
                    h('div.pf-small.pf-muted', fmt(v.at), ' · ', label(v.detail && v.detail.source)), v.detail && v.detail.note ? h('div.pf-small.ju-note', v.detail.note) : null));
                events('Notes', s.notes, (n) => h('li.pf-list-item', fmt(n.at), ' · ', label(n.detail && n.detail.action), n.detail && n.detail.mode ? ` (${label(n.detail.mode)})` : ''));
                if (s.state === 'active') box.appendChild(probationActions(cid, s));
            }

            function probationActions(cid, s) {
                const wrap = h('div.ju-grid2', { style: { marginTop: '12px' } });
                // appointment
                {
                    const key = keyed('appointment');
                    const at = h('input.pf-input', { type: 'datetime-local', value: inputTime(Math.floor(Date.now() / 1000) + 86400) });
                    const office = select(st.me.offices.map((o) => [String(o.id), o.label]));
                    const minutes = h('input.pf-input', { type: 'number', min: '15', max: '240', value: '30' });
                    const note = h('input.pf-input', { maxlength: '500', placeholder: 'Note for the citizen' });
                    const err = h('div.ju-error', { role: 'alert' });
                    const btn = h('button.pf-btn.primary.sm', { type: 'submit' }, 'Schedule');
                    const form = h('form.pf-card.ju-form', h('div.ju-section', 'Appointment'), field('When', at), field('Office', office), field('Minutes', minutes), field('Note', note), err, h('div', btn));
                    form.addEventListener('submit', async (e) => {
                        const res = await submitter(btn, err, async () => {
                            const r = await ctx.rpc('appointment', { supId: s.id, at: toUnix(at.value), office: Number(office.value), minutes: Number(minutes.value), note: note.value, key: await key.get() });
                            key.settle(r);
                            return r;
                        })(e);
                        if (res) { ctx.notify('Appointment scheduled; the citizen was told', 'success'); go('supervision', { cid }); }
                    });
                    wrap.appendChild(form);
                }
                // field check-in
                {
                    const err = h('div.ju-error', { role: 'alert' });
                    const btn = h('button.pf-btn.sm', { type: 'button' }, 'Record check-in');
                    btn.addEventListener('click', async () => {
                        const res = await submitter(btn, err, () => ctx.rpc('checkIn', { supId: s.id }))();
                        if (res) { ctx.notify('Check-in recorded', 'success'); go('supervision', { cid }); }
                    });
                    wrap.appendChild(h('div.pf-card.ju-form', h('div.ju-section', 'Check-in'),
                        h('div.ju-hint', 'Stand next to the citizen, or meet them at a probation office. Positions are read by the server.'), err, h('div', btn)));
                }
                // violation report
                {
                    const key = keyed('violation');
                    const kind = select(st.me.violationTypes.map((v) => [v.id, v.label]));
                    const note = h('textarea.pf-textarea', { rows: '2', maxlength: '500', placeholder: 'What happened' });
                    const err = h('div.ju-error', { role: 'alert' });
                    const btn = h('button.pf-btn.danger.sm', { type: 'submit' }, 'Report violation');
                    const form = h('form.pf-card.ju-form', h('div.ju-section', 'Violation report'), field('Type', kind), field('Note', note),
                        h('div.ju-hint', 'A report for the supervising officer and the court; nothing happens to the citizen automatically.'), err, h('div', btn));
                    form.addEventListener('submit', async (e) => {
                        const res = await submitter(btn, err, async () => {
                            const r = await ctx.rpc('violation', { supId: s.id, kind: kind.value, note: note.value, key: await key.get() });
                            key.settle(r);
                            return r;
                        })(e);
                        if (res) { ctx.notify('Violation reported', 'success'); go('supervision', { cid }); }
                    });
                    wrap.appendChild(form);
                }
                // monitor
                {
                    const mode = select([['track', 'Track only'], ['home', 'Home zone'], ['curfew', 'Curfew at home']]);
                    const house = h('input.pf-input', { maxlength: '64', placeholder: 'House id the citizen owns' });
                    const zone = select([['', 'No configured zone']].concat(st.me.zones.map((z) => [z.id, z.label])));
                    const from = h('input.pf-input', { type: 'time' });
                    const to = h('input.pf-input', { type: 'time' });
                    const err = h('div.ju-error', { role: 'alert' });
                    const btn = h('button.pf-btn.sm', { type: 'submit' }, 'Fit monitor');
                    const remove = h('button.pf-btn.sm.ghost', { type: 'button' }, 'Remove monitor');
                    const form = h('form.pf-card.ju-form', h('div.ju-section', 'Electronic monitor'), field('Mode', mode), h('div.pf-row', field('House', house), field('Zone', zone)),
                        h('div.pf-row', field('Curfew from', from), field('Curfew to', to)), err, h('div.ju-actions', btn, s.monitored ? remove : null));
                    form.addEventListener('submit', async (e) => {
                        const res = await submitter(btn, err, () => ctx.rpc('monitor', { cid, mode: mode.value, house: house.value.trim() || undefined,
                            zone: zone.value || undefined, from: from.value || undefined, to: to.value || undefined }))(e);
                        if (res) { ctx.notify('Monitor fitted', 'success'); go('supervision', { cid }); }
                    });
                    remove.addEventListener('click', async () => {
                        const res = await submitter(remove, err, () => ctx.rpc('monitor', { cid, remove: true }))();
                        if (res) { ctx.notify('Monitor removed', 'success'); go('supervision', { cid }); }
                    });
                    wrap.appendChild(form);
                }
                return wrap;
            }

            const VIEWS = { docket, cases, case: caseView, file: fileView, warrants, orders, probation, supervision };

            // live updates from the server (ids only)
            ctx.on('caseChanged', (p) => {
                if (st.view === 'docket' || st.view === 'cases') VIEWS[st.view]();
                else if (st.view === 'case' && p && Number(p.caseId) === Number(st.caseId)) go('case', { caseId: st.caseId });
            });
            ctx.on('warrantChanged', () => { if (st.view === 'warrants') warrants(); });

            (async function start() {
                clear(main).appendChild(loading());
                const me = await ctx.rpc('me');
                clear(main);
                if (!me || !me.ok) { main.appendChild(failed(me, start)); return; }
                st.me = me;
                const first = allowed()[0];
                if (!first) {
                    renderNav();
                    main.appendChild(h('div.pf-empty', me.offDuty ? 'Go on duty to use the court tools.' : 'You hold no court role.'));
                    return;
                }
                go(first[0]);
            })();
        },
    });
})();
