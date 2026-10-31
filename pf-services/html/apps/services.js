// Services: a citizen calls a tow truck, a mechanic, a taxi, a medic or the police to where they stand.
(function () {
    const ERRORS = {
        cooldown: 'Wait a minute before calling again', too_many_open: 'You already have open calls',
        insufficient_funds: 'Not enough money in your bank account for the call-out fee', bank_unavailable: 'The bank is not responding',
        not_yours: 'That is not your call', not_accepted: 'Nobody has taken this call yet', unknown_kind: 'That service does not exist',
        no_vehicle: 'Sit in or stand next to the vehicle that needs towing',
    };
    const STATUS = { open: 'Waiting', accepted: 'On the way', completed: 'Done', cancelled: 'Cancelled', expired: 'Expired' };

    PFApps.register('services', {
        mount(container, ctx) {
            const { h, money, timeAgo } = ctx;
            let kinds = [];
            let mine = [];
            let busy = false;
            let reloadTimer = null;

            const grid = h('div.pf-grid');
            const calls = h('div.pf-list');
            const root = h('div.pf-app.pfs-services',
                h('div.pf-app-header',
                    h('div.pf-app-title', h('span.pf-icon', '🆘'), h('div', 'Services', h('div.pf-app-sub', 'Help comes to where you are standing'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                h('div.pf-app-body.pf-stack', h('h3', 'Call a service'), grid, h('h3', 'Your calls'), calls));
            container.appendChild(root);

            function card(k) {
                const note = h('textarea.pf-textarea.pfs-note', { maxlength: 300, placeholder: 'What is the problem? (optional)' });
                return h('div.pf-card.pf-stack',
                    h('div.pf-row', h('span.pfs-icon', k.icon), h('div', h('div.pf-strong', k.label), h('div.pf-small.pf-muted', k.description))),
                    h('div.pf-row.between',
                        h('span.pf-badge' + (k.available ? '.ok' : '.warn'), k.available ? `${k.onDuty} available` : 'Nobody on duty'),
                        h('span.pf-small', k.fee ? `Call-out ${money(k.fee)}` : 'No call-out fee')),
                    note,
                    h('button.pf-btn.primary', { onclick: () => request(k, note.value) }, `Call ${k.label.toLowerCase()}`));
            }

            function renderCalls() {
                calls.innerHTML = '';
                if (!mine.length) { calls.appendChild(h('div.pf-empty', 'No calls in the last day.')); return; }
                mine.forEach((r) => {
                    const actions = h('div.pf-row');
                    if (r.status === 'open' || r.status === 'accepted') actions.appendChild(h('button.pf-btn.sm.danger', { onclick: () => act('cancel', r) }, 'Cancel'));
                    if (r.status === 'accepted') actions.appendChild(h('button.pf-btn.sm.primary', { onclick: () => act('confirm', r) }, 'Job done'));
                    calls.appendChild(h('div.pf-list-item',
                        h('div.pf-row', h('span.pfs-icon', r.icon),
                            h('div', h('div.pf-strong', r.label), h('div.pf-small.pf-muted',
                                `${STATUS[r.status] || r.status}${r.assigneeName ? ' · ' + r.assigneeName : ''} · ${timeAgo(r.created)}${r.reward ? ' · ' + money(r.reward) : ''}`))),
                        actions));
                });
            }

            async function load() {
                const [k, m] = await Promise.all([ctx.rpc('kinds'), ctx.rpc('mine')]);
                kinds = (k && k.kinds) || [];
                mine = (m && m.requests) || [];
                grid.innerHTML = '';
                kinds.forEach((x) => grid.appendChild(card(x)));
                renderCalls();
            }

            function scheduleReload() { clearTimeout(reloadTimer); reloadTimer = setTimeout(load, 300); }

            async function request(k, details) {
                if (busy) return;
                busy = true;
                const res = await ctx.rpc('request', { kind: k.kind, details: String(details || '').slice(0, 300) });
                busy = false;
                if (!res || !res.ok) ctx.notify(ERRORS[res && res.error] || 'The call did not go through', 'error');
                else ctx.notify(res.existing ? 'You already called; they have your location' : `${k.label} called`, 'success');
                scheduleReload();
            }

            async function act(method, r) {
                if (busy) return;
                busy = true;
                const res = await ctx.rpc(method, { id: r.id });
                busy = false;
                if (!res || !res.ok) ctx.notify(ERRORS[res && res.error] || 'That did not work', 'error');
                scheduleReload();
            }

            ctx.on('request:new', scheduleReload);
            ctx.on('request:changed', scheduleReload);
            load();
        },
    });
})();
