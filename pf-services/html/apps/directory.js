// Directory: the businesses registered with City Hall and the public services on duty.
(function () {
    PFApps.register('directory', {
        mount(container, ctx) {
            const { h } = ctx;
            let data = { services: [], businesses: [] };
            let filter = '';
            const services = h('div.pf-grid');
            const list = h('div.pf-list');
            const search = h('input.pf-input', { placeholder: 'Search businesses', oninput: (e) => { filter = e.target.value.toLowerCase(); renderList(); } });
            container.appendChild(h('div.pf-app',
                h('div.pf-app-header',
                    h('div.pf-app-title', h('span.pf-icon', '🗂️'), h('div', 'Directory', h('div.pf-app-sub', 'Who is open and who is working'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                h('div.pf-app-body.pf-stack',
                    h('h3', 'Services on duty'), services,
                    h('h3', 'Businesses'), search, list)));

            function renderServices() {
                services.innerHTML = '';
                data.services.forEach((s) => services.appendChild(h('div.pf-card.pf-row.between',
                    h('div.pf-row', h('span.pfs-icon', s.icon), h('div.pf-strong', s.label)),
                    h('span.pf-badge' + (s.onDuty > 0 ? '.ok' : ''), s.onDuty > 0 ? `${s.onDuty} on duty` : 'Nobody'))));
            }

            function renderList() {
                list.innerHTML = '';
                const rows = data.businesses.filter((b) => !filter || String(b.name || '').toLowerCase().includes(filter) || String(b.type || '').toLowerCase().includes(filter));
                if (!rows.length) { list.appendChild(h('div.pf-empty', 'No businesses found.')); return; }
                rows.forEach((b) => list.appendChild(h('div.pf-list-item',
                    h('div', h('div.pf-strong', b.name), h('div.pf-small.pf-muted', [b.type, b.address].filter(Boolean).join(' · '))),
                    h('div.pf-row',
                        h('span.pf-badge' + (b.open ? '.ok' : '.bad'), b.open ? 'Open' : 'Closed'),
                        b.hasLocation ? h('button.pf-btn.sm', { onclick: () => waypoint(b) }, 'Waypoint') : null))));
            }

            async function waypoint(b) {
                const res = await ctx.rpc('waypoint', { id: b.id });
                ctx.notify(res && res.ok ? `Waypoint set to ${b.name}` : 'No location for this business', res && res.ok ? 'success' : 'error');
            }

            async function load() {
                const res = await ctx.rpc('list');
                if (res && res.ok) data = res;
                renderServices();
                renderList();
            }
            load();
        },
    });
})();
