// Job Board (pf-computer, a pf-devices app on the tablet and the computer).
// Vacancies of real businesses. Anyone applies as their own character (name and phone come from the
// server); a business's boss or registry owner posts vacancies, reviews applicants, hires (a job offer
// the applicant accepts, a restaurant staff role, or an accepted application) and closes posts.
// "Jobs in the city" is the city's job list with how each is joined. Every action is checked on the
// server (server/jobboard.lua); the board refreshes itself when something changes (pushes).
(function () {
    const ERRORS = {
        storage_unavailable: 'The job board is not available right now.', storage_starting: 'The job board is starting, try again in a moment.',
        not_business_manager: 'Only the boss or owner of a business can post its vacancies.', missing_title: 'Give the post a title.',
        too_many_posts: 'This business already has 10 open posts.', job_not_found: 'That post is no longer open.',
        already_applied: 'You already applied for this post.', own_business: 'You cannot apply to your own business.',
        already_employed: 'You already work there.', not_authorized: 'You do not manage this business.',
        not_pending: 'That application was already answered.', invalid_grade: 'Pick a rank.', invalid_role: 'Pick a role.',
        grade_above_yours: 'You cannot hire above your own rank.', no_offer: 'There is no open offer.', offer_expired: 'The offer has expired.',
        hire_failed: 'The hire did not go through.', no_permission: 'Your role at the restaurant cannot hire.', owner_only: 'Only the owner can do that.',
        unknown_citizen: 'That character no longer exists.', unknown_restaurant: 'That restaurant is not open.',
        application_not_found: 'That application no longer exists.', already_closed: 'That post is already closed.',
        no_identifier: 'Your character could not be read.', db_error: 'The job board could not save that.', rate_limited: 'Slow down a little.',
        server_error: 'Something went wrong on the server.',
    };
    const err = (res, fallback) => (res && ERRORS[res.error]) || fallback || 'Something went wrong.';
    const APP_STATUS = {
        pending: ['Waiting', 'warn'], offered: ['Offer for you', 'accent'], hire_pending: ['Hired · starts at next sign-in', 'ok'],
        hired: ['Hired', 'ok'], accepted: ['Accepted', 'ok'], rejected: ['Not taken further', 'bad'], declined: ['Declined', ''],
        withdrawn: ['Withdrawn', ''], closed: ['Closed', ''], open: ['Open', 'ok'],
    };
    function when(ts) {
        const t = Number(ts) * (Number(ts) < 1e12 ? 1000 : 1);
        if (!t) return '';
        return new Date(t).toLocaleDateString([], { day: 'numeric', month: 'short', year: 'numeric' });
    }

    PFApps.register('jobboard', {
        mount(container, ctx) {
            const { h } = ctx;
            const S = { tab: 'vacancies', posts: [], businesses: [], query: '', category: '', applying: null, unavailable: false, busy: false, open: {} };
            const tabs = h('div.pf-tabs');
            const body = h('div.pf-app-body');
            const root = h('div.pf-app.pfbiz.pfbiz-jb',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '💼'), h('div', 'Job Board', h('div.pf-app-sub', 'Open roles across Los Santos'))),
                    h('button.pf-btn.sm', { onclick: () => refresh() }, 'Refresh')),
                tabs, body);
            container.appendChild(root);

            const empty = (text) => h('div.pf-empty', text);
            const badge = (status) => { const s = APP_STATUS[status] || [status, '']; return h('span.pf-badge' + (s[1] ? '.' + s[1] : ''), s[0]); };
            const field = (label, input) => h('div.pf-field', h('label', label), input);
            async function call(method, payload, okText) {
                if (S.busy) return null;
                S.busy = true;
                const res = await ctx.rpc(method, payload || {});
                S.busy = false;
                if (!res || res.ok === false) { ctx.notify(err(res), 'error'); return null; }
                if (okText) ctx.notify(okText, 'success');
                return res;
            }

            function renderTabs() {
                tabs.innerHTML = '';
                const list = [['vacancies', 'Vacancies'], ['city', 'Jobs in the city'], ['mine', 'My applications']];
                if (S.businesses.length) list.push(['business', 'My business']);
                list.forEach(([id, label]) => tabs.appendChild(h('div.pf-tab' + (S.tab === id ? '.active' : ''), { onclick: () => { S.tab = id; render(); } }, label)));
            }

            function render() {
                renderTabs();
                body.innerHTML = '';
                if (S.unavailable) { body.appendChild(empty(ERRORS.storage_unavailable)); return; }
                ({ vacancies: renderVacancies, city: renderCity, mine: renderMine, business: renderBusiness })[S.tab]();
            }

            // ── vacancies ───────────────────────────────────────────────────
            function postCard(p) {
                const card = h('div.pf-card.pfbiz-post',
                    h('div.pf-row.between', h('span.pf-strong', p.title), p.myApplication ? badge(p.myApplication) : null),
                    h('div.pf-small.pf-muted', [p.company, p.location, p.type, p.salary].filter(Boolean).join(' · ')),
                    p.description ? h('p.pfbiz-post-desc', p.description) : null,
                    (p.tags || []).length ? h('div.pfbiz-tagline', p.tags.map((t) => h('span.pf-badge', t))) : null,
                    h('div.pf-row.between',
                        h('span.pf-small.pf-muted', `Posted by ${p.posterName || 'staff'} · ${when(p.createdAt)}${p.hires ? (p.hireKind === 'restaurant' ? ' · joins the staff' : ' · hires into the job') : ''}`),
                        !p.isMine && !p.myApplication && S.applying !== p.id ? h('button.pf-btn.sm.primary', { onclick: () => { S.applying = p.id; render(); } }, 'Apply') : null));
                if (S.applying === p.id) {
                    const experience = h('textarea.pf-textarea', { maxlength: 1000, placeholder: 'Your experience' });
                    const message = h('textarea.pf-textarea', { maxlength: 1000, placeholder: 'A message to the employer' });
                    card.appendChild(h('div.pf-stack',
                        h('div.pf-small.pf-muted', 'You apply as your own character: the business sees your name and phone number.'),
                        experience, message,
                        h('div.pf-row', h('button.pf-btn', { onclick: () => { S.applying = null; render(); } }, 'Cancel'),
                            h('button.pf-btn.primary', { onclick: async () => {
                                const res = await call('apply', { jobId: p.id, experience: experience.value, message: message.value }, 'Application sent');
                                if (res) { S.applying = null; refresh(); }
                            } }, 'Send application'))));
                }
                return card;
            }
            function renderVacancies() {
                const cats = [...new Set(S.posts.map((p) => p.category).filter(Boolean))].sort();
                const search = h('input.pf-input', { placeholder: 'Search vacancies', value: S.query, style: { maxWidth: '260px' } });
                const chips = h('div.pfbiz-chips', [h('div.pfbiz-chip' + (!S.category ? '.active' : ''), { onclick: () => { S.category = ''; render(); } }, 'All')]
                    .concat(cats.map((c) => h('div.pfbiz-chip' + (S.category === c ? '.active' : ''), { onclick: () => { S.category = c; render(); } }, c))));
                const list = h('div.pf-stack');
                const draw = () => {
                    list.innerHTML = '';
                    const q = S.query.toLowerCase();
                    const shown = S.posts.filter((p) => (!S.category || p.category === S.category)
                        && (!q || `${p.title} ${p.company} ${p.category} ${p.location}`.toLowerCase().includes(q)));
                    if (!shown.length) list.appendChild(empty(S.posts.length ? 'Nothing matches.' : 'No open vacancies right now.'));
                    shown.forEach((p) => list.appendChild(postCard(p)));
                };
                search.addEventListener('input', () => { S.query = search.value; draw(); });
                draw();
                body.appendChild(h('div.pf-toolbar', search, chips));
                body.appendChild(list);
            }

            // ── jobs in the city ────────────────────────────────────────────
            async function renderCity() {
                body.appendChild(empty('Loading…'));
                const res = await ctx.rpc('catalog');
                if (S.tab !== 'city') return;
                body.innerHTML = '';
                const rows = res && res.ok !== false ? res.data || [] : [];
                if (!rows.length) { body.appendChild(empty('The city\'s job list is not available.')); return; }
                body.appendChild(h('div.pfbiz-table-wrap', h('table.pf-table',
                    h('thead', h('tr', h('th', 'Job'), h('th', 'How to join'), h('th', 'Vacancies'))),
                    h('tbody', rows.map((j) => h('tr', h('td', j.label),
                        h('td', j.jobCentre ? 'Anyone, at the City Hall job centre' : (j.managed ? 'Hired by the boss' : 'Hired by staff')),
                        h('td', j.openPosts > 0 ? h('span.pf-badge.ok', `${j.openPosts} open`) : (j.jobCentre ? h('span.pf-badge.ok', 'open') : h('span.pf-badge', 'none')))))))));
            }

            // ── my applications ─────────────────────────────────────────────
            async function renderMine() {
                body.appendChild(empty('Loading…'));
                const res = await ctx.rpc('myApplications');
                if (S.tab !== 'mine') return;
                body.innerHTML = '';
                const rows = res && res.ok !== false ? res.data || [] : [];
                if (!rows.length) { body.appendChild(empty('You have not applied anywhere.')); return; }
                body.appendChild(h('div.pf-stack', rows.map((a) => h('div.pf-card.pfbiz-post',
                    h('div.pf-row.between', h('span.pf-strong', a.title), badge(a.status)),
                    h('div.pf-small.pf-muted', `${a.company}${a.offerRank ? ` · offered as ${a.offerRank}` : ''} · applied ${when(a.createdAt)}`),
                    h('div.pf-row',
                        a.status === 'offered' ? h('button.pf-btn.sm.primary', { onclick: async () => {
                            const r = await call('respond', { applicationId: a.id, accept: true });
                            if (r) { ctx.notify('Welcome aboard!', 'success'); render(); }
                        } }, 'Accept the offer') : null,
                        a.status === 'offered' ? h('button.pf-btn.sm', { onclick: async () => {
                            if (await call('respond', { applicationId: a.id, accept: false }, 'Offer declined')) render();
                        } }, 'Decline') : null,
                        ['pending', 'offered', 'hire_pending'].includes(a.status) ? h('button.pf-btn.sm.danger', { onclick: async () => {
                            if (await call('withdraw', { applicationId: a.id }, 'Application withdrawn')) render();
                        } }, 'Withdraw') : null)))));
            }

            // ── my business ─────────────────────────────────────────────────
            async function renderBusiness() {
                const business = h('select.pf-select', S.businesses.map((b) => h('option', { value: b.key }, `${b.name}${b.hires ? '' : ' (accept only)'}`)));
                const titleIn = h('input.pf-input', { maxlength: 80 });
                const location = h('input.pf-input', { maxlength: 80, placeholder: 'Los Santos' });
                const salary = h('input.pf-input', { maxlength: 40, placeholder: 'Negotiable' });
                const type = h('select.pf-select', ['Full-time', 'Part-time', 'Contract'].map((t) => h('option', { value: t }, t)));
                const category = h('input.pf-input', { maxlength: 30, placeholder: 'general' });
                const tags = h('input.pf-input', { maxlength: 200, placeholder: 'comma, separated' });
                const description = h('textarea.pf-textarea', { maxlength: 2000 });
                const form = h('div.pf-card.pf-stack',
                    h('div.pfbiz-card-title', 'Post a vacancy'),
                    h('div.pfbiz-form-grid', field('Business', business), field('Title', titleIn), field('Location', location), field('Pay', salary),
                        field('Type', type), field('Category', category), h('div.pfbiz-wide', field('Tags', tags)), h('div.pfbiz-wide', field('Description', description))),
                    h('div.pf-row', h('button.pf-btn.primary', { onclick: async () => {
                        if (!titleIn.value.trim()) { ctx.notify(ERRORS.missing_title, 'error'); return; }
                        const res = await call('create', {
                            business: business.value, title: titleIn.value, location: location.value, salary: salary.value, type: type.value,
                            category: category.value, description: description.value,
                            tags: tags.value.split(',').map((t) => t.trim()).filter(Boolean).slice(0, 8),
                        }, 'Vacancy published');
                        if (res) refresh();
                    } }, 'Publish')));
                body.appendChild(form);
                const posts = h('div.pf-stack', { style: { marginTop: '12px' } }, empty('Loading…'));
                body.appendChild(h('div.pfbiz-card-title', { style: { marginTop: '14px' } }, 'Your business\'s posts'));
                body.appendChild(posts);
                const res = await ctx.rpc('myJobs');
                if (S.tab !== 'business') return;
                posts.innerHTML = '';
                const list = res && res.ok !== false ? res.data || [] : [];
                if (!list.length) { posts.appendChild(empty('No posts yet.')); return; }
                list.forEach((p) => {
                    const box = h('div.pf-stack');
                    const card = h('div.pf-card.pfbiz-post',
                        h('div.pf-row.between', h('span.pf-strong', p.title), badge(p.status)),
                        h('div.pf-small.pf-muted', `${p.company} · ${p.applicantCount} applicant(s), ${p.waiting} waiting · posted ${when(p.createdAt)}`),
                        h('div.pf-row',
                            h('button.pf-btn.sm', { onclick: () => { S.open[p.id] = !S.open[p.id]; if (S.open[p.id]) applicants(p, box); else box.innerHTML = ''; } }, 'Applicants'),
                            p.status === 'open' ? h('button.pf-btn.sm.danger', { onclick: async () => { if (await call('close', { jobId: p.id }, 'Post closed')) render(); } }, 'Close post') : null),
                        box);
                    posts.appendChild(card);
                    if (S.open[p.id]) applicants(p, box);
                });
            }

            async function applicants(p, box) {
                box.innerHTML = '';
                box.appendChild(empty('Loading…'));
                const res = await ctx.rpc('applicants', { jobId: p.id });
                box.innerHTML = '';
                if (!res || res.ok === false) { box.appendChild(empty(err(res))); return; }
                const post = res.post || {};
                const biz = S.businesses.find((b) => b.key === post.business) || {};
                const rows = res.data || [];
                if (!rows.length) { box.appendChild(empty('No applications yet.')); return; }
                rows.forEach((a) => {
                    const actions = h('div.pf-row');
                    if (a.status === 'pending') {
                        let pick = null;
                        if (post.hireKind === 'restaurant') {
                            pick = h('select.pf-select', { style: { maxWidth: '180px' } }, (biz.roles || []).map((r) => h('option', { value: r.id }, r.label)));
                        } else if (post.hires) {
                            pick = h('select.pf-select', { style: { maxWidth: '180px' } }, (biz.grades || []).map((g) => h('option', { value: g.level }, g.label)));
                        }
                        if (pick) actions.appendChild(pick);
                        actions.appendChild(h('button.pf-btn.sm.primary', { onclick: async () => {
                            const payload = { applicationId: a.id };
                            if (post.hireKind === 'restaurant') payload.role = pick && pick.value;
                            else if (pick) payload.grade = Number(pick.value);
                            const r = await call('hire', payload);
                            if (!r) return;
                            const s = r.data && r.data.status;
                            ctx.notify(s === 'offered' ? 'Offer sent: they accept it in their Job Board'
                                : s === 'hire_pending' ? 'Hired: the job starts when they next sign in'
                                    : s === 'hired' ? `Hired${r.data.rank ? ' as ' + r.data.rank : ''}` : 'Applicant accepted', 'success');
                            applicants(p, box);
                        } }, post.hires ? 'Hire' : 'Accept'));
                        actions.appendChild(h('button.pf-btn.sm.danger', { onclick: async () => { if (await call('reject', { applicationId: a.id }, 'Applicant told')) applicants(p, box); } }, 'Reject'));
                    }
                    box.appendChild(h('div.pfbiz-applicant',
                        h('div.pf-row', h('span.pf-strong', a.name), a.online ? h('span.pf-badge.ok', 'online') : null, badge(a.status), a.offerRank ? h('span.pf-small.pf-muted', `as ${a.offerRank}`) : null),
                        h('div.pf-small.pf-muted', `Phone ${a.phone || '-'} · applied ${when(a.createdAt)}`),
                        a.experience ? h('p.pfbiz-post-desc', a.experience) : null,
                        a.message ? h('p.pfbiz-post-desc', a.message) : null,
                        actions.childNodes.length ? actions : null));
                });
            }

            async function refresh() {
                const [posts, businesses] = await Promise.all([ctx.rpc('list'), ctx.rpc('businesses')]);
                S.unavailable = !posts || posts.ok === false;
                S.posts = posts && posts.ok !== false ? posts.data || [] : [];
                S.businesses = businesses && businesses.ok !== false ? businesses.data || [] : [];
                if (S.tab === 'business' && !S.businesses.length) S.tab = 'vacancies';
                render();
            }

            ctx.on('posts', () => { if (S.tab === 'vacancies' && S.applying == null) refresh(); else if (S.tab === 'business') render(); });
            ctx.on('applications', () => { if (S.tab === 'business') render(); });
            ctx.on('myApplications', () => { if (S.tab === 'mine') render(); else if (S.applying == null) refresh(); });
            refresh();
        },
    });
})();
