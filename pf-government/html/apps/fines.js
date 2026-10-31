// Fines (government tablet): fine a person standing next to you or a registered business, see recent
// fines and bills, waive one. The server checks the permission, the distance and the amount.
(function () {
    const ERRORS = {
        no_permission: 'You may not issue fines', invalid_amount: 'Enter a whole amount within the fine limit',
        reason_required: 'Give a reason', not_nearby: 'That person is no longer next to you', business_not_found: 'Unknown business',
        not_open: 'That bill is already closed', bill_not_found: 'Bill not found', rate_limited: 'Slow down',
    };
    const errText = (e) => ERRORS[e] || (e ? String(e).replace(/_/g, ' ') : 'That did not work');

    PFApps.register('govfines', {
        mount(container, ctx) {
            const { h, money, timeAgo } = ctx;
            const state = { tab: 'issue', target: 'citizen', people: [], businesses: [], bills: [], canWaive: false, busy: false };
            const body = h('div.pf-app-body');
            const tabs = h('div.pf-tabs');
            container.appendChild(h('div.pf-app.gov-app',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '🧾'), h('div', 'Fines', h('div.pf-app-sub', 'City fines and bills')))),
                tabs, body));

            function renderTabs() {
                tabs.innerHTML = '';
                [['issue', 'Issue a fine'], ['recent', 'Recent']].forEach(([id, label]) => {
                    tabs.appendChild(h('div.pf-tab' + (state.tab === id ? '.active' : ''), { onclick: () => { state.tab = id; render(); if (id === 'recent') loadRecent(); } }, label));
                });
            }

            async function scan() {
                const res = await ctx.rpc('nearby');
                state.people = (res && res.ok && res.people) || [];
                if (res && !res.ok) ctx.notify(errText(res.error), 'error');
                render();
            }

            async function loadBusinesses() {
                const res = await ctx.rpc('businesses');
                state.businesses = (res && res.ok && res.businesses) || [];
                render();
            }

            async function loadRecent() {
                const res = await ctx.rpc('recent');
                state.bills = (res && res.ok && res.bills) || [];
                state.canWaive = !!(res && res.canWaive);
                render();
            }

            function issueForm() {
                const amount = h('input.pf-input', { type: 'number', min: '1', step: '1', placeholder: 'Amount ($)' });
                const reason = h('textarea.pf-textarea', { rows: '3', maxlength: '200', placeholder: 'Reason (shown to the person fined)' });
                let picker;
                if (state.target === 'citizen') {
                    picker = h('select.pf-select', state.people.length
                        ? state.people.map((p) => h('option', { value: String(p.id) }, `${p.name || 'Unknown'} — ${p.distance} m`))
                        : [h('option', { value: '' }, 'Nobody close enough — scan again')]);
                } else {
                    picker = h('select.pf-select', state.businesses.map((b) => h('option', { value: b.id }, b.name || b.id)));
                }
                const submit = h('button.pf-btn.primary', {
                    onclick: async () => {
                        if (state.busy) return;
                        const payload = { target: state.target, amount: Number(amount.value), reason: reason.value };
                        if (state.target === 'citizen') payload.playerId = Number(picker.value); else payload.businessId = picker.value;
                        state.busy = true;
                        const res = await ctx.rpc('issue', payload);
                        state.busy = false;
                        if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                        const who = res.name || res.business || 'Target';
                        const extra = state.target === 'citizen' ? ` (collected ${money(res.collected || 0)}, owing ${money(res.remaining || 0)})` : '';
                        ctx.notify(`${who} fined ${money(payload.amount)}${extra}`, 'success');
                        amount.value = ''; reason.value = '';
                    },
                }, 'Issue fine');
                return h('div.pf-card.gov-form',
                    h('div.pf-row',
                        h('button.pf-btn.sm' + (state.target === 'citizen' ? '.primary' : ''), { onclick: () => { state.target = 'citizen'; render(); scan(); } }, 'Person nearby'),
                        h('button.pf-btn.sm' + (state.target === 'business' ? '.primary' : ''), { onclick: () => { state.target = 'business'; render(); loadBusinesses(); } }, 'Business')),
                    h('div.pf-field', h('label', state.target === 'citizen' ? 'Person (within a few metres)' : 'Registered business'),
                        h('div.pf-row', picker, state.target === 'citizen' ? h('button.pf-btn.sm.ghost', { onclick: scan }, 'Scan') : null)),
                    h('div.pf-field', h('label', 'Amount'), amount),
                    h('div.pf-field', h('label', 'Reason'), reason),
                    h('div.pf-row', submit));
            }

            function waiveRow(bill) {
                const reason = h('input.pf-input', { maxlength: '200', placeholder: 'Waiver reason' });
                return h('div.pf-row', reason, h('button.pf-btn.sm.danger', {
                    onclick: async () => {
                        const res = await ctx.rpc('waive', { billId: bill.id, reason: reason.value });
                        if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                        ctx.notify(`Bill #${bill.id} waived`, 'success');
                        loadRecent();
                    },
                }, 'Waive'));
            }

            function recentTable() {
                if (!state.bills.length) return h('div.pf-empty', 'No fines or business bills yet.');
                const open = (s) => s === 'unpaid' || s === 'partial' || s === 'delinquent';
                const badge = (s) => h('span.pf-badge' + (s === 'paid' ? '.ok' : s === 'waived' ? '' : s === 'delinquent' ? '.bad' : '.warn'), s);
                return h('table.pf-table',
                    h('thead', h('tr', ['#', 'To', 'Type', 'Amount', 'Status', 'Reason', 'Issued', ''].map((t) => h('th', t)))),
                    h('tbody', state.bills.map((b) => h('tr',
                        h('td', String(b.id)),
                        h('td', b.target || '', h('div.pf-small.pf-muted', b.targetType)),
                        h('td', b.type),
                        h('td', money(b.amount), b.paid ? h('div.pf-small.pf-muted', 'paid ' + money(b.paid)) : null),
                        h('td', badge(b.status)),
                        h('td.gov-note', b.description || ''),
                        h('td', b.issued ? timeAgo(b.issued) : '', h('div.pf-small.pf-muted', b.issuedBy || '')),
                        h('td', state.canWaive && open(b.status) ? waiveRow(b) : null)))));
            }

            function render() {
                renderTabs();
                body.innerHTML = '';
                if (state.tab === 'issue') body.appendChild(issueForm());
                else body.appendChild(recentTable());
            }

            render();
            scan();
        },
    });
})();
