// Mail: the citizen's one mailbox (the same mail as on the phone). Inbox, sent, drafts, trash,
// threads, reply, compose with the address book, document attachments, search.
(function () {
    const ERRORS = {
        no_recipients: 'Add at least one recipient', too_many_recipients: 'Too many recipients (at most 5)',
        unknown_recipient: 'Nobody has that address', unknown_business: 'That business is not registered',
        bad_recipient: 'That address is not valid', no_subject: 'Add a subject', no_message: 'Write a message',
        rate_limited: 'You are sending too fast, wait a moment', attachment_not_allowed: 'You cannot attach that document',
        too_many_attachments: 'At most 5 attachments', too_many_drafts: 'Too many drafts, delete some first',
        not_found: 'That mail is gone', rate: 'Slow down',
    };
    const FOLDERS = [['inbox', '📥', 'Inbox'], ['sent', '📤', 'Sent'], ['drafts', '📝', 'Drafts'], ['trash', '🗑️', 'Trash']];
    const TYPE_BADGE = { government: ['Government', 'accent'], business: ['Business', 'ok'], system: ['System', ''], person: null };

    function fmtDate(ts) {
        if (!ts) return '';
        const d = new Date(ts * 1000);
        const now = new Date();
        if (d.toDateString() === now.toDateString()) return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        return d.toLocaleDateString([], { day: 'numeric', month: 'short' }) + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    PFApps.register('mail', {
        mount(container, ctx, params) {
            const { h } = ctx;
            const uid = 'pfcmail' + Math.random().toString(36).slice(2, 8);
            const state = { folder: 'inbox', mails: [], counts: {}, search: '', selected: null, address: '', book: null, busy: false };

            const navEl = h('div.pfc-nav');
            const tabsEl = h('div.pf-tabs.pfc-tabs-narrow');
            const searchInput = h('input.pf-input', { placeholder: 'Search mail', maxlength: 60 });
            const listEl = h('div');
            const moreBtn = h('button.pf-btn.sm.ghost', { onclick: () => load(true) }, 'Older mail');
            const readerEl = h('div.pfc-col.pfc-main-col');
            const split = h('div.pfc-split', navEl,
                h('div.pfc-col.pfc-list-col', h('div.pfc-search', searchInput), listEl, h('div.pf-row', { style: { padding: '8px', justifyContent: 'center' } }, moreBtn)),
                readerEl);
            const addrEl = h('div.pf-app-sub');
            const root = h('div.pf-app.pfc.pfc-mail',
                h('div.pf-app-header',
                    h('div.pf-app-title', h('span.pf-icon', '✉️'), h('div', 'Mail', addrEl)),
                    h('div.pf-row', h('button.pf-btn.primary.sm', { onclick: () => compose({}) }, 'Compose'), h('button.pf-btn.sm', { onclick: () => load() }, 'Refresh'))),
                tabsEl, split);
            container.appendChild(root);

            // one column at a time in a small window (the tablet); the computer window may be resized
            const fit = () => root.classList.toggle('pfc-narrow', container.clientWidth < 820);
            if (typeof ResizeObserver !== 'undefined') { root.__ro = new ResizeObserver(fit); root.__ro.observe(container); }
            fit();

            let searchTimer = null;
            searchInput.addEventListener('input', () => {
                clearTimeout(searchTimer);
                searchTimer = setTimeout(() => { state.search = searchInput.value.trim(); load(); }, 300);
            });

            function renderNav() {
                navEl.innerHTML = ''; tabsEl.innerHTML = '';
                FOLDERS.forEach(([id, icon, label]) => {
                    const n = id === 'inbox' ? state.counts.unread : (id === 'drafts' ? state.counts.drafts : 0);
                    const pick = () => { state.folder = id; state.selected = null; split.classList.remove('reading'); load(); };
                    navEl.appendChild(h('div.pf-nav-item' + (state.folder === id ? '.active' : ''), { onclick: pick },
                        h('span', icon + ' ' + label), n ? h('span.pf-badge.accent', String(n)) : null));
                    tabsEl.appendChild(h('div.pf-tab' + (state.folder === id ? '.active' : ''), { onclick: pick }, label + (n ? ` (${n})` : '')));
                });
                if (state.folder === 'trash') {
                    navEl.appendChild(h('div.pf-divider'));
                    navEl.appendChild(h('button.pf-btn.sm.danger', { onclick: emptyTrash }, 'Empty trash'));
                }
            }

            function renderList() {
                listEl.innerHTML = '';
                if (!state.mails.length) {
                    listEl.appendChild(h('div.pfc-empty', state.search ? 'No mail matches your search.' : 'Nothing here.'));
                    return;
                }
                state.mails.forEach((m) => {
                    const who = state.folder === 'sent' || state.folder === 'drafts' ? ('To: ' + (m.recipients || '—')) : m.sender;
                    const el = h('div.pfc-item' + (m.read || state.folder !== 'inbox' ? '' : '.unread') + (state.selected === m.id ? '.active' : ''),
                        { onclick: () => (state.folder === 'drafts' ? openDraft(m) : open(m.id)) },
                        h('div.pfc-item-top', h('span', !m.read && state.folder === 'inbox' ? h('span.pfc-dot') : null, who), h('span', fmtDate(m.at))),
                        h('div.pfc-item-title', m.subject || '(no subject)'),
                        h('div.pfc-item-sub', (m.attachments && m.attachments.length ? '📎 ' : '') + (m.preview || '')));
                    listEl.appendChild(el);
                });
            }

            function badgeFor(type) {
                const b = TYPE_BADGE[type];
                return b ? h('span.pf-badge' + (b[1] ? '.' + b[1] : ''), b[0]) : null;
            }

            function chips(list) {
                if (!list || !list.length) return null;
                return h('div.pfc-chips', list.map((a) => h('span.pfc-chip', {
                    title: a.type === 'bill' ? 'Open in Bills' : 'Open in Documents',
                    onclick: () => (a.type === 'bill' ? ctx.openApp('bills', { focus: a.ref }) : ctx.openApp('documents', { open: Number(a.ref) })),
                }, a.type === 'bill' ? '🧾' : '📄', a.title || a.ref)));
            }

            function renderReader(data) {
                readerEl.innerHTML = '';
                if (!data) { readerEl.appendChild(h('div.pfc-empty', 'Select a mail to read it.')); return; }
                const m = data.mail;
                const actions = h('div.pf-row', { style: { flexWrap: 'wrap' } },
                    h('button.pf-btn.sm.ghost.pfc-mobile-only', { onclick: () => { split.classList.remove('reading'); state.selected = null; renderList(); } }, '← Back'));
                if (m.folder !== 'trash' && m.replyTo && !m.mine) actions.appendChild(h('button.pf-btn.sm.primary', { onclick: () => reply(m) }, 'Reply'));
                if (m.folder === 'sent') actions.appendChild(h('button.pf-btn.sm', { onclick: () => compose({ subject: 'Fwd: ' + m.subject, message: '\n\n---- Forwarded ----\n' + m.message }) }, 'Forward'));
                if (m.folder === 'inbox') actions.appendChild(h('button.pf-btn.sm', { onclick: () => markUnread(m) }, 'Mark unread'));
                if (m.folder === 'trash') actions.appendChild(h('button.pf-btn.sm', { onclick: () => restore(m) }, 'Restore'));
                actions.appendChild(h('button.pf-btn.sm.danger', { onclick: () => remove(m) }, m.folder === 'trash' ? 'Delete forever' : 'Delete'));
                const thread = (data.thread && data.thread.length > 1) ? data.thread : [m];
                readerEl.appendChild(h('div.pf-stack',
                    h('div.pf-row.between', { style: { flexWrap: 'wrap' } }, h('h3', { style: { margin: 0 } }, m.subject || '(no subject)'), actions),
                    thread.map((t) => h('div.pfc-msg' + (t.mine ? '.own' : ''),
                        h('div.pfc-msg-head',
                            h('span', h('strong', t.mine ? 'You' : t.sender), ' ', badgeFor(t.senderType), t.replyTo && !t.mine ? h('span.pf-muted', ' · ' + t.replyTo) : null),
                            h('span', fmtDate(t.at))),
                        t.recipients ? h('div.pf-small.pf-muted', { style: { marginBottom: '6px' } }, 'To: ' + t.recipients) : null,
                        h('div.pfc-body', t.message || ''),
                        chips(t.attachments)))));
            }

            async function load(more) {
                const payload = { folder: state.folder, search: state.search || undefined };
                if (more && state.mails.length) payload.before = state.mails[state.mails.length - 1].id;
                const res = await ctx.rpc('list', payload);
                if (!res || !res.ok) { ctx.notify('Mail is not available right now', 'error'); return; }
                state.mails = more ? state.mails.concat(res.mails || []) : (res.mails || []);
                state.counts = res.counts || {};
                state.address = res.address || '';
                addrEl.textContent = state.address ? 'Your address: ' + state.address : '';
                moreBtn.style.display = res.more ? '' : 'none';
                renderNav();
                renderList();
                if (!more && !state.selected) renderReader(null);
            }

            async function open(id) {
                const res = await ctx.rpc('get', { id });
                if (!res || !res.ok) { ctx.notify(ERRORS[res && res.error] || 'Could not open that mail', 'error'); return; }
                state.selected = id;
                const m = state.mails.find((x) => x.id === id);
                if (m) m.read = true;
                state.counts = res.counts || state.counts;
                split.classList.add('reading');
                renderNav(); renderList(); renderReader(res);
            }

            async function act(method, payload, okMsg) {
                if (state.busy) return null;
                state.busy = true;
                const res = await ctx.rpc(method, payload);
                state.busy = false;
                if (!res || !res.ok) { ctx.notify(ERRORS[res && res.error] || 'That did not work', 'error'); return null; }
                if (okMsg) ctx.notify(okMsg, 'success');
                return res;
            }

            async function remove(m) {
                if (await act('delete', { id: m.id }, m.folder === 'trash' ? 'Deleted' : 'Moved to trash')) {
                    state.selected = null; split.classList.remove('reading'); load();
                }
            }
            async function restore(m) { if (await act('restore', { id: m.id }, 'Restored')) { state.selected = null; split.classList.remove('reading'); load(); } }
            async function markUnread(m) { if (await act('markRead', { id: m.id, read: false })) { state.selected = null; split.classList.remove('reading'); load(); } }
            async function emptyTrash() { if (await act('emptyTrash', {}, 'Trash emptied')) load(); }

            function reply(m) {
                compose({ to: m.replyTo, subject: /^re:/i.test(m.subject) ? m.subject : 'Re: ' + m.subject, replyTo: m.id,
                    message: `\n\nOn ${fmtDate(m.at)}, ${m.sender} wrote:\n> ` + String(m.message || '').split('\n').join('\n> ') });
            }

            function openDraft(m) {
                ctx.rpc('get', { id: m.id }).then((res) => {
                    if (!res || !res.ok) return;
                    compose({ draftId: m.id, to: res.mail.recipients || '', subject: res.mail.subject === '(no subject)' ? '' : res.mail.subject,
                        message: res.mail.message, attachments: (res.mail.attachments || []).map((a) => ({ type: 'document', id: Number(a.ref), title: a.title })) });
                });
            }

            async function addressBook() {
                if (state.book) return state.book;
                const res = await ctx.rpc('addressBook');
                state.book = (res && res.ok && res.entries) || [];
                return state.book;
            }

            async function compose(init) {
                const atts = (init.attachments || []).slice(0, 5);
                const listId = uid + '-book';
                const to = h('input.pf-input', { value: init.to || '', placeholder: 'Phone number, citizen id or pick from the address book', maxlength: 380, list: listId });
                const datalist = h('datalist', { id: listId });
                const subject = h('input.pf-input', { value: init.subject || '', maxlength: 120, placeholder: 'Subject' });
                const message = h('textarea.pf-textarea', { maxlength: 4000, rows: 10, placeholder: 'Message' });
                message.value = init.message || '';
                const attEl = h('div.pfc-chips');
                const docSelect = h('select.pf-select', h('option', { value: '' }, 'Attach a document…'));
                const sendBtn = h('button.pf-btn.primary', 'Send');
                let draftId = init.draftId || null;
                const overlay = h('div.pfc-overlay');

                function renderAtts() {
                    attEl.innerHTML = '';
                    atts.forEach((a, i) => attEl.appendChild(h('span.pfc-chip', '📄 ', a.title || ('#' + a.id),
                        h('span.pfc-x', { onclick: () => { atts.splice(i, 1); renderAtts(); } }, '✕'))));
                }
                renderAtts();
                docSelect.addEventListener('change', () => {
                    const opt = docSelect.selectedOptions[0];
                    const id = Number(docSelect.value);
                    if (id && atts.length < 5 && !atts.some((a) => a.id === id)) atts.push({ type: 'document', id, title: opt.textContent });
                    docSelect.value = '';
                    renderAtts();
                });

                const close = () => overlay.remove();
                async function send() {
                    sendBtn.disabled = true;
                    const res = await ctx.rpc('send', { to: to.value, subject: subject.value, message: message.value, replyTo: init.replyTo, draftId,
                        attachments: atts.map((a) => ({ type: 'document', id: a.id })) });
                    sendBtn.disabled = false;
                    if (!res || !res.ok) {
                        const who = res && res.recipient ? ` (${res.recipient})` : '';
                        ctx.notify((ERRORS[res && res.error] || 'The mail was not sent') + who, 'error');
                        return;
                    }
                    ctx.notify('Sent', 'success');
                    close();
                    load();
                }
                async function saveDraft() {
                    const res = await ctx.rpc('saveDraft', { id: draftId, to: to.value, subject: subject.value, message: message.value,
                        attachments: atts.map((a) => ({ type: 'document', id: a.id })) });
                    if (!res || !res.ok) { ctx.notify(ERRORS[res && res.error] || 'The draft was not saved', 'error'); return; }
                    draftId = res.id;
                    ctx.notify('Draft saved', 'success');
                    if (state.folder === 'drafts') load();
                }
                sendBtn.addEventListener('click', send);
                overlay.appendChild(h('div.pfc-dialog',
                    h('h3', init.replyTo ? 'Reply' : 'New mail'),
                    h('div.pf-field', h('label', 'To (separate several with commas)'), to, datalist),
                    h('div.pf-field', h('label', 'Subject'), subject),
                    message, attEl, docSelect,
                    h('div.pfc-actions', h('button.pf-btn.ghost', { onclick: close }, 'Discard'), h('button.pf-btn', { onclick: saveDraft }, 'Save draft'), sendBtn)));
                root.appendChild(overlay);
                (init.to ? subject : to).focus();

                addressBook().then((book) => {
                    book.forEach((e) => datalist.appendChild(h('option', { value: e.address }, e.name + (e.kind === 'business' ? ' (business)' : ''))));
                });
                ctx.rpc('documents').then((res) => {
                    if (!res || !res.ok) return;
                    (res.mine || []).concat(res.shared || []).forEach((d) => docSelect.appendChild(h('option', { value: d.id }, d.title)));
                });
            }

            function handleParams(p) {
                if (p && p.compose) compose(p.compose);
                if (p && p.open) open(Number(p.open));
            }

            ctx.on('new', (m) => {
                ctx.notify(`New mail from ${m && m.sender ? m.sender : 'someone'}: ${m && m.subject ? m.subject : ''}`, 'primary');
                if (state.folder === 'inbox') load();
            });
            ctx.on('params', handleParams);
            renderReader(null);
            load().then(() => handleParams(params));
        },
        unmount(ctx) {
            const root = ctx.el && ctx.el.querySelector('.pfc-mail');
            if (root && root.__ro) root.__ro.disconnect();
        },
    });
})();
