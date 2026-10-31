/*
 * Recycling app (pf-devices platform module, tablet + computer): the recycling plant shift, the
 * materials sorted, pay, level and the buyer's prices. Everything comes from the server
 * (server/apps/recycle.lua via ctx.rpc and the 'state' push); the only action is ending the shift,
 * which the server pays on the bank ledger. DOM is built with ctx.h inside the given container.
 */
(function () {
    'use strict';
    if (!window.PFApps) return;

    const ERRORS = {
        not_installed: 'Install Recycling from the App Store first',
        off_shift: 'You are not clocked in',
        rate_limited: 'Slow down a little',
        server_error: 'Something went wrong',
        request_failed: 'Could not reach the server',
        no_player: 'Your character is not loaded',
    };
    const TABS = [['shift', 'Shift'], ['materials', 'Materials'], ['level', 'Level'], ['history', 'History']];
    const STATUS = { paid: ['ok', 'Paid'], unpaid: ['warn', 'Waiting for the bank'], open: ['accent', 'In progress'] };

    function create(container, ctx) {
        const { h, money } = ctx;
        const st = { tab: ctx.storage.get('tab', 'shift'), view: null, error: null, busy: false };
        let alive = true;
        let ticker = null;

        const root = h('div.pf-app.pfj-rc');
        container.appendChild(root);
        const num = (v, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);
        const text = (v) => (v == null ? '' : String(v));

        async function load() {
            const res = await ctx.rpc('getInit');
            if (!alive) return;
            if (!res || res.ok === false) st.error = ERRORS[res && res.error] || 'The plant is not answering';
            else { st.error = null; st.view = res; }
            render();
        }

        async function clockOut() {
            if (st.busy) return;
            st.busy = true;
            render();
            const res = await ctx.rpc('clockOut');
            st.busy = false;
            if (!alive) return;
            if (res && res.ok !== false) {
                st.view = res;
                const s = res.summary || {};
                if (num(s.wage) > 0) ctx.notify(s.paid ? `Shift ended: ${money(s.wage)} paid to your bank` : `Shift ended: ${money(s.wage)} will be paid when the bank answers`, s.paid ? 'success' : 'error');
                else ctx.notify('Shift ended', 'primary');
            } else {
                ctx.notify(ERRORS[res && res.error] || 'That did not work', 'error');
            }
            render();
        }

        function waypoint() {
            const p = st.view && st.view.plant;
            if (!p) return;
            ctx.setWaypoint(num(p.x), num(p.y));
            ctx.notify('Waypoint set to the recycling plant', 'success');
        }

        function stat(label, value) {
            return h('div.pf-card.pf-stat', h('div.pf-stat-label', label), h('div.pf-stat-value', text(value)));
        }

        function table(head, rows) {
            return h('div.pfj-rc-scroll', h('table.pf-table',
                h('thead', h('tr', head.map((c) => h('th', c)))),
                h('tbody', rows)));
        }

        function shiftTab(v) {
            const s = v.shift;
            const out = [];
            if (!v.available) out.push(h('div.pf-card.pfj-rc-note', 'The plant office is closed right now: shifts cannot start until it opens again.'));
            if (num(v.owed) > 0) out.push(h('div.pf-card.pfj-rc-note', h('span.pf-badge.warn', 'Pending pay'), ` ${money(v.owed)} from earlier shifts is paid at your next clock in.`));
            if (s) {
                out.push(h('div.pf-row.between.pfj-rc-wrap',
                    h('div', h('div.pf-strong', 'On shift'), h('div.pf-muted.pf-small', `Started ${ctx.timeAgo(s.startedAt)}`)),
                    h('span.pf-badge.' + (s.carrying ? 'accent' : 'ok'), s.carrying ? 'Carrying a package: take it to the sorting table' : 'Take the marked package from the shelves')));
                out.push(h('div.pf-grid.pfj-rc-stats',
                    stat('Packages sorted', num(s.packages)),
                    stat('Materials sorted', num(s.materialCount)),
                    stat('Pay so far', money(s.wage)),
                    stat('XP this shift', num(s.xp))));
                const mats = Array.isArray(s.materials) ? s.materials : [];
                out.push(h('div.pf-card', h('div.pf-strong', 'Sorted this shift'),
                    mats.length ? h('div.pfj-rc-chips', mats.map((m) => h('span.pf-badge', `${text(m.label)} × ${num(m.amount)}`)))
                        : h('div.pf-muted.pf-small', 'Nothing yet. Sorted materials go straight into your pockets.')));
                out.push(h('div.pf-row.pfj-rc-wrap',
                    h('button.pf-btn.danger', { type: 'button', disabled: st.busy, onclick: clockOut }, st.busy ? 'Working…' : 'End shift and get paid'),
                    h('span.pf-muted.pf-small', 'Your pay goes to your bank when the shift ends.')));
            } else {
                const lvl = v.stats || {};
                out.push(h('div.pf-card',
                    h('div.pf-strong', 'Not clocked in'),
                    h('ol.pfj-rc-steps',
                        h('li', 'Go to the recycling plant in Paleto Bay and enter the warehouse.'),
                        h('li', 'Clock in at the desk. The package to take lights up on the shelves.'),
                        h('li', 'Carry it to the sorting table and sort it into materials.'),
                        h('li', `Each package pays ${money(lvl.wagePerPackage)} at your level. Clock out (or leave) to get paid.`))));
            }
            out.push(h('div.pf-row', h('button.pf-btn.primary', { type: 'button', onclick: waypoint }, 'Waypoint to the plant')));
            return out;
        }

        function materialsTab(v) {
            const rows = (v.prices || []).map((p) => h('tr',
                h('td', text(p.label)),
                h('td', v.sellEnabled && p.price != null ? money(p.price) : '—'),
                v.limitedStock ? h('td', text(num(p.stock))) : null,
                h('td', text(num(p.have)))));
            const head = ['Material', 'Buyer pays'].concat(v.limitedStock ? ['Plant stock'] : []).concat(['You carry']);
            return [
                h('div.pf-muted.pf-small', v.sellEnabled ? 'The materials buyer inside the warehouse pays cash. Mechanic shops also buy materials from suppliers (Supplier app).' : 'The plant does not buy materials right now. Mechanic shops buy them from suppliers (Supplier app).'),
                table(head, rows),
                h('div.pf-muted.pf-small', `Each package sorts into ${num(v.draws && v.draws[0], 1)}–${num(v.draws && v.draws[1], 5)} lots of materials, plus your level bonus.`),
            ];
        }

        function levelTab(v) {
            const s = v.stats || {};
            const base = num(s.levelXp);
            const next = s.nextXp != null ? num(s.nextXp) : null;
            const pct = next ? Math.max(0, Math.min(100, ((num(s.xp) - base) / Math.max(1, next - base)) * 100)) : 100;
            const rows = (v.levels || []).map((l) => h('tr' + (num(l.level) === num(s.level) ? '.pfj-rc-current' : ''),
                h('td', `${num(l.level)} · ${text(l.title)}`), h('td', text(num(l.xp))), h('td', money(l.wage)), h('td', `+${num(l.bonusDraws)}`)));
            return [
                h('div.pf-card',
                    h('div.pf-row.between', h('div.pf-strong', `Level ${num(s.level, 1)} · ${text(s.title)}`), h('span.pf-muted.pf-small', next ? `${num(s.xp)} / ${next} XP` : `${num(s.xp)} XP · top level`)),
                    h('div.pfj-rc-bar', h('div', { style: { width: pct + '%' } })),
                    h('div.pf-muted.pf-small', `+${num(v.xpPerPackage)} XP per package`)),
                h('div.pf-grid.pfj-rc-stats',
                    stat('Packages', num(s.packages)), stat('Materials', num(s.materials)), stat('Shifts', num(s.shifts)),
                    stat('Wages', money(s.wages)), stat('Material sales', money(s.sales)), stat('Total earned', money(s.earned))),
                table(['Level', 'XP', 'Pay / package', 'Extra materials'], rows),
            ];
        }

        function historyTab(v) {
            const list = v.history || [];
            if (!list.length) return [h('div.pf-empty', 'No shifts yet.')];
            return [table(['Started', 'Packages', 'Materials', 'Pay', ''], list.map((r) => {
                const badge = STATUS[r.status] || ['', text(r.status)];
                return h('tr', h('td', ctx.timeAgo(r.startedAt)), h('td', text(num(r.packages))), h('td', text(num(r.materials))),
                    h('td', money(r.wage)), h('td', h('span.pf-badge' + (badge[0] ? '.' + badge[0] : ''), badge[1])));
            }))];
        }

        function render() {
            if (!alive) return;
            root.textContent = '';
            const v = st.view;
            const lvl = v && v.stats ? `Level ${num(v.stats.level, 1)}` : '';
            root.appendChild(h('div.pf-app-header',
                h('div.pf-app-title', h('span.pf-icon', '♻️'), h('div', 'Recycling', h('div.pf-app-sub', 'Paleto Bay recycling plant'))),
                h('div.pf-row', lvl ? h('span.pf-badge.accent', lvl) : null, v && v.shift ? h('span.pf-badge.ok', 'On shift') : null,
                    h('button.pf-btn.sm.ghost', { type: 'button', onclick: load }, 'Refresh'))));
            root.appendChild(h('div.pf-tabs', TABS.map(([id, label]) => h('div.pf-tab' + (st.tab === id ? '.active' : ''), {
                onclick: () => { st.tab = id; ctx.storage.set('tab', id); render(); },
            }, label))));
            const body = h('div.pf-app-body.pf-stack');
            root.appendChild(body);
            if (st.error) { body.appendChild(h('div.pf-empty', st.error)); return; }
            if (!v) { body.appendChild(h('div.pf-empty', 'Loading…')); return; }
            const parts = st.tab === 'materials' ? materialsTab(v) : st.tab === 'level' ? levelTab(v) : st.tab === 'history' ? historyTab(v) : shiftTab(v);
            parts.forEach((p) => p && body.appendChild(p));
        }

        // pushes from the server while the app is open (every pick-up, sorting and clock in/out)
        ctx.on('state', (p) => {
            if (!st.view || !p) return;
            const wasOn = !!st.view.shift;
            st.view.shift = p.shift || null;
            if (p.stats) st.view.stats = p.stats;
            if (wasOn && !p.shift) load(); else render();
        });
        // the elapsed time and the pending state stay fresh
        ticker = setInterval(() => { if (st.view && st.view.shift && st.tab === 'shift') render(); }, 30000);

        render();
        return {
            start: load,
            destroy() { alive = false; if (ticker) clearInterval(ticker); },
        };
    }

    let instance = null;
    PFApps.register('recycle', {
        async mount(container, ctx) {
            if (instance) instance.destroy();
            instance = create(container, ctx);
            await instance.start();
        },
        unmount() {
            if (instance) instance.destroy();
            instance = null;
        },
    });
})();
