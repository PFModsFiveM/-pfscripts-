// Bills: every bill and fine the citizen owes (city bills, phone invoices, bills of businesses they
// run), paid through the system that issued it, with the history of settled bills.
(function () {
    const ERRORS = {
        insufficient_funds: 'Not enough money in your bank account', bank_unavailable: 'The bank is not responding',
        not_open: 'This bill is already settled', nothing_due: 'Nothing left to pay', in_progress: 'A payment for this bill is in progress',
        not_found: 'That bill is not yours or no longer exists', government_offline: 'City Hall is not responding',
        phone_offline: 'The billing system is not responding', not_declinable: 'This bill cannot be declined', bad_amount: 'Enter a valid amount',
    };
    const STATUS = {
        open: ['Open', ''], partial: ['Part paid', 'warn'], overdue: ['Overdue', 'bad'], delinquent: ['Delinquent', 'bad'],
        paid: ['Paid', 'ok'], waived: ['Waived', 'accent'], declined: ['Declined', ''],
    };
    const SOURCE = { government: '🏛️', phone: '📱', business: '🏢' };

    function day(ts) { return ts ? new Date(ts * 1000).toLocaleDateString([], { day: 'numeric', month: 'short', year: 'numeric' }) : ''; }

    PFApps.register('bills', {
        mount(container, ctx, params) {
            const { h, money } = ctx;
            const state = { tab: 'open', data: null, focus: params && params.focus, busy: false };
            const stats = h('div.pfc-stats');
            const tabs = h('div.pf-tabs');
            const list = h('div.pf-list');
            const root = h('div.pf-app.pfc.pfc-bills',
                h('div.pf-app-header',
                    h('div.pf-app-title', h('span.pf-icon', '🧾'), h('div', 'Bills', h('div.pf-app-sub', 'City bills, fines and invoices in one place'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                tabs,
                h('div.pf-app-body.pf-stack', stats, list));
            container.appendChild(root);

            function stat(label, value, cls) {
                return h('div.pf-card.pf-stat', h('div.pf-stat-value' + (cls ? '.' + cls : ''), value), h('div.pf-stat-label', label));
            }

            function render() {
                const d = state.data || { open: [], history: [] };
                stats.innerHTML = '';
                stats.appendChild(stat('Total due', money(d.totalDue || 0)));
                stats.appendChild(stat('Open bills', String(d.open.length)));
                stats.appendChild(stat('Overdue', String(d.overdue || 0)));
                if (d.bank != null) stats.appendChild(stat('In your bank', money(d.bank)));
                tabs.innerHTML = '';
                [['open', `Open (${d.open.length})`], ['history', 'History']].forEach(([id, label]) => {
                    tabs.appendChild(h('div.pf-tab' + (state.tab === id ? '.active' : ''), { onclick: () => { state.tab = id; render(); } }, label));
                });
                list.innerHTML = '';
                const rows = state.tab === 'open' ? d.open : d.history;
                if (!rows.length) { list.appendChild(h('div.pfc-empty', state.tab === 'open' ? 'You owe nothing. 🎉' : 'No settled bills yet.')); return; }
                rows.forEach((b) => list.appendChild(card(b)));
                const focused = list.querySelector('.pfc-bill.focus');
                if (focused && focused.scrollIntoView) focused.scrollIntoView({ block: 'center' });
            }

            function card(b) {
                const st = STATUS[b.status] || [b.status, ''];
                const meta = [b.kind, b.from, b.business ? 'for ' + b.business : null,
                    b.open ? (b.due ? 'due ' + day(b.due) : 'due on receipt') : (b.settled ? 'settled ' + day(b.settled) : null),
                    b.issued ? 'issued ' + day(b.issued) : null].filter(Boolean).join(' · ');
                const actions = h('div.pf-row', { style: { flexWrap: 'wrap', justifyContent: 'flex-end' } });
                if (b.canPay) {
                    actions.appendChild(h('button.pf-btn.sm.primary', { onclick: () => pay(b) }, 'Pay ' + money(b.remaining)));
                    if (b.source === 'government' && b.remaining > 1) {
                        const part = h('input.pf-input', { type: 'number', min: 1, step: '0.01', max: b.remaining, placeholder: 'Amount', style: { width: '100px' } });
                        actions.appendChild(part);
                        actions.appendChild(h('button.pf-btn.sm', { onclick: () => pay(b, Number(part.value)) }, 'Pay part'));
                    }
                } else if (b.open) {
                    actions.appendChild(h('span.pf-small.pf-muted', 'Pay this bill where it was issued'));
                }
                if (b.canDecline) actions.appendChild(h('button.pf-btn.sm.danger', { onclick: () => decline(b) }, 'Decline'));
                return h('div.pf-card.pfc-bill' + (state.focus && state.focus === b.key ? '.focus' : ''),
                    h('div.pf-stack', { style: { gap: '4px', minWidth: '0', flex: '1' } },
                        h('div.pf-row', h('span', SOURCE[b.source] || '🧾'), h('span.pf-strong', b.title), h('span.pf-badge' + (st[1] ? '.' + st[1] : ''), st[0])),
                        h('div.pf-small.pf-muted', meta)),
                    h('div.pf-stack', { style: { gap: '6px', alignItems: 'flex-end' } },
                        h('div.pfc-bill-amount', money(b.open ? b.remaining : b.amount)),
                        b.paid && b.open ? h('div.pf-small.pf-muted', `${money(b.paid)} of ${money(b.amount)} paid`) : null,
                        actions));
            }

            async function load() {
                const res = await ctx.rpc('list');
                if (!res || !res.ok) { ctx.notify('Bills are not available right now', 'error'); return; }
                state.data = res;
                if (state.focus && !res.open.some((b) => b.key === state.focus) && res.history.some((b) => b.key === state.focus)) state.tab = 'history';
                render();
            }

            async function pay(b, amount) {
                if (state.busy) return;
                if (amount !== undefined && !(amount > 0)) { ctx.notify(ERRORS.bad_amount, 'error'); return; }
                state.busy = true;
                const res = await ctx.rpc('pay', { key: b.key, amount });
                state.busy = false;
                if (!res || !res.ok) ctx.notify(ERRORS[res && res.error] || 'The payment did not go through', 'error');
                else ctx.notify('Paid ' + money(res.paid || amount || b.remaining), 'success');
                load();
            }

            async function decline(b) {
                if (state.busy) return;
                state.busy = true;
                const res = await ctx.rpc('decline', { key: b.key });
                state.busy = false;
                if (!res || !res.ok) ctx.notify(ERRORS[res && res.error] || 'That did not work', 'error');
                else ctx.notify('Bill declined', 'success');
                load();
            }

            ctx.on('new', (b) => { ctx.notify(`New bill: ${b && b.title ? b.title : ''} ${b && b.amount ? money(b.amount) : ''}`, 'primary'); load(); });
            ctx.on('changed', load);
            ctx.on('params', (p) => { if (p && p.focus) { state.focus = p.focus; load(); } });
            load();
        },
    });
})();
