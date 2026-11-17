// Justice Records (pf-devices module, tablet and computer): the citizen's own criminal record, court dates
// and cases, the sentence clock, probation and community service, fines (paid through the justice order's
// keyed payment on the bank ledger) and a complaint to Internal Affairs. The server reads who the citizen is
// from the player; nothing here can name another person's record.
(function () {
    'use strict';

    const ERRORS = {
        insufficient_funds: 'Not enough money; nothing was charged', payment_unclear: 'The bank is still processing this payment. Nothing more was charged.',
        bank_unavailable: 'The bank is not available; nothing was charged', invalid_state: 'This can no longer be done', rate_limited: 'Wait a moment before trying again',
        not_found: 'Not found', db_unavailable: 'The justice database did not answer', ia_unavailable: 'Internal Affairs is not taking complaints right now',
        bad_key: 'This form expired; send it again', no_permission: 'You may not do that', key_reused: 'This form was already used; open it again',
        server_error: 'The server could not do that', busy: 'Busy; try again',
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
    function dur(sec) {
        sec = Math.max(0, Math.floor(Number(sec) || 0));
        const d = Math.floor(sec / 86400); const hr = Math.floor((sec % 86400) / 3600); const m = Math.floor((sec % 3600) / 60);
        return d > 0 ? `${d} d ${hr} h ${m} min` : `${hr} h ${pad(m)} min`;
    }
    const label = (s) => String(s == null ? '' : s).replace(/_/g, ' ');
    const TONE = { issued: 'pending', overdue: 'bad', paid: 'ok', waived: 'off', dismissed: 'off', contested: 'active', upheld: 'warn', invoiced: 'pending',
        payment_pending: 'pending', referred: 'warn', active: 'active', pending: 'pending', suspended: 'warn', completed: 'ok', assigned: 'pending',
        scheduled: 'active', attended: 'ok', missed: 'bad', cancelled: 'off', sentenced: 'bad', acquitted: 'ok', closed: 'off', filed: 'pending' };
    let live = null; // the open window's state (one instance per app), for unmount

    PFApps.register('justice-records', {
        mount(container, ctx) {
            const { h, money } = ctx;
            const st = { tab: 'record', timer: null };
            live = st;
            const clear = (el) => { el.textContent = ''; return el; };
            const badge = (s) => h('span.ju-st' + (TONE[s] ? '.' + TONE[s] : ''), label(s));
            const tabs = h('div.pf-tabs', { role: 'tablist' });
            const body = h('div.pf-app-body');
            container.appendChild(h('div.pf-app.ju-app.ju-records',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '📜'), h('div', 'Justice Records', h('div.pf-app-sub', 'Your record, court dates, sentence and fines')))),
                tabs, body));
            const loading = () => h('div.pf-empty', 'Loading…');
            const failed = (res, retry) => h('div.pf-empty', h('div.ju-error', errText(res)), h('button.pf-btn.sm', { type: 'button', onclick: retry }, 'Try again'));
            const field = (text, input) => h('div.pf-field', h('label', text), input);

            const TABS = [['record', 'Record'], ['court', 'Court dates'], ['sentence', 'Sentence'], ['fines', 'Fines'], ['complaint', 'Complaint']];
            function renderTabs() {
                clear(tabs);
                TABS.forEach(([id, text]) => tabs.appendChild(h('button.pf-tab' + (st.tab === id ? '.active' : ''),
                    { type: 'button', role: 'tab', 'aria-selected': st.tab === id ? 'true' : 'false', 'data-tab': id, onclick: () => show(id) }, text)));
            }
            function show(id) {
                if (st.timer) { clearInterval(st.timer); st.timer = null; }
                st.tab = id;
                renderTabs();
                clear(body);
                VIEWS[id]();
            }
            async function load(tab, method, payload) {
                body.appendChild(loading());
                const res = await ctx.rpc(method, payload);
                if (st.tab !== tab) return null;
                clear(body);
                if (!res || !res.ok) { body.appendChild(failed(res, () => show(tab))); return null; }
                return res;
            }

            async function record() {
                const res = await load('record', 'record');
                if (!res) return;
                body.appendChild(h('div.ju-hint', 'Your criminal record as the justice system holds it. Expunged entries are not shown.'));
                if (!res.entries.length) { body.appendChild(h('div.pf-empty', 'Your record is clean.')); return; }
                body.appendChild(h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['Date', 'Entry', 'Details'].map((t) => h('th', t)))),
                    h('tbody', res.entries.map((e) => h('tr', h('td', fmt(e.at)), h('td', label(e.kind)), h('td.ju-note', e.summary || '')))))));
            }

            async function court() {
                const res = await load('court', 'court');
                if (!res) return;
                body.appendChild(h('div.ju-section', 'Upcoming hearings'));
                body.appendChild(res.hearings.length ? h('ul.pf-list', res.hearings.map((x) => h('li.pf-list-item',
                    h('div.pf-row.between', h('span.pf-strong', fmt(x.at)), h('span', label(x.kind), ' hearing')),
                    h('div.pf-small.pf-muted', `Case ${x.caseNo} · ${x.courtroom || 'Superior Court'}`))))
                    : h('div.pf-empty', 'No hearing is scheduled for you.'));
                body.appendChild(h('div.ju-section', 'Your cases'));
                body.appendChild(res.cases.length ? h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['Case', 'Kind', 'State', 'Filed', 'Closed'].map((t) => h('th', t)))),
                    h('tbody', res.cases.map((c) => h('tr', h('td', c.caseNo), h('td', label(c.kind)), h('td', badge(c.state)), h('td', fmt(c.filedAt)), h('td', fmt(c.closedAt)))))))
                    : h('div.pf-empty', 'No court cases.'));
            }

            async function sentence() {
                const res = await load('sentence', 'sentence');
                if (!res) return;
                const inc = res.incarceration;
                body.appendChild(h('div.ju-section', 'Sentence clock'));
                if (inc) {
                    const total = (inc.requiredSeconds || 0);
                    const done = Math.max(0, total - (inc.remainingSeconds || 0));
                    body.appendChild(h('div.pf-card',
                        h('div.pf-row.between', h('span.pf-strong', `${label(inc.kind)} · ${inc.facility || ''}`), badge(inc.state)),
                        h('div.ju-clock', dur(inc.remainingSeconds)), h('div.pf-small.pf-muted', 'left to serve'),
                        total ? h('div.ju-bar', h('span', { style: { width: `${Math.min(100, Math.round((done / total) * 100))}%` } })) : null,
                        h('div.ju-hint', inc.clock === 'online'
                            ? 'Time counts while you are online and inside the facility (or in hospital custody). It is read from the server every minute.'
                            : 'Time counts in real time.')));
                    // the server's clock, re-read each minute while this tab is open (no local guesswork)
                    st.timer = setInterval(() => { if (st.tab === 'sentence') show('sentence'); }, 60000);
                } else {
                    body.appendChild(h('div.pf-empty', 'You are not serving a custodial sentence.'));
                }
                const sup = res.supervision;
                body.appendChild(h('div.ju-section', 'Probation and parole'));
                if (sup) {
                    body.appendChild(h('div.pf-card',
                        h('div.pf-row.between', h('span.pf-strong', `${label(sup.kind)} #${sup.orderId}`), badge(sup.state)),
                        h('dl.ju-kv', h('dt', 'Ends'), h('dd', fmt(sup.endsAt)), h('dt', 'Next check-in'), h('dd', fmt(sup.nextCheckinAt)),
                            h('dt', 'Monitor'), h('dd', sup.monitor ? label(sup.monitor.mode) : 'none')),
                        (sup.conditions || []).length ? h('div.ju-actions', sup.conditions.map((c) => h('span.pf-badge',
                            [label(c.kind), c.everyDays && `every ${c.everyDays} d`, c.from != null && c.to != null && `${c.from}-${c.to}`].filter(Boolean).join(' ')))) : null,
                        h('div.ju-hint', 'Check in at a probation office with /checkin, or meet your officer.'),
                        (sup.appointments || []).length ? h('ul.pf-list', sup.appointments.map((a) => h('li.pf-list-item.pf-row.between',
                            h('span', fmt(a.dueAt), ' · ', (a.detail && a.detail.location) || ''), badge(a.state)))) : null));
                } else {
                    body.appendChild(h('div.pf-empty', 'You are not under supervision.'));
                }
                const cs = res.communityService || [];
                body.appendChild(h('div.ju-section', 'Community service'));
                body.appendChild(cs.length ? h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['Order', 'Units', 'Deadline', 'State'].map((t) => h('th', t)))),
                    h('tbody', cs.map((o) => h('tr', h('td', '#' + o.orderId), h('td', `${o.unitsDone} / ${o.units}`), h('td', fmt(o.dueAt)), h('td', badge(o.state)))))))
                    : h('div.pf-empty', 'No community service orders.'));
            }

            function payButton(o, account) {
                const btn = h('button.pf-btn.sm' + (account === 'bank' ? '.primary' : '.ghost'), { type: 'button' }, account === 'bank' ? `Pay ${money(o.owed)} (bank)` : 'Pay cash');
                btn.addEventListener('click', async () => {
                    if (btn.disabled) return;
                    btn.disabled = true;
                    const res = await ctx.rpc('pay', { orderId: o.id, account });
                    btn.disabled = false;
                    if (res && res.ok) ctx.notify(res.duplicate ? 'Already paid' : `Paid ${money(o.owed)}`, 'success');
                    else ctx.notify(errText(res), res && res.error === 'payment_unclear' ? 'info' : 'error');
                    show('fines');
                });
                return btn;
            }

            function contestForm(o) {
                const reason = h('input.pf-input', { maxlength: '200', placeholder: 'Why you contest it' });
                const btn = h('button.pf-btn.sm.ghost', { type: 'submit' }, 'Contest');
                const form = h('form.pf-row', reason, btn);
                form.addEventListener('submit', async (e) => {
                    e.preventDefault();
                    if (btn.disabled) return;
                    btn.disabled = true;
                    const res = await ctx.rpc('contest', { orderId: o.id, reason: reason.value });
                    btn.disabled = false;
                    if (res && res.ok) { ctx.notify('Citation contested; the court will decide', 'success'); show('fines'); } else ctx.notify(errText(res), 'error');
                });
                return form;
            }

            async function fines() {
                const res = await load('fines', 'fines');
                if (!res) return;
                if (!res.list.length) { body.appendChild(h('div.pf-empty', 'You have no fines or citations.')); return; }
                const owed = res.list.filter((o) => o.payable).reduce((n, o) => n + (o.owed || 0), 0);
                body.appendChild(h('div.ju-stats', h('div.pf-card', h('div.pf-small.pf-muted', 'Payable now'), h('div.ju-num', money(owed)))));
                body.appendChild(h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['#', 'Kind', 'Details', 'Amount', 'Due', 'State', ''].map((t) => h('th', t)))),
                    h('tbody', res.list.map((o) => h('tr',
                        h('td', String(o.id)), h('td', label(o.kind)),
                        h('td.ju-note.pf-small', [o.violation && label(o.violation), o.plate && `plate ${o.plate}`,
                            Array.isArray(o.charges) ? o.charges.map((c) => [c.code, c.label].filter(Boolean).join(' ')).join(', ') : ''].filter(Boolean).join(' · ')),
                        h('td', money(o.amount), o.paidAmount ? h('div.pf-small.pf-muted', 'paid ' + money(o.paidAmount)) : null),
                        h('td', fmt(o.dueAt)), h('td', badge(o.state)),
                        h('td', h('div.ju-actions',
                            o.payable ? [payButton(o, 'bank'), payButton(o, 'cash')] : null,
                            o.state === 'invoiced' ? h('span.pf-small.pf-muted', 'Pay on your phone (Invoices)') : null,
                            o.contestable ? contestForm(o) : null,
                            o.contestable ? h('div.pf-small.pf-muted', 'Contest until ' + fmt(o.contestUntil)) : null))))))));
            }

            async function complaint() {
                const res = await load('complaint', 'iaForm');
                if (!res) return;
                const officer = h('input.pf-input', { maxlength: '128', placeholder: 'Name, callsign or badge number' });
                const category = h('select.pf-select', res.categories.map((c) => h('option', { value: c }, label(c))));
                const incident = h('input.pf-input', { maxlength: '64', placeholder: 'Incident or report number (optional)' });
                const summary = h('textarea.pf-textarea', { rows: '6', maxlength: '4000', placeholder: 'What happened, when and where (at least a sentence)' });
                const err = h('div.ju-error', { role: 'alert' });
                const btn = h('button.pf-btn.primary', { type: 'submit' }, 'Send to Internal Affairs');
                const form = h('form.pf-card.ju-form',
                    h('div.ju-hint', 'Your complaint goes to the police Internal Affairs unit under your own name. The officer named does not see it.'),
                    h('div.pf-row', field('Officer', officer), field('Category', category)), field('Incident', incident), field('What happened', summary), err, h('div', btn));
                let key = res.key;
                form.addEventListener('submit', async (e) => {
                    e.preventDefault();
                    if (btn.disabled) return;
                    btn.disabled = true;
                    err.textContent = '';
                    const r = await ctx.rpc('fileComplaint', { officerName: officer.value, category: category.value, incidentRef: incident.value, summary: summary.value, key });
                    btn.disabled = false;
                    if (!r || !r.ok) {
                        err.textContent = errText(r);
                        if (r && (r.error === 'bad_key' || r.error === 'key_reused')) {
                            const again = await ctx.rpc('iaForm');
                            if (again && again.ok) key = again.key;
                        }
                        return;
                    }
                    clear(body);
                    body.appendChild(h('div.pf-card', h('div.pf-strong', `Complaint #${r.complaintId} received`),
                        h('div.ju-hint', 'Internal Affairs will look into it. Keep the number for any follow-up.'),
                        h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => show('complaint') }, 'File another')));
                });
                body.appendChild(form);
            }

            const VIEWS = { record, court, sentence, fines, complaint };
            show('record');
        },
        unmount() {
            if (live && live.timer) clearInterval(live.timer);
            live = null;
        },
    });
})();
