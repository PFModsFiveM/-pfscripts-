// Order Supplies (pf-computer, a pf-devices app on the tablet and the computer).
// A business boss or a store owner orders stock through the city's shared supply-order service
// (pf-stores): prices come from the server's catalog, the order is paid from the business's or the
// store's bank account, and it is collected (pickup run or straight into the store stock) or
// delivered by a trucker. Orders can be cancelled while no trucker has taken them.
// Every action is checked on the server (server/devices.lua -> the computer's supply actions).
(function () {
    const ERRORS = {
        no_store: 'You do not own a store.', job_not_allowed: 'Your job has no business that orders supplies.',
        insufficient_grade: 'Your rank cannot order for this business.', not_authorized: 'Only the boss can spend the business account.',
        not_boss: 'Only the boss can do that.', empty_cart: 'Your cart is empty.', insufficient_funds: 'Not enough money in the business account.',
        insufficient_store_funds: 'Not enough money in the store account. Deposit in the store\'s manage panel.',
        bank_unavailable: 'Payments are unavailable right now.', payment_failed: 'The payment failed. Nothing was charged.',
        delivery_unavailable: 'Delivery is not available for this business yet.', trucking_disabled: 'Trucking delivery is off for this store.',
        delivery_locations_not_configured: 'Trucking delivery is not set up for this store.',
        contract_create_failed: 'Trucking dispatch is unavailable; the money was refunded.', stores_offline: 'The supply service is offline.',
        stores_unavailable: 'The supply service is not responding.', order_not_ready: 'That order is not ready to collect yet.',
        order_not_found: 'That order no longer exists.', not_cancellable: 'This order can no longer be cancelled.',
        already_claimed: 'A trucker has already taken this delivery.', invalid_order: 'That order no longer exists.',
        storage_starting: 'The business records are still loading.', storage_unavailable: 'The business records are not available right now.',
        rate_limited: 'Slow down a little.', server_error: 'Something went wrong on the server.', pickup_start_failed: 'The pickup run could not start.',
    };
    const err = (res, fallback) => (res && (ERRORS[res.error] || res.message)) || fallback || 'That did not work.';
    const FINISHED = ['picked_up', 'cancelled', 'failed'];
    const STATUS = {
        pending: ['Waiting', 'warn'], ready: ['Ready to collect', 'accent'], in_transit: ['On the road', 'accent'], delivered: ['Delivered', 'ok'],
        picked_up: ['Done', 'ok'], cancelled: ['Cancelled', ''], failed: ['Failed', 'bad'],
    };
    const DETAIL = {
        created: 'Placed', paid: 'Paid', awaiting_supplier: 'Paid · offered to suppliers', awaiting_delivery: 'Paid · waiting for a trucker',
        assigned: 'A trucker accepted the delivery', in_transit: 'On the road', delivered: 'Delivered · unpack the pallet at the business',
        ready: 'Paid · ready to collect', unpacked: 'Unpacked into the stock', cancelled: 'Cancelled and refunded', failed: 'Failed',
    };
    const STEPS = [['paid', 'Paid'], ['ready', 'Ready / on the way'], ['delivered', 'Arrived'], ['done', 'In stock']];
    const stepOf = (o) => {
        const s = o.orderStatus || o.status;
        if (['unpacked', 'picked_up'].includes(s)) return 3;
        if (s === 'delivered') return 2;
        if (['ready', 'assigned', 'in_transit'].includes(s)) return 1;
        return 0;
    };
    const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
    function when(v) {
        let t = typeof v === 'number' ? v : Date.parse(v);
        if (typeof v === 'number' && v < 1e12) t = v * 1000;
        if (!t || Number.isNaN(t)) return '';
        return new Date(t).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
    }

    PFApps.register('ordersupplies', {
        mount(container, ctx, params) {
            const { h, money } = ctx;
            const S = {
                tab: 'shop', data: null, cart: [], orders: [], ordersKey: '', category: 'all', sort: 'desc', search: '',
                fulfillment: 'pickup', mode: (params && params.mode) || null, storeId: null, busy: false, timers: [],
            };
            const title = h('div', 'Order Supplies');
            const sub = h('div.pf-app-sub', '');
            const headActions = h('div.pf-row');
            const tabs = h('div.pf-tabs');
            const body = h('div.pf-app-body');
            const root = h('div.pf-app.pfbiz.pfbiz-os',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '📦'), h('div', title, sub)), headActions), tabs, body);
            container.appendChild(root);

            const context = (extra) => Object.assign({}, S.mode ? { mode: S.mode } : {}, S.storeId ? { storeId: S.storeId } : {}, extra || {});
            const isStore = () => S.data && S.data.mode === 'store';
            const empty = (text) => h('div.pf-empty', text);
            const badge = (text, cls) => h('span.pf-badge' + (cls ? '.' + cls : ''), text);
            const items = () => (S.data && S.data.catalog && S.data.catalog.items) || [];
            const imageOf = (it) => it.image || `${(S.data.catalog && S.data.catalog.imageBase) || 'https://cfx-nui-pfm-inventory/html/images/'}${it.item}.png`;
            const cartCount = () => S.cart.reduce((n, l) => n + l.quantity, 0);
            const cartTotal = () => S.cart.reduce((n, l) => n + num(l.pricePerCase) * l.quantity, 0);

            function image(it) {
                const img = h('img.pfbiz-supply-img', { src: imageOf(it), alt: '' });
                img.addEventListener('error', () => { img.style.visibility = 'hidden'; });
                return img;
            }

            function renderHead() {
                const d = S.data || {};
                const mechanic = d.businessType === 'mechanic';
                title.textContent = d.businessName ? `${d.businessName} · ${mechanic ? 'Order parts' : 'Order supplies'}` : 'Order Supplies';
                sub.textContent = isStore()
                    ? `Store account: ${d.balance == null ? 'unknown' : money(d.balance)}. Orders are paid from it.`
                    : (d.businessName ? 'Paid from the company account.' : '');
                headActions.innerHTML = '';
                const stores = (d.stores || []).filter((s) => s && s.storeId);
                if (isStore() && stores.length > 1) {
                    headActions.appendChild(h('select.pf-select', { style: { maxWidth: '200px' }, onchange: (e) => { S.storeId = e.target.value; S.cart = []; load(); } },
                        stores.map((s) => h('option', { value: s.storeId, selected: s.storeId === d.storeId }, s.label || s.storeId))));
                }
                if (d.canSwitch) {
                    headActions.appendChild(h('button.pf-btn.sm', { onclick: () => { S.mode = isStore() ? 'job' : 'store'; S.storeId = null; S.cart = []; load(); } },
                        isStore() ? 'Order for my job business' : 'Order for my store'));
                }
                headActions.appendChild(h('button.pf-btn.sm.primary', { onclick: () => show('cart') }, `Cart (${cartCount()})`));
            }

            function renderTabs() {
                tabs.innerHTML = '';
                const active = S.orders.filter((o) => !FINISHED.includes(o.status)).length;
                [['shop', 'Shop'], ['cart', `Cart (${cartCount()})`], ['orders', `Orders${active ? ` (${active})` : ''}`], ['history', 'History'], ['settings', 'Delivery']]
                    .forEach(([id, label]) => tabs.appendChild(h('div.pf-tab' + (S.tab === id ? '.active' : ''), { onclick: () => show(id) }, label)));
            }

            function show(tab) {
                S.tab = tab;
                renderTabs();
                renderHead();
                body.innerHTML = '';
                ({ shop: renderShop, cart: renderCart, orders: renderOrders, history: renderHistory, settings: renderSettings })[tab]();
            }

            // ── shop ────────────────────────────────────────────────────────
            function renderShop() {
                const cats = [{ id: 'all', label: 'All' }].concat((S.data.catalog && S.data.catalog.categories) || []);
                const chips = h('div.pfbiz-chips', cats.map((c) => h('div.pfbiz-chip' + (S.category === c.id ? '.active' : ''), { onclick: () => { S.category = c.id; show('shop'); } }, c.label || c.id)));
                const sortBtn = h('button.pf-btn.sm', { onclick: () => { S.sort = S.sort === 'asc' ? 'desc' : 'asc'; show('shop'); } }, `Price: ${S.sort === 'asc' ? 'low to high' : 'high to low'}`);
                const search = h('input.pf-input', { placeholder: 'Search supplies', value: S.search, style: { maxWidth: '240px' } });
                const list = h('div.pf-stack');
                search.addEventListener('input', () => { S.search = search.value; drawList(); });
                function drawList() {
                    list.innerHTML = '';
                    const q = S.search.toLowerCase();
                    const shown = items().filter((it) => (S.category === 'all' || it.category === S.category)
                        && (!q || `${it.label} ${it.category}`.toLowerCase().includes(q)))
                        .sort((a, b) => (S.sort === 'asc' ? 1 : -1) * (num(a.pricePerCase) - num(b.pricePerCase)));
                    if (!shown.length) { list.appendChild(empty(items().length ? 'Nothing matches.' : 'There is nothing to order for this business.')); return; }
                    const groups = {};
                    shown.forEach((it) => { (groups[it.category || 'Supplies'] = groups[it.category || 'Supplies'] || []).push(it); });
                    Object.keys(groups).forEach((cat) => {
                        list.appendChild(h('div.pfbiz-card-title', cat));
                        list.appendChild(h('div.pfbiz-cards', groups[cat].map(supplyCard)));
                    });
                }
                drawList();
                body.appendChild(h('div.pf-toolbar', chips, sortBtn, search));
                body.appendChild(list);
            }

            function supplyCard(it) {
                const qty = h('input.pf-input', { type: 'number', min: 1, max: 100, value: 1 });
                const step = (d) => { qty.value = String(Math.max(1, Math.min(100, Math.floor(num(qty.value)) + d))); };
                return h('div.pf-card.pfbiz-supply',
                    h('div.pfbiz-supply-top', image(it), h('div', h('div.pf-strong', it.label || it.item),
                        h('div.pf-small', `${money(it.pricePerCase)} per case`), h('div.pf-small.pf-muted', it.caseContents || `${num(it.caseSize) || 1} per case`))),
                    it.stock != null ? h('div.pf-small.pf-muted', `In your stock: ${num(it.stock)}`) : null,
                    h('div.pf-row.between', h('div.pfbiz-qty', h('button.pf-btn.sm', { onclick: () => step(-1) }, '−'), qty, h('button.pf-btn.sm', { onclick: () => step(1) }, '+')),
                        h('button.pf-btn.sm.primary', { onclick: () => add(it, Math.max(1, Math.min(100, Math.floor(num(qty.value))))) }, 'Add to cart')));
            }

            function add(it, quantity) {
                const line = S.cart.find((l) => l.item === it.item);
                if (line) line.quantity = Math.min(1000, line.quantity + quantity);
                else S.cart.push(Object.assign({}, it, { quantity }));
                ctx.notify(`Added ${quantity} case(s) of ${it.label || it.item}`, 'success');
                renderTabs();
                renderHead();
            }

            // ── cart ────────────────────────────────────────────────────────
            function renderCart() {
                if (!S.cart.length) { body.appendChild(empty('Your cart is empty. Add supplies from the shop.')); return; }
                const delivery = S.data.deliveryAvailable === true;
                if (!delivery) S.fulfillment = 'pickup';
                body.appendChild(h('div.pf-stack', S.cart.map((l, i) => h('div.pf-card.pfbiz-cart-line',
                    image(l),
                    h('div', h('div.pf-strong', l.label || l.item), h('div.pf-small.pf-muted', `${money(l.pricePerCase)} per case`)),
                    h('div.pfbiz-qty', h('button.pf-btn.sm', { onclick: () => { l.quantity = Math.max(1, l.quantity - 1); show('cart'); } }, '−'),
                        h('span', String(l.quantity)), h('button.pf-btn.sm', { onclick: () => { l.quantity = Math.min(1000, l.quantity + 1); show('cart'); } }, '+')),
                    h('div.pf-strong', money(num(l.pricePerCase) * l.quantity)),
                    h('button.pf-btn.sm.danger', { onclick: () => { S.cart.splice(i, 1); show('cart'); } }, 'Remove')))));
                const option = (id, label, enabled) => h('div.pfbiz-chip' + (S.fulfillment === id ? '.active' : ''), {
                    onclick: () => { if (enabled) { S.fulfillment = id; show('cart'); } },
                    style: enabled ? {} : { opacity: '.5', cursor: 'default' },
                }, label);
                const note = S.fulfillment === 'delivery'
                    ? 'Posted to trucking dispatch. The payment is held until a trucker delivers; the trucker is paid from it. You can cancel while no trucker has taken it.'
                    : (isStore() ? 'Collected from the supplier straight into your store stock.' : 'Waits at the supplier until it is collected (a pickup run for mechanics).');
                body.appendChild(h('div.pf-card.pf-stack', { style: { marginTop: '12px' } },
                    h('div.pfbiz-card-title', 'How it gets to you'),
                    h('div.pfbiz-chips', option('pickup', 'Collect it', true), option('delivery', delivery ? 'Trucker delivery' : 'Delivery (no delivery point yet)', delivery)),
                    h('div.pf-small.pf-muted', note),
                    h('div.pf-row.between', h('div.pfbiz-total', `Total ${money(cartTotal())}`),
                        h('button.pf-btn.primary', { onclick: checkout, disabled: S.busy }, 'Place order'))));
            }

            async function checkout() {
                if (S.busy || !S.cart.length) return;
                S.busy = true;
                const res = await ctx.rpc('create', context({ fulfillment: S.fulfillment, items: S.cart.map((l) => ({ item: l.item, quantity: l.quantity })) }));
                S.busy = false;
                if (!res || res.ok === false) { ctx.notify(err(res, 'The order was not placed.'), 'error'); if (S.tab === 'cart') show('cart'); return; }
                if (res.balance != null) S.data.balance = res.balance;
                ctx.notify(res.message || 'Order placed', 'success');
                S.cart = [];
                await loadOrders();
                show('orders');
            }

            // ── orders ──────────────────────────────────────────────────────
            function orderCard(o, finished) {
                const st = STATUS[o.status] || [String(o.status || '').replace(/_/g, ' '), ''];
                const step = stepOf(o);
                const actions = h('div.pf-row');
                if (!finished && o.status === 'ready' && o.fulfillment === 'pickup') {
                    actions.appendChild(h('button.pf-btn.sm.primary', { onclick: () => pickup(o) }, isStore() ? 'Collect into the store' : 'Collect'));
                }
                if (!finished && o.cancellable) actions.appendChild(h('button.pf-btn.sm.danger', { onclick: () => cancel(o) }, 'Cancel and refund'));
                const lines = (o.items || []).map((it) => `${num(it.quantity)}× ${it.label || it.name || it.item || ''}`).join(', ');
                return h('div.pf-card.pf-stack', { style: { gap: '6px' } },
                    h('div.pf-row.between', h('div', h('span.pf-strong', `Order #${o.id}`), h('span.pf-small.pf-muted', ` · ${when(o.createdAt)}`)), h('div.pf-strong', money(o.total))),
                    h('div.pf-row', badge(st[0], st[1]), badge(o.fulfillment === 'delivery' ? 'Trucker delivery' : 'Collect'), h('span.pf-small.pf-muted', DETAIL[o.orderStatus] || '')),
                    finished ? null : h('div.pfbiz-steps', STEPS.map(([, label], i) => h('span.pfbiz-step' + (i < step ? '.done' : (i === step ? '.now' : '')), label))),
                    lines ? h('div.pf-small.pf-muted', lines) : null,
                    actions.childNodes.length ? actions : null);
            }
            function renderOrders() {
                const active = S.orders.filter((o) => !FINISHED.includes(o.status));
                body.appendChild(active.length ? h('div.pf-stack', active.map((o) => orderCard(o, false))) : empty('No orders on the way. Place one from the shop.'));
            }
            function renderHistory() {
                const done = S.orders.filter((o) => FINISHED.includes(o.status));
                body.appendChild(done.length ? h('div.pf-stack', done.map((o) => orderCard(o, true))) : empty('Finished orders show here.'));
            }
            async function pickup(o) {
                if (S.busy) return;
                S.busy = true;
                const res = await ctx.rpc('pickup', context({ orderId: o.id }));
                S.busy = false;
                if (!res || res.ok === false) { ctx.notify(err(res, 'The order could not be collected.'), 'error'); return; }
                ctx.notify(isStore() ? 'Supplies added to your store stock' : 'Collected. Follow the pickup run if one started.', 'success');
                await loadOrders();
                show(S.tab);
            }
            async function cancel(o) {
                if (S.busy) return;
                S.busy = true;
                const res = await ctx.rpc('cancel', context({ orderId: o.id }));
                S.busy = false;
                if (!res || res.ok === false) { ctx.notify(err(res), 'error'); return; }
                if (res.balance != null) S.data.balance = res.balance;
                ctx.notify(`Order cancelled${res.data && res.data.refunded != null ? `: ${money(res.data.refunded)} refunded` : ''}`, 'success');
                await loadOrders();
                show(S.tab);
            }

            // ── delivery point ──────────────────────────────────────────────
            function renderSettings() {
                const d = S.data;
                body.appendChild(h('div.pf-card.pf-stack',
                    h('div.pfbiz-card-title', 'Delivery point'),
                    h('div.pf-small.pf-muted', isStore()
                        ? 'Store deliveries go to the store\'s own unloading point, set in the store\'s manage panel.'
                        : 'Truckers and pickup runs bring this business\'s supplies to its delivery point. Place it with a preview truck where it should park; press E to confirm.'),
                    d.deliveryAvailable ? badge('Deliveries can be made', 'ok') : badge('No delivery point yet', 'warn'),
                    isStore() ? null : h('div.pf-row', h('button.pf-btn.primary', { onclick: async () => {
                        const res = await ctx.rpc('deliveryPoint');
                        if (!res || res.ok === false) ctx.notify(err(res), 'error');
                    } }, 'Set the delivery point'))));
                body.appendChild(h('div.pf-card.pf-stack', { style: { marginTop: '12px' } },
                    h('div.pfbiz-card-title', 'How orders arrive'),
                    h('div.pf-small', '🚚 Trucker delivery: the order is posted to trucking dispatch and paid on delivery.'),
                    h('div.pf-small', '📦 Collect: a ready order is collected from the supplier (mechanics drive a pickup run with a forklift and pallets).'),
                    h('div.pf-small', '🏪 Unpacking: a delivered pallet is unpacked into the business stock.')));
            }

            // ── loading ─────────────────────────────────────────────────────
            async function loadOrders() {
                const res = await ctx.rpc('orders', context());
                if (!res || res.ok === false) return false;
                const list = Array.isArray(res.data) ? res.data : [];
                const key = JSON.stringify(list.map((o) => [o.id, o.status, o.orderStatus]));
                const changed = key !== S.ordersKey;
                S.orders = list;
                S.ordersKey = key;
                if (res.balance != null && S.data) S.data.balance = res.balance;
                return changed;
            }
            async function load() {
                body.innerHTML = '';
                body.appendChild(empty('Loading…'));
                const res = await ctx.rpc('catalog', context());
                if (!res || res.ok === false) {
                    tabs.innerHTML = '';
                    headActions.innerHTML = '';
                    body.innerHTML = '';
                    body.appendChild(empty(err(res, 'Order Supplies is not available to you.')));
                    return;
                }
                S.data = res.data || {};
                S.mode = S.data.mode || S.mode;
                S.storeId = S.data.storeId || null;
                if (!S.data.deliveryAvailable) S.fulfillment = 'pickup';
                await loadOrders();
                show(S.tab);
            }
            // orders move on their own (suppliers, truckers): look again while the app is open
            S.timers.push(setInterval(async () => {
                if (!S.data) return;
                if (await loadOrders() && (S.tab === 'orders' || S.tab === 'history')) show(S.tab);
                else renderTabs();
            }, 15000));
            ctx.on('orders', async () => { if (await loadOrders() && (S.tab === 'orders' || S.tab === 'history')) show(S.tab); else renderTabs(); });
            ctx.__os = S;
            load();
        },
        unmount(ctx) {
            const S = ctx && ctx.__os;
            if (S) S.timers.forEach(clearInterval);
        },
    });
})();
