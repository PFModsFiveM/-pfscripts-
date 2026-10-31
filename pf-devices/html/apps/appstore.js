// App Store: installable apps the player may add to this device.
(function () {
    PFApps.register('appstore', {
        mount(container, ctx) {
            const { h, esc, money } = ctx;
            let data = { store: [], installed: [] };
            let busy = false;

            const body = h('div.pf-app-body');
            const root = h('div.pf-app',
                h('div.pf-app-header',
                    h('div.pf-app-title', h('span.pf-icon', '🛍️'), h('div', 'App Store', h('div.pf-app-sub', 'Apps you can add to this device'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                body);
            container.appendChild(root);

            function card(app, installed) {
                const price = app.store && app.store.price ? money(app.store.price) : 'Free';
                return h('div.pf-card.pf-stack',
                    h('div.pf-row', h('span', { style: { fontSize: '28px' } }, app.icon || '📦'),
                        h('div', h('div.pf-strong', app.name), h('div.pf-small.pf-muted', (app.store && app.store.publisher) || app.resource))),
                    h('div.pf-small', (app.store && app.store.description) || app.description || ''),
                    h('div.pf-row.between',
                        h('span.pf-badge' + (installed ? '.ok' : '.accent'), installed ? 'Installed' : price),
                        installed
                            ? h('button.pf-btn.sm.danger', { onclick: () => act('uninstall', app) }, 'Remove')
                            : h('button.pf-btn.sm.primary', { onclick: () => act('install', app) }, 'Install')));
            }

            function render() {
                body.innerHTML = '';
                if (!data.store.length && !data.installed.length) {
                    body.appendChild(h('div.pf-empty', 'No installable apps are available to you right now.'));
                    return;
                }
                if (data.store.length) {
                    body.appendChild(h('h3', 'Available'));
                    body.appendChild(h('div.pf-grid', data.store.map((a) => card(a, false))));
                }
                if (data.installed.length) {
                    body.appendChild(h('h3', { style: { marginTop: '18px' } }, 'Installed'));
                    body.appendChild(h('div.pf-grid', data.installed.map((a) => card(a, true))));
                }
            }

            async function load() {
                const res = await ctx.rpc('list', { device: ctx.device });
                data = { store: (res && res.store) || [], installed: (res && res.installed) || [] };
                render();
            }

            async function act(method, app) {
                if (busy) return;
                busy = true;
                const res = await ctx.rpc(method, { app: app.id });
                busy = false;
                if (!res || !res.ok) {
                    const reasons = { payment_failed: 'Payment failed', banking_down: 'The bank is unavailable', not_authorized: 'You cannot use this app', busy: 'Try again in a moment' };
                    ctx.notify(reasons[res && res.error] || 'That did not work', 'error');
                } else {
                    ctx.notify(method === 'install' ? `${app.name} installed` : `${app.name} removed`, 'success');
                }
                await load();
            }

            load();
        },
    });
})();
