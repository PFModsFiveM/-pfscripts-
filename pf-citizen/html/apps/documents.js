// Documents: stored on the server for the citizen, editable until signed, shared as a read-only link
// or a copy, attached to mail, signed with the signer's server identity and time.
(function () {
    const ERRORS = {
        no_title: 'Give the document a title', too_long: 'The document is too long', locked: 'Signed documents cannot be changed',
        too_many_documents: 'You have too many documents', not_found: 'That document is not available', not_owner: 'Only the owner can share a link',
        unknown_recipient: 'Nobody has that phone number or citizen id', bad_recipient: 'Enter a phone number or citizen id',
        people_only: 'Documents are shared with people', self: 'That is you', rate_limited: 'You are sharing too fast, wait a moment',
        recipient_full: 'Their documents are full', already_signed: 'You already signed this document',
    };

    function esc(s) {
        return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
    }

    // Safe formatting: the text is escaped first, then a few marks become tags.
    //   # / ## / ### heading, - list item, **bold**, *italic*, __underline__, blank line = new paragraph
    function format(text) {
        const inline = (s) => s
            .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
            .replace(/__(.+?)__/g, '<u>$1</u>')
            .replace(/\*(.+?)\*/g, '<em>$1</em>');
        const out = [];
        let para = [];
        let list = null;
        const flushPara = () => { if (para.length) { out.push('<p>' + para.map(inline).join('<br>') + '</p>'); para = []; } };
        const flushList = () => { if (list) { out.push('<ul>' + list.map((li) => '<li>' + inline(li) + '</li>').join('') + '</ul>'); list = null; } };
        esc(text).split('\n').forEach((line) => {
            const hm = line.match(/^(#{1,3})\s+(.*)$/);
            const lm = line.match(/^\s*[-•]\s+(.*)$/);
            if (hm) { flushPara(); flushList(); out.push(`<h${hm[1].length}>${inline(hm[2])}</h${hm[1].length}>`); }
            else if (lm) { flushPara(); (list = list || []).push(lm[1]); }
            else if (!line.trim()) { flushPara(); flushList(); }
            else { flushList(); para.push(line); }
        });
        flushPara(); flushList();
        return out.join('');
    }

    function when(ts) { return ts ? new Date(ts * 1000).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : ''; }

    PFApps.register('documents', {
        format,
        mount(container, ctx, params) {
            const { h } = ctx;
            const uid = 'pfcdoc' + Math.random().toString(36).slice(2, 8);
            const state = { mine: [], shared: [], current: null, editing: false, busy: false };
            const listEl = h('div');
            const mainEl = h('div.pfc-col.pfc-main-col');
            const split = h('div.pfc-split', h('div.pfc-col.pfc-list-col', h('div.pfc-search', h('button.pf-btn.primary.sm', { onclick: () => edit(null) }, '+ New document')), listEl), mainEl);
            const root = h('div.pf-app.pfc.pfc-docs',
                h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '📄'), h('div', 'Documents', h('div.pf-app-sub', 'Kept on the city servers, on every device'))),
                    h('button.pf-btn.sm', { onclick: loadList }, 'Refresh')),
                split);
            container.appendChild(root);
            const fit = () => root.classList.toggle('pfc-narrow', container.clientWidth < 760);
            if (typeof ResizeObserver !== 'undefined') { root.__ro = new ResizeObserver(fit); root.__ro.observe(container); }
            fit();

            function item(d) {
                const sub = [d.own ? null : 'from ' + d.owner, d.signatures ? `✍️ ${d.signatures} signed` : null, d.shares ? `🔗 ${d.shares}` : null, d.updated ? when(d.updated) : null].filter(Boolean).join(' · ');
                return h('div.pfc-item' + (state.current && state.current.id === d.id ? '.active' : ''), { onclick: () => open(d.id) },
                    h('div.pfc-item-title', { style: { color: 'var(--pf-fg)' } }, (d.locked ? '🔒 ' : '') + d.title), h('div.pfc-item-sub', sub));
            }

            function renderList() {
                listEl.innerHTML = '';
                listEl.appendChild(h('div.pf-small.pf-muted', { style: { padding: '8px 12px' } }, 'My documents'));
                if (!state.mine.length) listEl.appendChild(h('div.pfc-empty', 'No documents yet.'));
                state.mine.forEach((d) => listEl.appendChild(item(d)));
                if (state.shared.length) {
                    listEl.appendChild(h('div.pf-small.pf-muted', { style: { padding: '8px 12px' } }, 'Shared with me'));
                    state.shared.forEach((d) => listEl.appendChild(item(d)));
                }
            }

            function back() { return h('button.pf-btn.sm.ghost.pfc-mobile-only', { onclick: () => { split.classList.remove('reading'); state.current = null; renderList(); } }, '← Back'); }

            function renderView(doc) {
                mainEl.innerHTML = '';
                if (!doc) { mainEl.appendChild(h('div.pfc-empty', 'Open a document or write a new one.')); return; }
                const actions = h('div.pf-row', { style: { flexWrap: 'wrap' } }, back());
                if (doc.canEdit) actions.appendChild(h('button.pf-btn.sm.primary', { onclick: () => edit(doc) }, 'Edit'));
                actions.appendChild(h('button.pf-btn.sm', { onclick: () => share(doc) }, 'Share'));
                actions.appendChild(h('button.pf-btn.sm', { onclick: () => ctx.openApp('mail', { compose: { subject: doc.title, attachments: [{ type: 'document', id: doc.id, title: doc.title }] } }) }, 'Mail it'));
                if (!doc.signedByMe) actions.appendChild(h('button.pf-btn.sm', { onclick: () => sign(doc) }, '✍️ Sign'));
                actions.appendChild(h('button.pf-btn.sm.danger', { onclick: () => remove(doc) }, doc.own ? 'Delete' : 'Remove from my list'));
                const sigs = (doc.signatures || []).map((s) => h('div.pfc-sign', h('span', '✍️'),
                    h('div', h('div', h('strong', s.name), ' signed on ', when(s.at)), h('div.pfc-mono', 'SHA-256 ' + String(s.fingerprint || '').slice(0, 16) + '…'))));
                const shares = doc.own && doc.sharedWith && doc.sharedWith.length
                    ? h('div.pfc-chips', h('span.pf-small.pf-muted', 'Shared with:'), doc.sharedWith.map((p) => h('span.pfc-chip', p.name,
                        h('span.pfc-x', { title: 'Stop sharing', onclick: () => unshare(doc, p) }, '✕'))))
                    : null;
                mainEl.appendChild(h('div.pf-stack',
                    h('div.pf-row.between', { style: { flexWrap: 'wrap' } }, h('h2', { style: { margin: 0 } }, doc.title), actions),
                    h('div.pf-small.pf-muted', [doc.own ? 'Yours' : 'Owner: ' + doc.owner, 'updated ' + when(doc.updated), doc.locked ? 'locked by signature' : null, doc.copiedFrom ? 'a copy' : null].filter(Boolean).join(' · ')),
                    shares,
                    h('div.pf-card.pfc-doc-view', { html: format(doc.body) || '<p class="pf-muted">(empty)</p>' }),
                    sigs.length ? h('div.pf-stack', sigs) : null));
            }

            function edit(doc) {
                state.editing = true;
                split.classList.add('reading');
                mainEl.innerHTML = '';
                const title = h('input.pf-input', { value: doc ? doc.title : '', maxlength: 120, placeholder: 'Title' });
                const body = h('textarea.pf-textarea.pfc-editor', { maxlength: 20000, placeholder: '# Heading\n**bold**, *italic*, __underline__\n- list item' });
                body.value = doc ? doc.body : '';
                const preview = h('div.pf-card.pfc-doc-view');
                const updatePreview = () => { preview.innerHTML = format(body.value) || '<p class="pf-muted">Preview</p>'; };
                body.addEventListener('input', updatePreview);
                updatePreview();
                const save = async () => {
                    if (state.busy) return;
                    state.busy = true;
                    const res = await ctx.rpc('save', { id: doc ? doc.id : undefined, title: title.value, body: body.value });
                    state.busy = false;
                    if (!res || !res.ok) { ctx.notify(ERRORS[res && res.error] || 'Not saved', 'error'); return; }
                    ctx.notify('Saved', 'success');
                    state.editing = false;
                    await loadList();
                    open(res.id);
                };
                mainEl.appendChild(h('div.pf-stack',
                    h('div.pf-row.between', h('h3', { style: { margin: 0 } }, doc ? 'Edit document' : 'New document'),
                        h('div.pf-row', h('button.pf-btn.sm.ghost', { onclick: () => { state.editing = false; doc ? open(doc.id) : (split.classList.remove('reading'), renderView(null)); } }, 'Cancel'),
                            h('button.pf-btn.sm.primary', { onclick: save }, 'Save'))),
                    title, body, h('div.pf-small.pf-muted', 'Preview'), preview));
                title.focus();
            }

            async function loadList() {
                const res = await ctx.rpc('list');
                if (!res || !res.ok) { ctx.notify('Documents are not available right now', 'error'); return; }
                state.mine = res.mine || [];
                state.shared = res.shared || [];
                renderList();
                if (!state.current && !state.editing) renderView(null);
            }

            async function open(id) {
                const res = await ctx.rpc('get', { id });
                if (!res || !res.ok) { ctx.notify(ERRORS[res && res.error] || 'Could not open it', 'error'); return; }
                state.current = res.document;
                state.editing = false;
                split.classList.add('reading');
                renderList();
                renderView(res.document);
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

            async function sign(doc) {
                if (!window.confirm || window.confirm(`Sign "${doc.title}"? Your name and the time are stamped on it and it can no longer be edited.`)) {
                    if (await act('sign', { id: doc.id }, 'Signed')) { await loadList(); open(doc.id); }
                }
            }
            async function remove(doc) {
                if (await act('delete', { id: doc.id }, doc.own ? 'Deleted' : 'Removed')) { state.current = null; split.classList.remove('reading'); loadList(); renderView(null); }
            }
            async function unshare(doc, p) { if (await act('unshare', { id: doc.id, cid: p.cid }, 'No longer shared')) open(doc.id); }

            function share(doc) {
                const listId = uid + '-book';
                const to = h('input.pf-input', { placeholder: 'Phone number or citizen id', maxlength: 60, list: listId });
                const book = h('datalist', { id: listId });
                const mode = h('select.pf-select', doc.own ? h('option', { value: 'link' }, 'Read-only link (stays yours)') : null, h('option', { value: 'copy' }, 'A copy they own'));
                const overlay = h('div.pfc-overlay');
                const close = () => overlay.remove();
                const go = async () => {
                    const res = await act('share', { id: doc.id, to: to.value.trim(), mode: mode.value });
                    if (res) { ctx.notify(`Shared with ${res.to}`, 'success'); close(); open(doc.id); }
                };
                overlay.appendChild(h('div.pfc-dialog', h('h3', 'Share “' + doc.title + '”'),
                    h('div.pf-field', h('label', 'With'), to, book), h('div.pf-field', h('label', 'How'), mode),
                    h('div.pf-small.pf-muted', 'They get a mail with the document attached.'),
                    h('div.pfc-actions', h('button.pf-btn.ghost', { onclick: close }, 'Cancel'), h('button.pf-btn.primary', { onclick: go }, 'Share'))));
                root.appendChild(overlay);
                to.focus();
                ctx.rpc('addressBook').then((res) => {
                    ((res && res.entries) || []).filter((e) => e.kind !== 'business').forEach((e) => book.appendChild(h('option', { value: e.address }, e.name)));
                });
            }

            ctx.on('changed', loadList);
            ctx.on('params', (p) => { if (p && p.open) open(Number(p.open)); });
            loadList().then(() => { if (params && params.open) open(Number(params.open)); });
        },
        unmount(ctx) {
            const root = ctx.el && ctx.el.querySelector('.pfc-docs');
            if (root && root.__ro) root.__ro.disconnect();
        },
    });
})();
