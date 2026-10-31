// Weazel News newsroom (job reporter), the same module on the tablet and the computer: desk overview,
// leads (claim, waypoint, release), the article editor with live preview, the review queue for
// editors, published stories (pin, retract, correct) and ad moderation. Every action is checked on
// the server (pf-news/server/apps.lua); buttons only show what the server says the player may do.
(function () {
    const ERR = {
        not_authorized: 'You are not allowed to do that.',
        off_duty: 'Go on duty at the Weazel News office to take leads.',
        too_many_leads: 'You already hold the most leads you can. Finish or release one.',
        lead_taken: 'Someone else took that lead, or it expired.',
        not_yours: 'That lead is not yours.',
        no_location: 'This lead has no location.',
        title_too_short: 'The headline is too short.',
        body_too_short: 'Write a little more before publishing.',
        bad_image: 'Images must be https links to a png, jpg, gif or webp file.',
        too_many_images: 'Too many images.',
        too_many_drafts: 'You have too many drafts open. Finish or delete some.',
        lead_not_claimed: 'You can only link a lead you hold.',
        published_locked: 'Only an editor can change a published story.',
        retracted: 'A retracted story cannot be changed.',
        needs_review: 'Submit the story for review; an editor will publish it.',
        not_in_review: 'That story is not waiting for review.',
        not_published: 'That story is not published.',
        note_required: 'Write a short note.',
        too_many_pinned: 'Unpin a story first.',
        not_active: 'That is not active any more.',
        changed: 'Someone changed this meanwhile. Reload and try again.',
        not_found: 'Not found.',
        rate_limited: 'Slow down a little.',
    };
    const errText = (r) => ERR[r && r.error] || 'Something went wrong. Try again.';
    const instances = new Map();

    function loadReaderLib(ctx) {
        if (window.PFNewsUI && window.PFNewsUI.renderBody) return Promise.resolve(true);
        const base = String((ctx.app && ctx.app.entry) || '').replace(/[^/]*$/, '');
        if (!base) return Promise.resolve(false);
        return new Promise((resolve) => {
            const s = document.createElement('script');
            s.src = base + 'news_ui.js';
            s.onload = () => resolve(true);
            s.onerror = () => resolve(false);
            document.head.appendChild(s);
        });
    }

    const mod = {
        async mount(container, ctx) {
            const { h } = ctx;
            const st = { tab: 'desk', dash: null, editing: null, alive: true, timers: new Set() };
            instances.set(ctx, st);
            loadReaderLib(ctx);

            const tabs = h('div.pf-tabs.pfn-tabs');
            const body = h('div.pf-app-body.pfn-room-body');
            const sub = h('span.pf-app-sub');
            const modal = h('div.pfn-modal-slot');
            const root = h('div.pf-app.pfn.pfn-room',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '🗞️'), 'Newsroom', sub),
                    h('div.pf-row', h('button.pf-btn.sm.ghost', { onclick: () => ctx.openSite('news.ls') }, 'Open news.ls'),
                        h('button.pf-btn.sm', { onclick: () => reload() }, 'Refresh'))),
                tabs, body, modal);
            container.appendChild(root);

            const roles = () => (st.dash && st.dash.me && st.dash.me.roles) || {};
            function later(fn, ms) {
                const t = setTimeout(() => { st.timers.delete(t); if (st.alive) fn(); }, ms);
                st.timers.add(t);
            }
            async function call(method, payload, okText) {
                const r = await ctx.rpc(method, payload);
                if (!r || r.ok === false) { ctx.notify(errText(r), 'error'); return null; }
                if (okText) ctx.notify(okText, 'success');
                return r;
            }

            // A small in-app form for notes (NUI has no window.prompt).
            function askNote(title, confirmLabel, onSubmit) {
                modal.innerHTML = '';
                const input = h('textarea.pf-textarea', { rows: '3', maxlength: '300', placeholder: 'Note' });
                const close = () => { modal.innerHTML = ''; };
                modal.appendChild(h('div.pfn-modal', h('div.pf-card.pf-stack.pfn-modal-card',
                    h('div.pf-strong', title), input,
                    h('div.pf-row', h('button.pf-btn.danger', { onclick: async () => { const v = input.value.trim(); if (!v) { ctx.notify(ERR.note_required, 'error'); return; } close(); await onSubmit(v); } }, confirmLabel),
                        h('button.pf-btn.ghost', { onclick: close }, 'Cancel')))));
                input.focus();
            }

            function renderTabs() {
                tabs.innerHTML = '';
                const r = roles();
                const list = [['desk', 'Desk'], ['leads', 'Leads'], ['write', st.editing && st.editing.id ? 'Editor' : 'Write'], ['mine', 'My stories']];
                if (r.editor) list.push(['review', 'Review' + (st.dash && st.dash.review.length ? ' (' + st.dash.review.length + ')' : '')]);
                list.push(['published', 'Published'], ['ads', 'Ads']);
                list.forEach(([id, label]) => tabs.appendChild(h('button.pf-tab' + (st.tab === id ? '.active' : ''), { onclick: () => show(id) }, label)));
            }

            function badge(status) {
                const cls = { published: '.ok', covered: '.ok', active: '.ok', review: '.warn', claimed: '.accent', open: '', draft: '', retracted: '.bad', rejected: '.bad', expired: '.bad', failed: '.bad' }[status] || '';
                return h('span.pf-badge' + cls, status);
            }

            function storyRow(a, actions) {
                return h('div.pf-list-item.pfn-story',
                    h('div.pfn-story-main',
                        h('div.pf-strong', a.title),
                        h('div.pf-small.pf-muted', [a.categoryLabel, a.auto ? 'City Desk' : a.author, a.publishedAt ? ctx.timeAgo(a.publishedAt) : (a.createdAt ? 'started ' + ctx.timeAgo(a.createdAt) : null), a.views ? a.views + ' reads' : null].filter(Boolean).join(' · ')),
                        a.reviewNote ? h('div.pf-small.pfn-note', 'Editor: ' + a.reviewNote) : null,
                        a.retractNote ? h('div.pf-small.pfn-note', 'Retracted: ' + a.retractNote) : null),
                    h('div.pf-row', badge(a.status), a.breaking ? h('span.pf-badge.bad', 'breaking') : null, a.pinned ? h('span.pf-badge.accent', 'pinned') : null, actions || null));
            }

            // ── desk ────────────────────────────────────────────────
            function renderDesk() {
                const d = st.dash;
                const s = d.stats || {};
                const openLeads = d.leads.filter((l) => l.status === 'open').length;
                const stat = (label, value) => h('div.pf-card.pf-stat', h('div.pf-small.pf-muted', label), h('div.pfn-stat-value', String(value)));
                body.appendChild(h('div.pf-grid.pfn-stats',
                    stat('Open leads', openLeads), stat('My drafts', d.drafts.length), stat('In review', roles().editor ? d.review.length : d.drafts.filter((a) => a.status === 'review').length),
                    stat('Published today', s.publishedToday || 0), stat('My stories', s.myPublished || 0), stat('My reads', s.myViews || 0)));
                const dutyHint = d.me.onduty ? null : h('div.pf-card.pfn-warn', 'You are off duty. Go on duty at the Weazel News office to claim leads.');
                body.appendChild(h('div.pfn-cols',
                    h('div.pf-stack',
                        dutyHint,
                        h('div.pf-card', h('div.pf-strong', 'My leads'),
                            d.myLeads.length ? h('div.pf-list', d.myLeads.map((l) => leadRow(l))) : h('div.pf-small.pf-muted', 'No leads claimed. Take one from the Leads tab.')),
                        h('div.pf-card', h('div.pf-strong', 'My drafts'),
                            d.drafts.length ? h('div.pf-list', d.drafts.map((a) => storyRow(a, h('button.pf-btn.sm', { onclick: () => openEditor(a.id) }, 'Open')))) : h('div.pf-small.pf-muted', 'Nothing in progress.')),
                        roles().editor && d.review.length ? h('div.pf-card', h('div.pf-strong', 'Waiting for review'),
                            h('div.pf-list', d.review.map((a) => storyRow(a, h('button.pf-btn.sm.primary', { onclick: () => openEditor(a.id) }, 'Review'))))) : null),
                    h('div.pf-stack',
                        h('div.pf-card', h('div.pf-strong', 'Staff online'),
                            d.staff.length ? h('div.pf-list', d.staff.map((p) => h('div.pf-list-item',
                                h('div', h('div', p.name), h('div.pf-small.pf-muted', [p.grade, p.field ? 'out in ' + p.field : null].filter(Boolean).join(' · '))),
                                h('span.pf-badge' + (p.onduty ? '.ok' : ''), p.onduty ? 'on duty' : 'off duty')))) : h('div.pf-small.pf-muted', 'Nobody else is online.')),
                        h('div.pf-card', h('div.pf-strong', 'My bonuses'),
                            h('div.pf-small.pf-muted', 'Stories of ' + d.limits.payMinBody + '+ characters earn ' + ctx.money(d.limits.perArticle) + ' (+' + ctx.money(d.limits.leadBonus) + ' for a covered lead), paid a few minutes after publishing.'),
                            d.payouts.length ? h('div.pf-list', d.payouts.map((p) => h('div.pf-list-item', h('span', 'Story #' + p.articleId + (p.leadBonus ? ' (lead)' : '')), h('span', ctx.money(p.amount)), badge(p.state)))) : null))));
            }

            // ── leads ───────────────────────────────────────────────
            function leadRow(l) {
                const actions = [];
                if (l.status === 'open') {
                    actions.push(h('button.pf-btn.sm.primary', {
                        disabled: st.dash.requireOnDuty && !st.dash.me.onduty ? true : null,
                        title: st.dash.requireOnDuty && !st.dash.me.onduty ? ERR.off_duty : null,
                        onclick: async () => {
                            const r = await call('claimLead', { id: l.id }, 'Lead claimed');
                            if (r && r.coords) { ctx.setWaypoint(r.coords.x, r.coords.y); ctx.notify('Waypoint set to the scene', 'primary'); }
                            if (r) reload();
                        },
                    }, 'Claim'));
                }
                if (l.mine) {
                    if (l.hasLocation) actions.push(h('button.pf-btn.sm', { onclick: async () => { const r = await call('leadWaypoint', { id: l.id }); if (r && r.coords) ctx.setWaypoint(r.coords.x, r.coords.y); } }, 'Waypoint'));
                    actions.push(h('button.pf-btn.sm', { onclick: () => openEditor(null, l) }, 'Write story'));
                    actions.push(h('button.pf-btn.sm.ghost', { onclick: async () => { if (await call('releaseLead', { id: l.id }, 'Lead released')) reload(); } }, 'Release'));
                }
                if (roles().editor && (l.status === 'open' || l.status === 'claimed')) {
                    actions.push(h('button.pf-btn.sm.ghost', { onclick: async () => { if (await call('dismissLead', { id: l.id }, 'Lead dismissed')) reload(); } }, 'Dismiss'));
                }
                return h('div.pf-list-item.pfn-lead',
                    h('div.pfn-story-main',
                        h('div.pf-strong', l.title, l.hits > 1 ? h('span.pf-small.pf-muted', ' · ' + l.hits + ' reports') : null),
                        h('div.pf-small.pfn-details', l.details || ''),
                        h('div.pf-small.pf-muted', [l.claimedBy ? 'claimed by ' + l.claimedBy : null, 'came in ' + ctx.timeAgo(l.createdAt), l.hasLocation ? null : 'no location'].filter(Boolean).join(' · '))),
                    h('div.pf-row', badge(l.status), actions));
            }

            function renderLeads() {
                const leads = st.dash.leads;
                body.appendChild(h('div.pf-small.pf-muted.pfn-hint', 'Leads come from the city: crime, courts, businesses and the full story behind breaking bulletins. They are never published by themselves; claim one, go to the scene, write it up.'));
                body.appendChild(leads.length ? h('div.pf-list', leads.map(leadRow)) : h('div.pf-empty', 'No open leads right now.'));
            }

            // ── editor ──────────────────────────────────────────────
            async function openEditor(id, lead) {
                if (id) {
                    const r = await call('getArticle', { id });
                    if (!r) return;
                    st.editing = Object.assign({}, r.article, { canEdit: r.canEdit });
                } else {
                    st.editing = { id: null, title: lead ? lead.title : '', summary: '', body: '', category: lead ? lead.category : 'city', images: [], leadId: lead ? lead.id : null, breaking: false, status: 'draft', mine: true, canEdit: true };
                }
                show('write');
            }

            function renderEditor() {
                const d = st.dash;
                const a = st.editing || { id: null, title: '', summary: '', body: '', category: 'city', images: [], leadId: null, breaking: false, status: 'draft', mine: true, canEdit: true };
                st.editing = a;
                const r = roles();
                const L = d.limits;
                const ro = !a.canEdit;
                const title = h('input.pf-input', { value: a.title || '', maxlength: String(L.titleMax), placeholder: 'Headline', disabled: ro || null });
                const summary = h('input.pf-input', { value: a.summary || '', maxlength: String(L.summaryMax), placeholder: 'One-line summary (shown on the front page)', disabled: ro || null });
                const category = h('select.pf-select', { disabled: ro || null }, d.categories.map((c) => h('option', { value: c.id, selected: c.id === a.category ? true : null }, c.label)));
                const text = h('textarea.pf-textarea.pfn-editor-body', { rows: '14', maxlength: String(L.bodyMax), placeholder: 'Write the story…', disabled: ro || null });
                text.value = a.body || '';
                const imgs = [];
                for (let i = 0; i < L.images; i++) imgs.push(h('input.pf-input', { value: (a.images || [])[i] || '', placeholder: 'https://… image ' + (i + 1), maxlength: '300', disabled: ro || null }));
                const leadOpts = [h('option', { value: '' }, 'No lead')];
                const myLeads = d.myLeads.slice();
                if (a.leadId && !myLeads.some((l) => l.id === a.leadId)) myLeads.push({ id: a.leadId, title: 'Lead #' + a.leadId });
                myLeads.forEach((l) => leadOpts.push(h('option', { value: String(l.id), selected: l.id === a.leadId ? true : null }, l.title)));
                const leadSel = h('select.pf-select', { disabled: ro || !a.mine || null }, leadOpts);
                const breaking = h('input', { type: 'checkbox', checked: a.breaking ? true : null, disabled: !r.editor || null });
                const count = h('span.pf-small.pf-muted');
                const preview = h('div.pfn-preview');
                function update() {
                    count.textContent = text.value.length + ' characters' + (text.value.length < L.payMinBody ? ' (' + L.payMinBody + ' earn a bonus)' : '');
                    preview.innerHTML = '';
                    preview.appendChild(h('h2.pfn-article-title', title.value || 'Headline'));
                    if (summary.value) preview.appendChild(h('p.pfn-lead', summary.value));
                    if (window.PFNewsUI && window.PFNewsUI.renderBody) preview.appendChild(window.PFNewsUI.renderBody(h, text.value));
                    else preview.appendChild(h('div.pfn-body.pfn-pre', text.value));
                }
                [title, summary, text].forEach((el) => el.addEventListener('input', update));
                update();
                loadReaderLib(ctx).then(() => { if (st.alive && st.tab === 'write') update(); });

                const values = () => ({
                    id: a.id || undefined, title: title.value, summary: summary.value, body: text.value, category: category.value,
                    images: imgs.map((i) => i.value.trim()).filter(Boolean), leadId: leadSel.value ? Number(leadSel.value) : null, breaking: breaking.checked,
                });
                async function save(quiet) {
                    const res = await call('save', values(), quiet ? null : 'Saved');
                    if (res) { a.id = res.id; Object.assign(a, values(), { id: res.id }); }
                    return res;
                }
                const buttons = [];
                if (!ro) buttons.push(h('button.pf-btn', { onclick: async () => { if (await save()) reload(); } }, a.status === 'published' ? 'Save correction' : 'Save draft'));
                if (!ro && a.mine && a.status === 'draft') {
                    buttons.push(h('button.pf-btn.primary', {
                        onclick: async () => {
                            if (!(await save(true))) return;
                            const res = await call('submit', { id: a.id }, r.publish ? 'Published' : 'Sent to the editors');
                            if (res) { st.editing = null; show(res.status === 'published' ? 'published' : 'mine'); }
                        },
                    }, r.publish ? 'Publish' : 'Submit for review'));
                }
                if (r.editor && a.id && !a.mine && (a.status === 'review' || a.status === 'draft')) {
                    buttons.push(h('button.pf-btn.primary', {
                        onclick: async () => {
                            if (!(await save(true))) return;
                            if (await call('publish', { id: a.id }, 'Published')) { st.editing = null; show('published'); }
                        },
                    }, 'Approve and publish'));
                }
                if (r.editor && a.id && a.status === 'review') {
                    buttons.push(h('button.pf-btn.danger', { onclick: () => askNote('Send back to the author', 'Send back', async (note) => { if (await call('reject', { id: a.id, note }, 'Sent back')) { st.editing = null; show('review'); } }) }, 'Send back'));
                }
                if (a.id && a.status === 'draft' && (a.mine || r.editor)) {
                    buttons.push(h('button.pf-btn.ghost', { onclick: async () => { if (await call('delete', { id: a.id }, 'Draft deleted')) { st.editing = null; show('mine'); } } }, 'Delete draft'));
                }
                buttons.push(h('button.pf-btn.ghost', { onclick: () => { st.editing = null; show('write'); } }, 'New story'));

                body.appendChild(h('div.pfn-editor',
                    h('div.pf-stack.pfn-editor-form',
                        h('div.pf-row', badge(a.status || 'draft'), a.mine ? null : h('span.pf-small.pf-muted', 'by ' + (a.author || 'someone else')), a.reviewNote ? h('span.pf-small.pfn-note', 'Editor: ' + a.reviewNote) : null),
                        h('label.pf-field', h('span', 'Headline'), title),
                        h('label.pf-field', h('span', 'Summary'), summary),
                        h('div.pf-row', h('label.pf-field', h('span', 'Section'), category), h('label.pf-field', h('span', 'Lead'), leadSel),
                            h('label.pfn-check' + (r.editor ? '' : '.pfn-disabled'), breaking, ' Breaking news', r.editor ? null : h('span.pf-small.pf-muted', ' (editors)'))),
                        h('label.pf-field', h('span', 'Story'), text, count),
                        h('div.pf-small.pf-muted', 'Blank line = new paragraph · ## Heading · - list item · > quote · **bold** · *italic*'),
                        h('div.pf-field', h('span', 'Images (https links)'), imgs),
                        h('div.pf-row.pfn-buttons', buttons)),
                    h('div.pfn-editor-preview', h('div.pf-small.pf-muted', 'Preview'), preview)));
            }

            // ── lists ───────────────────────────────────────────────
            function renderMine() {
                const d = st.dash;
                body.appendChild(h('div.pf-card', h('div.pf-strong', 'Drafts and stories in review'),
                    d.drafts.length ? h('div.pf-list', d.drafts.map((a) => storyRow(a, h('button.pf-btn.sm', { onclick: () => openEditor(a.id) }, 'Open')))) : h('div.pf-small.pf-muted', 'Nothing in progress.')));
                body.appendChild(h('div.pf-card', h('div.pf-strong', 'Published'),
                    d.myPublished.length ? h('div.pf-list', d.myPublished.map((a) => storyRow(a))) : h('div.pf-small.pf-muted', 'Nothing published yet.')));
            }

            function renderReview() {
                const list = st.dash.review;
                body.appendChild(list.length ? h('div.pf-list', list.map((a) => storyRow(a, h('button.pf-btn.sm.primary', { onclick: () => openEditor(a.id) }, 'Review')))) : h('div.pf-empty', 'Nothing waiting for review.'));
            }

            function renderPublished() {
                const r = roles();
                const list = st.dash.recent;
                body.appendChild(list.length ? h('div.pf-list', list.map((a) => {
                    const actions = [];
                    if (r.editor && a.status === 'published') {
                        actions.push(h('button.pf-btn.sm', { onclick: () => openEditor(a.id) }, 'Correct'));
                        actions.push(h('button.pf-btn.sm', { onclick: async () => { if (await call('pin', { id: a.id, pinned: !a.pinned }, a.pinned ? 'Unpinned' : 'Pinned')) reload(); } }, a.pinned ? 'Unpin' : 'Pin'));
                        actions.push(h('button.pf-btn.sm.danger', { onclick: () => askNote('Retract “' + a.title + '”', 'Retract', async (note) => { if (await call('retract', { id: a.id, note }, 'Retracted')) reload(); }) }, 'Retract'));
                    }
                    return storyRow(a, actions);
                })) : h('div.pf-empty', 'Nothing published yet.'));
            }

            async function renderAds() {
                const res = await call('ads');
                if (!res || !st.alive || st.tab !== 'ads') return;
                body.appendChild(h('div.pf-small.pf-muted.pfn-hint', 'Businesses buy ads from the News app or news.ls. Taking an ad down refunds the business in full.'));
                if (!res.ads.length) { body.appendChild(h('div.pf-empty', 'No ads yet.')); return; }
                body.appendChild(h('div.pf-list', res.ads.map((ad) => h('div.pf-list-item.pfn-story',
                    h('div.pfn-story-main', h('div.pf-strong', ad.business), h('div', ad.text),
                        h('div.pf-small.pf-muted', [ctx.money(ad.price), ad.duration, ad.buyer ? 'bought by ' + ad.buyer : null, ad.status === 'active' ? 'ends ' + ctx.timeAgo(ad.endsAt).replace(' ago', '') : null, ad.rejectNote ? 'rejected: ' + ad.rejectNote : null].filter(Boolean).join(' · '))),
                    h('div.pf-row', badge(ad.status),
                        res.canReject && ad.status === 'active' ? h('button.pf-btn.sm.danger', { onclick: () => askNote('Take down this ad (full refund)', 'Take down', async (note) => { const r = await call('rejectAd', { id: ad.id, note }, 'Ad taken down'); if (r) show('ads'); }) }, 'Take down') : null)))));
            }

            async function show(tab) {
                st.tab = tab;
                renderTabs();
                body.innerHTML = '';
                if (!st.dash) return;
                if (tab === 'desk') renderDesk();
                else if (tab === 'leads') renderLeads();
                else if (tab === 'write') renderEditor();
                else if (tab === 'mine') renderMine();
                else if (tab === 'review') renderReview();
                else if (tab === 'published') renderPublished();
                else if (tab === 'ads') await renderAds();
            }

            async function reload() {
                const r = await ctx.rpc('dashboard');
                if (!st.alive) return;
                if (!r || r.ok === false) { body.innerHTML = ''; body.appendChild(h('div.pf-empty', errText(r))); return; }
                st.dash = r;
                sub.textContent = r.me.name + (r.me.grade ? ' · ' + r.me.grade : '') + (r.me.onduty ? ' · on duty' : ' · off duty');
                // the editor keeps what is being typed; other tabs redraw
                if (st.tab !== 'write') show(st.tab); else renderTabs();
            }

            let pending = false;
            ctx.on('refresh', () => {
                if (pending) return;
                pending = true;
                later(() => { pending = false; reload(); }, 700);
            });

            body.appendChild(h('div.pf-empty', 'Loading the newsroom…'));
            await reload();
        },
        unmount(ctx) {
            const st = instances.get(ctx);
            if (!st) return;
            st.alive = false;
            st.timers.forEach((t) => clearTimeout(t));
            instances.delete(ctx);
        },
    };

    PFApps.register('newsroom', mod);
})();
