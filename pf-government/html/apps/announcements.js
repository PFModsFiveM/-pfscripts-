// Announcements (tablet and computer): read City Hall announcements; officials with the permission
// post and withdraw them (the server decides who may).
(function () {
    const ERRORS = { no_permission: 'You may not post announcements', missing_fields: 'Write a title and a text', not_found: 'Already withdrawn' };
    const errText = (e) => ERRORS[e] || (e ? String(e).replace(/_/g, ' ') : 'That did not work');
    const PRIORITY = { urgent: '.bad', high: '.warn', normal: '.accent', low: '' };

    PFApps.register('govannouncements', {
        mount(container, ctx) {
            const { h, timeAgo } = ctx;
            const body = h('div.pf-app-body.pf-stack');
            container.appendChild(h('div.pf-app.gov-app',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '📢'), h('div', 'Announcements', h('div.pf-app-sub', 'From City Hall'))),
                    h('button.pf-btn.sm', { onclick: load }, 'Refresh')),
                body));

            function form() {
                const title = h('input.pf-input', { maxlength: '120', placeholder: 'Title' });
                const text = h('textarea.pf-textarea', { rows: '4', maxlength: '4000', placeholder: 'Announcement' });
                const priority = h('select.pf-select', ['normal', 'low', 'high', 'urgent'].map((p) => h('option', { value: p }, p)));
                const days = h('input.pf-input', { type: 'number', min: '1', max: '30', value: '7' });
                return h('div.pf-card.gov-form',
                    h('div.gov-section', 'New announcement'),
                    title, text,
                    h('div.pf-row', h('div.pf-field', h('label', 'Priority'), priority), h('div.pf-field', h('label', 'Days shown'), days)),
                    h('div.pf-row', h('button.pf-btn.primary', {
                        onclick: async () => {
                            const res = await ctx.rpc('create', { title: title.value, body: text.value, priority: priority.value, days: Number(days.value) });
                            if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                            ctx.notify('Announcement posted', 'success');
                            load();
                        },
                    }, 'Post')));
            }

            function render(list, canPost) {
                body.innerHTML = '';
                if (canPost) body.appendChild(form());
                if (!list.length) { body.appendChild(h('div.pf-empty', 'No announcements right now.')); return; }
                list.forEach((a) => body.appendChild(h('div.pf-card.pf-stack',
                    h('div.pf-row.between', h('strong', a.title), h('span.pf-badge' + (PRIORITY[a.priority] || ''), a.priority || 'normal')),
                    h('div.gov-note', a.body || ''),
                    h('div.pf-row.between', h('div.pf-small.pf-muted', [a.author, a.created ? timeAgo(a.created) : null].filter(Boolean).join(' · ')),
                        canPost ? h('button.pf-btn.sm.danger', { onclick: async () => {
                            const res = await ctx.rpc('delete', { id: a.id });
                            if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                            ctx.notify('Announcement withdrawn', 'success');
                            load();
                        } }, 'Withdraw') : null))));
            }

            async function load() {
                const res = await ctx.rpc('list');
                if (!res || !res.ok) { ctx.notify(errText(res && res.error), 'error'); return; }
                render(res.announcements || [], !!res.canPost);
            }

            load();
        },
    });
})();
