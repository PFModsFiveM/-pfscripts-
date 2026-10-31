// Supplier: a player's supply business — offers, stock and the orders they can fill.
(function () {
    const ERRORS = {
        not_a_supplier: 'Register as a supplier first', invalid_name: 'Use letters, numbers and spaces',
        invalid_offer: 'Enter a price above 0', no_offer: 'Offer the item first', invalid_amount: 'Enter how many cases',
        missing_items: 'You do not carry that many', not_fresh_enough: 'Only fresh goods can be stocked',
        not_enough_stock: 'Not enough stock for this order (or your price is above the order price)', not_open: 'The order was taken',
    };
    PFApps.register('supplier', {
        mount(container, ctx) {
            const { h, money } = ctx;
            let busy = false;
            const body = h('div.pf-app-body.pf-stack');
            container.appendChild(h('div.pf-app',
                h('div.pf-app-header',
                    h('div.pf-app-title', h('span.pf-icon', '🚜'), h('div', 'Supplier', h('div.pf-app-sub', 'Sell to stores and restaurants'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                body));

            async function call(method, payload, okMsg) {
                if (busy) return;
                busy = true;
                const res = await ctx.rpc(method, payload);
                busy = false;
                if (!res || !res.ok) ctx.notify(ERRORS[res && res.error] || 'That did not work', 'error');
                else if (okMsg) ctx.notify(okMsg, 'success');
                load();
            }

            function renderRegister() {
                const name = h('input.pf-input', { placeholder: 'Business name, e.g. Grapeseed Farms', maxlength: 64 });
                body.appendChild(h('div.pf-card.pf-stack',
                    h('div.pf-strong', 'Start supplying'),
                    h('div.pf-small.pf-muted', 'Stores and restaurants order supplies. Registered suppliers get the order first, at their own price, before the AI wholesaler.'),
                    h('div.pf-field', h('label', 'Name'), name),
                    h('button.pf-btn.primary', { onclick: () => call('register', { name: name.value }, 'Registered') }, 'Register')));
            }

            function renderSupplier(d) {
                body.appendChild(h('div.pf-row.between', h('div.pf-strong', d.name), h('span.pf-badge' + (d.active ? '.ok' : ''), d.active ? 'Active' : 'Inactive')));

                const item = h('input.pf-input', { placeholder: 'Item name, e.g. tomato' });
                const price = h('input.pf-input', { type: 'number', min: '1', placeholder: 'Price per case' });
                body.appendChild(h('div.pf-card.pf-stack', h('div.pf-strong', 'Offer an item'),
                    h('div.pf-row', item, price, h('button.pf-btn.primary', { onclick: () => call('setOffer', { item: item.value.trim().toLowerCase(), price: Number(price.value) }, 'Offer saved') }, 'Save'))));

                const offers = h('table.pf-table', h('tr', h('th', 'Item'), h('th', 'Price'), h('th', 'Stock'), h('th', 'You carry'), h('th', '')));
                (d.offers || []).forEach((o) => {
                    const c = (d.carried || {})[o.item] || { cases: 0, items: 0, caseSize: 1 };
                    const cases = h('input.pf-input', { type: 'number', min: '1', max: String(Math.max(1, c.cases)), value: String(Math.max(1, c.cases)), style: { width: '70px' } });
                    offers.appendChild(h('tr',
                        h('td', o.label), h('td', money(o.price)), h('td', `${o.stock} cases`),
                        h('td', `${c.items} (${c.cases} cases of ${c.caseSize})`),
                        h('td', h('div.pf-row', cases, h('button.pf-btn.sm', { disabled: c.cases < 1, onclick: () => call('stock', { item: o.item, cases: Number(cases.value) }, 'Stocked') }, 'Stock')))));
                });
                body.appendChild(h('div.pf-card.pf-stack', h('div.pf-strong', 'Your offers'), (d.offers || []).length ? offers : h('div.pf-muted', 'No offers yet.')));

                const orders = h('div.pf-list');
                (d.orders || []).forEach((o) => orders.appendChild(h('div.pf-list-item',
                    h('div', h('div.pf-strong', `Order #${o.orderId}`), h('div.pf-small.pf-muted', o.lines.map((l) => `${l.quantity}× ${l.label} @ ${money(l.cost)}`).join(', '))),
                    h('button.pf-btn.sm.primary', { onclick: () => call('accept', { orderId: o.orderId }, 'Order accepted: a trucker will collect it') }, 'Fill order'))));
                body.appendChild(h('div.pf-card.pf-stack', h('div.pf-strong', 'Orders you can fill'), (d.orders || []).length ? orders : h('div.pf-muted', 'No open orders match your stock right now.')));
            }

            async function load() {
                const d = await ctx.rpc('status');
                body.innerHTML = '';
                if (!d || !d.ok) { body.appendChild(h('div.pf-empty', 'The supply service is unavailable.')); return; }
                if (!d.supplier) renderRegister(); else renderSupplier(d);
            }
            load();
        },
    });
})();
