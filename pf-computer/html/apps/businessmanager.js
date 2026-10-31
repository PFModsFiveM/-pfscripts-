// Business Manager (pf-computer, a pf-devices app on the tablet and the computer).
// For a business's management: sales and money from the bank ledger and the city's sale reports,
// staff from the job roster (promote, demote, fire), wages paid by the paycheck, the menu and meals
// the registers sell, real stock, premises equipment, the company account and the business profile.
// For government staff with the 'businesses' permission: the city's business registry (owners,
// licences, compliance, bills, audit trail) with ownership transfers.
// Every action is checked on the server (server/devices.lua -> the computer's business actions);
// nothing shown here is made up, and every server string is rendered as text.
(function () {
    const ERRORS = {
        job_not_allowed: 'Your job has no business to manage.', insufficient_grade: 'Your rank cannot manage this business.',
        missing_job: 'You have no job.', not_boss: 'Only the boss can do that.', not_authorized: 'You are not allowed to do that.',
        job_mismatch: 'That is not your business.', invalid_price: 'Enter a valid price.', menu_full: 'The menu is full.',
        too_many_meals: 'There are too many meals.', item_not_found: 'That item no longer exists.', meal_not_found: 'That meal no longer exists.',
        invalid_coords: 'Stand where it should go.', too_many_stashes: 'This business has the most stash points it can have.',
        invalid_logo: 'The logo must be an https:// image address.', invalid_color: 'Pick a blip colour.',
        storage_starting: 'The business records are still loading. Try again in a moment.', storage_unavailable: 'The business records are not available right now.',
        records_unavailable: 'The records cannot be read right now.', insufficient_funds: 'Not enough money for that.',
        bank_unavailable: 'The bank is not responding.', invalid_amount: 'Enter a valid amount.', payment_failed: 'The bank refused the transfer.',
        cap_exceeded: 'A wage is above the city\'s cap.', invalid_wage: 'Enter valid wages.', payroll_unavailable: 'The payroll could not be updated.',
        grade_above_yours: 'You cannot promote above your own rank.', invalid_grade: 'There is no such rank.', outranks_you: 'They outrank you.',
        cannot_change_self: 'You cannot change your own rank.', cannot_fire_self: 'You cannot fire yourself.', employee_not_found: 'They no longer work here.',
        fire_failed: 'They could not be let go.', government_offline: 'City Hall is not responding.', government_unavailable: 'City Hall is not responding.',
        registry_unavailable: 'The business registry could not be read.', unknown_citizen: 'No citizen with that ID.',
        job_business: 'Mechanic shops belong to their job; the job boss runs them.', business_not_found: 'That business is no longer registered.',
        no_permission: 'You need the government businesses permission.', too_fast: 'Wait a moment before trying again.',
        rate_limited: 'Slow down a little.', server_error: 'Something went wrong on the server.', failed_to_update_item: 'The item could not be saved.',
        failed_to_add_item: 'The item could not be added.', failed_to_delete_item: 'The item could not be removed.',
        failed_to_delete_category: 'The category could not be removed.', failed_to_rename_category: 'The category could not be renamed.',
        missing_parameters: 'Fill in every field.', storage_unavailable_db: 'The database is unavailable.',
    };
    const err = (res, fallback) => (res && ERRORS[res.error]) || fallback || 'That did not work.';

    const BLIP_COLORS = [[1, 'White'], [2, 'Red'], [3, 'Green'], [5, 'Yellow'], [18, 'Blue'], [27, 'Purple'], [40, 'Orange'], [46, 'Light blue'], [47, 'Pink'], [60, 'Gold']];

    function when(v) {
        if (v == null || v === '') return '';
        let t = typeof v === 'number' ? v : Date.parse(v);
        if (typeof v === 'number' && v < 1e12) t = v * 1000;
        if (!t || Number.isNaN(t)) return String(v);
        return new Date(t).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
    }
    const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };

    PFApps.register('businessmanager', {
        mount(container, ctx) {
            const { h, money } = ctx;
            const S = {
                section: null, init: null, config: {}, data: {}, employees: [], grades: [], transactions: [], menu: [], meals: [],
                analytics: null, period: 'week', chart: 'bar', menuTab: 'items', menuCat: '', menuQuery: '',
                txType: '', txQuery: '', account: null, accountPage: 1, registry: null, regSelected: null, regEmployees: {},
                timers: [], busy: false,
            };

            const logo = h('div.pf-icon', '📊');
            const title = h('div', 'Business Manager');
            const sub = h('div.pf-app-sub', '');
            const nav = h('div.pf-app-nav');
            const body = h('div.pf-app-body');
            const root = h('div.pf-app.pfbiz.pfbiz-bm',
                h('div.pf-app-header',
                    h('div.pf-app-title', logo, h('div', title, sub)),
                    h('button.pf-btn.sm', { onclick: () => load() }, 'Refresh')),
                h('div.pf-app-side', nav, body));
            container.appendChild(root);

            // the tablet window is narrow: the side menu becomes a row
            const fit = () => root.classList.toggle('pfbiz-narrow', (container.clientWidth || 1000) < 760);
            if (typeof ResizeObserver !== 'undefined') { const ro = new ResizeObserver(fit); ro.observe(container); S.ro = ro; }
            fit();

            // ── small UI helpers ────────────────────────────────────────────
            function dialog(heading, content, actions, onClose) {
                const back = h('div.pfbiz-dialog-back');
                const close = () => { if (!back.isConnected) return; back.remove(); if (onClose) onClose(); };
                const box = h('div.pfbiz-dialog', h('h3', heading), content,
                    h('div.pfbiz-dialog-actions', h('button.pf-btn', { onclick: close }, (actions || []).length ? 'Cancel' : 'Close'),
                        ...(actions || []).map((a) => h('button.pf-btn' + (a.danger ? '.danger' : '.primary'), {
                            onclick: async () => { if ((await a.run()) !== false) close(); },
                        }, a.label))));
                back.appendChild(box);
                back.addEventListener('click', (e) => { if (e.target === back) close(); });
                root.appendChild(back);
                return close;
            }
            // the computer replaces window.confirm, so confirmations are asked inside the app
            function ask(text, label, danger) {
                return new Promise((resolve) => {
                    let answer = false;
                    dialog('Please confirm', h('p', text), [{ label: label || 'Confirm', danger, run: () => { answer = true; } }], () => resolve(answer));
                });
            }
            function field(label, input) { return h('div.pf-field', h('label', label), input); }
            function stat(label, value, cls) {
                return h('div.pf-card.pf-stat', h('div.pf-stat-value' + (cls ? '.' + cls : ''), value), h('div.pf-stat-label', label));
            }
            function section(heading, subText, ...children) {
                body.innerHTML = '';
                body.appendChild(h('h2.pfbiz-section-title', heading));
                if (subText) body.appendChild(h('p.pfbiz-section-sub', subText));
                children.forEach((c) => c && body.appendChild(c));
            }
            function empty(text) { return h('div.pf-empty', text); }
            function table(headers, rows) {
                return h('div.pfbiz-table-wrap', h('table.pf-table', h('thead', h('tr', headers.map((x) => h('th', x)))), h('tbody', rows)));
            }
            function badge(text, cls) { return h('span.pf-badge' + (cls ? '.' + cls : ''), text); }
            function statusBadge(status) {
                const s = String(status || '').toLowerCase();
                let cls = '';
                if (['open', 'active', 'current', 'compliant'].includes(s)) cls = 'ok';
                else if (['late', 'warning', 'expired', 'partial', 'unpaid'].includes(s)) cls = 'warn';
                else if (['closed', 'delinquent', 'non_compliant', 'flagged', 'suspended', 'revoked', 'none'].includes(s)) cls = 'bad';
                return badge(status || '-', cls);
            }
            async function rpc(method, payload, okText) {
                const res = await ctx.rpc(method, payload || {});
                if (!res || res.ok === false) { ctx.notify(err(res), 'error'); return null; }
                if (okText) ctx.notify(okText, 'success');
                return res;
            }

            // ── what the player can see ─────────────────────────────────────
            const isRestaurant = () => S.config.businessType === 'restaurant' || S.config.businessType === 'bar';
            const typeConfig = () => S.config.businessTypeConfig || {};
            const SECTIONS = [
                { id: 'dashboard', icon: '📈', label: 'Dashboard', group: 'business', render: renderDashboard },
                { id: 'analytics', icon: '📊', label: 'Analytics', group: 'business', render: renderAnalytics },
                { id: 'menu', icon: '🍽️', label: () => (isRestaurant() ? 'Menu' : 'Services'), group: 'business', render: renderMenu },
                { id: 'transactions', icon: '💳', label: 'Transactions', group: 'business', render: renderTransactions },
                { id: 'employees', icon: '👥', label: 'Employees', group: 'business', render: renderEmployees },
                { id: 'wages', icon: '💵', label: 'Wages', group: 'business', render: renderWages },
                { id: 'account', icon: '🏦', label: 'Company account', group: 'business', render: renderAccount },
                { id: 'inventory', icon: '📦', label: 'Inventory', group: 'business', render: renderInventory },
                { id: 'premises', icon: '🏗️', label: 'Premises', group: 'business', render: renderPremises },
                { id: 'settings', icon: '⚙️', label: 'Settings', group: 'business', render: renderSettings },
                { id: 'reg-overview', icon: '🏛️', label: 'Overview', group: 'registry', render: renderRegOverview },
                { id: 'reg-registry', icon: '📇', label: 'Registry', group: 'registry', render: renderRegRegistry },
                { id: 'reg-compliance', icon: '✅', label: 'Compliance', group: 'registry', render: renderRegCompliance },
                { id: 'reg-taxes', icon: '🧾', label: 'Taxes and bills', group: 'registry', render: renderRegTaxes },
                { id: 'reg-audit', icon: '📜', label: 'Audit log', group: 'registry', render: renderRegAudit },
            ];
            const visible = () => SECTIONS.filter((s) => (s.group === 'business' ? S.init && S.init.business : S.init && S.init.registry));

            function renderNav() {
                nav.innerHTML = '';
                let group = null;
                visible().forEach((s) => {
                    if (s.group !== group) {
                        group = s.group;
                        nav.appendChild(h('div.pfbiz-nav-group', group === 'business' ? 'Business' : 'City registry'));
                    }
                    const label = typeof s.label === 'function' ? s.label() : s.label;
                    nav.appendChild(h('div.pf-nav-item' + (S.section === s.id ? '.active' : ''), { onclick: () => go(s.id) },
                        h('span.pfbiz-nav-icon', s.icon), label));
                });
            }

            function go(id) {
                S.section = id;
                renderNav();
                const s = SECTIONS.find((x) => x.id === id);
                try { s.render(); } catch (e) { console.error('[businessmanager]', id, e); section('Something went wrong', null, empty('This page could not be shown.')); }
            }

            function renderHeader() {
                const cfg = S.config;
                logo.innerHTML = '';
                if (cfg.logoUrl && /^https:\/\//.test(cfg.logoUrl)) logo.appendChild(h('img.pfbiz-head-logo', { src: cfg.logoUrl, alt: '' }));
                else logo.textContent = typeConfig().icon || '📊';
                title.textContent = S.init && S.init.business ? (cfg.businessName || 'Business Manager') : 'Business Manager';
                sub.textContent = S.init && S.init.business ? (typeConfig().name || cfg.businessType || 'Business') : 'City business registry';
            }

            // ── loading ─────────────────────────────────────────────────────
            async function load() {
                const res = await ctx.rpc('init');
                if (!res || res.ok === false) { section('Business Manager', null, empty(err(res, 'The Business Manager is not available right now.'))); return; }
                S.init = res;
                const pick = (r, d) => (r && r.ok !== false && r.data !== undefined ? r.data : d);
                if (res.business) {
                    if (res.config && res.config.ok === false) { S.init.business = false; S.denied = res.config.error; } else S.config = pick(res.config, {}) || {};
                    S.data = pick(res.data, {}) || {};
                    S.employees = pick(res.employees, []) || [];
                    S.grades = (res.employees && res.employees.grades) || [];
                    S.transactions = pick(res.transactions, []) || [];
                    S.menu = pick(res.menu, []) || [];
                    S.meals = pick(res.meals, []) || [];
                }
                renderHeader();
                const list = visible();
                if (!list.length) {
                    nav.innerHTML = '';
                    section('Business Manager', null, empty(err({ error: S.denied || 'job_not_allowed' })));
                    return;
                }
                if (!S.section || !list.some((s) => s.id === S.section)) S.section = list[0].id;
                go(S.section);
            }

            async function reloadData() {
                const [data, tx] = await Promise.all([ctx.rpc('data'), ctx.rpc('transactions', { limit: 100 })]);
                if (data && data.ok !== false) S.data = data.data || {};
                if (tx && tx.ok !== false) S.transactions = tx.data || [];
            }
            async function reloadEmployees() {
                const res = await ctx.rpc('employees');
                if (res && res.ok !== false) { S.employees = res.data || []; S.grades = res.grades || S.grades; }
            }
            async function reloadMenu() {
                const [menu, meals] = await Promise.all([ctx.rpc('menu'), ctx.rpc('meals')]);
                if (menu && menu.ok !== false) S.menu = menu.data || [];
                if (meals && meals.ok !== false) S.meals = meals.data || [];
            }

            // ── dashboard ───────────────────────────────────────────────────
            function renderDashboard() {
                const stats = S.data.stats;
                const onDuty = S.employees.filter((e) => e.onDuty).length;
                const cards = h('div.pfbiz-stats');
                if (stats) {
                    cards.appendChild(stat('Sales today', money(stats.today && stats.today.revenue)));
                    cards.appendChild(stat('Sales this week', money(stats.week && stats.week.revenue)));
                    cards.appendChild(stat('Sales (30 days)', money(stats.month && stats.month.revenue)));
                    cards.appendChild(stat('Receipts today', String(num(stats.today && stats.today.sales))));
                    cards.appendChild(stat('Money in today', money(stats.today && stats.today.moneyIn), 'ok'));
                    cards.appendChild(stat('Money out today', money(stats.today && stats.today.moneyOut), 'bad'));
                }
                if (S.data.balance != null) cards.appendChild(stat('Company account', money(S.data.balance)));
                cards.appendChild(stat('Staff on duty', `${onDuty} / ${S.employees.length}`));
                const recent = S.transactions.slice(0, 6);
                const recentList = h('div.pf-list', recent.length ? recent.map((tx) => {
                    const amount = num(tx.amount != null ? tx.amount : tx.total);
                    const incoming = tx.incoming != null ? tx.incoming : amount >= 0;
                    return h('div.pf-list-item',
                        h('div', h('div.pf-strong', tx.description || tx.type || 'Payment'), h('div.pf-small.pf-muted', when(tx.date), tx.employee || tx.processedBy ? ' · ' + (tx.employee || tx.processedBy) : '')),
                        h('div' + (incoming ? '.pfbiz-in' : '.pfbiz-out'), (incoming ? '+' : '-') + money(Math.abs(amount))));
                }) : [empty('No payments yet.')]);
                const itemSales = {};
                S.transactions.forEach((tx) => (tx.items || []).forEach((it) => {
                    const key = it.name || 'Item';
                    itemSales[key] = itemSales[key] || { name: key, qty: 0, revenue: 0 };
                    itemSales[key].qty += num(it.quantity) || 1;
                    itemSales[key].revenue += num(it.price) * (num(it.quantity) || 1);
                }));
                const top = Object.values(itemSales).sort((a, b) => b.qty - a.qty).slice(0, 5);
                section('Dashboard', stats ? 'Sales from the city\'s receipts; money from the company bank account.' : 'The sales records cannot be read right now.',
                    cards,
                    h('div.pfbiz-two',
                        h('div.pf-card', h('div.pfbiz-card-title', 'Recent payments'), recentList),
                        top.length ? h('div.pf-card', h('div.pfbiz-card-title', 'Top selling items'),
                            h('div.pf-list', top.map((t, i) => h('div.pf-list-item', h('span', `#${i + 1} `, t.name), h('span.pf-small.pf-muted', `${t.qty} sold · ${money(t.revenue)}`)))))
                            : h('div.pf-card', h('div.pfbiz-card-title', 'Staff'), h('div.pf-list', S.employees.slice(0, 6).map((e) =>
                                h('div.pf-list-item', h('span', e.name), statusBadge(e.onDuty ? 'On duty' : (e.online || e.isActive ? 'Online' : 'Offline'))))
                                .concat(S.employees.length ? [] : [empty('No staff.')])))));
            }

            // ── analytics ───────────────────────────────────────────────────
            function series(a) {
                if (!a) return { labels: [], values: [] };
                if (a.series && a.series[S.period]) return a.series[S.period];
                if (Array.isArray(a.byDay)) return { labels: a.byDay.map((d) => String(d.day).slice(5)), values: a.byDay.map((d) => num(d.revenue)) };
                if (Array.isArray(a.salesByDay)) return { labels: a.salesByDay.map((d) => String(d.day || d.label || '')), values: a.salesByDay.map((d) => num(d.revenue || d.sales)) };
                return { labels: [], values: [] };
            }
            function barChart(s) {
                const max = Math.max(1, ...s.values);
                return h('div.pfbiz-chart', s.values.map((v, i) => h('div.pfbiz-bar',
                    h('div.pfbiz-bar-value', money(v)),
                    h('div.pfbiz-bar-fill', { style: { height: `${Math.max(1, (v / max) * 100)}%` } }),
                    h('div.pfbiz-bar-label', s.labels[i] || ''))));
            }
            function lineChart(s) {
                const NS = 'http://www.w3.org/2000/svg';
                const W = 600, H = 200, pad = 12;
                const values = s.values.length > 1 ? s.values : [s.values[0] || 0, s.values[0] || 0];
                const max = Math.max(1, ...values);
                const pts = values.map((v, i) => [pad + (i / (values.length - 1)) * (W - 2 * pad), H - pad - (v / max) * (H - 2 * pad)]);
                const svg = document.createElementNS(NS, 'svg');
                svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
                svg.setAttribute('preserveAspectRatio', 'none');
                svg.setAttribute('class', 'pfbiz-line');
                const area = document.createElementNS(NS, 'path');
                area.setAttribute('d', `M ${pts[0][0]} ${H - pad} ` + pts.map((p) => `L ${p[0]} ${p[1]}`).join(' ') + ` L ${pts[pts.length - 1][0]} ${H - pad} Z`);
                area.setAttribute('fill', 'rgba(56,189,248,0.15)');
                const line = document.createElementNS(NS, 'path');
                line.setAttribute('d', pts.map((p, i) => `${i ? 'L' : 'M'} ${p[0]} ${p[1]}`).join(' '));
                line.setAttribute('fill', 'none');
                line.setAttribute('stroke', '#38bdf8');
                line.setAttribute('stroke-width', '3');
                svg.appendChild(area);
                svg.appendChild(line);
                pts.forEach((p) => { const c = document.createElementNS(NS, 'circle'); c.setAttribute('cx', p[0]); c.setAttribute('cy', p[1]); c.setAttribute('r', '4'); c.setAttribute('fill', '#38bdf8'); svg.appendChild(c); });
                const first = s.labels[0] || '', last = s.labels[s.labels.length - 1] || '';
                return h('div', svg, h('div.pfbiz-line-labels', h('span', first), h('span', last)));
            }
            async function renderAnalytics() {
                const chip = (id, label, key) => h('div.pfbiz-chip' + (S[key] === id ? '.active' : ''), { onclick: () => { S[key] = id; if (key === 'period') S.analytics = null; renderAnalytics(); } }, label);
                const controls = h('div.pf-toolbar',
                    h('div.pfbiz-chips', chip('day', 'Day', 'period'), chip('week', 'Week', 'period'), chip('month', 'Month', 'period')),
                    h('div.pfbiz-chips', chip('bar', 'Bars', 'chart'), chip('line', 'Line', 'chart')));
                if (!S.analytics) {
                    section('Analytics', null, controls, empty('Loading…'));
                    const res = await ctx.rpc('analytics', { period: S.period });
                    if (S.section !== 'analytics') return;
                    if (!res || res.ok === false) { section('Analytics', null, controls, empty(err(res, 'The records cannot be read right now.'))); return; }
                    S.analytics = res.data || {};
                }
                const a = S.analytics;
                const s = series(a);
                const stats = h('div.pfbiz-stats',
                    stat('Sales', money(a.totalRevenue)), stat('Receipts', String(num(a.totalSales))), stat('Average receipt', money(a.averageTicket)),
                    stat('Sales tax', money(a.taxPaid)), stat('Money in', money(a.moneyIn), 'ok'), stat('Money out', money(a.moneyOut), 'bad'));
                const kinds = Array.isArray(a.byKind) ? a.byKind : [];
                section('Analytics', 'Owner deposits and withdrawals are left out of money in and out.', controls, stats,
                    h('div.pf-card', h('div.pfbiz-card-title', 'Sales per day'), s.values.length ? (S.chart === 'line' ? lineChart(s) : barChart(s)) : empty('No sales in this period.')),
                    h('div.pf-card', { style: { marginTop: '12px' } }, h('div.pfbiz-card-title', 'Money in and out by type'),
                        kinds.length ? table(['Type', 'Payments', 'In', 'Out'], kinds.map((k) => h('tr', h('td', k.kind), h('td', String(num(k.count))),
                            h('td.pfbiz-in', money(k.moneyIn)), h('td.pfbiz-out', money(k.moneyOut))))) : empty('No payments in this period.')));
            }

            // ── menu and meals ──────────────────────────────────────────────
            const itemId = (it) => (it.id != null ? it.id : it.item_id);
            const itemName = (it) => it.name || it.label || 'Item';
            async function categories() {
                const res = await ctx.rpc('categories');
                const list = res && res.ok !== false && Array.isArray(res.data) ? res.data.map(String) : [];
                (typeConfig().menuCategories || []).forEach((c) => { if (!list.includes(c)) list.push(c); });
                if (!list.length) list.push('General');
                return list;
            }
            function renderMenu() {
                const restaurant = isRestaurant();
                const tabs = h('div.pfbiz-chips',
                    h('div.pfbiz-chip' + (S.menuTab === 'items' ? '.active' : ''), { onclick: () => { S.menuTab = 'items'; renderMenu(); } }, restaurant ? 'Items' : 'Services'),
                    restaurant ? h('div.pfbiz-chip' + (S.menuTab === 'meals' ? '.active' : ''), { onclick: () => { S.menuTab = 'meals'; renderMenu(); } }, 'Meals') : null);
                const toolbar = h('div.pf-toolbar', tabs,
                    h('button.pf-btn.sm.primary', { onclick: () => (S.menuTab === 'meals' ? mealDialog() : itemDialog()) }, S.menuTab === 'meals' ? 'Add meal' : (restaurant ? 'Add item' : 'Add service')),
                    S.menuTab === 'items' ? h('button.pf-btn.sm', { onclick: categoryDialog }, 'Categories') : null);
                if (S.menuTab === 'meals' && restaurant) {
                    section('Meals', 'Combos of menu items sold at one price.', toolbar,
                        S.meals.length ? h('div.pfbiz-cards', S.meals.map(mealCard)) : empty('No meals yet. Combine menu items into a meal.'));
                    return;
                }
                const cats = [...new Set(S.menu.map((m) => m.category || 'General'))].sort();
                const select = h('select.pf-select', { style: { maxWidth: '200px' }, onchange: (e) => { S.menuCat = e.target.value; drawGrid(); } },
                    h('option', { value: '' }, 'All categories'), cats.map((c) => h('option', { value: c, selected: S.menuCat === c }, c)));
                const search = h('input.pf-input', { placeholder: 'Search', value: S.menuQuery, style: { maxWidth: '220px' }, oninput: (e) => { S.menuQuery = e.target.value; drawGrid(); } });
                const grid = h('div.pfbiz-cards');
                function drawGrid() {
                    grid.innerHTML = '';
                    const q = S.menuQuery.toLowerCase();
                    const list = S.menu.filter((m) => (!S.menuCat || (m.category || 'General') === S.menuCat)
                        && (!q || `${itemName(m)} ${m.description || ''}`.toLowerCase().includes(q)));
                    if (!list.length) grid.appendChild(empty(S.menu.length ? 'Nothing matches.' : 'Nothing on the menu yet.'));
                    list.forEach((m) => grid.appendChild(itemCard(m)));
                }
                drawGrid();
                section(restaurant ? 'Menu' : 'Services', 'These prices are what the business\'s registers charge.', toolbar, h('div.pf-toolbar', select, search), grid);
            }
            function itemCard(m) {
                const price = num(m.price), cost = num(m.cost);
                const available = m.available !== false;
                const toggle = h('input', { type: 'checkbox', checked: available, onchange: async (e) => {
                    const ok = await saveItem(m, { available: e.target.checked });
                    if (!ok) e.target.checked = !e.target.checked;
                } });
                return h('div.pf-card',
                    h('div.pf-row.between', badge(m.category || 'General', 'accent'), h('label.pfbiz-switch', toggle, available ? 'Available' : 'Unavailable')),
                    h('div.pf-strong', itemName(m)),
                    m.description ? h('div.pf-small.pf-muted', m.description) : null,
                    h('div.pfbiz-price-row', h('span', 'Price'), h('strong', money(price))),
                    cost ? h('div.pfbiz-price-row', h('span', 'Cost'), h('strong', money(cost))) : null,
                    cost ? h('div.pfbiz-price-row', h('span', 'Profit'), h('strong', `${money(price - cost)} (${price > 0 ? (((price - cost) / price) * 100).toFixed(1) : '0'}%)`)) : null,
                    h('div.pf-row', h('button.pf-btn.sm', { onclick: () => itemDialog(m) }, 'Edit'), h('button.pf-btn.sm.danger', { onclick: () => deleteItem(m) }, 'Delete')));
            }
            async function saveItem(m, changes) {
                const item = Object.assign({ name: itemName(m), category: m.category || 'General', price: num(m.price), description: m.description || '', available: m.available !== false }, changes);
                const res = await rpc('menuEdit', { itemId: itemId(m), item });
                if (!res) return false;
                await reloadMenu();
                if (S.section === 'menu') renderMenu();
                return true;
            }
            async function itemDialog(m) {
                const cats = await categories();
                const name = h('input.pf-input', { maxlength: 60, value: m ? itemName(m) : '' });
                const catSelect = h('select.pf-select', cats.map((c) => h('option', { value: c, selected: m && m.category === c }, c)), h('option', { value: '__new' }, 'New category…'));
                const newCat = h('input.pf-input', { maxlength: 40, placeholder: 'New category name', style: { display: 'none' } });
                catSelect.addEventListener('change', () => { newCat.style.display = catSelect.value === '__new' ? '' : 'none'; });
                const price = h('input.pf-input', { type: 'number', min: 0, step: '0.01', value: m ? num(m.price) : '' });
                const desc = h('textarea.pf-textarea', { maxlength: 300 }, m ? m.description || '' : '');
                const costOut = h('strong', money(m ? num(m.cost) : 0));
                const ingredients = (!m && isRestaurant()) ? (typeConfig().ingredients || []) : [];
                const picks = ingredients.map((ing) => ({ ing, check: h('input', { type: 'checkbox' }), qty: h('input.pf-input', { type: 'number', min: 1, max: 99, value: 1 }) }));
                const cost = () => picks.reduce((sum, p) => sum + (p.check.checked ? num(p.ing.cost) * Math.max(1, num(p.qty.value)) : 0), m ? num(m.cost) : 0);
                const updateCost = () => {
                    const c = cost(), p = num(price.value);
                    costOut.textContent = `${money(c)}${p > 0 && c > 0 ? ` · margin ${(((p - c) / p) * 100).toFixed(1)}%` : ''}`;
                };
                picks.forEach((p) => { p.check.addEventListener('change', updateCost); p.qty.addEventListener('input', updateCost); });
                price.addEventListener('input', updateCost);
                const form = h('div.pfbiz-form-grid',
                    field('Name', name), field('Category', h('div.pf-stack', { style: { gap: '6px' } }, catSelect, newCat)), field('Price', price),
                    h('div.pfbiz-wide', field('Description', desc)),
                    picks.length ? h('div.pfbiz-wide', field('Ingredients (sets the cost)', h('div.pfbiz-pick-list', picks.map((p) =>
                        h('label.pfbiz-pick', p.check, h('span', p.ing.name), h('span.pf-small.pf-muted', money(p.ing.cost)), p.qty))))) : null,
                    h('div.pfbiz-wide.pf-small.pf-muted', 'Cost: ', costOut));
                dialog(m ? 'Edit item' : (isRestaurant() ? 'New menu item' : 'New service'), form, [{
                    label: 'Save', run: async () => {
                        const category = catSelect.value === '__new' ? newCat.value.trim() : catSelect.value;
                        if (!name.value.trim() || !(num(price.value) > 0) || !category) { ctx.notify('Enter a name, a category and a price.', 'error'); return false; }
                        const item = { name: name.value.trim(), category, price: num(price.value), description: desc.value, available: m ? m.available !== false : true };
                        let res;
                        if (m) res = await rpc('menuEdit', { itemId: itemId(m), item }, 'Item saved');
                        else res = await rpc('menuAdd', { item: Object.assign(item, { cost: cost() }) }, 'Item added');
                        if (!res) return false;
                        await reloadMenu();
                        renderMenu();
                        return true;
                    },
                }]);
            }
            async function deleteItem(m) {
                if (!(await ask(`Remove ${itemName(m)} from the menu?`, 'Remove', true))) return;
                if (await rpc('menuDelete', { itemId: itemId(m) }, 'Item removed')) { await reloadMenu(); renderMenu(); }
            }
            async function categoryDialog() {
                const cats = await categories();
                const list = h('div.pf-list', cats.map((c) => {
                    const input = h('input.pf-input', { value: c, maxlength: 40, style: { maxWidth: '220px' } });
                    return h('div.pf-list-item', input, h('div.pf-row',
                        h('button.pf-btn.sm', { onclick: async () => {
                            const next = input.value.trim();
                            if (!next || next === c) return;
                            if (await rpc('categoryRename', { oldCategory: c, newCategory: next }, 'Category renamed')) { close(); await reloadMenu(); renderMenu(); }
                        } }, 'Rename'),
                        c !== 'General' ? h('button.pf-btn.sm.danger', { onclick: async () => {
                            if (!(await ask(`Delete the category ${c} and every item in it?`, 'Delete', true))) return;
                            if (await rpc('categoryDelete', { category: c }, 'Category deleted')) { close(); await reloadMenu(); renderMenu(); }
                        } }, 'Delete') : null));
                }));
                const close = dialog('Categories', h('div.pf-stack', h('p.pf-small.pf-muted', 'A new category is made when you add an item to it.'), list), []);
            }
            function mealCard(meal) {
                const parts = (meal.items || []).map((mi) => {
                    const it = S.menu.find((m) => String(itemId(m)) === String(mi.itemId));
                    return badge(`${it ? itemName(it) : 'Removed item'} ×${num(mi.quantity) || 1}`);
                });
                const toggle = h('input', { type: 'checkbox', checked: meal.available !== false, onchange: async (e) => {
                    if (!(await rpc('mealUpdate', { mealId: meal.id, available: e.target.checked }))) { e.target.checked = !e.target.checked; return; }
                    meal.available = e.target.checked;
                } });
                return h('div.pf-card',
                    h('div.pf-row.between', badge('Meal', 'accent'), h('label.pfbiz-switch', toggle, 'Available')),
                    h('div.pf-strong', meal.name), meal.description ? h('div.pf-small.pf-muted', meal.description) : null,
                    h('div.pfbiz-tagline', parts),
                    h('div.pfbiz-price-row', h('span', 'Meal price'), h('strong', money(meal.price))),
                    h('div.pf-row', h('button.pf-btn.sm', { onclick: () => mealDialog(meal) }, 'Edit'), h('button.pf-btn.sm.danger', { onclick: async () => {
                        if (!(await ask(`Delete the meal ${meal.name}?`, 'Delete', true))) return;
                        if (await rpc('mealDelete', { mealId: meal.id }, 'Meal deleted')) { await reloadMenu(); renderMenu(); }
                    } }, 'Delete')));
            }
            function mealDialog(meal) {
                const name = h('input.pf-input', { maxlength: 60, value: meal ? meal.name : '' });
                const price = h('input.pf-input', { type: 'number', min: 0, step: '0.01', value: meal ? num(meal.price) : '' });
                const desc = h('textarea.pf-textarea', { maxlength: 300 }, meal ? meal.description || '' : '');
                const summary = h('div.pf-small.pf-muted');
                const picks = S.menu.filter((m) => itemId(m) != null).map((m) => {
                    const had = meal && (meal.items || []).find((mi) => String(mi.itemId) === String(itemId(m)));
                    return { m, check: h('input', { type: 'checkbox', checked: !!had }), qty: h('input.pf-input', { type: 'number', min: 1, max: 20, value: had ? had.quantity : 1 }) };
                });
                const update = () => {
                    const chosen = picks.filter((p) => p.check.checked);
                    const total = chosen.reduce((s, p) => s + num(p.m.price) * Math.max(1, num(p.qty.value)), 0);
                    const diff = total - num(price.value);
                    summary.textContent = `${chosen.length} item(s), ${money(total)} on their own${num(price.value) > 0 && total > 0 ? ` · the meal ${diff >= 0 ? 'saves' : 'costs'} ${money(Math.abs(diff))}` : ''}`;
                };
                picks.forEach((p) => { p.check.addEventListener('change', update); p.qty.addEventListener('input', update); });
                price.addEventListener('input', update);
                update();
                dialog(meal ? 'Edit meal' : 'New meal', h('div.pfbiz-form-grid', field('Name', name), field('Price', price), h('div.pfbiz-wide', field('Description', desc)),
                    h('div.pfbiz-wide', field('Menu items in this meal', picks.length ? h('div.pfbiz-pick-list', picks.map((p) =>
                        h('label.pfbiz-pick', p.check, h('span', itemName(p.m)), h('span.pf-small.pf-muted', money(p.m.price)), p.qty))) : empty('Add menu items first.'))),
                    h('div.pfbiz-wide', summary)), [{
                    label: 'Save', run: async () => {
                        const items = picks.filter((p) => p.check.checked).map((p) => ({ itemId: Number(itemId(p.m)), quantity: Math.max(1, Math.min(20, Math.floor(num(p.qty.value)))) }));
                        if (!name.value.trim() || !(num(price.value) > 0) || !items.length) { ctx.notify('Enter a name, a price and at least one item.', 'error'); return false; }
                        const payload = { name: name.value.trim(), price: num(price.value), description: desc.value, items };
                        const res = meal ? await rpc('mealUpdate', Object.assign({ mealId: meal.id }, payload), 'Meal saved') : await rpc('mealAdd', Object.assign({ available: true }, payload), 'Meal added');
                        if (!res) return false;
                        await reloadMenu();
                        renderMenu();
                        return true;
                    },
                }]);
            }

            // ── transactions ────────────────────────────────────────────────
            function renderTransactions() {
                const types = [...new Set(S.transactions.map((t) => t.type || 'payment'))].sort();
                const typeSel = h('select.pf-select', { style: { maxWidth: '180px' }, onchange: (e) => { S.txType = e.target.value; draw(); } },
                    h('option', { value: '' }, 'All types'), types.map((t) => h('option', { value: t, selected: S.txType === t }, t)));
                const search = h('input.pf-input', { placeholder: 'Search', value: S.txQuery, style: { maxWidth: '220px' }, oninput: (e) => { S.txQuery = e.target.value; draw(); } });
                const holder = h('div');
                function draw() {
                    const q = S.txQuery.toLowerCase();
                    const rows = S.transactions.filter((t) => (!S.txType || (t.type || 'payment') === S.txType)
                        && (!q || `${t.description || ''} ${t.type || ''} ${t.processedBy || t.employee || ''}`.toLowerCase().includes(q)));
                    holder.innerHTML = '';
                    holder.appendChild(rows.length ? table(['Date', 'Type', 'Description', 'By', 'Amount'], rows.map((t) => {
                        const amount = num(t.amount != null ? t.amount : t.total);
                        const incoming = t.incoming != null ? t.incoming : amount >= 0;
                        const items = (t.items || []).map((it) => `${num(it.quantity) || 1}× ${it.name}`).join(', ');
                        return h('tr', h('td', when(t.date)), h('td', badge(t.type || 'payment')),
                            h('td', t.description || items || '-', t.paymentMethod ? h('div.pf-small.pf-muted', t.paymentMethod) : null),
                            h('td', t.employee || t.processedBy || '-'),
                            h('td' + (incoming ? '.pfbiz-in' : '.pfbiz-out'), (incoming ? '+' : '-') + money(Math.abs(amount))));
                    })) : empty('No payments match.'));
                }
                draw();
                section('Transactions', 'Every payment in or out of the company account (the bank ledger).', h('div.pf-toolbar', typeSel, search), holder);
            }

            // ── employees ───────────────────────────────────────────────────
            function renderEmployees() {
                const grades = S.grades || [];
                const cards = S.employees.map((e) => {
                    const state = e.onDuty ? ['On duty', 'ok'] : (e.online || e.isActive ? ['Online', 'warn'] : ['Offline', '']);
                    const rankSel = grades.length ? h('select.pf-select', { style: { maxWidth: '160px' } },
                        grades.map((g) => h('option', { value: g.level, selected: num(g.level) === num(e.grade) }, `${g.label} (${g.level})`))) : null;
                    return h('div.pf-card',
                        h('div.pf-row', h('div.pfbiz-avatar', e.isBoss ? '👔' : String(e.name || '?').charAt(0)),
                            h('div', { style: { flex: '1', minWidth: '0' } }, h('div.pf-strong', e.name || e.citizenid), h('div.pf-small.pf-muted', `${e.rank || 'Employee'} · grade ${num(e.grade)}`)),
                            badge(state[0], state[1])),
                        h('div.pfbiz-price-row', h('span', 'Paycheck'), h('strong', money(e.salary))),
                        e.isBoss ? h('div.pf-small.pf-muted', 'Boss') : h('div.pf-stack', { style: { gap: '6px' } },
                            h('div.pf-row', h('button.pf-btn.sm', { onclick: () => setGrade(e, num(e.grade) + 1) }, 'Promote'),
                                h('button.pf-btn.sm', { onclick: () => setGrade(e, num(e.grade) - 1) }, 'Demote'),
                                h('button.pf-btn.sm.danger', { onclick: () => fire(e) }, 'Fire')),
                            rankSel ? h('div.pf-row', rankSel, h('button.pf-btn.sm', { onclick: () => setGrade(e, num(rankSel.value)) }, 'Set rank')) : null));
                });
                section('Employees', 'Everyone with this job, online or not. Changes are saved on the character.',
                    cards.length ? h('div.pfbiz-cards', cards) : empty('No staff yet. Hire through the Job Board.'));
            }
            async function setGrade(e, grade) {
                if (grade < 0) return;
                const res = await rpc('employeeGrade', { employeeId: e.citizenid || e.id, grade });
                if (!res) return;
                ctx.notify(`${e.name} is now ${(res.data && res.data.rank) || 'updated'}.`, 'success');
                await reloadEmployees();
                if (S.section === 'employees') renderEmployees();
            }
            async function fire(e) {
                if (!(await ask(`Let ${e.name} go? They lose the job at once.`, 'Fire', true))) return;
                if (await rpc('employeeFire', { employeeId: e.citizenid || e.id }, `${e.name} was let go.`)) {
                    await reloadEmployees();
                    if (S.section === 'employees') renderEmployees();
                }
            }

            // ── wages ───────────────────────────────────────────────────────
            async function renderWages() {
                section('Wages', 'What the paycheck pays each rank, up to the city\'s wage caps.', empty('Loading…'));
                const res = await ctx.rpc('wages');
                if (S.section !== 'wages') return;
                if (!res || res.ok === false) { section('Wages', null, empty(err(res))); return; }
                const grades = (res.data && res.data.grades) || [];
                const inputs = {};
                const rows = grades.map((g) => {
                    const status = h('span.pf-small.pf-muted', '');
                    const input = h('input.pf-input', { type: 'number', min: 0, max: g.cap > 0 ? g.cap : undefined, step: 1, value: num(g.wage), style: { maxWidth: '120px' },
                        oninput: () => { status.textContent = num(input.value) !== num(g.wage) ? 'changed' : ''; if (g.cap > 0 && num(input.value) > g.cap) status.textContent = `above the cap of ${money(g.cap)}`; } });
                    inputs[g.level] = { input, g };
                    return h('tr', h('td', String(g.level)), h('td', g.label), h('td', money(g.wage)), h('td', g.cap > 0 ? money(g.cap) : 'none'), h('td', input), h('td', status));
                });
                const save = h('button.pf-btn.primary', { onclick: async () => {
                    const wages = {};
                    Object.values(inputs).forEach(({ input, g }) => { if (num(input.value) !== num(g.wage)) wages[String(g.level)] = Math.floor(num(input.value)); });
                    if (!Object.keys(wages).length) { ctx.notify('Nothing changed.', 'primary'); return; }
                    const out = await ctx.rpc('wagesSet', { wages });
                    if (!out || out.ok === false) {
                        const caps = out && out.data && out.data.errors;
                        ctx.notify(caps && caps.length ? `Above the cap for grade ${caps.map((c) => c.level).join(', ')}` : err(out), 'error');
                        return;
                    }
                    ctx.notify('Wages saved. The next paycheck pays them.', 'success');
                    renderWages();
                } }, 'Save wages');
                section('Wages', 'What the paycheck pays each rank, up to the city\'s wage caps.',
                    grades.length ? table(['Grade', 'Rank', 'Now', 'Cap', 'New wage', ''], rows) : empty('This job has no ranks.'),
                    h('div.pf-toolbar', { style: { marginTop: '12px' } }, save, h('button.pf-btn', { onclick: renderWages }, 'Reset')));
            }

            // ── company account ─────────────────────────────────────────────
            async function renderAccount(fresh) {
                if (!S.account || fresh !== false) {
                    section('Company account', null, empty('Loading…'));
                    const res = await ctx.rpc('account');
                    if (S.section !== 'account') return;
                    if (!res || res.ok === false) { section('Company account', null, empty(err(res))); return; }
                    S.account = res.data || { balance: 0, transactions: [] };
                }
                const acc = S.account;
                const amount = h('input.pf-input', { type: 'number', min: 0, step: '0.01', placeholder: 'Amount', style: { maxWidth: '140px' } });
                const note = h('input.pf-input', { maxlength: 100, placeholder: 'Note (optional)', style: { maxWidth: '240px' } });
                async function move(method, label) {
                    const value = num(amount.value);
                    if (!(value > 0)) { ctx.notify(ERRORS.invalid_amount, 'error'); return; }
                    if (S.busy) return;
                    S.busy = true;
                    const res = await rpc(method, { amount: value, description: note.value }, `${label} ${money(value)}`);
                    S.busy = false;
                    if (res) { S.account = res.data || S.account; S.accountPage = 1; renderAccount(false); reloadData(); }
                }
                const per = 10;
                const tx = acc.transactions || [];
                const pages = Math.max(1, Math.ceil(tx.length / per));
                S.accountPage = Math.min(Math.max(1, S.accountPage), pages);
                const slice = tx.slice((S.accountPage - 1) * per, S.accountPage * per);
                section('Company account', 'The business\'s bank account: wages, sales and supplies go through it.',
                    h('div.pfbiz-stats', stat('Balance', money(acc.balance))),
                    h('div.pf-card', h('div.pfbiz-card-title', 'Move money'), h('div.pf-toolbar', amount, note,
                        h('button.pf-btn.primary', { onclick: () => move('deposit', 'Deposited') }, 'Deposit from my bank'),
                        h('button.pf-btn', { onclick: () => move('withdraw', 'Withdrew') }, 'Withdraw to my bank')),
                        h('div.pf-small.pf-muted', 'Only the boss can withdraw.')),
                    h('div.pf-card', { style: { marginTop: '12px' } }, h('div.pfbiz-card-title', 'History'),
                        slice.length ? table(['Date', 'Type', 'Description', 'Amount'], slice.map((t) => h('tr', h('td', when(t.date)), h('td', badge(t.type || 'payment')),
                            h('td', t.description || '-'), h('td' + (t.incoming ? '.pfbiz-in' : '.pfbiz-out'), (t.incoming ? '+' : '-') + money(Math.abs(num(t.amount)))))))
                            : empty('No payments yet.'),
                        pages > 1 ? h('div.pfbiz-pager',
                            h('button.pf-btn.sm', { disabled: S.accountPage <= 1, onclick: () => { S.accountPage--; renderAccount(false); } }, 'Previous'),
                            h('span.pf-small', `Page ${S.accountPage} of ${pages}`),
                            h('button.pf-btn.sm', { disabled: S.accountPage >= pages, onclick: () => { S.accountPage++; renderAccount(false); } }, 'Next')) : null));
            }

            // ── inventory ───────────────────────────────────────────────────
            async function renderInventory() {
                const orderBtn = ctx.apps().some((a) => a.id === 'ordersupplies') ? h('button.pf-btn.sm.primary', { onclick: () => ctx.openApp('ordersupplies') }, 'Order stock') : null;
                section('Inventory', 'What is in the business\'s stock stashes now.', h('div.pf-toolbar', orderBtn), empty('Loading…'));
                const res = await ctx.rpc('stock');
                if (S.section !== 'inventory') return;
                const items = res && res.ok !== false && res.data ? res.data.items || [] : null;
                const grid = !items ? empty(err(res, 'The stock cannot be read right now.'))
                    : (items.length ? h('div.pfbiz-cards', items.map((it) => {
                        const level = it.amount > 50 ? 'ok' : (it.amount > 20 ? 'warn' : 'bad');
                        return h('div.pf-card', h('div.pf-row.between', h('span.pf-strong', it.label || it.name), badge(it.area || 'stock')),
                            h('div.pfbiz-price-row', h('span', 'In stock'), h('strong', badge(`${num(it.amount)} units`, level))),
                            it.freshness ? h('div.pfbiz-price-row', h('span', 'Freshness'), h('strong', `${it.freshness.label} (${Math.round(num(it.freshness.pct))}%)`)) : null);
                    })) : empty('No stock. Order supplies and unpack the delivery.'));
                section('Inventory', 'What is in the business\'s stock stashes now.', h('div.pf-toolbar', orderBtn), grid);
            }

            // ── premises ────────────────────────────────────────────────────
            async function renderPremises() {
                section('Premises', 'Equipment goes in slots the city has approved. It is paid from the company account.', empty('Loading…'));
                const res = await ctx.rpc('premises');
                if (S.section !== 'premises') return;
                if (!res || res.ok === false) { section('Premises', null, empty(`${err(res, 'Premises are not available.')} The business must be registered with the city.`)); return; }
                const d = res.data || res;
                const catalog = d.catalog || [];
                const rows = (d.slots || []).map((slot) => {
                    let action;
                    if (slot.equipment_type) action = badge(String(slot.equipment_type).replace(/_/g, ' '), 'ok');
                    else {
                        const options = catalog.filter((c) => c.slotType === slot.slot_type);
                        if (!options.length) action = h('span.pf-small.pf-muted', 'Nothing available');
                        else {
                            const sel = h('select.pf-select', { style: { maxWidth: '220px' } }, options.map((c) => h('option', { value: c.key }, `${c.label} (${money(c.price)})`)));
                            action = h('div.pf-row', sel, h('button.pf-btn.sm.primary', { onclick: async () => {
                                if (await rpc('premisesBuy', { slotId: Number(slot.id), equipmentType: sel.value }, 'Equipment installed')) renderPremises();
                            } }, 'Buy and install'));
                        }
                    }
                    return h('tr', h('td', slot.label || `#${slot.id}`), h('td', String(slot.slot_type || '').replace(/_/g, ' ')), h('td', action));
                });
                section('Premises', 'Equipment goes in slots the city has approved. Stand at the slot to install; it is paid from the company account.',
                    rows.length ? table(['Slot', 'Type', 'Equipment'], rows) : empty('No approved slots yet. Ask City Hall for a premises inspection.'));
            }

            // ── settings ────────────────────────────────────────────────────
            async function renderSettings() {
                const cfg = S.config;
                const name = h('input.pf-input', { maxlength: 50, value: cfg.businessName || '' });
                const logoUrl = h('input.pf-input', { maxlength: 300, placeholder: 'https://…', value: cfg.logoUrl || '' });
                const current = num(cfg.blipColor != null ? cfg.blipColor : 5);
                const color = h('select.pf-select', BLIP_COLORS.map(([v, l]) => h('option', { value: v, selected: v === current }, l)));
                const stashCount = h('span.pf-small.pf-muted', '');
                section('Settings', null,
                    h('div.pfbiz-two',
                        h('div.pf-card.pf-stack', h('div.pfbiz-card-title', 'Business profile'), field('Name', name), field('Logo (image address)', logoUrl), field('Map blip colour', color),
                            h('div.pf-row', h('button.pf-btn.primary', { onclick: async () => {
                                if (!name.value.trim()) { ctx.notify('Enter a name.', 'error'); return; }
                                const res = await rpc('settings', { name: name.value.trim(), logoUrl: logoUrl.value.trim(), blipColor: Number(color.value) }, 'Business profile saved');
                                if (res) { S.config.businessName = name.value.trim(); S.config.logoUrl = logoUrl.value.trim(); S.config.blipColor = Number(color.value); renderHeader(); }
                            } }, 'Save'))),
                        h('div.pf-card.pf-stack', h('div.pfbiz-card-title', 'Places'),
                            h('div.pf-small.pf-muted', 'Each of these is set where you stand now.'),
                            h('div.pf-row', h('button.pf-btn', { onclick: () => rpc('blipHere', { name: name.value.trim() || cfg.businessName, color: Number(color.value) }, 'The map blip is here now') }, 'Move the map blip here')),
                            h('div.pf-row', h('button.pf-btn', { onclick: async () => {
                                const res = await rpc('stashHere', {}, 'Stock stash point placed here');
                                if (res && res.data) stashCount.textContent = `${res.data.count} stash point(s)`;
                            } }, 'Place a stock stash point here'), stashCount),
                            h('div.pf-row', h('button.pf-btn', { onclick: () => rpc('deliveryPoint', {}, 'Place the delivery truck, then press E') }, 'Set the delivery point')),
                            h('div.pf-small.pf-muted', 'Staff open the business stock at its stash points. Suppliers and truckers deliver to the delivery point.'))));
            }

            // ── city registry (government) ──────────────────────────────────
            async function registry(force) {
                if (S.registry && !force) return S.registry;
                const res = await ctx.rpc('registry');
                S.registry = res && res.ok !== false ? res : { ok: false, error: res && res.error };
                return S.registry;
            }
            async function regPage(heading, draw) {
                section(heading, null, empty('Loading…'));
                const reg = await registry();
                if (!S.section.startsWith('reg-')) return;
                if (!reg.ok) { section(heading, null, empty(err(reg, 'The business registry could not be read.'))); return; }
                draw(reg);
            }
            function renderRegOverview() {
                regPage('Business oversight', (reg) => {
                    const top = [...reg.businesses].sort((a, b) => b.revenueWeek - a.revenueWeek).slice(0, 5);
                    const watch = reg.businesses.filter((b) => b.warnings.length).slice(0, 8);
                    section('Business oversight', 'Every business registered with the city.',
                        h('div.pfbiz-stats', stat('Registered', String(reg.stats.totalBusinesses)), stat('Open', String(reg.stats.activeBusinesses)),
                            stat('Sales today', money(reg.stats.revenueToday)), stat('Sales (7 days)', money(reg.stats.revenueWeek)),
                            stat('Sales (30 days)', money(reg.stats.revenueMonth)), stat('Sales tax (30 days)', money(reg.stats.taxMonth))),
                        h('div.pfbiz-two',
                            h('div.pf-card', h('div.pfbiz-card-title', 'Compliance risk'), h('div.pf-list',
                                h('div.pf-list-item', h('span', 'With unpaid bills'), badge(String(reg.alerts.unpaidTaxes), reg.alerts.unpaidTaxes ? 'bad' : 'ok')),
                                h('div.pf-list-item', h('span', 'Without an active licence'), badge(String(reg.alerts.unlicensed), reg.alerts.unlicensed ? 'warn' : 'ok')),
                                h('div.pf-list-item', h('span', 'Sales more than doubled week on week'), badge(String(reg.alerts.incomeSpikes), reg.alerts.incomeSpikes ? 'warn' : 'ok')))),
                            h('div.pf-card', h('div.pfbiz-card-title', 'Top sales (7 days)'), top.length ? h('div.pf-list', top.map((b) => h('div.pf-list-item', h('span', b.name), h('span', money(b.revenueWeek))))) : empty('No sales recorded.')),
                            h('div.pf-card', h('div.pfbiz-card-title', 'Watchlist'), watch.length ? h('div.pf-list', watch.map((b) => h('div.pf-list-item', h('span', b.name), h('span.pf-small.pf-muted', b.warnings.join(', '))))) : empty('Nothing flagged.'))));
                });
            }
            function renderRegRegistry() {
                regPage('Business registry', (reg) => {
                    const list = reg.businesses;
                    if (!S.regSelected && list[0]) S.regSelected = list[0].id;
                    const rows = list.map((b) => h('tr.pfbiz-click' + (b.id === S.regSelected ? '.pfbiz-active' : ''), { onclick: () => { S.regSelected = b.id; renderRegRegistry(); } },
                        h('td', b.name), h('td', b.owner), h('td', b.type), h('td', statusBadge(b.status)), h('td', money(b.revenueWeek)),
                        h('td', statusBadge(b.licenseStatus)), h('td', statusBadge(b.taxStatus))));
                    section('Business registry', 'Businesses register themselves when they are bought or opened.',
                        list.length ? table(['Business', 'Owner', 'Type', 'Status', 'Sales (7d)', 'Licence', 'Bills'], rows) : empty('No registered businesses.'),
                        details(list.find((b) => b.id === S.regSelected)));
                });
            }
            function details(b) {
                if (!b) return null;
                const row = (label, value) => h('div.pfbiz-price-row', h('span', label), h('strong', value));
                const staff = h('div', empty('Loading staff…'));
                const known = S.regEmployees[b.id];
                const drawStaff = (r) => {
                    staff.innerHTML = '';
                    if (!r || r.ok === false) { staff.appendChild(h('div.pf-small.pf-muted', err(r, 'Staff unknown.'))); return; }
                    const list = r.employees || [];
                    staff.appendChild(list.length ? h('div.pf-list', list.map((x) => h('div.pf-list-item', h('span', x.name || x.citizenid), h('span.pf-small.pf-muted', x.role || x.grade || '')))) : h('div.pf-small.pf-muted', 'No staff recorded.'));
                };
                if (known) drawStaff(known);
                else ctx.rpc('registryEmployees', { businessId: b.id }).then((r) => { S.regEmployees[b.id] = r; drawStaff(r); });
                return h('div.pf-card.pf-stack', { style: { marginTop: '12px' } },
                    h('div.pfbiz-card-title', b.name),
                    row('Business ID', b.id), row('Owner', b.owner + (b.ownerId ? ` (${b.ownerId})` : '')), row('Location', b.location),
                    row('Account balance', b.balance == null ? '-' : money(b.balance)), row('Sales (30 days)', `${money(b.revenueMonth)} from ${num(b.sales30d)} receipts`),
                    row('Sales tax (30 days)', money(b.taxMonth)), row('Unpaid bills', money(b.taxDebt)), row('Compliance', b.compliance),
                    row('Active licences', (b.permits || []).join(', ') || 'None'),
                    b.transferable ? h('div.pf-row', h('button.pf-btn.sm.primary', { onclick: () => transferDialog(b) }, b.ownerId ? 'Transfer ownership' : 'Assign an owner'),
                        b.ownerId ? h('button.pf-btn.sm.danger', { onclick: async () => {
                            if (!(await ask(`Remove ${b.owner} as owner of ${b.name}?`, 'Remove owner', true))) return;
                            transfer(b, null);
                        } }, 'Remove owner') : null) : h('div.pf-small.pf-muted', 'Owned by its job: the job boss runs it.'),
                    h('div.pfbiz-card-title', 'Staff'), staff,
                    h('div.pfbiz-card-title', 'Recent government activity'),
                    (b.activityLog || []).length ? h('div.pf-list', b.activityLog.map((a) => h('div.pf-list-item', h('span', a.action), h('span.pf-small.pf-muted', `${a.actor} · ${a.date}`)))) : h('div.pf-small.pf-muted', 'None recorded.'));
            }
            function transferDialog(b) {
                const sel = h('select.pf-select', h('option', { value: '' }, 'Online citizens…'), (S.registry.citizens || []).map((c) => h('option', { value: c.citizenId }, `${c.name} (${c.citizenId})`)));
                const typed = h('input.pf-input', { maxlength: 50, placeholder: 'Or type a citizen ID' });
                dialog(b.ownerId ? 'Transfer ownership' : 'Assign an owner', h('div.pf-stack', h('p', `New owner of ${b.name}:`), sel, typed), [{
                    label: 'Transfer', run: () => {
                        const id = typed.value.trim() || sel.value;
                        if (!id) { ctx.notify('Choose a citizen.', 'error'); return false; }
                        transfer(b, id);
                        return true;
                    },
                }]);
            }
            async function transfer(b, ownerId) {
                if (await rpc('registryTransfer', { businessId: b.id, ownerId: ownerId || '' }, 'Ownership updated')) {
                    S.regEmployees = {};
                    await registry(true);
                    renderRegRegistry();
                }
            }
            function renderRegCompliance() {
                regPage('Compliance', (reg) => {
                    const flagged = reg.businesses.filter((b) => b.warnings.length || String(b.licenseStatus).toLowerCase() !== 'active');
                    section('Compliance', 'Inspections, closures and licences are handled in the government apps.',
                        flagged.length ? table(['Business', 'Status', 'Licence', 'Compliance', 'Issues'], flagged.map((b) => h('tr', h('td', b.name), h('td', statusBadge(b.status)),
                            h('td', statusBadge(b.licenseStatus)), h('td', statusBadge(b.compliance)), h('td', b.warnings.join(', ') || 'No active licence')))) : empty('No compliance issues.'));
                });
            }
            function renderRegTaxes() {
                regPage('Taxes and bills', (reg) => {
                    const rows = [];
                    reg.businesses.forEach((b) => (b.bills || []).forEach((bill) => rows.push({ b, bill })));
                    const total = rows.reduce((s, r) => s + num(r.bill.owed), 0);
                    section('Taxes and bills', null, h('div.pfbiz-stats', stat('Outstanding', money(total)), stat('Open bills', String(rows.length))),
                        rows.length ? table(['Bill', 'Business', 'Type', 'Owed', 'Status', 'Due', 'Description'], rows.map(({ b, bill }) => h('tr', h('td', `#${bill.id}`), h('td', b.name),
                            h('td', bill.type || '-'), h('td', money(bill.owed)), h('td', statusBadge(bill.status)), h('td', bill.dueDate || '-'), h('td', bill.description || '')))) : empty('No unpaid business bills.'));
                });
            }
            function renderRegAudit() {
                regPage('Audit log', (reg) => {
                    section('Audit log', 'The latest government actions.', (reg.auditLog || []).length ? table(['Time', 'Action', 'By', 'Target'], reg.auditLog.map((a) =>
                        h('tr', h('td', a.timestamp), h('td', a.action), h('td', a.actor), h('td', a.target)))) : empty('No entries.'));
                });
            }

            // ── live refresh ────────────────────────────────────────────────
            async function refreshLive() {
                if (!S.init || !S.init.business) return;
                if (S.section === 'dashboard' || S.section === 'transactions') {
                    await reloadData();
                    if (S.section === 'dashboard') renderDashboard();
                    else if (S.section === 'transactions' && !body.querySelector('input:focus')) renderTransactions();
                }
            }
            S.timers.push(setInterval(refreshLive, 30000));
            ctx.on('staff', async () => { await reloadEmployees(); if (S.section === 'employees' || S.section === 'dashboard') go(S.section); });
            ctx.on('settings', async () => {
                const res = await ctx.rpc('config');
                if (res && res.ok !== false) { S.config = res.data || S.config; renderHeader(); }
            });
            ctx.on('stock', () => { if (S.section === 'inventory') renderInventory(); });
            S.ctx = ctx;
            ctx.__bm = S;
            load();
        },
        unmount(ctx) {
            const S = ctx && ctx.__bm;
            if (!S) return;
            S.timers.forEach(clearInterval);
            if (S.ro) S.ro.disconnect();
        },
    });
})();
