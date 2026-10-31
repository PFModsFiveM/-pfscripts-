/*
 * Vineyard app (pf-devices platform module, tablet + computer, vineyard job): today's picking
 * shift, the juice press and the wine barrel, what the worker carries, where to sell (the wholesale
 * buyer, or restaurants through the Supplier app) and the worker's level. Everything comes from the
 * server (server/apps/vineyard.lua via ctx.rpc and the 'state' push); the only action is ending a
 * picking shift early. DOM is built with ctx.h inside the given container.
 */
(function () {
    'use strict';
    if (!window.PFApps) return;

    const ERRORS = {
        not_authorized: 'The Vineyard app is for vineyard workers',
        off_shift: 'You are not on a picking shift',
        rate_limited: 'Slow down a little',
        server_error: 'Something went wrong',
        request_failed: 'Could not reach the server',
        no_player: 'Your character is not loaded',
    };
    const TABS = [['today', 'Today'], ['selling', 'Selling'], ['level', 'Level']];

    function create(container, ctx) {
        const { h, money } = ctx;
        const st = { tab: ctx.storage.get('tab', 'today'), view: null, error: null, busy: false, loadedAt: Date.now() };
        let alive = true;
        let ticker = null;

        const root = h('div.pf-app.pfj-vy');
        container.appendChild(root);
        const num = (v, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);
        const text = (v) => (v == null ? '' : String(v));
        // seconds left on a server timer, counted down since the view arrived
        const left = (t) => Math.max(0, num(t && t.readyIn) - Math.floor((Date.now() - st.loadedAt) / 1000));
        const duration = (s) => (s >= 60 ? `${Math.floor(s / 60)} min ${s % 60} s` : `${s} s`);

        async function load() {
            const res = await ctx.rpc('getInit');
            if (!alive) return;
            if (!res || res.ok === false) st.error = ERRORS[res && res.error] || 'The vineyard is not answering';
            else { st.error = null; st.view = res; st.loadedAt = Date.now(); }
            render();
        }

        async function endShift() {
            if (st.busy) return;
            st.busy = true;
            render();
            const res = await ctx.rpc('endShift');
            st.busy = false;
            if (!alive) return;
            if (res && res.ok !== false) { st.view = res; st.loadedAt = Date.now(); ctx.notify('Picking shift ended', 'primary'); }
            else ctx.notify(ERRORS[res && res.error] || 'That did not work', 'error');
            render();
        }

        function waypoint(label, x, y) {
            ctx.setWaypoint(num(x), num(y));
            ctx.notify(`Waypoint set: ${label}`, 'success');
        }

        function stat(label, value) {
            return h('div.pf-card.pf-stat', h('div.pf-stat-label', label), h('div.pf-stat-value', text(value)));
        }

        function table(head, rows) {
            return h('div.pfj-vy-scroll', h('table.pf-table', h('thead', h('tr', head.map((c) => h('th', c)))), h('tbody', rows)));
        }

        function bar(pct) { return h('div.pfj-vy-bar', h('div', { style: { width: Math.max(0, Math.min(100, pct)) + '%' } })); }

        function todayTab(v) {
            const out = [];
            const s = v.shift;
            const r = v.recipe || {};
            const c = v.carrying || {};
            if (s) {
                out.push(h('div.pf-card',
                    h('div.pf-row.between', h('div.pf-strong', 'Picking shift'), h('span.pf-muted.pf-small', `Started ${ctx.timeAgo(s.startedAt)}`)),
                    h('div.pf-muted.pf-small', `${num(s.picked)} of ${num(s.goal)} vines picked · ${num(s.grapes)} grapes`),
                    bar((num(s.picked) / Math.max(1, num(s.goal))) * 100),
                    h('div.pf-row.pfj-vy-wrap',
                        s.vine ? h('button.pf-btn.primary', { type: 'button', onclick: () => waypoint('next vine', s.vine.x, s.vine.y) }, 'Waypoint to the next vine') : null,
                        h('button.pf-btn.danger', { type: 'button', disabled: st.busy, onclick: endShift }, st.busy ? 'Working…' : 'End shift'))));
            } else {
                out.push(h('div.pf-card', h('div.pf-strong', 'No picking shift'),
                    h('div.pf-muted.pf-small', `Start one at the vineyard office: ${num(r.vinesPerShift && r.vinesPerShift[0], 8)}–${num(r.vinesPerShift && r.vinesPerShift[1], 12)} vines, one at a time.`)));
            }
            const press = v.press;
            const pressLeft = press ? left(press) : 0;
            out.push(h('div.pf-card',
                h('div.pf-row.between', h('div.pf-strong', 'Juice press'),
                    press ? h('span.pf-badge.' + (pressLeft > 0 ? 'accent' : 'ok'), pressLeft > 0 ? `Pressing · ${duration(pressLeft)}` : 'Juice ready to collect') : h('span.pf-badge', 'Empty')),
                h('div.pf-muted.pf-small', `${num(r.grapesPerJuice, 16)} grapes make a batch of grape juice.`)));
            const barrel = v.barrel;
            const barrelLeft = barrel ? left(barrel) : 0;
            out.push(h('div.pf-card',
                h('div.pf-row.between', h('div.pf-strong', 'Wine barrel'),
                    barrel ? h('span.pf-badge.' + (barrelLeft > 0 ? 'accent' : 'ok'), barrelLeft > 0 ? `Fermenting · ${duration(barrelLeft)}` : 'Ready to bottle') : h('span.pf-badge', 'Empty')),
                h('div.pf-muted.pf-small', `${num(r.juicePerWine, 23)} grape juice ferment into wine in ${num(r.wineMinutes, 3)} minutes.`)));
            out.push(h('div.pf-grid.pfj-vy-stats',
                stat('Grapes', num(c.grape)), stat('Grape juice', num(c.grapejuice)), stat('Wine', num(c.wine)),
                stat('Batches you can press', Math.floor(num(c.grape) / Math.max(1, num(r.grapesPerJuice, 16))))));
            out.push(h('div.pf-card', h('div.pf-strong', 'Places'),
                h('div.pf-list.pfj-vy-places', (v.places || []).map((p) => h('div.pf-list-item', h('span', text(p.label)),
                    h('button.pf-btn.sm', { type: 'button', onclick: () => waypoint(text(p.label), p.x, p.y) }, 'Waypoint'))))));
            return out;
        }

        function sellingTab(v) {
            const rows = (v.prices || []).map((p) => h('tr', h('td', text(p.label)),
                h('td', p.buyer != null ? money(p.buyer) : '—'), h('td', p.restaurants != null ? money(p.restaurants) : '—')));
            const buyer = (v.places || []).find((p) => /buyer/i.test(text(p.label)));
            return [
                table(['Product', 'Wholesale buyer pays', 'Restaurants pay up to'], rows),
                h('div.pf-card',
                    h('div.pf-strong', 'Sell to restaurants'),
                    h('div.pf-muted.pf-small', 'Restaurants order wine and grape juice as supplies. Register as a supplier, set your price (up to what restaurants pay) and stock what you carry; orders you accept are delivered by truckers.'),
                    v.supplierApp ? h('div.pf-row', h('button.pf-btn.primary', { type: 'button', onclick: () => ctx.openApp('supplier') }, 'Open the Supplier app')) : null),
                buyer ? h('div.pf-row', h('button.pf-btn', { type: 'button', onclick: () => waypoint(text(buyer.label), buyer.x, buyer.y) }, 'Waypoint to the wholesale buyer')) : null,
            ];
        }

        function levelTab(v) {
            const s = v.stats || {};
            const base = num(s.levelXp);
            const next = s.nextXp != null ? num(s.nextXp) : null;
            const pct = next ? ((num(s.xp) - base) / Math.max(1, next - base)) * 100 : 100;
            const xp = (v.recipe && v.recipe.xp) || {};
            return [
                h('div.pf-card',
                    h('div.pf-row.between', h('div.pf-strong', `Level ${num(s.level, 1)} · ${text(s.title)}`), h('span.pf-muted.pf-small', next ? `${num(s.xp)} / ${next} XP` : `${num(s.xp)} XP · top level`)),
                    bar(pct),
                    h('div.pf-muted.pf-small', `+${num(xp.vine)} XP per vine, +${num(xp.juice)} per juice batch, +${num(xp.wine)} per barrel`)),
                h('div.pf-grid.pfj-vy-stats',
                    stat('Vines picked', num(s.vines)), stat('Grapes', num(s.grapes)), stat('Juice pressed', num(s.juice)),
                    stat('Wine bottled', num(s.wine)), stat('Shifts', num(s.shifts)), stat('Sold to the buyer', money(s.sold))),
                table(['Level', 'XP', 'Extra grapes / vine', 'Extra per batch'], (v.levels || []).map((l) => h('tr' + (num(l.level) === num(s.level) ? '.pfj-vy-current' : ''),
                    h('td', `${num(l.level)} · ${text(l.title)}`), h('td', text(num(l.xp))), h('td', `+${num(l.grapeBonus)}`), h('td', `+${num(l.batchBonus)}`)))),
            ];
        }

        function render() {
            if (!alive) return;
            root.textContent = '';
            const v = st.view;
            root.appendChild(h('div.pf-app-header',
                h('div.pf-app-title', h('span.pf-icon', '🍇'), h('div', 'Vineyard', h('div.pf-app-sub', 'Picking, pressing and wine'))),
                h('div.pf-row', v && v.stats ? h('span.pf-badge.accent', `Level ${num(v.stats.level, 1)}`) : null, v && v.shift ? h('span.pf-badge.ok', 'Picking') : null,
                    h('button.pf-btn.sm.ghost', { type: 'button', onclick: load }, 'Refresh'))));
            root.appendChild(h('div.pf-tabs', TABS.map(([id, label]) => h('div.pf-tab' + (st.tab === id ? '.active' : ''), {
                onclick: () => { st.tab = id; ctx.storage.set('tab', id); render(); },
            }, label))));
            const body = h('div.pf-app-body.pf-stack');
            root.appendChild(body);
            if (st.error) { body.appendChild(h('div.pf-empty', st.error)); return; }
            if (!v) { body.appendChild(h('div.pf-empty', 'Loading…')); return; }
            if (!v.available) body.appendChild(h('div.pf-card.pfj-vy-note', 'The winery is closed right now: barrels cannot be filled until it opens again.'));
            const parts = st.tab === 'selling' ? sellingTab(v) : st.tab === 'level' ? levelTab(v) : todayTab(v);
            parts.forEach((p) => p && body.appendChild(p));
        }

        // every pick, press and barrel change while the app is open; the item counts come with a refresh
        ctx.on('state', () => load());
        ticker = setInterval(() => {
            const v = st.view;
            if (v && st.tab === 'today' && (v.press || v.barrel)) render();
        }, 5000);

        render();
        return {
            start: load,
            destroy() { alive = false; if (ticker) clearInterval(ticker); },
        };
    }

    let instance = null;
    PFApps.register('vineyard', {
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
