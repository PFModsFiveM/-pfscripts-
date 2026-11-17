// Community Service (pf-devices module, tablet and computer). Citizens see their orders, sign in at a
// desk, take city work and finish a task; supervisors see the open shifts, sign off a worker standing near
// them and follow the orders. The server's community-service runtime does every check (position, timing,
// GOV work orders, units); the world markers and prompts follow from the same server state.
(function () {
    'use strict';

    const ERRORS = {
        too_far: 'You are not at the right place', invalid_state: 'Not possible right now', not_found: 'Nothing to do here',
        rate_limited: 'One moment', too_soon: 'Keep working on site a little longer', conflict: 'Finish or abandon your current task first',
        db_unavailable: 'Community service did not answer; nothing was changed', no_permission: 'You may not do that',
        offline: 'That person is not in the city', busy: 'Someone else is changing this right now; try again', server_error: 'The server could not do that',
    };
    function errText(res) {
        if (!res) return 'No answer from the server';
        return res.message || ERRORS[res.error] || String(res.error || 'That did not work').replace(/_/g, ' ');
    }
    const pad = (n) => String(n).padStart(2, '0');
    function fmt(ts) {
        if (!ts) return '-';
        const d = new Date(Number(ts) * 1000);
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }
    function dueIn(sec) {
        if (sec == null) return 'no deadline';
        if (sec <= 0) return 'due now';
        const d = Math.floor(sec / 86400); const hr = Math.floor((sec % 86400) / 3600);
        return d > 0 ? `due in ${d} d ${hr} h` : `due in ${hr} h ${Math.floor((sec % 3600) / 60)} min`;
    }
    const label = (s) => String(s == null ? '' : s).replace(/_/g, ' ');
    const TONE = { assigned: 'pending', active: 'active', overdue: 'bad', completed: 'ok', vacated: 'off' };

    PFApps.register('community-service', {
        mount(container, ctx) {
            const { h } = ctx;
            const st = { me: null, tab: null, work: null, board: { page: 1 }, orders: { page: 1, scope: 'open' } };
            const clear = (el) => { el.textContent = ''; return el; };
            const badge = (s) => h('span.ju-st' + (TONE[s] ? '.' + TONE[s] : ''), label(s));
            const tabs = h('div.pf-tabs', { role: 'tablist' });
            const body = h('div.pf-app-body');
            container.appendChild(h('div.pf-app.ju-app.ju-cs',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '🧹'), h('div', 'Community Service', h('div.pf-app-sub', 'Repair the city, one unit at a time')))),
                tabs, body));

            const loading = () => h('div.pf-empty', 'Loading…');
            const failed = (res, retry) => h('div.pf-empty', h('div.ju-error', errText(res)), retry ? h('button.pf-btn.sm', { type: 'button', onclick: retry }, 'Try again') : null);
            const bar = (done, total) => h('div.ju-bar', { role: 'progressbar', 'aria-valuemin': '0', 'aria-valuemax': String(total || 0), 'aria-valuenow': String(done || 0) },
                h('span', { style: { width: `${total ? Math.min(100, Math.round((done / total) * 100)) : 0}%` } }));

            // an action button: busy while the server works, the server's answer as a toast
            function action(text, cls, fn, after) {
                const btn = h('button.pf-btn' + (cls || ''), { type: 'button' }, text);
                btn.addEventListener('click', async () => {
                    if (btn.disabled) return;
                    btn.disabled = true;
                    let res;
                    try { res = await fn(); } catch (e) { res = null; }
                    btn.disabled = false;
                    if (!res || !res.ok) { ctx.notify(errText(res), 'error'); return; }
                    if (after) after(res);
                });
                return btn;
            }

            const TABS = [
                ['mine', 'My service', (m) => m.hasOrders || m.citizenView],
                ['board', 'Open shifts', (m) => m.supervisor], ['signoff', 'Sign-off', (m) => m.supervisor], ['orders', 'Orders', (m) => m.supervisor],
            ];
            function visible() { return TABS.filter((t) => t[2](st.me || {})); }
            function renderTabs() {
                clear(tabs);
                visible().forEach(([id, text]) => tabs.appendChild(h('button.pf-tab' + (st.tab === id ? '.active' : ''),
                    { type: 'button', role: 'tab', 'aria-selected': st.tab === id ? 'true' : 'false', 'data-tab': id, onclick: () => show(id) }, text)));
            }
            function show(id) {
                st.tab = id;
                renderTabs();
                clear(body);
                VIEWS[id]();
            }

            // ── the citizen's own service ──
            async function mine() {
                body.appendChild(loading());
                const res = await ctx.rpc('state');
                if (st.tab !== 'mine') return;
                clear(body);
                if (!res || !res.ok) { body.appendChild(failed(res, () => show('mine'))); return; }
                const s = res.state || {};
                const orders = s.orders || [];
                if (!orders.length && !s.shift) {
                    body.appendChild(h('div.pf-empty', 'You have no open community service order.'));
                } else {
                    body.appendChild(h('div.ju-section', 'Open orders'));
                    orders.forEach((o) => body.appendChild(h('div.pf-card', { style: { marginBottom: '8px' } },
                        h('div.pf-row.between', h('span.pf-strong', `Order #${o.id}`), badge(o.state)),
                        h('div.pf-row.between', h('span', `${o.unitsDone || 0} of ${o.units} units`), h('span.pf-small.pf-muted', o.state === 'overdue' ? 'overdue: referred to the court' : dueIn(o.dueIn))),
                        bar(o.unitsDone || 0, o.units))));
                }
                // shift and task
                body.appendChild(h('div.ju-section', 'Shift'));
                if (!s.shift) {
                    body.appendChild(h('div.pf-card.ju-form',
                        h('div', 'Sign in at a community service desk to start working.'),
                        h('ul.pf-list', (s.signIns || []).map((d) => h('li.pf-list-item.pf-row.between', h('span', d.label || d.id),
                            h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => { ctx.setWaypoint(d.x, d.y); ctx.notify('Waypoint set', 'success'); } }, 'Set waypoint')))),
                        orders.length ? h('div', action('Sign in here', '.primary', () => ctx.rpc('startShift'), () => { ctx.notify('Signed in for community service', 'success'); show('mine'); })) : null));
                } else {
                    const sh = s.shift;
                    body.appendChild(h('div.pf-card.ju-form',
                        h('div.pf-row.between', h('span.pf-strong', `Shift #${sh.id} · order #${sh.orderId}`), sh.supervised ? h('span.ju-st.ok', 'supervised') : h('span.ju-st', 'unsupervised')),
                        h('div.pf-small.pf-muted', 'Started ' + fmt(sh.startedAt)),
                        h('div.ju-actions',
                            !s.task ? action('Find work nearby', '.primary', () => ctx.rpc('listWork'), (r) => { st.work = r.list || []; renderWork(workBox); }) : null,
                            action('Sign out', '.ghost', () => ctx.rpc('endShift'), () => { ctx.notify('Signed out', 'success'); show('mine'); }))));
                    const workBox = h('div');
                    body.appendChild(workBox);
                    if (s.task) body.appendChild(taskCard(s.task));
                    else renderWork(workBox);
                }
                if (res.history && res.history.length) {
                    body.appendChild(h('div.ju-section', 'All orders'));
                    body.appendChild(h('div.ju-table-wrap', h('table.pf-table', h('thead', h('tr', ['Order', 'Units', 'Deadline', 'State'].map((t) => h('th', t)))),
                        h('tbody', res.history.map((o) => h('tr', h('td', '#' + o.orderId), h('td', `${o.unitsDone} / ${o.units}`), h('td', fmt(o.dueAt)), h('td', badge(o.state))))))));
                }
            }

            function renderWork(box) {
                clear(box);
                if (st.work == null) return;
                if (!st.work.length) { box.appendChild(h('div.pf-empty', 'No community service work nearby right now.')); return; }
                box.appendChild(h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['Work', 'Where', 'Distance', 'Open units', ''].map((t) => h('th', t)))),
                    h('tbody', st.work.map((w) => h('tr', h('td', w.label || label(w.kind)), h('td', [w.district, w.site].filter(Boolean).join(' · ')),
                        h('td', `${w.distance} m`), h('td', String(w.unitsOpen)),
                        h('td', action('Take', '.sm.primary', () => ctx.rpc('claim', { workOrderId: w.id }), () => { st.work = null; ctx.notify('Task assigned: go to the marked site', 'success'); show('mine'); }))))))));
            }

            function taskCard(t) {
                const next = (t.points || [])[t.stepsDone];
                return h('div.pf-card.ju-form', { style: { marginTop: '10px' } },
                    h('div.pf-row.between', h('span.pf-strong', t.label || label(t.kind)), h('span', `${t.stepsDone} of ${t.stepsNeeded} steps`)),
                    bar(t.stepsDone, t.stepsNeeded),
                    h('div.ju-hint', t.stepsDone < t.stepsNeeded
                        ? `Go to the marked spot and ${String(t.stepLabel || 'work').toLowerCase()} (each step is checked on site).`
                        : `Every step is done. Stay on site for at least ${Math.ceil((t.minSeconds || 0) / 60)} min in total, then finish.`),
                    h('div.ju-actions',
                        t.site ? h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => { const p = next || t.site; ctx.setWaypoint(p.x, p.y); ctx.notify('Waypoint set', 'success'); } }, 'Waypoint to the work') : null,
                        t.stepsDone >= t.stepsNeeded ? action('Finish task', '.primary', () => ctx.rpc('complete', { taskId: t.id }), (r) => {
                            ctx.notify(r.completed ? 'Community service order completed' : `Unit done: ${r.unitsDone || 0} of ${r.units || 0}`, 'success'); show('mine');
                        }) : null,
                        action('Abandon task', '.ghost.danger', () => ctx.rpc('abandon', { taskId: t.id }), () => { ctx.notify('Task given back', 'success'); show('mine'); })));
            }

            // ── supervisors ──
            function pager(state, reload) {
                return h('div.ju-pager',
                    h('button.pf-btn.sm.ghost', { type: 'button', disabled: state.page <= 1, onclick: () => { state.page -= 1; reload(); } }, 'Previous'),
                    h('span.pf-small.pf-muted', 'Page ' + state.page),
                    h('button.pf-btn.sm.ghost', { type: 'button', disabled: !state.more, onclick: () => { state.page += 1; reload(); } }, 'Next'));
            }

            async function board() {
                body.appendChild(h('div.pf-toolbar', h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => show('board') }, 'Refresh')));
                const list = h('div', loading());
                body.appendChild(list);
                const res = await ctx.rpc('board', { page: st.board.page });
                if (st.tab !== 'board') return;
                clear(list);
                if (!res || !res.ok) { list.appendChild(failed(res, () => show('board'))); return; }
                st.board.more = !!res.more;
                if (!res.list.length) { list.appendChild(h('div.pf-empty', 'Nobody is signed in for community service.')); return; }
                list.appendChild(h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['Worker', 'Order', 'Task', 'Since', 'Supervised'].map((t) => h('th', t)))),
                    h('tbody', res.list.map((x) => h('tr',
                        h('td', x.name || x.cid, x.name ? h('div.pf-small.pf-muted', x.cid) : null),
                        h('td', `#${x.orderId} · ${x.unitsDone}/${x.units}`, h('div', badge(x.orderState))),
                        h('td', x.task ? `${x.task.label} (${x.task.stepsDone}/${x.task.stepsNeeded})` : 'looking for work'),
                        h('td', fmt(x.startedAt)), h('td', x.supervised ? h('span.ju-st.ok', 'yes') : h('span.ju-st', 'no'))))))));
                list.appendChild(pager(st.board, () => show('board')));
            }

            async function signoff() {
                body.appendChild(h('div.ju-hint', 'Workers signed in within reach of you (server positions). Signing off a shift makes it supervised.'));
                body.appendChild(h('div.pf-toolbar', h('button.pf-btn.sm.ghost', { type: 'button', onclick: () => show('signoff') }, 'Scan again')));
                const list = h('div', loading());
                body.appendChild(list);
                const res = await ctx.rpc('nearby');
                if (st.tab !== 'signoff') return;
                clear(list);
                if (!res || !res.ok) { list.appendChild(failed(res, () => show('signoff'))); return; }
                if (!res.list.length) { list.appendChild(h('div.pf-empty', 'No signed-in worker near you.')); return; }
                list.appendChild(h('ul.pf-list', res.list.map((x) => h('li.pf-list-item.pf-row.between',
                    h('span', x.name || ('Worker ' + x.src), h('span.pf-small.pf-muted', ` · ${x.distance} m · shift #${x.shiftId}`)),
                    x.supervised ? h('span.ju-st.ok', 'signed off')
                        : action('Sign off shift', '.sm.primary', () => ctx.rpc('verify', { target: x.src }), () => { ctx.notify('Shift verified', 'success'); show('signoff'); })))));
            }

            async function orders() {
                const o = st.orders;
                body.appendChild(h('div.pf-toolbar', ['open', 'overdue', 'completed', 'vacated'].map((s) => h('button.pf-btn.sm' + (o.scope === s ? '.primary' : '.ghost'),
                    { type: 'button', onclick: () => { o.scope = s; o.page = 1; show('orders'); } }, label(s)))));
                const list = h('div', loading());
                body.appendChild(list);
                const res = await ctx.rpc('orders', { scope: o.scope, page: o.page });
                if (st.tab !== 'orders') return;
                clear(list);
                if (!res || !res.ok) { list.appendChild(failed(res, () => show('orders'))); return; }
                o.more = !!res.more;
                if (!res.list.length) { list.appendChild(h('div.pf-empty', 'No orders here.')); return; }
                list.appendChild(h('div.ju-table-wrap', h('table.pf-table',
                    h('thead', h('tr', ['Order', 'Citizen', 'Units', 'Deadline', 'State'].map((t) => h('th', t)))),
                    h('tbody', res.list.map((x) => h('tr', h('td', '#' + x.id), h('td', x.name || x.cid), h('td', `${x.unitsDone} / ${x.units}`, bar(x.unitsDone, x.units)),
                        h('td', fmt(x.dueAt)), h('td', badge(x.state))))))));
                list.appendChild(pager(o, () => show('orders')));
            }

            const VIEWS = { mine, board, signoff, orders };

            (async function start() {
                clear(body).appendChild(loading());
                const me = await ctx.rpc('me');
                clear(body);
                if (!me || !me.ok) { body.appendChild(failed(me, start)); return; }
                st.me = me;
                const first = visible()[0];
                renderTabs();
                if (!first) {
                    body.appendChild(h('div.pf-empty', me.supervisorJob
                        ? 'Supervising needs you on duty and the GOV community-service supervisor qualification.'
                        : 'You have no community service order.'));
                    return;
                }
                show(first[0]);
            })();
        },
    });
})();
