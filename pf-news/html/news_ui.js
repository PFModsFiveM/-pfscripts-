// Weazel News reader: ONE module for the News app and the news.ls website, so both look and work
// the same on the tablet and the computer. Every server string goes into the DOM as text (ctx.h),
// never as HTML; article formatting is parsed here into elements.
//
// Server handlers (pf-news/server/apps.lua): front, list, article, search, ads, adOptions, buyAd.
// Pushes: published, updated, retracted, ads, breaking.
(function () {
    const UI = (window.PFNewsUI = window.PFNewsUI || {});

    // ── formatting: paragraphs, "## " headings, "- " lists, "> " quotes, **bold**, *italic* ──
    function inline(h, text) {
        const out = [];
        const re = /(\*\*[^*\n]+\*\*|\*[^*\n]+\*)/g;
        let last = 0;
        let m;
        while ((m = re.exec(text))) {
            if (m.index > last) out.push(text.slice(last, m.index));
            const tok = m[0];
            out.push(tok.startsWith('**') ? h('strong', tok.slice(2, -2)) : h('em', tok.slice(1, -1)));
            last = m.index + tok.length;
        }
        if (last < text.length) out.push(text.slice(last));
        return out;
    }

    function renderBody(h, text) {
        const root = h('div.pfn-body');
        String(text || '').replace(/\r/g, '').split(/\n{2,}/).forEach((block) => {
            const lines = block.split('\n').filter((l) => l.trim() !== '');
            if (!lines.length) return;
            if (lines.every((l) => /^\s*- /.test(l))) {
                root.appendChild(h('ul', lines.map((l) => h('li', inline(h, l.replace(/^\s*- /, ''))))));
            } else if (lines.length === 1 && /^## /.test(lines[0])) {
                root.appendChild(h('h3', inline(h, lines[0].slice(3))));
            } else if (lines.every((l) => /^> ?/.test(l))) {
                root.appendChild(h('blockquote', lines.map((l, i) => [i ? h('br') : null, inline(h, l.replace(/^> ?/, ''))])));
            } else {
                root.appendChild(h('p', lines.map((l, i) => [i ? h('br') : null, inline(h, l)])));
            }
        });
        return root;
    }
    UI.renderBody = renderBody;
    UI.inline = inline;

    const ERRORS = {
        not_found: 'That article is not available any more.',
        query_too_short: 'Type at least two characters.',
        not_business_owner: 'Only the owner or boss of a business can buy its ads.',
        insufficient_funds: 'The business account does not have enough money.',
        no_slots: 'All ad slots are taken right now. Try again later.',
        business_limit: 'This business already has the most ads it can run at once.',
        text_too_short: 'The ad text is too short.',
        bad_image: 'Images must be https links to a png, jpg, gif or webp file.',
        bad_duration: 'Pick how long the ad should run.',
        busy: 'Another purchase for this business is in progress.',
        payment_failed: 'The payment did not go through. Nothing was charged.',
        bank_unavailable: 'The bank is not responding. Nothing was charged.',
        news_account_missing: 'Weazel News cannot take payments right now.',
        ads_disabled: 'Ads are not available.',
        not_installed: 'Install Weazel News from the App Store.',
        rate_limited: 'Slow down a little.',
    };
    const errText = (res) => ERRORS[res && res.error] || 'Something went wrong. Try again.';
    UI.errText = errText;

    function fmtDate(ts) {
        if (!ts) return '';
        const d = new Date(ts * 1000);
        return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
    }

    function image(h, url, cls) {
        if (!url) return null;
        const img = h('img' + (cls || ''), { src: url, alt: '', loading: 'lazy', referrerpolicy: 'no-referrer' });
        img.addEventListener('error', () => { img.style.display = 'none'; });
        return img;
    }

    const instances = new Map();

    const mod = {
        async mount(container, ctx, params) {
            const { h } = ctx;
            const st = { view: 'front', front: null, canAdvertise: false, articleId: null, timers: new Set(), alive: true };
            instances.set(ctx, st);

            const nav = h('nav.pfn-nav');
            const banner = h('div.pfn-banner-slot');
            const main = h('main.pfn-main');
            const side = h('aside.pfn-side');
            const toast = h('div.pfn-toast');
            const scroll = h('div.pfn-scroll', banner, h('div.pfn-layout', main, side));
            const root = h('div.pf-app.pfn.pfn-reader',
                h('header.pfn-masthead', { onclick: () => go('front') },
                    h('div.pfn-logo', 'WEAZEL', h('span', 'NEWS')),
                    h('div.pfn-tagline', 'Los Santos, as it happens')),
                nav, scroll, toast);
            container.appendChild(root);

            function later(fn, ms) {
                const t = setTimeout(() => { st.timers.delete(t); if (st.alive) fn(); }, ms);
                st.timers.add(t);
            }
            function showToast(text) {
                toast.textContent = text;
                toast.classList.add('show');
                later(() => toast.classList.remove('show'), 4000);
            }
            let reloadPending = false;
            function reloadSoon() {
                if (reloadPending) return;
                reloadPending = true;
                later(() => { reloadPending = false; refresh(); }, 600);
            }

            function renderNav() {
                nav.innerHTML = '';
                const item = (id, label, onclick) => h('button.pfn-nav-item' + (st.view === id ? '.active' : ''), { onclick }, label);
                nav.appendChild(item('front', 'Front page', () => go('front')));
                ((st.front && st.front.categories) || []).forEach((c) => {
                    nav.appendChild(item('cat:' + c.id, c.label, () => go('category', c.id)));
                });
                nav.appendChild(item('search', '🔍 Search', () => go('search')));
                if (st.canAdvertise) nav.appendChild(item('advertise', 'Advertise', () => go('advertise')));
            }

            function renderBanner() {
                banner.innerHTML = '';
                const b = st.front && st.front.breaking && st.front.breaking[0];
                if (!b) return;
                banner.appendChild(h('div.pfn-breaking', { onclick: () => go('article', b.id) },
                    h('span.pfn-breaking-tag', 'BREAKING'), h('span.pfn-breaking-title', b.title),
                    h('span.pfn-breaking-time', ctx.timeAgo(b.publishedAt))));
            }

            function renderAds() {
                side.innerHTML = '';
                const ads = (st.front && st.front.ads) || [];
                side.appendChild(h('div.pfn-side-title', 'Local ads'));
                if (!ads.length) {
                    side.appendChild(h('div.pfn-ad.pfn-ad-empty', h('div.pf-small.pf-muted', 'Your business here.'),
                        st.canAdvertise ? h('button.pf-btn.sm', { onclick: () => go('advertise') }, 'Advertise') : null));
                    return;
                }
                ads.forEach((a) => side.appendChild(h('div.pfn-ad', image(h, a.image, '.pfn-ad-img'),
                    h('div.pfn-ad-biz', a.business), h('div.pfn-ad-text', a.text))));
            }

            function meta(a) {
                return h('div.pfn-meta',
                    h('span', a.auto ? 'City Desk' : ('By ' + (a.author || 'Weazel News'))),
                    a.publishedAt ? h('span', ctx.timeAgo(a.publishedAt)) : null,
                    a.views ? h('span', a.views + (a.views === 1 ? ' read' : ' reads')) : null);
            }

            function card(a, big) {
                return h('article.pfn-card' + (big ? '.pfn-card-big' : ''), { onclick: () => go('article', a.id) },
                    a.image ? h('div.pfn-thumb', image(h, a.image)) : null,
                    h('div.pfn-card-body',
                        h('div.pfn-kicker', a.breaking ? h('span.pfn-tag-breaking', 'Breaking') : null, a.pinned ? h('span.pfn-tag', 'Top story') : null, a.categoryLabel || a.category),
                        h('h3.pfn-card-title', a.title),
                        a.summary ? h('p.pfn-card-summary', a.summary) : null,
                        meta(a)));
            }

            function empty(text) { return h('div.pf-empty', text); }

            async function loadFront() {
                const res = await ctx.rpc('front');
                if (!st.alive) return false;
                if (!res || res.ok === false) { main.innerHTML = ''; main.appendChild(empty(errText(res))); return false; }
                st.front = res.front || {};
                st.canAdvertise = !!res.canAdvertise;
                renderNav(); renderBanner(); renderAds();
                return true;
            }

            function renderFront() {
                main.innerHTML = '';
                const f = st.front || {};
                const pinned = f.pinned || [];
                const pinnedIds = new Set(pinned.map((a) => a.id));
                const latest = (f.latest || []).filter((a) => !pinnedIds.has(a.id));
                if (!pinned.length && !latest.length) { main.appendChild(empty('No news yet. Check back soon.')); return; }
                if (pinned.length) main.appendChild(h('section.pfn-top', pinned.map((a, i) => card(a, i === 0))));
                main.appendChild(h('div.pfn-section-title', 'Latest'));
                main.appendChild(h('section.pfn-grid', latest.map((a) => card(a, false))));
            }

            async function renderCategory(id) {
                main.innerHTML = '';
                const cat = ((st.front && st.front.categories) || []).find((c) => c.id === id);
                main.appendChild(h('div.pfn-section-title', cat ? cat.label : id));
                const list = h('section.pfn-grid');
                main.appendChild(list);
                let page = 0;
                const more = h('button.pf-btn.ghost.pfn-more', { onclick: () => load() }, 'Older stories');
                async function load() {
                    const res = await ctx.rpc('list', { category: id, page });
                    if (!st.alive || st.view !== 'cat:' + id) return;
                    if (!res || res.ok === false) { list.appendChild(empty(errText(res))); return; }
                    (res.articles || []).forEach((a) => list.appendChild(card(a, false)));
                    if (!res.articles.length && page === 0) list.appendChild(empty('Nothing in this section yet.'));
                    page += 1;
                    if (res.more) main.appendChild(more); else more.remove();
                }
                await load();
            }

            async function renderArticle(id) {
                main.innerHTML = '';
                main.appendChild(h('div.pf-empty', 'Loading…'));
                const res = await ctx.rpc('article', { id });
                if (!st.alive || st.articleId !== id) return;
                main.innerHTML = '';
                const back = h('button.pf-btn.sm.ghost.pfn-back', { onclick: () => go('front') }, '← Front page');
                if (!res || res.ok === false) { main.append(back, empty(errText(res))); return; }
                const a = res.article;
                main.appendChild(h('article.pfn-article', back,
                    h('div.pfn-kicker', a.breaking ? h('span.pfn-tag-breaking', 'Breaking') : null, a.categoryLabel || a.category),
                    h('h1.pfn-article-title', a.title),
                    h('div.pfn-meta.pfn-article-meta',
                        h('span', a.auto ? 'Weazel News City Desk' : ('By ' + (a.author || 'Weazel News'))),
                        h('span', fmtDate(a.publishedAt)),
                        a.updatedAt && a.updatedAt > (a.publishedAt || 0) + 30 ? h('span', 'Updated ' + ctx.timeAgo(a.updatedAt)) : null,
                        h('span', (a.views || 0) + ' reads')),
                    (a.images || []).length ? h('div.pfn-gallery', a.images.map((u) => image(h, u))) : null,
                    a.summary ? h('p.pfn-lead', a.summary) : null,
                    renderBody(h, a.body)));
                scroll.scrollTop = 0;
            }

            function renderSearch() {
                main.innerHTML = '';
                const input = h('input.pf-input', { placeholder: 'Search the news', maxlength: '60' });
                const results = h('section.pfn-grid');
                async function run() {
                    const q = input.value.trim();
                    results.innerHTML = '';
                    const res = await ctx.rpc('search', { q });
                    if (!st.alive || st.view !== 'search') return;
                    if (!res || res.ok === false) { results.appendChild(empty(errText(res))); return; }
                    if (!res.articles.length) { results.appendChild(empty('No stories match “' + res.query + '”.')); return; }
                    res.articles.forEach((a) => results.appendChild(card(a, false)));
                }
                input.addEventListener('keydown', (e) => { if (e.key === 'Enter') run(); });
                main.append(h('div.pfn-section-title', 'Search'), h('div.pf-row.pfn-search', input, h('button.pf-btn.primary', { onclick: run }, 'Search')), results);
                input.focus();
            }

            async function renderAdvertise() {
                main.innerHTML = '';
                main.appendChild(h('div.pfn-section-title', 'Advertise with Weazel News'));
                const res = await ctx.rpc('adOptions');
                if (!st.alive || st.view !== 'advertise') return;
                if (!res || res.ok === false) { main.appendChild(empty(errText(res))); return; }
                if (!res.enabled || !(res.businesses || []).length) {
                    main.appendChild(empty('Ads are bought by the owner of a registered business or the boss of a job.'));
                    return;
                }
                const biz = h('select.pf-select', res.businesses.map((b) => h('option', { value: b.id }, b.name)));
                const dur = h('select.pf-select', res.durations.map((d) => h('option', { value: d.id }, d.label + ' — ' + ctx.money(d.price))));
                const text = h('textarea.pf-textarea', { rows: '3', maxlength: String(res.textMax || 220), placeholder: 'What should readers know?' });
                const img = h('input.pf-input', { placeholder: 'https://… image (optional)', maxlength: '300' });
                const count = h('span.pf-small.pf-muted');
                const preview = h('div.pfn-ad');
                const status = h('div.pf-small');
                function updatePreview() {
                    count.textContent = text.value.length + ' / ' + (res.textMax || 220);
                    preview.innerHTML = '';
                    const name = (res.businesses.find((b) => b.id === biz.value) || {}).name;
                    if (/^https:\/\//.test(img.value.trim())) preview.appendChild(image(h, img.value.trim(), '.pfn-ad-img'));
                    preview.append(h('div.pfn-ad-biz', name || ''), h('div.pfn-ad-text', text.value || 'Your ad text'));
                }
                [biz, text, img].forEach((el) => el.addEventListener('input', updatePreview));
                biz.addEventListener('change', updatePreview);
                const buy = h('button.pf-btn.primary', {
                    onclick: async () => {
                        buy.disabled = true;
                        status.textContent = 'Paying from the business account…';
                        const r = await ctx.rpc('buyAd', { businessId: biz.value, durationId: dur.value, text: text.value, image: img.value.trim() });
                        buy.disabled = false;
                        if (!st.alive) return;
                        if (!r || r.ok === false) { status.textContent = errText(r); ctx.notify(errText(r), 'error'); return; }
                        ctx.notify('Your ad is live on Weazel News', 'success');
                        await loadFront();
                        if (st.view === 'advertise') renderAdvertise();
                    },
                }, 'Buy ad');
                updatePreview();
                main.appendChild(h('div.pfn-adform',
                    h('div.pf-card.pf-stack',
                        h('label.pf-field', h('span', 'Business'), biz),
                        h('label.pf-field', h('span', 'Runs for'), dur),
                        h('label.pf-field', h('span', 'Text'), text, count),
                        h('label.pf-field', h('span', 'Image'), img),
                        h('div.pf-small.pf-muted', 'Paid from the business account. Weazel News may take down an ad that breaks its rules; the business then gets a full refund.'),
                        h('div.pf-row', buy, status)),
                    h('div.pfn-adpreview', h('div.pfn-side-title', 'Preview'), preview)));
                const mine = res.mine || [];
                if (mine.length) {
                    main.appendChild(h('div.pfn-section-title', 'Your ads'));
                    main.appendChild(h('table.pf-table', h('tbody', mine.map((a) => h('tr',
                        h('td', a.business), h('td', a.text),
                        h('td', h('span.pf-badge' + (a.status === 'active' ? '.ok' : a.status === 'rejected' || a.status === 'failed' ? '.bad' : ''), a.status)),
                        h('td.pf-small', a.status === 'active' ? 'until ' + fmtDate(a.endsAt) : a.status === 'rejected' ? ('refund ' + (a.refund === 'done' ? 'paid' : 'pending') + (a.rejectNote ? ' · ' + a.rejectNote : '')) : ''))))));
                }
            }

            async function go(view, arg) {
                st.view = view === 'category' ? 'cat:' + arg : view;
                st.articleId = view === 'article' ? arg : null;
                renderNav();
                if (view === 'front') { renderFront(); }
                else if (view === 'category') await renderCategory(arg);
                else if (view === 'article') await renderArticle(arg);
                else if (view === 'search') renderSearch();
                else if (view === 'advertise') await renderAdvertise();
            }

            async function refresh() {
                const ok = await loadFront();
                if (ok && st.view === 'front') renderFront();
                if (ok && st.view === 'article' && st.articleId) renderArticle(st.articleId);
            }

            ctx.on('published', (p) => { if (p && p.title) showToast((p.breaking ? 'BREAKING: ' : 'New: ') + p.title); reloadSoon(); });
            ctx.on('updated', () => reloadSoon());
            ctx.on('ads', () => reloadSoon());
            ctx.on('breaking', () => reloadSoon());
            ctx.on('retracted', (p) => {
                if (p && st.view === 'article' && st.articleId === p.id) { showToast('This story was retracted'); go('front'); }
                reloadSoon();
            });
            ctx.on('params', (p) => { if (p && p.article) go('article', Number(p.article)); });

            main.appendChild(h('div.pf-empty', 'Loading the news…'));
            if (await loadFront()) {
                if (params && params.article) go('article', Number(params.article)); else renderFront();
            }
        },
        unmount(ctx) {
            const st = instances.get(ctx);
            if (!st) return;
            st.alive = false;
            st.timers.forEach((t) => clearTimeout(t));
            instances.delete(ctx);
        },
    };

    // The same module object is the app and the website.
    PFApps.register('news', mod);
    PFApps.registerSite('news.ls', mod);
    UI.module = mod;
})();
