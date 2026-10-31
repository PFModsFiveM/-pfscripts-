// City Budget (government tablet, read only): treasury, department budgets, district power and
// water, recent spending. Budgets are changed on the government computer.
(function () {
    const STAGE = (s) => (s >= 5 ? ['Critical', '.bad'] : s >= 3 ? ['Degraded', '.warn'] : ['Normal', '.ok']);

    PFApps.register('govbudget', {
        mount(container, ctx) {
            const { h, money, timeAgo } = ctx;
            const body = h('div.pf-app-body');
            container.appendChild(h('div.pf-app.gov-app',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '💰'), h('div', 'City Budget', h('div.pf-app-sub', 'Read only — changes are made on the City Hall computer'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                body));

            function stat(label, value) { return h('div.pf-card.pf-stat', h('div.pf-small.pf-muted', label), h('div.gov-num', value)); }

            function render(d) {
                body.innerHTML = '';
                const deps = d.departments || [];
                const totalBudget = deps.reduce((a, x) => a + (Number(x.budget) || 0), 0);
                const totalSpent = deps.reduce((a, x) => a + (Number(x.spent) || 0), 0);
                const dark = (d.districts || []).filter((x) => x.blackout || (x.powerStage || 1) >= 3).length;
                body.appendChild(h('div.gov-stats',
                    stat('Treasury', money(d.treasury)), stat('Monthly budgets', money(totalBudget)),
                    stat('Spent this month', money(totalSpent)), stat('Districts with power trouble', String(dark))));

                body.appendChild(h('div.gov-section', `Departments ${d.month ? '(' + d.month + ')' : ''}`));
                body.appendChild(h('table.pf-table',
                    h('thead', h('tr', ['Department', 'Budget', 'Account', 'Spent', 'Status', 'Condition'].map((t) => h('th', t)))),
                    h('tbody', deps.map((x) => h('tr',
                        h('td', x.label), h('td', money(x.budget)), h('td', money(x.balance)), h('td', money(x.spent)),
                        h('td', h('span.pf-badge' + (/Under|Risk/.test(x.status || '') ? '.bad' : /Tight/.test(x.status || '') ? '.warn' : '.ok'), x.status || '—')),
                        h('td', x.condition != null ? `${Math.round(x.condition)}%` : '—'))))));

                body.appendChild(h('div.gov-section', 'Districts'));
                body.appendChild(h('table.pf-table',
                    h('thead', h('tr', ['District', 'Power', 'Water', 'Roads', 'Lights'].map((t) => h('th', t)))),
                    h('tbody', (d.districts || []).map((x) => {
                        const [p, pc] = STAGE(x.powerStage || 1);
                        const [r, rc] = STAGE(x.roadStage || 1);
                        return h('tr',
                            h('td', x.label),
                            h('td', h('span.pf-badge' + pc, x.blackout ? 'Blackout now' : p), x.flicker ? h('div.pf-small.pf-muted', 'rolling outages') : null),
                            h('td', h('span.pf-badge' + (x.water ? (x.waterPressure < 100 ? '.warn' : '.ok') : '.bad'), x.water ? `${x.waterPressure}% pressure` : 'No water')),
                            h('td', h('span.pf-badge' + rc, r), x.roadCondition != null ? h('div.pf-small.pf-muted', `${Math.round(x.roadCondition)}% condition`) : null),
                            h('td', x.trafficLights && x.streetLights ? 'Working' : 'Failing'));
                    }))));

                body.appendChild(h('div.gov-section', 'Recent spending'));
                const recent = d.recent || [];
                if (!recent.length) { body.appendChild(h('div.pf-empty', 'Nothing spent yet this month.')); return; }
                body.appendChild(h('div.pf-list', recent.map((t) => h('div.pf-list-item',
                    h('div', h('strong', `${t.department} · ${t.category || t.type}`), h('div.pf-small.pf-muted', [t.reason, t.by].filter(Boolean).join(' · '))),
                    h('div', h('div', money(t.amount)), h('div.pf-small.pf-muted', t.at ? timeAgo(t.at) : ''))))));
            }

            async function load() {
                const res = await ctx.rpc('overview');
                if (!res || !res.ok) { body.innerHTML = ''; body.appendChild(h('div.pfapp-error', 'The budget is unavailable right now.')); return; }
                render(res);
            }

            load();
        },
    });
})();
