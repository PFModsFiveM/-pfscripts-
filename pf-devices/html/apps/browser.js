// Browser: the same city websites on every device. Sites are modules registered with
// exports['pf-devices']:RegisterSite and rendered by PFApps.mountSite inside this window.
(function () {
    PFApps.register('browser', {
        mount(container, ctx, params) {
            const { h, esc } = ctx;
            let sites = [];
            let current = null;
            const history = [];

            const address = h('input.pf-input', { placeholder: 'Type a site, e.g. news.ls', spellcheck: 'false' });
            const page = h('div.pf-browser-page');
            const bar = h('div.pf-browser-bar',
                h('button.pf-btn.sm.ghost', { title: 'Back', onclick: back }, '←'),
                h('button.pf-btn.sm.ghost', { title: 'Home', onclick: () => go(null) }, '⌂'),
                address,
                h('button.pf-btn.sm.primary', { onclick: () => go(address.value) }, 'Go'));
            const root = h('div.pf-app.pf-browser', bar, page);
            container.appendChild(root);

            address.addEventListener('keydown', (e) => { if (e.key === 'Enter') go(address.value); });

            function normalize(input) {
                return String(input || '').trim().toLowerCase().replace(/^https?:\/\//, '').replace(/\/.*$/, '');
            }

            function renderHome() {
                page.innerHTML = '';
                address.value = '';
                const list = h('div.pf-grid');
                if (!sites.length) {
                    page.appendChild(h('div.pf-empty', 'No websites are online yet.'));
                    return;
                }
                sites.forEach((s) => {
                    list.appendChild(h('div.pf-card.pf-site-tile', { onclick: () => go(s.host) },
                        h('div.pf-row', h('span', { style: { fontSize: '26px' } }, s.icon || '🌐'),
                            h('div', h('div.pf-strong', s.name), h('div.pf-small.pf-muted', s.host))),
                        s.description ? h('div.pf-small', s.description) : null));
                });
                page.appendChild(h('div.pf-app-body', h('h3', 'City websites'), list));
            }

            async function go(hostInput, fromHistory) {
                if (current) { PFApps.unmountSite(current); }
                const host = normalize(hostInput);
                if (!host) { current = null; renderHome(); return; }
                const site = sites.find((s) => s.host === host) || sites.find((s) => s.host.startsWith(host));
                page.innerHTML = '';
                if (!site) {
                    address.value = host;
                    current = null;
                    page.appendChild(h('div.pf-app-body', h('div.pf-card', h('div.pf-strong', 'This site can’t be reached'), h('div.pf-small.pf-muted', `${esc(host)} is not a known city website.`))));
                    return;
                }
                if (!fromHistory && current !== site.host) history.push(current);
                current = site.host;
                address.value = site.host;
                const mountEl = h('div.pf-site-mount');
                page.appendChild(mountEl);
                await PFApps.mountSite(site, mountEl);
            }

            function back() {
                if (!history.length) { go(null, true); return; }
                const prev = history.pop();
                go(prev, true);
            }

            ctx.on('params', (p) => { if (p && p.host) go(p.host); });

            (async () => {
                sites = await PFApps.sites();
                if (params && params.host) go(params.host); else renderHome();
            })();
        },
        unmount() {
            // sites unmount themselves through PFApps.unmountSite when the window content is dropped
        },
    });
})();
